"""Reach, penetration and contact check for a car's gear-lever hand (shift_paths.py's paths.json),
against the cabin dump it was keyed in.

  python tools/anim/shift_check.py <paths.json> [--json <out.json>] [--break <dx>,<dy>,<dz>]
      [--ignore <name>,...] [--hand <glb>]

For every ordered pair of gates, the lever is moved along Vehicle/ShiftPlan's path (out of the gate,
the knob down into reverse, across the rail, into the gate) and the hand rides it; the way between
the steering grip and the knob is sampled as Rules/ShiftHand plays it, ending on each gate's knob.
At every place:
- the arm the controller draws (shoulder, elbow from its rule, wrist) must reach the wrist within
  REACH_SHARE of its length;
- the forearm and the upper arm, as capsules of the sleeves' half-widths, must stay ARM_LIMIT clear
  of the cabin (startup_check's segment depth);
- the hand mesh (the open hand stands in for the knob grip until it exists) must not sink more than
  HAND_LIMIT into the cabin (startup_check's vote, within MAX_DEPTH);
- on the knob, the palm must be within TOUCH_GAP of the ball's surface (the hand holds it).
Objects named in --ignore (the lever's own parts, its boot) are left out. `--break` moves the whole
lever by that many metres (seat frame) and must turn the run red. Exits 1 on any failure.
"""
import json
import math
import os
import sys

import numpy as np
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gesture_paths import STUDS, Arm, Frame, cabin_in, quat_matrix, sample  # noqa: E402
from shift_paths import Shifter, compose, path_states  # noqa: E402
from startup_check import inside_depth, read_glb, segment_depth, surface_samples  # noqa: E402

REACH_SHARE = 0.96
ARM_LIMIT = 0.005
HAND_LIMIT = 0.002
TOUCH_GAP = 0.008
SPACING = 0.003
REGION_MARGIN = 0.15
# Sleeve half-widths, metres (the smaller of each modelled cross-section, as startup_check uses).
UPPER_HALF, LOWER_HALF = 0.045, 0.035


def key_frame(key):
    return Frame(quat_matrix(key[4:8]), key[1:4])


def retarget(frame, frm, to, share):
    """Rules/StartupArms.retarget on frames."""
    turn = to.rot @ frm.rot.T
    angle = math.acos(max(-1.0, min(1.0, (np.trace(turn) - 1) / 2)))
    if angle < 1e-9:
        partial = np.eye(3)
    else:
        axis = np.array([turn[2, 1] - turn[1, 2], turn[0, 2] - turn[2, 0], turn[1, 0] - turn[0, 1]]) / (2 * math.sin(angle))
        k = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
        a = angle * share
        partial = np.eye(3) + math.sin(a) * k + (1 - math.cos(a)) * (k @ k)
    return Frame(partial @ frame.rot, frame.pos + (to.pos - frm.pos) * share)


def hand_on_way(keys, share, grip, knob_wrist):
    """Rules/ShiftHand.pose: the keyed way by share, its start carried onto the live grip and its end
    onto the live knob."""
    first, last = key_frame(keys[0]), key_frame(keys[-1])
    t = keys[0][0] + (keys[-1][0] - keys[0][0]) * share
    to_end = share * share * (3 - 2 * share)
    pos, q = sample(keys, t)
    frame = Frame(quat_matrix(q), pos)
    frame = retarget(frame, first, grip, 1 - to_end)
    return retarget(frame, last, knob_wrist, to_end)


def main(argv):
    paths_path = argv[0]
    out = argv[argv.index("--json") + 1] if "--json" in argv else None
    shift = np.array([float(x) for x in argv[argv.index("--break") + 1].split(",")]) if "--break" in argv else np.zeros(3)
    ignore = argv[argv.index("--ignore") + 1].split(",") if "--ignore" in argv else []
    paths = json.load(open(paths_path, encoding="utf-8"))
    inputs = json.load(open(paths["inputs"], encoding="utf-8"))
    spec = dict(inputs["shifter"])
    spec["pivot"] = (np.array(spec["pivot"], float) + shift).tolist()
    shifter = Shifter(spec)
    gates = {k: tuple(v) for k, v in paths["gates"].items()}
    grip_local = key_frame(paths["grip"])
    keys = paths["hand"]["keys"]
    arm = Arm(inputs["driver"], 1)

    hand_glb = argv[argv.index("--hand") + 1] if "--hand" in argv else os.path.join(os.path.dirname(inputs["poses"]), "hand_Rest_R.glb")
    hand_local = read_glb(hand_glb)

    rows = []
    places = []

    def test(label, wrist, on_knob=None):
        places.append((label, wrist, on_knob))

    def measure(label, wrist, on_knob=None):
        share = arm.reach_share(wrist.pos)
        elbow = arm.elbow(wrist.pos, wrist.rot[:, 2])
        arm_depth = 0.0
        for a, b, half in ((arm.shoulder, elbow, UPPER_HALF), (elbow, wrist.pos, LOWER_HALF)):
            # Only the samples within reach of the capsule: around points along its bone.
            along = a + np.outer(np.linspace(0, 1, 12), b - a)
            reach = half + np.linalg.norm(b - a) / 22 + ARM_LIMIT
            near = sorted(set(i for group in tree.query_ball_point(along, reach) for i in group))
            if near:
                arm_depth = max(arm_depth, float(segment_depth(samples[near], a, b, half).max()))
        hand_pts = wrist.rot @ hand_local.T
        hand_pts = hand_pts.T + wrist.pos
        depth, _ = inside_depth(tree, samples, normals, hand_pts)
        row = {"at": label, "reach": round(float(share), 4), "arm": round(float(arm_depth), 4), "hand": round(float(depth.max()), 4)}
        fails = []
        if share > REACH_SHARE:
            fails.append(f"reach {share:.3f} > {REACH_SHARE}")
        if arm_depth > ARM_LIMIT:
            fails.append(f"arm {arm_depth * 1000:.1f} mm into the cabin")
        if depth.max() > HAND_LIMIT:
            fails.append(f"hand {depth.max() * 1000:.1f} mm into the cabin")
        if on_knob is not None:
            palm_gap = float(np.linalg.norm(wrist.apply(on_knob["palm"]) - on_knob["centre"])) - shifter.radius
            row["palm"] = round(palm_gap, 4)
            if palm_gap > TOUCH_GAP:
                fails.append(f"palm {palm_gap * 1000:.1f} mm off the knob")
        row["fails"] = fails
        rows.append(row)

    poses = json.load(open(inputs["poses"], encoding="utf-8"))
    palm = np.array(poses["shapes"]["Rest"]["R"]["palm"], float) / poses["studsPerMetre"]
    order = paths["gateOrder"]
    for a in order:
        for b in order:
            if a == b:
                continue
            for k, (c, r, knob) in enumerate(path_states(gates, a, b, steps=8)):
                frame = shifter.lever(c, r, knob)
                test(f"{a}-{b} #{k}", compose(frame, grip_local), {"palm": palm, "centre": frame.pos})
    from shift_paths import steering_grip

    grip = steering_grip(inputs)
    for g in order:
        knob_wrist = compose(shifter.lever(*gates[g]), grip_local)
        for k in range(0, 41):
            test(f"reach to {g} {k / 40:.3f}", hand_on_way(keys, k / 40, grip, knob_wrist))

    # Only the cabin the arm and hand can meet: the box round every wrist and the shoulder, grown by
    # REGION_MARGIN (the whole cabin at this spacing takes gigabytes).
    wrists = np.array([w.pos for _, w, _ in places] + [arm.shoulder])
    low, high = wrists.min(0) - REGION_MARGIN, wrists.max(0) + REGION_MARGIN
    verts, tris, owner, names = cabin_in(inputs)
    centres = verts[tris].mean(1)
    inside = np.all((centres > low) & (centres < high), axis=1)
    keep = inside & np.array([not any(word.lower() in names[o].lower() for word in ignore) for o in owner])
    samples, normals, _ = surface_samples(verts, tris[keep], SPACING)
    tree = cKDTree(samples)
    print(f"{int(keep.sum())} of {len(tris)} triangles in reach, {len(samples)} samples")
    for label, wrist, on_knob in places:
        measure(label, wrist, on_knob)
    failing = [r for r in rows if r["fails"]]
    worst = {key: max(rows, key=lambda r: r.get(key, 0)) for key in ("reach", "arm", "hand")}
    print(f"{len(rows)} places checked, {len(failing)} failing")
    for key, row in worst.items():
        print(f"  worst {key}: {row[key]} at {row['at']}")
    for row in failing[:20]:
        print("  FAIL", row["at"], "; ".join(row["fails"]))
    if out:
        json.dump({"paths": os.path.abspath(paths_path), "break": shift.tolist(), "ignore": ignore, "pass": not failing, "rows": rows}, open(out, "w", encoding="utf-8"), indent=1)
    sys.exit(1 if failing else 0)


if __name__ == "__main__":
    main(sys.argv[1:])
