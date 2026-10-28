"""
Roblox R6 rig in Blender, built from the joint data Roblox itself returns for an R6 rig
(Players:CreateHumanoidModelFromDescription, read 2026-10-27), so a pose here is the pose in game.

Roblox places a joint's child part at  Part0 * C0 * Transform * C1^-1.
Here each joint is  Part0 -> pivot (C0's position only) -> anim (animated, BODY axes)
-> Part1 at (C0's rotation * C1^-1).  Animating in body axes keeps the curves readable
(X = pitch / swing, Y = yaw, Z = roll / spread), and the export recovers
Transform = C0rot^T * anim * C0rot.

Everything lives under one empty, "RobloxSpace", turned +90 degrees about X so Roblox's
Y-up coordinates can be written verbatim (Roblox forward -Z is Blender +Y).

Body-axis signs (Roblox frame: +X right, +Y up, -Z forward):
  limbs:  rot X +  = swing forward      rot Z + = right limb out / left limb in
  torso:  rot X -  = lean forward       rot Y + = turn left      rot Z + = lean left
  head:   rot X -  = nod down           rot Y + = look left

Usage inside Blender:
  blender -b -P r6_rig.py -- build <keys.json> <out.blend>
  blender -b <file.blend> -P r6_rig.py -- bake <out.json>
"""
import json
import math
import sys

import bpy
from mathutils import Euler, Matrix, Vector


def cframe(x, y, z, r):
    return Matrix(
        (
            (r[0], r[1], r[2], x),
            (r[3], r[4], r[5], y),
            (r[6], r[7], r[8], z),
            (0, 0, 0, 1),
        )
    )


ROOT_ROT = [-1, 0, 0, 0, 0, 1, 0, 1, 0]
RIGHT_ROT = [0, 0, 1, 0, 1, 0, -1, 0, 0]
LEFT_ROT = [0, 0, -1, 0, 1, 0, 1, 0, 0]

PARTS = {
    "HumanoidRootPart": (2, 2, 1),
    "Torso": (2, 2, 1),
    "Head": (2, 1, 1),
    "Right Arm": (1, 2, 1),
    "Left Arm": (1, 2, 1),
    "Right Leg": (1, 2, 1),
    "Left Leg": (1, 2, 1),
}

# name: (part0, part1, C0, C1), exactly as Roblox builds an R6 rig.
JOINTS = {
    "RootJoint": ("HumanoidRootPart", "Torso", cframe(0, 0, 0, ROOT_ROT), cframe(0, 0, 0, ROOT_ROT)),
    "Neck": ("Torso", "Head", cframe(0, 1, 0, ROOT_ROT), cframe(0, -0.5, 0, ROOT_ROT)),
    "Right Shoulder": ("Torso", "Right Arm", cframe(1, 0.5, 0, RIGHT_ROT), cframe(-0.5, 0.5, 0, RIGHT_ROT)),
    "Left Shoulder": ("Torso", "Left Arm", cframe(-1, 0.5, 0, LEFT_ROT), cframe(0.5, 0.5, 0, LEFT_ROT)),
    "Right Hip": ("Torso", "Right Leg", cframe(1, -1, 0, RIGHT_ROT), cframe(0.5, 1, 0, RIGHT_ROT)),
    "Left Hip": ("Torso", "Left Leg", cframe(-1, -1, 0, LEFT_ROT), cframe(-0.5, 1, 0, LEFT_ROT)),
}

# Standing: the root part's centre is 3 studs up (legs 2 + half a torso).
ROOT_HEIGHT = 3.0

COLOURS = {
    "Torso": (0.42, 0.44, 0.48, 1),
    "Head": (0.93, 0.93, 0.93, 1),
    "Right Arm": (0.93, 0.93, 0.93, 1),
    "Left Arm": (0.93, 0.93, 0.93, 1),
    "Right Leg": (0.93, 0.93, 0.93, 1),
    "Left Leg": (0.93, 0.93, 0.93, 1),
}


def rotation_part(m):
    return m.to_3x3().to_4x4()


def material(name, colour):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = colour
    bsdf.inputs["Roughness"].default_value = 0.55
    return mat


def box(name, size, parent):
    bpy.ops.mesh.primitive_cube_add(size=1)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    for vertex in obj.data.vertices:
        vertex.co = Vector((vertex.co.x * size[0], vertex.co.y * size[1], vertex.co.z * size[2]))
    obj.parent = parent
    obj.matrix_parent_inverse = Matrix.Identity(4)
    if name in COLOURS:
        obj.data.materials.append(material(f"R6 {name}", COLOURS[name]))
    bevel = obj.modifiers.new("Bevel", "BEVEL")
    bevel.width = 0.04
    bevel.segments = 2
    return obj


def empty(name, parent, basis):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_size = 0.3
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.matrix_basis = basis
    return obj


def build_rig():
    space = empty("RobloxSpace", None, Euler((math.radians(90), 0, 0)).to_matrix().to_4x4())
    parts = {}
    root = box("HumanoidRootPart", PARTS["HumanoidRootPart"], space)
    root.matrix_basis = Matrix.Translation((0, ROOT_HEIGHT, 0))
    root.hide_render = True
    root.display_type = "WIRE"
    parts["HumanoidRootPart"] = root
    for name, (part0, part1, c0, c1) in JOINTS.items():
        pivot = empty(f"{name} pivot", parts[part0], Matrix.Translation(c0.to_translation()))
        anim = empty(name, pivot, Matrix.Identity(4))
        anim.rotation_mode = "XYZ"
        child = box(part1, PARTS[part1], anim)
        child.matrix_basis = rotation_part(c0) @ c1.inverted()
        parts[part1] = child
    return space, parts


def transform_of(joint_name):
    """The Roblox Motor6D.Transform this joint's current pose stands for."""
    _, _, c0, _ = JOINTS[joint_name]
    anim = bpy.data.objects[joint_name].matrix_basis
    c0_rotation = rotation_part(c0)
    return c0_rotation.inverted() @ anim @ c0_rotation


def apply_keys(keys):
    """keys: {"fps", "frames", "joints": {joint: [{"frame", "rot": [x,y,z] deg, "loc": [x,y,z]?,
    "interp": "BEZIER"|"LINEAR"|"CONSTANT", "ease": "AUTO_CLAMPED"|"VECTOR"|...}]}}"""
    scene = bpy.context.scene
    scene.render.fps = keys["fps"]
    scene.frame_start = 0
    scene.frame_end = keys["frames"] - 1
    for joint_name, entries in keys["joints"].items():
        obj = bpy.data.objects[joint_name]
        for entry in entries:
            obj.rotation_euler = [math.radians(a) for a in entry["rot"]]
            obj.keyframe_insert("rotation_euler", frame=entry["frame"])
            if "loc" in entry:
                obj.location = entry["loc"]
                obj.keyframe_insert("location", frame=entry["frame"])
        if obj.animation_data and obj.animation_data.action:
            for curve in fcurves_of(obj):
                for point, entry in zip(curve.keyframe_points, sorted_entries(entries, curve)):
                    point.interpolation = entry.get("interp", "BEZIER")
                    handle = entry.get("ease", "AUTO_CLAMPED")
                    point.handle_left_type = handle
                    point.handle_right_type = handle
                if keys.get("cyclic", False):
                    curve.modifiers.new("CYCLES")
                curve.update()


def sorted_entries(entries, curve):
    if curve.data_path == "location":
        return sorted((e for e in entries if "loc" in e), key=lambda e: e["frame"])
    return sorted(entries, key=lambda e: e["frame"])


def fcurves_of(obj):
    action = obj.animation_data.action
    # Blender 4.4+ stores curves in layered actions (slots and channelbags).
    if hasattr(action, "layers") and action.layers:
        curves = []
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    curves.extend(bag.fcurves)
        return curves
    return list(action.fcurves)


def bake(out_path, substeps=1):
    """substeps > 1 samples between frames too, to check what Roblox interpolates."""
    scene = bpy.context.scene
    frames = []
    samples = [
        (frame, step / substeps)
        for frame in range(scene.frame_start, scene.frame_end + 1)
        for step in range(substeps)
        if frame < scene.frame_end or step == 0
    ]
    for frame, subframe in samples:
        scene.frame_set(frame, subframe=subframe)
        poses = {}
        for joint_name in JOINTS:
            m = transform_of(joint_name)
            poses[joint_name] = [m[0][3], m[1][3], m[2][3]] + [m[i][j] for i in range(3) for j in range(3)]
        world = {}
        space = bpy.data.objects["RobloxSpace"].matrix_world.inverted()
        for part in PARTS:
            # Part CFrame in Roblox space, for a numeric check against the engine.
            w = space @ bpy.data.objects[part].matrix_world
            world[part] = [w[0][3], w[1][3], w[2][3]] + [w[i][j] for i in range(3) for j in range(3)]
        frames.append(
            {
                "frame": frame + subframe,
                "time": (frame + subframe - scene.frame_start) / scene.render.fps,
                "poses": poses,
                "parts": world,
            }
        )
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump({"fps": scene.render.fps * substeps, "frames": frames}, handle)


def main(argv):
    command = argv[0]
    if command == "build":
        keys_path, out_blend = argv[1], argv[2]
        bpy.ops.wm.read_factory_settings(use_empty=True)
        build_rig()
        with open(keys_path, encoding="utf-8") as handle:
            apply_keys(json.load(handle))
        bpy.ops.wm.save_as_mainfile(filepath=out_blend)
    elif command == "bake":
        bake(argv[1], int(argv[2]) if len(argv) > 2 else 1)
    else:
        raise SystemExit(f"unknown command {command}")


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1 :])
