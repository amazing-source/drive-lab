"""Dump every visible mesh of the master in world space (metres, Blender frame) to one .npz.

blender -b <dr458_master.blend> --factory-startup -P dump_mesh.py -- <out.npz> [collection ...]

Arrays: V (n,3) float32, F (m,3) int32 triangles, obj (m,) int32 object index per triangle,
names (k,) object names, cols (k,) collection names. Lets landmark and overlap analysis run in
plain numpy without reopening Blender.
"""
import sys

import bpy
import numpy as np

args = sys.argv[sys.argv.index("--") + 1:]
out, want = args[0], set(args[1:])
dg = bpy.context.evaluated_depsgraph_get()
Vs, Fs, Os, names, cols = [], [], [], [], []
base = 0
excluded = {lc.collection.name for lc in bpy.context.view_layer.layer_collection.children if lc.exclude}
for c in bpy.data.collections:
    if c.name.startswith("Replaced") or c.name in excluded or (want and c.name not in want):
        continue
    for o in c.objects:
        if o.type != "MESH" or o.hide_render:
            continue
        m = o.evaluated_get(dg).to_mesh()
        m.calc_loop_triangles()
        v = np.empty(len(m.vertices) * 3, np.float32)
        m.vertices.foreach_get("co", v)
        v = v.reshape(-1, 3)
        M = np.array(o.matrix_world)
        v = v @ M[:3, :3].T + M[:3, 3]
        t = np.empty(len(m.loop_triangles) * 3, np.int32)
        m.loop_triangles.foreach_get("vertices", t)
        Vs.append(v); Fs.append(t.reshape(-1, 3) + base); Os.append(np.full(len(t) // 3, len(names), np.int32))
        names.append(o.name); cols.append(c.name)
        base += len(v)
        o.evaluated_get(dg).to_mesh_clear()
np.savez_compressed(out, V=np.concatenate(Vs), F=np.concatenate(Fs), obj=np.concatenate(Os), names=np.array(names), cols=np.array(cols))
print("DUMP", out, base, "verts", sum(len(f) for f in Fs), "tris", len(names), "objects; excluded collections:", sorted(excluded))
