"""Measure decimation variants of Cabin_InnerSkin: triangles, surface deviation, boundary retreat.

blender -b <master.blend> --factory-startup -P tools/blender/dr458/skin_probe.py -- <source.blend> <report.json>

The source is the skin before decimation and the depth-fight fixer (dr458_master_v11_cut.blend).
The skin is the body's cabin faces copied 3 mm inward, so it inherits the body's splits at hard
edges and UV seams; welded, its open boundary is its real outline, where it meets the door frames,
the roof rubber and the dash. A slit opens where that outline retreats: boundary retreat is the
distance from points every 2 mm along the source outline to the variant's surface.
Variants: the source, the master's current skin (decimated, then moved by the fixer), and the
welded skin decimated at several ratios with no vertex group and with the outline weighted 1 /
the rest 0 and the reverse, to learn which way Blender's Decimate weights protect.
"""
import json
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

src_blend, out_json = sys.argv[sys.argv.index("--") + 1:][:2]
rng = np.random.default_rng(11)
with bpy.data.libraries.load(src_blend, link=False) as (src, dst):
    dst.objects = ["Cabin_InnerSkin"]
src_obj = dst.objects[0]
cur_obj = bpy.data.objects["Cabin_InnerSkin"]
MW = src_obj.matrix_world.copy()
print("PROBE source matrix identity:", MW == cur_obj.matrix_world, "current matrix", [round(x, 4) for x in cur_obj.matrix_world.translation])


def tri_arrays(me, mw):
    me.calc_loop_triangles()
    v = np.array([tuple(mw @ x.co) for x in me.vertices])
    t = np.array([tuple(lt.vertices) for lt in me.loop_triangles], dtype=np.int64)
    return v, t


def bvh_of(v, t):
    return BVHTree.FromPolygons([tuple(x) for x in v], [tuple(x) for x in t])


def surf_samples(v, t, n):
    a = 0.5 * np.linalg.norm(np.cross(v[t[:, 1]] - v[t[:, 0]], v[t[:, 2]] - v[t[:, 0]]), axis=1)
    k = rng.choice(len(t), n, p=a / a.sum())
    r1, r2 = np.sqrt(rng.random(n)), rng.random(n)
    return (1 - r1)[:, None] * v[t[k, 0]] + (r1 * (1 - r2))[:, None] * v[t[k, 1]] + (r1 * r2)[:, None] * v[t[k, 2]]


def welded(me):
    m = me.copy()
    bm = bmesh.new()
    bm.from_mesh(m)
    n0 = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bnd = sum(1 for e in bm.edges if e.is_boundary)
    bm.to_mesh(m)
    bm.free()
    return m, n0, bnd


def boundary_points(me, mw, step=0.002):
    bm = bmesh.new()
    bm.from_mesh(me)
    pts = []
    for e in bm.edges:
        if not e.is_boundary:
            continue
        a, b = mw @ e.verts[0].co, mw @ e.verts[1].co
        k = max(1, int((b - a).length / step))
        pts += [a.lerp(b, i / k) for i in range(k)]
    bm.free()
    return np.array([tuple(p) for p in pts])


def measure(me, mw):
    v, t = tri_arrays(me, mw)
    if not len(t):
        return {"tris": 0}
    b = bvh_of(v, t)
    d1 = np.array([b.find_nearest(Vector(p))[3] for p in SRC_PTS])
    d2 = np.array([SRC_BVH.find_nearest(Vector(p))[3] for p in surf_samples(v, t, 2000)])
    dev = np.r_[d1, d2] * 1000
    br = np.array([b.find_nearest(Vector(p))[3] for p in BND]) * 1000
    return {"tris": int(len(t)), "dev_p95_mm": round(float(np.percentile(dev, 95)), 2), "dev_max_mm": round(float(dev.max()), 2),
            "bnd_p95_mm": round(float(np.percentile(br, 95)), 2), "bnd_p99_mm": round(float(np.percentile(br, 99)), 2),
            "bnd_max_mm": round(float(br.max()), 2), "bnd_over_1mm_share": round(float((br > 1.0).mean()), 4)}


def decimate(me, ratio, group=None, factor=0.0, invert=False):
    tmp = bpy.data.objects.new("_tmp", me.copy())
    bpy.context.scene.collection.objects.link(tmp)
    tmp.matrix_world = MW
    m = tmp.modifiers.new("d", "DECIMATE")
    m.ratio = ratio
    if group is not None:
        vg = tmp.vertex_groups.new(name="pin")
        bm = bmesh.new()
        bm.from_mesh(tmp.data)
        onb = {v.index for e in bm.edges if e.is_boundary for v in e.verts}
        bm.free()
        inside = [i for i in range(len(tmp.data.vertices)) if i not in onb]
        vg.add(sorted(onb), 1.0 if group == "outline1" else 0.0, "REPLACE")
        vg.add(inside, 0.0 if group == "outline1" else 1.0, "REPLACE")
        m.vertex_group, m.vertex_group_factor, m.invert_vertex_group = "pin", factor, invert
    dg = bpy.context.evaluated_depsgraph_get()
    out = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    old = tmp.data
    bpy.data.objects.remove(tmp, do_unlink=True)
    bpy.data.meshes.remove(old)
    return out


sv, st = tri_arrays(src_obj.data, MW)
SRC_PTS = surf_samples(sv, st, 2000)
SRC_BVH = bvh_of(sv, st)
wme, n0, bnd_w = welded(src_obj.data)
BND = boundary_points(wme, MW)
bm = bmesh.new()
bm.from_mesh(src_obj.data)
bnd_raw = sum(1 for e in bm.edges if e.is_boundary)
bm.free()
rep = {"source": {"verts": n0, "verts_welded": len(wme.vertices), "boundary_edges_raw": bnd_raw,
                  "boundary_edges_welded": bnd_w, "outline_samples": int(len(BND))}, "variants": {}}
print("PROBE", rep["source"], flush=True)
rep["variants"]["source"] = measure(src_obj.data, MW)
rep["variants"]["current_master"] = measure(cur_obj.data, cur_obj.matrix_world)
for r in (0.3, 0.4, 0.5, 0.6, 0.7, 0.8):
    for name, kw in (("plain", {}), ("outline1_f10", {"group": "outline1", "factor": 10.0}),
                     ("outline1_f1000", {"group": "outline1", "factor": 1000.0}),
                     ("outline0_f10", {"group": "outline0", "factor": 10.0}),
                     ("outline0_f1000", {"group": "outline0", "factor": 1000.0})):
        me = decimate(wme, r, **kw)
        rep["variants"][f"{name}_r{r}"] = measure(me, MW)
        bpy.data.meshes.remove(me)
    print("PROBE ratio", r, "done", flush=True)
json.dump(rep, open(out_json, "w"), indent=1)
for k, v in rep["variants"].items():
    print(f"PROBE {k:22s} {v}")
