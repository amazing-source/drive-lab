"""Inventory of a master: every rendered mesh object outside the Replaced_* collections, with its
collection, triangle count, world bounding box (m) and materials.

blender -b <master.blend> --factory-startup -P tools/blender/dr458/inventory.py -- <out.json>
"""
import json
import sys

import bpy
import numpy as np

out = sys.argv[sys.argv.index("--") + 1]
rows = []
for c in bpy.data.collections:
    if c.name.startswith("Replaced"):
        continue
    for o in c.objects:
        if o.type != "MESH" or o.hide_render:
            continue
        me = o.data
        v = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", v)
        M = np.array(o.matrix_world)
        v = v.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3] if len(v) else np.zeros((1, 3))
        rows.append({"name": o.name, "col": c.name, "tris": sum(len(p.vertices) - 2 for p in me.polygons),
                     "verts": len(me.vertices), "min": [round(x, 4) for x in v.min(0)],
                     "max": [round(x, 4) for x in v.max(0)],
                     "materials": [s.material.name if s.material else None for s in o.material_slots]})
by_col = {}
for r in rows:
    by_col[r["col"]] = by_col.get(r["col"], 0) + r["tris"]
json.dump({"file": bpy.data.filepath, "objects": rows, "tris_by_collection": by_col,
           "tris_total": sum(by_col.values())}, open(out, "w"), indent=1)
print("INVENTORY", len(rows), "objects", sum(by_col.values()), "tris", by_col)
