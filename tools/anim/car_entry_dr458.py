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
# The palm a hand's end-face distance off the door card's inner face, ahead of the bucket's shoulder
# wing (the card's face at x 0.7323 there, door shut).
CARD_FACE = np.array([0.7323 - 0.035, -1.80, 0.66])


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




def both(b, start, end):
    b.support.append((start, end, ["right_leg", "left_leg"]))



def feet_at(car, point, yaw):
    """Both soles beside a body centre (car x, y) facing `yaw`, on the ground, and that centre."""
    c = car.p([point[0], point[1], 0.0])
    c[1] = 0.0
    r = facing_right(yaw) * 0.5
    return {"right_leg": c + r, "left_leg": c - r}, c


def walk(b, f, frm, to, yaw0, yaw1, lead, pairs=2, bulge=None):
    """Side steps from one stance to another: each foot rises before it travels, the stepping hip
    hikes, both feet are down for a frame between steps (`bulge` arcs the path outward)."""
    order = (lead, "right_leg" if lead == "left_leg" else "left_leg")
    n, at = 0, {limb: frm[limb] for limb in order}
    # The pelvis stays over the feet until the first step, however long the wait before it.
    start = (frm["right_leg"] + frm["left_leg"]) / 2
    b.pelvis.at(f, (start[0], 2.0, start[2]))

    def along(limb, u):
        p = frm[limb] + (to[limb] - frm[limb]) * u
        return p + (bulge * np.sin(np.pi * u) if bulge is not None else 0.0)

    for k in range(pairs):
        for limb in order:
            to_k = along(limb, (k + 1) / pairs)
            side_step(b, limb, f, f + 8, at[limb], to_k, lift=0.45)
            at[limb] = to_k
            n += 1
            sign = 1.0 if limb == "right_leg" else -1.0
            yaw = yaw0 + (yaw1 - yaw0) * (n - 0.5) / (2 * pairs)
            b.torso.at(f + 1, (-1, yaw, sign * 6)).at(f + 4, (-1, yaw, sign * 7)).at(f + 6, (-1, yaw, sign * 6))
            f += 9
            mid = (at["right_leg"] + at["left_leg"]) / 2
            b.pelvis.at(f - 1, (mid[0], 2.0, mid[2]))
            both(b, f - 1, f - 1)
    return f


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
        arm_ends[limb] = (goal, (end_x, -1.0, 0.0))
        pose[r6_fk.LIMB_JOINT[limb]] = (SEATED_ARMS[limb], (0, 0, 0))
        part = r6_fk.pose_parts(pose)[r6_fk.JOINTS[r6_fk.LIMB_JOINT[limb]][1]]
        out[limb] = r6_fk.point(part, r6_fk.HAND)
    for limb, angles in SEATED_LEGS.items():
        pose[r6_fk.LIMB_JOINT[limb]] = (angles, (0, 0, 0))
        out[limb] = r6_fk.point(r6_fk.pose_parts(pose)[LIMB_PART[limb]], r6_fk.FOOT)
    return out, arm_ends


# The blocky legs at the hand-over: forward over the cushion, the least deep in the bucket within
# 40 degrees of the custom thighs (an R6 leg is 21.5 cm thick at 1.15; aimed along the custom
# thighs it sinks 0.39-0.48 stud into the cushion, here 0.16).
SEATED_LEGS = {"right_leg": (84.0, 0.0, 1.0), "left_leg": (84.0, 0.0, -2.0)}
# The blocky arms at the hand-over, the least deep within 40 degrees of the rest pose's arm ends:
# aimed at REST_POSE's blockyArmEnd (a quiet hand-over) the left one runs 0.50 stud through the
# stowed window net and the upper door bar; here both are about 0.21 into the bolsters, the left
# hand 18 cm from its rest point (decision pending with the coordinator).
SEATED_ARMS = {"right_arm": (38.0, 0.0, -31.7), "left_arm": (74.4, 0.0, 34.5)}


def quat_matrix(q):
    w, x, y, z = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)],
        [2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)],
        [2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)],
    ])


def hand_over(car, rest_path):
    """The drawn hands' pose at the hand-over (decision D): each with the resting hand's turn,
    placed so its palm is where the blocky palm ends (SEATED_ARMS), in the DriverSeat frame
    (studs of the 1.5x world), as Config/Cars/<car>/Driver.luau's `handOver` takes it."""
    rest = json.load(open(rest_path, encoding="utf-8"))
    s = car.seated()
    rot = r6_fk.body_turn(*s["torso"])
    loc = r6_fk.torso_root_offset(rot, s["pelvis"] - np.array([0.0, r6_fk.ROOT_HEIGHT, 0.0]))
    pose = {"RootJoint": (rot, tuple(loc)), "Neck": ((0, 0, 0), (0, 0, 0))}
    inv = np.linalg.inv(car.a)
    out = {}
    for limb, side in (("right_arm", "right"), ("left_arm", "left")):
        pose[r6_fk.LIMB_JOINT[limb]] = (SEATED_ARMS[limb], (0, 0, 0))
        palm = r6_fk.point(r6_fk.pose_parts(pose)[LIMB_PART[limb]], r6_fk.HAND)
        palm_seat = inv[:3, :3] @ palm + inv[:3, 3]
        r = quat_matrix(rest[side]["rotation"])
        local = r.T @ (np.array(rest[side]["palmCentre"]) - np.array(rest[side]["wrist"]))
        wrist = palm_seat - r @ local
        out[side] = {"wrist": wrist, "rotation": rest[side]["rotation"], "palm": palm_seat, "rest_palm": np.array(rest[side]["palmCentre"])}
    return out


def entry(car, rest_path):
    s = car.seated()
    yaw_out = car.yaw_facing(car.outboard)
    yaw_seat = s["yaw"]
    ends, _ = seated_ends(car, s, rest_path)
    walk0 = WALK0
    total = END + 1
    b = Body(total, FPS)
    start_idle(b, 0)
    b.door.at(0, (0.0,))
    b.neck_loc.at(0, (0.0, 0.0, 0.0))

    # -- OutsideOpen: two pairs of short steps forward and out to stand behind the door facing
    # mostly forward, the right arm reaching in to the door's pull (the stance where the blocky arm
    # meets the skin most squarely); a tug opens the door a little as the body leans back; the
    # body backs out past the door's sweep while the door swings slowly, then returns to the mark.
    handle = car.riding(b, DOOR_HANDLE + np.array([0.035, 0.0, 0.0]))
    yaw_in = car.yaw_facing(-car.outboard)
    yaw_pull = yaw_in + (yaw_seat - yaw_in) * 0.8
    pull_feet, pull_c = feet_at(car, GRAB, yaw_pull)
    out_feet, out_c = feet_at(car, OUT, yaw_pull * 0.5)

    both(b, 0, 1)
    f = walk(b, 2, IDLE, pull_feet, 0.0, yaw_pull, "left_leg")
    b.pelvis.at(2, IDLE_PELVIS).at(f, (pull_c[0], 2.0, pull_c[2]))
    b.torso.at(f, (-10, yaw_pull, 0))
    pull, release = f, f + 6
    both(b, pull, release + 4)
    b.hang("right_arm", 0, pull - 14)
    b.targets["right_arm"].at(pull - 5, car.p(DOOR_HANDLE + np.array([0.12, 0.08, 0.03])))
    b.targets["right_arm"].attach(pull, release, handle)
    b.contact.append((pull, release))
    b.torso.at(release + 4, (4, yaw_pull, 0))
    f = walk(b, release + 4, pull_feet, out_feet, yaw_pull, yaw_pull * 0.5, "right_leg", pairs=1)
    b.pelvis.at(release + 4, (pull_c[0], 2.0, pull_c[2])).at(f, (out_c[0], 2.0, out_c[2]))
    for fr, v in ((pull + 1, 0.0), (release, 0.025), (release + 8, 0.06), (f, 0.22), (f + 6, 0.6), (f + 13, 0.95), (f + 16, 1.0)):
        b.door.at(fr, (v,))
    b.targets["right_arm"].at(release + 3, car.p(DOOR_HANDLE + np.array([0.22, 0.10, -0.02])))
    b.hang("right_arm", release + 12, OPEN_END)
    b.hang("left_arm", 0, OPEN_END)
    back = f + 2
    f = walk(b, back, out_feet, IDLE, yaw_pull * 0.5, 0.0, "left_leg", pairs=1)
    both(b, f, OPEN_END + 1)
    b.pelvis.at(back, (out_c[0], 2.0, out_c[2])).at(f, IDLE_PELVIS)
    b.torso.at(back, (0, yaw_pull * 0.5, 0)).at(f, (0, 0, 0))
    b.neck.at(0, (0, 0, 0)).at(8, (-12, -10, 0)).at(pull - 5, (-15, -10, 0)).at(release + 8, (5, 15, 0)).at(OPEN_END, (0, 0, 0))
    b.pelvis.at(OPEN_END, IDLE_PELVIS)
    for limb in ("right_leg", "left_leg"):
        b.targets[limb].at(OPEN_END, IDLE[limb])
    b.torso.at(OPEN_END, (0, 0, 0))
    print(f"OutsideOpen: grab f{pull}-f{release}, back at the mark f{f}, clip ends f{OPEN_END}")
    open_end = OPEN_END

    getin(b, car, s, open_end, ends)
    return b, s, yaw_out, yaw_seat, (0, open_end, total)


# GetIn's beats, frames from the timeline's start.
OPEN_END = 88
GRAB = np.array([1.50, -1.10])  # body behind the door, the right arm reaching in to its pull
OUT = np.array([1.60, -0.72])  # past the door's sweep (radius 1.28 m about the hinge)
WALK0 = OPEN_END
LEAN0, HOP0 = WALK0 + 36, WALK0 + 52
SIT, T1, T2, OVER = HOP0 + 10, HOP0 + 15, HOP0 + 20, HOP0 + 26
DROP, D1, D2, SEATED = OVER + 12, OVER + 8, OVER + 16, OVER + 26
CLOSE_FROM, END = SEATED - 4, SEATED + 40
# The SVJ's InsideClose door curve (Config/Cars/SVJ/Door.luau), seconds from its start: the door
# swings shut at the speed the game's other door does.
SVJ_CLOSE = ((0.0, 1.0), (0.033, 0.995), (0.1, 0.961), (0.2, 0.88), (0.233, 0.847), (0.3, 0.756), (0.433, 0.55), (0.566, 0.369), (0.7, 0.228), (0.8, 0.143), (0.966, 0.031), (1.033, 0.004), (1.066, 0.0))
KEY_FRAMES = {"B": SIT, "T1": T1, "T2": T2, "C": OVER, "D1": D1, "D2": D2}
# Key poses found by grid search on scene_v14 (the torso and head first, then each limb):
# B sitting across the bars facing in, head inside; T1, T2 turning on them; C facing the nose,
# torso leaning 55 degrees in across the bucket; D1, D2 over the bolster and down.
KEYS = {
    "B": {"pelvis": (0.7, -1.57, 0.58), "torso": (-55, -36.21, 10), "neck": (-15, 0, 0), "limbs": {"right_leg": (20, -15), "left_leg": (10, -5), "right_arm": (110, -130), "left_arm": (-140, -130)}},
    "T1": {"pelvis": (0.685, -1.575, 0.565), "torso": (-45, -20.21, -10), "neck": (-25, 0, 0), "limbs": {"right_leg": (-20, -35), "left_leg": (0, -25), "right_arm": (130, 130), "left_arm": (-190, -130)}},
    "T2": {"pelvis": (0.67, -1.58, 0.55), "torso": (-35, 10, -30), "neck": (-25, 0, 0), "limbs": {"right_leg": (0, -85), "left_leg": (60, -65), "right_arm": (90, 130), "left_arm": (-20, 100)}},
    "C": {"pelvis": (0.676, -1.527, 0.588), "torso": (5, 57, -55), "neck": (-10, 0, 0), "limbs": {"right_leg": (100, -75), "left_leg": (50, 75), "right_arm": (20, 100), "left_arm": (-170, -130)}},
    "D1": {"pelvis": (0.5599, -1.503, 0.54), "torso": (15, 48, -35), "neck": (-20, 0, 0), "limbs": {"right_leg": (50, -65), "left_leg": (40, 65), "right_arm": (140, -120), "left_arm": (190, -130)}},
    "D2": {"pelvis": (0.4438, -1.48, 0.44), "torso": (10, 54, -15), "neck": (-5, 0, 0), "limbs": {"right_leg": (130, 15), "left_leg": (70, 75), "right_arm": (30, -30), "left_arm": (140, 130)}},
}
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
    # 5. The door swings shut on its own as the driver settles, on the SVJ's own close curve, while
    #    the hands settle into their hand-over pose (the coordinator's decision E1': from the seat a
    #    1.15 R6 reaches nothing on this door that pulls, and any reach lays its arm on the card).
    for t, v in SVJ_CLOSE:
        b.door.at(CLOSE_FROM + round(t * FPS), (v,))
    # Into the hand-over pose from its own side: an R6 arm reaches a palm point two ways, and the
    # solve keeps whichever way the arm arrives from.
    for limb in ("right_arm", "left_arm"):
        b.targets[limb].at(SEATED + 8, ends[limb] + np.array([0.15 if limb == "left_arm" else -0.15, 0.35, -0.25]))
    for track, value in ((b.pelvis, s["pelvis"]), (b.torso, s["torso"]), (b.neck, s["neck"]), (b.neck_loc, s["neck_loc"])):
        track.at(END, value)
    for limb, t in ends.items():
        b.targets[limb].at(END, t)

# The exit's beats: InsideOpen, then GetOut ending at the mark's idle stance (the root jumps there
# between clips), then OutsideClose from the mark.
HAND_OVER = 18  # frames the drawn hands take to ease onto the blocky ones (Driver handOver, 0.6 s)
IO_END = HAND_OVER + 44
GO_D2, GO_D1, GO_C, GO_T2, GO_T1, GO_B = IO_END + 14, IO_END + 22, IO_END + 32, IO_END + 38, IO_END + 43, IO_END + 49
GO_STAND, GO_UP, GO_WALK = IO_END + 59, IO_END + 71, IO_END + 72
GO_END = GO_WALK + 40
CLOSE_AT = np.array([2.08, -1.38])  # behind the open door, outside its sweep, facing the nose
CARD_REAR = np.array([0.725, -1.20, 0.70])  # the door card's inner face near its rear upper corner, door shut


def exit_timeline(car, rest_path):
    """InsideOpen: the left hand reaches the door card's top edge and pushes the door open, which
    swings on to its stop. GetOut: the entry's caged poses the other way, from the bucket up onto
    the bars, turning to face the car with the head kept inside, the feet down outside, standing
    up out from under the rail, side steps back to the mark. OutsideClose: steps up behind the open
    door, the right hand takes its pull loop and draws it in while the body backs away, lets go,
    and is past the door's sweep before it shuts; back to the mark."""
    s = car.seated()
    ends, _ = seated_ends(car, s, rest_path)
    yaw_in = car.yaw_facing(-car.outboard)
    yaw_seat = s["yaw"]
    b = Body(OC_END + 1, FPS)
    # The arms start on their hand-over pose, solved from its own joint angles.
    for limb, angles in SEATED_ARMS.items():
        b.guess[limb] = (angles[0], angles[2])
    for track, value in ((b.pelvis, s["pelvis"]), (b.torso, s["torso"]), (b.neck, s["neck"]), (b.neck_loc, s["neck_loc"])):
        track.at(0, value)
    for limb, t in ends.items():
        b.targets[limb].at(0, t)
        b.twist[limb].at(0, (0,))
    b.door.at(0, (0.0,))
    # -- InsideOpen: the blocky arms hold their hand-over pose while the drawn ones ease onto it
    # (HAND_OVER); the driver leans forward out of the bucket's shoulder wing, the left palm on the
    # door card pushes the door from shut to about 12 % (the coordinator's decision: from the seat
    # this is the one door surface a 1.15 R6 reaches), and it swings open; back into the seat.
    lean = (s["torso"][0] - 34.5, yaw_seat, 4.0)
    push, push_end = HAND_OVER + 8, HAND_OVER + 18
    b.torso.at(HAND_OVER, s["torso"]).at(push - 2, lean).at(push_end, lean).at(IO_END, s["torso"])
    b.neck.at(HAND_OVER, s["neck"]).at(push - 2, (-10, 8, 0)).at(push_end, (-10, 8, 0)).at(IO_END, s["neck"])
    for limb, t in ends.items():
        b.targets[limb].at(HAND_OVER, t)
    b.targets["left_arm"].at(push - 3, car.p(CARD_FACE + np.array([-0.06, 0.03, 0.02])))
    b.targets["left_arm"].attach(push, push_end, car.riding(b, CARD_FACE))
    b.contact.append((push, push_end))
    for fr, v in ((push + 1, 0.0), (push_end, 0.12), (push_end + 8, 0.45), (push_end + 16, 0.9), (push_end + 20, 1.0)):
        b.door.at(fr, (v,))
    b.targets["left_arm"].at(push_end + 6, ends["left_arm"] + np.array([0.15, 0.35, -0.25]))
    for track, value in ((b.pelvis, s["pelvis"]), (b.neck_loc, s["neck_loc"])):
        track.at(IO_END, value)
    for limb, t in ends.items():
        b.targets[limb].at(IO_END + 2, t)
    # -- GetOut: the entry's key poses in reverse.
    b.neck_loc.at(GO_D1, (0.0, 0.0, 0.0))
    for name, frame in (("D2", GO_D2), ("D1", GO_D1), ("C", GO_C), ("T2", GO_T2), ("T1", GO_T1), ("B", GO_B)):
        key_beats(b, car, frame, KEYS[name])
    b.contact.append((GO_D2 - 2, GO_STAND + 2))
    feet = feet_at(car, STANCE, yaw_in)[0]
    for limb in ("right_leg", "left_leg"):
        b.targets[limb].at(GO_STAND - 2, feet[limb] + (0, 0.05, 0)).at(GO_STAND, feet[limb])
    both(b, GO_STAND, GO_WALK)
    b.pelvis.at(GO_STAND, car.p([STANCE[0], STANCE[1], 0.43]))
    b.torso.at(GO_STAND, (-40, yaw_in, 0)).at(GO_UP, (0, yaw_in, 0))
    b.neck.at(GO_STAND, (-20, 0, 0)).at(GO_UP, (-10, 0, 0))
    b.targets["right_arm"].at(GO_B + 4, car.p(BAR_REAR)).at(GO_STAND + 2, car.p(BAR_REAR))
    b.targets["left_arm"].at(GO_B + 4, car.p(BAR_FRONT)).at(GO_STAND + 2, car.p(BAR_FRONT))
    b.hang("right_arm", GO_UP - 2, GO_END)
    b.hang("left_arm", GO_UP - 2, GO_END)
    bulge = car.outboard * np.array([1.0, 0.0, 1.0]) * 0.55
    f = walk(b, GO_WALK, feet, {k: IDLE[k] for k in feet}, yaw_in, 0.0, "right_leg", bulge=bulge)
    both(b, f - 1, GO_END + 1)
    b.pelvis.at(GO_END, IDLE_PELVIS)
    b.torso.at(GO_END, (0, 0, 0))
    b.neck.at(GO_END, (0, 0, 0))
    for limb in ("right_leg", "left_leg"):
        b.targets[limb].at(GO_END, IDLE[limb])
    b.door.at(GO_END, (1.0,))
    # -- OutsideClose: side steps out behind the open door, beyond its sweep, facing the nose; the
    # right hand flat on the card near its rear corner tugs the door in as the body leans back, lets
    # go, and the door swings shut; back to the mark.
    yaw_close = yaw_seat
    close_feet, close_c = feet_at(car, CLOSE_AT, yaw_close)
    f = walk(b, GO_END + 1, {k: IDLE[k] for k in close_feet}, close_feet, 0.0, yaw_close, "right_leg", pairs=3)
    b.pelvis.at(GO_END + 1, IDLE_PELVIS).at(f, (close_c[0], 2.0, close_c[2]))
    b.torso.at(f, (-8, yaw_close, 0))
    pull, release = f + 2, f + 12
    both(b, f - 1, release)
    palm = CARD_REAR - np.array([0.035, 0.0, 0.0])
    b.targets["right_arm"].at(pull - 8, car.p(car_point_at_door(car, palm, 1.0) + np.array([0.10, 0.12, 0.0])))
    b.targets["right_arm"].attach(pull, release, car.riding(b, palm))
    b.contact.append((pull, release))
    b.torso.at(release, (6, yaw_close, 0))
    for fr, v in ((pull, 1.0), (release, 0.9), (release + 8, 0.76), (release + 16, 0.5), (release + 24, 0.15), (release + 28, 0.0)):
        b.door.at(fr, (v,))
    # The right arm hangs on the door's side of the body: it comes up in front of the chest until
    # the door has swung past.
    b.targets["right_arm"].at(release + 3, car.p(car_point_at_door(car, palm, 0.88) + np.array([0.30, 0.30, 0.05])))
    b.targets["right_arm"].attach(release + 6, release + 26, b.on_torso((0.3, 0.6, -1.4)))
    b.hang("right_arm", release + 34, OC_END)
    b.hang("left_arm", GO_END, OC_END)
    # Half a step out of the door's way as it swings past.
    clear_feet, clear_c = feet_at(car, CLOSE_AT + np.array([0.14, 0.06]), yaw_close)
    f = walk(b, release + 1, close_feet, clear_feet, yaw_close, yaw_close, "left_leg", pairs=1)
    b.pelvis.at(release + 1, (close_c[0], 2.0, close_c[2])).at(f, (clear_c[0], 2.0, clear_c[2]))
    close_feet = clear_feet
    rest_at = max(f + 2, release + 28)
    both(b, f - 1, rest_at + 1)
    b.torso.at(rest_at, (0, yaw_close, 0))
    b.neck.at(pull, (-12, 0, 0)).at(release + 12, (-5, 15, 0)).at(rest_at, (0, 0, 0))
    f = walk(b, rest_at + 2, close_feet, {k: IDLE[k] for k in close_feet}, yaw_close, 0.0, "left_leg", pairs=3)
    both(b, f - 1, OC_END + 1)
    for track, value in ((b.pelvis, IDLE_PELVIS), (b.torso, (0, 0, 0)), (b.neck, (0, 0, 0))):
        track.at(OC_END, value)
    for limb in ("right_leg", "left_leg"):
        b.targets[limb].at(OC_END, IDLE[limb])
    clips = [
        {"name": "InsideOpen", "start": 0, "end": IO_END},
        {"name": "GetOut", "start": IO_END, "end": GO_END},
        {"name": "OutsideClose", "start": GO_END, "end": OC_END},
    ]
    print(f"exit: InsideOpen ..f{IO_END}, GetOut ..f{GO_END}, OutsideClose ..f{OC_END}, pull f{pull}-f{release}, at rest past the sweep f{rest_at}")
    return b, clips


OC_END = GO_END + 172


def car_point_at_door(car, point, openness):
    """A door point (car metres, door shut) where the door puts it at `openness`, car metres."""
    a = car.door_at(point, openness)
    inv = np.linalg.inv(car.a)
    seat = a @ inv[:3, :3].T + inv[:3, 3]
    return H_POINT + TO_SEAT @ (seat * STUD)


ARMS = ["Right Arm", "Left Arm"]
LEGS = ["Right Leg", "Left Leg"]


def entry_contacts():
    """Named contacts (depth, studs at scale 1) and held limbs, for car_entry_clear.py; the check's
    allow file is written from the same list at the measured depths."""
    allow = [
        {"why": "right hand on the door's pull, pulling", "from": 34, "to": 50, "parts": ["Right Arm"], "groups": ["door"], "depth": 0.15},
        {"why": "hands on the door bars and the bucket, leaning in, pushing up, turning", "from": HOP0 - 2, "to": DROP + 2, "parts": ARMS, "groups": ["cage", "seat"], "depth": 0.15},
        {"why": "PROPOSED (rigid-thigh class): thighs over the sill and the door bars while the legs swing in", "from": HOP0 + 4, "to": DROP + 4, "parts": LEGS, "groups": ["cage", "sill"], "depth": 0.25},
        {"why": "PROPOSED: the bottom across the door bars while sitting and turning on them", "from": HOP0 + 4, "to": DROP, "parts": ["Torso"], "groups": ["cage"], "depth": 0.15},
        {"why": "DECIDED (owner, option D): torso sides into the bucket's bolsters, 5.5 cm seated", "from": OVER + 4, "to": END, "parts": ["Torso"], "groups": ["seat"], "depth": 0.261},
        {"why": "DECIDED (seated pose): head on the headrest pad, at the house checker's depth (its 0.62-stud head box; the seated check's smaller box measured 0.89 cm)", "from": SEATED, "to": END, "parts": ["Head"], "groups": ["seat"], "depth": 0.059},
        {"why": "DECIDED (coordinator, B): the blocky arms at their hand-over pose beside the torso, into the bucket's bolsters as the torso's sides are", "from": SEATED, "to": END, "parts": ARMS, "groups": ["seat"], "depth": 0.22},
        {"why": "DECIDED (coordinator): the blocky legs at their least-deep pose in the bucket, under the wheel", "from": SEATED - 6, "to": END, "parts": LEGS, "groups": ["seat"], "depth": 0.17},
    ]
    holds = [
        {"from": WALK0, "to": HOP0 + 2, "limb": "right_leg"},
        {"from": WALK0, "to": HOP0 + 2, "limb": "left_leg"},
        {"from": HOP0 - 2, "to": HOP0 + 2, "limb": "right_arm"},
        {"from": HOP0 - 2, "to": HOP0 + 2, "limb": "left_arm"},
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


def exit_contacts():
    """The exit's named contacts and held limbs (as entry_contacts)."""
    allow = [
        {"why": "DECIDED (coordinator, owner's overnight mandate): the left palm on the door card pushing the door from shut to 12 %, the arm's side along the card (a seated R6 at 1.15 reaches the card only this way)", "from": HAND_OVER + 8, "to": HAND_OVER + 18, "parts": ["Left Arm"], "groups": ["door"], "depth": 0.3},
        {"why": "hands on the bucket and the door bars, climbing out and standing up", "from": GO_D2 - 2, "to": GO_STAND + 4, "parts": ARMS, "groups": ["cage", "seat"], "depth": 0.15},
        {"why": "PROPOSED (rigid-thigh class): thighs over the door bars and the sill while the legs swing out", "from": GO_D1 - 4, "to": GO_STAND, "parts": LEGS, "groups": ["cage", "sill"], "depth": 0.25},
        {"why": "PROPOSED: the bottom across the door bars while turning on them", "from": GO_D1, "to": GO_STAND - 4, "parts": ["Torso"], "groups": ["cage"], "depth": 0.15},
        {"why": "DECIDED (owner, option D): torso sides into the bucket's bolsters, 5.5 cm seated", "from": 0, "to": GO_C - 4, "parts": ["Torso"], "groups": ["seat"], "depth": 0.261},
        {"why": "DECIDED (seated pose): head on the headrest pad, at the house checker's depth", "from": 0, "to": GO_D2, "parts": ["Head"], "groups": ["seat"], "depth": 0.059},
        {"why": "DECIDED (coordinator, B): the blocky arms at their hand-over pose beside the torso, into the bucket's bolsters as the torso's sides are", "from": 0, "to": IO_END + 4, "parts": ARMS, "groups": ["seat"], "depth": 0.22},
        {"why": "DECIDED (coordinator): the blocky legs at their least-deep pose in the bucket, under the wheel", "from": 0, "to": GO_D2, "parts": LEGS, "groups": ["seat"], "depth": 0.17},
        {"why": "right hand flat on the door card, tugging the door in", "from": GO_END + 30, "to": GO_END + 52, "parts": ["Right Arm"], "groups": ["door"], "depth": 0.12},
    ]
    holds = [
        {"from": HAND_OVER + 8, "to": HAND_OVER + 18, "limb": "left_arm"},
        {"from": GO_STAND, "to": OC_END, "limb": "right_leg"},
        {"from": GO_STAND, "to": OC_END, "limb": "left_leg"},
        {"from": 0, "to": 6, "limb": "right_arm"},
        {"from": 0, "to": 6, "limb": "left_arm"},
    ]
    return allow, holds


def timeline(car, rest, which):
    """(body, clips) of the entry or the exit timeline."""
    if which == "exit":
        return exit_timeline(car, rest)
    b, s, yaw_out, yaw_seat, (o0, o1, total) = entry(car, rest)
    return b, [{"name": "OutsideOpen", "start": o0, "end": o1}, {"name": "GetIn", "start": o1, "end": total - 1}]


def build(argv):
    """For car_entry_clear.py: <scene> <seated pose> <rest pose> [--timeline entry|exit]
    [--clear table.json]."""
    scene, pose, rest = argv[:3]
    which = argv[argv.index("--timeline") + 1] if "--timeline" in argv else "entry"
    b, _ = timeline(Car(scene, pose), rest, which)
    if "--clear" in argv:
        apply_table(b, argv[argv.index("--clear") + 1])
    allow, holds = exit_contacts() if which == "exit" else entry_contacts()
    return b, allow, holds


def main(argv):
    """<scene> <seated pose> <rest pose> <out dir> [--timeline entry|exit] [--clear table.json]"""
    scene, pose, rest, out_dir = argv[:4]
    which = argv[argv.index("--timeline") + 1] if "--timeline" in argv else "entry"
    os.makedirs(out_dir, exist_ok=True)
    b, clips = timeline(Car(scene, pose), rest, which)
    if "--clear" in argv:
        apply_table(b, argv[argv.index("--clear") + 1])
    b.solve()
    data = b.keys(every=1, clips=clips, markers=[])
    write(os.path.join(out_dir, f"{which}.keys.json"), data)
    with open(os.path.join(out_dir, f"{which}.fk.json"), "w", encoding="utf-8", newline="\n") as h:
        json.dump(b.fk_bake(), h)
    for f, limb, err in b.report_misses():
        if f % 6 == 0:
            print("miss", f, limb, err)


if __name__ == "__main__":
    main(sys.argv[1:])
