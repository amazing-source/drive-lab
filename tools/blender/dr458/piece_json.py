"""Export named objects of a .blend as triangle lists in Roblox axes, for an edit-mode Studio import
through EditableMesh (studio_import.luau) with no upload.

blender -b <file.blend> --factory-startup -P piece_json.py -- <out.json> <object> [<object> ...]

Per object: "p" corner positions in metres, Roblox axes (x = -blender x, y = blender z, z = blender
y: the car's right is +X, up is +Y, the nose toward -Z), "n" corner normals, "uv" corner UVs (V
flipped, Roblox's origin is top-left), three corners per triangle, plus the object's colour and the
triangle count. Positions keep the master's frame (rear-axle midpoint on the ground), so pieces land
where they sit on the car when placed at one shared origin.
"""
import json
import sys

import bpy

args = sys.argv[sys.argv.index("--") + 1:]
out, names = args[0], args[1:]
dg = bpy.context.evaluated_depsgraph_get()
res = {}
for n in names:
    o = bpy.data.objects[n]
    me = o.evaluated_get(dg).to_mesh()
    me.calc_loop_triangles()
    mw = o.matrix_world
    rot = mw.to_3x3().inverted().transposed()
    uvl = me.uv_layers.active.data if me.uv_layers.active else None
    p, nn, uv = [], [], []
    for lt in me.loop_triangles:
        for li, vi in zip(lt.loops, lt.vertices):
            w = mw @ me.vertices[vi].co
            p += [round(-w.x, 5), round(w.z, 5), round(w.y, 5)]
            nv = (rot @ me.corner_normals[li].vector).normalized()
            nn += [round(-nv.x, 4), round(nv.z, 4), round(nv.y, 4)]
            if uvl:
                u, v = uvl[li].uv
                uv += [round(u, 5), round(1 - v, 5)]
    col = list(o.color[:3])
    if me.materials and me.materials[0] and me.materials[0].use_nodes:
        b = me.materials[0].node_tree.nodes.get("Principled BSDF")
        if b:
            col = list(b.inputs["Base Color"].default_value[:3])
    res[n] = {"p": p, "n": nn, "uv": uv, "colour_linear": [round(c, 4) for c in col], "triangles": len(me.loop_triangles)}
    o.evaluated_get(dg).to_mesh_clear()
json.dump(res, open(out, "w"))
print("PIECES", out, {k: v["triangles"] for k, v in res.items()})
