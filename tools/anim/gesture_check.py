"""Penetration and contact check for the hand gestures tools/anim/gesture_paths.py keyed (its
paths.json), against the cabin dump they were keyed in.

  python tools/anim/gesture_check.py <paths.json> [--allow <allow.json>] [--json <out.json>]
      [--steer <degrees>,...] [--break <metres>] [--track <CONTROL/state>]

Every key of every track, and a point half way to the next, sampled as the game samples them
(Rules/StartupArms.sample), places the mesh the track shows there: the grip (its mesh in the
wheel's frame, moved with the wrist), a thumb mesh (a grip with only the thumb moved, likewise),
or a posed hand in its wrist frame (Rest, Point). Then, with tools/anim/startup_check.py's tests
(the eight-sample vote within MAX_DEPTH, confirmed by ray parity on closed objects):

- a "Wheel" track's hand against the wheel's own parts in the wheel's frame: the rim up to
  GRIP_LIMIT while the hand shows a grip (the grip's own fit), the pressed button up to
  TOUCH_LIMIT while its thumb mesh shows, anything else HAND_LIMIT; and, turned with the wheel to
  each steering angle (default 0 and +-90 degrees: the hands follow the wheel to 110), against
  every cabin part that does not turn with it;
- a "Seat" track's hand against the whole cabin in the seat frame, the toggle it works turned as
  the game turns it (TOUCH_LIMIT while it works it);
- the arm the controller draws to each wrist (forearm and upper arm as capsules of the sleeves'
  half-widths, the elbow from its rule) against the switch panel, the wheel, the cage and the dash
  (ARM_LIMIT; other contacts are listed);
- contacts that must touch: a thumb mesh's skin within PRESS_GAP of its button at the held pose;
  a toggle's index end within TOUCH_GAP of the lever's end while the game turns it.

A named contact goes in an allow list (`--allow`, as startup_check.py's: object prefix, side,
shape or "*", track control or "*", from / to seconds, limitMm, why, decidedBy); every allowance is
printed with its worst depth. `--break 0.01` pushes every hand 1 cm into the wheel (a Wheel track)
or forward (a Seat track) to show the check failing. `--track` checks one track (lighter on
memory). Only the cabin within REGION_MARGIN of the wrists and shoulders is sampled. Exits 1 on any
failure.
"""

import hashlib
import json
import math
import os
import sys

import numpy as np
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gesture_paths import Arm, Knob, cabin_in, lever_tip, sample, smooth, unit  # noqa: E402
from gesture_paths import rotation as turn_about  # noqa: E402
from startup_check import inside_depth, parity_inside, quat_matrix, read_glb, segment_depth, surface_samples  # noqa: E402

HAND_LIMIT = 0.002
TOUCH_LIMIT = 0.003
GRIP_LIMIT = 0.003
ARM_LIMIT = 0.005
TOUCH_GAP = 0.002
PRESS_GAP = 0.001
# The thumb resting on the rim while a finger works the knob: its pad no further off the rim.
REST_GAP = 0.003
FOREARM_RADIUS, UPPER_RADIUS = 0.029, 0.046
# Surface samples: the wheel's own parts as thumb_check.py samples them, the rest of the cabin as
# its fixed parts.
SPACING = 0.0015
CABIN_SPACING = 0.002
# Around the wrists and shoulders, the hand's length and a margin: the only cabin sampled.
REGION_MARGIN = 0.28
WHEEL_PARTS = ("SteeringWheel", "WheelButton", "WheelRotary")
STRICT_ARM = ("SwitchPanel", "Panel", "SteeringWheel", "WheelButton", "WheelRotary", "Cage", "Binnacle", "Dash", "dash")
DRAWN = ("Grip", "Rest", "Point")


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def frame_of(key7):
    """(rotation, position) of a { x, y, z, qw, qx, qy, qz }."""
    return quat_matrix(key7[3:7]), np.array(key7[:3], float)


def main(argv):
    paths_path = argv[0]
    record = json.load(open(paths_path))
    inputs = record["inputs"]
    steer = [float(a) for a in argv[argv.index("--steer") + 1].split(",")] if "--steer" in argv else [0.0, 90.0, -90.0]
    push = float(argv[argv.index("--break") + 1]) if "--break" in argv else 0.0
    allowances = json.load(open(argv[argv.index("--allow") + 1])) if "--allow" in argv else []
    axes = np.array(record["wheel"]["axes"])
    centre = np.array(record["wheel"]["centre"])
    if "--track" in argv:
        wanted = argv[argv.index("--track") + 1]
        record["gestures"] = [g for g in record["gestures"] if f"{g['control']}/{g['state']}" == wanted]
        assert record["gestures"], f"no track {wanted}"
    seat_cabin = cabin_in(inputs)
    verts_w, tris, owner, names = cabin_in(inputs, axes, centre)
    verts_s = seat_cabin[0]
    config = json.load(open(inputs["gestureConfig"]))
    grip = json.load(open(inputs["grip"]))

    # Each shape's vertices in its wrist frame, by (shape, side).
    local = {}
    for side in ("R", "L"):
        g = grip[side]
        z = unit(g["forearm"])
        y = unit(np.array(g["back"]) - z * (np.array(g["back"]) @ z))
        rot = np.stack([np.cross(y, z), y, z], 1)
        pos = np.array(g["wrist"]) / (1.5 / 0.28)
        local[("Grip", side)] = (read_glb(os.path.join(inputs["gripDir"], f"hand_{side}.glb")) - pos) @ rot
        for shape in ("Rest", "Point"):
            local[(shape, side)] = read_glb(os.path.join(inputs["posesDir"], f"hand_{shape}_{side}.glb"))
    for name, mesh in record["meshes"].items():
        side = name[-1]
        rot, pos = frame_of(mesh["frame"])
        verts = read_glb(os.path.join(mesh.get("dir") or inputs["thumbsDir"], mesh["file"]))
        centre_m = 0.5 * (verts.min(0) + verts.max(0))
        local[(name, side)] = (verts - centre_m) @ rot.T + pos

    # The region the hands and arms can reach, in the seat frame, from every wrist the tracks key
    # (a Wheel track's turned to each steering angle) and both shoulders.
    wrists = []
    for track in record["gestures"]:
        for k in track["keys"]:
            p = np.array(k[1:4])
            if track["frame"] == "Wheel":
                for angle in steer:
                    wrists.append(axes @ (turn_about([0, 0, 1], math.radians(angle)) @ p) + centre)
            else:
                wrists.append(p)
    for side in (1, -1):
        wrists.append(Arm(inputs["driver"], side).shoulder)
    wrists = np.array(wrists)
    lo, hi = wrists.min(0) - REGION_MARGIN, wrists.max(0) + REGION_MARGIN
    tri_s = verts_s[tris]
    in_region = np.all(tri_s.max(1) >= lo, 1) & np.all(tri_s.min(1) <= hi, 1)
    knob_parts = np.array([names[o].startswith("WheelRotary_Manettino") for o in owner])
    turning = np.array([names[o].startswith(WHEEL_PARTS) for o in owner]) & in_region & ~knob_parts
    tri_ids = np.arange(len(tris))
    p_w, n_w, t_w = surface_samples(verts_w, tris[turning], SPACING, tri_ids[turning])
    wheel_obj = owner[turning][t_w]
    wheel_tree = cKDTree(p_w)
    near = np.all(np.abs(verts_w[tris].mean(1)) < 0.4, 1)
    fixed = ~turning & ~knob_parts & near & in_region
    p_f, n_f, t_f = surface_samples(verts_w, tris[fixed], CABIN_SPACING, tri_ids[fixed])
    fixed_obj = owner[fixed][t_f]
    fixed_tree = cKDTree(p_f)
    # The whole cabin in the seat frame, for the Seat tracks and the arms; toggles apart.
    toggles = {g["turn"]["control"] for g in record["gestures"] if g["frame"] == "Seat" and g.get("turn")}
    toggle_mask = np.array([names[o] in toggles for o in owner])
    rest_mask = ~toggle_mask & in_region
    p_s, n_s, t_s = surface_samples(verts_s, tris[rest_mask], CABIN_SPACING, tri_ids[rest_mask])
    seat_obj = owner[rest_mask][t_s]
    print("sampled:", len(p_w), "wheel,", len(p_f), "fixed,", len(p_s), "cabin points")
    seat_tree = cKDTree(p_s)
    lever_surfaces = {}
    for name in toggles:
        mask = owner == names.index(name)
        p, n, t = surface_samples(verts_s, tris[mask], SPACING * 0.5, tri_ids[mask])
        lever_surfaces[name] = (cKDTree(p), p, n)

    knob = Knob(config, (verts_w, tris, owner, names), axes, centre) if config.get("modeKnob") else None
    if knob is not None:
        p_k, n_k, t_k = surface_samples(verts_w, tris[knob_parts], SPACING * 0.5, tri_ids[knob_parts])
        knob_obj = owner[knob_parts][t_k]
        knob_tree = cKDTree(p_k)
    cache = {}

    def closed_triangles(obj, verts):
        key = (obj, id(verts))
        if key not in cache:
            faces = tris[owner == obj]
            edges = np.sort(np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]]), axis=1)
            _, counts = np.unique(edges, axis=0, return_counts=True)
            cache[key] = verts[faces] if np.all(counts == 2) else None
        return cache[key]

    def depths(tree, sp, sn, so, pts, verts):
        depth, idx = inside_depth(tree, sp, sn, pts)
        if depth.max() > 0:
            flagged = np.flatnonzero(depth > 0)
            for obj in np.unique(so[idx[flagged]]):
                closed = closed_triangles(obj, verts)
                if closed is not None:
                    mine = flagged[so[idx[flagged]] == obj]
                    depth[mine[~parity_inside(pts[mine], closed)]] = 0.0
        out = {}
        for obj in np.unique(so[idx[depth > 0]]) if depth.max() > 0 else []:
            hits = (so[idx] == obj) & (depth > 0)
            out[names[obj]] = float(depth[hits].max())
        return out

    arms = {1: Arm(inputs["driver"], 1), -1: Arm(inputs["driver"], -1)}
    worst, failures = {}, []

    def allowance(obj, side, shape, control, t):
        for entry in allowances:
            if (
                obj.startswith(entry["object"])
                and entry["side"] == side
                and entry["shape"] in (shape, "*")
                and entry.get("control", "*") in (control, "*")
                and entry["from"] <= t <= entry["to"]
            ):
                return entry
        return None

    def note(kind, control, side, obj, depth, t, allowed, limit):
        key = (kind, control, side, obj)
        if depth > worst.get(key, (0,))[0]:
            worst[key] = (depth, t, allowed, limit)
        if depth > limit:
            failures.append((kind, control, side, obj, round(depth * 1000, 2), round(t, 3)))

    def judge(kind, control, side, shape, hits, t, button=None, working=None):
        for obj, d in hits.items():
            named = allowance(obj, side, shape, control, t)
            if named:
                note(kind, control, side, obj, d, t, named["why"], named["limitMm"] / 1000)
            elif button and obj.startswith(button) and shape not in DRAWN:
                note(kind, control, side, obj, d, t, "the pressed button", TOUCH_LIMIT)
            elif working and obj == working:
                note(kind, control, side, obj, d, t, "the control worked", TOUCH_LIMIT)
            elif obj.startswith("SteeringWheel_Rim") and shape not in ("Rest", "Point"):
                note(kind, control, side, obj, d, t, "a grip on the rim", GRIP_LIMIT)
            else:
                note(kind, control, side, obj, d, t, None, HAND_LIMIT)

    def turned_states(turn, lever, t):
        """The angles the control a track turns has while the hand is at `t`: on the way in, before
        the turn, it is still at its first angle, but on the way back (the track played backward)
        it stays turned, so both are checked."""
        a0, a1 = lever
        if t < turn["start"]:
            return [a0, a1]
        if t > turn["finish"]:
            return [a1]
        return [a0 + (a1 - a0) * smooth((t - turn["start"]) / (turn["finish"] - turn["start"]))]

    def check_arm(control, sign, side, wrist_rot, wrist_pos, t):
        arm = arms[sign]
        joint = arm.elbow(wrist_pos, wrist_rot[:, 2])
        for bone, a, b, radius in (("forearm", joint, wrist_pos, FOREARM_RADIUS), ("upper arm", arm.shoulder, joint, UPPER_RADIUS)):
            near_idx = seat_tree.query_ball_point((a + b) / 2, np.linalg.norm(b - a) / 2 + radius)
            if not near_idx:
                continue
            near_idx = np.array(near_idx)
            d = segment_depth(p_s[near_idx], a, b, radius)
            hit = d > 0
            for obj in np.unique(seat_obj[near_idx][hit]):
                name = names[obj]
                dd = float(d[hit & (seat_obj[near_idx] == obj)].max())
                strict = name.startswith(STRICT_ARM)
                note(bone, control, side, name, dd, t, None if strict else "cloth contact, listed", ARM_LIMIT if strict else 1.0)
        return arm.reach_share(wrist_pos)

    gaps, reach = {}, {}
    for track in record["gestures"]:
        control, side, state = track["control"], track["side"], track["state"]
        label = f"{control}/{state}"
        sign = 1 if side == "R" else -1
        keys = track["keys"]
        times = sorted({k[0] for k in keys} | {(a[0] + b[0]) / 2 for a, b in zip(keys, keys[1:])})
        shapes = track["shapes"]
        button = None
        for change in shapes:
            mesh = record["meshes"].get(change["shape"])
            if mesh and mesh["cuff"] == "Grip":
                button = mesh["file"].replace(f"hand_{side}_", "WheelButton_").replace(".glb", "")
        turn = track.get("turn")
        worst_reach = 0.0
        for t in times:
            shape = shapes[0]["shape"]
            for change in shapes:
                if t >= change["at"]:
                    shape = change["shape"]
            pos, q = sample(keys, t)
            rot = quat_matrix(q)
            pts = local[(shape, side)] @ rot.T + pos
            if track["frame"] == "Wheel":
                pts = pts + np.array([0, 0, -push])
                judge("hand", label, side, shape, depths(wheel_tree, p_w, n_w, wheel_obj, pts, verts_w), t, button)
                if knob is not None:
                    working = turn is not None and turn["start"] - 0.05 <= t <= turn["finish"] + 0.05
                    if turn:
                        states = turned_states(turn, track["lever"], t)
                    else:
                        # A track that does not turn the knob meets it wherever the car's mode left it.
                        states = sorted({a - knob.rest for a in knob.positions.values()})
                    for angle in states:
                        back = turn_about(knob.axis, -angle)
                        in_knob = (pts - knob.pivot) @ back.T + knob.pivot
                        hits = depths(knob_tree, p_k, n_k, knob_obj, in_knob, verts_w)
                        judge("hand", label, side, shape, hits, t, working=knob.part if working else None)
                if turn and track.get("sense") is not None and turn["start"] <= t <= turn["finish"]:
                    a0, a1 = track["lever"]
                    angle = a0 + (a1 - a0) * smooth((t - turn["start"]) / (turn["finish"] - turn["start"]))
                    target = knob.contact(angle, track["sense"], **(track.get("contact") or {}))
                    tip = rot @ np.array(track["tip"]) + pos + np.array([0, 0, -push])
                    gap = float(np.linalg.norm(tip - target))
                    if gap > gaps.get(label, (0,))[0]:
                        gaps[label] = (gap, round(t, 4), "lever")
                    pad = rot @ np.array(track["pad"]) + pos + np.array([0, 0, -push])
                    rim_own = np.array([names[o] == "SteeringWheel_Rim" for o in wheel_obj])
                    pad_gap = float(cKDTree(p_w[rim_own]).query(pad)[0])
                    if pad_gap > gaps.get(label + " thumb on rim", (0,))[0]:
                        gaps[label + " thumb on rim"] = (pad_gap, round(t, 4), "rest")
                for angle in steer:
                    r = turn_about([0, 0, 1], math.radians(angle))
                    turned = pts @ r.T
                    hits = depths(fixed_tree, p_f, n_f, fixed_obj, turned, verts_w)
                    judge(f"hand {angle:g}", label, side, shape, hits, t)
                    wrist_rot = axes @ r @ rot
                    wrist_pos = axes @ (r @ (pos + np.array([0, 0, -push]))) + centre
                    worst_reach = max(worst_reach, check_arm(label, sign, side, wrist_rot, wrist_pos, t))
            else:
                pts = pts + np.array([0, 0, -push])
                judge("hand", label, side, shape, depths(seat_tree, p_s, n_s, seat_obj, pts, verts_s), t)
                if turn:
                    hinge = config["controls"][turn["control"]]
                    pivot, axis = np.array(hinge["pivot"]), unit(hinge["axis"])
                    a0, a1 = track["lever"]
                    share = (t - turn["start"]) / (turn["finish"] - turn["start"])
                    angle = a0 + (a1 - a0) * smooth(share)
                    working = turn["start"] - 0.05 <= t <= turn["finish"] + 0.05
                    tree_l, lp, ln = lever_surfaces[turn["control"]]
                    for state_angle in turned_states(turn, track["lever"], t):
                        back = turn_about(axis, -state_angle)
                        in_lever = (pts - pivot) @ back.T + pivot
                        d, _ = inside_depth(tree_l, lp, ln, in_lever)
                        if d.max() > 0:
                            closed = closed_triangles(names.index(turn["control"]), verts_s)
                            flagged = np.flatnonzero(d > 0)
                            if closed is not None:
                                d[flagged[~parity_inside(in_lever[flagged], closed)]] = 0.0
                        if d.max() > 0:
                            judge("hand", label, side, shape, {turn["control"]: float(d.max())}, t, working=turn["control"] if working else None)
                    if turn["start"] <= t <= turn["finish"]:
                        modelled = lever_tip(seat_cabin, hinge)
                        end = turn_about(axis, angle) @ (modelled - pivot) + pivot
                        motion = unit(np.cross(axis, end - pivot) * (1 if a1 >= a0 else -1))
                        target = end - motion * 0.006
                        tip = rot @ np.array(track["tip"]) + pos + np.array([0, 0, -push])
                        gap = float(np.linalg.norm(tip - target))
                        if gap > gaps.get(label, (0,))[0]:
                            gaps[label] = (gap, round(t, 4), "lever")
                worst_reach = max(worst_reach, check_arm(label, sign, side, rot, pos + np.array([0, 0, -push]), t))
        reach[label] = round(worst_reach, 3)
        if track["frame"] == "Wheel":
            # The grip's own reach at the same steering angles, which the gesture starts from.
            grip_reach = 0.0
            r0, p0 = quat_matrix(keys[0][4:8]), np.array(keys[0][1:4])
            for angle in steer:
                r = turn_about([0, 0, 1], math.radians(angle))
                grip_reach = max(grip_reach, arms[sign].reach_share(axes @ (r @ p0) + centre))
            reach[label] = {"gesture": round(worst_reach, 3), "grip": round(grip_reach, 3)}
            del r0
        if button and track["frame"] == "Wheel":
            # The thumb on its button at the held pose: the skin's nearest point to the button.
            pos, q = sample(keys, keys[-1][0])
            pts = local[(shapes[-1]["shape"], side)] @ quat_matrix(q).T + pos + np.array([0, 0, -push])
            own = np.array([names[o] == button for o in wheel_obj])
            gap = float(cKDTree(p_w[own]).query(pts)[0].min()) if own.any() else 1.0
            gaps[label] = (gap, keys[-1][0], "press")
    for label, (gap, t, kind) in gaps.items():
        limit = PRESS_GAP if kind == "press" else REST_GAP if kind == "rest" else TOUCH_GAP
        if gap > limit:
            failures.append(("float", label, "", kind, round(gap * 1000, 2), t))

    rows = sorted(
        (
            {"kind": k[0], "track": k[1], "side": k[2], "object": k[3], "worstMm": round(v[0] * 1000, 2), "at": round(v[1], 3), "allowed": v[2], "limitMm": round(v[3] * 1000, 1)}
            for k, v in worst.items()
        ),
        key=lambda r: -r["worstMm"],
    )
    result = {
        "paths": paths_path,
        "pathsSha256": sha(paths_path),
        "cabinSha256": sha(inputs["cabin"]),
        "mutation": push or None,
        "steerDeg": steer,
        "allow": allowances,
        "gapsMm": {k: {"mm": round(v[0] * 1000, 2), "at": v[1], "kind": v[2]} for k, v in gaps.items()},
        "reachShare": reach,
        "contacts": rows,
        "failures": failures[:60],
        "failureCount": len(failures),
        "pass": not failures,
    }
    for row in rows[:30]:
        print(f"{row['kind']:10} {row['track']:22} {row['side']} {row['object'][:34]:34} {row['worstMm']:7.2f} mm at {row['at']:.3f}s (limit {row['limitMm']}) {row['allowed'] or ''}")
    print("contacts that must touch (mm):", {k: v["mm"] for k, v in result["gapsMm"].items()})
    print("reach share:", reach)
    for f in failures[:15]:
        print("FAIL", f)
    print(("PASS" if result["pass"] else f"FAIL ({len(failures)} sample-failures)"), "mutation:", result["mutation"])
    if "--json" in argv:
        json.dump(result, open(argv[argv.index("--json") + 1], "w"), indent=1)
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
