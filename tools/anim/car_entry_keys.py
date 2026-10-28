"""
Keys for getting in and out of the SVJ, one continuous timeline per direction, cut into the
clips CarEntry plays (games/drive-lab/src/shared/Config/CarEntry.luau):

  entry:  OutsideOpen | GetIn | InsideClose        (the door shut at the start)
  exit:   InsideOpen  | GetOut | OutsideClose

Consecutive clips are cut from one timeline, so they meet on the same pose by construction.
Authored in the AUTHORING frame of tools/anim/car_entry_prep.py: the door mark's standing root at
(0, 3, 0) facing -Z, the world divided by the driver's scale, ground y = 0. Car forward is -X,
into the car is -Z; seated, the body faces -X (yaw -270, reached by turning right).

The technique is the real one for this car and this body (docs/pipelines/CAR_ENTRY_ANIMATION.md):
outside, the fingers find the release in the recess at the door's upper rear and lift the door
skyward; getting in, the back turns to the car, the bottom perches on the edge of the wide sill,
the legs lift and swing over it, and a push of both hands hoists the body onto the seat (Roblox's
upright sit, which floats above this car's low cushion); inside, the strap on the door pulls it
down. Getting out: a hand pushes the door up, the body slides to the sill's edge, the legs swing
out, the feet find the ground, a push off the sill stands it up, it turns to face the car and pulls
the door down by its edge.

  python car_entry_keys.py <scene.npz> <SEAT_WELD.json> <REST_POSE.json> <door.json> <out_dir>

Writes entry.keys.json, exit.keys.json, seated.keys.json and their solved previews (*.fk.json).
"""
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r6_fk  # noqa: E402
from beat_tracks import Body, write  # noqa: E402
from car_scene import rotation_about  # noqa: E402

FPS = 30
SEATED_YAW = -270.0
# The palm against each door contact, off the surface toward the body (shut door, authoring
# frame): the outer skin faces out (+Z), the door card faces the cabin (-Z), the lower corner is
# taken from below.
PALM_OFF = {"release": (0, 0, 0.42), "strap": (0, 0, -0.42), "low_corner": (0, -0.42, 0)}
# Agent B's loop strap on the door card (#31): 25 cm, in studs of the 1.5x world.
STRAP_LENGTH = 0.25 * 1.5 / 0.28
# Shoulder joint to palm (r6_fk.HAND) of a scale-1 R6 arm, which is rigid: 1.44 studs.
ARM_REACH = float(np.linalg.norm(np.array(r6_fk.HAND) - np.array([0.5, 0.5, 0.0])))


class Car:
    """Landmarks in the authoring frame, all derived from measured files."""

    def __init__(self, scene_path, seat_path, rest_path, door_path):
        d = np.load(scene_path, allow_pickle=False)
        self.a = d["seat_to_authoring"]
        self.scale = float(d["scale"])
        seat = json.load(open(seat_path, encoding="utf-8"))
        rest = json.load(open(rest_path, encoding="utf-8"))
        self.door_spec = json.load(open(door_path, encoding="utf-8"))
        sit = seat["robloxSit"]["pointsInSeat"]
        self.seated_root = self.p(sit["rootCentre"])
        self.seated_pelvis = self.seated_root - np.array([0.0, 1.0, 0.0])
        self.left_shoulder = self.p(sit["leftShoulder"])
        self.rest_arm_end = {side: self.p(rest[side]["blockyArmEnd"]) for side in ("right", "left")}
        studs = 1.5 / 0.28
        self.knee = {
            side: self.p(np.array(rest[side]["check"]["kneeMetres"]) * studs) for side in ("right", "left")
        }
        hinge = self.door_spec["hinge"]
        self.hinge_pivot = np.asarray(hinge["pivot"], dtype=float)
        self.hinge_axis = np.asarray(hinge["axis"], dtype=float)
        self.open_angle = math.radians(hinge["openDegrees"])
        self.door_points = {k: np.asarray(v, dtype=float) for k, v in self.door_spec["points"].items()}
        self.door_track = None

    def p(self, seat_point):
        v = np.asarray(seat_point, dtype=float)
        return self.a[:3, :3] @ v + self.a[:3, 3]

    def door_at(self, name, openness):
        """A point of the shut door, carried by the door at `openness`. Where a hand holds it,
        the point stands off the surface by the arm's half thickness (PALM_OFF, in the shut door's
        frame), so the arm's box ends on the surface instead of half through it."""
        r = rotation_about(self.hinge_axis, openness * self.open_angle)[:3, :3]
        point = self.door_points[name] + np.asarray(PALM_OFF.get(name, (0, 0, 0)), dtype=float)
        return self.hinge_pivot + r @ (point - self.hinge_pivot)

    def strap_grab(self, openness):
        """Where the hand holds agent B's 25 cm loop strap (#31). An R6 arm has no elbow: its palm
        is always ARM_REACH from the shoulder joint. So the hand holds the strap where that sphere
        meets the line from the seated left shoulder to the strap's anchor on the door card; the
        strap runs taut from the anchor to the hand (never longer than it is: at the shut door it
        needs 1.6 cm more, which a lean of the torso gives)."""
        anchor = self.door_at("strap_anchor", openness)
        towards = anchor - self.left_shoulder
        return self.left_shoulder + ARM_REACH * towards / np.linalg.norm(towards)

    def riding_strap(self):
        def at(frame):
            return self.strap_grab(float(self.door_track.sample(np.array([frame]))[0, 0]))

        return at

    def riding(self, name):
        """A beat value that rides a door point on the timeline's own door track."""

        def at(frame):
            openness = float(self.door_track.sample(np.array([frame]))[0, 0])
            return self.door_at(name, openness)

        return at


def rest_pose():
    return {name: ((0, 0, 0), (0, 0, 0)) for name in r6_fk.ORDER}


def idle_targets():
    parts = r6_fk.pose_parts(rest_pose())
    return {
        "right_arm": r6_fk.point(parts["Right Arm"], r6_fk.HAND),
        "left_arm": r6_fk.point(parts["Left Arm"], r6_fk.HAND),
        "right_leg": r6_fk.point(parts["Right Leg"], r6_fk.FOOT),
        "left_leg": r6_fk.point(parts["Left Leg"], r6_fk.FOOT),
    }


IDLE = idle_targets()
IDLE_PELVIS = np.array([0.0, 2.0, 0.0])
V = np.array


def seated_targets(car):
    """The SEATED pose's limb targets: blocky arms aimed the way REST_POSE.json aims them (the arm's
    end, 1.5 studs from the shoulder joint along the arm, on blockyArmEnd), legs along the custom
    legs' thighs toward the knees, tipped a little down toward the pedals."""
    torso_rot = (0.0, SEATED_YAW, 0.0)
    pose = {"RootJoint": (torso_rot, tuple(car.seated_root - np.array([0, r6_fk.ROOT_HEIGHT, 0])))}
    pose["Neck"] = ((0, 0, 0), (0, 0, 0))
    out = {}
    for limb, side, end_x in (("right_arm", "right", -0.5), ("left_arm", "left", 0.5)):
        angles, _ = r6_fk.aim(pose, limb, car.rest_arm_end[side], (end_x, -1.0, 0.0), guess=(60, 0))
        pose[r6_fk.LIMB_JOINT[limb]] = (angles, (0, 0, 0))
        part = r6_fk.pose_parts(pose)[r6_fk.JOINTS[r6_fk.LIMB_JOINT[limb]][1]]
        out[limb] = r6_fk.point(part, r6_fk.HAND)
    torso = r6_fk.pose_parts(pose)["Torso"]
    for limb, side in (("right_leg", "right"), ("left_leg", "left")):
        joint = r6_fk.point(torso, (0.5 if side == "right" else -0.5, -1, 0))
        direction = car.knee[side] - joint
        direction[1] -= 0.25 * np.linalg.norm(direction)
        if side == "right":
            # The custom right knee tucks between the column and the console; the blocky leg
            # (hidden once seated) points straight ahead instead, clear of both.
            direction[2] = 0.0
        out[limb] = joint + 2.0 * direction / np.linalg.norm(direction)
    return torso_rot, out


def start_idle(b, frame):
    b.pelvis.at(frame, IDLE_PELVIS)
    b.torso.at(frame, (0, 0, 0))
    b.neck.at(frame, (0, 0, 0))
    for limb in IDLE:
        b.targets[limb].at(frame, IDLE[limb])
        b.twist[limb].at(frame, (0,))


def start_seated(b, car, frame, seat):
    rot, targets = seat
    b.pelvis.at(frame, car.seated_pelvis)
    b.torso.at(frame, rot)
    b.neck.at(frame, (0, 0, 0))
    for limb in targets:
        b.targets[limb].at(frame, targets[limb])
        b.twist[limb].at(frame, (0,))


def side_step(b, limb, start, end, frm, to, lift=0.24):
    """One step of `limb` from `frm` to `to` over start..end, the other leg supporting: the foot
    leaves and lands vertically, the stepping hip hikes so a rigid leg can clear the ground."""
    other = "left_leg" if limb == "right_leg" else "right_leg"
    frm, to = V(frm), V(to)
    b.support.append((start, end - 1, [other]))
    b.targets[limb].at(start, frm).at(start + (end - start) // 3, frm * 0.7 + to * 0.3 + (0, lift, 0))
    b.targets[limb].at(end - (end - start) // 3, frm * 0.2 + to * 0.8 + (0, lift, 0)).at(end, to)


def walk_steps(b, start, pairs, frm_r, frm_l, to_r, to_l, lead="left_leg", per=8, roll=6.0, yaw=0.0):
    """Side steps from one stance to another, `pairs` pairs, the leading foot first; the pelvis
    rides between the feet and the hips hike a few degrees for the stepping leg. Returns the frame
    the last step lands."""
    both = ["right_leg", "left_leg"]
    trail = "right_leg" if lead == "left_leg" else "left_leg"
    frm = {"right_leg": V(frm_r), "left_leg": V(frm_l)}
    to = {"right_leg": V(to_r), "left_leg": V(to_l)}
    f = start
    for k in range(pairs):
        for limb in (lead, trail):
            a = frm[limb] + (to[limb] - frm[limb]) * k / pairs
            z = frm[limb] + (to[limb] - frm[limb]) * (k + 1) / pairs
            side_step(b, limb, f, f + per - 1, a, z)
            sign = 1.0 if limb == "right_leg" else -1.0
            b.torso.at(f + per // 2, (-1, yaw, sign * roll))
            b.support.append((f + per - 1, f + per - 1, both))
            r = frm["right_leg"] + (to["right_leg"] - frm["right_leg"]) * ((k + (1 if limb == trail else 0.5)) / pairs)
            l_ = frm["left_leg"] + (to["left_leg"] - frm["left_leg"]) * ((k + (1 if limb == trail else 0.5)) / pairs)
            mid = (r + l_) / 2
            b.pelvis.at(f + per - 1, (mid[0], 2.0, mid[2]))
            f += per
    b.torso.at(f, (0, yaw, 0))
    return f


def outside_open(b, car, s, e):
    """Idle at the mark: two steps up to the door's rear, the fingers into the release at the top
    of the recess, a press, the door lifted as far as the arm goes; the struts carry it up and out,
    the body stepping back out of its sweep, then back to the mark."""
    both = ["right_leg", "left_leg"]
    home_r, home_l = IDLE["right_leg"] * V([1, 0, 1]), IDLE["left_leg"] * V([1, 0, 1])
    release = car.door_at("release", 0.0)
    px = float(release[0]) - 1.0
    near = V([px, 2.0, -1.05])
    near_r, near_l = V([px + 0.5, 0, -1.05]), V([px - 0.5, 0, -1.05])
    back = 1.5  # out of the door's sweep: its lower edge swings out ~0.9 here at 30-50 % open
    back_r, back_l = V([px + 0.5, 0, back]), V([px - 0.5, 0, back])
    b.door.at(s, (0,))
    b.support.append((s, s + 5, both))
    b.pelvis.at(s + 5, IDLE_PELVIS + (-0.08, 0, 0))
    b.neck.at(s + 5, (-4, -38, 0))
    b.hang("left_arm", s + 2, e - 2, (-1.5, -0.9, 0.05))
    b.hang("right_arm", s + 2, s + 12, (1.5, -0.9, 0.0))
    f = walk_steps(b, s + 6, 1, home_r, home_l, near_r, near_l, lead="right_leg", per=9)
    b.support.append((f, s + 41, both))
    b.pelvis.at(f, near)
    b.neck.at(s + 18, (10, -14, 0))
    reach, press, lift_end = s + 26, s + 30, s + 38
    b.targets["right_arm"].at(s + 18, release + (0.0, -1.2, 0.9))
    b.targets["right_arm"].attach(reach, lift_end, car.riding("release"))
    b.twist["right_arm"].at(reach, (-20,)).at(lift_end, (-40,)).at(s + 50, (0,))
    b.torso.at(reach, (-8, -2, 2)).at(press, (-8, -2, 2)).at(lift_end, (-3, -2, 3))
    b.pelvis.at(press, near + (0, 0, -0.02))
    b.neck.at(reach, (14, -16, 0)).at(lift_end, (26, -12, 0))
    doors = [(press - 1, 0.0), (press + 2, 0.012), (lift_end, 0.03), (s + 46, 0.1), (s + 54, 0.22)]
    doors += [(s + 62, 0.4), (s + 70, 0.66), (s + 78, 0.88), (s + 84, 0.98), (s + 88, 1.0)]
    for fr, v in doors:
        b.door.at(fr, (v,))
    b.door.at(e, (1.0,))
    b.contact.append((reach - 2, lift_end + 2))
    # Let go and step back out of the door's sweep, watching it rise.
    b.targets["right_arm"].at(s + 42, release + (0.1, 0.5, 0.9))
    b.hang("right_arm", s + 50, e - 2, (1.5, -0.9, 0.0))
    b.neck.at(s + 48, (30, 0, 0)).at(s + 62, (40, 6, 0)).at(s + 76, (30, 20, 0))
    f = walk_steps(b, s + 40, 1, near_r, near_l, back_r, back_l, lead="left_leg", per=8, roll=3)
    b.support.append((f, s + 65, both))
    b.pelvis.at(f, (px, 2.0, back))
    # The door is past its sweep at the body: back to the mark.
    f = walk_steps(b, s + 66, 2, back_r, back_l, home_r, home_l, lead="left_leg", per=8, roll=3)
    b.support.append((f, e, both))
    b.pelvis.at(f, IDLE_PELVIS)
    b.neck.at(e - 4, (8, 0, 0))
    start_idle(b, e)


def outside_close(b, car, s, e):
    """Idle at the mark, door up: side steps forward along the car to stand ahead of the door's
    lower front corner, out of its sweep; up on the toes with the right arm at full stretch for it;
    the door comes the last few centimetres down into the hand, which pulls it down until it is
    low and lets it fall shut; side steps back to the mark."""
    both = ["right_leg", "left_leg"]
    home_r, home_l = IDLE["right_leg"] * V([1, 0, 1]), IDLE["left_leg"] * V([1, 0, 1])
    corner_open = car.door_at("low_corner", 1.0)
    px = float(corner_open[0]) - 0.75  # the right shoulder just ahead of the corner
    pz = float(corner_open[2]) + 0.75  # outboard of the door's front, which comes down past the head
    # Standing on the toes: the soles a little behind the hips tilt the straight legs back.
    stand_r, stand_l = V([px + 0.5, 0, pz + 0.12]), V([px - 0.5, 0, pz + 0.12])
    b.door.at(s, (1.0,))
    b.support.append((s, s + 3, both))
    b.hang("left_arm", s + 2, e - 2, (-1.5, -0.9, 0.0))
    b.hang("right_arm", s + 2, s + 30, (1.5, -0.9, 0.0))
    b.neck.at(s + 6, (26, -24, 0))
    f = walk_steps(b, s + 4, 3, home_r, home_l, stand_r, stand_l, lead="left_leg", per=8, roll=4)
    b.support.append((f, f + 34, both))
    b.pelvis.at(f, (px, 2.0, pz))
    # Up on the toes, leaning away to lift the right shoulder, the arm straight up for the corner.
    up = f + 8
    b.torso.at(up, (2, -6, 18))
    b.pelvis.at(up, (px, 2.06, pz - 0.05))
    b.targets["right_arm"].at(f - 4, corner_open + (0.2, -1.2, 0.4)).at(up, corner_open + (0.0, -0.08, 0.0))
    b.neck.at(up, (40, -10, 0))
    # The door starts down as the hand is about to touch; the hand rides its lower front corner.
    meet, let_go = up + 4, up + 18
    b.door.at(up - 2, (1.0,)).at(meet, (0.97,)).at(meet + 6, (0.78,)).at(let_go, (0.4,))
    b.door.at(let_go + 4, (0.2,)).at(let_go + 7, (0.0,))
    b.targets["right_arm"].attach(meet, let_go, car.riding("low_corner"))
    b.torso.at(meet + 6, (-6, -4, 6)).at(let_go, (-14, -2, 0)).at(let_go + 6, (-4, 0, 0))
    b.pelvis.at(meet + 6, (px, 2.0, pz - 0.3)).at(let_go, (px, 2.0, pz - 0.75))
    b.neck.at(meet + 6, (14, -10, 0)).at(let_go, (-16, -8, 0)).at(let_go + 8, (-8, 0, 0))
    b.targets["right_arm"].at(let_go + 6, corner_open + (0.3, -2.4, -0.9))
    b.hang("right_arm", let_go + 10, e - 2, (1.5, -0.9, 0.0))
    b.contact.append((meet - 2, let_go + 2))
    g = walk_steps(b, let_go + 10, 3, stand_r, stand_l, home_r, home_l, lead="right_leg", per=8, roll=4)
    b.support.append((g, e, both))
    b.pelvis.at(g, IDLE_PELVIS)
    b.door.at(e, (0.0,))
    start_idle(b, e)
    return g


def inside_close(b, car, s, e, seat):
    """Seated, door up: the left hand goes up and out for it; the door comes down on its own (open,
    it is out of this body's reach) and as the arm nears full stretch the hand takes agent B's loop
    strap at 30 degrees and pulls the door shut with it, then rests on the thigh."""
    rot, targets = seat
    meet, shut = s + 26, s + 40
    at_meet = 30.0 / 90.8
    b.door.at(s, (1.0,)).at(s + 8, (1.0,)).at(s + 14, (0.88,)).at(s + 21, (0.55,))
    b.door.at(meet, (at_meet,)).at(s + 33, (0.12,)).at(shut, (0.0,))
    grab = car.strap_grab(at_meet)
    b.neck.at(s + 6, (24, 26, 0)).at(s + 20, (14, 22, 0))
    b.targets["left_arm"].at(s + 10, grab + (-0.2, 1.2, 0.6))
    b.targets["left_arm"].at(s + 20, grab + (-0.05, 0.3, 0.15))
    b.targets["left_arm"].attach(meet, shut, car.riding_strap())
    b.torso.at(s + 12, (-3, SEATED_YAW + 3, 4)).at(meet, (-1, SEATED_YAW + 1, 1)).at(shut, (-1, SEATED_YAW + 1, 3))
    b.neck.at(shut, (-2, 18, 0)).at(e - 6, (-2, 4, 0))
    b.targets["left_arm"].at(shut + 6, targets["left_arm"] + (0.0, 0.35, 0.15))
    b.contact.append((meet - 2, shut + 2))
    start_seated(b, car, e, seat)
    b.door.at(e, (0.0,))


def inside_open(b, car, s, e, seat):
    """Seated, door shut: the left hand to the strap, the latch gives, the hand pushes the door up
    and out as far as it reaches, the struts lift it the rest of the way, the hand comes back."""
    rot, targets = seat
    grip, pushed = s + 12, s + 22
    b.door.at(s, (0.0,))
    b.neck.at(s + 6, (-4, 26, 0))
    b.targets["left_arm"].at(s + 6, car.door_at("strap", 0.0) + (0.15, -0.35, -0.25))
    b.targets["left_arm"].attach(grip, pushed, car.riding("strap"))
    b.door.at(grip + 1, (0.0,)).at(grip + 3, (0.012,)).at(pushed, (0.08,))
    b.door.at(s + 28, (0.3,)).at(s + 36, (0.72,)).at(s + 42, (0.95,)).at(s + 45, (1.0,))
    b.torso.at(grip, (-2, SEATED_YAW + 3, 2)).at(pushed, (1, SEATED_YAW + 4, -1))
    b.neck.at(pushed, (18, 24, 0)).at(s + 40, (12, 10, 0))
    b.targets["left_arm"].at(pushed + 6, targets["left_arm"] + (0.1, 0.6, 0.3))
    b.contact.append((grip - 2, pushed + 2))
    start_seated(b, car, e, seat)
    b.door.at(e, (1.0,))


# Perched on the lip of the sill, facing out: x along the car where the bottom sits, z of the hips.
PERCH_X = -0.15
PERCH_Z = -1.55
PERCH_Y = 1.72  # the torso's bottom on the lip, which stands ~0.13 proud of the sill top
SILL_TOP = 1.54
LIP_Z = -1.93
WALL_Z = -3.44
WALL_TOP = 2.24
FACING_OUT = -180.0


def pose_at(pelvis, rot):
    loc = r6_fk.torso_root_offset(rot, np.asarray(pelvis, dtype=float) - np.array([0, r6_fk.ROOT_HEIGHT, 0]))
    return {"RootJoint": (tuple(rot), tuple(loc)), "Neck": ((0, 0, 0), (0, 0, 0))}


def planted_sole(pelvis, rot, limb):
    """Where a straight leg from this hip meets the ground, swung forward."""
    found = r6_fk.ground_foot(pose_at(pelvis, rot), limb)
    return None if found is None else found[1]


def hips_over(sole_z, pelvis_z, rot, limb="right_leg"):
    """The pelvis height at pelvis_z whose straight leg stands on a sole at sole_z (bisection)."""
    lo, hi = 1.2, 2.0
    for _ in range(40):
        mid = (lo + hi) / 2
        sole = planted_sole((PERCH_X, mid, pelvis_z), rot, limb)
        if sole is None or sole[2] < sole_z:
            hi = mid
        else:
            lo = mid
    return (lo + hi) / 2


def get_in(b, car, s, e, seat):
    """Idle at the mark to the seated pose."""
    rot, targets = seat
    out = (0.0, FACING_OUT, 0.0)
    perch = np.array([PERCH_X, PERCH_Y, PERCH_Z])
    soles = {limb: planted_sole(perch, out, limb) for limb in ("right_leg", "left_leg")}
    feet = {limb: V([soles[limb][0], 0.0, soles[limb][2]]) for limb in soles}
    sole_z = soles["right_leg"][2]
    lift = V([0.0, 0.42, 0.0])

    # Anticipation: weight onto the left foot, a look over the right shoulder at the sill.
    b.pelvis.at(s + 6, IDLE_PELVIS + (-0.1, 0.0, 0.0))
    b.torso.at(s + 6, (0, -6, 1))
    b.neck.at(s + 6, (-16, -40, 0))
    b.hang("right_arm", s + 2, s + 36, (1.5, -0.9, 0.15))
    b.hang("left_arm", s + 2, s + 36, (-1.5, -0.9, -0.15))
    both = ["right_leg", "left_leg"]
    # Step A: pivot on the right foot to face the car's rear; the left hip hikes and the left foot
    # steps round behind.
    right0, left0 = IDLE["right_leg"] * V([1, 0, 1]), IDLE["left_leg"] * V([1, 0, 1])
    pivot_r = V([0.45, 0.0, -0.05])
    left_a = V([0.35, 0.0, -0.95])
    b.support += [(s, s + 9, both), (s + 10, s + 18, ["right_leg"]), (s + 19, s + 23, both)]
    b.targets["right_leg"].at(s + 8, right0).at(s + 20, pivot_r)
    b.targets["left_leg"].at(s + 9, left0).at(s + 12, left0 * 0.7 + left_a * 0.3 + (0, 0.14, 0))
    b.targets["left_leg"].at(s + 16, left0 * 0.2 + left_a * 0.8 + (0, 0.12, 0)).at(s + 19, left_a)
    b.pelvis.at(s + 14, (0.12, 2.0, -0.3)).at(s + 20, (0.38, 2.0, -0.5))
    b.torso.at(s + 10, (0, -30, -2)).at(s + 14, (-1, -55, -5)).at(s + 20, (-2, -90, 0))
    b.neck.at(s + 20, (-12, -38, 0))
    # Step B: pivot on the left foot to face out; the right hip hikes, the right foot comes round.
    b.support += [(s + 24, s + 31, ["left_leg"]), (s + 32, s + 35, both)]
    b.targets["left_leg"].at(s + 33, left_a)
    b.targets["right_leg"].at(s + 23, pivot_r).at(s + 26, pivot_r * 0.7 + feet["right_leg"] * 0.3 + (0, 0.14, 0))
    b.targets["right_leg"].at(s + 29, pivot_r * 0.2 + feet["right_leg"] * 0.8 + (0, 0.12, 0)).at(s + 32, feet["right_leg"])
    b.pelvis.at(s + 27, (0.3, 2.0, -0.4)).at(s + 33, (PERCH_X + 0.1, 2.0, -0.25))
    b.torso.at(s + 24, (-2, -110, 2)).at(s + 28, (-2, -140, 5)).at(s + 33, (-2, -172, 0))
    b.neck.at(s + 33, (-14, 6, 0))
    # A shuffle of the left foot squares the stance.
    b.support += [(s + 36, s + 39, ["right_leg"]), (s + 40, s + 60, both)]
    b.targets["left_leg"].at(s + 35, left_a).at(s + 37, left_a * 0.5 + feet["left_leg"] * 0.5 + (0, 0.12, 0))
    b.targets["left_leg"].at(s + 40, feet["left_leg"])
    b.torso.at(s + 37, (-2, -177, -3))
    stand = V([PERCH_X, 2.0, sole_z])
    b.pelvis.at(s + 41, stand)
    b.torso.at(s + 41, (-2, -180, 0))
    b.neck.at(s + 41, (-10, 0, 0))
    # Sit back: the hips swing back and down about the planted feet onto the lip; the chest goes
    # forward to balance; the hands reach back for the sill.
    sit = (s + 42, s + 52)
    for frac in (0.0, 0.3, 0.6, 0.85, 1.0):
        z = stand[2] + (PERCH_Z - stand[2]) * frac
        f = round(sit[0] + (sit[1] - sit[0]) * frac)
        b.pelvis.at(f, (PERCH_X, PERCH_Y if frac == 1 else 2.0, z))
    b.pelvis.at(s + 54, perch + (0, -0.02, 0)).at(s + 57, perch)
    b.torso.at(s + 46, (-14, -180, 0)).at(s + 52, (-8, -180, 0)).at(s + 57, (-2, -180, 0))
    for limb in feet:
        b.targets[limb].at(s + 42, feet[limb]).at(s + 60, feet[limb])
    hand_y = SILL_TOP + 0.18
    sill_r, sill_l = V([PERCH_X - 1.1, hand_y, -2.65]), V([PERCH_X + 0.6, hand_y, -2.75])
    b.targets["right_arm"].at(s + 44, (PERCH_X - 1.7, 1.9, -0.9)).at(s + 51, sill_r + (0, 0.2, 0.2))
    b.targets["left_arm"].at(s + 44, (PERCH_X + 1.5, 1.9, -0.9)).at(s + 51, sill_l + (0.15, 0.35, 0.45))
    b.targets["right_arm"].at(s + 54, sill_r).at(s + 64, sill_r)
    b.targets["left_arm"].at(s + 54, sill_l).at(s + 62, sill_l)
    b.neck.at(s + 50, (-20, 12, 0)).at(s + 58, (-8, 30, 0))
    b.contact.append((s + 42, s + 64))
    # Swing: weight onto the hands lifts the bottom off the lip; the body turns right on it, the
    # legs come up and over the sill, the hips drift in over the sill.
    b.torso.at(s + 62, (6, -183, 0))
    b.pelvis.at(s + 62, perch + (0, 0.04, -0.05))
    b.pelvis.at(s + 66, perch + (0, 0.42, -0.15))
    for limb in feet:
        b.targets[limb].at(s + 61, feet[limb] + (0, 0.06, -0.02)).at(s + 66, feet[limb] + (0, 0.55, -0.15))
    wall_r = V([PERCH_X - 0.7, WALL_TOP + 0.18, WALL_Z - 0.25])
    b.targets["right_arm"].at(s + 67, wall_r + (0, 0.35, 0.2)).at(s + 70, wall_r).at(s + 90, wall_r)
    lip_l = V([PERCH_X + 0.55, PERCH_Y + 0.12, LIP_Z + 0.3])
    b.targets["left_arm"].at(s + 66, lip_l + (0.2, 0.4, 0.1)).at(s + 70, lip_l).at(s + 92, lip_l)
    b.pelvis.at(s + 70, (PERCH_X, 2.25, -1.85))
    b.torso.at(s + 70, (14, -215, 0))
    b.targets["right_leg"].at(s + 70, (PERCH_X - 0.9, 2.2, -0.2))
    b.targets["left_leg"].at(s + 70, (PERCH_X + 0.1, 2.3, 0.2))
    b.pelvis.at(s + 80, (PERCH_X - 0.05, 2.45, -2.3))
    b.torso.at(s + 80, (12, -252, 0))
    b.targets["right_leg"].at(s + 80, (PERCH_X - 2.1, 2.7, -2.4))
    b.targets["left_leg"].at(s + 80, (PERCH_X - 2.1, 2.8, -1.45))
    b.neck.at(s + 74, (-6, 30, 0)).at(s + 82, (-12, 8, 0))
    # Hoist: weight forward over the right hand on the cabin wall, the left arm straightening on
    # the lip, the hips rise over the wall and onto the seat; the legs drop into the footwell.
    b.torso.at(s + 86, (-10, -266, 0))
    b.pelvis.at(s + 86, (PERCH_X + 0.1, 2.75, -2.9))
    b.targets["right_leg"].at(s + 88, (PERCH_X - 2.2, 2.95, -3.8))
    b.targets["left_leg"].at(s + 88, (PERCH_X - 2.3, 3.05, -2.8))
    b.pelvis.at(s + 94, (0.0, 2.82, -4.2))
    b.torso.at(s + 94, (-12, -270, 0))
    b.targets["right_arm"].at(s + 94, wall_r + (0.1, 0.2, -0.6))
    b.targets["right_leg"].at(s + 96, (PERCH_X - 2.3, 2.5, -5.6))
    b.targets["left_leg"].at(s + 96, (PERCH_X - 2.4, 2.6, -4.3))
    b.pelvis.at(s + 101, car.seated_pelvis + (0.0, 0.07, 0.0))
    b.pelvis.at(s + 104, car.seated_pelvis)
    b.torso.at(s + 101, (-4, -270, 0)).at(s + 107, (1.5, -270, 0))
    b.neck.at(s + 96, (-8, 0, 0))
    b.contact.append((s + 66, s + 96))
    # Settle: hands off the wall and the lip, legs toward the pedals; then the door, as the
    # standalone InsideClose closes it (the open door is out of reach until it is low).
    b.targets["right_arm"].at(s + 103, targets["right_arm"] + (0.25, 0.45, 0.05))
    b.targets["left_arm"].at(s + 99, targets["left_arm"] + (0.4, 0.9, 0.6))
    b.targets["right_leg"].at(s + 106, targets["right_leg"])
    b.targets["left_leg"].at(s + 106, targets["left_leg"])
    b.neck.at(s + 106, (-6, 0, 0))
    b.door.at(s, (1.0,))
    b.torso.at(s + 108, rot)
    b.pelvis.at(s + 108, car.seated_pelvis)
    b.targets["right_arm"].at(s + 108, targets["right_arm"])
    for limb in b.twist:
        b.twist[limb].at(s + 108, (0,))
    inside_close(b, car, s + 104, e, seat)


def entry(car):
    """OutsideOpen 0-100, GetIn 100-258 (it ends with the door closed)."""
    b = Body(259, FPS)
    car.door_track = b.door
    seat = seated_targets(car)
    seat = ((0.0, SEATED_YAW, 0.0), seat[1])
    open_end, getin_end = 100, 258
    start_idle(b, 0)
    outside_open(b, car, 0, open_end)
    get_in(b, car, open_end, getin_end, seat)
    clips = [
        {"name": "OutsideOpen", "start": 0, "end": open_end},
        {"name": "GetIn", "start": open_end, "end": getin_end},
    ]
    return b, clips


def get_out(b, car, s, e, seat):
    """Seated with the door open to standing idle at the mark: hands push the body up and out over
    the cabin wall, the bottom comes down on the lip as the body turns left to face out, the legs
    swing out over the sill, the feet find the ground, a push off the sill stands it up, and two
    steps turn it round to face the car."""
    rot, targets = seat
    out = (0.0, FACING_OUT, 0.0)
    perch = np.array([PERCH_X, PERCH_Y, PERCH_Z])
    soles = {limb: planted_sole(perch, out, limb) for limb in ("right_leg", "left_leg")}
    feet = {limb: V([soles[limb][0], 0.0, soles[limb][2]]) for limb in soles}
    wall_r = V([PERCH_X - 0.7, WALL_TOP + 0.18, WALL_Z - 0.25])
    lip_l = V([PERCH_X + 0.55, PERCH_Y + 0.12, LIP_Z + 0.3])
    both = ["right_leg", "left_leg"]
    # Hands to the cabin wall and the lip, a lean forward over them.
    b.neck.at(s + 6, (-14, 30, 0))
    b.targets["right_arm"].at(s + 8, wall_r + (0.15, 0.5, -0.7)).at(s + 12, wall_r + (0.1, 0.2, -0.6))
    b.targets["left_arm"].at(s + 8, lip_l + (-0.3, 0.9, -0.6)).at(s + 13, lip_l)
    b.torso.at(s + 10, (-6, SEATED_YAW, 0))
    # Hoist out: up off the seat, over the wall, the right hand walking to the wall top.
    b.pelvis.at(s + 18, car.seated_pelvis + (0.05, 0.0, 0.3))
    b.torso.at(s + 18, (-12, SEATED_YAW + 2, 0))
    b.targets["right_arm"].at(s + 20, wall_r + (0.1, 0.2, -0.6)).at(s + 24, wall_r + (0.1, 0.4, -0.2))
    b.targets["right_arm"].at(s + 27, wall_r).at(s + 50, wall_r)
    b.targets["left_arm"].at(s + 50, lip_l)
    b.pelvis.at(s + 26, (0.0, 2.8, -4.15))
    b.torso.at(s + 26, (-14, SEATED_YAW + 4, 0))
    b.targets["right_leg"].at(s + 22, (PERCH_X - 2.3, 2.5, -5.6))
    b.targets["left_leg"].at(s + 22, (PERCH_X - 2.4, 2.6, -4.3))
    b.pelvis.at(s + 34, (PERCH_X + 0.1, 2.75, -2.9))
    b.torso.at(s + 34, (6, SEATED_YAW + 10, 0))
    b.targets["right_leg"].at(s + 32, (PERCH_X - 2.2, 2.95, -3.8))
    b.targets["left_leg"].at(s + 32, (PERCH_X - 2.3, 3.1, -2.8))
    b.neck.at(s + 30, (-10, 10, 0))
    # Swing out: turning left on the bottom, the legs come up over the sill and out.
    b.pelvis.at(s + 42, (PERCH_X - 0.05, 2.6, -2.3))
    b.torso.at(s + 42, (12, -250, 0))
    b.targets["right_leg"].at(s + 42, (PERCH_X - 2.1, 2.8, -2.4))
    b.targets["left_leg"].at(s + 42, (PERCH_X - 2.1, 2.9, -1.45))
    b.pelvis.at(s + 50, (PERCH_X, 2.25, -1.85))
    b.torso.at(s + 50, (12, -212, 0))
    b.targets["right_leg"].at(s + 50, (PERCH_X - 0.9, 2.2, -0.2))
    b.targets["left_leg"].at(s + 50, (PERCH_X + 0.1, 2.3, 0.2))
    b.neck.at(s + 46, (-8, -20, 0)).at(s + 54, (-16, 0, 0))
    # Down onto the lip, facing out; the feet reach for the ground.
    b.pelvis.at(s + 55, perch + (0, 0.3, -0.12)).at(s + 58, perch + (0, 0.03, -0.02)).at(s + 59, perch)
    b.torso.at(s + 56, (4, -184, 0)).at(s + 60, (0, FACING_OUT, 0))
    for limb in feet:
        b.targets[limb].at(s + 54, feet[limb] + (0, 0.55, -0.15)).at(s + 58, feet[limb] + (0, 0.12, -0.04))
        b.targets[limb].at(s + 61, feet[limb])
    hand_y = SILL_TOP + 0.18
    sill_r, sill_l = V([PERCH_X - 1.1, hand_y, -2.65]), V([PERCH_X + 0.6, hand_y, -2.75])
    b.targets["right_arm"].at(s + 54, sill_r + (0.1, 0.3, 0.1)).at(s + 57, sill_r).at(s + 66, sill_r)
    b.targets["left_arm"].at(s + 54, sill_l + (-0.1, 0.3, 0.1)).at(s + 57, sill_l).at(s + 66, sill_l)
    b.contact.append((s + 10, s + 66))
    # Push off: weight forward over the feet, the hips arc up and forward to standing.
    b.support += [(s + 62, s + 84, both)]
    stand = V([PERCH_X, 2.0, feet["right_leg"][2]])
    b.torso.at(s + 64, (-16, FACING_OUT, 0))
    for frac, f in ((0.0, s + 62), (0.35, s + 66), (0.7, s + 70), (1.0, s + 74)):
        z = PERCH_Z + (stand[2] - PERCH_Z) * frac
        b.pelvis.at(f, (PERCH_X, PERCH_Y if frac == 0 else 2.0, z))
    b.torso.at(s + 70, (-8, FACING_OUT, 0)).at(s + 76, (-1, FACING_OUT, 0))
    b.hang("right_arm", s + 72, s + 108, (1.5, -0.9, -0.1))
    b.hang("left_arm", s + 72, s + 108, (-1.5, -0.9, 0.1))
    b.neck.at(s + 72, (-6, 0, 0))
    for limb in feet:
        b.targets[limb].at(s + 84, feet[limb])
    # Turn round to the car, away from it: three short steps out and round, the pelvis kept a
    # stride out from the car so the leg on its side never swings into the sill.
    right_out = V([0.1, 0.0, 0.9])
    left_home, right_home = IDLE["left_leg"] * V([1, 0, 1]), IDLE["right_leg"] * V([1, 0, 1])
    b.support += [(s + 85, s + 93, ["left_leg"]), (s + 94, s + 95, both)]
    b.targets["right_leg"].at(s + 85, feet["right_leg"]).at(s + 88, feet["right_leg"] * 0.6 + right_out * 0.4 + (0, 0.14, 0))
    b.targets["right_leg"].at(s + 91, feet["right_leg"] * 0.15 + right_out * 0.85 + (0, 0.12, 0)).at(s + 94, right_out)
    b.pelvis.at(s + 89, (PERCH_X + 0.05, 2.0, 0.15)).at(s + 95, (0.0, 2.0, 0.4))
    b.torso.at(s + 86, (-1, -170, -2)).at(s + 90, (-1, -140, 4)).at(s + 95, (-1, -100, 0))
    b.neck.at(s + 90, (-8, 30, 0))
    b.support += [(s + 96, s + 103, ["right_leg"]), (s + 104, s + 105, both)]
    b.targets["left_leg"].at(s + 95, feet["left_leg"]).at(s + 98, feet["left_leg"] * 0.6 + left_home * 0.4 + (0, 0.14, 0))
    b.targets["left_leg"].at(s + 101, feet["left_leg"] * 0.15 + left_home * 0.85 + (0, 0.12, 0)).at(s + 104, left_home)
    b.pelvis.at(s + 104, (-0.1, 2.0, 0.2))
    b.torso.at(s + 97, (-1, -85, -4)).at(s + 104, (-1, -15, 0))
    b.neck.at(s + 102, (-4, -10, 0))
    b.support += [(s + 106, s + 111, ["left_leg"]), (s + 112, e, both)]
    b.targets["right_leg"].at(s + 105, right_out).at(s + 108, right_out * 0.5 + right_home * 0.5 + (0, 0.14, 0))
    b.targets["right_leg"].at(s + 112, right_home)
    b.pelvis.at(s + 112, (0.02, 2.0, 0.02))
    b.torso.at(s + 108, (0, -5, 3)).at(s + 112, (0, 0, 0))
    b.targets["left_leg"].at(s + 112, left_home)
    start_idle(b, e)


def exit_timeline(car):
    """InsideOpen 0-48, GetOut 48-168, OutsideClose 168-306."""
    b = Body(307, FPS)
    car.door_track = b.door
    seat = seated_targets(car)
    seat = ((0.0, SEATED_YAW, 0.0), seat[1])
    open_end, out_end, close_end = 48, 168, 306
    start_seated(b, car, 0, seat)
    inside_open(b, car, 0, open_end, seat)
    get_out(b, car, open_end, out_end, seat)
    b.door.at(out_end, (1.0,))
    outside_close(b, car, out_end, close_end)
    clips = [
        {"name": "InsideOpen", "start": 0, "end": open_end},
        {"name": "GetOut", "start": open_end, "end": out_end},
        {"name": "OutsideClose", "start": out_end, "end": close_end},
    ]
    return b, clips


def close_timeline(car):
    """The standalone InsideClose: seated with the door up, to seated with it shut."""
    b = Body(55, FPS)
    car.door_track = b.door
    seat = seated_targets(car)
    seat = ((0.0, SEATED_YAW, 0.0), seat[1])
    start_seated(b, car, 0, seat)
    inside_close(b, car, 0, 54, seat)
    return b, [{"name": "InsideClose", "start": 0, "end": 54}]


def seated(car):
    """The looped SEATED pose: one second of the pose InsideClose ends on."""
    b = Body(31, FPS)
    car.door_track = b.door
    seat = seated_targets(car)
    seat = ((0.0, SEATED_YAW, 0.0), seat[1])
    start_seated(b, car, 0, seat)
    b.door.at(0, (0.0,))
    start_seated(b, car, 30, seat)
    return b, [{"name": "SeatedPose", "start": 0, "end": 30}]


def emit(body, clips, out_dir, name):
    body.solve()
    data = body.keys(every=2, clips=clips, markers=[])
    write(os.path.join(out_dir, f"{name}.keys.json"), data)
    with open(os.path.join(out_dir, f"{name}.fk.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(body.fk_bake(), handle)
    misses = body.report_misses()
    print(f"{name}: {body.frames} frames, {len(data['joints']['RootJoint'])} keys per joint, {len(misses)} limb misses > 0.08")
    spans = {}
    for f, limb, err in misses:
        spans.setdefault(limb, []).append((f, err))
    for limb, rows in spans.items():
        print(f"  {limb}: f{rows[0][0]}..f{rows[-1][0]}, worst {max(r[1] for r in rows)}")


def main(argv):
    scene, seat, rest, door, out_dir = argv
    car = Car(scene, seat, rest, door)
    os.makedirs(out_dir, exist_ok=True)
    emit(*entry(car), out_dir, "entry")
    emit(*exit_timeline(car), out_dir, "exit")
    emit(*close_timeline(car), out_dir, "close")
    emit(*seated(car), out_dir, "seated")


if __name__ == "__main__":
    main(sys.argv[1:])
