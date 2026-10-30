"""Master clean-up: remove what the race car does not show, cut faces nobody can see, and resolve
surfaces that would depth-fight in Roblox.

blender -b <dr458_master.blend> --factory-startup -P tools/blender/dr458/clean_hidden.py -- <out.blend> <report.json>

1. Delete objects the race car does not have or that are always hidden: the road car's badges and
   emblems (the car is unbadged), the hood and engine-lid gas struts (inside, lid shut), and the
   Forza door cards (replaced by the cockpit modeller's Door_L_Card / Door_R_Card).
2. Visibility cut, per face, for the objects most likely to be hidden (inner skin, road interior,
   engine bay, hood underside, front boot, engine-lid internals): a face is kept when a ray from
   any viewpoint on its front side reaches its centre or a point near one of its corners before
   anything else (MeshParts are single-sided, so a face seen only from behind is never drawn). The
   viewpoints are the driver's eye region and a ring of exterior points; glass and lamp lenses do
   not block rays. Faces next to a kept face are kept too, so a cut never opens a hole at an edge.
3. Depth fighting (two different meshes within 1.5 mm, facing the same way): per object pair, the
   object whose coincident share of its own vertices is larger is the overlay; faces of the other
   one lying entirely within 2 mm of the overlay are deleted, and the overlay's coincident vertices
   are lifted 2.5 mm along their normals so what is left is at least 2 mm apart.
Independent checks run afterwards from other scripts: tools/blender/dr458/zfight_scan.py and
tools/assets/dr458/render_diff.py (renders from viewpoints not used here, before against after).
"""
import json
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

out_blend, out_json = sys.argv[sys.argv.index("--") + 1:][:2]
O = bpy.data.objects
report = {"deleted_objects": [], "visibility": {}, "zfight": [], "tris_before": {}, "tris_after": {}}


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def live():
    return [o for c in bpy.data.collections if not c.name.startswith("Replaced")
            for o in c.objects if o.type == "MESH" and not o.hide_render]


def collection_tris():
    return {c.name: sum(tris(o) for o in c.objects if o.type == "MESH")
            for c in bpy.data.collections if not c.name.startswith("Replaced")}


report["tris_before"] = collection_tris()

# 1. Objects to delete.
for o in [o for o in live() if any(s in o.name for s in ("_emblem_", "badgeLF", "badgeRF", "_piston",
                                                           "doorcardLF", "doorcardRF", "engine_badge_"))]:
    report["deleted_objects"].append({"name": o.name, "tris": tris(o)})
    bpy.data.objects.remove(o, do_unlink=True)


# 2. Visibility cut.
def is_transparent(o):
    return any(s in o.name for s in ("_glass", "_window_", "glassLHL", "glassRHL", "glassLTL", "glassRTL"))


objs = [o for o in live() if not is_transparent(o)]
verts, polys, owner, base = [], [], [], 0
for o in objs:
    mw = o.matrix_world
    verts.extend(mw @ v.co for v in o.data.vertices)
    for p in o.data.polygons:
        polys.append([i + base for i in p.vertices])
        owner.append((o.name, p.index))
    base += len(o.data.vertices)
bvh = BVHTree.FromPolygons(verts, polys)
gidx = {key: k for k, key in enumerate(owner)}
eye = Vector((0.36, -1.45, 0.98))  # driver's eye region: left seat, a 1.80 m driver
views = [eye + Vector((dx, 0.0, dz)) for dx, dz in ((-0.12, 0.0), (0.12, 0.0), (0.0, 0.06), (0.0, -0.06), (0.0, 0.0))]
for az in range(0, 360, 15):
    for h, r in ((0.6, 5.0), (1.6, 5.0)):
        a = np.radians(az)
        views.append(Vector((r * np.cos(a), -1.4 + r * 1.3 * np.sin(a), h)))
views.append(Vector((0.0, -1.4, 6.0)))
TRIM = [o for o in objs if o.name == "Cabin_InnerSkin" or o.users_collection[0].name in ("Engine", "Cabin")
        or any(s in o.name for s in ("hooda_plastic", "boot_bump", "boot_rubber", "boot_smooth", "trunk_misc", "body_metal_"))]
for o in TRIM:
    mw = o.matrix_world
    keep = set()
    for p in o.data.polygons:
        cen = mw @ p.center
        pts = [cen] + [cen.lerp(mw @ o.data.vertices[i].co, 0.8) for i in p.vertices[:3]]
        nw = (mw.to_3x3() @ p.normal).normalized()
        me = gidx[(o.name, p.index)]
        hit = False
        for v in views:
            if nw.dot(v - cen) <= 0:
                continue  # MeshParts are single-sided: a face seen only from behind is never drawn
            for q in pts:
                d = q - v
                loc, _n, fi, _dist = bvh.ray_cast(v, d.normalized(), d.length + 0.002)
                if fi == me or (loc is not None and (loc - q).length < 0.002):
                    hit = True
                    break
            if hit:
                break
        if hit:
            keep.add(p.index)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.faces.ensure_lookup_table()
    grown = set(keep)
    for i in keep:
        for e in bm.faces[i].edges:
            grown.update(f.index for f in e.link_faces)
    gone = [f for f in bm.faces if f.index not in grown]
    report["visibility"][o.name] = {"faces": len(bm.faces), "kept": len(grown), "removed": len(gone)}
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    bm.to_mesh(o.data)
    o.data.update()
    bm.free()
for o in [o for o in live() if len(o.data.polygons) == 0]:
    report["deleted_objects"].append({"name": o.name, "tris": 0, "why": "no face visible"})
    bpy.data.objects.remove(o, do_unlink=True)

# 3. Depth fighting.
DIST, COS = 0.0015, float(np.cos(np.radians(25)))


def tri_bvh(o):
    mw = o.matrix_world
    return BVHTree.FromPolygons([mw @ v.co for v in o.data.vertices], [list(p.vertices) for p in o.data.polygons])


cur = live()
trees = {o.name: tri_bvh(o) for o in cur}
boxes = {}
for o in cur:
    P = np.array([tuple(o.matrix_world @ v.co) for v in o.data.vertices])
    boxes[o.name] = (P.min(0) - 0.003, P.max(0) + 0.003)


def overlap(a, b):
    return bool(np.all(boxes[a][0] <= boxes[b][1]) and np.all(boxes[b][0] <= boxes[a][1]))


def coincident_verts(o, other):
    mw, rot = o.matrix_world, o.matrix_world.to_3x3()
    t = trees[other.name]
    res = []
    for v in o.data.vertices:
        loc, nrm, _i, _d = t.find_nearest(mw @ v.co, DIST + 0.0005)
        if loc is not None and (rot @ v.normal).normalized().dot(nrm) >= COS:
            res.append(v.index)
    return res


names = [o.name for o in cur]
for i, a in enumerate(names):
    for b in names[i + 1:]:
        if a not in O or b not in O or not overlap(a, b):
            continue
        A, B = O[a], O[b]
        ca, cb = coincident_verts(A, B), coincident_verts(B, A)
        if len(ca) < 3 and len(cb) < 3:
            continue
        sa = len(ca) / max(1, len(A.data.vertices))
        sb = len(cb) / max(1, len(B.data.vertices))
        top, under = (A, B) if sa >= sb else (B, A)
        tt = trees[top.name]
        bm = bmesh.new()
        bm.from_mesh(under.data)
        mw = under.matrix_world
        gone = [f for f in bm.faces
                if all(tt.find_nearest(p, 0.002)[0] is not None
                       for p in [mw @ f.calc_center_median()] + [mw @ v.co for v in f.verts])]
        bmesh.ops.delete(bm, geom=gone, context="FACES")
        bm.to_mesh(under.data)
        under.data.update()
        bm.free()
        trees[under.name] = tri_bvh(under)
        lift = coincident_verts(top, under) if len(under.data.polygons) else []
        for vi in lift:
            v = top.data.vertices[vi]
            v.co += v.normal * 0.0025
        top.data.update()
        trees[top.name] = tri_bvh(top)
        report["zfight"].append({"overlay": top.name, "under": under.name,
                                 "under_faces_deleted": len(gone), "overlay_verts_lifted": len(lift)})
for o in [o for o in live() if len(o.data.polygons) == 0]:
    report["deleted_objects"].append({"name": o.name, "tris": 0, "why": "empty after depth-fight cut"})
    bpy.data.objects.remove(o, do_unlink=True)

report["tris_after"] = collection_tris()
report["total_before"] = sum(report["tris_before"].values())
report["total_after"] = sum(report["tris_after"].values())
bpy.ops.wm.save_as_mainfile(filepath=out_blend, compress=True)
with open(out_json, "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=1)
print("CLEAN", json.dumps({k: report[k] for k in ("tris_before", "tris_after", "total_before", "total_after")}))
print("CLEAN deleted", len(report["deleted_objects"]), "objects; depth-fight pairs treated", len(report["zfight"]))
