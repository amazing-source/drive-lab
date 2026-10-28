"""
Renders the door and the START flap through their swing, and saves a .blend with them rigged,
run headless by Blender:

    blender -b --factory-startup -P tools/blender/hero_car_door_render.py -- <svj_door.blend> <hinge.json> <door_selection.json> <out dir>

<svj_door.blend> and <door_selection.json> come from hero_car_door.py, <hinge.json> from
hero_car_door_hinge.py. The tagged faces are separated into objects (Door_<source>, StartFlap),
each parented to an Empty at its hinge whose local X is the hinge axis: turning an Empty about
its X by +angle opens it, as the game turns its weld. Saves <out dir>/svj_door_rig.blend and
Workbench renders (textured) of the door shut, half and fully open from the side, the front
three-quarter, above and the driver's seat; the opening from outside and from the driver's eye
with the door open; the flap shut and open. Workbench is used because it renders headless.
"""

import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

DOOR, FLAP = 1, 2
FLAP_DEGREES = 70.0

blend, hinge_path, selection_path, out = (Path(arg).resolve() for arg in sys.argv[sys.argv.index("--") + 1 :][:4])
out.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(blend))
scene = bpy.context.scene
hinge = json.loads(hinge_path.read_text())
selection = json.loads(selection_path.read_text())


def tags(obj):
    values = np.zeros(len(obj.data.polygons), dtype=np.int32)
    attr = obj.data.attributes.get("door_part")
    if attr:
        attr.data.foreach_get("value", values)
    return values


def hinge_empty(name, pivot, axis):
    x = Vector(axis).normalized()
    up = Vector((0, 0, 1)) if abs(x.z) < 0.99 else Vector((0, 1, 0))
    y = (up - x * up.dot(x)).normalized()
    z = x.cross(y)
    empty = bpy.data.objects.new(name, None)
    empty.empty_display_type = "ARROWS"
    empty.empty_display_size = 0.15
    empty.matrix_world = Matrix((x, y, z)).transposed().to_4x4()
    empty.matrix_world.translation = Vector(pivot)
    scene.collection.objects.link(empty)
    return empty


door_hinge = hinge_empty("DoorHinge", hinge["pivot"], hinge["axis"])
flap_hinge = hinge_empty("FlapHinge", selection["flapHinge"]["pivot"], selection["flapHinge"]["axis"])
bpy.context.view_layer.update()

# Separate the tagged faces in Edit Mode, which keeps the custom split normals.
for obj in [o for o in scene.objects if o.type == "MESH"]:
    values = tags(obj)
    for part, empty, prefix in ((DOOR, door_hinge, "Door_"), (FLAP, flap_hinge, "StartFlap")):
        if not (values == part).any():
            continue
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode="EDIT")
        bm = bmesh.from_edit_mesh(obj.data)
        layer = bm.faces.layers.int.get("door_part")
        for face in bm.faces:
            face.select_set(face[layer] == part)
        bmesh.update_edit_mesh(obj.data)
        bpy.ops.mesh.separate(type="SELECTED")
        bpy.ops.object.mode_set(mode="OBJECT")
        piece = next(o for o in bpy.context.selected_objects if o is not obj)
        piece.name = prefix + obj.name.split("_Geo")[0].replace("body:Kit1_", "") if part == DOOR else prefix
        world = piece.matrix_world.copy()
        piece.parent = empty
        piece.matrix_world = world
        values = tags(obj)
bpy.ops.wm.save_as_mainfile(filepath=str(out / "svj_door_rig.blend"), compress=True)

rest = {"door": door_hinge.matrix_world.copy(), "flap": flap_hinge.matrix_world.copy()}

# A reference for the game's hinge maths (tests/Hinge.spec.luau): the door's top rear corner, shut
# and turned open by Blender's own rotation.
corner = max(
    (o.matrix_world @ v.co for o in door_hinge.children for v in o.data.vertices), key=lambda p: p.y + p.z
)
turn = Matrix.Translation(Vector(hinge["pivot"])) @ Matrix.Rotation(
    math.radians(hinge["openDegrees"]), 4, Vector(hinge["axis"])
) @ Matrix.Translation(-Vector(hinge["pivot"]))
(out / "door_corner.json").write_text(
    json.dumps({"shut": [round(c, 5) for c in corner], "open": [round(c, 5) for c in turn @ corner]})
)


def pose(empty, key, degrees):
    empty.matrix_world = rest[key] @ Matrix.Rotation(math.radians(degrees), 4, "X")
    bpy.context.view_layer.update()


scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "TEXTURE"
scene.render.resolution_x = 1280
scene.render.resolution_y = 800


def shot(name, location, target, lens):
    data = bpy.data.cameras.new(name)
    data.lens = lens
    data.clip_start = 0.005
    camera = bpy.data.objects.new(name, data)
    scene.collection.objects.link(camera)
    camera.location = Vector(location)
    camera.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    scene.render.filepath = str(out / f"{name}.png")
    bpy.ops.render.render(write_still=True)


open_degrees = hinge["openDegrees"]
views = {
    "side": ((5.2, -0.3, 0.9), (0.9, -0.3, 0.75), 40),
    "front34": ((3.4, -3.6, 1.7), (0.85, -0.4, 0.75), 40),
    "above": ((1.6, -0.3, 3.6), (0.9, -0.3, 0.5), 40),
    "cabin": ((0.30, 0.15, 0.80), (0.95, -0.55, 0.55), 30),
}
for label, degrees in (("shut", 0.0), ("half", open_degrees / 2), ("open", open_degrees)):
    pose(door_hinge, "door", degrees)
    for view, (location, target, lens) in views.items():
        shot(f"door_{label}_{view}", location, target, lens)
pose(door_hinge, "door", open_degrees)
shot("opening_outside", (2.0, -0.2, 0.9), (0.82, -0.3, 0.2), 32)
shot("opening_sill_front", (1.5, 0.9, 0.7), (0.82, -0.7, 0.15), 30)
shot("opening_driver_eye", (0.38, -0.06, 0.70), (1.0, -0.35, 0.25), 28)
pose(door_hinge, "door", 0)
for label, degrees in (("shut", 0.0), ("open", FLAP_DEGREES)):
    pose(flap_hinge, "flap", degrees)
    shot(f"flap_{label}", (0.14, -0.20, 0.58), (0.0, -0.335, 0.445), 50)
    shot(f"flap_{label}_side", (0.20, -0.30, 0.50), (0.0, -0.34, 0.45), 55)
print("RENDERED", sorted(p.name for p in out.glob("*.png")))
