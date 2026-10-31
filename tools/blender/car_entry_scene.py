"""
The car-entry authoring scene: the R6 rig of r6_rig.py, the car and its driver's door around it,
one continuous timeline per direction (entry, exit), the door keyed on the same timeline as the
hand that moves it.

Everything sits in r6_rig's RobloxSpace (Roblox axes, scale-1 R6). The car is placed by
tools/anim/car_entry_prep.py: the world is divided by the driver's scale about the door mark's
standing root, which sits where r6_rig puts a standing root, (0, 3, 0) facing -Z. So keys are
authored at scale 1 against a car 1/scale bigger, which is the same picture as the scaled
character beside the real car.

  blender -b --factory-startup -P car_entry_scene.py -- build <keys.json> <scene.npz> <out.blend>
  blender -b <out.blend> -P car_entry_scene.py -- bake <out.json> [substeps]
  blender -b <out.blend> -P car_entry_scene.py -- render <out_dir> [--cams side,game,top,eye]
      [--stretch 4] [--res 480] [--from F] [--to F] [--step N]

Cameras: side, game, top (placed by car_entry_prep.py), eye (rides the head, first person),
entry and leave (EntryView's third person: a fixed offset from the head, looking at it), door (a
standing eye at the door mark looking into the opening).

The keys file is r6_rig's format plus "door": [{"frame", "value", "interp"?}] (openness 0 shut to
1 open) and "clips": [{"name", "start", "end"}].
"""
import argparse
import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import r6_rig  # noqa: E402

COLOURS = {
    "paint": (0.62, 0.08, 0.07, 1),
    "carbon": (0.07, 0.07, 0.08, 1),
    "trim": (0.16, 0.16, 0.17, 1),
    "interior": (0.20, 0.20, 0.23, 1),
    "underbody": (0.10, 0.10, 0.10, 1),
    "wheel": (0.12, 0.12, 0.12, 1),
    "caliper": (0.7, 0.6, 0.1, 1),
    "light": (0.8, 0.8, 0.75, 1),
    "engine": (0.25, 0.25, 0.27, 1),
    "plate": (0.6, 0.6, 0.6, 1),
    "glass": (0.55, 0.70, 0.80, 0.25),
    "door": (0.75, 0.12, 0.10, 1),
    "sill": (0.10, 0.10, 0.11, 1),
    "door_glass": (0.55, 0.70, 0.80, 0.25),
    "ground": (0.32, 0.33, 0.35, 1),
    # Groups of a manifest-built car (tools/anim/car_entry_prep_manifest.py).
    "body": (0.62, 0.08, 0.07, 1),
    "cage": (0.18, 0.18, 0.2, 1),
    "seat": (0.45, 0.06, 0.06, 1),
    "harness": (0.85, 0.65, 0.1, 1),
    "cabin": (0.2, 0.2, 0.23, 1),
}


def flat(name, colour):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = colour
    return mat


def mesh_object(name, vertices, triangles, parent, colour_key):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in vertices], [], [tuple(int(i) for i in t) for t in triangles])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.data.materials.append(flat(f"Car {colour_key}", COLOURS.get(colour_key, (0.3, 0.3, 0.3, 1))))
    return obj


def add_car(scene_path, space):
    data = np.load(scene_path, allow_pickle=False)
    groups = [str(g) for g in data["groups"]]
    for group in groups:
        mesh_object(f"Car {group}", data[f"v_{group}"], data[f"f_{group}"], space, group)
    hinge = bpy.data.objects.new("DoorHinge", None)
    hinge.empty_display_size = 0.4
    bpy.context.scene.collection.objects.link(hinge)
    hinge.parent = space
    hinge.matrix_parent_inverse = Matrix.Identity(4)
    pivot = Vector(data["hinge_pivot"].tolist())
    hinge.location = pivot
    hinge["axis"] = data["hinge_axis"].tolist()
    hinge["open_angle"] = float(data["open_angle"])
    for part in ("door", "door_glass"):
        if f"v_{part}" in data:
            obj = mesh_object(f"Door {part}", data[f"v_{part}"] - data["hinge_pivot"], data[f"f_{part}"], hinge, part)
            obj.location = (0, 0, 0)
    ground = mesh_object(
        "Ground",
        [(-60, 0, -60), (60, 0, -60), (60, 0, 60), (-60, 0, 60)],
        [(0, 1, 2), (0, 2, 3)],
        space,
        "ground",
    )
    ground.location = (0, -0.002, 0)
    return hinge


def door_matrix(hinge, openness):
    axis = Vector(hinge["axis"]).normalized()
    return Matrix.Rotation(openness * hinge["open_angle"], 4, axis)


def key_door(keys, hinge):
    """Openness lives on an empty's X location, interpolated like any other key; the hinge's
    rotation is then keyed every frame from it, so the mesh and the curve cannot disagree."""
    store = bpy.data.objects.new("DoorOpenness", None)
    bpy.context.scene.collection.objects.link(store)
    for entry in keys.get("door", []):
        store.location.x = entry["value"]
        store.keyframe_insert("location", index=0, frame=entry["frame"])
    if store.animation_data:
        for curve in r6_rig.fcurves_of(store):
            for point, entry in zip(curve.keyframe_points, sorted(keys["door"], key=lambda e: e["frame"])):
                point.interpolation = entry.get("interp", "BEZIER")
                handle = entry.get("ease", "AUTO_CLAMPED")
                point.handle_left_type = handle
                point.handle_right_type = handle
            curve.update()
    scene = bpy.context.scene
    hinge.rotation_mode = "QUATERNION"
    for frame in range(scene.frame_start, scene.frame_end + 1):
        scene.frame_set(frame)
        openness = max(0.0, min(1.0, store.location.x))
        hinge.rotation_quaternion = door_matrix(hinge, openness).to_quaternion()
        hinge.keyframe_insert("rotation_quaternion", frame=frame)
    for curve in r6_rig.fcurves_of(hinge):
        for point in curve.keyframe_points:
            point.interpolation = "LINEAR"


def key_root_quaternions(keys):
    """The torso turns through a full 270 degrees and leans at a 90-degree yaw, where an XYZ Euler
    locks: RootJoint is keyed as quaternions instead (the keys carry both; the bake reads the
    joint's matrix either way)."""
    entries = [e for e in keys["joints"]["RootJoint"] if "quat" in e]
    if not entries:
        return
    obj = bpy.data.objects["RootJoint"]
    action = obj.animation_data.action
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in [c for c in bag.fcurves if c.data_path == "rotation_euler"]:
                    bag.fcurves.remove(curve)
    obj.rotation_mode = "QUATERNION"
    for entry in entries:
        obj.rotation_quaternion = entry["quat"]
        obj.keyframe_insert("rotation_quaternion", frame=entry["frame"])
    for curve in r6_rig.fcurves_of(obj):
        if curve.data_path == "rotation_quaternion":
            for point in curve.keyframe_points:
                point.interpolation = "BEZIER"
                point.handle_left_type = "AUTO_CLAMPED"
                point.handle_right_type = "AUTO_CLAMPED"
            curve.update()


def build(keys_path, scene_path, out_blend):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    space, _ = r6_rig.build_rig()
    with open(keys_path, encoding="utf-8") as handle:
        keys = json.load(handle)
    r6_rig.apply_keys(keys)
    key_root_quaternions(keys)
    hinge = add_car(scene_path, space)
    key_door(keys, hinge)
    bpy.context.scene["clips"] = json.dumps(keys.get("clips", []))
    bpy.ops.wm.save_as_mainfile(filepath=out_blend)


def bake(out_path, substeps=1):
    scene = bpy.context.scene
    store = bpy.data.objects["DoorOpenness"]
    frames = []
    samples = [
        (frame, step / substeps)
        for frame in range(scene.frame_start, scene.frame_end + 1)
        for step in range(substeps)
        if frame < scene.frame_end or step == 0
    ]
    space = bpy.data.objects["RobloxSpace"].matrix_world.inverted()
    for frame, subframe in samples:
        scene.frame_set(frame, subframe=subframe)
        poses = {}
        for joint_name in r6_rig.JOINTS:
            m = r6_rig.transform_of(joint_name)
            poses[joint_name] = [m[0][3], m[1][3], m[2][3]] + [m[i][j] for i in range(3) for j in range(3)]
        world = {}
        for part in r6_rig.PARTS:
            w = space @ bpy.data.objects[part].matrix_world
            world[part] = [w[0][3], w[1][3], w[2][3]] + [w[i][j] for i in range(3) for j in range(3)]
        frames.append(
            {
                "frame": frame + subframe,
                "time": (frame + subframe - scene.frame_start) / scene.render.fps,
                "poses": poses,
                "parts": world,
                "door": max(0.0, min(1.0, store.location.x)),
            }
        )
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(
            {"fps": scene.render.fps * substeps, "clips": json.loads(scene.get("clips", "[]")), "frames": frames},
            handle,
        )


def add_camera(name, location, target, lens):
    data = bpy.data.cameras.new(name)
    data.lens = lens
    data.clip_start = 0.05
    camera = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(camera)
    camera.location = location
    direction = Vector(target) - Vector(location)
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return camera


# EntryView's third-person offsets from the head (authoring studs: game studs / driver scale).
# Leaving, as EntryView places it since #17's 92a85a5: 11 game studs off the driver's door, a little
# toward the rear (85% outward, 50% rearward, flattened), 3.5 up.
FOLLOW = {"entry": (0.0, 4.5, 12.0), "leave": (6.51, 4.08, 11.06)}


def roblox_to_blender(point):
    """RobloxSpace is turned +90 degrees about X: Roblox (x, y, z) is Blender (x, -z, y)."""
    return (point[0], -point[2], point[1])


def render(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("out_dir")
    parser.add_argument("--cams", default="side,game,top,eye")
    parser.add_argument("--stretch", type=int, default=4)
    parser.add_argument("--res", type=int, default=480)
    parser.add_argument("--from", dest="start", type=int, default=None)
    parser.add_argument("--to", dest="end", type=int, default=None)
    parser.add_argument("--step", type=int, default=1, help="render every n-th output frame")
    args = parser.parse_args(argv)
    scene = bpy.context.scene
    cams = json.loads(scene.get("cameras", "{}"))
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "MATERIAL"
    shading.show_shadows = True
    shading.shadow_intensity = 0.4
    shading.show_cavity = True
    shading.background_type = "VIEWPORT"
    shading.background_color = (0.62, 0.74, 0.86)
    scene.display.light_direction = (0.45, -0.35, 0.82)
    scene.display.render_aa = "8"
    scene.view_settings.view_transform = "Standard"
    for mat in bpy.data.materials:
        if mat.name.startswith("R6 "):
            mat.diffuse_color = (0.42, 0.44, 0.48, 1) if mat.name == "R6 Torso" else (0.95, 0.85, 0.72, 1)
    scene.render.resolution_x = args.res
    scene.render.resolution_y = int(args.res * 9 / 16)
    scene.render.image_settings.file_format = "PNG"
    first, last = scene.frame_start, scene.frame_end
    start = args.start if args.start is not None else first
    end = args.end if args.end is not None else last
    scene.render.frame_map_old = 1
    scene.render.frame_map_new = args.stretch
    scene.frame_start = start * args.stretch
    scene.frame_end = end * args.stretch
    scene.frame_step = args.step
    for name in args.cams.split(","):
        head = bpy.data.objects["Head"]
        head.hide_render = False
        if name == "eye":
            # First person rides the animated head, as EntryView does: CFrame.new(0, 0.1, -0.35)
            # in game studs at the driver's scale, the head itself hidden as in Roblox's own.
            scale = float(scene.get("driver_scale", 1.0))
            camera = add_camera(name, (0, 0, 0), (0, 1, 0), 14.5)
            camera.parent = head
            camera.matrix_parent_inverse = Matrix.Identity(4)
            camera.matrix_basis = Matrix.Translation(Vector((0.0, 0.1, -0.35)) / scale) @ Matrix.Rotation(0, 4, "X")
            head.hide_render = True
            scene.camera = camera
        elif name in FOLLOW:
            # EntryView's third person: a fixed offset from the head, kept from the sequence's
            # start, looking at the head (entering, the on-foot camera behind the player; leaving,
            # the car view's place behind the car). Offsets in authoring studs.
            camera = add_camera(name, roblox_to_blender(FOLLOW[name]), (0, 0, 0), 24)
            follow = camera.constraints.new("COPY_LOCATION")
            follow.target = head
            follow.use_offset = True
            look = camera.constraints.new("TRACK_TO")
            look.target = head
            look.track_axis = "TRACK_NEGATIVE_Z"
            look.up_axis = "UP_Y"
            scene.camera = camera
        elif name == "door":
            # A standing eye beside the door mark (a scale-1 R6's eye, the authoring frame's scale;
            # a step back and to the side, out of the entering body's way), looking into the opening.
            scene.camera = add_camera(name, roblox_to_blender((1.8, 4.6, 2.4)), roblox_to_blender((-0.5, 2.4, -3.4)), 18)
        else:
            location, target, lens = cams[name]
            scene.camera = add_camera(name, roblox_to_blender(location), roblox_to_blender(target), lens)
        scene.render.filepath = os.path.join(args.out_dir, name, "f_")
        bpy.ops.render.render(animation=True)


def main(argv):
    command = argv[0]
    if command == "build":
        build(argv[1], argv[2], argv[3])
        data = np.load(argv[2], allow_pickle=False)
        bpy.context.scene["cameras"] = str(data["cameras"])
        bpy.context.scene["driver_scale"] = float(data["scale"])
        bpy.ops.wm.save_as_mainfile(filepath=argv[3])
    elif command == "bake":
        bake(argv[1], int(argv[2]) if len(argv) > 2 else 1)
    elif command == "render":
        render(argv[1:])
    else:
        raise SystemExit(f"unknown command {command}")


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1 :])
