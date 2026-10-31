"""Keys the driver's hand gestures on a car's wheel buttons and panel switches (Config/DriverGestures)
from measured inputs, and writes the car's Gestures.luau and the dense samples the check and the
renders read.

  python tools/anim/gesture_paths.py <inputs.json> <out dir> [--write <Gestures.luau>]

inputs.json names the grip (hands.json: the right hand's wrist, forearm and back in the wheel's
frame, studs, and its grip angle), the thumb presses (thumb_press.py's thumbs.json after
thumb_check.py --pick, and the meshes beside it), the posed hands (hand_poses.py's poses.json),
the car as gesture_config.luau prints it (hub, knob, toggles, drive modes), the cabin dump the
thumbs were solved on, the driver's arms (shoulders, bone lengths, elbow bias; studs in the seat
frame) and per gesture its control, side and shape of path:

- "thumb": the grip slides round the rim and rolls over it (thumbs.json's slide and roll for that
  button) on a smooth curve, keyed every KEY_STEP, loosening off the rim by up to "slideLift"
  (metres, out along the radius) half way so the fingers do not drag through it, then the thumb's
  mesh shows;
- "regrip": the hand opens (Rest), lifts off the rim ("liftOff"), goes round past the spoke to the
  button's slide and roll, and comes back onto the rim ("comeOn"), closing with the thumb on the
  button;
- "toggle": the Point hand leaves the grip, reaches the toggle's lever and pushes its end through
  the binding's travel as the game turns it (one track per state, Off and On); the seat frame,
  blended onto the live grip at both ends;
- "knob": a finger pushes the drive-mode knob's lever from each mode to the next while the thumb
  rests on the rim (one track per mode).

A track's keys run from the grip to the pose held while the input is held. Every frame is the
wrist frame the game moves (z up the forearm, y out of the back of the hand), metres.
"""

import json
import math
import os
import sys

import numpy as np

STUDS = 1.5 / 0.28
KEY_STEP = 1 / 60
# How far past the arm's reach a wrist may be asked to go, as in startup_paths.py.
REACH_SHARE = 0.96
# The index's end sits on the finger's centre line: this far behind the lever's end puts the finger
# on it (startup_sequence.py's FINGER_UNDER).
FINGER_UNDER = 0.006
RIDE_STEP = 0.025
# The thumb's pad rests this far off the rim's surface while a finger works the knob.
PAD_REST = 0.0005


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


def rotation(axis, angle):
    x, y, z = unit(axis)
    c, s, k = math.cos(angle), math.sin(angle), 1 - math.cos(angle)
    return np.array(
        [
            [c + x * x * k, x * y * k - z * s, x * z * k + y * s],
            [y * x * k + z * s, c + y * y * k, y * z * k - x * s],
            [z * x * k - y * s, z * y * k + x * s, c + z * z * k],
        ]
    )


def matrix_quat(m):
    """(w, x, y, z) of a rotation matrix, w >= 0."""
    t = np.trace(m)
    if t > 0:
        s = math.sqrt(t + 1) * 2
        q = [0.25 * s, (m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = math.sqrt(1 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [(m[2, 1] - m[1, 2]) / s, 0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s]
    elif m[1, 1] > m[2, 2]:
        s = math.sqrt(1 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 2] - m[2, 0]) / s, (m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s]
    else:
        s = math.sqrt(1 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[1, 0] - m[0, 1]) / s, (m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s]
    q = np.array(q)
    q /= np.linalg.norm(q)
    return q if q[0] >= 0 else -q


def quat_matrix(q):
    w, x, y, z = q
    return np.array(
        [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
    )


class Frame:
    """A wrist frame: rotation (columns x, y, z) and position, metres."""

    def __init__(self, rot, pos):
        self.rot = np.asarray(rot, float)
        self.pos = np.asarray(pos, float)

    @staticmethod
    def grip(wrist_studs, forearm, back):
        # As Rig/StartupHands.gripWrist builds it.
        z = unit(forearm)
        y = unit(np.asarray(back, float) - z * (np.asarray(back, float) @ z))
        return Frame(np.stack([np.cross(y, z), y, z], 1), np.asarray(wrist_studs, float) / STUDS)

    def moved(self, rot, about=None, shift=None):
        """Turned by `rot` about the point `about`, then shifted."""
        about = np.zeros(3) if about is None else np.asarray(about, float)
        pos = rot @ (self.pos - about) + about
        if shift is not None:
            pos = pos + shift
        return Frame(rot @ self.rot, pos)

    def apply(self, local):
        return self.rot @ np.asarray(local, float) + self.pos

    def key(self, t):
        q = matrix_quat(self.rot)
        return [round(t, 4)] + [round(float(c), 5) for c in self.pos] + [round(float(c), 6) for c in q]


def smooth(s):
    s = min(1.0, max(0.0, s))
    return s * s * (3 - 2 * s)


def mirror_frame(frame):
    """The left hand's frame from the right hand's, as hands.json mirrors the grip: positions and
    the forearm and back directions mirrored in x, the frame rebuilt from them."""
    flip = np.array([-1.0, 1.0, 1.0])
    z = frame.rot[:, 2] * flip
    y = frame.rot[:, 1] * flip
    return Frame(np.stack([np.cross(y, z), y, z], 1), frame.pos * flip)


def wheel_axes(config):
    hub = config["steeringHub"]
    z = unit(hub["axis"])
    x = np.array([1.0, 0, 0])
    x = unit(x - z * (x @ z))
    return np.stack([x, np.cross(z, x), z], 1), np.array(hub["pivot"], float) + np.array([0, config.get("steeringWheelLift", 0), 0])


def cabin_in(inputs, axes=None, centre=None):
    """The cabin dump in the seat frame (or the wheel's, given its axes and centre), metres."""
    data = np.load(inputs["cabin"])
    rel = data["vertices"].astype(float) - np.array(inputs["seat"])
    seat = np.stack([-rel[:, 0], rel[:, 2], rel[:, 1]], 1)
    points = seat if axes is None else (seat - centre) @ axes
    return points, data["triangles"], data["object"], list(data["names"])


def part_points(cabin, name):
    points, tris, owner, names = cabin
    return points[np.unique(tris[owner == names.index(name)])]


class Rim:
    """The right grip's rim tube, as thumb_press.py measures it: the centre of the rim's points
    within 3 degrees of the grip's angle, and the tube's tangent there."""

    def __init__(self, wheel_cabin, grip_angle_deg):
        rim = part_points(wheel_cabin, "SteeringWheel_Rim")
        angle = math.radians(grip_angle_deg)
        polar = np.arctan2(rim[:, 1], rim[:, 0])
        self.tube = rim[np.abs(polar - angle) < math.radians(3)].mean(0)
        self.tangent = np.array([-math.sin(angle), math.cos(angle), 0.0])
        self.radial = np.array([math.cos(angle), math.sin(angle), 0.0])

    def slid(self, frame, slide_deg, roll_deg, lift=(0.0, 0.0), lift_roll_deg=0.0):
        """The right grip's frame rolled over the tube, lifted off it (out along the radius and
        toward the driver, metres) and slid round the wheel's axis: thumb_press.py's
        Rz(slide) @ roll(tube tangent) @ grip, plus the lift."""
        rolled = frame.moved(rotation(self.tangent, math.radians(roll_deg + lift_roll_deg)), self.tube)
        lifted = Frame(rolled.rot, rolled.pos + self.radial * lift[0] + np.array([0, 0, 1.0]) * lift[1])
        return lifted.moved(rotation([0, 0, 1], math.radians(slide_deg)))


def thumb_track(gesture, button, grip_r, rim, side):
    """The grip sliding and rolling to the button's pose on a smooth curve, then the thumb."""
    slide, roll = button["slideDeg"], button["rollDeg"]
    travel = gesture.get("travel", 0.15 if (slide or roll) else 0.0)
    press = gesture.get("press", 0.04)
    frames = []
    steps = max(1, int(round(travel / KEY_STEP)))
    loosen = gesture.get("slideLift", 0.0)
    for i in range(steps + 1):
        s = smooth(i / steps) if travel > 0 else 1.0
        f = rim.slid(grip_r, slide * s, roll * s, (loosen * math.sin(math.pi * i / steps), 0.0))
        frames.append((travel * i / steps, f if side > 0 else mirror_frame(f)))
    if travel <= 0:
        # The thumb alone moves: the wrist holds the grip for the press's time.
        frames = [(0.0, frames[0][1]), (press, frames[0][1])]
        return frames, [{"at": 0, "shape": "Grip"}, {"at": round(press * 0.5, 4), "shape": gesture["mesh"]}]
    # No key after the last: the game's cubic would carry the slide past it and back.
    return frames, [{"at": 0, "shape": "Grip"}, {"at": round(travel - KEY_STEP, 4), "shape": gesture["mesh"]}]


def regrip_track(gesture, button, grip_r, rim, side):
    """Open, lift off the rim, round past the spoke to the button's slide and roll, close. The way
    off ("liftOff"), round ("round") and on ("comeOn") are each [out along the radius, toward the
    driver] in metres and a roll over the tube in degrees, relative to the hand's place on the
    rim, eased from one to the next. A fourth number on the way off turns the hand round the
    wheel's axis as it lifts (degrees, signed as the slides are in the right hand's frame: positive
    up the rim), to keep clear of what is beside the grip."""
    slide, roll = button["slideDeg"], button["rollDeg"]
    off, mid, on = gesture["liftOff"], gesture["round"], gesture["comeOn"]
    early_slide = off[3] if len(off) > 3 else 0.0
    t_lift, t_round, t_on = gesture.get("times", (0.08, 0.30, 0.38))
    t_mid = (t_lift + t_round) / 2

    def blend(a, b, w):
        return [a[k] * (1 - w) + b[k] * w for k in range(3)]

    frames = []
    t = 0.0
    zero = [0.0, 0.0, 0.0]
    while t < t_on + 1e-9:
        if t <= t_lift:
            a, lift = 0.0, blend(zero, off, smooth(t / t_lift))
        elif t <= t_round:
            a = smooth((t - t_lift) / (t_round - t_lift))
            lift = blend(off, mid, smooth((t - t_lift) / (t_mid - t_lift))) if t <= t_mid else blend(mid, on, smooth((t - t_mid) / (t_round - t_mid)))
        else:
            a, lift = 1.0, blend(on, zero, smooth((t - t_round) / (t_on - t_round)))
        early = early_slide * (1 - a) * (smooth(t / t_lift) if t <= t_lift else 1.0)
        f = rim.slid(grip_r, slide * a + early, roll * a, (lift[0], lift[1]), lift[2])
        frames.append((t, f if side > 0 else mirror_frame(f)))
        t = round(t + KEY_STEP, 6)
    if abs(frames[-1][0] - t_on) > 1e-6:
        f = rim.slid(grip_r, slide, roll)
        frames.append((t_on, f if side > 0 else mirror_frame(f)))
    open_at, close_at = gesture.get("openAt", 0.03), t_on - gesture.get("closeLead", 0.01)
    shapes = [{"at": 0, "shape": "Grip"}, {"at": open_at, "shape": "Rest"}, {"at": round(close_at, 4), "shape": gesture["mesh"]}]
    return frames, shapes


class Arm:
    """The arm controller's right or left arm in the seat frame, metres (inputs' driver block)."""

    def __init__(self, driver, sign):
        side = "R" if sign > 0 else "L"
        self.sign = sign
        self.shoulder = np.array(driver["shoulders"][side], float) / STUDS
        self.upper, self.lower = driver["upper"] / STUDS, driver["lower"] / STUDS
        self.bias = np.array(driver["elbowBias"], float)

    def elbow(self, wrist, along):
        to_wrist = wrist - self.shoulder
        distance = min(max(np.linalg.norm(to_wrist), abs(self.upper - self.lower) + 1e-6), self.upper + self.lower - 1e-6)
        bend = math.acos(max(-1, min(1, (self.upper**2 + distance**2 - self.lower**2) / (2 * self.upper * distance))))
        pole = unit(wrist + along * self.lower - self.shoulder) + np.array([self.sign * self.bias[0], self.bias[1], self.bias[2]])
        u = unit(to_wrist)
        out = unit(pole - u * (pole @ u))
        return self.shoulder + u * (self.upper * math.cos(bend)) + out * (self.upper * math.sin(bend))

    def reach_share(self, wrist):
        return np.linalg.norm(wrist - self.shoulder) / (self.upper + self.lower)

    def aimed(self, target, tip, roll, aim_from=(0, 0, 0), up=(0, 1, 0)):
        """startup_paths.aimed: the Point hand whose index end lands on `target`, in line with the
        forearm the controller would draw (the hand's axis set from the elbow, four passes)."""
        shoulder = self.shoulder + np.asarray(aim_from, float)
        up = np.asarray(up, float)
        z = unit(shoulder - target)
        rot = None
        for _ in range(4):
            y = unit(up - z * (up @ z))
            rot = np.stack([np.cross(y, z), y, z], 1) @ rotation([0, 0, 1], roll)
            wrist = target - rot @ tip
            joint = self.elbow(wrist, z)
            z = unit(z + unit(joint - wrist))
        return Frame(rot, target - rot @ tip)


def to_seat(frame, axes, centre):
    return Frame(axes @ frame.rot, axes @ frame.pos + centre)


def lever_tip(cabin_seat, hinge):
    """The lever's end (the vertices farthest from the pivot) of a toggle in the dump's pose."""
    points = part_points(cabin_seat, hinge["part"])
    far = np.linalg.norm(points - hinge["pivot"], axis=1)
    return points[far > far.max() - 0.002].mean(0)


def toggle_track(gesture, config, cabin_seat, grip_seat, arm, tip, state, axes):
    """The Point hand from the grip to the toggle's lever, its end riding behind the lever's end as
    the game turns it from `state` to the other, then held there. Seat frame."""
    hinge = config["controls"][gesture["control_part"]]
    pivot, axis = np.array(hinge["pivot"], float), unit(hinge["axis"])
    rest, travel = hinge["rest"], hinge["travel"]
    # The dump has the lever in its modelled pose; the game rests it at `rest`, on is rest + travel.
    modelled = lever_tip(cabin_seat, hinge)
    start_angle = rest + (travel if state == "On" else 0.0)
    end_angle = rest + (0.0 if state == "On" else travel)
    turn = end_angle - start_angle
    p = gesture["phases"]
    t_open, t_reach, t_touch, t_move = p["open"], p["reach"], p["touch"], p["move"]

    def contact(share):
        angle = start_angle + turn * smooth(share)
        end = rotation(axis, angle) @ (modelled - pivot) + pivot
        arm_vec = end - pivot
        motion = unit(np.cross(axis, arm_vec) * (1 if turn >= 0 else -1))
        return end - motion * gesture.get("under", FINGER_UNDER)

    roll = math.radians(gesture.get("rollDeg", -10))
    aim_from = np.array(gesture.get("aimFrom", (0, 0, 0)), float) / STUDS
    approach = np.array(gesture.get("approach", (0, -0.02, 0.03)), float)
    frames = [(0.0, grip_seat)]
    # Off the rim the way the start-up comes onto it (startup_sequence.py's RIM_APPROACH): out
    # along the wheel's x and toward the driver, in the wheel's frame.
    off = Frame(grip_seat.rot, grip_seat.pos + axes @ np.array(gesture.get("offRim", (0.04, 0.0, 0.03)), float))
    frames.append((t_open, off))
    frames.append((t_reach, arm.aimed(contact(0) + approach, tip, roll, aim_from)))
    t = t_touch
    end_t = t_touch + t_move
    while t < end_t + 1e-9:
        share = (t - t_touch) / t_move
        frames.append((round(t, 4), arm.aimed(contact(share), tip, roll, aim_from)))
        t = round(t + RIDE_STEP, 6)
    if abs(frames[-1][0] - end_t) > 1e-6:
        frames.append((round(end_t, 4), arm.aimed(contact(1.0), tip, roll, aim_from)))
    shapes = [
        {"at": 0, "shape": "Grip"},
        {"at": gesture.get("openAt", 0.03), "shape": "Rest"},
        {"at": round((t_open + t_reach) / 2, 4), "shape": "Point"},
    ]
    reach = max(arm.reach_share(f.pos) for _, f in frames)
    return frames, shapes, {"start": round(t_touch, 4), "finish": round(end_t, 4)}, contact, reach, (start_angle, end_angle)


class Knob:
    """The drive-mode knob's lever in the wheel's frame: its pivot and axis (the binding's), its
    direction at its modelled pose (OFF) in the wheel's face, its length to the red tip and the top
    of its fin. Positions are angles from the modelled pose."""

    def __init__(self, config, wheel_cabin, axes, centre):
        hinge = config["modeKnob"]["hinge"]
        self.positions = config["modeKnob"]["positions"]
        self.rest = hinge.get("rest", 0)
        self.part = hinge["part"]
        self.pivot = (np.array(hinge["pivot"], float) - centre) @ axes
        self.axis = unit(axes.T @ np.array(hinge["axis"], float))
        tip = part_points(wheel_cabin, hinge["part"] + "_Tip").mean(0)
        along = tip - self.pivot
        along -= self.axis * (along @ self.axis)
        self.length = float(np.linalg.norm(along))
        self.up = along / self.length
        self.top = float(part_points(wheel_cabin, hinge["part"])[:, 2].max())

    def contact(self, angle, sense, along=0.8, under=FINGER_UNDER, depth=0.004):
        """Where the index's end pushes the lever turned to `angle`: `along` its length, just under
        its fin's top, FINGER_UNDER behind it against the turn (`sense` +1 turns it positively)."""
        u = rotation(self.axis, angle) @ self.up
        point = self.pivot + u * self.length * along
        point = point - self.axis * ((point - self.pivot) @ self.axis) + self.axis * (self.top - depth - self.pivot @ self.axis)
        motion = unit(np.cross(self.axis, u)) * sense
        return point - motion * under


def knob_reference(gesture, knob, arm, tip, axes, centre):
    """The Point-fingered hand with its index end on the lever at OFF, pushing toward 1, aimed as the
    arm controller would hold it (the seat frame's aim, turned into the wheel's frame)."""
    target = axes @ knob.contact(0.0, 1) + centre
    roll = math.radians(gesture.get("rollDeg", 0))
    aim_from = np.array(gesture.get("aimFrom", (0, 0, 0)), float) / STUDS
    seat = arm.aimed(target, tip, roll, aim_from)
    return Frame(axes.T @ seat.rot, axes.T @ (seat.pos - centre))


def knob_frame(reference, finger, pad, target, rim=None):
    """The reference frame turned about the thumb's pad (round the wheel's axis) to point the index
    at `target`, then moved across the rim's face by what the finger's length leaves, so the
    index's end lands on it, and tipped about the index's end until the thumb's pad rests on the
    rim's surface again (`rim`: its surface samples and normals, wheel frame), since the tube's
    face curves under the moved pad. Returns the frame and how far the pad moved (metres)."""
    p = reference.apply(pad)
    v = reference.apply(finger) - p
    want = target - p
    phi = math.atan2(want[1], want[0]) - math.atan2(v[1], v[0])
    phi = (phi + math.pi) % (2 * math.pi) - math.pi
    turned = rotation([0, 0, 1], phi) @ v
    shift = want - turned
    shift[2] = 0.0
    frame = reference.moved(rotation([0, 0, 1], phi), p, shift)
    if rim is not None:
        points, normals = rim
        tip = frame.apply(finger)

        def rest_gap(psi):
            axis = np.cross([0, 0, 1.0], frame.apply(pad) - tip)
            moved = frame.moved(rotation(axis, psi), tip)
            q = moved.apply(pad)
            k = int(np.argmin(np.linalg.norm(points - q, axis=1)))
            return float((q - points[k]) @ normals[k]) - PAD_REST, moved

        lo, hi = -0.25, 0.25
        if rest_gap(lo)[0] * rest_gap(hi)[0] < 0:
            for _ in range(40):
                mid = (lo + hi) / 2
                if rest_gap(lo)[0] * rest_gap(mid)[0] <= 0:
                    hi = mid
                else:
                    lo = mid
            frame = rest_gap((lo + hi) / 2)[1]
    return frame, float(np.linalg.norm(shift))


def knob_track(gesture, knob, reference, finger, pad, grip_r, axes, state, order, rim=None):
    """The finger from the grip onto the knob's lever at `state`'s position, pushing it to the next
    mode's while the thumb stays on the rim; the wheel's frame."""
    to = order[(order.index(state) + 1) % len(order)]
    a0, a1 = knob.positions[state] - knob.rest, knob.positions[to] - knob.rest
    sense = 1 if a1 >= a0 else -1
    p = gesture["phases"]
    t_open, t_reach, t_touch, t_move = p["open"], p["reach"], p["touch"], p["move"] * abs(a1 - a0) / 0.785
    frames = [(0.0, grip_r)]
    frames.append((t_open, Frame(grip_r.rot, grip_r.pos + np.array(gesture.get("offRim", (0.04, 0.0, 0.03)), float))))
    under, along = gesture.get("under", FINGER_UNDER), gesture.get("along", 0.8)
    # Turned round the wheel's centre the thumb stays on the (round) rim: a track may start from the
    # reference moved along it, so the finger comes at the lever from another side.
    orbit = gesture.get("orbitDeg", {}).get(state, 0.0)
    reference = reference.moved(rotation([0, 0, 1], math.radians(orbit)))

    def contact(angle):
        return knob.contact(angle, sense, along=along, under=under)

    start, _ = knob_frame(reference, finger, pad, contact(a0), rim)
    hover = Frame(start.rot, start.pos + np.array(gesture.get("hover", (0.0, 0.0, 0.025)), float))
    # Over the rim between the way off it and the hover, clear of the tube.
    if "over" in gesture:
        over = Frame(hover.rot, (frames[-1][1].pos + hover.pos) / 2 + np.array(gesture["over"], float))
        frames.append(((t_open + t_reach) / 2, over))
    frames.append((t_reach, hover))
    slides = []
    t = t_touch
    end_t = t_touch + t_move
    while t < end_t + 1e-9:
        share = (t - t_touch) / t_move
        f, slide = knob_frame(reference, finger, pad, contact(a0 + (a1 - a0) * smooth(share)), rim)
        frames.append((round(t, 4), f))
        slides.append(slide)
        t = round(t + RIDE_STEP, 6)
    if abs(frames[-1][0] - end_t) > 1e-6:
        f, slide = knob_frame(reference, finger, pad, contact(a1), rim)
        frames.append((round(end_t, 4), f))
        slides.append(slide)
    shapes = [
        {"at": 0, "shape": "Grip"},
        {"at": gesture.get("openAt", 0.04), "shape": "Rest"},
        {"at": round(gesture.get("meshAt", (t_open + t_reach) / 2), 4), "shape": gesture["mesh"]},
    ]
    turn = {"control": knob.part, "start": round(t_touch, 4), "finish": round(end_t, 4)}
    return frames, shapes, turn, (a0, a1, sense), slides


def sample(keys, t):
    """Rules/StartupArms.sample: positions on a cubic through every key (Catmull-Rom slopes over
    uneven spans), rotations turned evenly between keys."""
    if t <= keys[0][0]:
        k = keys[0]
        return np.array(k[1:4]), np.array(k[4:8])
    if t >= keys[-1][0]:
        k = keys[-1]
        return np.array(k[1:4]), np.array(k[4:8])
    i = 0
    while keys[i + 1][0] <= t:
        i += 1
    a, b = keys[i], keys[i + 1]
    span = b[0] - a[0]
    s = (t - a[0]) / span

    def slope(j, axis):
        before, after = keys[max(j - 1, 0)], keys[min(j + 1, len(keys) - 1)]
        width = after[0] - before[0]
        return (after[axis] - before[axis]) / width if width > 0 else 0.0

    h00, h10, h01, h11 = 2 * s**3 - 3 * s**2 + 1, s**3 - 2 * s**2 + s, -2 * s**3 + 3 * s**2, s**3 - s**2
    pos = np.array([h00 * a[ax] + h10 * span * slope(i, ax) + h01 * b[ax] + h11 * span * slope(i + 1, ax) for ax in (1, 2, 3)])
    qa, qb = np.array(a[4:8]), np.array(b[4:8])
    if qa @ qb < 0:
        qb = -qb
    d = min(1.0, qa @ qb)
    if d > 0.9995:
        q = qa + (qb - qa) * s
    else:
        ang = math.acos(d)
        q = (qa * math.sin((1 - s) * ang) + qb * math.sin(s * ang)) / math.sin(ang)
    return pos, q / np.linalg.norm(q)


def luau(value, indent=0):
    pad = "\t" * indent
    if isinstance(value, dict):
        items = [f"{pad}\t{k if k.isidentifier() else '[' + json.dumps(k) + ']'} = {luau(v, indent + 1)}," for k, v in value.items()]
        return "{\n" + "\n".join(items) + f"\n{pad}}}"
    if isinstance(value, list):
        if all(isinstance(v, (int, float)) for v in value):
            return "{ " + ", ".join(num(v) for v in value) + " }"
        return "{\n" + "\n".join(f"{pad}\t{luau(v, indent + 1)}," for v in value) + f"\n{pad}}}"
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, bool):
        return "true" if value else "false"
    return num(value)


def num(v):
    if isinstance(v, int):
        return str(v)
    text = f"{v:.6f}".rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def main(argv):
    inputs = json.load(open(argv[0]))
    out = argv[1]
    os.makedirs(out, exist_ok=True)
    config = json.load(open(inputs["gestureConfig"]))
    grip = json.load(open(inputs["grip"]))
    thumbs = json.load(open(inputs["thumbs"]))["buttons"]
    poses = json.load(open(inputs["poses"]))
    axes, centre = wheel_axes(json.load(open(inputs["startupConfig"])))
    wheel_cabin = cabin_in(inputs, axes, centre)
    seat_cabin = cabin_in(inputs)
    rim = Rim(wheel_cabin, grip["gripAngleDeg"])
    grip_r = Frame.grip(grip["R"]["wrist"], grip["R"]["forearm"], grip["R"]["back"])
    grip_frames = {1: grip_r, -1: Frame.grip(grip["L"]["wrist"], grip["L"]["forearm"], grip["L"]["back"])}
    point_tip = np.array(poses["shapes"]["Point"]["R"]["fingertip"], float) / STUDS
    arms = {1: Arm(inputs["driver"], 1), -1: Arm(inputs["driver"], -1)}

    meshes, gestures, record = {}, [], {"inputs": inputs, "wheel": {"axes": axes.tolist(), "centre": centre.tolist()}, "gestures": []}
    for gesture in inputs["gestures"]:
        side = 1 if gesture["side"] == "R" else -1
        letter = gesture["side"]
        entry = {"control": gesture["control"], "side": side, "frame": "Wheel", "tracks": {}}
        tracks = {}
        if gesture["kind"] in ("thumb", "regrip"):
            button = thumbs[gesture["button"]]
            assert button["side"] == letter, gesture
            make = thumb_track if gesture["kind"] == "thumb" else regrip_track
            frames, shapes = make(gesture, button, grip_r, rim, side)
            hold = Frame.grip(button["wrist"], button["forearm"], button["back"])
            last = frames[-1][1]
            gap = np.linalg.norm(last.pos - hold.pos)
            turn = math.degrees(math.acos(min(1.0, (np.trace(last.rot.T @ hold.rot) - 1) / 2)))
            assert gap < 0.0002 and turn < 0.05, (gesture["control"], gap, turn)
            first = frames[0][1]
            assert np.linalg.norm(first.pos - grip_frames[side].pos) < 1e-9, gesture["control"]
            centre_m = np.array(button["centre"], float) / STUDS
            meshes[gesture["mesh"]] = {"frame": Frame(hold.rot.T, hold.rot.T @ (centre_m - hold.pos)), "cuff": "Grip", "file": button["file"]}
            pad = np.array(button["faceWheel"], float)
            tracks["Press"] = {"frames": frames, "shapes": shapes, "tip": hold.rot.T @ (pad - hold.pos), "target": pad}
        elif gesture["kind"] == "toggle":
            entry["frame"], entry["latch"] = "Seat", "Toggle"
            grip_seat = to_seat(grip_frames[side], axes, centre)
            for state in ("Off", "On"):
                spec = dict(gesture, **gesture.get(state, {}))
                frames, shapes, turn, contact, reach, angles = toggle_track(spec, config, seat_cabin, grip_seat, arms[side], point_tip, state, axes)
                print(gesture["control"], state, "reach", round(reach, 3), "lever", [round(a, 3) for a in angles])
                assert reach <= gesture.get("reachShare", REACH_SHARE), (gesture["control"], state, reach)
                target = contact(1.0)
                last = frames[-1][1]
                tracks[state] = {
                    "frames": frames,
                    "shapes": shapes,
                    "turn": {"control": hinge_part(config, gesture), **turn},
                    "gripBlend": gesture.get("gripBlend", 0.2),
                    "tip": point_tip,
                    "target": target,
                    "reach": reach,
                    "lever": angles,
                }
                assert np.linalg.norm(last.apply(point_tip) - target) < 1e-6
        elif gesture["kind"] == "knob":
            entry["latch"] = "Mode"
            posed = json.load(open(os.path.join(gesture["posesOut"], "gestures.json")))["Manettino"]
            finger, pad = np.array(posed["fingertip"], float), np.array(posed["thumbPad"], float)
            knob = Knob(config, wheel_cabin, axes, centre)
            reference = knob_reference(gesture, knob, arms[side], point_tip, axes, centre)
            assert np.linalg.norm(np.array(reference.key(0)[1:4]) - np.array(posed["reference"][:3])) < 1e-4, "the pose was made on another reference"
            meshes[gesture["mesh"]] = {"frame": Frame(np.eye(3), np.array(posed["centre"], float) / STUDS), "cuff": "Wrist", "file": posed["file"], "dir": gesture["posesOut"]}
            order = config["modeOrder"]
            from startup_check import surface_samples

            points, tris, owner, names = wheel_cabin
            rim_mask = owner == names.index("SteeringWheel_Rim")
            rim_points, rim_normals, _ = surface_samples(points, tris[rim_mask], 0.0015, np.flatnonzero(rim_mask))
            # Outward normals: away from the tube's centre line.
            radial = rim_points.copy()
            radial[:, 2] = 0
            centre_line = radial / np.linalg.norm(radial, axis=1, keepdims=True) * 0.1585
            flip = np.einsum("ij,ij->i", rim_normals, rim_points - centre_line) < 0
            rim_normals[flip] *= -1
            for state in order:
                frames, shapes, turn, angles, slides = knob_track(
                    gesture, knob, reference, finger, pad, grip_r, axes, state, order, (rim_points, rim_normals)
                )
                print(gesture["control"], state, "turn", [round(a, 3) for a in angles[:2]], "thumb moves", round(min(slides) * 1000, 1), "to", round(max(slides) * 1000, 1), "mm")
                tracks[state] = {
                    "frames": frames,
                    "shapes": shapes,
                    "turn": turn,
                    "tip": finger,
                    "target": knob.contact(angles[1], angles[2], along=gesture.get("along", 0.8), under=gesture.get("under", FINGER_UNDER)),
                    "contact": {"along": gesture.get("along", 0.8), "under": gesture.get("under", FINGER_UNDER)},
                    "lever": [angles[0], angles[1]],
                    "sense": angles[2],
                    "pad": pad,
                    "slides": slides,
                }
                first = frames[0][1]
                assert np.linalg.norm(first.pos - grip_frames[side].pos) < 1e-9
        else:
            raise SystemExit(f"unknown gesture kind {gesture['kind']}")
        for state, track in tracks.items():
            keys = [f.key(t) for t, f in track["frames"]]
            luau_track = {"keys": keys, "shapes": track["shapes"]}
            if "turn" in track:
                luau_track["turn"] = track["turn"]
            if "gripBlend" in track:
                luau_track["gripBlend"] = track["gripBlend"]
            luau_track["tip"] = dict(zip("xyz", [round(float(c), 5) for c in track["tip"]]))
            luau_track["target"] = dict(zip("xyz", [round(float(c), 5) for c in track["target"]]))
            entry["tracks"][state] = luau_track
            record["gestures"].append(
                {
                    "control": gesture["control"],
                    "side": letter,
                    "frame": entry["frame"],
                    "state": state,
                    "keys": keys,
                    "shapes": track["shapes"],
                    "turn": track.get("turn"),
                    "gripBlend": track.get("gripBlend"),
                    "tip": [float(c) for c in track["tip"]],
                    "target": [float(c) for c in track["target"]],
                    "lever": track.get("lever"),
                    "sense": track.get("sense"),
                    "contact": track.get("contact"),
                    "pad": [float(c) for c in track["pad"]] if "pad" in track else None,
                    "reach": track.get("reach"),
                }
            )
        gestures.append(entry)
    mesh_table = {name: {"frame": m["frame"].key(0)[1:], "cuff": m["cuff"]} for name, m in meshes.items()}
    record["meshes"] = {name: {"frame": m["frame"].key(0)[1:], "cuff": m["cuff"], "file": m.get("file"), "dir": m.get("dir")} for name, m in meshes.items()}
    record["holdMin"] = inputs.get("holdMin", 0.12)
    json.dump(record, open(os.path.join(out, "paths.json"), "w"), indent=1)
    if "--write" in argv:
        write_luau(argv[argv.index("--write") + 1], gestures, mesh_table, record["holdMin"], inputs.get("about", ""))
    print("wrote", os.path.join(out, "paths.json"), len(record["gestures"]), "tracks")


def hinge_part(config, gesture):
    return config["controls"][gesture["control_part"]]["part"]


def write_luau(path, gestures, meshes, hold_min, about):
    body = {"list": gestures, "MESHES": meshes, "HOLD_MIN": hold_min}
    text = (
        "--!strict\n--[[\n\tGenerated by tools/anim/gesture_paths.py; do not edit by hand. "
        + about
        + "\n]]\nlocal DriverGestures = require(\"../../DriverGestures\")\n\nlocal Gestures: DriverGestures.Gestures = "
        + luau(body)
        + "\n\nreturn Gestures\n"
    )
    open(path, "w", newline="\n").write(text)
    print("wrote", path)


if __name__ == "__main__":
    main(sys.argv[1:])
