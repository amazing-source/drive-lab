"""
Keys for getting in and out of the SVJ, one continuous timeline per direction, cut into the
clips CarEntry plays (games/drive-lab/src/shared/Config/CarEntry.luau):

  entry:  OutsideOpen | GetIn                      (GetIn ends seated with the door shut, #9)
  exit:   InsideOpen  | GetOut | OutsideClose
  close:  InsideClose                              (the door key while seated with the door up)
  seated: SeatedPose

Consecutive clips are cut from one timeline, so they meet on the same pose by construction.
Authored in the AUTHORING frame of tools/anim/car_entry_prep.py: the door mark's standing root at
(0, 3, 0) facing -Z, the world divided by the driver's scale, ground y = 0. Car forward is -X,
into the car is -Z; seated, the body faces -X (yaw -270, reached by turning right).

The technique is the real one for this car and this body (docs/pipelines/CAR_ENTRY_ANIMATION.md):
outside, the fingers find the release in the recess at the door's upper rear and lift the door
skyward; getting in, the back turns to the car, the bottom perches on the edge of the wide sill,
the legs lift and swing over it, and a push of both hands hoists the body onto the seat (Roblox's
upright sit, which floats above this car's low cushion) while the left hand takes the door's lower
inner edge at half open and rides it down, then the strap on the door's edge pulls it shut.
Getting out: a hand pulls the release bar and pushes the door up, the body slides to the sill's
edge, the legs swing out, the feet find the ground, a push off the sill stands it up, it turns to
face the car and pulls the door down by its edge.

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
from car_entry_check import depths  # noqa: E402
from car_scene import rotation_about  # noqa: E402

FPS = 30
SEATED_YAW = -270.0
# The palm against each door contact, off the surface toward the body (shut door, authoring
# frame): the outer skin faces out (+Z), the door card faces the cabin (-Z), the lower corner is
# taken from below.
# The door card's lower inner edge is held from below and from the cabin side, the release bar
# from below on its cabin side.
PALM_OFF = {
    "release": (0, -0.1, 0.55),
    "low_corner": (0, -0.45, 0.25),
    "edge_at_strap": (0, -0.3, -0.3),
    "release_bar": (0, -0.2, -0.42),
}
# The loop strap on the door card (#31): 25 cm in studs of the 1.5x world. Authoring studs are the
# world divided by the driver's scale (Car.strap_length).
STRAP_LENGTH = 0.25 * 1.5 / 0.28
# The door's openness at which the hand takes the strap, closing, in GetIn and InsideClose alike:
# the strap is drawn held from here to shut (agreed with the strap's runtime, #31).
STRAP_OPENNESS = 30.0 / 90.8
# Shoulder joint to palm (r6_fk.HAND) of a scale-1 R6 arm, which is rigid: 1.44 studs.
ARM_REACH = float(np.linalg.norm(np.array(r6_fk.HAND) - np.array([0.5, 0.5, 0.0])))
LEFT_SHOULDER = np.array([-1.0, 0.5, 0.0])  # the Left Shoulder joint in the torso's frame
SHOULDER = {"right_arm": np.array([1.0, 0.5, 0.0]), "left_arm": LEFT_SHOULDER}
# Shoulder joint to the centre of the arm's end face: where a hand pushing on a surface meets it.
END_REACH = float(np.linalg.norm(np.array([0.0, -1.0, 0.0]) - np.array([0.5, 0.5, 0.0])))
# The car's surfaces a hand may push on (the door is posed per frame and held by named points).
SURFACES = ("sill", "paint", "interior", "carbon", "trim")
# The region of the car a hand can push on: around the door and the driver's seat (authoring frame).
SURFACE_BOX = (np.array([-4.5, 0.5, -8.0]), np.array([3.5, 8.0, 1.5]))
# How far a pushing hand's arm may press into the surface it pushes on (studs, scale 1).
HAND_PRESS = 0.08


class Car:
    """Landmarks in the authoring frame, all derived from measured files."""

    def __init__(self, scene_path, seat_path, rest_path, door_path):
        d = np.load(scene_path, allow_pickle=False)
        self.scene_path = scene_path
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
        self.holds = []  # (start, end, what): spans where the left hand holds the door, for reports
        self.reach = {}  # label -> {frame: True when the surface was within the arm's reach}
        self._surface = None

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

    def strap_grab(self, openness, shoulder=None):
        """Where the hand holds the 25 cm loop strap (#31). An R6 arm has no elbow: its palm is
        always ARM_REACH from the shoulder joint. So the hand holds the strap where that sphere meets
        the line from the left shoulder (the seated one unless given) to where the strap is sewn on
        the door card; the strap runs taut from there to the hand."""
        shoulder = self.left_shoulder if shoulder is None else shoulder
        anchor = self.door_at("strap_anchor", openness)
        towards = anchor - shoulder
        return shoulder + ARM_REACH * towards / np.linalg.norm(towards)

    def riding_strap(self, body):
        """A beat value: the strap grip from the body's own left shoulder at that frame (a lean
        toward the door shortens the strap), the door on the timeline's door track."""

        def at(frame):
            shoulder = body.torso_frame(frame)[:3, :3] @ LEFT_SHOULDER + body.torso_frame(frame)[:3, 3]
            return self.strap_grab(float(self.door_track.sample(np.array([frame]))[0, 0]), shoulder)

        return at

    @property
    def strap_length(self):
        return STRAP_LENGTH / self.scale

    def surface(self):
        if self._surface is None:
            from scipy.spatial import cKDTree

            from car_entry_check import sample

            d = np.load(self.scene_path, allow_pickle=False)
            cloud = np.concatenate([sample(d[f"v_{g}"].astype(float), d[f"f_{g}"], 0.05) for g in SURFACES])
            # Only around the door and the driver's seat, where hands can reach.
            cloud = cloud[np.all((cloud > SURFACE_BOX[0]) & (cloud < SURFACE_BOX[1]), axis=1)]
            self._surface = (cloud, cKDTree(cloud))
        return self._surface

    def on_surface(self, body, limb, target, label):
        """A beat value: the hand pushing on the car, as near the authored target as the rigid arm
        reaches. Each frame, among the surface points where the arm's end face lands (END_REACH
        from the solved shoulder), the nearest to the target; the palm sits on the line to it.
        Where no surface is within reach the hand reaches toward the target, and the frame is
        logged as out of reach (a must-touch contact there fails the check)."""
        cloud, tree = self.surface()
        log = self.reach.setdefault(label, {})
        target = np.asarray(target, dtype=float)

        joint = r6_fk.LIMB_JOINT[limb]
        state = {"guess": (0.0, 0.0)}

        def clear_depth(torso, palm):
            angles, _ = r6_fk.aim({}, limb, palm, r6_fk.HAND, guess=state["guess"], torso=torso)
            arm = r6_fk.limb_frame(torso, joint, angles)
            near = tree.query_ball_point(arm[:3, 3], 1.2)
            depth = depths(cloud[near], arm, (0.5, 1.0, 0.5), 0.0)[0] if near else 0.0
            return depth, (angles[0], angles[2])

        def at(frame):
            m = body.torso_frame(frame)
            shoulder = m[:3, :3] @ SHOULDER[limb] + m[:3, 3]
            idx = tree.query_ball_point(shoulder, END_REACH + 0.03)
            if idx:
                pts = cloud[idx]
                shell = pts[np.linalg.norm(pts - shoulder, axis=1) > END_REACH - 0.03]
                if len(shell):
                    # Twelve landing points spread over those nearest the target, the first kept
                    # whose whole arm gets there without passing through the car (its end face may
                    # press in a little, HAND_PRESS).
                    best = None
                    for p in shell[np.argsort(np.linalg.norm(shell - target, axis=1))[:: max(1, len(shell) // 400)][:12]]:
                        palm = shoulder + ARM_REACH * (p - shoulder) / np.linalg.norm(p - shoulder)
                        depth, angles = clear_depth(m, palm)
                        if best is None or depth < best[0]:
                            best = (depth, palm, angles)
                        if depth <= HAND_PRESS:
                            break
                    if best[0] <= HAND_PRESS:
                        log[int(frame)] = True
                        state["guess"] = best[2]
                        return best[1]
            log[int(frame)] = False
            return shoulder + ARM_REACH * (target - shoulder) / np.linalg.norm(target - shoulder)

        return at

    def riding(self, name):
        """A beat value that rides a door point on the timeline's own door track."""

        def at(frame):
            openness = float(self.door_track.sample(np.array([frame]))[0, 0])
            return self.door_at(name, openness)

        return at


def blend(first, second, start, end):
    """A beat value that eases from one riding value to another over start..end."""

    def at(frame):
        u = min(1.0, max(0.0, (frame - start) / (end - start)))
        u = u * u * (3 - 2 * u)
        return np.asarray(first(frame)) * (1 - u) + np.asarray(second(frame)) * u

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
    third = max(2, (end - start) // 3)
    b.support.append((start, end - 1, [other]))
    # Up before across and down before still: a grounded sole that moves is a slide.
    b.targets[limb].at(start, frm).at(start + 1, frm + (0, 0.05, 0))
    b.targets[limb].at(start + third, frm * 0.75 + to * 0.25 + (0, lift, 0))
    b.targets[limb].at(end - third, frm * 0.25 + to * 0.75 + (0, lift, 0))
    b.targets[limb].at(end - 1, to + (0, 0.05, 0)).at(end, to)


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
            # The stepping hip hikes from the step's first frame to its last, so the rigid leg
            # clears the ground without first dragging its foot.
            b.torso.at(f + 1, (-1, yaw, sign * roll)).at(f + per // 2, (-1, yaw, sign * roll * 1.2))
            b.torso.at(f + per - 3, (-1, yaw, sign * roll))
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
    b.torso.at(reach, (-5, -2, 2)).at(press, (-5, -2, 2)).at(lift_end, (-2, -2, 3))
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
    f = walk_steps(b, s + 40, 2, near_r, near_l, back_r, back_l, lead="left_leg", per=6, roll=4)
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
    it is out of this body's reach) and as the arm nears full stretch the hand takes the loop strap
    at 30 degrees and pulls the door shut with it, leaning toward the door at the end so the strap
    stays within its 25 cm, then rests on the thigh."""
    rot, targets = seat
    meet, shut = s + 26, s + 40
    b.door.at(s, (1.0,)).at(s + 8, (1.0,)).at(s + 14, (0.88,)).at(s + 21, (0.55,))
    b.door.at(meet, (STRAP_OPENNESS,)).at(s + 33, (0.12,)).at(shut, (0.0,))
    grab = car.strap_grab(STRAP_OPENNESS)
    b.neck.at(s + 6, (24, 26, 0)).at(s + 20, (14, 22, 0))
    b.targets["left_arm"].at(s + 10, grab + (-0.2, 1.2, 0.6))
    b.targets["left_arm"].at(s + 20, grab + (-0.05, 0.3, 0.15))
    b.targets["left_arm"].attach(meet, shut, car.riding_strap(b))
    car.holds.append((meet, shut, "strap"))
    b.torso.at(s + 12, (-3, SEATED_YAW + 3, 4)).at(meet, (-1, SEATED_YAW + 1, 1)).at(shut, (-1, SEATED_YAW + 1, 6))
    b.neck.at(shut, (-2, 18, 0)).at(e - 6, (-2, 4, 0))
    b.targets["left_arm"].at(shut + 6, targets["left_arm"] + (0.0, 0.35, 0.15))
    b.contact.append((meet - 2, shut + 2))
    start_seated(b, car, e, seat)
    b.door.at(e, (0.0,))


def inside_open(b, car, s, e, seat):
    """Seated, door shut: leaning forward and toward the door, the left hand hooks the slotted bar
    at the top of the door card (where the old strap hung; the model names no release, so pulling
    it as the release is our reading), the latch gives, the hand pushes the door up and out as far
    as it reaches, the struts lift it the rest of the way, and the body sits back."""
    rot, targets = seat
    grip, pushed = s + 14, s + 24
    bar = car.door_at("release_bar", 0.0)
    b.door.at(s, (0.0,)).at(grip + 1, (0.0,)).at(grip + 3, (0.012,)).at(pushed, (0.06,))
    b.door.at(s + 30, (0.25,)).at(s + 38, (0.7,)).at(s + 44, (0.95,)).at(s + 47, (1.0,))
    b.neck.at(s + 6, (-2, 12, 0)).at(grip, (6, 8, 0)).at(pushed, (14, 12, 0)).at(s + 40, (10, 6, 0))
    # Turning toward the door rolls the blocky legs about their length: the right one lower and
    # outboard, clear of the column above it, the left one up off the floor.
    clear_r, clear_l = targets["right_leg"] + (0.0, -0.3, 0.3), targets["left_leg"] + (0.0, 0.2, 0.0)
    b.targets["right_leg"].at(s + 6, clear_r).at(s + 38, clear_r)
    b.targets["left_leg"].at(s + 6, clear_l).at(s + 38, clear_l)
    b.torso.at(s + 6, (-12, SEATED_YAW + 2, 2))
    b.targets["left_arm"].at(s + 8, bar + (0.4, -0.5, -1.0))
    b.targets["left_arm"].attach(grip, pushed, car.riding("release_bar"))
    car.holds.append((grip, pushed, "bar"))
    # The lean that puts the shoulder one reach from the bar, solved frame by frame through the
    # push (car_entry_hold.py): the pelvis stays in the seat, the torso leans forward and turns
    # toward the door; the arm, head and torso stay clear of the door, the wheel and the console.
    for offset, pelvis, turn in INSIDE_OPEN_PUSH:
        b.pelvis.at(grip + offset, pelvis)
        b.torso.at(grip + offset, turn)
    b.targets["left_arm"].at(pushed + 6, targets["left_arm"] + (0.1, 0.6, 0.3))
    b.contact.append((grip - 2, pushed + 2))
    b.torso.at(s + 36, (-4, SEATED_YAW, 0))
    start_seated(b, car, e, seat)
    b.door.at(e, (1.0,))


# car_entry_hold.py --timeline exit --point release_bar --from 14 --to 24 --arm-allow 0.12
INSIDE_OPEN_PUSH = [  # frame offset from the grip, pelvis, (lean, yaw, roll)
    (0, (-0.002, 3.178, -5.496), (-31.66, -263.70, 3.90)),
    (1, (-0.001, 3.178, -5.496), (-31.66, -263.74, 3.91)),
    (2, (-0.001, 3.194, -5.510), (-31.59, -263.85, 3.96)),
    (3, (-0.001, 3.182, -5.498), (-30.15, -264.02, 3.53)),
    (4, (-0.002, 3.182, -5.499), (-29.24, -264.25, 3.69)),
    (5, (-0.002, 3.179, -5.496), (-28.51, -264.53, 3.40)),
    (6, (-0.002, 3.177, -5.493), (-27.62, -264.85, 3.44)),
    (7, (-0.002, 3.173, -5.489), (-26.66, -265.21, 3.52)),
    (8, (-0.002, 3.170, -5.485), (-25.60, -265.59, 3.65)),
    (9, (-0.002, 3.167, -5.479), (-24.49, -266.00, 3.74)),
    (10, (-0.002, 3.166, -5.473), (-23.25, -266.42, 4.03)),
]


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
    b.targets["left_leg"].at(s + 9, left0).at(s + 10, left0 + (0, 0.06, 0))
    b.targets["left_leg"].at(s + 12, left0 * 0.7 + left_a * 0.3 + (0, 0.14, 0))
    b.targets["left_leg"].at(s + 16, left0 * 0.2 + left_a * 0.8 + (0, 0.12, 0)).at(s + 19, left_a)
    b.pelvis.at(s + 14, (0.12, 2.0, -0.3)).at(s + 20, (0.38, 2.0, -0.5))
    b.torso.at(s + 10, (0, -30, -2)).at(s + 14, (-1, -55, -5)).at(s + 20, (-2, -90, 0))
    b.neck.at(s + 20, (-12, -38, 0))
    # Step B: pivot on the left foot to face out; the right hip hikes, the right foot comes round.
    b.support += [(s + 24, s + 31, ["left_leg"]), (s + 32, s + 32, both)]
    b.targets["left_leg"].at(s + 32, left_a)
    b.targets["right_leg"].at(s + 23, pivot_r).at(s + 24, pivot_r + (0, 0.06, 0))
    b.targets["right_leg"].at(s + 26, pivot_r * 0.7 + feet["right_leg"] * 0.3 + (0, 0.14, 0))
    b.targets["right_leg"].at(s + 29, pivot_r * 0.2 + feet["right_leg"] * 0.8 + (0, 0.12, 0)).at(s + 32, feet["right_leg"])
    b.pelvis.at(s + 27, (0.3, 2.0, -0.4)).at(s + 33, (PERCH_X + 0.1, 2.0, -0.25))
    b.torso.at(s + 24, (-2, -110, 2)).at(s + 28, (-2, -140, 5)).at(s + 33, (-2, -172, 0))
    b.neck.at(s + 33, (-14, 6, 0))
    # A shuffle of the left foot squares the stance.
    b.support += [(s + 33, s + 39, ["right_leg"]), (s + 40, s + 60, both)]
    b.targets["left_leg"].at(s + 33, left_a + (0, 0.06, 0))
    b.targets["left_leg"].at(s + 37, left_a * 0.5 + feet["left_leg"] * 0.5 + (0, 0.12, 0))
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
    b.torso.at(s + 46, (-14, -180, 0)).at(s + 52, (-4, -180, 0)).at(s + 56, (7, -180, 0)).at(s + 60, (7, -180, 0))
    for limb in feet:
        b.targets[limb].at(s + 42, feet[limb]).at(s + 60, feet[limb])
    hand_y = SILL_TOP + 0.18
    sill_r, sill_l = V([PERCH_X - 1.1, hand_y, -2.65]), V([PERCH_X + 0.6, hand_y, -2.75])
    b.targets["right_arm"].at(s + 44, (PERCH_X - 1.7, 1.9, -0.9)).at(s + 51, sill_r + (0, 0.2, 0.2))
    b.targets["left_arm"].at(s + 44, (PERCH_X + 1.5, 1.9, -0.9)).at(s + 51, sill_l + (0.15, 0.35, 0.45))
    b.targets["right_arm"].attach(s + 54, s + 64, car.on_surface(b, "right_arm", sill_r, "GetIn right hand on the sill"))
    b.targets["left_arm"].attach(s + 54, s + 62, car.on_surface(b, "left_arm", sill_l, "GetIn left hand on the sill"))
    b.neck.at(s + 50, (-20, 12, 0)).at(s + 58, (-8, 30, 0))
    b.contact.append((s + 42, s + 64))
    # Swing: weight onto the hands lifts the bottom off the lip; the body turns right on it, the
    # legs come up and over the sill, the hips drift in over the sill.
    b.torso.at(s + 62, (6, -183, 0))
    b.pelvis.at(s + 62, perch + (0, 0.2, -0.05)).at(s + 64, perch + (0, 0.45, -0.1))
    b.pelvis.at(s + 66, perch + (0, 0.52, -0.15))
    for limb in feet:
        b.targets[limb].at(s + 61, feet[limb] + (0, 0.08, 0)).at(s + 62, feet[limb] + (0, 0.2, 0))
        b.targets[limb].at(s + 64, feet[limb] + (0, 0.42, -0.06)).at(s + 66, feet[limb] + (0, 0.55, -0.15))
    wall_r = V([PERCH_X - 0.7, WALL_TOP + 0.18, WALL_Z - 0.25])
    b.targets["right_arm"].at(s + 67, wall_r + (0, 0.35, 0.2))
    b.targets["right_arm"].attach(s + 70, s + 90, car.on_surface(b, "right_arm", wall_r, "GetIn right hand on the cabin wall"))
    lip_l = V([PERCH_X + 0.55, PERCH_Y + 0.12, LIP_Z + 0.3])
    b.targets["left_arm"].at(s + 66, lip_l + (0.2, 0.4, 0.1))
    b.targets["left_arm"].attach(s + 70, s + 73, car.on_surface(b, "left_arm", lip_l, "GetIn left hand on the lip"))
    b.pelvis.at(s + 70, (PERCH_X, 2.25, -1.85))
    b.torso.at(s + 70, (14, -215, 0))
    b.targets["right_leg"].at(s + 70, (PERCH_X - 0.9, 2.2, -0.2))
    b.targets["left_leg"].at(s + 70, (PERCH_X + 0.1, 2.3, 0.2))
    b.pelvis.at(s + 80, (PERCH_X - 0.05, 2.45, -2.3))
    b.torso.at(s + 80, (12, -252, 0))
    b.targets["right_leg"].at(s + 80, (PERCH_X - 2.1, 2.7, -2.4))
    b.targets["left_leg"].at(s + 80, (PERCH_X - 2.1, 2.8, -1.45))
    b.contact.append((s + 66, s + 73))
    # The door (#9): the left hand leaves the lip and reaches up and out for the door's lower inner
    # edge. Open, the door is out of this body's reach, so it starts down on its own as the arm
    # nears full stretch and meets the hand at half open, at the top of the hoist.
    meet = s + 86
    b.targets["left_arm"].at(s + 79, car.door_at("edge_at_strap", 0.6) + (0.1, -0.3, -0.25))
    b.door.at(s, (1.0,)).at(s + 76, (1.0,)).at(s + 80, (0.87,)).at(s + 83, (0.67,)).at(meet, (0.5,))
    b.neck.at(s + 74, (14, 30, 0)).at(meet, (26, 24, 0))
    # The hoist with the door in hand: weight over the right hand on the cabin wall, the hips slide
    # in over the wall while the hand rides the edge down. Every frame is a pose where the rigid arm
    # (no elbow: shoulder to palm is always ARM_REACH) holds the edge, with the arm, head and torso
    # clear of the door at that frame's openness, solved against the door's mesh
    # (car_entry_hold.py): the body sinks and leans away from the door as its edge comes in, its
    # weight drawing the door down.
    # The door's own curve through the ride; the body follows it frame by frame (GETIN_RIDE).
    ride_doors = [(meet, 0.5), (s + 89, 0.45), (s + 92, 0.4), (s + 95, 0.36), (s + 98, STRAP_OPENNESS)]
    for frame, openness in ride_doors:
        b.door.at(frame, (openness,))
    for offset, pelvis, turn in GETIN_RIDE:
        b.pelvis.at(meet + offset, pelvis)
        b.torso.at(meet + offset, turn)
    handover = ride_doors[-1][0]
    b.targets["left_arm"].attach(meet, handover, car.riding("edge_at_strap"))
    car.holds.append((meet, handover, "edge"))
    b.targets["right_leg"].at(s + 88, (PERCH_X - 2.2, 2.95, -3.8))
    b.targets["left_leg"].at(s + 88, (PERCH_X - 2.3, 3.05, -2.8))
    b.targets["right_arm"].at(s + 94, wall_r + (0.1, 0.2, -0.6)).at(s + 99, targets["right_arm"] + (0.2, 1.0, 0.45))
    b.targets["right_leg"].at(s + 96, (PERCH_X - 2.3, 2.15, -5.6)).at(s + 101, (PERCH_X - 2.2, 2.4, -5.75))
    b.targets["left_leg"].at(s + 96, (PERCH_X - 2.4, 2.95, -4.3)).at(s + 101, (PERCH_X - 2.3, 2.6, -4.9))
    b.neck.at(s + 92, (16, 20, 0))
    b.contact.append((s + 74, s + 96))
    # At 30 degrees the hand moves from the edge onto the strap sewn beside it (#31) and pulls the
    # door shut as the body settles into the seat; the palm stays on the line from the body's own
    # shoulder to where the strap is sewn, and a lean toward the door at the end keeps the strap
    # within its 25 cm.
    grabbed, shut = handover + 3, s + 112
    b.targets["left_arm"].attach(handover, grabbed, blend(car.riding("edge_at_strap"), car.riding_strap(b), handover, grabbed))
    b.targets["left_arm"].attach(grabbed, shut, car.riding_strap(b))
    car.holds.append((handover, shut, "strap"))
    b.door.at(s + 101, (0.26,)).at(s + 104, (0.17,)).at(s + 107, (0.08,)).at(s + 110, (0.015,)).at(shut, (0.0,))
    b.pelvis.at(s + 101, (0.0, 3.0, -5.05)).at(s + 104, car.seated_pelvis + (0.0, 0.02, 0.0))
    b.pelvis.at(s + 107, car.seated_pelvis)
    b.torso.at(s + 104, (-3, -270, -2)).at(s + 108, (-2, -270, 3)).at(shut, (-2, -270, 6))
    b.neck.at(handover, (8, 22, 0)).at(shut, (-2, 16, 0))
    b.contact.append((handover - 2, shut + 2))
    # Settle: the right hand off the wall onto its thigh, the legs toward the pedals, the left hand
    # lets the strap go and rests.
    b.targets["right_arm"].at(s + 103, targets["right_arm"] + (0.25, 0.7, 0.05)).at(s + 108, targets["right_arm"])
    b.targets["right_leg"].at(s + 106, targets["right_leg"])
    b.targets["left_leg"].at(s + 106, targets["left_leg"])
    b.targets["left_arm"].at(shut + 6, targets["left_arm"] + (0.0, 0.35, 0.15))
    b.neck.at(e - 6, (-2, 4, 0))
    for limb in b.twist:
        b.twist[limb].at(s + 108, (0,))
    start_seated(b, car, e, seat)
    b.door.at(e, (0.0,))


# car_entry_hold.py --timeline entry --point edge_at_strap --from 186 --to 198 --stay 3
GETIN_RIDE = [  # frame offset from the meet, pelvis, (lean, yaw, roll)
    (0, (-0.050, 2.619, -2.970), (-11.70, -262.00, 1.31)),
    (1, (-0.069, 2.463, -3.088), (-13.11, -263.14, 1.88)),
    (2, (-0.092, 2.375, -3.198), (-14.69, -264.14, 1.98)),
    (3, (-0.123, 2.312, -3.317), (-16.74, -265.00, 1.51)),
    (4, (-0.138, 2.316, -3.494), (-19.70, -265.73, -0.98)),
    (5, (-0.148, 2.335, -3.619), (-22.36, -266.36, -3.82)),
    (6, (-0.167, 2.365, -3.708), (-23.98, -267.00, -6.00)),
    (7, (-0.134, 2.439, -3.801), (-24.71, -267.72, -8.62)),
    (8, (-0.118, 2.486, -3.872), (-24.01, -268.43, -10.29)),
    (9, (-0.092, 2.550, -3.931), (-22.89, -269.00, -11.66)),
    (10, (-0.061, 2.614, -3.973), (-21.83, -269.46, -12.35)),
    (11, (-0.047, 2.675, -4.003), (-20.73, -269.84, -12.46)),
    (12, (-0.048, 2.731, -4.034), (-20.68, -270.00, -12.04)),
]


def entry(car):
    """OutsideOpen 0-100, GetIn 100-228 (it ends seated with the door shut)."""
    b = Body(229, FPS)
    car.door_track = b.door
    seat = seated_targets(car)
    seat = ((0.0, SEATED_YAW, 0.0), seat[1])
    open_end, getin_end = 100, 228
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
    # Hands for the cabin wall and the lip, a lean forward over them. From the seat both are out of
    # an R6 arm's reach (Roblox's sit floats over this car's cushion): the hands reach for them and
    # push once the body has come close enough (Car.on_surface logs which frames touch).
    b.neck.at(s + 6, (-14, 30, 0))
    b.targets["right_arm"].at(s + 8, wall_r + (0.15, 0.5, -0.7))
    b.targets["left_arm"].at(s + 8, lip_l + (-0.3, 0.9, -0.6))
    b.targets["right_arm"].attach(s + 12, s + 50, car.on_surface(b, "right_arm", wall_r, "GetOut right hand on the cabin wall"))
    b.targets["left_arm"].attach(s + 13, s + 50, car.on_surface(b, "left_arm", lip_l, "GetOut left hand on the lip"))
    b.torso.at(s + 10, (-6, SEATED_YAW, 0))
    b.targets["right_leg"].at(s + 8, targets["right_leg"] + (0.0, -0.3, 0.3)).at(s + 18, targets["right_leg"] + (-0.2, -0.35, 0.5))
    b.targets["left_leg"].at(s + 8, targets["left_leg"] + (0.0, 0.2, 0.0))
    # Hoist out: up off the seat, over the wall, the right hand walking to the wall top.
    b.pelvis.at(s + 18, car.seated_pelvis + (0.05, 0.0, 0.3))
    b.torso.at(s + 18, (-16, SEATED_YAW + 2, 0))
    b.pelvis.at(s + 26, (0.0, 2.8, -4.15))
    b.torso.at(s + 26, (-18, SEATED_YAW + 4, 0))
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
    b.pelvis.at(s + 50, (PERCH_X, 2.42, -1.85))
    b.torso.at(s + 50, (12, -212, 0))
    b.targets["right_leg"].at(s + 50, (PERCH_X - 0.9, 2.2, -0.2))
    b.targets["left_leg"].at(s + 50, (PERCH_X + 0.1, 2.3, 0.2))
    b.neck.at(s + 46, (-8, -20, 0)).at(s + 54, (-16, 0, 0))
    # Down onto the lip, facing out; the feet reach for the ground.
    b.pelvis.at(s + 55, perch + (0, 0.42, -0.12)).at(s + 58, perch + (0, 0.06, -0.02)).at(s + 59, perch)
    b.torso.at(s + 55, (4, -184, 0)).at(s + 58, (0, FACING_OUT, 0))
    for limb in feet:
        b.targets[limb].at(s + 54, feet[limb] + (0, 0.55, -0.15)).at(s + 58, feet[limb] + (0, 0.12, 0))
        b.targets[limb].at(s + 60, feet[limb] + (0, 0.04, 0)).at(s + 62, feet[limb])
    hand_y = SILL_TOP + 0.18
    sill_r, sill_l = V([PERCH_X - 1.1, hand_y, -2.65]), V([PERCH_X + 0.6, hand_y, -2.75])
    b.targets["right_arm"].at(s + 54, sill_r + (0.1, 0.3, 0.1))
    b.targets["left_arm"].at(s + 54, sill_l + (-0.1, 0.3, 0.1))
    b.targets["right_arm"].attach(s + 57, s + 66, car.on_surface(b, "right_arm", sill_r, "GetOut right hand on the sill"))
    b.targets["left_arm"].attach(s + 57, s + 66, car.on_surface(b, "left_arm", sill_l, "GetOut left hand on the sill"))
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
    b.targets["right_leg"].at(s + 85, feet["right_leg"]).at(s + 86, feet["right_leg"] + (0, 0.06, 0))
    b.targets["right_leg"].at(s + 88, feet["right_leg"] * 0.6 + right_out * 0.4 + (0, 0.14, 0))
    b.targets["right_leg"].at(s + 91, feet["right_leg"] * 0.15 + right_out * 0.85 + (0, 0.12, 0)).at(s + 94, right_out)
    b.pelvis.at(s + 89, (PERCH_X + 0.05, 2.0, 0.15)).at(s + 95, (0.0, 2.0, 0.4))
    b.torso.at(s + 86, (-1, -170, 4)).at(s + 90, (-1, -140, 5)).at(s + 95, (-1, -100, 0))
    b.neck.at(s + 90, (-8, 30, 0))
    b.support += [(s + 96, s + 103, ["right_leg"]), (s + 104, s + 105, both)]
    b.targets["left_leg"].at(s + 95, feet["left_leg"]).at(s + 96, feet["left_leg"] + (0, 0.06, 0))
    b.targets["left_leg"].at(s + 98, feet["left_leg"] * 0.6 + left_home * 0.4 + (0, 0.14, 0))
    b.targets["left_leg"].at(s + 101, feet["left_leg"] * 0.15 + left_home * 0.85 + (0, 0.12, 0)).at(s + 104, left_home)
    b.pelvis.at(s + 104, (-0.1, 2.0, 0.2))
    b.torso.at(s + 97, (-1, -85, -4)).at(s + 104, (-1, -15, 0))
    b.neck.at(s + 102, (-4, -10, 0))
    b.support += [(s + 106, s + 111, ["left_leg"]), (s + 112, e, both)]
    b.targets["right_leg"].at(s + 105, right_out).at(s + 106, right_out + (0, 0.06, 0))
    b.targets["right_leg"].at(s + 108, right_out * 0.5 + right_home * 0.5 + (0, 0.14, 0))
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


def hold_report(body, car):
    """Per hold span: the door's range, how far the palm misses its hold point, and for the strap
    how long it must be (from where it is sewn to the palm) against its 25 cm."""
    lines = []
    for start, end, what in car.holds:
        door = body.door_values[start : end + 1]
        miss = max(body.misses[f]["left_arm"] for f in range(start, end + 1))
        line = f"  hold {what} f{start}-f{end}: door {door[0]:.3f} -> {door[-1]:.3f}, palm miss <= {miss:.3f}"
        if what == "strap":
            need = []
            for f in range(start, end + 1):
                palm = r6_fk.point(r6_fk.pose_parts(body.poses[f])["Left Arm"], r6_fk.HAND)
                need.append(float(np.linalg.norm(palm - car.door_at("strap_anchor", body.door_values[f]))))
            k = int(np.argmax(need))
            line += f", strap needed <= {need[k]:.3f} of {car.strap_length:.3f} (f{start + k})"
        lines.append(line)
    return lines


def reach_report(car):
    """Per declared hand-on-surface contact, the frames whose surface was within the arm's reach."""
    lines = []
    for label, log in car.reach.items():
        frames = sorted(log)
        touched = [f for f in frames if log[f]]
        spans, run = [], []
        for f in touched:
            if run and f != run[-1] + 1:
                spans.append((run[0], run[-1]))
                run = []
            run.append(f)
        if run:
            spans.append((run[0], run[-1]))
        lines.append(f"  reach {label} f{frames[0]}-f{frames[-1]}: within reach {spans or 'never'}")
    return lines


def emit(body, clips, out_dir, name, car=None):
    body.solve()
    data = body.keys(every=2, clips=clips, markers=[])
    write(os.path.join(out_dir, f"{name}.keys.json"), data)
    with open(os.path.join(out_dir, f"{name}.fk.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(body.fk_bake(), handle)
    misses = body.report_misses()
    print(f"{name}: {body.frames} frames, {len(data['joints']['RootJoint'])} keys per joint, {len(misses)} limb misses > 0.08")
    if car is not None:
        for line in hold_report(body, car) + reach_report(car):
            print(line)
        car.holds = []
        car.reach = {}
    spans = {}
    for f, limb, err in misses:
        spans.setdefault(limb, []).append((f, err))
    for limb, rows in spans.items():
        print(f"  {limb}: f{rows[0][0]}..f{rows[-1][0]}, worst {max(r[1] for r in rows)}")


def main(argv):
    scene, seat, rest, door, out_dir = argv
    car = Car(scene, seat, rest, door)
    os.makedirs(out_dir, exist_ok=True)
    emit(*entry(car), out_dir, "entry", car)
    emit(*exit_timeline(car), out_dir, "exit", car)
    emit(*close_timeline(car), out_dir, "close", car)
    emit(*seated(car), out_dir, "seated", car)


if __name__ == "__main__":
    main(sys.argv[1:])
