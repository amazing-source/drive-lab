"""Which depth-fighting pairs a game camera sees, and how large they appear.

blender -b <assembled car.blend> --factory-startup -P tools/blender/dr458/zfight_seen.py -- <out.json> <manifest.json> [min px] [--controls]

Pairs are found with zfight_scan.py's test and seed (same-facing within 1.5 mm, along the
sample's normal, pairs over 1 cm2), keeping each pair's samples. Each sample is then looked at from
the game's cameras (Config/CarCamera), drawn as Roblox draws: single-sided, through glass:
- cockpit eye: the manifest's Driver_Eye moved over EYE_RANGE (forward -0.15..0.12 m, up
  -0.05..0.15 m, 3 x 3), seeing whatever lies inside the look-around reach (yaw 110 degrees plus
  half the horizontal field, pitch 40 plus half the vertical);
- chase: orbiting the centre of mass (1.113 m ahead of the rear axle, at hub height) 3.3 m back
  and 1.2 m up, look yaw -110..110 every 10 degrees, look pitch -40..40 every 20, aimed 4 m ahead
  of the rear axle and tilted 2 degrees up, frustum 75 degrees vertical (60 plus the kick); an
  orbit that would put the camera under the road (below 0.1 m) is skipped, the road hides the car.
A sample is seen from a camera when it faces it, lies in its frustum or reach, and the first front
face along the ray is its own surface (within 3 mm). Its size on screen is its area over the
squared distance, in 1080p pixels at a 60-degree vertical field. A pair is seen when its largest
size from any one camera reaches `min px` (default 20). Exit 1 when any pair with a master object
is seen. `--controls` adds two fighting quad pairs: one behind the car facing the chase camera
(must be seen) and one under the floor facing down (must not be).
"""
import json
import math
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

args = sys.argv[sys.argv.index("--") + 1:]
CONTROLS = "--controls" in args
args = [a for a in args if a != "--controls"]
out, manifest = args[0], args[1]
MIN_PX = float(args[2]) if len(args) > 2 else 20.0
LATERAL, SAMPLE_CM2, MAX_SAMPLES, DIST, COS = 0.0003, 0.5, 40000, 0.0015, math.cos(math.radians(25))
PER_PAIR = 100
GLASS = ("_glass", "_window_", "glassLHL", "glassRHL", "glassLTL", "glassRTL", "Glass_", "Lens")
PX_SR = (math.radians(60) / 1080) ** 2
rng = np.random.default_rng(11)


def add_quad_pair(name, centre, normal, size=0.1, gap=0.001):
    n = Vector(normal).normalized()
    u = n.orthogonal().normalized()
    w = n.cross(u)
    for k, off in enumerate((0.0, gap)):
        c = Vector(centre) + n * off
        h = size / 2
        vs = [c + (u * a + w * b) * h for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        me = bpy.data.meshes.new(f"{name}_{k}")
        me.from_pydata([tuple(v) for v in vs], [], [(0, 1, 2, 3)])
        if me.polygons[0].normal.dot(n) < 0:
            me.flip_normals()
        o = bpy.data.objects.new(f"{name}_{k}", me)
        bpy.context.scene.collection.objects.link(o)


if CONTROLS:
    add_quad_pair("CONTROL_seen_behind", (0.0, 1.6, 0.6), (0, 1, 0))
    add_quad_pair("CONTROL_hidden_under", (0.2, -1.3, 0.04), (0, 0, -1))

objs, T, own = [], [], []
dg = bpy.context.evaluated_depsgraph_get()
for o in bpy.context.scene.objects:
    if o.type != "MESH" or o.hide_render or any(c.name.startswith("Replaced") for c in o.users_collection):
        continue
    me = o.evaluated_get(dg).to_mesh()
    me.calc_loop_triangles()
    if not len(me.loop_triangles):
        o.evaluated_get(dg).to_mesh_clear()
        continue
    v = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", v)
    M = np.array(o.matrix_world)
    v = v.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3]
    t = np.empty(len(me.loop_triangles) * 3, np.int64)
    me.loop_triangles.foreach_get("vertices", t)
    T.append(v[t.reshape(-1, 3)])
    own.append(np.full(len(t) // 3, len(objs)))
    objs.append(o)
    o.evaluated_get(dg).to_mesh_clear()
T, own = np.concatenate(T), np.concatenate(own)
nrm = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
area = 0.5 * np.linalg.norm(nrm, axis=1)
nrm /= np.maximum(2 * area, 1e-12)[:, None]
is_glass = np.array([any(s in o.name for s in GLASS) for o in objs])
bvh = BVHTree.FromPolygons([tuple(p) for p in T.reshape(-1, 3)], [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(T))], epsilon=0.0)

pairs = {}
for k, o in enumerate(objs):
    idx = np.where(own == k)[0]
    a = area[idx]
    if a.sum() <= 0:
        continue
    n = int(min(MAX_SAMPLES, max(50, a.sum() * 1e4 / SAMPLE_CM2)))
    pick = idx[rng.choice(len(idx), n, p=a / a.sum())]
    r1, r2 = np.sqrt(rng.random(n)), rng.random(n)
    pts = (1 - r1)[:, None] * T[pick, 0] + (r1 * (1 - r2))[:, None] * T[pick, 1] + (r1 * r2)[:, None] * T[pick, 2]
    w = a.sum() * 1e4 / n
    for p, ti in zip(pts, pick):
        seen = set()
        for loc, _nr, fi, _d in bvh.find_nearest_range(Vector(p), DIST):
            j = int(own[fi])
            if j == k or j in seen or float(nrm[fi] @ nrm[ti]) < COS:
                continue
            dv = p - np.asarray(loc)
            if np.linalg.norm(dv - (dv @ nrm[ti]) * nrm[ti]) > LATERAL:
                continue
            seen.add(j)
            pairs.setdefault((k, j), []).append((p, nrm[ti], w, int(ti)))

meta = json.load(open(manifest))
e = meta["points"]["Driver_Eye"]
EYE0 = Vector((-e["right"], -e["forward"], e["up"]))
eyes = [EYE0 + Vector((0, -f, u)) for f in (-0.15, 0.0, 0.12) for u in (-0.05, 0.05, 0.15)]
EYE_YAW = math.radians(110) + math.atan(math.tan(math.radians(30)) * 16 / 9)
EYE_PITCH = math.radians(40 + 30)
CENTRE, LOOK_AT = Vector((0.0, -2.65 * 0.42, 0.345)), Vector((0.0, -4.0, 0.345))
chase = []
for yaw in range(-110, 111, 10):
    for pitch in range(-40, 41, 20):
        R = Matrix.Rotation(math.radians(yaw), 3, "Z") @ Matrix.Rotation(math.radians(pitch), 3, "X")
        cam = CENTRE + R @ Vector((0.0, 3.3 + 2.65 * 0.42, 1.2))
        if cam.z < 0.1:
            continue
        focus = CENTRE + R @ (LOOK_AT - CENTRE)
        q = (focus - cam).to_track_quat("-Z", "Y")
        q = q @ Matrix.Rotation(math.radians(2), 3, "X").to_quaternion()
        chase.append((f"chase yaw {yaw} pitch {pitch}", cam, q.to_matrix()))
TAN_V, TAN_H = math.tan(math.radians(37.5)), math.tan(math.radians(37.5)) * 16 / 9


def first_front_hit(origin, target):
    d = target - origin
    dist = d.length
    d.normalize()
    o, travelled = origin.copy(), 0.0
    for _ in range(64):
        loc, _n, fi, h = bvh.ray_cast(o, d, dist - travelled + 0.01)
        if loc is None:
            return None
        travelled += h
        if is_glass[own[fi]] or float(nrm[fi] @ np.asarray(d)) > 0:
            o = loc + d * 1e-5
            travelled += 1e-5
            continue
        return travelled
    return None


def seen_px(cam, p, n, w, inside):
    to_cam = cam - p
    dist = to_cam.length
    cos = float(np.asarray(to_cam) @ n) / dist
    if cos <= 0 or not inside(p):
        return 0.0
    hit = first_front_hit(cam, p)
    if hit is None or hit < dist - 0.003:
        return 0.0
    return w * 1e-4 * cos / dist ** 2 / PX_SR


rows = []
for (k, j), smp in pairs.items():
    a_cm2 = sum(s[2] for s in smp)
    if a_cm2 <= 1.0:
        continue
    use = [smp[i] for i in sorted(rng.choice(len(smp), min(PER_PAIR, len(smp)), replace=False))]
    scale = len(smp) / len(use)
    best = {"eye": (0.0, ""), "chase": (0.0, "")}
    for kind, cams in (("eye", [(f"eye {i}", c, None) for i, c in enumerate(eyes)]), ("chase", chase)):
        for label, cam, rot in cams:
            if rot is None:
                def inside(p, cam=cam):
                    d = p - cam
                    yaw = math.atan2(d.x, -d.y)
                    pitch = math.atan2(d.z, math.hypot(d.x, d.y))
                    return abs(yaw) <= EYE_YAW and abs(pitch) <= EYE_PITCH
            else:
                inv = rot.transposed()

                def inside(p, cam=cam, inv=inv):
                    c = inv @ (p - cam)
                    return c.z < 0 and abs(c.y / -c.z) <= TAN_V and abs(c.x / -c.z) <= TAN_H
            px = scale * sum(seen_px(cam, Vector(p), n, w, inside) for p, n, w, _ti in use)
            if px > best[kind][0]:
                best[kind] = (px, label)
    centre = np.mean([s[0] for s in smp], axis=0)
    a_, b_ = objs[k], objs[j]
    rows.append({"a": a_.name, "b": b_.name, "cm2": round(a_cm2, 1),
                 "a_collection": a_.users_collection[0].name, "b_collection": b_.users_collection[0].name,
                 "centre": [round(float(x), 3) for x in centre],
                 "eye_px": round(float(best["eye"][0]), 1), "eye_view": best["eye"][1],
                 "chase_px": round(float(best["chase"][0]), 1), "chase_view": best["chase"][1],
                 "seen": bool(max(best["eye"][0], best["chase"][0]) >= MIN_PX)})
rows.sort(key=lambda r: -max(r["eye_px"], r["chase_px"]))
master_cols = {"Body", "Cabin", "Doors", "Engine", "Evo", "Glass", "Lights", "Wheels", "Unsorted"}
master_seen = [r for r in rows if r["seen"] and (r["a_collection"] in master_cols or r["b_collection"] in master_cols)
               and not r["a"].startswith("CONTROL") and not r["b"].startswith("CONTROL")]
json.dump({"min_px": MIN_PX, "eye_base": [float(x) for x in EYE0], "pairs_over_1cm2": len(rows), "seen": sum(r["seen"] for r in rows),
           "master_seen": len(master_seen), "pairs": rows}, open(out, "w"), indent=1)
print(f"SEEN {sum(r['seen'] for r in rows)} of {len(rows)} pairs over 1 cm2 seen at >= {MIN_PX} px; with a master object: {len(master_seen)}")
for r in rows[:60]:
    print(f"SEEN {'Y' if r['seen'] else '.'} eye {r['eye_px']:8.1f} px  chase {r['chase_px']:8.1f} px  {r['cm2']:6.1f} cm2  "
          f"{r['a'][:38]:38s} | {r['b'][:38]:38s} at {r['centre']}  [{r['eye_view'] or '-'} / {r['chase_view'] or '-'}]")
sys.exit(1 if master_seen else 0)
