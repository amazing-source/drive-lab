"""
Solves the body, frame by frame, over a span where the authored beats take it into the car: for
each frame it moves the pelvis, the torso's turn, the neck and the free limbs as little as it can
off the authored pose and off its own previous frame, so that no part goes into the car (or the door
at that frame's openness, or the ground) deeper than the timeline's named contacts allow, while each
held limb keeps its point (a hand on a bar, a planted foot). car_entry_hold.py does this for one
hand on a moving door; this is the same idea for the whole body.

  python car_entry_clear.py <keys module> <scene.npz> <keys args...> --from F --to F --out table.json
      [--step 2] [--ignore harness]

The keys module (car_entry_dr458) provides `build(argv)` returning (body, allow, holds): `allow` is
the named contacts [{"from", "to", "parts", "groups", "depth"}], `holds` the limbs that must stay on
their authored target [{"from", "to", "limb"}]. The table is one beat per solved frame (pelvis,
torso, neck, limb targets), which the keys module adds back as beats. Re-run it whenever the beats,
the allowances or the scene change.
"""
import argparse
import importlib
import json
import math
import os
import sys

import numpy as np
from scipy.optimize import minimize
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r6_fk  # noqa: E402
from car_entry_check import HALF, rotation_about, sample  # noqa: E402

LIMB_PART = {"right_arm": "Right Arm", "left_arm": "Left Arm", "right_leg": "Right Leg", "left_leg": "Left Leg"}
POINT = {"right_arm": r6_fk.HAND, "left_arm": r6_fk.HAND, "right_leg": r6_fk.FOOT, "left_leg": r6_fk.FOOT}


class Scene:
    def __init__(self, path, spacing, ignore=(), box=None):
        d = np.load(path, allow_pickle=False)
        clouds, labels = [], []
        self.names = [g for g in [str(x) for x in d["groups"]] if g not in ignore] + ["door"]
        for k, g in enumerate(self.names[:-1]):
            pts = sample(d[f"v_{g}"].astype(float), d[f"f_{g}"], spacing)
            if box is not None:
                pts = pts[np.all((pts > box[0]) & (pts < box[1]), axis=1)]
            clouds.append(pts)
            labels.append(np.full(len(pts), k))
        self.cloud = np.concatenate(clouds)
        self.labels = np.concatenate(labels)
        self.tree = cKDTree(self.cloud)
        self.door0 = sample(d["v_door"].astype(float), d["f_door"], spacing) - d["hinge_pivot"]
        self.pivot, self.axis, self.angle = d["hinge_pivot"], d["hinge_axis"], float(d["open_angle"])

    def door(self, openness):
        pts = self.door0 @ rotation_about(self.axis, openness * self.angle).T + self.pivot
        return pts, cKDTree(pts)


def group_depths(points, labels, frame, half, names):
    """{group: depth} of the points inside the box (depth past its nearest face)."""
    if not len(points):
        return {}
    local = (points - frame[:3, 3]) @ frame[:3, :3]
    h = np.asarray(half)
    inside = np.all(np.abs(local) < h, axis=1)
    if not inside.any():
        return {}
    d = (h - np.abs(local[inside])).min(axis=1)
    best = np.zeros(len(names))
    np.maximum.at(best, labels[inside], d)
    return {names[k]: float(best[k]) for k in np.flatnonzero(best)}


def part_depths(scene, door, parts):
    out = {}
    door_pts, door_tree = door
    for part, half in HALF.items():
        m = parts[part]
        r = float(np.linalg.norm(half))
        idx = np.asarray(scene.tree.query_ball_point(m[:3, 3], r, return_sorted=False), dtype=int)
        g = group_depths(scene.cloud[idx], scene.labels[idx], m, half, scene.names) if len(idx) else {}
        idx = np.asarray(door_tree.query_ball_point(m[:3, 3], r, return_sorted=False), dtype=int)
        if len(idx):
            dd = group_depths(door_pts[idx], np.full(len(idx), len(scene.names) - 1), m, half, scene.names)
            g.update(dd)
        low = float(((CORNERS * np.asarray(half)) @ m[:3, :3].T + m[:3, 3])[:, 1].min())
        if low < 0:
            g["ground"] = -low
        out[part] = g
    return out


CORNERS = np.array([[sx, sy, sz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)], dtype=float)


def fast_aim(torso, limb, target, local, start, iterations=8):
    """Swing X and spread Z putting the limb's `local` point on `target`: Gauss-Newton from a warm
    start (r6_fk.aim's least_squares is exact but ~20 times slower, too slow inside an optimiser)."""
    joint = r6_fk.LIMB_JOINT[limb]
    local = np.asarray(local, dtype=float)

    def miss(v):
        m = r6_fk.limb_frame(torso, joint, (v[0], 0.0, v[1]))
        return m[:3, :3] @ local + m[:3, 3] - target

    v = np.asarray(start, dtype=float).copy()
    for _ in range(iterations):
        e = miss(v)
        jac = np.empty((3, 2))
        for k in range(2):
            dv = v.copy()
            dv[k] += 0.5
            jac[:, k] = (miss(dv) - e) / 0.5
        step, *_ = np.linalg.lstsq(jac, -e, rcond=None)
        v += np.clip(step, -30.0, 30.0)
        if np.linalg.norm(step) < 1e-3:
            break
    return (float(v[0]), 0.0, float(v[1])), float(np.linalg.norm(miss(v)))


def allowed(allow, frame, part, group, tol):
    a = tol
    for e in allow:
        if e["from"] <= frame <= e["to"] and part in e["parts"] and group in e["groups"]:
            a = max(a, e.get("depth", 0.0))
    return a


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("module")
    ap.add_argument("scene")
    ap.add_argument("--from", dest="start", type=int, required=True)
    ap.add_argument("--to", dest="end", type=int, required=True)
    ap.add_argument("--step", type=int, default=2)
    ap.add_argument("--out", required=True)
    ap.add_argument("--ignore", default="", help="groups left out (e.g. geometry about to move)")
    ap.add_argument("--spacing", type=float, default=0.07)
    ap.add_argument("--margin", type=float, default=0.03, help="studs kept below each allowance")
    ap.add_argument("--stay", type=float, default=0.05)
    ap.add_argument("--smooth", type=float, default=0.5)
    ap.add_argument("--limb-stay", type=float, default=0.02, help="weight of a free limb's end off its authored target")
    ap.add_argument("--pin", type=int, default=None, help="from this frame the body keeps its authored pose (eased in over --pin-ease frames)")
    ap.add_argument("--pin-ease", type=int, default=12)
    ap.add_argument("--iters", type=int, default=1500)
    a, rest = ap.parse_known_args(argv)
    mod = importlib.import_module(a.module)
    body, allow, holds = mod.build([a.scene] + rest)
    frames = list(range(a.start, a.end + 1, a.step))
    if frames[-1] != a.end:
        frames.append(a.end)
    # The region the body can reach over the span: its authored pelvis path padded by a body length.
    path = body.pelvis.sample(np.array(frames, float))
    scene = Scene(a.scene, a.spacing, [g for g in a.ignore.split(",") if g], box=(path.min(axis=0) - 5.0, path.max(axis=0) + 5.0))
    tracks = {
        "pelvis": body.pelvis.sample(np.array(frames, float)),
        "torso": body.torso.sample(np.array(frames, float)),
        "neck": body.neck.sample(np.array(frames, float)),
        "neck_loc": body.neck_loc.sample(np.array(frames, float)) if body.neck_loc.beats else np.zeros((len(frames), 3)),
        "door": body.door.sample(np.array(frames, float))[:, 0],
    }
    targets = {k: t.sample(np.array(frames, float)) for k, t in body.targets.items()}
    table, previous = {}, None
    guess = {k: np.array(body.guess[k], dtype=float) for k in LIMB_PART}
    for i, f in enumerate(frames):
        held = [h["limb"] for h in holds if h["from"] <= f <= h["to"]]
        free = [k for k in LIMB_PART if k not in held]
        door = scene.door(float(tracks["door"][i]))
        pel0, tor0, nek0 = tracks["pelvis"][i], tracks["torso"][i], tracks["neck"][i]
        neck_loc = tuple(tracks["neck_loc"][i])
        stay = a.stay
        if a.pin is not None and f > a.pin - a.pin_ease:
            u = min(1.0, (f - (a.pin - a.pin_ease)) / a.pin_ease)
            stay = a.stay * 10 ** (5 * u)

        def pose_of(x):
            pel, tor, nek = x[0:3], x[3:6], (x[6], nek0[1], x[7])
            rot = r6_fk.body_turn(*tor)
            loc = r6_fk.torso_root_offset(rot, pel - np.array([0.0, r6_fk.ROOT_HEIGHT, 0.0]))
            pose = {"RootJoint": (rot, tuple(loc)), "Neck": (tuple(nek), neck_loc)}
            misses = 0.0
            torso = r6_fk.pose_parts({"RootJoint": pose["RootJoint"]})["Torso"]
            for limb in held:
                angles, miss = fast_aim(torso, limb, targets[limb][i], POINT[limb], guess[limb])
                pose[r6_fk.LIMB_JOINT[limb]] = (angles, (0, 0, 0))
                misses += miss * miss
            for k, limb in enumerate(free):
                pose[r6_fk.LIMB_JOINT[limb]] = ((x[8 + 2 * k], 0.0, x[9 + 2 * k]), (0, 0, 0))
            return pose, misses

        def cost(x):
            pose, misses = pose_of(x)
            parts = r6_fk.pose_parts(pose)
            c = 0.0
            for part, groups in part_depths(scene, door, parts).items():
                for g, d in groups.items():
                    lim = allowed(allow, f, part, g, 0.04) - a.margin
                    if d > lim:
                        c += (d - lim) ** 2
            c = 400 * c + 400 * misses
            c += stay * (float(np.sum((x[0:3] - pel0) ** 2)) + 1e-3 * float(np.sum((x[3:8] - np.r_[tor0, nek0[0], nek0[2]]) ** 2)))
            for limb in free:
                c += a.limb_stay * float(np.sum((r6_fk.point(parts[LIMB_PART[limb]], POINT[limb]) - targets[limb][i]) ** 2))
            if previous is not None:
                c += a.smooth * (10 * float(np.sum((x[0:3] - previous[0:3]) ** 2)) + 1e-2 * float(np.sum((x[3:8] - previous[3:8]) ** 2)))
                c += a.smooth * 1e-3 * float(np.sum((x[8:] - previous_limbs(previous, free)) ** 2))
            return c

        def excess_of(x):
            pose, misses = pose_of(x)
            parts = r6_fk.pose_parts(pose)
            worst = math.sqrt(misses) - 0.02
            for part, groups in part_depths(scene, door, parts).items():
                for g, d in groups.items():
                    worst = max(worst, d - allowed(allow, f, part, g, 0.04))
            return worst

        def previous_limbs(prev, free_now):
            out = []
            for limb in free_now:
                out += list(prev_angles.get(limb, (0.0, 0.0)))
            return np.array(out)

        if previous is None:
            prev_angles = {}
            base_pose, _ = pose_of(np.r_[pel0, tor0, nek0[0], nek0[2], np.zeros(2 * len(free))])
            for limb in free:
                ang, _ = r6_fk.aim(base_pose, limb, targets[limb][i], POINT[limb], guess=tuple(guess[limb]))
                prev_angles[limb] = (ang[0], ang[2])
            x0 = np.r_[pel0, tor0, nek0[0], nek0[2], [v for limb in free for v in prev_angles[limb]]]
        else:
            # Start from the authored move since the last frame, applied to the last solution.
            x0 = np.r_[previous[0:3] + (pel0 - last_authored[0]), previous[3:6] + (tor0 - last_authored[1]), previous[6], previous[7]]
            for limb in free:
                if limb not in prev_angles:
                    base_pose, _ = pose_of(np.r_[x0[0:8], np.zeros(2 * len(free))])
                    ang, _ = r6_fk.aim(base_pose, limb, targets[limb][i], POINT[limb], guess=tuple(guess[limb]))
                    prev_angles[limb] = (ang[0], ang[2])
            x0 = np.r_[x0, [v for limb in free for v in prev_angles[limb]]]
        # A frame the authored beats already keep within every allowance is left as authored.
        authored_pose, _ = pose_of(np.r_[pel0, tor0, nek0[0], nek0[2], np.zeros(2 * len(free))])
        authored = [pel0, tor0, [nek0[0], nek0[2]]]
        for limb in free:
            ang, _ = r6_fk.aim(authored_pose, limb, targets[limb][i], POINT[limb], guess=tuple(prev_angles.get(limb, guess[limb])))
            authored.append([ang[0], ang[2]])
        x_auth = np.concatenate([np.asarray(v, dtype=float) for v in authored])
        if excess_of(x_auth) <= 0.0:
            x = x_auth
        else:
            x = minimize(cost, x0, method="Powell", options={"maxfev": a.iters, "xtol": 1e-3, "ftol": 1e-8}).x
        pose, misses = pose_of(x)
        parts = r6_fk.pose_parts(pose)
        worst = []
        for part, groups in part_depths(scene, door, parts).items():
            for g, d in groups.items():
                lim = allowed(allow, f, part, g, 0.04)
                if d > lim:
                    worst.append(f"{part}/{g} {d:.3f}>{lim:.3f}")
        for limb in held:
            guess[limb] = np.array(pose[r6_fk.LIMB_JOINT[limb]][0])[[0, 2]]
        prev_angles = {limb: (x[8 + 2 * k], x[9 + 2 * k]) for k, limb in enumerate(free)}
        previous = x
        last_authored = (pel0, tor0)
        row = {
            "pelvis": [round(float(v), 4) for v in x[0:3]],
            "torso": [round(float(v), 3) for v in x[3:6]],
            "neck": [round(float(x[6]), 3), round(float(nek0[1]), 3), round(float(x[7]), 3)],
            "targets": {},
        }
        for limb in free:
            row["targets"][limb] = [round(float(v), 4) for v in r6_fk.point(parts[LIMB_PART[limb]], POINT[limb])]
        table[str(f)] = row
        moved = float(np.linalg.norm(x[0:3] - pel0))
        print(f"f{f}: moved {moved:.3f}, miss {np.sqrt(misses):.3f}, {'; '.join(worst) or 'clear'}", flush=True)
        json.dump(table, open(a.out, "w", encoding="utf-8", newline="\n"), indent=0)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
