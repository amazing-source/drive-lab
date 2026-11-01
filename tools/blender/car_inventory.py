"""Read-only inventory of a car blend: objects, their kn5 node chain, flags, materials and images. Never saves.

blender -b <file.blend> --factory-startup --python-exit-code 1 -P car_inventory.py -- <out.json>
"""
import json
import sys

import bpy

out = sys.argv[sys.argv.index("--") + 1:][0]


def chain(o):
    r = []
    while o is not None:
        r.append(o.get("kn5_name", o.name))
        o = o.parent
    return r


objs = []
for o in bpy.data.objects:
    row = {"name": o.name, "type": o.type, "kn5": o.get("kn5_name"), "chain": chain(o)[1:], "hide_render": o.hide_render,
           "hide_viewport": o.hide_viewport, "hidden_get": o.hide_get() if o.name in bpy.context.view_layer.objects else None,
           "collections": [c.name for c in o.users_collection], "props": sorted(k for k in o.keys() if not k.startswith("_"))}
    if o.type == "MESH":
        me = o.data
        me.calc_loop_triangles()
        per = {}
        for t in me.loop_triangles:
            per[t.material_index] = per.get(t.material_index, 0) + 1
        row["tris"] = len(me.loop_triangles)
        row["materials"] = {(o.material_slots[i].material.name if i < len(o.material_slots) and o.material_slots[i].material else "none"): n
                            for i, n in per.items()}
        row["uv_layers"] = len(me.uv_layers)
        row["modifiers"] = [m.type for m in o.modifiers]
    objs.append(row)
mats = {}
for m in bpy.data.materials:
    imgs = []
    if m.node_tree:
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image:
                imgs.append({"node": n.name, "label": n.label, "image": n.image.name, "path": n.image.filepath,
                             "size": list(n.image.size), "colorspace": n.image.colorspace_settings.name,
                             "to": [l.to_socket.name + "@" + l.to_node.name for o_ in n.outputs for l in o_.links]})
    mats[m.name] = {"users": m.users, "props": {k: (m[k] if isinstance(m[k], (int, float, str)) else str(m[k])[:200]) for k in m.keys() if not k.startswith("_")},
                    "images": imgs}
json.dump({"file": bpy.data.filepath, "objects": objs, "materials": mats,
           "collections": {c.name: [x.name for x in c.objects][:5] + ([f"... {len(c.objects)}"] if len(c.objects) > 5 else []) for c in bpy.data.collections}},
          open(out, "w"), indent=1)
print("INVENTORY", len(objs), "objects,", sum(1 for o in objs if o["type"] == "MESH"), "meshes,", len(mats), "materials ->", out)
