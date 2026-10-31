"""
Smooths a car_entry_track.py table: each pass moves every frame's pelvis, torso, neck and limb
angles toward the 1-2-1 average of its neighbours, and keeps the move only where no part goes
deeper past its named allowance, in any group, than it did before (held limbs are re-aimed at their points,
limbs with fixed angles are left alone). A per-frame search can leave small pops between
frames; this takes out the ones the contacts do not force.

  python car_entry_smooth.py <keys module> <scene.npz> <keys args...> --table in.json --out out.json
      [--passes 6] [--repair 40] [--spacing 0.05]

--repair N: after each smoothing pass, N random small joint moves on every frame still past an
allowance, kept only when the total excess drops and no group goes deeper.
--polish F0-F1: after the passes, a pattern search of the body and the free limbs on each frame of
the span still past an allowance (deepest excess first, then the total, then the distance to the
neighbours' average), kept on the same terms. --margin keeps every part that far under its
allowances: the house check samples its own cloud, so a pose exactly on a limit can fail there.
"""
import argparse
import importlib
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r6_fk  # noqa: E402
from car_entry_check import HALF  # noqa: E402
from car_entry_clear import LIMB_PART, POINT, Scene, allowed  # noqa: E402
from car_entry_track import held_aim, part_depth, pattern, rank  # noqa: E402

# The largest repair move: pelvis (studs), torso and neck angles, then each limb's swing and spread.
REPAIR_STEP = np.r_[[0.04] * 3, [3.0] * 3, [5.0] * 2, [6.0] * 8]


def vector(row, previous):
    """A row as one vector; a held limb (no angles in the table) starts from the previous frame's."""
    angles = row["angles"]
    held = [previous[8 + 2 * k: 10 + 2 * k] if previous is not None else np.zeros(2) for k in range(len(LIMB_PART))]
    return np.r_[row["pelvis"], row["torso"], row["neck"][0], row["neck"][2], [v for k, limb in enumerate(LIMB_PART) for v in angles.get(limb, held[k])]]


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("module")
    ap.add_argument("scene")
    ap.add_argument("--table", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--passes", type=int, default=6)
    ap.add_argument("--spacing", type=float, default=0.05)
    ap.add_argument("--repair", type=int, default=0, help="random trials per pass on each frame still past an allowance")
    ap.add_argument("--polish", default="", help="F0-F1: pattern search on each frame of the span still past an allowance")
    ap.add_argument("--margin", type=float, default=0.0, help="studs kept under every allowance")
    a, rest = ap.parse_known_args(argv)
    mod = importlib.import_module(a.module)
    body, allow, holds = mod.build([a.scene] + rest)
    table = json.load(open(a.table, encoding="utf-8"))
    frames = sorted(int(f) for f in table)
    at = np.array(frames, float)
    path = np.array([table[str(f)]["pelvis"] for f in frames])
    scene = Scene(a.scene, a.spacing, box=(path.min(axis=0) - 5.0, path.max(axis=0) + 5.0))
    door_t = dict(zip(frames, body.door.sample(at)[:, 0]))
    loc_t = dict(zip(frames, body.neck_loc.sample(at) if body.neck_loc.beats else np.zeros((len(frames), 3))))
    targets = {k: dict(zip(frames, t.sample(at))) for k, t in body.targets.items()}
    doors = {}

    def evaluate(f, x, turn):
        held = [h["limb"] for h in holds if h["from"] <= f <= h["to"]]
        key = round(float(door_t[f]), 4)
        if key not in doors:
            doors.clear()
            doors[key] = scene.door(key)
        rot = r6_fk.body_turn(*x[3:6])
        loc = r6_fk.torso_root_offset(rot, x[0:3] - np.array([0.0, r6_fk.ROOT_HEIGHT, 0.0]))
        pose = {"RootJoint": (rot, tuple(loc)), "Neck": ((x[6], turn, x[7]), tuple(loc_t[f]))}
        excess, misses = {}, 0.0
        for k, limb in enumerate(LIMB_PART):
            ang = (x[8 + 2 * k], 0.0, x[9 + 2 * k])
            if limb in held and f not in body.fixed.get(limb, {}):
                ang, miss = held_aim(pose["RootJoint"], limb, targets[limb][f], (ang[0], ang[2]))
                x[8 + 2 * k], x[9 + 2 * k] = ang[0], ang[2]
                misses = max(misses, miss)
            pose[r6_fk.LIMB_JOINT[limb]] = (ang, (0, 0, 0))
        parts = r6_fk.pose_parts(pose)
        for part in HALF:
            for g, d in part_depth(scene, doors[key], part, parts[part]).items():
                excess[(part, g)] = rank(d - allowed(allow, f, part, g, 0.04) + a.margin)
        excess["miss"] = rank(misses - 0.02)
        return excess, parts

    xs, previous = {}, None
    for f in frames:
        xs[f] = previous = vector(table[str(f)], previous)
        # A limb the choreography holds is at its held angles, whatever the table says there.
        for k, limb in enumerate(LIMB_PART):
            if f in body.fixed.get(limb, {}):
                xs[f][8 + 2 * k: 10 + 2 * k] = body.fixed[limb][f]
    turn = {f: table[str(f)]["neck"][1] for f in frames}
    base = {f: evaluate(f, xs[f], turn[f])[0] for f in frames}
    locked = {f: [k for k, limb in enumerate(LIMB_PART) if f in body.fixed.get(limb, {})] for f in frames}
    rng = np.random.default_rng(458)
    planted = {f for s0, s1, _ in body.support for f in range(s0, s1 + 1)}
    for p in range(a.passes):
        accepted = 0
        for f in frames[1:-1]:
            if f - 1 not in xs or f + 1 not in xs:
                continue
            trial = (xs[f - 1] + 2 * xs[f] + xs[f + 1]) / 4
            if f in planted:
                # The bake solves a planted stance from the authored body: only the limbs move.
                trial[0:8] = xs[f][0:8]
            for k in locked[f]:
                trial[8 + 2 * k: 10 + 2 * k] = xs[f][8 + 2 * k: 10 + 2 * k]
            r, _ = evaluate(f, trial, turn[f])
            # Kept only if no part goes deeper past its allowance in any group than before.
            if all(v <= max(base[f].get(k, 0), 0) for k, v in r.items()):
                xs[f], base[f] = trial, r
                accepted += 1
        repaired = 0
        for f in frames[1:-1] if a.repair else []:
            if max(base[f].values()) <= 0:
                continue
            # Small joint moves of the body and every free limb around this frame, kept when the
            # total excess drops and no group goes deeper than before (a group that was clear
            # stays clear).
            for _ in range(a.repair):
                trial = xs[f] + rng.uniform(-1.0, 1.0, len(xs[f])) * REPAIR_STEP
                if f in planted:
                    trial[0:8] = xs[f][0:8]
                for k in locked[f]:
                    trial[8 + 2 * k: 10 + 2 * k] = xs[f][8 + 2 * k: 10 + 2 * k]
                r, _ = evaluate(f, trial, turn[f])
                if sum(max(v, 0) for v in r.values()) < sum(max(v, 0) for v in base[f].values()) and all(v <= max(base[f].get(k, 0), 0) for k, v in r.items()):
                    xs[f], base[f] = trial, r
                    repaired += 1
        print(f"pass {p + 1}: {accepted} of {len(frames) - 2} frames smoothed, {repaired} repair moves", flush=True)
    if a.polish:
        f0, f1 = (int(v) for v in a.polish.split("-"))
        for f in frames[1:-1]:
            if not f0 <= f <= f1 or f - 1 not in xs or f + 1 not in xs or max(base[f].values()) <= 0:
                continue
            x0, mid, was = xs[f].copy(), (xs[f - 1] + xs[f + 1]) / 2, base[f]
            free = np.ones(len(x0), dtype=bool)
            if f in planted:
                free[0:8] = False
            for k in locked[f]:
                free[8 + 2 * k: 10 + 2 * k] = False

            def key(v):
                x = np.where(free, v, x0)
                r, _ = evaluate(f, x.copy(), turn[f])
                if any(e > max(was.get(k, 0), 0) for k, e in r.items()):
                    return (math.inf, math.inf, math.inf)
                over = [max(e, 0) for e in r.values()]
                return (max(over), sum(over), float(np.sum(((x - mid) / REPAIR_STEP) ** 2)))

            _, v = pattern(key, x0, [REPAIR_STEP, REPAIR_STEP / 2, REPAIR_STEP / 4], rng)
            x = np.where(free, v, x0)
            r, _ = evaluate(f, x, turn[f])
            if sum(max(e, 0) for e in r.values()) < sum(max(e, 0) for e in was.values()) and all(e <= max(was.get(k, 0), 0) for k, e in r.items()):
                xs[f], base[f] = x, r
            print(f"polish f{f}: deepest {max(was.values())} -> {max(base[f].values())} (steps of 0.002 past an allowance)", flush=True)
    out = {}
    for f in frames:
        x = xs[f]
        _, parts = evaluate(f, x, turn[f])
        held = [h["limb"] for h in holds if h["from"] <= f <= h["to"]]
        out[str(f)] = {
            "pelvis": [round(float(v), 4) for v in x[0:3]],
            "torso": [round(float(v), 3) for v in x[3:6]],
            "neck": [round(float(x[6]), 3), turn[f], round(float(x[7]), 3)],
            "targets": {limb: [round(float(v), 4) for v in r6_fk.point(parts[LIMB_PART[limb]], POINT[limb])] for limb in LIMB_PART if limb not in held},
            "angles": {limb: [round(float(x[8 + 2 * k]), 3), round(float(x[9 + 2 * k]), 3)] for k, limb in enumerate(LIMB_PART) if limb not in held},
        }
    json.dump(out, open(a.out, "w", encoding="utf-8", newline="\n"), indent=0)
    print("frames over an allowance:", sum(1 for f in frames if max(base[f].values()) > 0))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
