"""
Splits a car export's single light mesh into four, front-left, front-right, rear-left and
rear-right, so the game can drive each cluster on its own (brake lights brighten without the
headlights, an indicator blinks on one side). Faces go by their centre: front or rear of the
car's middle, left or right of its centre line. Positions and UVs are kept, so each piece
imports where it was and takes the same SurfaceAppearance.

    blender -b --factory-startup -P tools/blender/split_lights.py -- <car.glb> <light object> <out dir>

Axes: the export is Roblox (x, y, z) = Blender (-x, z, y); Roblox's front is -z (Blender -y)
and its right is +x (Blender -x). Writes light_<FrontLeft|FrontRight|RearLeft|RearRight>.glb
and lights.json with each piece's triangle count and centre in Roblox axes.
"""

import json
import os
import sys

import bmesh
import bpy


def main(car, name, out):
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=car)
    source = next(o for o in bpy.context.scene.objects if o.type == "MESH" and o.name.startswith(name))
    # Bake the object's transform into its vertices so every piece exports in place.
    source.data.transform(source.matrix_world)
    source.matrix_world.identity()
    report = {}
    for piece, front, right in (
        ("FrontLeft", True, False),
        ("FrontRight", True, True),
        ("RearLeft", False, False),
        ("RearRight", False, True),
    ):
        mesh = bmesh.new()
        mesh.from_mesh(source.data)
        doomed = []
        for face in mesh.faces:
            centre = face.calc_center_median()
            is_front = centre.y < 0
            is_right = centre.x < 0
            if is_front != front or is_right != right:
                doomed.append(face)
        bmesh.ops.delete(mesh, geom=doomed, context="FACES")
        data = bpy.data.meshes.new(f"Light_{piece}")
        mesh.to_mesh(data)
        mesh.free()
        obj = bpy.data.objects.new(f"Light_{piece}", data)
        bpy.context.collection.objects.link(obj)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.ops.export_scene.gltf(
            filepath=os.path.join(out, f"light_{piece}.glb"),
            use_selection=True,
            export_tangents=True,
            export_materials="NONE",
        )
        verts = [v.co for v in data.vertices]
        centre = [sum(v[i] for v in verts) / len(verts) for i in range(3)]
        report[piece] = {
            "triangles": sum(len(p.vertices) - 2 for p in data.polygons),
            "centreRoblox": [round(-centre[0], 4), round(centre[2], 4), round(centre[1], 4)],
        }
        bpy.data.objects.remove(obj)
    total = sum(len(p.vertices) - 2 for p in source.data.polygons)
    report["sourceTriangles"] = total
    json.dump(report, open(os.path.join(out, "lights.json"), "w"), indent=1)
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main(*sys.argv[sys.argv.index("--") + 1 :][:3])
