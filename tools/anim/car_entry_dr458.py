"""
The DR458's getting in and out, by beats (tools/anim/beat_tracks.py), against its scene file
(car_entry_prep_manifest.py) and its seated pose (the owner's option D: an R6 at scale 1.15 in the
race bucket). Every point is a car landmark in metres (Blender frame: x = the car's left, y = -forward,
z up, origin the rear-axle midpoint on the ground) moved into the authoring frame, so a cockpit move
is a re-run.

  python car_entry_dr458.py <scene.npz> <seated_pose.json> <REST_POSE.json> <out dir>

The DR458 is entered as a caged race car with a front-hinged door: the right hand takes the handle at
the door's rear edge and swings the door open while the body steps back out of its arc. The R6 is
0.70 m from its bottom to the top of its head, all rigid, and the window over the door bars is
0.45 m tall, so the head goes in first: facing the car the body leans in under the cage's side rail
with both hands on the bars, pushes up and turns on them to face the nose with the head kept
inside, the legs swinging over the sill and the bars, then slides over the bucket's bolster and
drops in. The door is out of an R6 arm's reach from the seat, so the left hand reaches out as the
door swings in and rides its card shut. The last frame aims the blocky arms where REST_POSE.json
(the start-up's resting hands) says, so the hand-over to the drawn arms does not jump.
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r6_fk  # noqa: E402
from beat_tracks import Body, write  # noqa: E402
from car_entry_keys import IDLE, IDLE_PELVIS, side_step, start_idle  # noqa: E402
from car_scene import rotation_about  # noqa: E402

FPS = 30
STUD = 0.28 / 1.5
H_POINT = np.array([0.3443, -1.5001, 0.3165])
TO_SEAT = np.array([[-1.0, 0, 0], [0, 0, 1.0], [0, 1.0, 0]])
# Car landmarks, Blender metres (dr458_manifest.json, the cockpit agent's contract, measured on the
# assembled car).
DOOR_HANDLE = np.array([0.95, -1.08, 0.60])  # the teardrop pull on the skin ahead of the rear shut line (photo 025)
CARD_TOP = np.array([0.75, -1.40, 0.80])  # the door card's top edge level with the seat


class Car:
    def __init__(self, scene_path, pose_path):
        self.scene = np.load(scene_path, allow_pickle=False)
        self.pose = json.load(open(pose_path, encoding="utf-8"))
        self.a = self.scene["seat_to_authoring"]
        self.k = float(self.scene["scale"])
        self.pivot = self.scene["hinge_pivot"]
        self.axis = self.scene["hinge_axis"]
        self.open_angle = float(self.scene["open_angle"])
        # The car's directions in the authoring frame.
        self.forward = self.d([0, -1, 0])
        self.outboard = self.d([1, 0, 0])

    def p(self, car_point):
        q = (np.asarray(car_point, float) - H_POINT) @ TO_SEAT.T / STUD
        return q @ self.a[:3, :3].T + self.a[:3, 3]

    def d(self, car_dir):
        v = (np.asarray(car_dir, float) @ TO_SEAT.T) @ self.a[:3, :3].T
        return v / np.linalg.norm(v)

    def m(self, metres):
        """Metres of the car as authoring studs."""
        return metres / STUD / self.k

    def door_at(self, car_point, openness):
        q = self.p(car_point) - self.pivot
        return rotation_about(self.axis, openness * self.open_angle)[:3, :3] @ q + self.pivot

    def riding(self, body, car_point, off=(0, 0, 0)):
        """A beat value: a door point carried by the timeline's own door track."""

        def at(frame):
            openness = float(body.door.sample(np.array([frame]))[0][0])
            return self.door_at(car_point, openness) + np.asarray(off, float)

        return at

    def yaw_facing(self, direction):
        """The torso yaw (degrees) that faces a horizontal authoring direction."""
        return float(np.degrees(np.arctan2(-direction[0], -direction[2])))

    def seated(self):
        """The seated pose (SeatedPose's RootJoint and Neck) as beat values: pelvis point, torso
        angles, neck angles and the neck's shift."""
        clip = self.pose["clip"]
        root_seat = np.array(self.pose["root_seat_studs_ASSUMED"])
        root_car = H_POINT + TO_SEAT.T @ (root_seat * STUD)
        root = self.p(root_car)
        yaw = self.yaw_facing(self.forward)
        lean = clip["RootJoint"]["lean_x_deg"]
        rot = r6_fk.body_turn(lean, yaw, 0.0)
        turn = r6_fk.body_turn(0.0, yaw, 0.0)
        loc = np.array(clip["RootJoint"]["position_studs_scale1"])
        centre = root + turn @ loc
        pelvis = centre + rot @ np.asarray(r6_fk.PELVIS, float)
        neck = clip["Neck"]
        return dict(pelvis=pelvis, torso=(lean, yaw, 0.0), neck=(neck["nod_x_deg"], 0.0, 0.0), neck_loc=tuple(neck["position_studs_scale1"]), root=root, yaw=yaw)



def facing_right(yaw):
    """The body's right (authoring frame) at a torso yaw."""
    a = np.radians(yaw)
    return np.array([np.cos(a), 0.0, -np.sin(a)])


def hike(b, steps, roll=7.0):
    """A rigid leg clears the ground only if its hip rides up: over each (limb, start, end) step the
    torso rolls toward the planted side (R6_ANIMATION.md section 4), on the lean and yaw the torso
    had before any hike, so consecutive steps do not cancel."""
    plan = []
    for limb, start, end in steps:
        sign = 1.0 if limb == "right_leg" else -1.0
        frames = (start + 1, (start + end) // 2, end - 2)
        for f, (lean, yaw, r) in zip(frames, b.torso.sample(np.array(frames, dtype=float))):
            plan.append((f, (lean, yaw, r + sign * roll * (1.2 if f == frames[1] else 1.0))))
    for f, turn in plan:
        b.torso.at(f, turn)


def step(b, limb, start, end, frm, to, lift=0.4):
    """One step of `limb`, the other leg supporting, with the hip hiked (hike): the foot rises
    straight up over two frames before it travels and comes straight down over two before it
    lands, since a grounded sole that moves fails the check as a slide."""
    other = "left_leg" if limb == "right_leg" else "right_leg"
    frm, to = np.asarray(frm, float), np.asarray(to, float)
    up = np.array([0.0, 1.0, 0.0])
    b.support.append((start, end - 1, [other]))
    t = b.targets[limb]
    t.at(start, frm).at(start + 1, frm + up * 0.08).at(start + 2, frm + up * 0.22)
    t.at(start + 4, frm * 0.6 + to * 0.4 + up * lift).at(end - 4, frm * 0.4 + to * 0.6 + up * lift)
    t.at(end - 2, to + up * 0.22).at(end - 1, to + up * 0.08).at(end, to)


def both(b, start, end):
    b.support.append((start, end, ["right_leg", "left_leg"]))



def seat_to_car(seat, studs=True):
    """A DriverSeat-frame point (x right, y up, z back; studs of the 1.5x world, or metres) in car
    metres."""
    return H_POINT + TO_SEAT @ (np.asarray(seat, float) * (STUD if studs else 1.0))


def seated_ends(car, s, rest_path):
    """GetIn's last frame for the blocky limbs, which the custom limbs replace once seated: each
    arm's end on the rest pose's blockyArmEnd (as the SVJ's seated_targets aims it), so the
    start-up's resting hands take over without a jump; each leg from its hip toward the custom
    knee, tipped down toward the pedals."""
    rest = json.load(open(rest_path, encoding="utf-8"))
    rot = r6_fk.body_turn(*s["torso"])
    loc = r6_fk.torso_root_offset(rot, s["pelvis"] - np.array([0.0, r6_fk.ROOT_HEIGHT, 0.0]))
    pose = {"RootJoint": (rot, tuple(loc)), "Neck": ((0, 0, 0), (0, 0, 0))}
    out, arm_ends = {}, {}
    for limb, side, end_x in (("right_arm", "right", -0.5), ("left_arm", "left", 0.5)):
        goal = car.p(seat_to_car(rest[side]["blockyArmEnd"]))
        angles, _ = r6_fk.aim(pose, limb, goal, (end_x, -1.0, 0.0), guess=(60, 0))
        pose[r6_fk.LIMB_JOINT[limb]] = (angles, (0, 0, 0))
        part = r6_fk.pose_parts(pose)[r6_fk.JOINTS[r6_fk.LIMB_JOINT[limb]][1]]
        out[limb] = r6_fk.point(part, r6_fk.HAND)
        arm_ends[limb] = (goal, (end_x, -1.0, 0.0))
    torso = r6_fk.pose_parts(pose)["Torso"]
    for limb, side in (("right_leg", "right"), ("left_leg", "left")):
        joint = r6_fk.point(torso, (0.5 if side == "right" else -0.5, -1, 0))
        knee = car.p(seat_to_car(rest[side]["check"]["kneeMetres"], studs=False))
        direction = knee - joint
        direction[1] -= 0.25 * np.linalg.norm(direction)
        out[limb] = joint + 2.0 * direction / np.linalg.norm(direction)
    return out, arm_ends


def entry(car, rest_path):
    s = car.seated()
    yaw_out = car.yaw_facing(car.outboard)
    yaw_seat = s["yaw"]
    ends, _ = seated_ends(car, s, rest_path)
    open_end = 72
    walk0 = WALK0
    total = END + 1
    b = Body(total, FPS)
    start_idle(b, 0)
    b.door.at(0, (0.0,))
    b.neck_loc.at(0, (0.0, 0.0, 0.0))

    # -- OutsideOpen (0..72): the right foot steps toward the door, the right hand takes the handle
    # at its rear edge (the arm's end on the skin) and pulls; the body steps well back as the
    # door's rear edge comes past; the door swings on to its stop; back to the mark.
    # The palm sits a hand's end-face distance off the skin, so the blocky hand meets the pull.
    handle = car.riding(b, DOOR_HANDLE + np.array([0.035, 0.0, 0.0]))
    fwd = np.array([0.15, 0.0, -0.65])
    back = np.array([0.55, 0.0, 0.55])
    both(b, 0, 1)
    step(b, "right_leg", 2, 12, IDLE["right_leg"], IDLE["right_leg"] + fwd)
    b.pelvis.at(2, IDLE_PELVIS).at(12, IDLE_PELVIS + fwd * np.array([0.5, 0, 0.5]))
    both(b, 12, 23)
    b.torso.at(2, (0, 0, 0)).at(14, (-20, -6, 3)).at(24, (-16, -4, 2))
    b.targets["right_arm"].at(4, IDLE["right_arm"])
    b.targets["right_arm"].at(11, car.p(DOOR_HANDLE + np.array([0.16, 0.06, -0.04])))
    b.targets["right_arm"].attach(15, 38, handle)
    b.contact.append((15, 38))
    b.door.at(18, (0.0,)).at(24, (0.05,)).at(38, (0.24,)).at(54, (0.92,)).at(60, (1.0,))
    step(b, "right_leg", 23, 33, IDLE["right_leg"] + fwd, IDLE["right_leg"] + back)
    step(b, "left_leg", 34, 44, IDLE["left_leg"], IDLE["left_leg"] + back)
    b.pelvis.at(23, IDLE_PELVIS + fwd * np.array([0.5, 0, 0.5])).at(44, IDLE_PELVIS + back)
    both(b, 44, 49)
    b.torso.at(34, (2, 4, 0)).at(44, (4, 10, 0)).at(56, (0, 8, 0))
    b.targets["right_arm"].at(48, IDLE["right_arm"] + back)
    b.hang("left_arm", 0, open_end)
    step(b, "left_leg", 49, 59, IDLE["left_leg"] + back, IDLE["left_leg"])
    step(b, "right_leg", 60, 70, IDLE["right_leg"] + back, IDLE["right_leg"])
    b.pelvis.at(49, IDLE_PELVIS + back).at(70, IDLE_PELVIS)
    both(b, 70, walk0 + 1)
    b.torso.at(open_end, (0, 0, 0))
    hike(b, (("right_leg", 2, 12), ("right_leg", 23, 33), ("left_leg", 34, 44), ("left_leg", 49, 59), ("right_leg", 60, 70)))
    both(b, 33, 34)
    both(b, 59, 60)
    b.neck.at(0, (0, 0, 0)).at(12, (-15, -5, 0)).at(40, (-5, 15, 0)).at(open_end, (0, 0, 0))
    b.pelvis.at(open_end, IDLE_PELVIS)
    for limb in ("right_arm", "right_leg", "left_leg"):
        b.targets[limb].at(open_end, IDLE[limb])

    getin(b, car, s, open_end, ends)
    return b, s, yaw_out, yaw_seat, (0, open_end, total)


# GetIn's beats, frames from the timeline's start.
WALK0, LEAN0, HOP0, SIT, OVER, DROP, SEATED, MEET, SHUT, END = 72, 108, 124, 134, 150, 162, 176, 194, 206, 220
KEY_FRAMES = {"B": SIT, "T1": 139, "T2": 144, "C": OVER, "D1": 158, "D2": 166}
KEYS = {}
STANCE = np.array([1.03, -1.58])  # where the body stands facing the car to lean in (car x, y)
# Palms over the stowed net's roll on the upper door bar (top z 0.525): an R6 palm is 0.15 stud
# (3.2 cm at 1.15) above the arm's end face, which is what rests on the roll.
BAR_REAR = np.array([0.61, -1.42, 0.557])
BAR_FRONT = np.array([0.61, -1.74, 0.557])


LIMB_PART = {"right_arm": "Right Arm", "left_arm": "Left Arm", "right_leg": "Right Leg", "left_leg": "Left Leg"}


def key_beats(b, car, frame, key, limbs=None):
    """A key pose (pelvis as a car point, torso and neck angles, limb joint angles) as beats: the
    limbs' targets are where those angles put the palm or the sole."""
    rot = r6_fk.body_turn(*key["torso"])
    pelvis = car.p(key["pelvis"])
    loc = r6_fk.torso_root_offset(rot, pelvis - np.array([0.0, r6_fk.ROOT_HEIGHT, 0.0]))
    pose = {"RootJoint": (rot, tuple(loc)), "Neck": (tuple(key["neck"]), (0, 0, 0))}
    for limb, (x, z) in key["limbs"].items():
        pose[r6_fk.LIMB_JOINT[limb]] = ((x, 0.0, z), (0, 0, 0))
    parts = r6_fk.pose_parts(pose)
    b.pelvis.at(frame, pelvis)
    b.torso.at(frame, tuple(key["torso"]))
    b.neck.at(frame, tuple(key["neck"]))
    for limb in limbs if limbs is not None else key["limbs"]:
        b.targets[limb].at(frame, r6_fk.point(parts[LIMB_PART[limb]], Body.LIMB_POINT[limb]))


def getin(b, car, s, start, ends):
    """The DR458's caged-car entry: facing the car at the opening, lean in under the side rail with
    both hands on the bars; push up, turning on the bars to face the nose with the head kept inside,
    the legs swinging over the sill and the bars; slide over the bucket's bolster and drop in; the
    left hand meets the door as it swings in and rides it shut; hands onto the thighs."""
    yaw_in = car.yaw_facing(-car.outboard)
    yaw_seat = s["yaw"]
    right = facing_right(yaw_in)
    feet_r = car.p([STANCE[0], STANCE[1], 0.0]) + right * 0.5
    feet_l = car.p([STANCE[0], STANCE[1], 0.0]) - right * 0.5
    feet_r[1] = feet_l[1] = 0.0
    # 1. Side steps from the mark to the stance, turning to face the car.
    f = WALK0
    pairs = 2
    bulge = car.outboard * np.array([1.0, 0.0, 1.0]) * 0.55  # an arc out past the rear fender

    def along(frm, to, u):
        return frm + (to - frm) * u + bulge * np.sin(np.pi * u)

    for k in range(pairs):
        for limb, frm, to in (("left_leg", IDLE["left_leg"], feet_l), ("right_leg", IDLE["right_leg"], feet_r)):
            side_step(b, limb, f, f + 8, along(frm, to, k / pairs), along(frm, to, (k + 1) / pairs), lift=0.45)
            sign = 1.0 if limb == "right_leg" else -1.0
            yaw = yaw_in * (2 * k + (1 if limb == "right_leg" else 0.5)) / (2 * pairs)
            b.torso.at(f + 1, (-1, yaw, sign * 6)).at(f + 4, (-1, yaw, sign * 7)).at(f + 6, (-1, yaw, sign * 6))
            f += 9
            r = along(IDLE["right_leg"], feet_r, (k + 1) / pairs if limb == "right_leg" else k / pairs)
            l_ = along(IDLE["left_leg"], feet_l, (k + 1) / pairs)
            mid = (r + l_) / 2
            b.pelvis.at(f - 1, (mid[0], 2.0, mid[2]))
            both(b, f - 1, f - 1)
    both(b, f - 1, HOP0 + 2)
    b.torso.at(f, (0, yaw_in, 0))
    b.neck.at(WALK0 + 6, (-8, 25, 0)).at(f, (-10, 0, 0))
    b.hang("right_arm", WALK0, f - 2)
    b.hang("left_arm", start, f - 2)
    # 2. Lean in under the rail, hands onto the bars.
    b.torso.at(LEAN0 + 2, (-6, yaw_in, 0)).at(HOP0, (-40, yaw_in, 0))
    b.neck.at(HOP0, (-20, 0, 0))
    b.targets["right_arm"].at(LEAN0 + 6, car.p(BAR_REAR + (0.15, 0.0, 0.15))).at(HOP0 - 2, car.p(BAR_REAR))
    b.targets["left_arm"].at(LEAN0 + 6, car.p(BAR_FRONT + (0.15, 0.0, 0.15))).at(HOP0 - 2, car.p(BAR_FRONT))
    b.contact.append((HOP0 - 2, OVER + 2))
    # 3. Push up onto the bars, sitting across them still facing in with the head inside and the
    #    legs hanging outside (B); turn on them to face the nose, the spine kept pointing in so the
    #    head stays under the rail, the legs swinging over the sill and the bars (T1, T2, OVER);
    #    slide over the bolster and drop into the bucket (D1, D2). Key poses from a grid search of
    #    the torso and head, then of each limb, against the scene (KEYS); the frames between are
    #    cleared by car_entry_clear.py.
    b.pelvis.at(HOP0 + 2, car.p([STANCE[0], STANCE[1], 0.43]))
    for limb, feet in (("right_leg", feet_r), ("left_leg", feet_l)):
        b.targets[limb].at(HOP0 + 2, feet).at(HOP0 + 4, feet + (0, 0.05, 0))
    for name, frame in KEY_FRAMES.items():
        if name in KEYS:
            key_beats(b, car, frame, KEYS[name])
    b.contact.append((OVER - 2, DROP + 2))
    b.neck_loc.at(0, (0.0, 0.0, 0.0)).at(DROP, (0.0, 0.0, 0.0)).at(SEATED, s["neck_loc"])
    b.pelvis.at(SEATED, s["pelvis"])
    b.torso.at(SEATED, s["torso"])
    b.neck.at(SEATED, s["neck"])
    for limb in ("right_leg", "left_leg", "right_arm"):
        b.targets[limb].at(SEATED, ends[limb])
    # 5. The door swings in as the left hand reaches out over the bars; the hand meets the card's
    #    top edge and rides it shut, then rests on the thigh.
    b.door.at(SEATED - 4, (1.0,)).at(MEET, (0.12,)).at(SHUT, (0.0,))
    b.targets["left_arm"].at(SEATED, car.p([0.70, -1.40, 0.72]))
    b.targets["left_arm"].attach(MEET, SHUT, car.riding(b, CARD_TOP))
    b.contact.append((MEET, SHUT))
    for track, value in ((b.pelvis, s["pelvis"]), (b.torso, s["torso"]), (b.neck, s["neck"]), (b.neck_loc, s["neck_loc"])):
        track.at(END, value)
    for limb, t in ends.items():
        b.targets[limb].at(END, t)
    b.targets["left_arm"].at(SHUT + 6, ends["left_arm"] + (0.3, 0.4, 0.0))


ARMS = ["Right Arm", "Left Arm"]
LEGS = ["Right Leg", "Left Leg"]


def entry_contacts():
    """Named contacts (depth, studs at scale 1) and held limbs, for car_entry_clear.py; the check's
    allow file is written from the same list at the measured depths."""
    allow = [
        {"why": "right hand on the door handle, pulling", "from": 15, "to": 38, "parts": ["Right Arm"], "groups": ["door"], "depth": 0.15},
        {"why": "hands on the door bars and the bucket, leaning in, pushing up, turning", "from": HOP0 - 2, "to": DROP + 2, "parts": ARMS, "groups": ["cage", "seat"], "depth": 0.15},
        {"why": "PROPOSED (rigid-thigh class): thighs over the sill and the door bars while the legs swing in", "from": HOP0 + 4, "to": DROP + 4, "parts": LEGS, "groups": ["cage", "sill"], "depth": 0.25},
        {"why": "PROPOSED: the bottom across the door bars while sitting and turning on them", "from": HOP0 + 4, "to": DROP, "parts": ["Torso"], "groups": ["cage"], "depth": 0.15},
        {"why": "DECIDED (owner, option D): torso sides into the bucket's bolsters, 5.5 cm seated", "from": OVER + 4, "to": END, "parts": ["Torso"], "groups": ["seat"], "depth": 0.261},
        {"why": "DECIDED (seated pose): head on the headrest pad", "from": SEATED, "to": END, "parts": ["Head"], "groups": ["seat"], "depth": 0.047},
        {"why": "left hand on the door card's top edge, riding it shut", "from": MEET, "to": SHUT, "parts": ["Left Arm"], "groups": ["door"], "depth": 0.12},
    ]
    holds = [
        {"from": WALK0, "to": HOP0 + 2, "limb": "right_leg"},
        {"from": WALK0, "to": HOP0 + 2, "limb": "left_leg"},
        {"from": HOP0 - 2, "to": HOP0 + 2, "limb": "right_arm"},
        {"from": HOP0 - 2, "to": HOP0 + 2, "limb": "left_arm"},
        {"from": MEET, "to": SHUT, "limb": "left_arm"},
        {"from": END, "to": END, "limb": "right_arm"},
        {"from": END, "to": END, "limb": "left_arm"},
    ]
    return allow, holds


def apply_table(b, path):
    """Beats solved by car_entry_clear.py, one per solved frame."""
    for frame, row in json.load(open(path, encoding="utf-8")).items():
        f = int(frame)
        b.pelvis.at(f, row["pelvis"])
        b.torso.at(f, row["torso"])
        b.neck.at(f, row["neck"])
        for limb, t in row["targets"].items():
            b.targets[limb].at(f, t)


def build(argv):
    """For car_entry_clear.py: <scene> <seated pose> <rest pose> [--clear table.json]."""
    scene, pose, rest = argv[:3]
    car = Car(scene, pose)
    b, *_ = entry(car, rest)
    if "--clear" in argv:
        apply_table(b, argv[argv.index("--clear") + 1])
    allow, holds = entry_contacts()
    return b, allow, holds


def main(argv):
    scene, pose, rest, out_dir = argv[:4]
    car = Car(scene, pose)
    os.makedirs(out_dir, exist_ok=True)
    b, s, yaw_out, yaw_seat, (o0, o1, total) = entry(car, rest)
    if "--clear" in argv:
        apply_table(b, argv[argv.index("--clear") + 1])
    print("seated yaw", round(yaw_seat, 1), "outboard yaw", round(yaw_out, 1))
    b.solve()
    clips = [{"name": "OutsideOpen", "start": o0, "end": o1}, {"name": "GetIn", "start": o1, "end": total - 1}]
    data = b.keys(every=1, clips=clips, markers=[])
    write(os.path.join(out_dir, "entry.keys.json"), data)
    with open(os.path.join(out_dir, "entry.fk.json"), "w", encoding="utf-8", newline="\n") as h:
        json.dump(b.fk_bake(), h)
    for f, limb, err in b.report_misses():
        if f % 6 == 0:
            print("miss", f, limb, err)


if __name__ == "__main__":
    main(sys.argv[1:])
