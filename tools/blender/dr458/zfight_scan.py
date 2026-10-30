"""Find surfaces that will depth-fight in Roblox: two different meshes within 1.5 mm and parallel.

blender -b <master.blend> --factory-startup -P zfight_scan.py -- <out.json> [max cm2 per pair]

Every visible mesh outside the Replaced_* collections is sampled (area-weighted, one sample per
SAMPLE_CM2, at most MAX_SAMPLES per object). A sample depth-fights when another object's face lies
within 1.5 mm of it facing the same way (normals within 25 degrees). Back-to-back faces (opposite
normals) do not fight on single-sided MeshParts, since one of the two is always culled; they are
counted apart, as information. Reported per pair of
objects as an area in cm2 (each pair counted from the sampled side, both sides listed). Exit code 1
when any pair exceeds the limit (default 1 cm2), so a build script can stop on it.
"""
import json
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

args = sys.argv[sys.argv.index("--") + 1:]
out = args[0]
limit = float(args[1]) if len(args) > 1 else 1.0
SAMPLE_CM2, MAX_SAMPLES, DIST, COS = 0.5, 40000, 0.0015, np.cos(np.radians(25))
rng = np.random.default_rng(11)
dg = bpy.context.evaluated_depsgraph_get()
objs, tris, owner = [], [], []
for c in bpy.data.collections:
    if c.name.startswith("Replaced"):
        continue
    for o in c.objects:
        if o.type != "MESH" or o.hide_render or o in objs:
            continue
        me = o.evaluated_get(dg).to_mesh()
        me.calc_loop_triangles()
        v = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", v)
        M = np.array(o.matrix_world); v = v.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3]
        t = np.empty(len(me.loop_triangles) * 3, np.int64); me.loop_triangles.foreach_get("vertices", t)
        tris.append(v[t.reshape(-1, 3)]); owner.append(np.full(len(t) // 3, len(objs))); objs.append(o)
        o.evaluated_get(dg).to_mesh_clear()
T = np.concatenate(tris); own = np.concatenate(owner)
nrm = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0]); area = 0.5 * np.linalg.norm(nrm, axis=1)
nrm /= np.maximum(2 * area, 1e-12)[:, None]
verts = T.reshape(-1, 3)
bvh = BVHTree.FromPolygons([tuple(p) for p in verts], [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(T))], epsilon=0.0)
pairs, back = {}, {}
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
        hits = bvh.find_nearest_range(Vector(p), DIST)
        seen = set()
        for _loc, _nr, fi, _d in hits:
            j = own[fi]
            if j == k or j in seen:
                continue
            c = float(nrm[fi] @ nrm[ti])
            if c >= COS:
                seen.add(j)
                pairs[(o.name, objs[j].name)] = pairs.get((o.name, objs[j].name), 0.0) + w
            elif c <= -COS:
                back[(o.name, objs[j].name)] = back.get((o.name, objs[j].name), 0.0) + w
rows = sorted(({"a": a_, "b": b_, "cm2": round(v, 1), "a_collection": bpy.data.objects[a_].users_collection[0].name,
                "b_collection": bpy.data.objects[b_].users_collection[0].name} for (a_, b_), v in pairs.items()), key=lambda r: -r["cm2"])
over = [r for r in rows if r["cm2"] > limit]
json.dump({"limit_cm2": limit, "pairs_over": len(over), "pairs": rows,
           "back_to_back_cm2_total": round(sum(back.values()), 1)}, open(out, "w"), indent=1)
print(f"ZFIGHT {len(over)} pairs over {limit} cm2 (of {len(rows)} touching); back-to-back (not fighting) {sum(back.values()):.0f} cm2")
for r in rows[:40]:
    print(f"ZFIGHT {r['cm2']:8.1f} cm2  {r['a'][:44]:44s} | {r['b'][:44]}")
sys.exit(1 if over else 0)
