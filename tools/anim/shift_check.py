"""Reach, penetration and contact check for a car's gear-lever hand (shift_paths.py's paths.json),
against the cabin dump it was keyed in.

  python tools/anim/shift_check.py <paths.json> [--json <out.json>] [--break <dx>,<dy>,<dz>]
      [--lever <name>,...] [--steps N] [--push <metres>] [--allow <allow.json>] [--reach-only]

For every ordered pair of gates, the lever is moved along Vehicle/ShiftPlan's path (out of the gate,
the knob down into reverse, across the rail, into the gate) and the hand rides it; the way between
the steering grip and the knob is sampled as Rules/ShiftHand plays it, ending on each gate's knob,
with the mesh its keyed shape names (the grip hand, the open hand, the Knob hand). At every place:
- the arm the controller draws (shoulder, elbow from its rule, wrist) must reach the wrist within
  REACH_SHARE of its length;
- the forearm and the upper arm, as capsules of the sleeves' half-widths, must stay ARM_LIMIT clear
  of the cabin (startup_check's segment depth);
- the shown hand mesh must not sink more than HAND_LIMIT into the cabin (startup_check's vote,
  within MAX_DEPTH), the grip hand on the steering wheel GRIP_LIMIT (the grip's own fit);
- on the knob, the Knob hand must hold the ball: some vertex within TOUCH_GAP of its surface, none
  more than HAND_LIMIT inside it.
The lever's own parts (--lever, modelled in neutral) move with it: each place is turned back into
the lever's neutral frame before it is measured against them. `--break` moves the whole lever by
that many metres (seat frame) and must turn the run red. Every object a part goes into is judged on
its own. A named contact (--allow: {"contacts": [{"part": "hand" | "upper" | "lower", "object",
"shape" (only while that hand shows), "when": "push" (only with the knob pushed down) | "any",
"limitMm", "why"}]}) is listed, not failed,
up to its measured depth; deeper fails. Exits 1 on any failure.
"""
import json
import os
import sys

import numpy as np
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gesture_paths import Arm, Frame, cabin_in  # noqa: E402
from shift_paths import compose, hand_on_way, inputs_of, key_frame, lever_inputs, path_states, portable, steering_grip  # noqa: E402
from startup_check import inside_depth, read_glb, segment_depth, surface_samples  # noqa: E402

REACH_SHARE = 0.96
ARM_LIMIT = 0.005
HAND_LIMIT = 0.002
# The grip hand on the steering wheel: the decided grip's own fit (as startup_check and gesture_check).
GRIP_LIMIT = 0.003
WHEEL_PREFIXES = ("SteeringWheel", "GEO_INT_STwheel")
TOUCH_GAP = 0.003
SPACING = 0.003
REGION_MARGIN = 0.15
# Sleeve half-widths, metres (the smaller of each modelled cross-section, as startup_check uses).
UPPER_HALF, LOWER_HALF = 0.045, 0.035
LEVER_PARTS = "GEO_INT_shifter_01,GEO_INT_shifter_decal,GEO_INT_shifter_00,GEO_INT_shifter_02"


def hand_meshes(inputs):
    """Each shape's mesh in its wrist frame, metres: the posed hands from hand_poses.py, the grip hand
    turned out of the wheel's frame it was posed in."""
    poses_dir = os.path.dirname(inputs["poses"])
    meshes = {name: read_glb(os.path.join(poses_dir, f"hand_{name}_R.glb")) for name in ("Rest", "Knob")}
    hands = json.load(open(inputs["grip"], encoding="utf-8"))["R"]
    grip = Frame.grip(hands["wrist"], hands["forearm"], hands["back"])
    wheel_verts = read_glb(os.path.join(os.path.dirname(inputs["grip"]), "hand_R.glb"))
    meshes["Grip"] = (wheel_verts - grip.pos) @ grip.rot
    return meshes


def main(argv):
    paths_path = argv[0]
    out = argv[argv.index("--json") + 1] if "--json" in argv else None
    shift = np.array([float(x) for x in argv[argv.index("--break") + 1].split(",")]) if "--break" in argv else np.zeros(3)
    lever_names = (argv[argv.index("--lever") + 1] if "--lever" in argv else LEVER_PARTS).split(",")
    steps = int(argv[argv.index("--steps") + 1]) if "--steps" in argv else 8
    # Only the way between the wheel and every gate's knob (tuning the way: the gate paths do not move).
    reach_only = "--reach-only" in argv
    allow = json.load(open(argv[argv.index("--allow") + 1], encoding="utf-8"))["contacts"] if "--allow" in argv else []
    paths = json.load(open(paths_path, encoding="utf-8"))
    inputs = json.load(open(inputs_of(paths_path, paths), encoding="utf-8"))
    shifter, gates, _ = lever_inputs(inputs)
    if "--push" in argv:
        shifter.push = float(argv[argv.index("--push") + 1])
    shifter.pivot = shifter.pivot + shift
    shifter.knob = shifter.knob + shift
    grip_local = key_frame(paths["grip"])
    keys, shapes = paths["hand"]["keys"], paths["hand"]["shapes"]
    arm = Arm(inputs["driver"], 1)
    meshes = hand_meshes(inputs)
    neutral = shifter.lever(*gates["N"])
    # The lever's parts are modelled where the unbroken lever sits in neutral.
    modelled = Frame(neutral.rot, neutral.pos - shift)

    places = []
    order = paths["gateOrder"]
    for a in order:
        for b in order:
            if a == b or reach_only:
                continue
            for k, (c, r, knob) in enumerate(path_states(gates, a, b, steps=steps)):
                frame = shifter.lever(c, r, knob)
                places.append((f"{a}-{b} #{k}", compose(frame, grip_local), "Knob", frame, knob, True))
    grip = steering_grip(inputs)
    for g in order:
        frame = shifter.lever(*gates[g])
        knob_wrist = compose(frame, grip_local)
        for k in range(0, 41):
            wrist, shape = hand_on_way(keys, shapes, k / 40, grip, knob_wrist)
            places.append((f"reach to {g} {k / 40:.3f}", wrist, shape, frame, 0.0, k == 40))

    # Only the cabin the arm and hand can meet: the box round every wrist and the shoulder, grown by
    # REGION_MARGIN (the whole cabin at this spacing takes gigabytes).
    wrists = np.array([p[1].pos for p in places] + [arm.shoulder])
    low, high = wrists.min(0) - REGION_MARGIN, wrists.max(0) + REGION_MARGIN
    verts, tris, owner, names = cabin_in(inputs)
    centres = verts[tris].mean(1)
    inside = np.all((centres > low) & (centres < high), axis=1)
    on_lever = np.array([names[o] in lever_names for o in owner])
    missing = [n for n in lever_names if n not in names]
    assert not missing, f"no lever part named {missing} in the dump"
    tri_ids = np.arange(len(tris))
    s_static, n_static, t_static = surface_samples(verts, tris[inside & ~on_lever], SPACING, tri_ids[inside & ~on_lever])
    s_lever, n_lever, t_lever = surface_samples(verts, tris[on_lever], SPACING, tri_ids[on_lever])
    # The object each sample lies on: every object a part goes into is judged on its own.
    o_static = owner[inside & ~on_lever][t_static]
    o_lever = owner[on_lever][t_lever]
    static_tree, lever_tree = cKDTree(s_static), cKDTree(s_lever)
    print(f"{int((inside & ~on_lever).sum())} cabin and {int(on_lever.sum())} lever triangles of {len(tris)}; {len(s_static)} + {len(s_lever)} samples")

    def to_modelled(points, lever):
        return (points - lever.pos) @ lever.rot @ modelled.rot.T + modelled.pos

    def per_object(depths, objects, into):
        for obj in np.unique(objects[depths > 0]):
            name = names[obj]
            into[name] = max(into.get(name, 0.0), float(depths[objects == obj].max()))

    def arm_hits(a, b, half, lever):
        into = {}
        along = a + np.outer(np.linspace(0, 1, 12), b - a)
        reach = half + np.linalg.norm(b - a) / 22 + ARM_LIMIT
        mapped_lever = tuple(to_modelled(np.array(p, ndmin=2), lever) for p in (a, b, along))
        for tree, samples, objects, (pa, pb, pts) in ((static_tree, s_static, o_static, (a, b, along)), (lever_tree, s_lever, o_lever, mapped_lever)):
            near = sorted(set(i for group in tree.query_ball_point(pts.reshape(-1, 3), reach) for i in group))
            if near:
                per_object(segment_depth(samples[near], pa.reshape(3), pb.reshape(3), half), objects[near], into)
        return into

    def allowance(part, name, knob, shape):
        for entry in allow:
            if entry["part"] != part or entry["object"] != name or entry.get("shape", shape) != shape:
                continue
            if entry.get("when", "any") == "any" or knob > 0:
                return entry
        return None

    rows = []
    measured = {}
    for label, wrist, shape, lever, knob, on_knob in places:
        # A lever state reached on many gate paths is measured once.
        state = (shape, knob, tuple(np.round(wrist.pos, 7)), tuple(np.round(wrist.rot.ravel(), 7)))
        if state in measured:
            rows.append(dict(measured[state], at=label))
            continue
        share = arm.reach_share(wrist.pos)
        elbow = arm.elbow(wrist.pos, wrist.rot[:, 2])
        hand_pts = (wrist.rot @ meshes[shape].T).T + wrist.pos
        hits = {"upper": arm_hits(arm.shoulder, elbow, UPPER_HALF, lever), "lower": arm_hits(elbow, wrist.pos, LOWER_HALF, lever), "hand": {}}
        cabin_d, cabin_i = inside_depth(static_tree, s_static, n_static, hand_pts)
        per_object(cabin_d, o_static[cabin_i], hits["hand"])
        lever_d, lever_i = inside_depth(lever_tree, s_lever, n_lever, to_modelled(hand_pts, lever))
        per_object(lever_d, o_lever[lever_i], hits["hand"])
        row = {"at": label, "shape": shape, "knob": knob, "reach": round(float(share), 4)}
        row["into"] = {part: {name: round(d, 5) for name, d in into.items()} for part, into in hits.items() if into}
        for part in ("upper", "lower", "hand"):
            row[part] = round(max(hits[part].values(), default=0.0), 4)
        fails, listed = [], []
        if share > REACH_SHARE:
            fails.append(f"reach {share:.3f} > {REACH_SHARE}")
        for part, into in hits.items():
            for name, d in into.items():
                limit = HAND_LIMIT if part == "hand" else ARM_LIMIT
                if part == "hand" and shape == "Grip" and name.startswith(WHEEL_PREFIXES):
                    limit = GRIP_LIMIT
                if d <= limit:
                    continue
                named = allowance(part, name, knob, shape)
                if named and d <= named["limitMm"] / 1000:
                    listed.append(f"{part} {d * 1000:.1f} mm into {name} ({named['why']})")
                else:
                    fails.append(f"{part} {d * 1000:.1f} mm into {name}")
        if on_knob:
            radial = np.linalg.norm(hand_pts - lever.pos, axis=1) - shifter.radius
            row["ballGap"], row["ballInside"] = round(float(max(radial.min(), 0.0)), 4), round(float(max(-radial.min(), 0.0)), 4)
            if radial.min() > TOUCH_GAP:
                fails.append(f"hand {radial.min() * 1000:.1f} mm off the knob")
            if -radial.min() > HAND_LIMIT:
                fails.append(f"hand {-radial.min() * 1000:.1f} mm inside the knob")
        row["fails"], row["listed"] = fails, listed
        rows.append(row)
        measured[state] = row
    failing = [r for r in rows if r["fails"]]
    print(f"{len(rows)} places checked, {len(failing)} failing, {sum(1 for r in rows if r['listed'])} with named contacts")
    for key in ("reach", "upper", "lower", "hand", "ballGap", "ballInside"):
        row = max(rows, key=lambda r: r.get(key, 0))
        print(f"  worst {key}: {row.get(key)} at {row['at']} ({row['shape']}) {row['into']}")
    deepest = {}
    for row in rows:
        for part, into in row["into"].items():
            for name, d in into.items():
                if d > deepest.get((part, name), (0.0, ""))[0]:
                    deepest[(part, name)] = (d, row["at"])
    for (part, name), (d, at) in sorted(deepest.items(), key=lambda kv: -kv[1][0]):
        print(f"  deepest {part} into {name}: {d * 1000:.2f} mm at {at}")
    for row in failing[:20]:
        print("  FAIL", row["at"], row["shape"], "; ".join(row["fails"]))
    if out:
        json.dump(
            {"paths": portable(paths_path), "break": shift.tolist(), "push": shifter.push, "lever": lever_names, "allow": allow, "pass": not failing, "rows": rows},
            open(out, "w", encoding="utf-8"),
            indent=1,
        )
    sys.exit(1 if failing else 0)


if __name__ == "__main__":
    main(sys.argv[1:])
