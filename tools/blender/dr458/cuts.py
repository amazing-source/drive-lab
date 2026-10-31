"""Remove what the race car does not have from the road interior, by boxes, and put the driver's door
glass in the Doors collection.

blender -b <master.blend> --factory-startup -P tools/blender/dr458/cuts.py -- <cuts.json> <out.blend> <report.json> [--break]

--break leaves one face per cut behind, to show the verification failing.

cuts.json: [{"name", "why", "box": [[x0, y0, z0], [x1, y1, z1]], "collections": [...],
"objects": [name parts] (optional)}]. A face goes when its centre lies inside the box and its object
is in one of the collections (and matches a name part, when given). Verified here, from the mesh
itself: after the cut no face of a listed object has its centre in a box, and every object's face
count outside the boxes is what it was before.
"""
import json
import sys

import bmesh
import bpy
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
cuts_path, out_blend, out_json = argv[:3]
BREAK = "--break" in argv
cuts = json.load(open(cuts_path))


def centres(o):
    me = o.data
    c = np.empty(len(me.polygons) * 3)
    me.polygons.foreach_get("center", c)
    M = np.array(o.matrix_world)
    return c.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3]


def inside(c, box):
    lo, hi = np.array(box[0]), np.array(box[1])
    return np.all((c >= lo) & (c <= hi), axis=1)


def targets(cut):
    return [o for o in bpy.data.objects if o.type == "MESH" and o.users_collection
            and o.users_collection[0].name in cut["collections"]
            and (not cut.get("objects") or any(s in o.name for s in cut["objects"]))]


def outside_count(o):
    if not len(o.data.polygons):
        return 0
    c = centres(o)
    m = np.zeros(len(c), bool)
    for cut in cuts:
        if o in targets(cut):
            m |= inside(c, cut["box"])
    return int((~m).sum())


touched = {o.name for cut in cuts for o in targets(cut)}
before_out = {n: outside_count(bpy.data.objects[n]) for n in touched}
report = {"cuts": [], "verify": {}}
for cut in cuts:
    row = {"name": cut["name"], "why": cut["why"], "box": cut["box"], "deleted": {}}
    for o in targets(cut):
        if not len(o.data.polygons):
            continue
        m = inside(centres(o), cut["box"])
        if not m.any():
            continue
        if BREAK:
            m[np.flatnonzero(m)[0]] = False
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.faces[i] for i in np.flatnonzero(m)], context="FACES")
        bm.to_mesh(o.data)
        o.data.update()
        bm.free()
        row["deleted"][o.name] = int(m.sum())
    report["cuts"].append(row)
problems = []
for n in touched:
    o = bpy.data.objects[n]
    left_in = sum(int(inside(centres(o), cut["box"]).sum()) for cut in cuts if o in targets(cut)) if len(o.data.polygons) else 0
    if left_in:
        problems.append(f"{n}: {left_in} faces still inside a box")
    if outside_count(o) != before_out[n]:
        problems.append(f"{n}: faces outside the boxes {before_out[n]} -> {outside_count(o)}")
emptied = [o.name for o in bpy.data.objects if o.name in touched and not len(o.data.polygons)]
for n in emptied:
    bpy.data.objects.remove(bpy.data.objects[n], do_unlink=True)
report["emptied_objects_removed"] = emptied
g = bpy.data.objects.get("fer_f142_10_cockpit_s_glassLF_window_")
doors = bpy.data.collections.get("Doors")
if g and doors and doors not in g.users_collection:
    for c in list(g.users_collection):
        c.objects.unlink(g)
    doors.objects.link(g)
    report["moved"] = {g.name: "Glass -> Doors"}
report["verify"] = {"verdict": "FAIL" if problems else "PASS", "problems": problems}
bpy.ops.wm.save_as_mainfile(filepath=out_blend, compress=True)
json.dump(report, open(out_json, "w"), indent=1)
for r in report["cuts"]:
    print("CUTS", r["name"], sum(r["deleted"].values()), "faces", r["deleted"])
print("CUTS verify", report["verify"]["verdict"], problems[:10], "moved", report.get("moved"))
