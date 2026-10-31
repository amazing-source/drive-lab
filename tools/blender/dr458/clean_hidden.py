"""Master clean-up, second version: remove what the race car does not show, cut faces no game
viewpoint sees, and resolve surfaces that would depth-fight in Roblox.

blender -b <dr458_master_v9_prelead.blend> --factory-startup -P tools/blender/dr458/clean_hidden.py -- <out.blend> <report.json>

1. Delete objects the race car does not have or that are always hidden: badges and emblems (the car
   is unbadged), the hood and engine-lid gas struts (inside, lids shut), the Forza door cards
   (replaced by the cockpit modeller's Door_L_Card / Door_R_Card).
2. Visibility cut, per face, for the objects most likely to be hidden (inner skin, road interior,
   engine bay, hood underside, front boot, engine-lid internals). A face is kept when a ray from any
   game viewpoint on its front side reaches its centre or a point near one of its corners. Roblox
   draws MeshParts single-sided, so a face met from behind neither counts as seen nor blocks the
   ray: the ray carries on through it. Glass and lamp lenses do not block rays. Viewpoints:
   - the cockpit eye over the camera's own range (Config/CarCamera EYE_RANGE: forward -0.15..+0.12,
     up -0.05..+0.15 m about the default eye), plus 6 cm either side;
   - on foot, close: two rings 0.5 and 1.5 m outside the body at 0.35, 1.0, 1.7 and 2.5 m high;
   - on foot, far: rings at 5 m, 0.6 and 1.6 m high, and one point overhead;
   - at the open driver's door (Door_L opens; Door_R never does): a grid outside the opening and two
     points in it, with the door's own objects removed from the occluders.
   Faces next to a kept face are kept too, so a cut never opens a hole at an edge.
1b. Cabin_InnerSkin ends at the cabin's rear window (y -0.83): behind it the copied body faces
   would double the engine lid's own parts, so its faces with centres behind that line go.
Depth fighting is resolved afterwards by tools/blender/dr458/zfix.py. Independent checks: tools/blender/dr458/zfight_scan.py,
tools/blender/dr458/render_ids.py + render_diff.py (seeded viewpoints, before against after), tools/assets/dr458/holes_check.py.
"""
import json
import math
import sys
import time

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

out_blend, out_json = sys.argv[sys.argv.index("--") + 1:][:2]
O = bpy.data.objects
T0 = time.time()
report = {"deleted_objects": [], "visibility": {}, "tris_before": {}, "tris_after": {}}


def log(*a):
    print(f"CLEAN {time.time() - T0:7.1f}s", *a, flush=True)


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def live():
    return [o for c in bpy.data.collections if not c.name.startswith("Replaced")
            for o in c.objects if o.type == "MESH" and not o.hide_render]


def collection_tris():
    return {c.name: sum(tris(o) for o in c.objects if o.type == "MESH")
            for c in bpy.data.collections if not c.name.startswith("Replaced")}


for o in live():
    if o.modifiers:
        log("WARNING modifiers ignored on", o.name, [m.type for m in o.modifiers])
report["tris_before"] = collection_tris()

# 1. Objects to delete.
for o in [o for o in live() if any(s in o.name for s in ("_emblem_", "badgeLF", "badgeRF", "_piston",
                                                           "doorcardLF", "doorcardRF", "engine_badge_"))]:
    report["deleted_objects"].append({"name": o.name, "tris": tris(o)})
    bpy.data.objects.remove(o, do_unlink=True)


# 1b. The inner skin stops at the cabin's rear window.
skin = O.get("Cabin_InnerSkin")
if skin:
    bm = bmesh.new()
    bm.from_mesh(skin.data)
    mw = skin.matrix_world
    behind = [f for f in bm.faces if (mw @ f.calc_center_median()).y > -0.83]
    report["inner_skin_behind_cabin_deleted"] = len(behind)
    bmesh.ops.delete(bm, geom=behind, context="FACES")
    bm.to_mesh(skin.data)
    skin.data.update()
    bm.free()


# 2. Visibility cut.
def is_transparent(o):
    return any(s in o.name for s in ("_glass", "_window_", "glassLHL", "glassRHL", "glassLTL", "glassRTL"))


def is_door_l(o):
    return any(s in o.name for s in ("doorLF_", "mirrorL_", "glassLF_", "Door_L"))


objs = [o for o in live() if not is_transparent(o)]


def build(objects):
    verts, polys, owner, base = [], [], [], 0
    for o in objects:
        mw = o.matrix_world
        verts.extend(mw @ v.co for v in o.data.vertices)
        for p in o.data.polygons:
            polys.append([i + base for i in p.vertices])
            owner.append((o.name, p.index))
        base += len(o.data.vertices)
    return BVHTree.FromPolygons(verts, polys), {key: k for k, key in enumerate(owner)}


bvh_all, gidx_all = build(objs)
bvh_door, gidx_door = build([o for o in objs if not is_door_l(o)])

EYE = Vector((0.36, -1.45, 0.98))  # default cockpit eye: left seat, a 1.80 m driver
views = []  # (point, door_open)
for dx in (-0.06, 0.0, 0.06):
    for fwd in (-0.15, 0.0, 0.12):
        for up in (-0.05, 0.05, 0.15):
            views.append((EYE + Vector((dx, -fwd, up)), False))  # forward is -y
CY, AX, AY = -1.48, 0.98, 2.15  # body footprint centre (y) and half-width / half-length, m
for off in (0.5, 1.5):
    for az in range(0, 360, 20):
        a = math.radians(az)
        for h in (0.35, 1.0, 1.7, 2.5):
            views.append((Vector(((AX + off) * math.cos(a), CY + (AY + off) * math.sin(a), h)), False))
for az in range(0, 360, 15):
    a = math.radians(az)
    for h in (0.6, 1.6):
        views.append((Vector((5.0 * math.cos(a), -1.4 + 6.5 * math.sin(a), h)), False))
views.append((Vector((0.0, -1.4, 6.0)), False))
for x in (1.1, 1.5, 2.0):
    for y in (-2.3, -1.8, -1.3, -0.9):
        for z in (0.5, 1.0, 1.5, 2.0):
            views.append((Vector((x, y, z)), True))
for y in (-1.9, -1.4):
    for z in (0.9, 1.3):
        views.append((Vector((0.95, y, z)), True))
report["viewpoints"] = len(views)


def reaches(v, q, me, bvh, gidx):
    """Single-sided ray from v to q: True when nothing front-facing is met before q."""
    d = q - v
    left = d.length + 0.002
    d.normalize()
    org = v
    for _ in range(24):
        loc, nrm, fi, dist = bvh.ray_cast(org, d, left)
        if loc is None:
            return True  # nothing in the way and q itself not hit (grazing): treat as seen
        if fi == me or (loc - q).length < 0.002:
            return True
        if nrm.dot(d) > 0:  # met from behind: culled in Roblox, the ray passes
            org = loc + d * 1e-4
            left -= dist + 1e-4
            if left <= 0:
                return True
            continue
        return False
    return False


TRIM = [o for o in objs if o.name == "Cabin_InnerSkin" or o.users_collection[0].name in ("Engine", "Cabin")
        or any(s in o.name for s in ("hooda_plastic", "boot_bump", "boot_rubber", "boot_smooth", "trunk_misc", "body_metal_"))]
log("visibility:", len(TRIM), "objects,", len(views), "viewpoints")
for o in TRIM:
    mw = o.matrix_world
    rot = mw.to_3x3()
    keep = set()
    for p in o.data.polygons:
        cen = mw @ p.center
        pts = [cen] + [cen.lerp(mw @ o.data.vertices[i].co, 0.8) for i in p.vertices[:3]]
        nw = (rot @ p.normal).normalized()
        hit = False
        for v, door in views:
            if nw.dot(v - cen) <= 0:
                continue
            bvh, gidx = (bvh_door, gidx_door) if door else (bvh_all, gidx_all)
            me = gidx.get((o.name, p.index), -1)
            for q in pts:
                if reaches(v, q, me, bvh, gidx):
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
    log(f"  {o.name[:50]:50s} {len(grown):6d} kept of {report['visibility'][o.name]['faces']}")
for o in [o for o in live() if len(o.data.polygons) == 0]:
    report["deleted_objects"].append({"name": o.name, "tris": 0, "why": "no face visible"})
    bpy.data.objects.remove(o, do_unlink=True)

report["tris_after"] = collection_tris()
report["total_before"] = sum(report["tris_before"].values())
report["total_after"] = sum(report["tris_after"].values())
report["seconds"] = round(time.time() - T0, 1)
bpy.ops.wm.save_as_mainfile(filepath=out_blend, compress=True)
with open(out_json, "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=1)
log("done", json.dumps({k: report[k] for k in ("tris_before", "tris_after", "total_before", "total_after")}))
log("deleted", len(report["deleted_objects"]), "objects; inner skin faces behind the cabin", report.get("inner_skin_behind_cabin_deleted"))
