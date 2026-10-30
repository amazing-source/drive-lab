"""Find raised lettering in a mesh: small connected islands inside a box, for the mesh's owner to delete.

blender -b <car.blend> --factory-startup -P tools/blender/car_find_islands.py -- <object> <out.json> <xmin,ymin,zmin,xmax,ymax,zmax>
        [--max-size 0.06] [--no-weld] [--render <out.png> --view down]

Islands are face groups connected through shared vertices welded by position (1e-5 m), so a
letter split at UV seams stays one island; --no-weld uses the mesh's own topology instead. An island is lettering when its whole bounding box lies
inside the given world box and its largest side is under --max-size metres. Writes the face indices
(of the object's mesh as saved) and each island's box. With --render, the islands are drawn red on
grey from one of the named cameras.
"""
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
name, out = args[0], Path(args[1])
box = [float(v) for v in args[2].split(",")]
max_size = float(args[args.index("--max-size") + 1]) if "--max-size" in args else 0.06
o = bpy.data.objects[name]
bm = bmesh.new()
bm.from_mesh(o.data)
bm.transform(o.matrix_world)
bm.faces.ensure_lookup_table()
key = {v.index: (v.index,) if "--no-weld" in args else tuple(round(c / 1e-5) for c in v.co) for v in bm.verts}
by_pos = {}
for v in bm.verts:
    by_pos.setdefault(key[v.index], []).append(v)
seen, islands = set(), []
for f in bm.faces:
    if f.index in seen:
        continue
    stack, comp = [f], []
    seen.add(f.index)
    while stack:
        g = stack.pop()
        comp.append(g.index)
        for v in g.verts:
            for w in by_pos[key[v.index]]:
                for h in w.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
    islands.append(comp)
hits = []
for comp in islands:
    pts = [v.co for i in comp for v in bm.faces[i].verts]
    lo = [min(p[k] for p in pts) for k in range(3)]
    hi = [max(p[k] for p in pts) for k in range(3)]
    inside = all(box[k] <= lo[k] and hi[k] <= box[k + 3] for k in range(3))
    if inside and max(hi[k] - lo[k] for k in range(3)) < max_size:
        hits.append({"faces": sorted(comp), "min": [round(x, 4) for x in lo], "max": [round(x, 4) for x in hi]})
faces = sorted(i for h in hits for i in h["faces"])
out.write_text(json.dumps({"object": name, "mesh_faces": len(o.data.polygons), "box": box, "max_size_m": max_size, "islands": len(hits),
                           "faces": faces, "island_boxes": [{k: h[k] for k in ("min", "max")} for h in hits]},
                          indent=1))
print("LETTERING", name, "islands", len(islands), "-> lettering islands", len(hits), "faces", len(faces), "->", out)
if "--render" in args:
    VIEWS = {"down": ((0.36, -1.45, 1.00), (0.20, -2.25, 0.20), 70),
             "across": ((-0.62, -1.55, 0.98), (0.30, -2.05, 0.62), 62),
             "close": ((-0.20, -1.70, 0.95), (-0.40, -2.10, 0.72), 40)}
    view = args[args.index("--view") + 1] if "--view" in args else "down"
    me = o.data
    red = bpy.data.materials.new("LetteringHit")
    red.diffuse_color = (1, 0.05, 0.05, 1)
    me.materials.append(red)
    idx = len(me.materials) - 1
    hitset = set(faces)
    for p in me.polygons:
        if p.index in hitset:
            p.material_index = idx
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "MATERIAL"
    sc.display.shading.show_backface_culling = True
    for m in bpy.data.materials:
        if m is not red:
            m.diffuse_color = (0.35, 0.35, 0.35, 1)
    for ob in sc.objects:
        if ob.type == "MESH" and any(s in ob.name for s in ("_glass", "_window_", "glassL", "glassR")):
            ob.hide_render = True
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720
    cam = bpy.data.objects.new("C", bpy.data.cameras.new("C"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    loc, tgt, fov = VIEWS[view]
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle_y = math.radians(fov)
    cam.data.clip_start = 0.02
    sc.render.filepath = args[args.index("--render") + 1]
    bpy.ops.render.render(write_still=True)
    print("LETTERING render", sc.render.filepath)
