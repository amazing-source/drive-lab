"""Penetration and contact check for baked start-up hands (tools/blender/startup_paths.py's
sequence mode writes the paths.json it reads), against the cabin dump the paths were made in.

  python tools/anim/startup_check.py <paths.json> [--allow <allow.json>] [--json <out.json>]
      [--break <seat axis>=<metres>] [--cabin <newer cabin dump.npz>]

Every baked sample, and a point half way to the next, sampled as the game samples the keys
(Rules/StartupArms.sample: positions on a cubic through every key, rotations turned evenly), places each hand's shown mesh (the posed hands in their wrist frame, the grip hand in the wheel's)
and the arm the controller would draw: the forearm and the upper arm as capsules of the sleeves'
smaller half-widths, the elbow from the controller's rule. Then:

- a hand vertex is inside a surface when most of its eight nearest surface samples face away from
  it (one sample alone misfires on thin double-faced parts), it is within MAX_DEPTH of the
  surface, and, where that object's surface is closed, a ray from it crosses its triangles an odd
  number of times (two rays of three: a finger in a cover's open cavity faces the cover's inner
  walls and fooled the vote; on an open surface the vote stands);
  its depth is the distance to the nearest sample. Further off, the vote says nothing:
  13 cm from an open strap, samples facing away were read as "inside" on the first bake. A hand
  sunk deeper than MAX_DEPTH into anything still fails, on the vertices nearer its surface. The controls the start-up turns are sampled at rest and the hand is turned back
  into their frame at each moment, so a guard or a key is checked where the game draws it;
- an arm is inside where a surface sample lies closer to its bone than the sleeve's half-width;
- the seated torso box (the car's seated pose) counts as a surface for the hands.

Fails on a hand more than HAND_LIMIT inside anything, except: the control a touch works, during
its touch, up to TOUCH_LIMIT; the steering wheel while the hand shows its grip, up to GRIP_LIMIT
(the grip's own measured fit). Fails on an arm more than ARM_LIMIT into the switch panel, the
wheel, the cage or the dash; arm contacts with anything else are listed, not failed (a sleeve on a
seat bolster or a harness strap is cloth on cloth). And contacts that must touch: during each
touch the hand's contact point (the index's end, or the pinch) stays within TOUCH_GAP of the
control's point as the game turns it.

A named contact goes in an allow list (`--allow`): [{"object": name prefix, "side": "R" or "L",
"shape": the hand shown or "*", "from"/"to": seconds, "limitMm", "why", "decidedBy", and "kind": "hand"
(the default), "forearm" or "upper arm" for an arm on a strict object}]; inside it that part may go
that deep. Every allowance is printed with its worst depth, and none is widened to pass.

And the hand-over from getting in: with the start pose "rest", each track's first key must be the
shared rest pose's wrist frame (the REST_POSE.json the entry's last frame aims its arms at), to
HANDOVER_GAP and HANDOVER_TURN.

`--break z=-0.02` moves every right-hand sample 2 cm forward (any seat axis x, y or z; metres) to
show the check failing. Exits 1 on any failure; `--json` records what it checked (SHA-256 of the
paths and the cabin, the mutation, the worst depth per object) for the PR.
"""

import hashlib
import json
import math
import struct
import sys

import numpy as np
from scipy.spatial import cKDTree

HAND_LIMIT = 0.002
TOUCH_LIMIT = 0.003
GRIP_LIMIT = 0.003
ARM_LIMIT = 0.005
TOUCH_GAP = 0.002
HANDOVER_GAP = 0.0001
HANDOVER_TURN = math.radians(0.1)
# The sleeves' smaller half-widths (tools/blender/driver_sleeves.py): forearm toward the wrist,
# upper arm.
FOREARM_RADIUS, UPPER_RADIUS = 0.029, 0.046
SPACING = 0.0015
MAX_DEPTH = 0.02
REGION_MARGIN = 0.08
STRICT_ARM = ("SwitchPanel", "Panel", "SteeringWheel", "GEO_INT_STwheel", "WheelButton", "WheelRotary", "Cage", "Binnacle", "Dash", "dash")
WORLD_STUD = 0.28 / 1.5


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def read_glb(path):
    data = open(path, "rb").read()
    length = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20 : 20 + length])
    blob = data[20 + length + 8 :]
    verts = []
    for mesh in gltf["meshes"]:
        for prim in mesh["primitives"]:
            acc = gltf["accessors"][prim["attributes"]["POSITION"]]
            view = gltf["bufferViews"][acc["bufferView"]]
            start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
            verts.append(np.frombuffer(blob, dtype=np.float32, count=acc["count"] * 3, offset=start).reshape(-1, 3))
    # The exporter's half turn about y (Roblox's importer undoes it), studs -> metres.
    return np.concatenate(verts).astype(float) * np.array([-1.0, 1.0, -1.0]) * WORLD_STUD


def quat_matrix(q):
    w, x, y, z = q
    return np.array(
        [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
    )


def slerp(a, b, s):
    a, b = np.array(a), np.array(b)
    if a @ b < 0:
        b = -b
    d = min(1.0, a @ b)
    if d > 0.9995:
        q = a + (b - a) * s
        return q / np.linalg.norm(q)
    ang = math.acos(d)
    return (a * math.sin((1 - s) * ang) + b * math.sin(s * ang)) / math.sin(ang)


def rotation(axis, angle):
    axis = np.asarray(axis, float) / np.linalg.norm(axis)
    x, y, z = axis
    c, s, k = math.cos(angle), math.sin(angle), 1 - math.cos(angle)
    return np.array([[c + x * x * k, x * y * k - z * s, x * z * k + y * s], [y * x * k + z * s, c + y * y * k, y * z * k - x * s], [z * x * k - y * s, z * y * k + x * s, c + z * z * k]])


def openness(t, move):
    back = move.get("back")
    if back is None or t < back:
        return max(0.0, min(1.0, (t - (move["at"] - move["move"])) / move["move"]))
    return max(0.0, min(1.0, 1 - (t - back) / move["move"]))


def surface_samples(v, t, spacing, ids=None):
    """Points over the triangles `t` about `spacing` apart, with each triangle's normal and index.
    With `ids` (each triangle's index in the whole dump) a triangle always gets the same points,
    whatever else is sampled with it: a depth must not change because the region did."""
    a, b, c = v[t[:, 0]], v[t[:, 1]], v[t[:, 2]]
    n = np.cross(b - a, c - a)
    area = 0.5 * np.linalg.norm(n, axis=1)
    n = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    k = np.maximum(1, np.ceil(area / (spacing * spacing * 0.5))).astype(int)
    tri = np.repeat(np.arange(len(t)), k)
    if ids is None:
        rng = np.random.default_rng(0)
        r1, r2 = rng.random(len(tri)), rng.random(len(tri))
    else:
        nth = np.arange(len(tri)) - np.repeat(np.cumsum(k) - k, k)
        seed = np.asarray(ids)[tri].astype(np.float64) * 7919.0 + nth
        r1 = np.modf(np.abs(np.sin(seed * 12.9898) * 43758.5453))[0]
        r2 = np.modf(np.abs(np.sin(seed * 78.233) * 43758.5453))[0]
    f = r1 + r2 > 1
    r1[f], r2[f] = 1 - r1[f], 1 - r2[f]
    p = a[tri] + (b[tri] - a[tri]) * r1[:, None] + (c[tri] - a[tri]) * r2[:, None]
    return p, n[tri], tri


def inside_depth(tree, samples, normals, points, votes=8):
    dist, idx = tree.query(points, k=votes)
    facing = np.einsum("ijk,ijk->ij", points[:, None, :] - samples[idx], normals[idx]) < 0
    inside = (facing.mean(1) > 0.5) & (dist[:, 0] < MAX_DEPTH)
    return np.where(inside, dist[:, 0], 0.0), idx[:, 0]


RAYS = np.array([[0.267, 0.535, 0.802], [-0.577, 0.577, -0.577], [0.707, -0.3, -0.64]])


def parity_inside(points, triangles):
    """Whether each point is inside the closed surface `triangles` (m, 3, 3): odd crossings along
    a ray, by a majority of three rays. The normal vote alone reads a point in a cover's open
    cavity, facing its inner walls, as inside the cover."""
    if len(points) == 0:
        return np.zeros(0, bool)
    a, b, c = triangles[:, 0], triangles[:, 1], triangles[:, 2]
    e1, e2 = b - a, c - a
    odd = np.zeros((len(RAYS), len(points)), bool)
    for r, d in enumerate(RAYS / np.linalg.norm(RAYS, axis=1, keepdims=True)):
        h = np.cross(d, e2)
        det = np.einsum("ij,ij->i", e1, h)
        ok = np.abs(det) > 1e-12
        e1o, e2o, ao, ho, inv = e1[ok], e2[ok], a[ok], h[ok], 1.0 / det[ok]
        for start in range(0, len(points), 64):
            p = points[start : start + 64]
            sv = p[:, None, :] - ao[None]
            u = np.einsum("pij,ij->pi", sv, ho) * inv
            q = np.cross(sv, e1o[None])
            v = np.einsum("j,pij->pi", d, q) * inv
            t = np.einsum("pij,ij->pi", q, e2o) * inv
            hit = (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 1e-9)
            odd[r, start : start + 64] = hit.sum(1) % 2 == 1
    return odd.sum(0) >= 2


def lean_at(lean, t):
    """tools/blender/startup_sequence.lean_at: degrees forward, smoothstep between keys."""
    if not lean:
        return 0.0
    keys = lean["keys"]
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, d0), (t1, d1) in zip(keys, keys[1:]):
        if t <= t1:
            u = (t - t0) / (t1 - t0)
            return d0 + (d1 - d0) * u * u * (3 - 2 * u)
    return keys[-1][1]


def lean_turn(lean, t):
    """The torso's turn at `t` about the seat's x axis (forward positive), and its pivot (metres)."""
    a = -math.radians(lean_at(lean, t))
    c, s = math.cos(a), math.sin(a)
    pivot = np.array(lean["pivot"], float) if lean else np.zeros(3)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]]), pivot


def elbow(shoulder, wrist, along, sign, upper, lower, bias):
    to_wrist = wrist - shoulder
    distance = min(max(np.linalg.norm(to_wrist), abs(upper - lower) + 1e-6), upper + lower - 1e-6)
    bend = math.acos(max(-1, min(1, (upper * upper + distance * distance - lower * lower) / (2 * upper * distance))))
    pole = wrist + along * lower - shoulder
    pole = pole / np.linalg.norm(pole) + np.array([sign * bias[0], bias[1], bias[2]])
    unit = to_wrist / np.linalg.norm(to_wrist)
    out = pole - unit * (pole @ unit)
    out = out / np.linalg.norm(out)
    return shoulder + unit * (upper * math.cos(bend)) + out * (upper * math.sin(bend))


def segment_depth(points, a, b, radius):
    ab = b - a
    u = np.clip(((points - a) @ ab) / (ab @ ab), 0, 1)
    d = np.linalg.norm(points - (a + ab[None, :] * u[:, None]), axis=1)
    return radius - d


def main(argv):
    paths_path = argv[0]
    record = json.load(open(paths_path))
    inputs = record["inputs"]
    studs = record["studsPerMetre"]
    mutation = None
    if "--break" in argv:
        axis, amount = argv[argv.index("--break") + 1].split("=")
        mutation = ("xyz".index(axis), float(amount))
    # A newer dump of the same cabin, when the cockpit changed after the bake.
    cabin_path = argv[argv.index("--cabin") + 1] if "--cabin" in argv else inputs["cabin"]
    data = np.load(cabin_path)
    origin = np.array(inputs["seat"])
    rel = data["vertices"].astype(float) - origin
    verts = np.stack([-rel[:, 0], rel[:, 2], rel[:, 1]], 1)
    names = list(data["names"])
    owner = data["object"]
    tris = data["triangles"]

    shapes = {}
    for shape in ("Rest", "Point", "Pinch"):
        for side in ("R", "L"):
            shapes[(shape, side)] = read_glb(f"{inputs['posesDir']}/hand_{shape}_{side}.glb")
    grip_local = {s: np.array(m) for s, m in record["gripLocal"].items()}
    for side in ("R", "L"):
        g = grip_local[side]
        wheel_verts = read_glb(f"{inputs['gripDir']}/hand_{side}.glb")
        rot, pos = g[:3, :3], g[:3, 3] / studs
        shapes[("Grip", side)] = (wheel_verts - pos) @ rot
    tips = {"Point": np.array(record["tips"]["Point"]) / studs, "Pinch": np.array(record["tips"]["Pinch"]) / studs}

    def samples_of(track, mutate):
        times = np.array([s["t"] for s in track])
        pos = np.array([s["p"] for s in track]) / studs
        n = len(track)

        def slope(i):
            before, after = max(i - 1, 0), min(i + 1, n - 1)
            span = times[after] - times[before]
            return (pos[after] - pos[before]) / span if span > 0 else np.zeros(3)

        out = []
        for i in range(n):
            steps = [0.0] if i == n - 1 else [0.0, 0.5]
            for frac in steps:
                if frac == 0:
                    p, q, t = pos[i].copy(), np.array(track[i]["q"]), times[i]
                else:
                    span = times[i + 1] - times[i]
                    s2, s3 = frac * frac, frac**3
                    p = (2 * s3 - 3 * s2 + 1) * pos[i] + (s3 - 2 * s2 + frac) * span * slope(i) + (-2 * s3 + 3 * s2) * pos[i + 1] + (s3 - s2) * span * slope(i + 1)
                    q = slerp(track[i]["q"], track[i + 1]["q"], frac)
                    t = times[i] + span * frac
                if mutate:
                    p[mutation[0]] += mutation[1]
                out.append((t, p, quat_matrix(q), track[i]["shape"]))
        return out

    tracks = {"R": samples_of(record["right"], mutation is not None), "L": samples_of(record["left"], False)}
    placed = {}
    lo, hi = np.full(3, np.inf), np.full(3, -np.inf)
    for side, track in tracks.items():
        rows = []
        for t, p, r, shape in track:
            pts = shapes[(shape, side)] @ r.T + p
            lo, hi = np.minimum(lo, pts.min(0)), np.maximum(hi, pts.max(0))
            rows.append((t, p, r, shape, pts))
        placed[side] = rows
    arm = record["arm"]
    upper, lower = arm["upper"] / studs, arm["lower"] / studs
    bias = arm["elbowBias"]
    shoulders = {s: np.array(arm["shoulders"][s]) / studs for s in ("R", "L")}
    for s in shoulders.values():
        lo, hi = np.minimum(lo, s), np.maximum(hi, s)
    lo, hi = lo - REGION_MARGIN, hi + REGION_MARGIN

    touches = record["touches"]
    # The cabin objects each turned control moves (a touch's "turns", else its "part" or its name), and the
    # controls: a control's pieces are one rigid body, measured as one surface (a small piece measured on its
    # own fools the nearest-sample vote).
    moving = {name: t for t in touches if t["move"] for name in (t.get("turns") or [t.get("part") or t["control"]])}
    controls = {t["control"]: t for t in touches if t["move"]}
    # Static cabin in the region; each moving control on its own, at rest.
    tri_lo = verts[tris].min(1)
    tri_hi = verts[tris].max(1)
    in_region = np.all(tri_hi >= lo, 1) & np.all(tri_lo <= hi, 1)
    groups = {}
    for name in set(names[i] for i in np.unique(owner[in_region])):
        index = names.index(name)
        mask = in_region & (owner == index)
        key = moving[name]["control"] if name in moving else "static"
        groups.setdefault(key, []).append(mask)
    surfaces = {}
    for key, masks in groups.items():
        mask = np.any(masks, 0)
        p, n, tri = surface_samples(verts, tris[mask], SPACING, np.flatnonzero(mask))
        obj = owner[mask][tri]
        surfaces[key] = (cKDTree(p), p, n, obj)

    cache = {}

    def object_triangles(obj):
        """The object's triangles when its surface is closed (every edge on two triangles), else
        None: on an open surface a ray's parity proves nothing, so the vote stands."""
        if obj not in cache:
            faces = tris[owner == obj]
            edges = np.sort(np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]]), axis=1)
            _, counts = np.unique(edges, axis=0, return_counts=True)
            cache[obj] = verts[faces] if np.all(counts == 2) else None
        return cache[obj]

    seated = json.load(open(inputs["seatedPose"]))["boxes"]["Torso"]
    cols = np.array(seated["axes_blender_columns_xyz"]).T
    torso_axes = np.stack([np.array([-c[0], c[2], c[1]]) for c in cols], 1)
    torso_centre = np.array(seated["centre_seat_studs"]) / studs
    torso_half = np.array(seated["half_m"])

    worst = {}
    failures = []
    allowances = json.load(open(argv[argv.index("--allow") + 1])) if "--allow" in argv else []

    def allowance(name, side, shape, t, kind="hand"):
        for entry in allowances:
            if entry.get("kind", "hand") != kind:
                continue
            if name.startswith(entry["object"]) and entry["side"] == side and entry["shape"] in (shape, "*") and entry["from"] <= t <= entry["to"]:
                return entry
        return None

    def note(kind, obj, depth, t, side, allowed, limit, where=None):
        key = (kind, side, obj)
        if depth > worst.get(key, (0, 0, None, None, None))[0]:
            worst[key] = (depth, t, allowed, limit, where)
        if depth > limit:
            failures.append((kind, side, obj, round(depth * 1000, 2), round(t, 3)))

    def touch_at(t):
        for touch in touches:
            if touch["from"] - 0.05 <= t <= touch["to"] + 0.05:
                return touch
        return None

    gaps = {t["control"]: 0.0 for t in touches}
    gap_at = {}
    for side, rows in placed.items():
        sign = 1 if side == "R" else -1
        for t, p, r, shape, pts in rows:
            touch = touch_at(t) if side == "R" else None
            tree, sp, sn, so = surfaces["static"]
            depth, idx = inside_depth(tree, sp, sn, pts)
            if depth.max() > 0:
                flagged = np.flatnonzero(depth > 0)
                for obj in np.unique(so[idx[flagged]]):
                    closed = object_triangles(obj)
                    if closed is not None:
                        mine = flagged[so[idx[flagged]] == obj]
                        depth[mine[~parity_inside(pts[mine], closed)]] = 0.0
            if depth.max() > 0:
                for obj in np.unique(so[idx[depth > 0]]):
                    name = names[obj]
                    hits = (so[idx] == obj) & (depth > 0)
                    k = np.flatnonzero(hits)[np.argmax(depth[hits])]
                    d = depth[k]
                    where = [round(c, 4) for c in r.T @ (pts[k] - p)]
                    named = allowance(name, side, shape, t)
                    if named:
                        note("hand", name, d, t, side, named["why"], named["limitMm"] / 1000, where)
                    elif shape == "Grip" and name.startswith("SteeringWheel"):
                        note("hand", name, d, t, side, "grip on the rim", GRIP_LIMIT, where)
                    elif touch and name in (touch.get("turns") or [touch.get("part") or touch["control"]]):
                        note("hand", name, d, t, side, "touch", TOUCH_LIMIT, where)
                    else:
                        note("hand", name, d, t, side, None, HAND_LIMIT, where)
            for cname, control in controls.items():
                if cname not in surfaces:
                    continue
                tree_c, cp, cn, co = surfaces[cname]
                # Moves on one control add up (a key to ON, then on to START).
                angle = sum(m["angle"] * openness(t, m) for m in control.get("moves") or [control["move"]])
                pivot = np.array(control["pivot"]) / studs
                back = rotation(control["axis"], -angle)
                local = (pts - pivot) @ back.T + pivot
                d_c, i_c = inside_depth(tree_c, cp, cn, local)
                if d_c.max() > 0:
                    flagged = np.flatnonzero(d_c > 0)
                    parts = [names.index(n) for n, t2 in moving.items() if t2["control"] == cname]
                    closed = [object_triangles(o) for o in parts]
                    if all(c is not None for c in closed):
                        d_c[flagged[~parity_inside(local[flagged], np.concatenate(closed))]] = 0.0
                if d_c.max() > 0:
                    allowed = touch is not None and touch["control"] == cname
                    k = int(np.argmax(d_c))
                    name = names[co[i_c[k]]]
                    where = [round(c, 4) for c in r.T @ (pts[k] - p)]
                    note("hand", name, d_c.max(), t, side, "touch" if allowed else None, TOUCH_LIMIT if allowed else HAND_LIMIT, where)
            local = (pts - torso_centre) @ torso_axes
            inside = np.all(np.abs(local) < torso_half, 1)
            if inside.any():
                d = (torso_half - np.abs(local[inside])).min(1).max()
                note("hand", "Torso (R6)", d, t, side, None, HAND_LIMIT)
            # The arm the controller draws to this wrist.
            turn, pivot = lean_turn(record.get("lean"), t)
            shoulder = pivot + turn @ (shoulders[side] - pivot)
            joint = elbow(shoulder, p, r[:, 2], sign, upper, lower, list(turn @ np.array(bias, float)))
            for bone, a, b, radius in (("forearm", joint, p, FOREARM_RADIUS), ("upper arm", shoulder, joint, UPPER_RADIUS)):
                near = tree.query_ball_point((a + b) / 2, np.linalg.norm(b - a) / 2 + radius)
                if not near:
                    continue
                near = np.array(near)
                d = segment_depth(sp[near], a, b, radius)
                hit = d > 0
                for obj in np.unique(so[near][hit]):
                    name = names[obj]
                    dd = d[hit & (so[near] == obj)].max()
                    strict = any(name.startswith(k) for k in STRICT_ARM)
                    named = allowance(name, side, shape, t, bone) if strict else None
                    if named:
                        note(bone, name, dd, t, side, named["why"], named["limitMm"] / 1000)
                    else:
                        note(bone, name, dd, t, side, None if strict else "cloth contact, listed", ARM_LIMIT if strict else 1.0)
            if side == "R":
                for touch in touches:
                    if touch["move"] and touch["from"] <= t <= touch["to"]:
                        angle = sum(m["angle"] * openness(t, m) for m in touch.get("moves") or [touch["move"]])
                        pivot = np.array(touch["pivot"]) / studs
                        target = (np.array(touch["point"]) / studs - pivot) @ rotation(touch["axis"], angle).T + pivot
                        tip = r @ tips[touch["shape"]] + p
                        gap = float(np.linalg.norm(tip - target))
                        if gap > gaps[touch["control"]]:
                            gaps[touch["control"]], gap_at[touch["control"]] = gap, round(t, 4)
                    elif not touch["move"] and touch["to"] - 0.5 <= t <= touch["to"]:
                        tip = r @ tips["Point"] + p
                        face = np.array(touch["point"]) / studs
                        gap = float(np.linalg.norm(tip - face))
                        if gap > gaps[touch["control"]]:
                            gaps[touch["control"]], gap_at[touch["control"]] = gap, round(t, 4)
    for name, gap in gaps.items():
        if gap > TOUCH_GAP:
            failures.append(("float", "R", name, round(gap * 1000, 2), None))
    handover = {}
    if inputs["sequence"].get("start", "rest") == "rest":
        rest = json.load(open(inputs["restPose"]))
        for side, label in (("R", "right"), ("L", "left")):
            first = placed[side][0]
            want = rest[label]
            off = float(np.linalg.norm(first[1] - np.array(want["wrist"]) / studs))
            have = np.array(record["right" if side == "R" else "left"][0]["q"])
            want_q = np.array(want["rotation"])
            # Both files round their quaternions; unnormalised, a dot of 0.999999 reads as 0.16 degrees.
            dot = abs(float((have / np.linalg.norm(have)) @ (want_q / np.linalg.norm(want_q))))
            turn = 2 * math.acos(min(1.0, dot))
            handover[label] = {"mm": round(off * 1000, 3), "deg": round(math.degrees(turn), 3)}
            if off > HANDOVER_GAP or turn > HANDOVER_TURN:
                failures.append(("handover", side, "rest pose", round(off * 1000, 3), 0.0))

    rows = sorted(
        ({"kind": k[0], "side": k[1], "object": k[2], "worstMm": round(v[0] * 1000, 2), "at": round(v[1], 3), "allowed": v[2], "limitMm": round(v[3] * 1000, 1), "handPoint": v[4]} for k, v in worst.items()),
        key=lambda r: -r["worstMm"],
    )
    result = {
        "paths": paths_path,
        "pathsSha256": sha(paths_path),
        "cabin": cabin_path,
        "cabinSha256": sha(cabin_path),
        "mutation": argv[argv.index("--break") + 1] if mutation else None,
        "allow": allowances,
        "samples": {s: len(r) for s, r in placed.items()},
        "touchGapMm": {k: round(v * 1000, 2) for k, v in gaps.items()},
        "touchGapAt": gap_at,
        "handover": handover,
        "contacts": rows,
        "failures": failures[:40],
        "failureCount": len(failures),
        "pass": not failures,
    }
    for row in rows[:25]:
        print(f"{row['kind']:9} {row['side']} {row['object'][:40]:40} {row['worstMm']:7.2f} mm at {row['at']:.3f}s  {row['allowed'] or ''} {row['handPoint'] or ''}")
    print("touch gaps (mm):", result["touchGapMm"], "at", gap_at)
    print("first key vs the shared rest pose:", handover)
    print(("PASS" if result["pass"] else f"FAIL ({len(failures)} sample-failures)"), "mutation:", result["mutation"])
    if "--json" in argv:
        json.dump(result, open(argv[argv.index("--json") + 1], "w"), indent=1)
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
