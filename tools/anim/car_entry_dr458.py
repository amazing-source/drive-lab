"""
The DR458's getting in and out, by beats (tools/anim/beat_tracks.py), against its scene file
(car_entry_prep_manifest.py) and its seated pose (the owner's option D: an R6 at scale 1.15 in the
race bucket). Every point is a car landmark in metres (Blender frame: x = the car's left, y = -forward,
z up, origin the rear-axle midpoint on the ground) moved into the authoring frame, so a cockpit move
is a re-run.

  python -I car_entry_dr458.py <scene.npz> <seated_pose.json> <out dir>

The DR458 is entered as a caged race car with a front-hinged door: the right hand takes the handle at
the door's rear edge and swings the door open while the body steps back out of its arc; the body
backs up to the cage's upper door bar, hoists itself onto it with both hands, leans out so the head
clears the roof edge, lifts the legs over the bar while turning to face the nose, then slides down
into the bucket, ducking under the cage's side rail. The door is out of an R6 arm's reach from the
seat, so the left hand reaches out as the door starts to swing in and rides its card down to shut.
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
DOOR_HANDLE = np.array([0.86, -1.07, 0.59])
UPPER_BAR = np.array([0.636, 0.0, 0.461])  # top of the cage's upper door bar (y free along the bar)
CARD_TOP = np.array([0.75, -1.40, 0.80])  # the door card's top edge level with the seat
STANCE_Y = -1.42  # where the body backs up to the bar, along the car


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


def seated_limb_targets(car, seated):
    """The blocky limbs at the seated pose (hidden once seated, shown at the hand-over): arms toward
    the grip, legs toward the footwell, as the SeatedPose clip aims them."""
    rot = r6_fk.body_turn(*seated["torso"])
    torso = np.identity(4)
    torso[:3, :3] = rot
    torso[:3, 3] = seated["pelvis"] - rot @ np.asarray(r6_fk.PELVIS, float)
    out = {}
    # Arms: toward the wheel's 9 and 3 at the rim (the custom arms are drawn once seated).
    wheel = np.array([0.3443, -1.8712, 0.7254])
    for limb, side in (("right_arm", -1), ("left_arm", 1)):
        out[limb] = car.p(wheel + np.array([side * 0.158, 0.0, 0.0]))
    for limb, side in (("right_leg", -1), ("left_leg", 1)):
        out[limb] = car.p(np.array([0.3443 + side * 0.12, -2.25, 0.20]))
    return out


def facing_right(yaw):
    """The body's right (authoring frame) at a torso yaw."""
    a = np.radians(yaw)
    return np.array([np.cos(a), 0.0, -np.sin(a)])


def stance(car, centre_car, yaw, spread=0.5):
    """Right and left soles on the ground either side of a car point, across the body at `yaw`."""
    c = car.p(centre_car)
    c[1] = 0.0
    r = facing_right(yaw)
    return c + r * spread, c - r * spread


def both(b, start, end):
    b.support.append((start, end, ["right_leg", "left_leg"]))


def entry(car):
    s = car.seated()
    yaw_out = car.yaw_facing(car.outboard)
    yaw_seat = s["yaw"]
    seat_limbs = seated_limb_targets(car, s)
    open_end, total = 72, 72 + 150
    b = Body(total, FPS)
    start_idle(b, 0)
    b.door.at(0, (0.0,))
    b.neck_loc.at(0, (0.0, 0.0, 0.0))

    # -- OutsideOpen (0..72): the right foot steps toward the door, the right hand takes the handle
    # at its rear edge and pulls; the door's rear edge comes past in front as the foot steps back;
    # the door swings on to its stop; back to the mark facing the opening.
    handle = car.riding(b, DOOR_HANDLE)
    fwd = np.array([0.15, 0.0, -0.65])
    both(b, 0, 1)
    side_step(b, "right_leg", 2, 11, IDLE["right_leg"], IDLE["right_leg"] + fwd)
    b.pelvis.at(2, IDLE_PELVIS).at(11, IDLE_PELVIS + fwd * np.array([0.5, 0, 0.5]))
    both(b, 11, 25)
    b.torso.at(2, (0, 0, 0)).at(14, (-20, -6, 3)).at(26, (-16, -4, 2))
    b.targets["right_arm"].at(4, IDLE["right_arm"])
    b.targets["right_arm"].attach(15, 42, handle)
    b.contact.append((15, 42))
    b.door.at(18, (0.0,)).at(24, (0.05,)).at(42, (0.30,)).at(56, (0.92,)).at(62, (1.0,))
    side_step(b, "right_leg", 26, 36, IDLE["right_leg"] + fwd, IDLE["right_leg"])
    b.pelvis.at(26, IDLE_PELVIS + fwd * np.array([0.5, 0, 0.5])).at(36, IDLE_PELVIS)
    both(b, 36, 73)
    b.torso.at(42, (-6, 10, 0)).at(58, (0, 8, 0)).at(open_end, (0, 0, 0))
    b.targets["right_arm"].at(54, IDLE["right_arm"])
    b.hang("left_arm", 0, 120)
    b.neck.at(0, (0, 0, 0)).at(12, (-15, -5, 0)).at(44, (-5, 15, 0)).at(open_end, (0, 0, 0))
    b.pelvis.at(open_end, IDLE_PELVIS)
    for limb in ("right_arm", "right_leg", "left_leg"):
        b.targets[limb].at(open_end, IDLE[limb])

    # -- GetIn (72..222).
    # 1. Pivot steps from the mark to stand with the back to the cage's upper door bar, the feet on
    #    the ground outside the sill, turning to face out.
    feet_r, feet_l = stance(car, [1.02, STANCE_Y, 0.0], yaw_out)
    path = [(IDLE["right_leg"], IDLE["left_leg"], 0.0)]
    centre0 = (IDLE["right_leg"] + IDLE["left_leg"]) / 2
    centre1 = (feet_r + feet_l) / 2
    for k, yaw in ((1, yaw_out * 0.35), (2, yaw_out * 0.7), (3, yaw_out)):
        c = centre0 + (centre1 - centre0) * k / 3
        r = facing_right(yaw) * 0.5
        path.append((c + r, c - r, yaw))
    f = 74
    for k in range(1, 4):
        (r0, l0, _), (r1, l1, yaw) = path[k - 1], path[k]
        for limb, frm, to in (("left_leg", l0, l1), ("right_leg", r0, r1)):
            side_step(b, limb, f, f + 7, frm, to)
            sign = 1.0 if limb == "right_leg" else -1.0
            b.torso.at(f + 1, (-2, yaw - 15, sign * 5)).at(f + 6, (-2, yaw, sign * 4))
            f += 7
        mid = (r1 + l1) / 2
        b.pelvis.at(f - 1, (mid[0], 2.0, mid[2]))
        both(b, f - 1, f - 1)
    stand_start = f
    both(b, stand_start, stand_start + 12)
    b.neck.at(stand_start - 30, (-10, 30, 0)).at(stand_start, (-5, 0, 0))
    # 2. Back up to the bar: lean back onto it, hands on the bar beside the hips.
    hips_stance = car.p([0.78, STANCE_Y, 0.37])
    b.pelvis.at(stand_start + 6, hips_stance)
    b.torso.at(stand_start, (0, yaw_out, 0)).at(stand_start + 10, (6, yaw_out, 0))
    bar_front = car.p(UPPER_BAR + np.array([0.0, STANCE_Y - 0.22, 0.02])) + np.array([0, 0.15, 0])
    bar_rear = car.p(UPPER_BAR + np.array([0.0, STANCE_Y + 0.22, 0.02])) + np.array([0, 0.15, 0])
    b.targets["right_arm"].at(stand_start + 2, IDLE["right_arm"] + (centre1 - centre0) * np.array([1, 0, 1]))
    b.targets["right_arm"].at(stand_start + 10, bar_front)
    b.targets["left_arm"].at(stand_start + 10, bar_rear)
    b.contact.append((stand_start + 10, stand_start + 46))
    # 3. Hoist onto the bar, leaning out so the head clears the roof edge; the feet leave the ground.
    up = stand_start + 12
    on_bar = car.p([0.66, STANCE_Y, 0.481])
    b.pelvis.at(up + 10, on_bar)
    b.torso.at(up + 10, (-22, yaw_out, 0))
    for limb, foot in (("right_leg", feet_r), ("left_leg", feet_l)):
        b.targets[limb].at(up, foot).at(up + 10, foot + np.array([0, 0.3, 0]) + car.outboard * 0.4)
    # 4. Lift the legs over the bar and turn to face the nose, ducking deeper (the head goes
    #    forward over the knees, under the cage's side rail).
    sw = up + 10
    mid_yaw = (yaw_out + yaw_seat) / 2
    b.pelvis.at(sw + 26, on_bar)
    b.torso.at(sw + 12, (-18, mid_yaw, 0)).at(sw + 26, (-34, yaw_seat, 0))
    over = car.p([0.66, STANCE_Y - 0.35, 0.78])
    for limb, side in (("right_leg", 1), ("left_leg", -1)):
        b.targets[limb].at(sw + 12, over + facing_right(mid_yaw) * side * 0.5)
        b.targets[limb].at(sw + 26, car.p([0.3443 - side * 0.12, -2.05, 0.42]))
    b.targets["left_arm"].at(sw + 20, bar_rear)
    # 5. Slide down into the bucket, rising from the duck to the seat's recline as the bottom
    #    drops below the rail.
    sl = sw + 26
    b.pelvis.at(sl + 14, car.p([0.50, -1.47, 0.43])).at(sl + 34, s["pelvis"])
    b.torso.at(sl + 14, (-24, yaw_seat, 0)).at(sl + 34, (s["torso"][0], yaw_seat, 0))
    b.targets["right_arm"].at(sl + 4, bar_front).at(sl + 30, seat_limbs["right_arm"])
    for limb in ("right_leg", "left_leg"):
        b.targets[limb].at(sl + 34, seat_limbs[limb])
    b.neck.at(sw + 26, (-10, 0, 0)).at(sl + 34, s["neck"])
    # 6. The door: it starts in as the left hand reaches out for it at full stretch; the hand meets
    #    the card's top edge and rides it shut.
    meet = sl + 20
    b.door.at(sl + 6, (1.0,)).at(meet, (0.40,)).at(meet + 14, (0.0,))
    b.targets["left_arm"].at(sl + 6, bar_rear + np.array([0, 0.5, 0]))
    b.targets["left_arm"].attach(meet, meet + 14, car.riding(b, CARD_TOP))
    b.contact.append((meet, meet + 14))
    end = total - 1
    b.targets["left_arm"].at(end - 2, seat_limbs["left_arm"])
    # 7. Settle on the seated pose (SeatedPose).
    b.pelvis.at(end, s["pelvis"])
    b.torso.at(end, s["torso"])
    b.neck.at(end, s["neck"])
    b.neck_loc.at(sl + 10, (0.0, 0.0, 0.0)).at(end, s["neck_loc"])
    for limb in seat_limbs:
        b.targets[limb].at(end, seat_limbs[limb])
    print(f"walk ends f{stand_start}, hoist f{up}..{up + 10}, swing f{sw}..{sw + 26}, slide f{sl}..{sl + 34}, door meets the hand f{meet}, end f{end}")
    return b, s, yaw_out, yaw_seat, (0, open_end, total)


def main(argv):
    scene, pose, out_dir = argv
    car = Car(scene, pose)
    os.makedirs(out_dir, exist_ok=True)
    b, s, yaw_out, yaw_seat, (o0, o1, total) = entry(car)
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
