"""
Solves the body, frame by frame, for a span where the left hand holds a moving door point, so the
hold is exact between beats instead of interpolated.

An R6 arm has no elbow: its palm is always ARM_REACH from the shoulder joint, so a hand can hold a
point only if the body puts its shoulder exactly that far from it, with the arm, head and torso
clear of the door at that frame's openness and of the car. Interpolating a few solved beats does
not keep that (between two beats the arm went 0.127 studs into the door), so every frame is
solved, each from the previous frame's answer.

For each frame it moves the pelvis and the torso's lean and roll (the yaw stays authored) away
from the timeline's own authored pose, and from its own previous frame, as little as it can,
subject to: the palm on the hold point
(the door point with its PALM_OFF, at that frame's openness), the arm no deeper in the door than
--arm-allow, and head and torso clear. It prints the table car_entry_keys.py takes as beats.

  python car_entry_hold.py <scene.npz> <SEAT_WELD.json> <REST_POSE.json> <door.json>
      --timeline entry --point edge_at_strap --from 186 --to 198 [--arm-allow 0.1]

Re-run it whenever the timeline's door beats or the authored pose around the span change.
"""
import argparse
import os
import sys

import numpy as np
from scipy.optimize import minimize
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import car_entry_keys as K  # noqa: E402
import r6_fk  # noqa: E402
from car_entry_check import HALF, depths, sample  # noqa: E402
from car_scene import rotation_about  # noqa: E402

SPACING = 0.06


class Scene:
    def __init__(self, path):
        d = np.load(path, allow_pickle=False)
        self.door = sample(d["v_door"].astype(float), d["f_door"], SPACING)
        self.pivot, self.axis, self.angle = d["hinge_pivot"], d["hinge_axis"], float(d["open_angle"])
        body = [sample(d[f"v_{g}"].astype(float), d[f"f_{g}"], SPACING) for g in [str(g) for g in d["groups"]]]
        self.car = np.concatenate(body)
        self.car_tree = cKDTree(self.car)

    def door_at(self, openness):
        pts = (self.door - self.pivot) @ rotation_about(self.axis, openness * self.angle)[:3, :3].T + self.pivot
        return pts, cKDTree(pts)


def depth_in(points, tree, frame, half):
    idx = tree.query_ball_point(frame[:3, 3], float(np.linalg.norm(half)))
    return depths(points[idx], frame, half, 0.0)[0] if idx else 0.0


def evaluate(scene, door, pelvis, turn, target, guess):
    rot = r6_fk.body_turn(*turn)
    loc = r6_fk.torso_root_offset(rot, np.asarray(pelvis) - np.array([0.0, r6_fk.ROOT_HEIGHT, 0.0]))
    pose = {"RootJoint": (rot, tuple(loc)), "Neck": ((0, 0, 0), (0, 0, 0))}
    angles, miss = r6_fk.aim(pose, "left_arm", target, r6_fk.HAND, guess=guess)
    pose["Left Shoulder"] = (angles, (0, 0, 0))
    parts = r6_fk.pose_parts(pose)
    out = {"miss": miss, "guess": (angles[0], angles[2])}
    for part in ("Left Arm", "Head", "Torso"):
        out[part] = (depth_in(door[0], door[1], parts[part], HALF[part]), depth_in(scene.car, scene.car_tree, parts[part], HALF[part]))
    return out


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("scene")
    ap.add_argument("seat")
    ap.add_argument("rest")
    ap.add_argument("door")
    ap.add_argument("--timeline", default="entry")
    ap.add_argument("--point", required=True)
    ap.add_argument("--from", dest="start", type=int, required=True)
    ap.add_argument("--to", dest="end", type=int, required=True)
    ap.add_argument("--arm-allow", type=float, default=0.1)
    ap.add_argument("--smooth", type=float, default=1.0, help="weight of frame-to-frame change")
    ap.add_argument("--stay", type=float, default=1.0, help="weight of the pelvis's move off the authored path")
    a = ap.parse_args(argv)
    car = K.Car(a.scene, a.seat, a.rest, a.door)
    body, _ = {"entry": K.entry, "exit": K.exit_timeline, "close": K.close_timeline}[a.timeline](car)
    scene = Scene(a.scene)
    frames = np.arange(a.start, a.end + 1)
    openness = body.door.sample(frames)[:, 0]
    pelvis0 = body.pelvis.sample(frames)
    turn0 = body.torso.sample(frames)
    previous = None
    guess = (150.0, 40.0)
    rows = []
    for i, f in enumerate(frames):
        door = scene.door_at(openness[i])
        target = car.door_at(a.point, openness[i])
        yaw = turn0[i][1]

        def cost(x):
            e = evaluate(scene, door, x[:3], (x[3], yaw, x[4]), target, guess)
            pen = max(0.0, e["Left Arm"][0] - a.arm_allow) ** 2 + max(0.0, e["Left Arm"][1] - 0.1) ** 2
            pen += e["Head"][0] ** 2 + e["Head"][1] ** 2 + e["Torso"][0] ** 2 + max(0.0, e["Torso"][1] - 0.02) ** 2
            c = 400 * e["miss"] ** 2 + 400 * pen
            c += a.stay * float(np.sum((x[:3] - pelvis0[i]) ** 2)) + 1e-4 * ((x[3] - turn0[i][0]) ** 2 + (x[4] - turn0[i][2]) ** 2)
            if previous is not None:
                # Smooth from frame to frame: a solved pose may not twitch to a far branch.
                c += a.smooth * (10 * float(np.sum((x[:3] - previous[:3]) ** 2)) + 0.01 * float(np.sum((x[3:] - previous[3:]) ** 2)))
            return c

        start = np.r_[pelvis0[i], turn0[i][0], turn0[i][2]] if previous is None else previous
        found = minimize(cost, start, method="Nelder-Mead", options={"xatol": 1e-3, "fatol": 1e-6, "maxiter": 1500})
        x = found.x
        e = evaluate(scene, door, x[:3], (x[3], yaw, x[4]), target, guess)
        guess = e["guess"]
        previous = x
        rows.append((int(f), float(openness[i]), x, yaw, e))
        print(
            f"# f{f} door {openness[i]:.3f}: miss {e['miss']:.3f}, arm in door {e['Left Arm'][0]:.3f} car {e['Left Arm'][1]:.3f},"
            f" head {e['Head'][0]:.3f}/{e['Head'][1]:.3f}, torso {e['Torso'][0]:.3f}/{e['Torso'][1]:.3f}",
            flush=True,
        )
    print("RIDE = [  # frame offset from the span's start, pelvis, (lean, yaw, roll)")
    for f, _, x, yaw, _ in rows:
        print(f"    ({f - a.start}, ({x[0]:.3f}, {x[1]:.3f}, {x[2]:.3f}), ({x[3]:.2f}, {yaw:.2f}, {x[4]:.2f})),")
    print("]")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
