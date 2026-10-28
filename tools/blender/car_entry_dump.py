"""
Dumps a car .blend's meshes for the car-entry pipeline (tools/anim/car_entry_prep.py): every mesh
object's evaluated triangles in world space (Blender metres), its name, and whether it hangs under
the door's hinge empty, so the door can be posed on its own.

  blender -b <svj_door_rig.blend> -P car_entry_dump.py -- <out.npz> [--hinge DoorHinge]
"""
import sys

import bpy
import numpy as np


def under(obj, name):
    parent = obj.parent
    while parent is not None:
        if parent.name == name:
            return True
        parent = parent.parent
    return False


def main(argv):
    out = argv[0]
    hinge = argv[argv.index("--hinge") + 1] if "--hinge" in argv else "DoorHinge"
    depsgraph = bpy.context.evaluated_depsgraph_get()
    data, names, doors = {}, [], []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or obj.hide_render:
            continue
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        if not mesh.loop_triangles:
            evaluated.to_mesh_clear()
            continue
        verts = np.empty(len(mesh.vertices) * 3, dtype=np.float64)
        mesh.vertices.foreach_get("co", verts)
        verts = verts.reshape(-1, 3)
        m = np.array(obj.matrix_world)
        verts = verts @ m[:3, :3].T + m[:3, 3]
        tris = np.empty(len(mesh.loop_triangles) * 3, dtype=np.int64)
        mesh.loop_triangles.foreach_get("vertices", tris)
        evaluated.to_mesh_clear()
        k = len(names)
        data[f"v{k}"] = verts.astype(np.float32)
        data[f"f{k}"] = tris.reshape(-1, 3).astype(np.int32)
        names.append(obj.name)
        doors.append(under(obj, hinge))
    data["names"] = np.array(names)
    data["door"] = np.array(doors)
    empty = bpy.data.objects.get(hinge)
    if empty is not None:
        data["hinge_matrix"] = np.array(empty.matrix_world)
    np.savez_compressed(out, **data)
    print(f"{len(names)} meshes, {sum(doors)} under {hinge} -> {out}")


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1 :])
