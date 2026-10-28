"""
Poses the CC0 hand of tools/blender/hand_grip.py into the shapes the driver's start-up needs and
exports both hands in their own wrist frame, with a sleeve cuff, for Roblox.

    blender -b --factory-startup -P tools/blender/hand_poses.py -- <Hand_Nails_R.gltf> <out dir>

Shapes:
- Point: the index straight, the other fingers curled into the palm and the thumb over them, to
  lift the START flap by its edge and press the button;
- Rest: a relaxed hand lying on the thigh, fingers a little curved and apart.

The hand's own frame (the frame the game moves): origin at the wrist joint, z from the wrist up
the forearm, y out of the back of the hand, x = y cross z (toward the little finger on the
right hand). In the source hand (fingers along +y, palm facing -x, index on +z) that is
z = -y, y = +x, x = -z. The left hand is the right mirrored in that frame's x.

Output, in <out dir>: hand_{Point,Rest}_{R,L}.glb and cuff_{R,L}.glb in Roblox studs at the
world scale (1 stud = 0.28 / 1.5 m), already in the hand frame; poses.json with, per shape and
side, the mesh centre (where Roblox puts the imported MeshPart), the cuff's centre, the index
fingertip (the skin's end of the index) and the middle of the palm, all studs in the hand frame;
and check renders.
"""

import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hand_grip import STUDS_PER_METRE, bounds_centre, cuff_mesh, export_studs, studs  # noqa: E402

FINGERS = ("Index", "Middle", "Ring", "Little")
# Flexion per joint (knuckle, middle, end), degrees; positive closes toward the palm.
SHAPES = {
    "Point": {
        "Index": (4, 6, 4),
        "Middle": (78, 95, 55),
        "Ring": (82, 98, 55),
        "Little": (86, 98, 55),
        "ThumbBase": 25,
        "Thumb": (45, 40),
        "spread": (0, 0, 0, 0),
    },
    "Rest": {
        "Index": (14, 18, 8),
        "Middle": (16, 20, 9),
        "Ring": (18, 22, 10),
        "Little": (20, 24, 12),
        "ThumbBase": 5,
        "Thumb": (8, 10),
        "spread": (-4, 0, 3, 7),
    },
}
# Source hand axes -> the hand frame (Roblox axes): x = -z, y = +x, z = -y.
TO_FRAME = Matrix(((0, 0, -1), (1, 0, 0), (0, -1, 0))).to_4x4()


def flex(arm, name, angle):
    """Turns a bone about the source's z axis, which closes a finger toward the palm."""
    bone = arm.pose.bones[name]
    axis = (bone.bone.matrix_local.to_3x3().inverted() @ Vector((0, 0, 1))).normalized()
    bone.rotation_mode = "QUATERNION"
    bone.rotation_quaternion = Quaternion(axis, math.radians(angle)) @ bone.rotation_quaternion


def spread(arm, name, angle):
    """Turns a knuckle about the source's x axis (palm normal), fanning the finger sideways."""
    bone = arm.pose.bones[name]
    axis = (bone.bone.matrix_local.to_3x3().inverted() @ Vector((1, 0, 0))).normalized()
    bone.rotation_mode = "QUATERNION"
    bone.rotation_quaternion = Quaternion(axis, math.radians(angle)) @ bone.rotation_quaternion


def posed(hand_path, shape):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=hand_path)
    added = [o for o in bpy.context.scene.objects if o not in before]
    arm = next(o for o in added if o.type == "ARMATURE")
    hand = next(o for o in added if o.type == "MESH")
    pose = SHAPES[shape]
    for finger, fan in zip(FINGERS, pose["spread"]):
        spread(arm, f"{finger}_Proximal_R", fan)
        for part, angle in zip(("Proximal", "Intermediate", "Distal"), pose[finger]):
            flex(arm, f"{finger}_{part}_R", angle)
    flex(arm, "Thumb_Metacarpal_R", pose["ThumbBase"])
    flex(arm, "Thumb_Proximal_R", pose["Thumb"][0])
    flex(arm, "Thumb_Distal_R", pose["Thumb"][1])
    bpy.context.view_layer.update()
    tip = arm.matrix_world @ arm.pose.bones["Index_Tip_R"].tail
    wrist = arm.data.bones["Wrist_R"].head_local.copy()
    bpy.context.view_layer.objects.active = hand
    for modifier in hand.modifiers:
        if modifier.type == "ARMATURE":
            bpy.ops.object.modifier_apply(modifier=modifier.name)
    for obj in added:
        if obj is not hand:
            bpy.data.objects.remove(obj)
    # Into the hand frame, wrist at the origin.
    place = TO_FRAME @ Matrix.Translation(-wrist)
    hand.data.transform(place @ hand.matrix_world)
    hand.matrix_world = Matrix.Identity(4)
    hand.name = f"Hand_{shape}"
    # The index's end on the skin: the bone's tail runs about 2.5 cm past the finger, so the
    # vertex nearest it is the fingertip the paths aim with.
    tail = place @ tip
    return hand, min((v.co.copy() for v in hand.data.vertices), key=lambda co: (co - tail).length)


def palm_centre(hand):
    """The middle of the palm's lowest band (most -y in the hand frame), where it rests: between
    the wrist and the knuckles and across the middle of the hand, so the thumb is left out."""
    points = [v.co for v in hand.data.vertices]
    palm = [p for p in points if -0.085 < p.z < -0.03 and -0.03 < p.x < 0.03]
    low = min(p.y for p in palm)
    band = [p for p in palm if p.y < low + 0.006]
    return sum(band, Vector()) / len(band)


def mirrored(obj):
    copy = obj.copy()
    copy.data = obj.data.copy()
    bpy.context.collection.objects.link(copy)
    copy.data.transform(Matrix.Scale(-1, 4, (1, 0, 0)))
    copy.data.flip_normals()
    return copy


def render_checks(out, objects):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    scene.render.resolution_x, scene.render.resolution_y = 1000, 700
    camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    scene.collection.objects.link(camera)
    scene.camera = camera
    for obj, colour in objects:
        obj.color = colour
    # The hand frame has y up (back of the hand) and z back along the forearm.
    views = {
        "side": (Vector((0.5, 0.12, -0.12)), Vector((0.07, -0.02, -0.1))),
        "above": (Vector((0.07, 0.55, -0.12)), Vector((0.07, 0.0, -0.1))),
        "front": (Vector((0.02, 0.15, -0.6)), Vector((0.07, -0.02, -0.1))),
        "under": (Vector((0.1, -0.45, -0.25)), Vector((0.07, 0.0, -0.1))),
    }
    for name, (eye, target) in views.items():
        forward = (target - eye).normalized()
        right = forward.cross(Vector((0, 1, 0))).normalized()
        up = right.cross(forward)
        camera.matrix_world = Matrix(
            (
                (right.x, up.x, -forward.x, eye.x),
                (right.y, up.y, -forward.y, eye.y),
                (right.z, up.z, -forward.z, eye.z),
                (0, 0, 0, 1),
            )
        )
        camera.data.lens = 40
        scene.render.filepath = os.path.join(out, f"check_{name}.png")
        bpy.ops.render.render(write_still=True)


def main(args):
    hand_path, out = args[:2]
    os.makedirs(out, exist_ok=True)
    report = {"studsPerMetre": STUDS_PER_METRE, "shapes": {}}
    bpy.ops.wm.read_factory_settings(use_empty=True)
    meshes = {}
    for shape in SHAPES:
        hand, tip = posed(hand_path, shape)
        meshes[shape] = (hand, tip, palm_centre(hand))
    along, back, width = Vector((0, 0, 1)), Vector((0, 1, 0)), Vector((1, 0, 0))
    # Where hand_grip.py centres its cuff on the wrist, in this frame.
    cuff = cuff_mesh(Vector((0.002, -0.004, 0)), along, width, back, "Cuff")
    checks = []
    for shape, (hand, tip, palm) in meshes.items():
        sides = {}
        for side, mirror in (("R", 1), ("L", -1)):
            piece = hand if mirror > 0 else mirrored(hand)
            export_studs(piece, os.path.join(out, f"hand_{shape}_{side}.glb"))
            flip = Vector((mirror, 1, 1))
            sides[side] = {
                "centre": studs(bounds_centre(piece)),
                "fingertip": studs(tip * flip),
                "palm": studs(palm * flip),
            }
            if mirror < 0:
                bpy.data.objects.remove(piece)
        report["shapes"][shape] = sides
        checks.append(hand)
    left_cuff = mirrored(cuff)
    export_studs(cuff, os.path.join(out, "cuff_R.glb"))
    export_studs(left_cuff, os.path.join(out, "cuff_L.glb"))
    report["cuff"] = {"R": studs(bounds_centre(cuff)), "L": studs(bounds_centre(left_cuff))}
    bpy.data.objects.remove(left_cuff)
    json.dump(report, open(os.path.join(out, "poses.json"), "w"), indent=1)
    print(json.dumps(report, indent=1))
    # Side by side for the renders: Point at the origin, Rest beside it.
    checks[1].location = (0.14, 0, 0)
    skin, cloth = (0.85, 0.62, 0.5, 1), (0.08, 0.08, 0.09, 1)
    render_checks(out, [(checks[0], skin), (checks[1], skin), (cuff, cloth)])


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1 :])
