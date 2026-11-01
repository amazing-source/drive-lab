"""
Poses the CC0 hand of tools/blender/hand_grip.py into the shapes the driver's start-up needs and
exports both hands in their own wrist frame, with a sleeve cuff, for Roblox.

    blender -b --factory-startup -P tools/blender/hand_poses.py -- <Hand_Nails_R.gltf> <out dir>

Shapes:
- Point: the index straight, the other fingers curled into the palm and the thumb over them, to
  lift the START flap by its edge and press the button;
- Rest: a relaxed hand lying on the thigh, fingers a little curved and apart;
- Pinch: a key pinch, the thumb's pad pressed against the side of the curled index with a key's
  blade (PINCH_GAP) between them, the other fingers curled; to turn a key;
- Knob: the palm over a ball (a gear lever's knob, --knob-radius, metres) and each finger closed
  round it until it touches, as hand_grip.py closes them round a rim; to hold a gear lever;
- KeyPinch: the lateral key pinch a key is turned with: the index curled so its middle bone stands
  in front of the palm, the thumb's pad against its side with a blade between, the other fingers
  curled beside it; the key leaves the pinch away from the palm, so the palm faces the cylinder.

The hand's own frame (the frame the game moves): origin at the wrist joint, z from the wrist up
the forearm, y out of the back of the hand, x = y cross z (toward the little finger on the
right hand). In the source hand (fingers along +y, palm facing -x, index on +z) that is
z = -y, y = +x, x = -z. The left hand is the right mirrored in that frame's x.

Output, in <out dir>: hand_{Point,Rest}_{R,L}.glb and cuff_{R,L}.glb in Roblox studs at the
world scale (1 stud = 0.28 / 1.5 m), already in the hand frame; poses.json with, per shape and
side, the mesh centre (where Roblox puts the imported MeshPart), the cuff's centre, the index
fingertip (the skin's end of the index) and the middle of the palm, all studs in the hand frame;
for Pinch and KeyPinch also the point the blade is held at and the unit axis from the thumb's pad
to the index across it, for KeyPinch also the key's axis out of the palm (keyAxis, unit, toward the
cylinder); for Knob the ball's centre; and check renders.
"""

import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hand_grip import FINGER_RADIUS, STUDS_PER_METRE, bounds_centre, cuff_mesh, export_studs, pose_bone_about_world_z, solve_finger, studs  # noqa: E402

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
    "Pinch": {
        "Index": (40, 55, 20),
        "Middle": (70, 90, 50),
        "Ring": (76, 95, 50),
        "Little": (82, 95, 50),
        "spread": (0, 0, 0, 0),
        "pinch": True,
    },
    "Knob": {
        "ThumbBase": 30,
        "Thumb": (30, 25),
        "ball": True,
    },
    "KeyPinch": {
        "Index": (60, 30, 15),
        "Middle": (82, 75, 45),
        "Ring": (84, 80, 45),
        "Little": (86, 85, 45),
        "spread": (0, 0, 0, 0),
        "pinch": True,
        "keyOutOfPalm": True,
        "thumbSearch": {"mz": (-70, 61, 10), "my": (-70, 41, 10), "curl": (0, 15, 30, 45, 60, 75, 90), "side": 0.95},
    },
}
# The knob grip (metres): the ball under the middle of the palm, between the wrist and the
# knuckles, the palm KNOB_GAP off its surface.
KNOB_RADIUS = 0.0246
KNOB_GAP = 0.002
KNOB_BACK = 0.035
# The finger pads' skin runs past the bone line plus FINGER_RADIUS; closing to it alone left the pads
# 5.8 mm inside the ball (measured on the exported mesh), as hand_grip.py's SKIN_MARGIN fixes on a rim.
KNOB_SKIN = 0.006
# The key pinch (metres): the blade held between the thumb's pad and the side of the index's
# middle bone. The pad is THUMB_PAD along the thumb's end bone, which runs about 2.5 cm past the
# skin (DRIVER_HANDS.md 8a).
PINCH_GAP = 0.009
THUMB_PAD = 0.35
THUMB_RADIUS = 0.0095
INDEX_RADIUS = 0.0085
THUMB = ("Thumb_Metacarpal_R", "Thumb_Proximal_R", "Thumb_Distal_R", "Thumb_Tip_R")
# The thumb's search (degrees): the metacarpal's turn about z as range() arguments, and the curls.
THUMB_SEARCH = {"mz": (-30, 61, 10), "curl": (0, 15, 30, 45, 60)}
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
    if pose.get("ball"):
        return posed_on_ball(arm, hand, added)
    for finger, fan in zip(FINGERS, pose["spread"]):
        spread(arm, f"{finger}_Proximal_R", fan)
        for part, angle in zip(("Proximal", "Intermediate", "Distal"), pose[finger]):
            flex(arm, f"{finger}_{part}_R", angle)
    pinch = None
    if pose.get("pinch"):
        bpy.context.view_layer.update()
        pinch = solve_pinch(arm, pose.get("thumbSearch", THUMB_SEARCH))
    else:
        flex(arm, "Thumb_Metacarpal_R", pose["ThumbBase"])
        flex(arm, "Thumb_Proximal_R", pose["Thumb"][0])
        flex(arm, "Thumb_Distal_R", pose["Thumb"][1])
    bpy.context.view_layer.update()
    tip = arm.matrix_world @ arm.pose.bones["Index_Tip_R"].tail
    wrist = arm.data.bones["Wrist_R"].head_local.copy()
    arm_world = arm.matrix_world.copy()
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
    fingertip = min((v.co.copy() for v in hand.data.vertices), key=lambda co: (co - tail).length)
    if pinch is not None:
        pad, side = (place @ (arm_world @ p) for p in pinch[:2])
        across = (side - pad).normalized()
        pinch = {"point": side - across * (INDEX_RADIUS + PINCH_GAP / 2), "axis": across, "report": pinch[2]}
        if pose.get("keyOutOfPalm"):
            # Out of the palm (-y), square to the pinch: the blade lies between the pad and the index.
            palm = Vector((0, -1, 0))
            pinch["keyAxis"] = (palm - across * palm.dot(across)).normalized()
    return hand, fingertip, pinch


def posed_on_ball(arm, hand, added):
    """The Knob shape: in the source's rest space (fingers along +y, palm facing -x, index on +z) the
    ball sits against the palm's middle; each finger closes in its own plane round the circle that
    plane cuts from the ball (hand_grip.solve_finger), the thumb set by angles."""
    bones = arm.data.bones
    knuckles = [bones[f"{f}_Proximal_R"].head_local for f in FINGERS]
    ball_y = sum(k.y for k in knuckles) / 4 - KNOB_BACK
    ball_z = (knuckles[1].z + knuckles[2].z) / 2
    palm = [hand.matrix_world @ v.co for v in hand.data.vertices]
    palm_x = min(p.x for p in palm if abs(p.y - ball_y) < 0.006 and abs(p.z - ball_z) < 0.02)
    centre = Vector((palm_x - KNOB_GAP - KNOB_RADIUS, ball_y, ball_z))
    for finger in FINGERS:
        names = [f"{finger}_{part}_R" for part in ("Proximal", "Intermediate", "Distal", "Tip")]
        heads = [bones[n].head_local.xy.copy() for n in names] + [bones[names[-1]].tail_local.xy.copy()]
        across = abs(bones[names[0]].head_local.z - centre.z)
        circle = math.sqrt(max(KNOB_RADIUS**2 - across**2, 0.0))
        angles = solve_finger(heads, centre.xy, circle + FINGER_RADIUS[finger] + KNOB_SKIN)
        for name, angle in zip(names[:3], angles):
            pose_bone_about_world_z(arm, name, angle)
    pose = SHAPES["Knob"]
    flex(arm, "Thumb_Metacarpal_R", pose["ThumbBase"])
    flex(arm, "Thumb_Proximal_R", pose["Thumb"][0])
    flex(arm, "Thumb_Distal_R", pose["Thumb"][1])
    bpy.context.view_layer.update()
    tip = arm.matrix_world @ arm.pose.bones["Index_Tip_R"].tail
    wrist = bones["Wrist_R"].head_local.copy()
    bpy.context.view_layer.objects.active = hand
    for modifier in hand.modifiers:
        if modifier.type == "ARMATURE":
            bpy.ops.object.modifier_apply(modifier=modifier.name)
    for obj in added:
        if obj is not hand:
            bpy.data.objects.remove(obj)
    place = TO_FRAME @ Matrix.Translation(-wrist)
    hand.data.transform(place @ hand.matrix_world)
    hand.matrix_world = Matrix.Identity(4)
    hand.name = "Hand_Knob"
    tail = place @ tip
    fingertip = min((v.co.copy() for v in hand.data.vertices), key=lambda co: (co - tail).length)
    return hand, fingertip, {"ball": place @ centre, "radius": KNOB_RADIUS}


def thumb_chain(bones, turn, proximal, distal):
    """The thumb's joints, armature space, after the metacarpal turns by `turn` (rest axes, about
    its head) and the proximal and distal joints curl about the rest pose's z, each after its
    parent, as Blender composes a pose: the metacarpal's head to the tip."""
    rest = [bones[THUMB[0]].head_local.copy()] + [bones[n].tail_local.copy() for n in THUMB]
    out = [rest[0]]
    rot = turn
    out.append(out[0] + rot @ (rest[1] - rest[0]))
    rot = turn @ Matrix.Rotation(proximal, 3, "Z")
    out.append(out[1] + rot @ (rest[2] - rest[1]))
    rot = rot @ Matrix.Rotation(distal, 3, "Z")
    out.append(out[2] + rot @ (rest[3] - rest[2]))
    out.append(out[3] + rot @ (rest[4] - rest[3]))
    return out


def closest_on_segment(p, a, b):
    ab = b - a
    u = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return a + ab * u, u


def solve_pinch(arm, search):
    """Lays the thumb's pad against the thumb side of the posed index's middle bone with a blade's
    gap between the skins: searched over the metacarpal's turn and the two curls. Poses the thumb
    and returns the pad and the nearest point of the index's bone line (armature space)."""
    bones = arm.data.bones
    index = arm.pose.bones["Index_Intermediate_R"]
    a, b = index.head.copy(), index.tail.copy()
    target = THUMB_RADIUS + PINCH_GAP + INDEX_RADIUS
    best = None
    rad = math.radians
    for mz in range(*search["mz"]):
        for mx in range(-40, 41, 10):
            for my in range(*search.get("my", (-40, 41, 10))):
                turn = Matrix.Rotation(rad(mz), 3, "Z") @ Matrix.Rotation(rad(mx), 3, "X") @ Matrix.Rotation(rad(my), 3, "Y")
                for curl in search["curl"]:
                    chain = thumb_chain(bones, turn, rad(curl * 0.4), rad(curl * 0.6))
                    pad = chain[3].lerp(chain[4], THUMB_PAD)
                    near, u = closest_on_segment(pad, a, b)
                    # The pad must sit beside the index (its thumb side is +z in the source
                    # hand), not under the palm or over the back of the finger.
                    side = (pad - near).normalized().z
                    score = abs((pad - near).length - target) * 100 + abs(u - 0.55) + max(0.0, search.get("side", 0.8) - side) * 3
                    score += (abs(mz) + abs(mx) + abs(my) + curl) * 0.0005
                    if best is None or score < best[0]:
                        best = (score, turn, curl, pad, near, dict(gap_mm=round(((pad - near).length - target) * 1000, 2), along=round(u, 2), side=round(side, 3), metacarpal_deg=(mz, mx, my), curl_deg=curl))
    _, turn, curl, pad, near, report = best
    meta = arm.pose.bones[THUMB[0]]
    rest = meta.bone.matrix_local.to_3x3()
    meta.rotation_mode = "QUATERNION"
    meta.rotation_quaternion = (rest.inverted() @ turn @ rest).to_quaternion()
    for name, angle in ((THUMB[1], curl * 0.4), (THUMB[2], curl * 0.6)):
        bone = arm.pose.bones[name]
        axis = (bone.bone.matrix_local.to_3x3().inverted() @ Vector((0, 0, 1))).normalized()
        bone.rotation_mode = "QUATERNION"
        bone.rotation_quaternion = Quaternion(axis, math.radians(angle))
    print("pinch:", report)
    return pad, near, report


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


def export_shape(out, shape, hand, tip, palm, pinch):
    """Both sides' glb of one posed shape, and their poses.json entry."""
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
        if pinch is not None and "ball" in pinch:
            sides[side]["ball"] = studs(pinch["ball"] * flip)
            sides[side]["ballRadius"] = round(pinch["radius"] * STUDS_PER_METRE, 4)
        elif pinch is not None:
            sides[side]["pinch"] = studs(pinch["point"] * flip)
            sides[side]["pinchAxis"] = [round(c, 4) for c in pinch["axis"] * flip]
            if "keyAxis" in pinch:
                sides[side]["keyAxis"] = [round(c, 4) for c in pinch["keyAxis"] * flip]
        if mirror < 0:
            bpy.data.objects.remove(piece)
    if pinch is not None and "report" in pinch:
        sides["solve"] = pinch["report"]
    return sides


def main(args):
    hand_path, out = args[:2]
    os.makedirs(out, exist_ok=True)
    report = {"studsPerMetre": STUDS_PER_METRE, "shapes": {}}
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # A shape added later is posed and exported after the others, so their files (whose mesh
    # names count the scene's datablocks) stay byte-identical.
    late = [shape for shape, pose in SHAPES.items() if pose.get("keyOutOfPalm")]
    meshes = {}
    for shape in SHAPES:
        if shape not in late:
            hand, tip, pinch = posed(hand_path, shape)
            meshes[shape] = (hand, tip, palm_centre(hand), pinch)
    along, back, width = Vector((0, 0, 1)), Vector((0, 1, 0)), Vector((1, 0, 0))
    # Where hand_grip.py centres its cuff on the wrist, in this frame.
    cuff = cuff_mesh(Vector((0.002, -0.004, 0)), along, width, back, "Cuff")
    checks = []
    for shape, (hand, tip, palm, pinch) in meshes.items():
        report["shapes"][shape] = export_shape(out, shape, hand, tip, palm, pinch)
        checks.append(hand)
    left_cuff = mirrored(cuff)
    export_studs(cuff, os.path.join(out, "cuff_R.glb"))
    export_studs(left_cuff, os.path.join(out, "cuff_L.glb"))
    report["cuff"] = {"R": studs(bounds_centre(cuff)), "L": studs(bounds_centre(left_cuff))}
    bpy.data.objects.remove(left_cuff)
    for shape in late:
        hand, tip, pinch = posed(hand_path, shape)
        report["shapes"][shape] = export_shape(out, shape, hand, tip, palm_centre(hand), pinch)
        checks.append(hand)
    json.dump(report, open(os.path.join(out, "poses.json"), "w"), indent=1)
    print(json.dumps(report, indent=1))
    # Side by side for the renders: Point at the origin, Rest beside it, then Pinch.
    for index, piece in enumerate(checks[1:], 1):
        piece.location = (0.14 * index, 0, 0)
    skin, cloth = (0.85, 0.62, 0.5, 1), (0.08, 0.08, 0.09, 1)
    render_checks(out, [(piece, skin) for piece in checks] + [(cuff, cloth)])


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1 :])
