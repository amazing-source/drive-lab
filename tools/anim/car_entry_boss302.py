"""
The Boss 302's getting in and out, by beats (tools/anim/beat_tracks.py), against its scene file
(car_entry_prep_manifest.py, the sill split into its own group) and its seated pose (an R6 at scale
1.15, torso 15 degrees back on the moved seat). Every point is a car landmark in metres (Blender frame:
x = the car's left, y = -forward, z up, origin the rear-axle midpoint on the ground) moved into the
authoring frame, so a cockpit move is a re-run. Built on car_entry_dr458.py; only the getting in over
the cage is replaced.

  python car_entry_boss302.py <scene.npz> <seated_pose.json> <REST_POSE.json> <out dir> [--timeline ...]

A road car with a long front-hinged door, a wide opening and a high seat: the seat's hip point is
0.15 m above a standing R6's hips. Outside, the right hand takes the pull bar ahead of the lock and
swings the door open as the body steps back out of its arc to the mark. Getting in, the back turns to
the seat, the hands go back onto the bolsters, a short push-up hop puts the bottom on the cushion's
outboard bolster, the body turns to face the nose with the legs lifting in over the sill, leans out
for the door's pull and draws the door in while sliding across into the seat; let go, the door shuts
on its own swing. The last frame aims the blocky arms where REST_POSE.json (the start-up's resting
hands) says, so the hand-over to the drawn arms does not jump.
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r6_fk  # noqa: E402
from beat_tracks import IDLE_LOCAL, Body, write  # noqa: E402
from car_entry_keys import IDLE, IDLE_PELVIS, side_step, start_idle  # noqa: E402
from car_scene import rotation_about  # noqa: E402

FPS = 30
STUD = 0.28 / 1.5
H_POINT = np.array([0.3746, -1.1562, 0.5757])
TO_SEAT = np.array([[-1.0, 0, 0], [0, 0, 1.0], [0, 1.0, 0]])
# Car landmarks, Blender metres: the door's contact points from the 3D agent's measurements on the
# car (door shut), the seat's bolster tops from sections of Seat_Driver.
DOOR_HANDLE = np.array([0.899, -0.859, 0.839])  # centre of the outside pull bar, ahead of the lock
# The palm on the armrest's pull recess wall from the cabin side, an end-face distance off it (taken
# from below the lip, the arm crosses the armrest: 0.34-0.45 stud into the door against 0.22-0.26 here).
DOOR_PULL = np.array([0.706 - 0.035, -1.362, 0.599])
# The palm a hand's end-face distance off the door card's pleated insert above the armrest (its face at
# x 0.742, measured on the door's triangles), pushing (InsideOpen). Pushed on the armrest's inboard face
# (the 3D agent's push patch) the arm crossed the seat's bolster, 0.34 stud deep, and missed by 0.05.
PUSH_PATCH = np.array([0.707, -1.33, 0.76])
PUSH_BACK = np.array([0.56, -1.28, 0.86])  # the left hand coming back from the push, over the bolster
# Palms on the bolster tops, 0.15 stud (3.2 cm at 1.15) above the arm's end face that rests there.
BOLSTER_BACK = np.array([0.60, -1.13, 0.70 + 0.032])  # the backrest's outboard wing
# The cushion's outboard bolster, front: the nearest palm point on it the leaning body's rigid arm reaches
# (at 1.53 forward the palm fell 0.12 stud short).
BOLSTER_FRONT = np.array([0.574, -1.514, 0.575])
CUSHION_PUSH = np.array([0.45, -1.42, 0.505 + 0.032])  # the cushion's middle, ahead of the hips
LET_GO_HAND = np.array([0.56, -1.30, 0.74])  # the left hand just let go of the door, over the bolster


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


def hold_hand_over(b, start, end, limbs=None):
    """The blocky limbs held on their hand-over angles (SEATED_ARMS, SEATED_LEGS) while the drawn
    hands ease over them: aimed at their end points, a limb can arrive on its other branch."""
    for limb, (x, _, z) in {**SEATED_ARMS, **SEATED_LEGS}.items():
        if limbs is not None and limb not in limbs:
            continue
        for f in range(start, end + 1):
            b.fixed.setdefault(limb, {})[f] = (x, z)


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


# The blocky limbs at the hand-over (boss_handover_grid.py on scene_v2): per limb, the least deep
# within 50 degrees of its aimed angles (one branch) and 40 degrees of where it should point (an arm at
# REST_POSE's blockyArmEnd, a leg at the custom knee). None clears: the right arm 0.10 into the seat's
# bolster, the left arm 0.30 into both the bolster and the door card, the right leg 0.11 into the
# cushion and the wheel's rim, the left leg 0.15-0.16 into the cushion, the rim and the door card.
SEATED_LEGS = {"right_leg": (76.0, 0.0, -11.0), "left_leg": (98.5, 0.0, 83.0)}
SEATED_ARMS = {"right_arm": (53.0, 0.0, 3.4), "left_arm": (52.6, 0.0, 60.1)}


def quat_matrix(q):
    w, x, y, z = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)],
        [2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)],
        [2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)],
    ])


def hand_over(car, rest_path):
    """The drawn hands' pose at the hand-over (decision D): each with the resting hand's turn,
    placed so its palm is where the blocky palm ends (SEATED_ARMS), in the DriverSeat frame in studs of
    the 1.5x world (REST_POSE.json's frame); Config/Cars/<car>/Driver.luau's `handOver` takes metres
    (Rig/StartupHands), so multiply the positions by 0.28 / 1.5."""
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
    total = END + 1
    b = Body(total, FPS)
    start_idle(b, 0)
    b.door.at(0, (0.0,))
    b.neck_loc.at(0, (0.0, 0.0, 0.0))

    # -- OutsideOpen: a pair of short steps up behind the door facing mostly forward, the right arm
    # reaching in to the pull bar; a tug opens the door a little as the body leans back, and a pair of
    # steps back to the mark (outside the door's sweep) clears its arc while it swings to its stop.
    handle = car.riding(b, DOOR_HANDLE + np.array([0.035, 0.0, 0.0]))
    yaw_in = car.yaw_facing(-car.outboard)
    yaw_pull = yaw_in + (yaw_seat - yaw_in) * 0.8
    pull_feet, pull_c = feet_at(car, GRAB, yaw_pull)
    both(b, 0, 1)
    f = walk(b, 2, IDLE, pull_feet, 0.0, yaw_pull, "right_leg")
    b.pelvis.at(2, IDLE_PELVIS).at(f, (pull_c[0], 2.0, pull_c[2]))
    b.torso.at(f, (-10, yaw_pull, 0))
    pull, release = f, f + 4
    assert (pull, release) == (PULL, PULL + 4), (pull, release)
    both(b, pull, release + 4)
    b.hang("right_arm", 0, pull - 8)
    b.targets["right_arm"].at(pull - 4, car.p(DOOR_HANDLE + np.array([0.30, 0.12, 0.08])))
    b.targets["right_arm"].attach(pull, release, handle)
    b.contact.append((pull, release))
    # Through the tug the body as solved per frame for the rigid arm to keep the bar (boss_hold.py); it
    # leans back once the hand lets go.
    for offset, pelvis, turn in PULL_RIDE:
        b.pelvis.at(pull + offset, car.p(pelvis))
        b.torso.at(pull + offset, turn)
    b.torso.at(release + 4, (4, yaw_pull, 0))
    f = walk(b, release + 4, pull_feet, IDLE, yaw_pull, 0.0, "right_leg", pairs=1)
    both(b, f - 1, OPEN_END + 1)
    b.pelvis.at(release + 4, (pull_c[0], 2.0, pull_c[2])).at(f, IDLE_PELVIS)
    for fr, v in ((pull + 1, 0.0), (release, 0.015), (release + 8, 0.06), (f, 0.22), (f + 6, 0.6), (f + 13, 0.95), (f + 16, 1.0)):
        b.door.at(fr, (v,))
    b.targets["right_arm"].at(release + 1, car.p(DOOR_HANDLE + np.array([0.26, 0.16, 0.06])))
    b.hang("right_arm", release + 12, OPEN_END)
    b.hang("left_arm", 0, OPEN_END)
    b.torso.at(f, (0, 0, 0))
    b.neck.at(0, (0, 0, 0)).at(8, (-12, -10, 0)).at(pull - 4, (-15, -10, 0)).at(release + 8, (5, 15, 0)).at(OPEN_END, (0, 0, 0))
    b.pelvis.at(OPEN_END, IDLE_PELVIS)
    for limb in ("right_leg", "left_leg"):
        b.targets[limb].at(OPEN_END, IDLE[limb])
    b.torso.at(OPEN_END, (0, 0, 0))
    print(f"OutsideOpen: grab f{pull}-f{release}, back at the mark f{f}, door open f{f + 16}, clip ends f{OPEN_END}")
    getin(b, car, s, OPEN_END, ends)
    return b, s, yaw_out, yaw_seat, (0, OPEN_END, total)


# OutsideOpen's beats.
GRAB = np.array([1.48, -0.82])  # behind the door, the right arm reaching in to its pull bar (car x, y)
PULL = 38
# The body over the tug: frame offset from PULL, pelvis (car metres), (lean, yaw, roll); boss_hold.py with
# the right palm on the pull bar (misses <= 0.001 stud, the arm 0.047 into the door).
PULL_RIDE = (
    (0, (1.4601, -0.8212, 0.4357), (-16.34, 33.34, 0.0)),
    (1, (1.4605, -0.8212, 0.4356), (-16.33, 33.34, -0.12)),
    (2, (1.4631, -0.8210, 0.4348), (-16.24, 33.34, -0.12)),
    (3, (1.4689, -0.8206, 0.4329), (-16.02, 33.34, -0.12)),
    (4, (1.4738, -0.8203, 0.4313), (-15.82, 33.34, 0.21)),
)
OPEN_END = 84
# GetIn's beats, frames from the timeline's start.
WALK0 = OPEN_END
STANCE = np.array([1.03, -1.20])  # the feet's centre in the opening, facing out with the back to the seat
# Metres the walk to the stance arcs out from the car's flank, so the arm on the car's side clears the
# rear quarter.
WALK_ARC = 0.30
# Degrees the stance turns from facing straight out toward the nose: the right arm then hangs clear of
# the open door's front, near its hinge.
STANCE_TURN = -10.0
AT_STANCE = WALK0 + 72  # four pairs of side steps (three left a planted foot sliding 9.8 studs/s)
LEAN_BACK = AT_STANCE + 6  # back against the seat's edge, hands on the bolsters (P)
HOP0 = LEAN_BACK + 4  # the push starts; the feet leave the ground
HOP_MID = HOP0 + 4
HOP_ARC = np.array([0.78, -1.29, 0.53])  # the pelvis half way up the hop (car metres)
HOP_TOP = HOP0 + 9  # the bottom on the cushion's outboard bolster (H), 0.3 s after the push
SIT = HOP_TOP + 4  # settled on the edge facing out (S)
T1, T2 = SIT + 8, SIT + 16  # turning to face the nose, the legs lifting in over the sill
REACH = T2 + 8  # the left palm on the door's pull, leaning out at the doorway
DOOR_GO = REACH - 4  # the door starts its swing as the hand arrives (the coordinator's decision A)
LET_GO = REACH + 6  # the door ridden in to TAKE_RELEASE, let go to swing shut on its own
# The door's openness where the palm lands and where it lets go: past 0.62 the hook comes in faster than
# a rigid arm can give way (boss_hold.py: the body would have to rise 13 cm, misses up to 0.045 stud).
TAKE_AT, TAKE_RELEASE = 0.85, 0.62
SEATED = LET_GO + 14
HOLD_FROM = SEATED - 2  # the limbs on their hand-over pose from here, as the body lands
ON_HAND_OVER, END = SEATED + 24, SEATED + 30
# The SVJ's InsideClose door curve (Config/Cars/SVJ/Door.luau), seconds from its start: the door
# swings shut at the speed the game's other door does.
SVJ_CLOSE = ((0.0, 1.0), (0.033, 0.995), (0.1, 0.961), (0.2, 0.88), (0.233, 0.847), (0.3, 0.756), (0.433, 0.55), (0.566, 0.369), (0.7, 0.228), (0.8, 0.143), (0.966, 0.031), (1.033, 0.004), (1.066, 0.0))
KEY_FRAMES = {"P": LEAN_BACK, "H": HOP_TOP, "S": SIT, "T1": T1, "T2": T2, "R": REACH}
# The body over the door ride: frame offset from REACH, pelvis (car metres), (lean, yaw, roll); solved by
# boss_hold.py with the left palm on DOOR_PULL, the left arm 0.22-0.29 stud into the door.
RIDE = (
    (0, (0.6397, -1.2998, 0.5703), (0.00, 50.00, 24.41)),
    (1, (0.6320, -1.2962, 0.5764), (0.00, 50.01, 22.96)),
    (2, (0.6249, -1.2927, 0.5823), (0.00, 50.03, 21.50)),
    (3, (0.6182, -1.2893, 0.5878), (0.00, 50.07, 20.10)),
    (4, (0.6108, -1.2829, 0.5992), (0.00, 50.12, 19.65)),
    (5, (0.6031, -1.2750, 0.6199), (0.00, 50.18, 20.50)),
    (6, (0.5911, -1.2614, 0.6370), (0.00, 50.24, 21.63)),
)
# Key poses found by grid search per group on scene_v2 (boss_keygrid.py, v4) (the torso and head first, then each limb):
# P leaning back against the seat's edge facing out (boss_lean_probe.py: pelvis 0.92 m out, torso 15 deg back,
# the palms on the bolsters, the right leg 0.14 stud against the rocker); H the top of the hop; S sitting on the edge;
# T1, T2 turning to face the nose with the legs coming in, the bottom still on the edge; R leaning out
# with the left palm on the door's pull at TAKE_AT (boss_reach_key.py: the least lean that reaches it).
KEYS = {
    "P": {"pelvis": (0.92, -1.22, 0.39), "torso": (15.0, 131.34, 0.0), "neck": (-15.0, 0.0, 0.0), "limbs": {"right_leg": (40.0, -35.0), "left_leg": (50.0, 35.0), "right_arm": (-120.0, -110.0), "left_arm": (-90.0, -80.0)}},
    "H": {"pelvis": (0.62, -1.38, 0.58), "torso": (-15.0, 146.34, 5.0), "neck": (-15.0, 0.0, 0.0), "limbs": {"right_leg": (70.0, 5.0), "left_leg": (70.0, 15.0), "right_arm": (-170.0, 130.0), "left_arm": (-20.0, 10.0)}},
    "S": {"pelvis": (0.61, -1.38, 0.575), "torso": (-15.0, 136.34, 10.0), "neck": (-15.0, 0.0, 0.0), "limbs": {"right_leg": (70.0, -5.0), "left_leg": (80.0, -15.0), "right_arm": (-180.0, 130.0), "left_arm": (-30.0, 20.0)}},
    "T1": {"pelvis": (0.62, -1.37, 0.575), "torso": (-15.0, 121.34, 20.0), "neck": (-15.0, 0.0, 0.0), "limbs": {"right_leg": (50.0, 65.0), "left_leg": (50.0, 45.0), "right_arm": (120.0, -130.0), "left_arm": (-50.0, 50.0)}},
    "T2": {"pelvis": (0.63, -1.35, 0.575), "torso": (5.0, 51.34, 20.0), "neck": (-15.0, 0.0, 0.0), "limbs": {"right_leg": (10.0, -75.0), "left_leg": (70.0, -5.0), "right_arm": (-10.0, -30.0), "left_arm": (-20.0, 70.0)}},
    "R": {"pelvis": (0.64, -1.30, 0.57), "torso": (0.0, 50.0, 25.0), "neck": (-10.0, 0.0, 0.0), "limbs": {"right_leg": (10.0, -75.0), "left_leg": (70.0, -5.0), "right_arm": (-10.0, -30.0), "left_arm": (27.3, -60.5)}},
}
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


def door_close_curve(b):
    """The door's openness over GetIn's close: from its stop, a short swing in as the hand arrives,
    ridden in by the hand, then its own swing shut at the SVJ curve's speed from TAKE_RELEASE."""
    b.door.at(OPEN_END + 1, (1.0,)).at(DOOR_GO, (1.0,)).at(REACH, (TAKE_AT,)).at(LET_GO, (TAKE_RELEASE,))
    times, values = zip(*SVJ_CLOSE)
    t0 = float(np.interp(-TAKE_RELEASE, [-v for v in values], times))
    for t, v in SVJ_CLOSE:
        if t > t0:
            b.door.at(LET_GO + max(1, round((t - t0) * FPS)), (v,))


def getin(b, car, s, start, ends):
    """The Boss's hop entry: side steps from the mark into the opening, turning the back to the seat;
    hands back onto the bolsters, a push-up hop onto the cushion's outboard bolster; turn to face the
    nose with the legs lifting in over the sill; lean out, the left hand takes the door's pull and
    draws it in while the body slides across into the seat; let go, and the door shuts on its own."""
    yaw_stance = car.yaw_facing(car.outboard) + STANCE_TURN
    stance, _ = feet_at(car, STANCE, yaw_stance)
    # An arc out from the car's flank, the right arm hanging in toward the body, clear of the rear quarter.
    f = walk(b, WALK0, IDLE, stance, 0.0, yaw_stance, "left_leg", pairs=4, bulge=car.outboard * np.array([1.0, 0.0, 1.0]) * car.m(WALK_ARC))
    assert f == AT_STANCE, f
    both(b, f - 1, HOP0)
    b.neck.at(WALK0 + 6, (-8, 25, 0)).at(f, (-10, 0, 0))
    b.hang("right_arm", WALK0, f - 2, IDLE_LOCAL["right_arm"] + np.array([-0.3, 0.0, 0.0]))
    b.hang("left_arm", start, f - 2)
    # Back against the seat's edge (P): the feet stay planted and the pelvis eases back, its height
    # solved from the straight legs; the hands go back onto the bolsters.
    for limb, spot in (("left_arm", BOLSTER_BACK), ("right_arm", BOLSTER_FRONT)):
        b.targets[limb].at(LEAN_BACK - 4, car.p(spot + np.array([0.08, 0.0, 0.10]))).at(LEAN_BACK, car.p(spot)).at(HOP0, car.p(spot))
        # A rigid arm cannot stay planted while the body rises: the hands come up off the bolsters with it.
        b.targets[limb].at(HOP_TOP, car.p(spot + np.array([0.04, 0.0, 0.12])))
    # Through the turn the hands stay on the bolsters, then the right one pushes on the cushion to
    # slide across and the left one goes out for the door.
    b.targets["left_arm"].at(T1 + 2, car.p(BOLSTER_BACK))
    b.targets["right_arm"].at(T1, car.p(BOLSTER_FRONT)).at(T2 + 2, car.p(CUSHION_PUSH)).at(LET_GO, car.p(CUSHION_PUSH))
    b.contact.append((LEAN_BACK - 2, LET_GO + 2))
    for name, frame in KEY_FRAMES.items():
        if name in KEYS:
            # The hands are authored below (bolsters, the door's pull); the key poses give the legs.
            limbs = [limb for limb in KEYS[name]["limbs"] if limb.endswith("leg") or (name == "R" and limb == "right_arm")]
            key_beats(b, car, frame, KEYS[name], limbs)
    for limb in ("right_leg", "left_leg"):
        b.targets[limb].at(LEAN_BACK, stance[limb]).at(HOP0, stance[limb])
    # Leaning back, the body holds still until the push (the feet are planted: easing toward the hop
    # first would tilt the rigid legs further into the rocker); the hop rises before it goes back, so
    # the torso clears the bolster's edge on its way up.
    b.pelvis.at(HOP0, car.p(KEYS["P"]["pelvis"]))
    b.torso.at(HOP0, tuple(KEYS["P"]["torso"]))
    b.pelvis.at(HOP_MID, car.p(HOP_ARC))
    # The left hand reaches out to the door's pull and rides it in.
    hook = car.riding(b, DOOR_PULL)
    b.targets["left_arm"].at(REACH - 4, car.p(DOOR_PULL + np.array([-0.10, 0.10, 0.10])))
    b.targets["left_arm"].attach(REACH, LET_GO, hook)
    # Let go, the hand comes in over the bolster, out of the closing door's way.
    b.targets["left_arm"].at(LET_GO + 3, car.p(LET_GO_HAND))
    # The body over the ride, solved per frame so the palm stays on the pull (boss_hold.py).
    for offset, pelvis, turn in RIDE:
        b.pelvis.at(REACH + offset, car.p(pelvis))
        b.torso.at(REACH + offset, turn)
    door_close_curve(b)
    b.neck_loc.at(0, (0.0, 0.0, 0.0)).at(LET_GO, (0.0, 0.0, 0.0)).at(SEATED, s["neck_loc"])
    b.pelvis.at(SEATED, s["pelvis"])
    b.torso.at(SEATED, s["torso"])
    b.neck.at(SEATED, s["neck"])
    for track, value in ((b.pelvis, s["pelvis"]), (b.torso, s["torso"]), (b.neck, s["neck"]), (b.neck_loc, s["neck_loc"])):
        track.at(END, value)
    for limb, t in ends.items():
        b.targets[limb].at(HOLD_FROM, t).at(END, t)
    hold_hand_over(b, HOLD_FROM, END)


# The exit's beats: InsideOpen, then GetOut ending at the mark's idle stance (the root jumps there
# between clips), then OutsideClose from the mark.
HAND_OVER = 18  # frames the drawn hands take to ease onto the blocky ones (Driver handOver, 0.6 s)
PUSH, PUSH_END = HAND_OVER + 8, HAND_OVER + 18  # the left palm on the armrest, the door pushed to 12 %
SEATED_AGAIN = HAND_OVER + 32  # back in the seat after the push
IO_END = HAND_OVER + 44
# GetOut: GetIn's solved path played backwards, beat for beat, from the seated pose to standing at the
# stance (car_entry_mirror.py writes its table from the entry's); then side steps back to the mark.
GO_SEATED = IO_END + 4
GO_LET_GO, GO_REACH = GO_SEATED + 14, GO_SEATED + 20
GO_T2, GO_T1, GO_SIT = GO_REACH + 8, GO_REACH + 16, GO_REACH + 24
GO_HOP_TOP, GO_HOP_MID, GO_HOP0 = GO_SIT + 4, GO_SIT + 9, GO_SIT + 13
GO_LEAN_BACK, GO_STAND = GO_HOP0 + 4, GO_HOP0 + 10
GO_WALK = GO_STAND + 2
GO_END = GO_WALK + 90  # five pairs of side steps (four left a planted foot sliding 10.6 studs/s)
MIRROR = (
    (GO_SEATED, SEATED), (GO_LET_GO, LET_GO), (GO_REACH, REACH), (GO_T2, T2), (GO_T1, T1), (GO_SIT, SIT),
    (GO_HOP_TOP, HOP_TOP), (GO_HOP_MID, HOP_MID), (GO_HOP0, HOP0), (GO_LEAN_BACK, LEAN_BACK), (GO_STAND - 1, AT_STANCE + 1),
)
EXIT_OUT = 1.3  # studs out from the mark of the stance where getting out ends (1.5 game studs at 1.15)
EXIT_HOLD = 8  # frames that stance is held


def exit_frame(entry_frame):
    """The GetOut frame that mirrors a GetIn frame between the seated pose and the stance."""
    if entry_frame < AT_STANCE + 1:
        return GO_STAND - 1 + (AT_STANCE + 1 - entry_frame)
    ex, en = zip(*MIRROR)
    return int(round(float(np.interp(-entry_frame, [-f for f in en], ex))))


def exit_timeline(car, rest_path):
    """InsideOpen: the left palm pushes the armrest's inboard face out, the door goes to 12 % and swings
    on to its stop. GetOut: GetIn the other way, from the seat out to the cushion's edge, turning to face
    out with the legs swinging over the sill, a drop off the edge onto the feet, standing up at the
    stance, side steps back to the mark. OutsideClose: steps out behind the open door, the right palm on
    the card near its rear corner draws the door in while the body backs away, lets go, and is past the
    door's sweep before it shuts; a still stance out from the car, then back to the mark."""
    s = car.seated()
    ends, _ = seated_ends(car, s, rest_path)
    yaw_seat = s["yaw"]
    yaw_stance = car.yaw_facing(car.outboard) + STANCE_TURN
    b = Body(OC_END + 1, FPS)
    for limb, angles in SEATED_ARMS.items():
        b.guess[limb] = (angles[0], angles[2])
    for track, value in ((b.pelvis, s["pelvis"]), (b.torso, s["torso"]), (b.neck, s["neck"]), (b.neck_loc, s["neck_loc"])):
        track.at(0, value)
    for limb, t in ends.items():
        b.targets[limb].at(0, t)
        b.twist[limb].at(0, (0,))
    hold_hand_over(b, 0, HAND_OVER)
    # Between the hand-over and the return to the seat the limbs keep aiming at their seated ends (held on
    # their angles, the torso's easing inboard for the push would swing them into the rim and the bolster);
    # the limb planner keeps them clear.
    b.door.at(0, (0.0,))
    # -- InsideOpen: the blocky arms hold their hand-over pose while the drawn ones ease onto it; the
    # left palm on the armrest's inboard face pushes the door from shut to 12 %, and it swings open.
    b.torso.at(HAND_OVER, s["torso"]).at(SEATED_AGAIN, s["torso"]).at(IO_END, s["torso"])
    b.neck.at(HAND_OVER, s["neck"]).at(PUSH - 2, (-10, 10, 0)).at(PUSH_END, (-10, 10, 0)).at(SEATED_AGAIN, s["neck"]).at(IO_END, s["neck"])
    for limb, t in ends.items():
        b.targets[limb].at(HAND_OVER, t)
    # Seated until the hand nears the card, then the body as solved for the push.
    b.pelvis.at(PUSH - 6, s["pelvis"])
    b.torso.at(PUSH - 6, s["torso"])
    for offset, pelvis, turn in PUSH_RIDE:
        b.pelvis.at(PUSH + offset, car.p(pelvis))
        b.torso.at(PUSH + offset, turn)
    b.targets["left_arm"].at(PUSH - 3, car.p(PUSH_PATCH + np.array([-0.06, 0.03, 0.03])))
    b.targets["left_arm"].attach(PUSH, PUSH_END, car.riding(b, PUSH_PATCH))
    b.contact.append((PUSH, PUSH_END))
    for fr, v in ((PUSH + 1, 0.0), (PUSH_END, 0.12), (PUSH_END + 8, 0.45), (PUSH_END + 16, 0.9), (PUSH_END + 20, 1.0)):
        b.door.at(fr, (v,))
    # Back from the card over the bolster's top, not through it.
    b.targets["left_arm"].at(PUSH_END + 5, car.p(PUSH_BACK)).at(PUSH_END + 10, ends["left_arm"] + car.d([0.0, 0.0, 1.0]) * car.m(0.06))
    for track, value in ((b.pelvis, s["pelvis"]), (b.neck_loc, s["neck_loc"])):
        track.at(SEATED_AGAIN, value).at(IO_END, value)
    for limb, t in ends.items():
        b.targets[limb].at(SEATED_AGAIN, t).at(IO_END, t)
    # Back in the seat the limbs hold the hand-over pose; InsideOpen ends, and GetOut starts, on it.
    hold_hand_over(b, SEATED_AGAIN, GO_SEATED)
    for track, value in ((b.pelvis, s["pelvis"]), (b.torso, s["torso"]), (b.neck, s["neck"])):
        track.at(GO_SEATED, value)
    # -- GetOut: GetIn's key poses in reverse (the table from car_entry_mirror.py replaces them).
    # The legs from the key poses while the body is on the seat's edge; leaning back (P) the feet are
    # planted at the stance below (a key's leg angles there would drag the planted soles).
    for name, frame in (("R", GO_REACH), ("T2", GO_T2), ("T1", GO_T1), ("S", GO_SIT), ("H", GO_HOP_TOP), ("P", GO_LEAN_BACK)):
        key_beats(b, car, frame, KEYS[name], [limb for limb in KEYS[name]["limbs"] if limb.endswith("leg") and name != "P"])
    b.pelvis.at(GO_HOP_MID, car.p(HOP_ARC))
    b.neck_loc.at(GO_SEATED, s["neck_loc"]).at(GO_LET_GO, (0.0, 0.0, 0.0))
    # The hands: the left one on the backrest's wing and the right one on the cushion's front bolster
    # from the edge to the drop, as on the way in.
    b.targets["right_arm"].at(GO_LET_GO, car.p(CUSHION_PUSH)).at(GO_T2 - 2, car.p(CUSHION_PUSH)).at(GO_T1, car.p(BOLSTER_FRONT)).at(GO_STAND - 6, car.p(BOLSTER_FRONT))
    b.targets["left_arm"].at(GO_LET_GO, car.p(BOLSTER_BACK + np.array([0.04, 0.0, 0.06]))).at(GO_T1 - 2, car.p(BOLSTER_BACK)).at(GO_STAND - 6, car.p(BOLSTER_BACK))
    b.contact.append((GO_LET_GO - 2, GO_STAND + 2))
    stance, stance_c = feet_at(car, STANCE, yaw_stance)
    for limb in ("right_leg", "left_leg"):
        b.targets[limb].at(GO_HOP0 - 2, stance[limb] + (0, 0.05, 0)).at(GO_HOP0, stance[limb]).at(GO_LEAN_BACK, stance[limb]).at(GO_STAND, stance[limb])
    both(b, GO_HOP0, GO_WALK)
    b.torso.at(GO_STAND, (0, yaw_stance, 0))
    b.neck.at(GO_STAND, (-10, 0, 0))
    b.hang("right_arm", GO_STAND - 2, GO_END, IDLE_LOCAL["right_arm"] + np.array([-0.3, 0.0, 0.0]))
    b.hang("left_arm", GO_STAND - 2, GO_END)
    bulge = car.outboard * np.array([1.0, 0.0, 1.0]) * car.m(WALK_ARC)
    f = walk(b, GO_WALK, stance, {k: IDLE[k] for k in stance}, yaw_stance, 0.0, "right_leg", pairs=5, bulge=bulge)
    assert f == GO_END, f
    both(b, f - 1, GO_END + 1)
    b.pelvis.at(GO_STAND, (stance_c[0], 2.0, stance_c[2])).at(GO_END, IDLE_PELVIS)
    b.torso.at(GO_END, (0, 0, 0))
    b.neck.at(GO_END, (0, 0, 0))
    for limb in ("right_leg", "left_leg"):
        b.targets[limb].at(GO_END, IDLE[limb])
    b.door.at(GO_END, (1.0,))
    # -- OutsideClose: side steps out round the open door's rear end to its outer side, the right palm
    # flat on the skin near its rear edge pushes the door away, lets go, and the door swings shut away from
    # the body; a still stance out from the car (exitEnd), then back to the mark. (Pulled from behind, as
    # on the DR458, the long door's rear edge swings through where the body stands: a rigid R6 arm
    # reaches its card only from inside the sweep.)
    yaw_push = PUSH_YAW
    push_feet, push_c = feet_at(car, PUSH_AT, yaw_push)
    arc = car.outboard * np.array([1.0, 0.0, 1.0]) * car.m(CLOSE_ARC)
    f = walk(b, GO_END + 1, {k: IDLE[k] for k in push_feet}, push_feet, 0.0, yaw_push, "right_leg", pairs=CLOSE_PAIRS, bulge=arc)
    b.pelvis.at(GO_END + 1, IDLE_PELVIS).at(f, (push_c[0], 2.0, push_c[2]))
    b.torso.at(f, (0, yaw_push, 0))
    push, release = f + 2, f + 2 + CLOSE_PUSH_FRAMES
    assert (push, release) == (CLOSE_PULL, CLOSE_RELEASE), (push, release)
    both(b, f - 1, release + 18)
    palm = CLOSE_PALM
    b.hang("right_arm", GO_END, push - 10)
    b.targets["right_arm"].at(push - 5, car.p(car_point_at_door(car, palm + np.array([0.25, 0.0, 0.0]), 1.0)))
    b.targets["right_arm"].attach(push, release, car.riding(b, palm))
    b.contact.append((push, release))
    for offset, pelvis, turn in CLOSE_RIDE:
        b.pelvis.at(push + offset, car.p(pelvis))
        b.torso.at(push + offset, turn)
    for fr, v in ((push, 1.0), (release, CLOSE_LET_GO), (release + 8, 0.6), (release + 16, 0.25), (release + 22, 0.04), (release + 24, 0.0)):
        b.door.at(fr, (v,))
    b.targets["right_arm"].at(release + 4, car.p(car_point_at_door(car, palm + np.array([0.20, 0.0, -0.10]), CLOSE_LET_GO)))
    b.hang("right_arm", release + 10, OC_END)
    # Facing the door, the left arm swings a little out and back, clear of the door's skin on that side
    # (the arm at (-30, -40) degrees: hanging straight it is 0.15-0.2 stud into the door as it starts to
    # move, crossed before the hips 0.08 as the body follows the push, at (-20, -40) 0.07 on the release).
    b.hang("left_arm", GO_END, push - 12)
    b.hang("left_arm", push - 6, release + 12, np.array([-2.151, -0.093, 0.632]))
    b.hang("left_arm", release + 20, OC_END)
    rest_at = release + 18
    b.torso.at(release + 10, (0, yaw_push, 0)).at(rest_at, (0, yaw_push, 0))
    b.pelvis.at(release + 10, (push_c[0], 2.0, push_c[2])).at(rest_at, (push_c[0], 2.0, push_c[2]))
    b.neck.at(push - 6, (-10, 0, 0)).at(release + 10, (-5, 10, 0)).at(rest_at, (0, 0, 0))
    # Back toward the mark, turning to its heading, and a still stance out from the car (exitEnd);
    # then the last steps in to the mark.
    stance_out = {k: IDLE[k] + np.array([0.0, 0.0, EXIT_OUT]) for k in push_feet}
    f = walk(b, rest_at + 1, push_feet, stance_out, yaw_push, 0.0, "left_leg", pairs=CLOSE_PAIRS_BACK)
    both(b, f - 1, f + EXIT_HOLD)
    b.torso.at(f - 1, (0, 0, 0)).at(f + EXIT_HOLD, (0, 0, 0))
    f = walk(b, f + EXIT_HOLD, stance_out, {k: IDLE[k] for k in push_feet}, 0.0, 0.0, "left_leg", pairs=2)
    assert f <= OC_END, f
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
    print(f"exit: InsideOpen ..f{IO_END}, GetOut ..f{GO_END}, OutsideClose ..f{OC_END}, push f{push}-f{release}, still f{rest_at}, at the mark f{f}")
    return b, clips


# OutsideClose: the walk round the open door's rear end to its outer side (boss_close_key.py: the right
# palm reaches the skin near the rear edge, torso and head clear of the door from 1 down to 0.7, the arm
# 0.09 into it), the push, the walk back out to exitEnd and in to the mark.
PUSH_AT = np.array([1.885, -1.665])  # the stance on the door's outer side, car x, y
PUSH_YAW = -120.0  # facing the open door's skin
# The palm on the door's skin near its rear edge (the skin at x 0.898 there, door shut), an end-face
# distance off it.
CLOSE_PALM = np.array([0.94, -0.70, 0.85])
CLOSE_ARC = 0.75  # metres the walk arcs out, round the open door's rear edge (1.93 m out at its stop)
# Seven and five pairs of side steps: with fewer, each step is too long for a rigid leg and a planted foot
# slides (10-13 studs/s at five and four out, 9.4 at five back).
CLOSE_PAIRS, CLOSE_PAIRS_BACK = 7, 6
CLOSE_PUSH_FRAMES = 6  # at four, the body following the door slid the planted feet 0.67 studs/s
# The door's openness where the palm leaves it: a short push, the feet planted (pushed to 0.85 the body
# had to slide 16 cm toward the door to keep the rigid arm's palm on it).
CLOSE_LET_GO = 0.93
CLOSE_PULL = GO_END + 1 + 9 * 2 * CLOSE_PAIRS + 2  # the push starts two frames after the walk
CLOSE_RELEASE = CLOSE_PULL + CLOSE_PUSH_FRAMES
OC_END = CLOSE_RELEASE + 18 + 1 + 9 * 2 * CLOSE_PAIRS_BACK + EXIT_HOLD + 36 + 2
# The body over the push (offset from CLOSE_PULL, pelvis car metres, (lean, yaw, roll)), solved by
# boss_hold.py with the right palm on the skin (misses <= 0.005 stud, the arm <= 0.101 into the door).
CLOSE_RIDE = (
    (0, (1.8861, -1.6670, 0.4290), (0.0, -120.0, 0.0)),
    (1, (1.8849, -1.6641, 0.4300), (0.0, -120.0, 0.0)),
    (2, (1.8815, -1.6562, 0.4328), (0.0, -120.0, 0.0)),
    (3, (1.8762, -1.6440, 0.4368), (0.0, -120.0, 0.0)),
    (4, (1.8698, -1.6281, 0.4410), (0.0, -120.0, 0.0)),
    (5, (1.8640, -1.6086, 0.4433), (0.0, -120.0, 0.0)),
    (6, (1.8574, -1.5877, 0.4457), (0.0, -120.0, 0.0)),
)
# The body over InsideOpen's push (frame offset from PUSH, pelvis car metres, (lean, yaw, roll)), solved
# by boss_hold.py with the left palm on PUSH_PATCH (misses <= 0.01 stud, the arm 0.30-0.37 into the
# door card): the body eases a few centimetres inboard, away from the card, as the rigid arm pushes.
PUSH_RIDE = (
    (0, (0.3147, -1.2013, 0.5994), (13.65, 51.34, 0.0)),
    (1, (0.3157, -1.2023, 0.6008), (13.89, 51.34, 0.0)),
    (2, (0.3160, -1.2022, 0.6007), (13.77, 51.34, 0.0)),
    (3, (0.3161, -1.2021, 0.6008), (13.34, 51.34, 0.0)),
    (4, (0.3188, -1.1949, 0.5931), (12.50, 51.34, 0.0)),
    (5, (0.3192, -1.1941, 0.5920), (11.56, 51.34, 0.0)),
    (6, (0.3207, -1.1959, 0.5926), (10.46, 51.34, 0.0)),
    (7, (0.3289, -1.1891, 0.5840), (10.00, 51.34, 0.0)),
    (8, (0.3388, -1.1827, 0.5801), (9.28, 51.34, 0.0)),
    (9, (0.3489, -1.1767, 0.5733), (8.82, 51.34, 0.0)),
    (10, (0.3578, -1.1695, 0.5670), (7.67, 51.34, 0.0)),
)


def car_point_at_door(car, point, openness):
    """A door point (car metres, door shut) where the door puts it at `openness`, car metres."""
    a = car.door_at(point, openness)
    inv = np.linalg.inv(car.a)
    seat = a @ inv[:3, :3].T + inv[:3, 3]
    return H_POINT + TO_SEAT @ (seat * STUD)


ARMS = ["Right Arm", "Left Arm"]
LEGS = ["Right Leg", "Left Leg"]


def seated_contacts_from(start, end):
    """The seated hand-over pose's contacts: the decided seated pose's torso, and the blocky limbs on
    their hand-over angles (SEATED_ARMS, SEATED_LEGS) at the depths measured."""
    return [
        {"why": "DECIDED (owner: torso 15 deg, scale 1.15, the seat moved 11 cm): the torso's side into the backrest's inboard wing, 5.85 cm seated", "from": start, "to": end, "parts": ["Torso"], "groups": ["seat"], "depth": 0.2727},
        {"why": "DECIDED (coordinator, as the DR458's decision B): the right blocky arm at its hand-over pose against the seat's bolster", "from": start, "to": end, "parts": ["Right Arm"], "groups": ["seat"], "depth": 0.0977},
        {"why": "DECIDED (coordinator, as the DR458's left arm): the left blocky arm at its hand-over pose between the seat's bolster and the door card", "from": start, "to": end, "parts": ["Left Arm"], "groups": ["seat", "door"], "depth": 0.2996},
        {"why": "DECIDED (coordinator, as the DR458's blocky legs): the blocky legs at their least-deep pose on the cushion, under the wheel's rim, the left one against the door card", "from": start, "to": end, "parts": LEGS, "groups": ["seat", "wheel", "door", "cabin"], "depth": 0.1630},
    ]


# The last frames before the limbs hold their hand-over pose, as the body lands in the seat.
SETTLE = (HOLD_FROM - 5, HOLD_FROM + 1)


def settle_contacts():
    """The settle into the hand-over pose: the limbs reach their held angles as the body lands, a few
    frames of squash into the cushion. No pose of the entry's polish clears it; named at the depths
    measured, rounded up at the fourth decimal (coordinator's decision, option a, as the DR458's)."""
    why = "DECIDED (coordinator, option a): the settle into the hand-over pose as the body lands, "
    return [
        {"why": why + "the left leg into the cushion", "from": SETTLE[0], "to": SETTLE[1], "parts": ["Left Leg"], "groups": ["seat"], "depth": 0.3078},
        {"why": why + "the left leg against the lower dash", "from": SETTLE[0], "to": SETTLE[1], "parts": ["Left Leg"], "groups": ["cabin"], "depth": 0.1215},
        {"why": why + "the left leg by the rim, the door card and the sill's body", "from": SETTLE[0], "to": SETTLE[1], "parts": ["Left Leg"], "groups": ["wheel", "door", "body"], "depth": 0.0488},
        {"why": why + "the right leg into the cushion", "from": SETTLE[0], "to": SETTLE[1], "parts": ["Right Leg"], "groups": ["seat"], "depth": 0.186},
        {"why": why + "the right leg under the rim and the lower dash", "from": SETTLE[0], "to": SETTLE[1], "parts": ["Right Leg"], "groups": ["wheel", "cabin"], "depth": 0.0997},
        {"why": why + "the left arm against the door card", "from": SETTLE[0], "to": SETTLE[1], "parts": ["Left Arm"], "groups": ["door"], "depth": 0.1031},
        {"why": why + "the left arm into the bolster", "from": SETTLE[0], "to": SETTLE[1], "parts": ["Left Arm"], "groups": ["seat"], "depth": 0.279},
        {"why": why + "the right arm into the bolster", "from": SETTLE[0], "to": SETTLE[1], "parts": ["Right Arm"], "groups": ["seat"], "depth": 0.0909},
        {"why": why + "the torso into the cushion", "from": SETTLE[0], "to": SETTLE[1], "parts": ["Torso"], "groups": ["seat"], "depth": 0.2657},
    ]


def entry_contacts():
    """Named contacts (depth, studs at scale 1) and held limbs, for car_entry_clear.py; the check's
    allow file is written from the same list at the measured depths."""
    allow = [
        {"why": "DECIDED (coordinator): the right hand on the door's pull bar, arriving in the pocket and pulling, the body leaning in so the rigid arm keeps the bar (its arm lies on the skin around the pocket)", "from": PULL - 2, "to": PULL + 4, "parts": ["Right Arm"], "groups": ["door"], "depth": 0.1912},
        {"why": "DECIDED (coordinator): the palms on the bolsters pushing up for the hop, the rigid arms' boxes into the bolsters' foam", "from": LEAN_BACK - 2, "to": HOP_TOP + 4, "parts": ARMS, "groups": ["seat"], "depth": 0.3471},
        {"why": "DECIDED (coordinator): leaning back to the seat's edge with the feet planted, the rigid right leg against the rocker (boss_lean_probe.py: the trade with the palms' reach)", "from": AT_STANCE, "to": HOP0 + 2, "parts": LEGS, "groups": ["body", "sill"], "depth": 0.14},
        {"why": "DECIDED (coordinator, rigid-thigh class): thighs over the sill while the legs lift in", "from": HOP0, "to": REACH, "parts": LEGS, "groups": ["sill"], "depth": 0.2345},
        {"why": "DECIDED (coordinator, rigid-thigh class): thighs over the bolster and the cushion's edge while the body turns and slides across", "from": HOP_TOP - 2, "to": SETTLE[0] - 1, "parts": LEGS, "groups": ["seat"], "depth": 0.1973},
        {"why": "DECIDED (coordinator): the bottom landing on the cushion's outboard bolster and sliding across it", "from": HOP_TOP - 2, "to": SETTLE[0] - 1, "parts": ["Torso"], "groups": ["seat"], "depth": 0.1569},
        {"why": "DECIDED (coordinator, decision A): the left palm on the door's pull, drawing the door in", "from": REACH, "to": LET_GO, "parts": ["Left Arm"], "groups": ["door"], "depth": 0.3137},
    ] + settle_contacts() + seated_contacts_from(HOLD_FROM, END) + [
        # A hand "on" a surface must reach it (within 0.1 stud of its end), not push on air.
        {"why": "the right hand on the pull bar: must touch", "from": PULL, "to": PULL + 4, "parts": ["Right Arm"], "groups": ["door"], "touch": 0.1},
        {"why": "the palms on the bolsters for the push: must touch", "from": LEAN_BACK, "to": HOP0, "parts": ARMS, "groups": ["seat"], "touch": 0.1},
        {"why": "the left palm on the door's pull: must touch", "from": REACH, "to": LET_GO, "parts": ["Left Arm"], "groups": ["door"], "touch": 0.1},
    ]
    holds = [
        {"from": WALK0, "to": HOP0, "limb": "right_leg"},
        {"from": WALK0, "to": HOP0, "limb": "left_leg"},
        # The palms stay on the bolsters for the push and on the door's pull through the ride.
        {"from": LEAN_BACK, "to": HOP0, "limb": "right_arm"},
        {"from": LEAN_BACK, "to": HOP0, "limb": "left_arm"},
        {"from": REACH, "to": LET_GO, "limb": "left_arm"},
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
        # A pose the choreography holds (hold_hand_over) wins over the search's angles.
        for limb, (x, z) in row.get("angles", {}).items():
            b.fixed.setdefault(limb, {}).setdefault(f, (x, z))


def inside_open_start():
    """InsideOpen's first frames, as the left hand leaves the hand-over pose for the card and the body
    begins to ease inboard: named at the depths measured (coordinator's decision, the DR458's class of
    the left arm sliding along the door card from the hand-over pose to the push)."""
    why = "DECIDED (coordinator, the DR458's class): InsideOpen's start, the hand leaving the hand-over pose for the card as the body eases inboard, "
    start, end = HAND_OVER, PUSH - 1
    return [
        {"why": why + "the left arm along the door card and the bolster", "from": start, "to": end, "parts": ["Left Arm"], "groups": ["door"], "depth": 0.3294},
        {"why": why + "the left arm against the bolster", "from": start, "to": end, "parts": ["Left Arm"], "groups": ["seat"], "depth": 0.3002},
        {"why": why + "the left leg against the door card", "from": start, "to": end, "parts": ["Left Leg"], "groups": ["door"], "depth": 0.2138},
        {"why": why + "the left leg under the wheel's rim", "from": start, "to": end, "parts": ["Left Leg"], "groups": ["wheel"], "depth": 0.1959},
        {"why": why + "the right arm against the bolster", "from": start, "to": end, "parts": ["Right Arm"], "groups": ["seat"], "depth": 0.1764},
        {"why": why + "the right leg under the wheel's rim", "from": start, "to": end, "parts": ["Right Leg"], "groups": ["wheel"], "depth": 0.1601},
        {"why": why + "the torso into the backrest's wing", "from": start, "to": end, "parts": ["Torso"], "groups": ["seat"], "depth": 0.3049},
    ]


def exit_contacts():
    """The exit's named contacts and held limbs: GetIn's between the stance and the seat at their
    mirrored GetOut frames (the same depths; the door ride has no counterpart, the door stays open),
    and InsideOpen's and OutsideClose's own."""
    entry_allow, _ = entry_contacts()
    mirrored = []
    for e in entry_allow:
        if e["to"] < AT_STANCE or e["from"] > SEATED or "door's pull" in e["why"] or "pull bar" in e["why"]:
            continue
        start, end = exit_frame(min(e["to"], SEATED)), exit_frame(max(e["from"], AT_STANCE))
        mirrored.append({**e, "why": "GetIn's, mirrored: " + e["why"], "from": start, "to": end})
    allow = [
        {"why": "DECIDED (coordinator): the left palm on the door card's insert pushing the door from shut to 12 %, the arm along the card (boss_hold.py: 0.30-0.37)", "from": PUSH - 2, "to": PUSH_END, "parts": ["Left Arm"], "groups": ["door"], "depth": 0.37},
        {"why": "DECIDED (coordinator): the torso's side deeper into the backrest's inboard wing than seated, as the body eases inboard for the push (boss_hold.py)", "from": PUSH - 6, "to": SEATED_AGAIN, "parts": ["Torso"], "groups": ["seat"], "depth": 0.31},
        {"why": "DECIDED (coordinator): the right palm flat on the door's skin near its rear edge, pushing the door shut from its outer side", "from": CLOSE_PULL - 2, "to": CLOSE_RELEASE + 2, "parts": ["Right Arm"], "groups": ["door"], "depth": 0.13},
    ] + seated_contacts_from(0, GO_SEATED) + mirrored + inside_open_start() + [
        {"why": "DECIDED (coordinator): the entry's settle, mirrored as the body rises, the left arm by the wheel's rim", "from": exit_frame(SETTLE[1]), "to": exit_frame(SETTLE[0]), "parts": ["Left Arm"], "groups": ["wheel"], "depth": 0.0501},
        # Getting out, the hands come down onto the bolsters as the body drops off the seat's edge.
        {"why": "DECIDED (coordinator, option A): the left arm into the backrest's wing as the hand comes down onto it in the drop", "from": GO_HOP_TOP - 3, "to": GO_HOP0 - 4, "parts": ["Left Arm"], "groups": ["seat"], "depth": 0.3969},
        {"why": "DECIDED (coordinator, option A): the right arm against the lower dash and the body as the hand comes down onto the cushion's bolster in the drop", "from": GO_HOP_TOP - 3, "to": GO_HOP0 - 4, "parts": ["Right Arm"], "groups": ["cabin", "body"], "depth": 0.0564},
    ] + [
        {"why": "the left palm on the door card's insert, pushing: must touch", "from": PUSH, "to": PUSH_END, "parts": ["Left Arm"], "groups": ["door"], "touch": 0.1},
        {"why": "the right palm on the door's skin near its rear edge, pushing: must touch", "from": CLOSE_PULL, "to": CLOSE_RELEASE, "parts": ["Right Arm"], "groups": ["door"], "touch": 0.1},
    ]
    holds = [
        {"from": PUSH, "to": PUSH_END, "limb": "left_arm"},
        # Held from four frames before the feet land, so the rigid arms are on the bolsters as they do.
        {"from": GO_HOP0 - 4, "to": GO_LEAN_BACK, "limb": "right_arm"},
        {"from": GO_HOP0 - 4, "to": GO_LEAN_BACK, "limb": "left_arm"},
        {"from": GO_HOP0, "to": OC_END, "limb": "right_leg"},
        {"from": GO_HOP0, "to": OC_END, "limb": "left_leg"},
        {"from": 0, "to": 6, "limb": "right_arm"},
        {"from": 0, "to": 6, "limb": "left_arm"},
    ]
    return allow, holds


CLOSE_LEAD = 8  # InsideClose: frames seated before the door starts to swing
CLOSE_END = CLOSE_LEAD + round(SVJ_CLOSE[-1][0] * FPS) + 8


def close_timeline(car, rest_path):
    """InsideClose: seated on the hand-over pose (the drawn hands are what shows), the door swings
    shut on its own on the SVJ's close curve, as at the end of GetIn (decision E1')."""
    s = car.seated()
    ends, _ = seated_ends(car, s, rest_path)
    b = Body(CLOSE_END + 1, FPS)
    for track, value in ((b.pelvis, s["pelvis"]), (b.torso, s["torso"]), (b.neck, s["neck"]), (b.neck_loc, s["neck_loc"])):
        track.at(0, value).at(CLOSE_END, value)
    for limb, t in ends.items():
        b.targets[limb].at(0, t).at(CLOSE_END, t)
        b.twist[limb].at(0, (0,))
    hold_hand_over(b, 0, CLOSE_END)
    b.door.at(0, (1.0,))
    for t, v in SVJ_CLOSE:
        b.door.at(CLOSE_LEAD + round(t * FPS), (v,))
    b.door.at(CLOSE_END, (0.0,))
    return b, [{"name": "InsideClose", "start": 0, "end": CLOSE_END}]


def close_contacts():
    """InsideClose's named contacts: the seated hand-over pose's."""
    return seated_contacts_from(0, CLOSE_END), []


SEATED_END = FPS  # SeatedPose: one second, looped


def seated_timeline(car, rest_path):
    """SeatedPose: the seated hand-over pose held, door shut: what GetIn ends on and InsideClose,
    InsideOpen and GetOut start from, so CarEntry's loop between them shows no change."""
    s = car.seated()
    ends, _ = seated_ends(car, s, rest_path)
    b = Body(SEATED_END + 1, FPS)
    for track, value in ((b.pelvis, s["pelvis"]), (b.torso, s["torso"]), (b.neck, s["neck"]), (b.neck_loc, s["neck_loc"])):
        track.at(0, value).at(SEATED_END, value)
    for limb, t in ends.items():
        b.targets[limb].at(0, t).at(SEATED_END, t)
        b.twist[limb].at(0, (0,))
    hold_hand_over(b, 0, SEATED_END)
    b.door.at(0, (0.0,)).at(SEATED_END, (0.0,))
    return b, [{"name": "SeatedPose", "start": 0, "end": SEATED_END}]


def seated_contacts():
    """SeatedPose's named contacts: InsideClose's, decided, the door shut throughout."""
    allow = [{**e, "to": SEATED_END} for e in close_contacts()[0]]
    return allow, []


def timeline(car, rest, which):
    """(body, clips) of the entry, the exit, the inside close or the seated pose timeline."""
    if which == "exit":
        return exit_timeline(car, rest)
    if which == "close":
        return close_timeline(car, rest)
    if which == "seated":
        return seated_timeline(car, rest)
    b, s, yaw_out, yaw_seat, (o0, o1, total) = entry(car, rest)
    return b, [{"name": "OutsideOpen", "start": o0, "end": o1}, {"name": "GetIn", "start": o1, "end": total - 1}]


def build(argv):
    """For car_entry_clear.py: <scene> <seated pose> <rest pose> [--timeline entry|exit|close|seated]
    [--clear table.json]."""
    scene, pose, rest = argv[:3]
    which = argv[argv.index("--timeline") + 1] if "--timeline" in argv else "entry"
    b, _ = timeline(Car(scene, pose), rest, which)
    if "--clear" in argv:
        apply_table(b, argv[argv.index("--clear") + 1])
    allow, holds = {"exit": exit_contacts, "close": close_contacts, "seated": seated_contacts}.get(which, entry_contacts)()
    return b, allow, holds


def main(argv):
    """<scene> <seated pose> <rest pose> <out dir> [--timeline entry|exit|close|seated] [--clear table.json]"""
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
