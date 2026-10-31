"""
Contact check for a baked car-entry timeline (tools/blender/car_entry_scene.py bake): per frame,
every R6 part's box against the car's surfaces, the door posed at that frame's openness, and the
ground; and each foot's slide while it is on the ground.

The car is a cloud of points sampled over every triangle (no point further than --spacing from
its neighbours), so a box that cuts into a surface holds points; a point's depth is how far it is
inside the box's nearest face. Depths are in studs of the authoring frame (scale-1 R6; multiply by
the driver's scale for game studs).

  python car_entry_check.py <baked.json> <scene.npz> [--allow allow.json] [--tol 0.04]
      [--spacing 0.05] [--from F] [--to F] [--json out.json] [--mutate pelvis_y=-0.6@F0-F1]
      [--per-group | --no-per-group]

allow.json: [{"from", "to", "parts": [...], "groups": [...], "depth"}] = intended contacts (a bottom
on the sill, a hand on the door) may go that deep; everything else fails above --tol. An entry with
"touch": <gap> also REQUIRES the contact: on every frame of its span the end of each named part
(the hand, the sole: the quarter of the part toward its end) must come within <gap> of those
surfaces, or it fails as "float" (a hand pushing on air passes a penetration check). Exit code 1
on any failure, so a deliberate mutation (--mutate) must turn the run red.

--per-group tests every group a part cuts into (each car group, the door, the ground) against that
group's own allowance. --no-per-group tests only the group of the part's deepest point, so a
shallower contact with another group is never tested. With neither, a scene in DEEPEST_ONLY_SCENES
is checked deepest-only and every other scene per group.

--json also records what was checked: the SHA-256 of the baked timeline, the scene and the allow
list, the frame range, any mutation, the mode, and whether it passed. car_entry_upload.py refuses to
upload a clip unless such a record says its exact timeline passed over every frame, unmutated.
"""
import argparse
import hashlib
import json
import sys

import numpy as np
from scipy.spatial import cKDTree

# Half extents (scale 1). The R6 head is a 2x1x1 part drawn as a ~1.25-stud rounded head mesh.
HALF = {
    "Torso": (1.0, 1.0, 0.5),
    "Head": (0.62, 0.62, 0.62),
    "Right Arm": (0.5, 1.0, 0.5),
    "Left Arm": (0.5, 1.0, 0.5),
    "Right Leg": (0.5, 1.0, 0.5),
    "Left Leg": (0.5, 1.0, 0.5),
}
LEGS = ("Right Leg", "Left Leg")
# A sole closer than this to the ground is on it (a foot skimming higher is stepping).
GROUNDED = 0.025
# Scene SHA-256s whose clips were accepted under the deepest-group rule (the SVJ's entry scene).
DEEPEST_ONLY_SCENES = frozenset({"7710cfda47eb476d96b82a22805f083639d53cb08c5794ae85ca82b5eca95874"})


def sample(vertices, triangles, spacing):
    a, b, c = (vertices[triangles[:, i]] for i in range(3))
    longest = np.maximum.reduce(
        [np.linalg.norm(b - a, axis=1), np.linalg.norm(c - b, axis=1), np.linalg.norm(a - c, axis=1)]
    )
    steps = np.clip(np.ceil(longest / spacing).astype(int), 1, 80)
    out = [vertices[np.unique(triangles)]]
    for n in np.unique(steps):
        if n <= 1:
            continue
        pick = steps == n
        i, j = np.meshgrid(np.arange(n + 1), np.arange(n + 1), indexing="ij")
        keep = (i + j) <= n
        u = (i[keep] / n)[None, :, None]
        w = (j[keep] / n)[None, :, None]
        pa, pb, pc = a[pick][:, None, :], b[pick][:, None, :], c[pick][:, None, :]
        out.append((pa + u * (pb - pa) + w * (pc - pa)).reshape(-1, 3))
    return np.concatenate(out)


def frame_matrix(values):
    m = np.identity(4)
    m[:3, 3] = values[0:3]
    m[:3, :3] = np.array(values[3:12]).reshape(3, 3)
    return m


def rotation_about(axis, angle):
    x, y, z = np.asarray(axis, dtype=float) / np.linalg.norm(axis)
    c, s = np.cos(angle), np.sin(angle)
    t = 1 - c
    return np.array(
        [
            [t * x * x + c, t * x * y - s * z, t * x * z + s * y],
            [t * x * y + s * z, t * y * y + c, t * y * z - s * x],
            [t * x * z - s * y, t * y * z + s * x, t * z * z + c],
        ]
    )


def depths(points, frame, half, tol):
    """Points inside the box (shrunk by tol): their depth past the nearest face."""
    local = (points - frame[:3, 3]) @ frame[:3, :3]
    h = np.asarray(half) - tol
    inside = np.all(np.abs(local) < h, axis=1)
    if not inside.any():
        return 0.0, None
    margin = h - np.abs(local[inside])
    d = margin.min(axis=1) + tol
    k = int(np.argmax(d))
    return float(d[k]), np.flatnonzero(inside)[k]


def group_depths(points, groups, frame, half, tol):
    """{group: depth of its deepest point inside the box}, for the groups that have one."""
    out = {}
    for group in np.unique(groups):
        d, _ = depths(points[groups == group], frame, half, tol)
        if d > 0:
            out[str(group)] = d
    return out


def corners(frame, half):
    s = np.array([[x, y, z] for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)], dtype=float)
    return (s * np.asarray(half)) @ frame[:3, :3].T + frame[:3, 3]


def end_gap(points, frame, half):
    """Distance from the end quarter of a limb box (local y from -half_y to -half_y/2) to the
    nearest of `points`; infinity when there are none."""
    if not len(points):
        return float("inf")
    local = (points - frame[:3, 3]) @ frame[:3, :3]
    centre = np.array([0.0, -0.75 * half[1], 0.0])
    box = np.array([half[0], 0.25 * half[1], half[2]])
    excess = np.maximum(np.abs(local - centre) - box, 0.0)
    return float(np.sqrt((excess**2).sum(axis=1)).min())


def spans(found, order):
    """Failures merged into runs of consecutive frames (by position in the timeline) with the same
    part, group and limit."""
    runs = []
    for x in sorted(found, key=lambda x: (x["part"], x["group"], x["limit"], order[x["frame"]])):
        key = (x["part"], x["group"], x["limit"])
        last = runs[-1] if runs else None
        if last is None or last["key"] != key or order[x["frame"]] > order[last["to"]] + 1:
            last = {"key": key, "from": x["frame"], "to": None, "frames": 0, "max": x["value"], "at": x["frame"], "secondary": 0}
            runs.append(last)
        # Two touch entries on one part can fail the same frame: count the frame once.
        if x["frame"] != last["to"]:
            last["frames"] += 1
            last["secondary"] += int(x["secondary"])
        last["to"] = x["frame"]
        if x["value"] > last["max"]:
            last["max"], last["at"] = x["value"], x["frame"]
    out = [dict(zip(("part", "group", "limit"), r.pop("key")), **r) for r in runs]
    return sorted(out, key=lambda r: (order[r["from"]], r["part"], r["group"]))


def apply_mutation(frames, spec):
    """'pelvis_y=-0.6@120-150': move every part down 0.6 studs over frames 120-150."""
    what, span = spec.split("@")
    key, amount = what.split("=")
    start, end = (int(v) for v in span.split("-"))
    axis = {"pelvis_x": 0, "pelvis_y": 1, "pelvis_z": 2}[key]
    for f in frames:
        if start <= f["frame"] <= end:
            for part, values in f["parts"].items():
                values[axis] += float(amount)


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("baked")
    parser.add_argument("scene")
    parser.add_argument("--allow")
    parser.add_argument("--tol", type=float, default=0.04)
    parser.add_argument("--spacing", type=float, default=0.05)
    parser.add_argument("--from", dest="start", type=int, default=None)
    parser.add_argument("--to", dest="end", type=int, default=None)
    parser.add_argument("--json")
    parser.add_argument("--mutate")
    parser.add_argument("--slide", type=float, default=0.6, help="studs/s a grounded foot may slide")
    parser.add_argument(
        "--per-group",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="test every group a part touches (default: on, except for a scene in DEEPEST_ONLY_SCENES)",
    )
    args = parser.parse_args(argv)
    scene_sha256 = file_sha256(args.scene)
    per_group = args.per_group if args.per_group is not None else scene_sha256 not in DEEPEST_ONLY_SCENES

    baked = json.load(open(args.baked, encoding="utf-8"))
    frames = baked["frames"]
    if args.mutate:
        apply_mutation(frames, args.mutate)
    if args.start is not None or args.end is not None:
        lo = args.start if args.start is not None else -1
        hi = args.end if args.end is not None else 10**9
        frames = [f for f in frames if lo <= f["frame"] <= hi]
    allow = json.load(open(args.allow, encoding="utf-8")) if args.allow else []
    scene = np.load(args.scene, allow_pickle=False)

    # Region the body sweeps, padded.
    sweep = np.array([f["parts"][p][0:3] for f in frames for p in HALF])
    lo, hi = sweep.min(axis=0) - 2.5, sweep.max(axis=0) + 2.5
    clouds, labels = [], []
    for group in [str(g) for g in scene["groups"]]:
        pts = sample(scene[f"v_{group}"].astype(float), scene[f"f_{group}"], args.spacing)
        pts = pts[np.all((pts > lo) & (pts < hi), axis=1)]
        clouds.append(pts)
        labels += [group] * len(pts)
    cloud = np.concatenate(clouds)
    labels = np.array(labels)
    tree = cKDTree(cloud)
    door = None
    if "v_door" in scene:
        door = sample(scene["v_door"].astype(float), scene["f_door"], args.spacing) - scene["hinge_pivot"]
    pivot, axis, open_angle = scene["hinge_pivot"], scene["hinge_axis"], float(scene["open_angle"])

    found, rows, worst = [], [], {}
    previous = None
    dt = 1.0 / baked["fps"]

    def fail(fr, part, group, value, limit, secondary=False):
        found.append({"frame": fr, "part": part, "group": group, "value": value, "limit": limit, "secondary": secondary})

    for f in frames:
        fr = f["frame"]
        row = {"frame": fr, "door": f.get("door", 0.0), "parts": {}}
        door_pts = None
        if door is not None:
            centres = np.array([f["parts"][p][0:3] for p in HALF])
            near_lo, near_hi = centres.min(axis=0) - 2.4, centres.max(axis=0) + 2.4
            door_pts = door @ rotation_about(axis, f.get("door", 0.0) * open_angle).T + pivot
            door_pts = door_pts[np.all((door_pts > near_lo) & (door_pts < near_hi), axis=1)]
        for part, half in HALF.items():
            m = frame_matrix(f["parts"][part])
            radius = float(np.linalg.norm(half))
            idx = tree.query_ball_point(m[:3, 3], radius)
            contacts = {}
            if idx:
                if per_group:
                    contacts.update(group_depths(cloud[idx], labels[idx], m, half, args.tol))
                else:
                    d, k = depths(cloud[idx], m, half, args.tol)
                    if d > 0:
                        contacts[str(labels[idx[k]])] = d
            if door_pts is not None:
                near = door_pts[np.linalg.norm(door_pts - m[:3, 3], axis=1) < radius]
                if len(near):
                    d, _ = depths(near, m, half, args.tol)
                    if d > 0:
                        contacts["door"] = d
            low = float(corners(m, half)[:, 1].min())
            if low < 0:
                contacts["ground"] = -low
            # max() keeps the first of equal depths: car, then door, then ground.
            group = max(contacts, key=contacts.get) if contacts else None
            best = contacts[group] if contacts else 0.0
            row["parts"][part] = {"depth": round(best, 4), "group": group, "low": round(low, 4)}
            if per_group:
                row["parts"][part]["groups"] = {g: round(d, 4) for g, d in contacts.items()}
            for a in allow:
                if "touch" in a and a["from"] <= fr <= a["to"] and part in a["parts"]:
                    reach = radius + 2.5  # wide enough to report how far a floating hand is
                    near = [cloud[i] for i in tree.query_ball_point(m[:3, 3], reach) if labels[i] in a["groups"]]
                    if door_pts is not None and "door" in a["groups"]:
                        near += list(door_pts[np.linalg.norm(door_pts - m[:3, 3], axis=1) < reach])
                    gap = end_gap(np.array(near).reshape(-1, 3), m, half)
                    row["parts"][part]["gap"] = round(min(gap, 99.0), 3)
                    if gap > float(a["touch"]):
                        fail(fr, part, "float", round(min(gap, 99.0), 3), float(a["touch"]))
            tested = contacts if per_group else ({group: best} if group else {})
            for g, d in tested.items():
                if d <= args.tol:
                    continue
                allowed = 0.0
                for a in allow:
                    if a["from"] <= fr <= a["to"] and part in a["parts"] and g in a["groups"]:
                        allowed = max(allowed, a.get("depth", 0.0))
                if d > max(allowed, args.tol):
                    fail(fr, part, g, round(d, 6), max(allowed, args.tol), g != group)
            w = worst.get(part)
            if w is None or best > w[0]:
                worst[part] = (round(best, 4), fr, group)
        # Feet: a sole on the ground should not slide. Measured at the sole's centre, so a foot
        # turning on the spot (a pivot) is not a slide.
        if previous is not None:
            for leg in LEGS:
                m_now, m_before = frame_matrix(f["parts"][leg]), frame_matrix(previous["parts"][leg])
                low_now = corners(m_now, HALF[leg])[:, 1].min()
                low_before = corners(m_before, HALF[leg])[:, 1].min()
                if low_now < GROUNDED and low_before < GROUNDED:
                    sole_now = m_now[:3, :3] @ np.array([0, -1.0, 0]) + m_now[:3, 3]
                    sole_before = m_before[:3, :3] @ np.array([0, -1.0, 0]) + m_before[:3, 3]
                    speed = float(np.linalg.norm((sole_now - sole_before)[[0, 2]]) / dt)
                    row["parts"][leg]["slide"] = round(speed, 2)
                    if speed > args.slide:
                        fail(fr, leg, "slide", round(speed, 2), args.slide)
        previous = f
        rows.append(row)

    failures = [(x["frame"], x["part"], x["group"], x["value"]) for x in found]
    runs = spans(found, {f["frame"]: i for i, f in enumerate(frames)})
    mode = "every group a part touches" if per_group else "only the group of each part's deepest point"
    print(f"{len(frames)} frames, cloud {len(cloud)} points (+door {0 if door is None else len(door)}), tol {args.tol}")
    print(f"contacts tested: {mode}")
    for part, (d, fr, group) in worst.items():
        print(f"  worst {part:10s} {d:7.4f} at f{fr:g} ({group})")
    print(f"FAILURES {len(failures)}")
    for x in found[:60]:
        note = "  (not the deepest group)" if x["secondary"] else ""
        print(f"  f{x['frame']:<5g} {x['part']:10s} {x['group']:10s} {x['value']:.4f}  limit {x['limit']:.4f}{note}")
    print(f"SPANS {len(runs)}")
    for r in runs:
        frames_note = f"{r['frames']} frames" + (f", {r['secondary']} not the deepest group" if r["secondary"] else "")
        print(
            f"  f{r['from']:g}-f{r['to']:g} {r['part']:10s} {r['group']:10s} max {r['max']:.4f} at f{r['at']:g}"
            f"  limit {r['limit']:.4f}  ({frames_note})"
        )
    if args.json:
        record = {
            "baked": args.baked,
            "baked_sha256": file_sha256(args.baked),
            "scene_sha256": scene_sha256,
            "allow_sha256": file_sha256(args.allow) if args.allow else None,
            "allow": allow,
            "range": None if args.start is None and args.end is None else [args.start, args.end],
            "mutate": args.mutate,
            "tol": args.tol,
            "slide": args.slide,
            "spacing": args.spacing,
            "per_group": per_group,
            "frames": len(frames),
            "passed": not failures,
            "failures": failures,
            "spans": runs,
            "rows": rows,
        }
        with open(args.json, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(record, handle)
    return 1 if failures else 0


def file_sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
