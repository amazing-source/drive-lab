"""
Poses the hands a car's gestures need beyond the start-up's (tools/blender/hand_poses.py) and
exports each in its own wrist frame for Roblox, as hand_poses.py does.

    blender -b --factory-startup --python-exit-code 1 -P tools/blender/gesture_poses.py -- <inputs.json> <out dir>

inputs.json is tools/anim/gesture_paths.py's, with a "knob" gesture. Shapes:
- Manettino: the Point hand's fingers (the index out, the others curled) with the thumb laid on the
  rim: the hand is placed as tools/anim/gesture_paths.py's knob_reference aims it (the index's end
  on the drive-mode knob's lever), and the thumb's metacarpal turn and curls are searched
  (thumb_press.py's solver: the skin of the pad on a face, the rest of the thumb off the wheel) for
  its pad on the rim's surface nearest where it hangs.

Output: hand_Manettino_R.glb (studs, the hand frame: origin at the wrist, z up the forearm, y out
of the back of the hand), gestures.json (per shape: the mesh centre, the index's end and the
thumb's pad in the hand frame, metres, and the solve) and a check render.
"""

import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "anim"))
import gesture_paths as gp  # noqa: E402
from hand_grip import bounds_centre, export_studs, studs  # noqa: E402
from hand_poses import FINGERS, SHAPES, TO_FRAME, flex, spread  # noqa: E402
from thumb_press import THUMB, ThumbSkin, kd, metacarpal, pose_about_world_z, pose_world, solve  # noqa: E402


def to_matrix(frame):
    m = Matrix([list(frame.rot[i]) + [frame.pos[i]] for i in range(3)] + [[0, 0, 0, 1]])
    return m


def main(args):
    inputs = json.load(open(args[0]))
    out = args[1]
    os.makedirs(out, exist_ok=True)
    gesture = next(g for g in inputs["gestures"] if g["kind"] == "knob")
    config = json.load(open(inputs["gestureConfig"]))
    poses = json.load(open(inputs["poses"]))
    axes, centre = gp.wheel_axes(json.load(open(inputs["startupConfig"])))
    wheel_cabin = gp.cabin_in(inputs, axes, centre)
    knob = gp.Knob(config, wheel_cabin, axes, centre)
    arm = gp.Arm(inputs["driver"], 1)
    tip = np.array(poses["shapes"]["Point"]["R"]["fingertip"], float) / gp.STUDS
    reference = gp.knob_reference(gesture, knob, arm, tip, axes, centre)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=inputs["hand"])
    arm_obj = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    hand = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    shape = SHAPES["Point"]
    for finger, fan in zip(FINGERS, shape["spread"]):
        spread(arm_obj, f"{finger}_Proximal_R", fan)
        for part, angle in zip(("Proximal", "Intermediate", "Distal"), shape[finger]):
            flex(arm_obj, f"{finger}_{part}_R", angle)
    bpy.context.view_layer.update()
    bones = arm_obj.data.bones
    wrist = bones["Wrist_R"].head_local.copy()
    place = TO_FRAME @ Matrix.Translation(-wrist)
    to_wheel = to_matrix(reference) @ place
    to_rest = to_wheel.inverted()

    # The rim and the wheel's other parts, in the source hand's rest space.
    points, tris, owner, names = wheel_cabin
    wheel_points = []
    rim_points = []
    for index, name in enumerate(names):
        if not name.startswith(("SteeringWheel", "WheelButton", "WheelRotary")):
            continue
        used = np.unique(tris[owner == index])
        if len(used) == 0:
            continue
        samples = points[used]
        wheel_points.append(samples)
        if name == "SteeringWheel_Rim":
            rim_points.append(samples)
    surface = gp.np.concatenate(wheel_points)
    rim = gp.np.concatenate(rim_points)
    rest_surface = [to_rest @ Vector(p) for p in surface]
    obstacles = kd([tuple(p) for p in rest_surface])

    skin = ThumbSkin(hand, bones)
    start = tuple(gesture.get("thumbStart", (0, -20, -20, 0)))
    hanging = skin.posed(start)
    pad_rest = Vector(hanging[skin.end].mean(0))
    pad_wheel = np.array(to_wheel @ pad_rest)
    # The rim's surface point nearest where the thumb's pad hangs, and the tube's outward normal there.
    nearest = rim[np.argmin(np.linalg.norm(rim - pad_wheel, axis=1))]
    polar = math.atan2(nearest[1], nearest[0])
    tube = np.array([math.cos(polar), math.sin(polar), 0.0]) * gesture.get("rimTube", 0.1585)
    normal = gp.unit(nearest - tube)
    face_rest = to_rest @ Vector(nearest)
    normal_rest = (to_rest.to_3x3() @ Vector(normal)).normalized()
    pose, height, off_centre, clearance = solve(skin, obstacles, face_rest, normal_rest, start)
    report = {
        "thumb": {"metacarpalDeg": pose[:3], "curlDeg": pose[3], "padHeightMm": round(height * 1000, 2), "padOffCentreMm": round(off_centre * 1000, 2), "clearanceMm": round(clearance * 1000, 2)},
        "rimPoint": [round(float(c), 5) for c in nearest],
        "rimPolarDeg": round(math.degrees(polar), 2),
    }
    print("manettino thumb:", report)
    mz, mx, my, curl = pose
    pose_world(arm_obj, THUMB[0], metacarpal(mz, mx, my))
    pose_about_world_z(arm_obj, THUMB[1], math.radians(curl * 0.4))
    pose_about_world_z(arm_obj, THUMB[2], math.radians(curl * 0.6))
    bpy.context.view_layer.update()
    index_tail = arm_obj.matrix_world @ arm_obj.pose.bones["Index_Tip_R"].tail
    posed_pad = skin.posed(pose)[skin.end]

    bpy.context.view_layer.objects.active = hand
    for modifier in hand.modifiers:
        if modifier.type == "ARMATURE":
            bpy.ops.object.modifier_apply(modifier=modifier.name)
    hand.data.transform(place @ hand.matrix_world)
    hand.matrix_world = Matrix.Identity(4)
    tail = place @ index_tail
    fingertip = min((v.co.copy() for v in hand.data.vertices), key=lambda co: (co - tail).length)
    face_frame = place @ face_rest
    pad = min((place @ Vector(p) for p in posed_pad), key=lambda co: (co - face_frame).length)
    export_studs(hand, os.path.join(out, "hand_Manettino_R.glb"))
    report.update(
        {
            "file": "hand_Manettino_R.glb",
            "centre": studs(bounds_centre(hand)),
            "fingertip": [round(c, 5) for c in fingertip],
            "thumbPad": [round(c, 5) for c in pad],
            "reference": reference.key(0)[1:],
        }
    )
    json.dump({"Manettino": report}, open(os.path.join(out, "gestures.json"), "w"), indent=1)
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1 :])
