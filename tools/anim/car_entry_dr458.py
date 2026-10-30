"""
The DR458's getting in and out, by beats (tools/anim/beat_tracks.py), against its scene file
(car_entry_prep_manifest.py) and its seated pose (the owner's option D: an R6 at scale 1.15 in the
race bucket). Every point is a car landmark in metres (Blender frame: x = the car's left, y = -forward,
z up, origin the rear-axle midpoint on the ground) moved into the authoring frame, so a cockpit move
is a re-run.

  python car_entry_dr458.py <scene.npz> <seated_pose.json> <footwell.json> <out dir>

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


def both(b, start, end):
    b.support.append((start, end, ["right_leg", "left_leg"]))


def thigh_points(footwell_path):
    """Where the blocky hands rest at the end: on the custom thighs' tops, 45 % from hip to knee
    (as the start-up's resting hands), car metres."""
    legs = json.load(open(footwell_path, encoding="utf-8"))["poses_blender"]
    out = {}
    for side, label in (("right", "right on the brake, rest"), ("left", "left on the floor")):
        hip, knee = np.array(legs[label]["hip"]), np.array(legs[label]["knee"])
        out[side] = hip + (knee - hip) * 0.45 + np.array([0.0, 0.0, 0.085])
        out[side + "_knee"] = knee
    return out


def entry(car, footwell_path):
    s = car.seated()
    yaw_out = car.yaw_facing(car.outboard)
    yaw_seat = s["yaw"]
    thighs = thigh_points(footwell_path)
    end_arms = {"right_arm": car.p(thighs["right"]), "left_arm": car.p(thighs["left"])}
    end_legs = {"right_leg": car.p(thighs["right_knee"] + np.array([0.0, -0.10, -0.12])), "left_leg": car.p(thighs["left_knee"] + np.array([0.0, -0.10, -0.12]))}
    open_end = 72
    walk0, sit0, legs0, hoist0, drop0, settle0 = 72, 102, 114, 140, 160, 196
    total = 210
    b = Body(total, FPS)
    start_idle(b, 0)
    b.door.at(0, (0.0,))
    b.neck_loc.at(0, (0.0, 0.0, 0.0))

    # -- OutsideOpen (0..72): the right foot steps toward the door, the right hand takes the handle
    # at its rear edge (the arm's end on the skin) and pulls; the body steps well back as the
    # door's rear edge comes past; the door swings on to its stop; back to the mark.
    handle = car.riding(b, DOOR_HANDLE + np.array([0.04, 0.0, 0.0]))
    fwd = np.array([0.15, 0.0, -0.65])
    back = np.array([0.55, 0.0, 0.55])
    both(b, 0, 1)
    side_step(b, "right_leg", 2, 11, IDLE["right_leg"], IDLE["right_leg"] + fwd)
    b.pelvis.at(2, IDLE_PELVIS).at(11, IDLE_PELVIS + fwd * np.array([0.5, 0, 0.5]))
    both(b, 11, 24)
    b.torso.at(2, (0, 0, 0)).at(14, (-20, -6, 3)).at(24, (-16, -4, 2))
    b.targets["right_arm"].at(4, IDLE["right_arm"])
    b.targets["right_arm"].attach(15, 38, handle)
    b.contact.append((15, 38))
    b.door.at(18, (0.0,)).at(24, (0.05,)).at(38, (0.24,)).at(54, (0.92,)).at(60, (1.0,))
    side_step(b, "right_leg", 24, 33, IDLE["right_leg"] + fwd, IDLE["right_leg"] + back)
    side_step(b, "left_leg", 32, 41, IDLE["left_leg"], IDLE["left_leg"] + back)
    b.pelvis.at(24, IDLE_PELVIS + fwd * np.array([0.5, 0, 0.5])).at(41, IDLE_PELVIS + back)
    both(b, 41, 50)
    b.torso.at(34, (2, 4, 0)).at(44, (4, 10, 0)).at(56, (0, 8, 0))
    b.targets["right_arm"].at(48, IDLE["right_arm"] + back)
    b.hang("left_arm", 0, walk0 + 20)
    side_step(b, "left_leg", 50, 59, IDLE["left_leg"] + back, IDLE["left_leg"])
    side_step(b, "right_leg", 58, 67, IDLE["right_leg"] + back, IDLE["right_leg"])
    b.pelvis.at(50, IDLE_PELVIS + back).at(67, IDLE_PELVIS)
    both(b, 67, walk0 + 1)
    b.torso.at(open_end, (0, 0, 0))
    b.neck.at(0, (0, 0, 0)).at(12, (-15, -5, 0)).at(40, (-5, 15, 0)).at(open_end, (0, 0, 0))
    b.pelvis.at(open_end, IDLE_PELVIS)
    for limb in ("right_arm", "right_leg", "left_leg"):
        b.targets[limb].at(open_end, IDLE[limb])

    # -- GetIn.
    # 1. Pivot steps from the mark to stand beside the sill facing out, the feet where straight legs
    #    will hold the bottom on the sill.
    stand = np.array([1.126, -1.45, 0.0])
    feet_r = car.p(stand) + facing_right(yaw_out) * 0.5
    feet_l = car.p(stand) - facing_right(yaw_out) * 0.5
    feet_r[1] = feet_l[1] = 0.0
    centre0 = (IDLE["right_leg"] + IDLE["left_leg"]) / 2
    centre1 = (feet_r + feet_l) / 2
    away = car.outboard * 0.6
    path = [(IDLE["right_leg"], IDLE["left_leg"], 0.0)]
    for k, yaw in ((1, yaw_out * 0.35), (2, yaw_out * 0.7), (3, yaw_out)):
        c = centre0 + (centre1 - centre0) * k / 3 + away * np.sin(np.pi * k / 3)
        r = facing_right(yaw) * 0.5
        path.append((c + r, c - r, yaw))
    f = walk0 + 2
    for k in range(1, 4):
        (r0, l0, _), (r1, l1, yaw) = path[k - 1], path[k]
        for limb, frm, to in (("left_leg", l0, l1), ("right_leg", r0, r1)):
            side_step(b, limb, f, f + 4, frm, to)
            sign = 1.0 if limb == "right_leg" else -1.0
            b.torso.at(f + 1, (-2, yaw - 12, sign * 5)).at(f + 4, (-2, yaw, sign * 4))
            f += 5
        mid = (r1 + l1) / 2
        b.pelvis.at(f - 1, (mid[0], 2.0, mid[2]))
        both(b, f - 1, f - 1)
    b.targets["right_arm"].at(walk0 + 10, IDLE["right_arm"])
    b.neck.at(walk0 + 8, (-10, 30, 0)).at(sit0, (-5, 0, 0))
    # 2. Sit down on the sill: the bottom moves in over the sill and the straight legs lower it;
    #    the hands reach back to the upper door bar.
    both(b, sit0 - 2, legs0)
    b.pelvis.at(sit0, car.p([1.05, -1.45, 0.43])).at(legs0, car.p([0.80, -1.45, 0.29]))
    b.torso.at(sit0, (0, yaw_out, 0)).at(legs0, (-4, yaw_out, 0))
    bar_f = car.p([0.636, -1.45 - 0.22, 0.55])
    bar_r = car.p([0.636, -1.45 + 0.22, 0.55])
    b.targets["right_arm"].at(sit0 + 4, IDLE["right_arm"] + (centre1 - centre0)).at(legs0, bar_f)
    b.targets["left_arm"].at(sit0 + 4, car.p([1.0, -1.25, 0.35])).at(legs0, bar_r)
    b.contact.append((legs0, hoist0 + 6))
    # 3. Lean back on the bars and lift the legs steeply over them, turning to face the nose; the
    #    bottom pivots on the sill.
    mid_yaw = (yaw_out + yaw_seat) / 2
    b.pelvis.at(legs0 + 26, car.p([0.78, -1.47, 0.30]))
    b.torso.at(legs0 + 10, (10, (yaw_out * 2 + yaw_seat) / 3, 0)).at(legs0 + 26, (14, yaw_seat, 0))
    for limb, side in (("right_leg", -1), ("left_leg", 1)):
        b.targets[limb].at(legs0, feet_r if limb == "right_leg" else feet_l)
        b.targets[limb].at(legs0 + 10, car.p([0.92 + side * 0.05, -1.75, 0.70]))
        b.targets[limb].at(legs0 + 26, car.p([0.52 + side * 0.06, -1.95, 0.98]))
    b.targets["left_arm"].at(legs0 + 26, car.p([0.636, -1.30, 0.55]))
    b.targets["right_arm"].at(legs0 + 26, car.p([0.636, -1.62, 0.55]))
    # 4. Hoist the bottom over the bars, leaning inboard so the head passes under the roof, away
    #    from the side rail, short of the wheel.
    b.pelvis.at(hoist0 + 8, car.p([0.70, -1.50, 0.56])).at(drop0, car.p([0.52, -1.50, 0.56]))
    b.torso.at(hoist0 + 8, (-6, yaw_seat, -26)).at(drop0, (0, yaw_seat, -30))
    for limb, side in (("right_leg", -1), ("left_leg", 1)):
        b.targets[limb].at(drop0, car.p([0.40 + side * 0.10, -2.05, 0.62]))
    b.targets["right_arm"].at(hoist0 + 6, car.p([0.30, -1.55, 0.48])).at(drop0, car.p([0.20, -1.60, 0.42]))
    b.targets["left_arm"].at(drop0, car.p([0.636, -1.40, 0.55]))
    # 5. Drop into the bucket and straighten into its recline.
    b.pelvis.at(drop0 + 20, s["pelvis"])
    b.torso.at(drop0 + 10, (8, yaw_seat, -12)).at(drop0 + 20, s["torso"])
    for limb in end_legs:
        b.targets[limb].at(drop0 + 20, end_legs[limb])
    b.neck.at(hoist0, (-15, 0, -10)).at(drop0, (-20, 10, 0)).at(drop0 + 20, s["neck"])
    # 6. The door: it starts in as the left hand reaches out for it at full stretch; the hand meets
    #    the card's top edge and rides it shut.
    meet = drop0 + 16
    b.door.at(drop0 + 4, (1.0,)).at(meet, (0.40,)).at(meet + 14, (0.0,))
    b.targets["left_arm"].at(drop0 + 6, car.p([0.85, -1.55, 0.70]))
    b.targets["left_arm"].attach(meet, meet + 14, car.riding(b, CARD_TOP))
    b.contact.append((meet, meet + 14))
    b.targets["right_arm"].at(drop0 + 18, end_arms["right_arm"])
    # 7. Settle on the seated pose, hands on the thighs (where the start-up's resting hands are).
    end = total - 1
    b.targets["left_arm"].at(end - 2, end_arms["left_arm"])
    b.pelvis.at(end, s["pelvis"])
    b.torso.at(end, s["torso"])
    b.neck.at(end, s["neck"])
    b.neck_loc.at(drop0, (0.0, 0.0, 0.0)).at(end, s["neck_loc"])
    for limb, t in list(end_arms.items()) + list(end_legs.items()):
        b.targets[limb].at(end, t)
    print(f"walk f{walk0}..{sit0}, sit ..{legs0}, legs in ..{hoist0}, hoist ..{drop0}, drop ..{drop0 + 20}, door meets the hand f{meet}, end f{end}")
    return b, s, yaw_out, yaw_seat, (0, open_end, total)


def main(argv):
    scene, pose, footwell, out_dir = argv
    car = Car(scene, pose)
    os.makedirs(out_dir, exist_ok=True)
    b, s, yaw_out, yaw_seat, (o0, o1, total) = entry(car, footwell)
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
