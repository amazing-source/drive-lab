"""
Exports the hero-car import pilot, run headless by Blender: one wheel and one body panel of the
debadged car, to check the whole Blender -> Open Cloud -> Studio chain before the full car.

    blender --background --python tools/blender/hero_car_pilot.py -- <car.blend> <out dir>

The .blend is the debadged car in metres with its nose along -Y and Z up (see the Drive Lab
research notes). The pilot:

1. Turns the car so its nose points along +Y, which glTF's Y-up export makes Roblox's -Z, the
   direction an unrotated CFrame looks along. Puts the ground under the tyres at z = 0 and the
   midpoint between the axles at the origin.
2. Scales metres to studs (1 stud = 0.28 m, Roblox's documented convention); one glTF unit
   imports as one stud, as the traffic cars already showed.
3. Joins the front-left wheel's pieces into one mesh, Wheel_FL, with its origin at the wheel's
   centre, and keeps the left half of the paint shell as Body_Paint_L (under the 20,000-triangle
   per-mesh limit).
4. Exports pilot.glb with its textures, and manifest.json with each part's triangle count,
   origin and size in Roblox space (studs, X right, Y up, -Z forward) so Studio can be checked
   against it.
"""

import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

STUDS_PER_METRE = 1 / 0.28
PER_MESH_LIMIT = 20000
WHEELS = {"FL": "3DWheel Front L", "FR": "3DWheel Front R", "RL": "3DWheel Rear L", "RR": "3DWheel Rear R"}

blend, out = (Path(arg) for arg in sys.argv[sys.argv.index("--") + 1 :][:2])
out.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(blend))


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def bounds(objs):
    # From the vertices themselves: Object.bound_box is cached and goes stale after a
    # Mesh.transform() until the depsgraph updates, which once put the rear wheels at the front.
    points = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    return low, high


def triangles(obj) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def to_roblox(v: Vector) -> list:
    # glTF Y-up export: Blender (x, y, z) becomes (x, z, -y), imported as studs.
    return [round(v.x, 4), round(v.z, 4), round(-v.y, 4)]


def select_only(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def ancestors(obj):
    parent = obj.parent
    while parent is not None:
        yield parent
        parent = parent.parent


# Which pieces belong to each wheel has to be read before the hierarchy is flattened.
wheel_parts = {
    key: [o for o in meshes() if any(p.name == name for p in ancestors(o))] for key, name in WHEELS.items()
}

select_only(meshes())
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# Nose to +Y, then ground at z = 0, centreline at x = 0, axle midpoint at y = 0, then studs.
turn = Matrix.Rotation(math.pi, 4, "Z")
for obj in meshes():
    obj.data.transform(turn)
low, high = bounds(meshes())
wheel_centres = {}
for key, parts in wheel_parts.items():
    wlow, whigh = bounds(parts)
    wheel_centres[key] = (wlow + whigh) / 2
axle_mid_y = (wheel_centres["FL"].y + wheel_centres["FR"].y + wheel_centres["RL"].y + wheel_centres["RR"].y) / 4
shift = Matrix.Translation(Vector((-(low.x + high.x) / 2, -axle_mid_y, -low.z)))
scale = Matrix.Scale(STUDS_PER_METRE, 4)
for obj in meshes():
    obj.data.transform(scale @ shift)
for key in wheel_centres:
    wheel_centres[key] = scale @ shift @ wheel_centres[key]


def set_origin_to_centre(obj):
    olow, ohigh = bounds([obj])
    centre = (olow + ohigh) / 2
    obj.data.transform(Matrix.Translation(-centre))
    obj.location = centre


# Wheel_FL: every piece of the front-left wheel joined into one mesh.
select_only(wheel_parts["FL"])
bpy.ops.object.join()
wheel = bpy.context.view_layer.objects.active
wheel.name = "Wheel_FL"
set_origin_to_centre(wheel)

# Body_Paint_L: the paint shell's left half (the car's left is -X once the nose points +Y).
paint = next(o for o in meshes() if o.name.startswith("body:Kit1_Paint_Geo"))
panel = paint.copy()
panel.data = paint.data.copy()
panel.name = "Body_Paint_L"
bpy.context.scene.collection.objects.link(panel)
bm = bmesh.new()
bm.from_mesh(panel.data)
bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().x > 0], context="FACES")
bm.to_mesh(panel.data)
bm.free()
set_origin_to_centre(panel)

parts = [wheel, panel]
manifest = {"studsPerMetre": STUDS_PER_METRE, "parts": [], "wheelCentres": {}}
for obj in parts:
    count = triangles(obj)
    olow, ohigh = bounds([obj])
    size = ohigh - olow
    manifest["parts"].append(
        {
            "name": obj.name,
            "triangles": count,
            "underLimit": count <= PER_MESH_LIMIT,
            "origin": to_roblox(obj.location),
            "size": [round(size.x, 4), round(size.z, 4), round(size.y, 4)],
            "materials": [slot.material.name for slot in obj.material_slots if slot.material],
        }
    )
for key, centre in wheel_centres.items():
    manifest["wheelCentres"][key] = to_roblox(centre)
car_low, car_high = bounds([o for o in meshes() if o not in parts])
car_size = car_high - car_low
manifest["carSize"] = [round(car_size.x, 3), round(car_size.z, 3), round(car_size.y, 3)]

select_only(parts)
bpy.ops.export_scene.gltf(
    filepath=str(out / "pilot.glb"), export_format="GLB", use_selection=True, export_yup=True, export_apply=True
)
(out / "manifest.json").write_text(json.dumps(manifest, indent=1))
print(json.dumps(manifest, indent=1))
