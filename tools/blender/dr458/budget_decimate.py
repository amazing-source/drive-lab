"""Bring the master to its triangle budget by decimating each object as far as its shape allows.

blender -b <master.blend> --factory-startup -P tools/blender/dr458/budget_decimate.py -- <out.blend> <report.json> [budget.json]

Per object, a binary search finds the lowest collapse-decimation ratio whose surface deviation stays
inside the object's tolerance: sample points on the original surface, distance to the decimated
one (and back, so a collapse cannot spike out unseen), p95 and max. Tolerances by area (mm, p95 /
max): body, doors and aero 1.0 / 5; lamps 0.7 / 3; wheels 0.8 / 3; engine 4 / 15; cabin 2 / 8.
Objects under 300 triangles and the glass are left alone. The plan's lines (plan/dr458_budget.json)
are ceilings, not targets: each area takes the tightest tolerance whose result fits its line, trying
0.25x, 0.5x, 1x, 1.5x, 2.25x and 3.4x the base values in turn; the report gives the scale each area
ended at (over its line at 3.4x, it says so). Normals are rebuilt by
angle (35 degrees) after decimation, since collapse invalidates the source's custom normals.
"""
import json
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

args = sys.argv[sys.argv.index("--") + 1:]
out_blend, out_json = args[0], args[1]
rng = np.random.default_rng(2)
# Lines from plan/dr458_budget.json (dr458_target_lod0.areas), mapped onto the master's collections.
LINES = {"exterior": (("Body", "Doors", "Evo", "Lights", "Glass"), 90000),
         "wheels": (("Wheels",), 38000),
         "engine": (("Engine",), 12000),
         "cabin_shell": (("Cabin",), 23000)}  # dash 8k (the binnacle is a cockpit piece) + floor, tunnel, sills, bulkhead, lining 9k + reserve 6k
TOL = {"Body": (1.0, 5.0), "Doors": (1.0, 5.0), "Evo": (1.0, 5.0), "Lights": (0.7, 3.0), "Glass": (0.0, 0.0),
       "Wheels": (0.8, 3.0), "Engine": (4.0, 15.0), "Cabin": (2.0, 8.0)}


def tris(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)


def world_tris(o, me):
    mw = o.matrix_world
    v = np.array([tuple(mw @ x.co) for x in me.vertices])
    me.calc_loop_triangles()
    t = np.array([tuple(lt.vertices) for lt in me.loop_triangles])
    return v, t


def samples(v, t, n):
    a = 0.5 * np.linalg.norm(np.cross(v[t[:, 1]] - v[t[:, 0]], v[t[:, 2]] - v[t[:, 0]]), axis=1)
    k = rng.choice(len(t), n, p=a / a.sum())
    r1, r2 = np.sqrt(rng.random(n)), rng.random(n)
    return (1 - r1)[:, None] * v[t[k, 0]] + (r1 * (1 - r2))[:, None] * v[t[k, 1]] + (r1 * r2)[:, None] * v[t[k, 2]]


def deviation(src_pts, src_bvh, v, t):
    b = BVHTree.FromPolygons([tuple(x) for x in v], [tuple(x) for x in t])
    d1 = [(b.find_nearest(Vector(p))[3] or 0.0) for p in src_pts]
    dst_pts = samples(v, t, min(1500, len(src_pts)))
    d2 = [(src_bvh.find_nearest(Vector(p))[3] or 0.0) for p in dst_pts]
    d = np.r_[d1, d2] * 1000
    return float(np.percentile(d, 95)), float(d.max())


def decimated(o, ratio):
    src = o.data.copy()  # weights live on the mesh: never write them into the original's
    tmp = bpy.data.objects.new("_tmp", src)
    bpy.context.scene.collection.objects.link(tmp)
    tmp.matrix_world = o.matrix_world
    m = tmp.modifiers.new("d", "DECIMATE")
    m.ratio = ratio
    dg = bpy.context.evaluated_depsgraph_get()
    ev = tmp.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    bpy.data.objects.remove(tmp, do_unlink=True)
    bpy.data.meshes.remove(src)
    return me


def best_ratio(o, p95_tol, max_tol):
    v, t = world_tris(o, o.data)
    src_pts = samples(v, t, 2000)
    src_bvh = BVHTree.FromPolygons([tuple(x) for x in v], [tuple(x) for x in t])
    lo, hi, best = 0.04, 1.0, (1.0, 0.0, 0.0)
    for _ in range(6):
        mid = (lo + hi) / 2
        me = decimated(o, mid)
        dv, dt = world_tris(o, me)
        p95, mx = deviation(src_pts, src_bvh, dv, dt) if len(dt) else (1e9, 1e9)
        bpy.data.meshes.remove(me)
        if p95 <= p95_tol and mx <= max_tol:
            best, hi = (mid, p95, mx), mid
        else:
            lo = mid
    return best


objs = {c.name: [o for o in c.objects if o.type == "MESH" and not o.hide_render]
        for c in bpy.data.collections if not c.name.startswith("Replaced")}
plan, report = {}, {"lines": {}, "objects": {}}
for line, (cols, budget) in LINES.items():
    scales = (0.25, 0.5, 1.0, 1.5, 2.25, 3.375)
    for attempt, scale in enumerate(scales):
        total = 0
        for c in cols:
            p95_tol, max_tol = (TOL[c][0] * scale, TOL[c][1] * scale)
            for o in objs.get(c, []):
                n = tris(o.data)
                if n < 300 or TOL[c][0] == 0.0:
                    plan[o.name] = (1.0, 0.0, 0.0, n, n)
                    total += n
                    continue
                r, p95, mx = best_ratio(o, p95_tol, max_tol)
                est = int(round(n * r))
                plan[o.name] = (r, p95, mx, n, est)
                total += est
        report["lines"][line] = {"budget": budget, "estimate": total, "tolerance_scale": scale}
        if total <= budget or attempt == len(scales) - 1:
            break
for c, os_ in objs.items():
    for o in os_:
        if o.name not in plan:
            continue
        r, p95, mx, n, _ = plan[o.name]
        if r < 1.0:
            m = o.modifiers.new("budget", "DECIMATE")
            m.ratio = r
            bpy.context.view_layer.objects.active = o
            with bpy.context.temp_override(object=o, active_object=o):
                bpy.ops.object.modifier_apply(modifier=m.name)
            o.data.shade_smooth()
            with bpy.context.temp_override(object=o, active_object=o, selected_editable_objects=[o]):
                bpy.ops.object.shade_auto_smooth(angle=0.6109)
        report["objects"][o.name] = {"collection": c, "ratio": round(r, 3), "p95_mm": round(p95, 2), "max_mm": round(mx, 2),
                                     "tris_before": n, "tris_after": tris(o.data)}
for line, (cols, budget) in LINES.items():
    report["lines"][line]["after"] = sum(tris(o.data) for c in cols for o in objs.get(c, []))
report["total_after"] = sum(v["after"] for v in report["lines"].values())
bpy.ops.wm.save_as_mainfile(filepath=out_blend, compress=True)
json.dump(report, open(out_json, "w"), indent=1)
print("BUDGET", json.dumps(report["lines"]), "total", report["total_after"])
