"""Delete listed faces of one object (a car_find_islands.py result), for the mesh's owner to run.

blender -b <file.blend> --factory-startup --python-exit-code 1 -P tools/blender/car_delete_faces.py -- <faces.json> --out <out.blend>

Refuses to run unless the object's face count equals the JSON's `mesh_faces` (indices from another
version of the mesh would delete the wrong faces). Loose vertices left behind are removed too.
"""
import json
import sys
from pathlib import Path

import bmesh
import bpy

args = sys.argv[sys.argv.index("--") + 1:]
spec = json.loads(Path(args[0]).read_text())
out = args[args.index("--out") + 1]
o = bpy.data.objects[spec["object"]]
n = len(o.data.polygons)
if n != spec["mesh_faces"]:
    sys.exit(f"DELETE FAIL {o.name} has {n} faces, the list was made on {spec['mesh_faces']}: "
             "re-run car_find_islands.py")
bm = bmesh.new()
bm.from_mesh(o.data)
bm.faces.ensure_lookup_table()
bmesh.ops.delete(bm, geom=[bm.faces[i] for i in spec["faces"]], context="FACES")
loose = [v for v in bm.verts if not v.link_faces]
bmesh.ops.delete(bm, geom=loose, context="VERTS")
bm.to_mesh(o.data)
bm.free()
print("DELETE", o.name, n, "->", len(o.data.polygons), "faces")
bpy.ops.wm.save_as_mainfile(filepath=out, relative_remap=False, compress=True)
