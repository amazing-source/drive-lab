"""Clearance of the right hand and its drawn forearm to the steering wheel along a baked start-up
path (the paths.json tools/blender/startup_paths.py writes), sampled as startup_check samples it.

  python tools/anim/startup_clearance.py <paths.json> [--prefix GEO_INT_STwheel] [--from s] [--to s] [--json out]

Per sample: the hand mesh's clearance to the wheel's objects (negative: the depth by startup_check's
nearest-sample vote, without its ray-parity pass, so a reading, not a verdict), the forearm capsule's,
and the wrist in the wheel frame (metres from the column's axis, degrees from 3 o'clock, metres toward
the driver). startup_check.py is what passes or fails a path.
"""

import json
import math
import os
import sys

import numpy as np
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import startup_check as sc  # noqa: E402


def option(argv, name, default):
    return argv[argv.index(name) + 1] if name in argv else default


def main(argv):
    record = json.load(open(argv[0]))
    prefix = option(argv, "--prefix", "GEO_INT_STwheel")
    start, end = float(option(argv, "--from", 0)), float(option(argv, "--to", 99))
    inputs, studs = record["inputs"], record["studsPerMetre"]
    data = np.load(inputs["cabin"])
    rel = data["vertices"].astype(float) - np.array(inputs["seat"])
    verts = np.stack([-rel[:, 0], rel[:, 2], rel[:, 1]], 1)
    names, owner, tris = list(data["names"]), data["object"], data["triangles"]
    mask = np.isin(owner, [i for i, n in enumerate(names) if str(n).startswith(prefix)])
    points, normals, _ = sc.surface_samples(verts, tris[mask], sc.SPACING, np.flatnonzero(mask))
    tree = cKDTree(points)
    wheel = np.array(record["wheel"])
    axes, pivot = wheel[:3, :3], wheel[:3, 3] / studs

    shapes = {s: sc.read_glb(f"{inputs['posesDir']}/hand_{s}_R.glb") for s in ("Rest", "Point", "Pinch")}
    grip = np.array(record["gripLocal"]["R"])
    shapes["Grip"] = (sc.read_glb(f"{inputs['gripDir']}/hand_R.glb") - grip[:3, 3] / studs) @ grip[:3, :3]
    arm = record["arm"]
    upper, lower, shoulder0 = arm["upper"] / studs, arm["lower"] / studs, np.array(arm["shoulders"]["R"]) / studs

    track = record["right"]
    times = np.array([s["t"] for s in track])
    pos = np.array([s["p"] for s in track]) / studs
    count = len(track)

    def slope(i):
        before, after = max(i - 1, 0), min(i + 1, count - 1)
        span = times[after] - times[before]
        return (pos[after] - pos[before]) / span if span > 0 else np.zeros(3)

    rows = []
    for i in range(count):
        for frac in [0.0] if i == count - 1 else [0.0, 0.5]:
            span = 0.0 if i == count - 1 else times[i + 1] - times[i]
            s2, s3 = frac * frac, frac**3
            p = pos[i] if frac == 0 else (2 * s3 - 3 * s2 + 1) * pos[i] + (s3 - 2 * s2 + frac) * span * slope(i) + (-2 * s3 + 3 * s2) * pos[i + 1] + (s3 - s2) * span * slope(i + 1)
            q = track[i]["q"] if frac == 0 else sc.slerp(track[i]["q"], track[i + 1]["q"], frac)
            t = times[i] + span * frac
            if t < start - 1e-9 or t > end + 1e-9:
                continue
            r, shape = sc.quat_matrix(q), track[i]["shape"]
            hand = shapes[shape] @ r.T + p
            gap, _ = tree.query(hand)
            depth, _ = sc.inside_depth(tree, points, normals, hand)
            hand_mm = -depth.max() if depth.max() > 0 else gap.min()
            turn, lean_pivot = sc.lean_turn(record.get("lean"), t)
            shoulder = lean_pivot + turn @ (shoulder0 - lean_pivot)
            joint = sc.elbow(shoulder, p, r[:, 2], 1, upper, lower, list(turn @ np.array(arm["elbowBias"], float)))
            ab = p - joint
            u = np.clip(((points - joint) @ ab) / (ab @ ab), 0, 1)
            forearm = np.linalg.norm(points - (joint + ab[None] * u[:, None]), axis=1).min() - sc.FOREARM_RADIUS
            w = (p - pivot) @ axes
            rows.append(
                {
                    "t": round(float(t), 4),
                    "shape": shape,
                    "handMm": round(float(hand_mm) * 1000, 1),
                    "forearmMm": round(float(forearm) * 1000, 1),
                    "wrist": [round(math.hypot(w[0], w[1]), 4), round(math.degrees(math.atan2(w[1], w[0])), 1), round(float(w[2]), 4)],
                }
            )
    for row in rows:
        r_, deg, ax = row["wrist"]
        print(f"t {row['t']:6.3f} {row['shape']:5} hand {row['handMm']:7.1f} mm  forearm {row['forearmMm']:7.1f} mm  wrist r {r_:.3f} m {deg:6.1f} deg axial {ax:+.3f} m")
    low_hand = min(rows, key=lambda row: row["handMm"])
    low_arm = min(rows, key=lambda row: row["forearmMm"])
    print(f"least: hand {low_hand['handMm']} mm at {low_hand['t']} s, forearm {low_arm['forearmMm']} mm at {low_arm['t']} s ({prefix}*, {start}-{end} s)")
    if "--json" in argv:
        json.dump({"paths": argv[0], "prefix": prefix, "from": start, "to": end, "rows": rows}, open(option(argv, "--json", None), "w"), indent=1)


if __name__ == "__main__":
    main(sys.argv[1:])
