"""
Poses a rigged hand gripping a steering-wheel rim and exports both hands for Roblox, already in
the wheel's own frame, plus the numbers the game needs to place them.

    blender -b --factory-startup -P tools/blender/hand_grip.py -- <hand_R.gltf> <wheel.glb>
        <points.json> <out dir> [--grip-angle 25] [--bar-tilt 28] [--wrist-turn 20]
        [--tube-radius 0.015] [--tube-centre 0.167,-0.005]

Inputs: a right hand with Godot XR Tools' bone names (Index_Proximal_R ...: fingers along +Y,
palm facing -X, index on +Z), the car's wheel export (an object named *Steering*) and the
export's points.json (wheel_centre, wheel_axis in Roblox axes, studs at 1 / 0.28 m).

How the grip is made:
- the rim at the grip is a straight tube (over a hand's width the rim's curve moves it 3 mm);
- it crosses the palm diagonally, as in a real power grip, from the base of the index finger
  toward the heel of the hand, tilted --bar-tilt degrees off the knuckle line. That tilt is what
  drops the wrist below the rim, so a forearm reaching up from the elbow meets the hand in line
  instead of at a right angle (the owner's note: the forearms must follow the hands);
- each finger's three joints close in turn, each until its bone touches the tube's surface
  plus the finger's thickness, within the joint's range, so the fingers wrap the rim instead of
  passing through it; a finger meets the tilted tube where the tube crosses that finger's plane;
- the posed hand is turned into the wheel's frame at 3 o'clock, rolled --wrist-turn degrees
  round the rim so the wrist sits outside it, then turned round the wheel by the grip angle,
  which lifts it clear of the spoke. The left hand is the right one mirrored;
- a short cuff of sleeve is built round the wrist along the hand's own axis: it covers the
  hand's cut end whatever angle the forearm arrives at.

Output, in <out dir>: hand_{R,L}.glb and cuff_{R,L}.glb in Roblox studs at the world scale
(1 stud = 0.28 / 1.5 m), already in the wheel frame (x right, y up the wheel's face, z toward
the driver); hands.json with, per hand, the mesh centres, the wrist point, the direction from
the wrist down the forearm and the back of the hand, all in that frame; check renders.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector
from mathutils.kdtree import KDTree

STUDS_PER_METRE = 1.5 / 0.28
EXPORT_STUDS_PER_METRE = 1 / 0.28
FINGERS = ("Index", "Middle", "Ring", "Little")
# Joint ranges, degrees: knuckle, middle joint, end joint.
LIMITS = (90, 110, 80)
# Half a finger's thickness, metres: how far a bone's line stays off the tube's surface.
FINGER_RADIUS = {"Index": 0.0085, "Middle": 0.0088, "Ring": 0.0082, "Little": 0.0072}


def option(args, name, default):
    return args[args.index(name) + 1] if name in args else default


def roblox_to_blender(v):
    return Vector((-v[0], v[2], v[1]))


def wheel_frame(points):
    centre = roblox_to_blender(points["wheel_centre"]) / EXPORT_STUDS_PER_METRE
    z = roblox_to_blender(points["wheel_axis"]).normalized()
    x = Vector((-1, 0, 0))
    x = (x - z * x.dot(z)).normalized()
    y = z.cross(x)
    return centre, x, y, z


def distance_to_segment(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (a + ab * t - p).length


def touches(tree, a, b, radius):
    """Whether the segment a-b (3D) comes within `radius` of any point in the KD tree."""
    if tree is None:
        return False
    for k in range(7):
        found = tree.find(a.lerp(b, k / 6))
        if found[0] is not None and found[2] < radius:
            return True
    return False


def solve_finger(heads, bar, reach, obstacles=None, zs=None, radius=0.0):
    """Greedy closing in the palm's plane (x, y): each joint turns until its bone touches the
    tube, or, with `obstacles` (a KD tree of the wheel's surface in the hand's rest space), any
    part of the wheel itself (`zs`: the heads' heights across the palm)."""
    angles = []
    points = [h.copy() for h in heads]
    for joint in range(3):
        best = 0.0
        for step in range(LIMITS[joint] + 1):
            a = math.radians(step)
            rot = Matrix.Rotation(a, 2)
            pivot = points[joint]
            moved = [pivot + rot @ (p - pivot) for p in points[joint + 1 :]]
            # Only the bone this joint drives is checked; the ones after it close next.
            if distance_to_segment(bar, pivot, moved[0]) < reach:
                break
            if obstacles is not None:
                a3 = Vector((pivot.x, pivot.y, zs[joint]))
                b3 = Vector((moved[0].x, moved[0].y, zs[joint + 1]))
                if touches(obstacles, a3, b3, radius):
                    break
            best = a
        rot = Matrix.Rotation(best, 2)
        pivot = points[joint]
        for k in range(joint + 1, len(points)):
            points[k] = pivot + rot @ (points[k] - pivot)
        angles.append(best)
    return angles


def cuff_mesh(wrist, along, across, thickness_axis, name):
    """A short closed oval tube round the wrist: 9 cm long, from 1.5 cm inside the hand back up
    the forearm, 8.0 x 6.4 cm outside (the hand's wrist is 6.4 x 4.8 cm)."""
    mesh = bmesh.new()
    rings = []
    stations = [-0.015, -0.012, 0.0, 0.02, 0.045, 0.07, 0.075]
    for k, d in enumerate(stations):
        end = 0.85 if k in (0, len(stations) - 1) else 1.0
        flare = 1.0 + 0.04 * max(0.0, d) / 0.075
        ring = []
        for j in range(20):
            theta = 2 * math.pi * j / 20
            fold = 0.025 * math.sin(3 * theta + 9 * d) if 0.0 < d < 0.07 else 0.0
            point = (
                wrist
                + along * d
                + across * (0.040 * end * flare * (1 + fold) * math.cos(theta))
                + thickness_axis * (0.032 * end * flare * (1 + fold) * math.sin(theta))
            )
            ring.append(mesh.verts.new(point))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for j in range(20):
            k = (j + 1) % 20
            mesh.faces.new((a[j], a[k], b[k], b[j]))
    mesh.faces.new(list(reversed(rings[0])))
    mesh.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(mesh, faces=mesh.faces)
    data = bpy.data.meshes.new(name)
    mesh.to_mesh(data)
    for polygon in data.polygons:
        polygon.use_smooth = True
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return obj


def export_studs(obj, path):
    # Wheel frame (Roblox axes) -> Blender axes for export, in studs: Roblox (x, y, z) is
    # Blender (-x, z, y) after the glTF importer's half turn.
    export = obj.copy()
    export.data = obj.data.copy()
    bpy.context.collection.objects.link(export)
    swap = Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    export.data.transform(Matrix.Scale(STUDS_PER_METRE, 4) @ swap)
    bpy.ops.object.select_all(action="DESELECT")
    export.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_tangents=True, export_materials="NONE")
    bpy.data.objects.remove(export)


def bounds_centre(obj):
    verts = [v.co for v in obj.data.vertices]
    lo = Vector([min(v[i] for v in verts) for i in range(3)])
    hi = Vector([max(v[i] for v in verts) for i in range(3)])
    return (lo + hi) / 2


def studs(v):
    return [round(c * STUDS_PER_METRE, 4) for c in v]


def pose_bone_about_world_z(arm, name, angle):
    bone = arm.pose.bones[name]
    axis = (bone.bone.matrix_local.to_3x3().inverted() @ Vector((0, 0, 1))).normalized()
    bone.rotation_mode = "QUATERNION"
    bone.rotation_quaternion = Quaternion(axis, angle)


def pose_bone_world(arm, name, turn):
    """Pose a bone by a rotation given in the rest pose's world axes."""
    bone = arm.pose.bones[name]
    rest = bone.bone.matrix_local.to_3x3()
    bone.rotation_mode = "QUATERNION"
    bone.rotation_quaternion = (rest.inverted() @ turn @ rest).to_quaternion()


def wheel_samples(wheel_path, points, spacing=0.002):
    """The wheel's surface as points in its own frame (metres: x right, y up the face, z toward
    the driver), from the car's wheel export; the import is removed again."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=wheel_path)
    added = [o for o in bpy.data.objects if o not in before]
    centre, xw, yw, zw = wheel_frame(points)
    basis = Matrix((xw, yw, zw)).to_4x4()
    out = []
    for o in added:
        if o.type != "MESH":
            continue
        m = basis @ Matrix.Scale(1 / EXPORT_STUDS_PER_METRE, 4) @ Matrix.Translation(-centre * EXPORT_STUDS_PER_METRE) @ o.matrix_world
        mesh = o.data
        mesh.calc_loop_triangles()
        verts = [m @ v.co for v in mesh.vertices]
        out.extend(verts)
        for tri in mesh.loop_triangles:
            a, b, c = (verts[i] for i in tri.vertices)
            n = max(1, int(math.ceil(((b - a).cross(c - a)).length / 2 / (spacing * spacing * 0.5))))
            steps = max(1, int(math.sqrt(n)))
            for i in range(steps + 1):
                for j in range(steps + 1 - i):
                    out.append(a + (b - a) * (i / steps) + (c - a) * (j / steps))
    for o in added:
        bpy.data.objects.remove(o, do_unlink=True)
    return out


def kd_tree(points):
    tree = KDTree(len(points))
    for i, p in enumerate(points):
        tree.insert(p, i)
    tree.balance()
    return tree


THUMB = ("Thumb_Metacarpal_R", "Thumb_Proximal_R", "Thumb_Distal_R", "Thumb_Tip_R")
# The end bone runs about 2.5 cm past the skin (DRIVER_HANDS.md 8a): the thumb's pad is this far
# along it.
THUMB_PAD = 0.35
# Half the thumb's thickness, metres.
THUMB_RADIUS = 0.0095
# How far the skin of a finger's pad and tip stands beyond its bone line plus its half
# thickness, metres: kept off the wheel's own surface.
SKIN_MARGIN = 0.003


def thumb_chain(bones, turn, proximal, distal):
    """The thumb's joints after the metacarpal turns by `turn` (rest world axes, about its head)
    and the proximal and distal joints curl about the rest pose's z, each after its parent, as
    Blender composes a pose. Returns the five chain points: the metacarpal's head to the tip."""
    rest = [bones[THUMB[0]].head_local.copy()] + [bones[n].tail_local.copy() for n in THUMB]
    rz_p = Matrix.Rotation(proximal, 3, "Z")
    rz_d = Matrix.Rotation(distal, 3, "Z")
    out = [rest[0]]
    rot = turn
    out.append(out[0] + rot @ (rest[1] - rest[0]))
    rot = turn @ rz_p
    out.append(out[1] + rot @ (rest[2] - rest[1]))
    rot = turn @ rz_p @ rz_d
    out.append(out[2] + rot @ (rest[3] - rest[2]))
    out.append(out[3] + rot @ (rest[4] - rest[3]))
    return out


def solve_thumb(bones, obstacles, spoke, avoid=True):
    """The thumb laid over the spoke: searched over the metacarpal's turn (about the rest pose's
    x, y, z) and the proximal and distal curls, for the tip resting on the spoke's surface, the
    thumb's last bones along it, and (with `avoid`) no part of the thumb inside the wheel.
    `obstacles` and `spoke` are KD trees in the hand's rest space. Returns (turn, proximal,
    distal, report)."""
    best = None
    rad = math.radians
    for mz in range(-30, 61, 10):
        for mx in range(-40, 41, 10):
            for my in range(-40, 41, 10):
                turn = (Matrix.Rotation(rad(mz), 3, "Z") @ Matrix.Rotation(rad(mx), 3, "X") @ Matrix.Rotation(rad(my), 3, "Y"))
                for curl in (0, 15, 30, 45, 60):
                    proximal, distal = rad(curl * 0.4), rad(curl * 0.6)
                    chain = thumb_chain(bones, turn, proximal, distal)
                    tip = chain[3].lerp(chain[4], THUMB_PAD)
                    found = spoke.find(tip)
                    if found[0] is None:
                        continue
                    contact = abs(found[2] - THUMB_RADIUS)
                    clearance = 1.0
                    if avoid:
                        for a, b in zip(chain[1:4], chain[2:4] + [tip]):
                            for k in range(7):
                                d = obstacles.find(a.lerp(b, k / 6))[2]
                                clearance = min(clearance, d)
                        if clearance < THUMB_RADIUS - 0.002:
                            continue
                    along = sum(1 for k in range(7) if spoke.find(chain[2].lerp(tip, k / 6))[2] < THUMB_RADIUS + 0.006)
                    score = contact * 100 - along * 0.2 + (abs(mz) + abs(mx) + abs(my) + curl) * 0.002
                    if best is None or score < best[0]:
                        best = (score, turn, proximal, distal, dict(tip_gap_mm=round((found[2] - THUMB_RADIUS) * 1000, 2), along=along,
                                                                     clearance_mm=round((clearance - THUMB_RADIUS) * 1000, 2) if avoid else None,
                                                                     metacarpal_deg=(mz, mx, my), curl_deg=curl))
    if best is None:
        raise SystemExit("no thumb pose rests on the spoke without entering the wheel")
    return best[1], best[2], best[3], best[4]


def main(args):
    hand_path, wheel_path, points_path, out = args[:4]
    grip_angle = math.radians(float(option(args, "--grip-angle", 25)))
    bar_tilt = math.radians(float(option(args, "--bar-tilt", 28)))
    wrist_turn = math.radians(float(option(args, "--wrist-turn", 20)))
    tube_radius = float(option(args, "--tube-radius", 0.015))
    tube_x, tube_z = (float(v) for v in option(args, "--tube-centre", "0.167,-0.005").split(","))
    os.makedirs(out, exist_ok=True)
    points = json.load(open(points_path))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=hand_path)
    arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    hand = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    bones = arm.data.bones

    # The tube lies against the palm across the base of the fingers.
    bar_y = sum(bones[f"{f}_Proximal_R"].head_local.y for f in FINGERS) / 4 + 0.012
    palm = [hand.matrix_world @ v.co for v in hand.data.vertices]
    palm_x = min(p.x for p in palm if abs(p.y - bar_y) < 0.004 and -0.045 < p.z < 0.025)
    bar = Vector((palm_x - tube_radius, bar_y))
    knuckles_z = [bones[f"{f}_Proximal_R"].head_local.z for f in FINGERS]
    bar_z = (max(knuckles_z) + min(knuckles_z)) / 2

    # Hand frame -> wheel frame. In the hand: the tube runs along b (tilted from the knuckle line
    # toward the fingers on the index side), the palm faces -x, and c = b x palm completes the
    # set. In the wheel at 3 o'clock: the tube runs up (+y), the palm faces in (-x), c goes to +z.
    b = Vector((0, math.sin(bar_tilt), math.cos(bar_tilt)))
    palm_n = Vector((-1, 0, 0))
    c = b.cross(palm_n)
    hand_axes = Matrix((palm_n, b, c)).transposed()
    wheel_axes = Matrix(((-1, 0, 0), (0, 1, 0), (0, 0, 1))).transposed()
    to_wheel = (wheel_axes @ hand_axes.transposed()).to_4x4()
    bar_h = Vector((bar.x, bar.y, bar_z))
    tube_w = Vector((tube_x, 0, tube_z))
    place = (
        Matrix.Rotation(grip_angle, 4, "Z")
        @ Matrix.Translation(tube_w)
        @ Matrix.Rotation(wrist_turn, 4, "Y")
        @ to_wheel
        @ Matrix.Translation(-bar_h)
    )

    # With --wheel-contact the fingers also stop on the wheel itself (the spoke where it joins the
    # rim, the button pods), and with --thumb-spoke the thumb is laid over the spoke at 3 o'clock;
    # both work against the wheel's surface brought into the hand's rest space.
    wheel_contact = "--wheel-contact" in args
    thumb_spoke = "--thumb-spoke" in args
    obstacles = spoke = None
    if wheel_contact or thumb_spoke:
        to_hand = place.inverted()
        surface = wheel_samples(wheel_path, points)
        obstacles = kd_tree([to_hand @ p for p in surface])
        # The spoke's driver-facing face and top edge at 3 o'clock: the thumb rests where the
        # driver sees it, not behind the spoke.
        spoke = kd_tree([to_hand @ p for p in surface if 0.08 < p.x < 0.135 and -0.03 < p.y < 0.035 and -0.017 < p.z < 0.01])

    report = {}
    for finger in FINGERS:
        names = [f"{finger}_{part}_R" for part in ("Proximal", "Intermediate", "Distal", "Tip")]
        heads = [bones[n].head_local.xy.copy() for n in names] + [bones[names[-1]].tail_local.xy.copy()]
        # Where the tilted tube crosses this finger's plane; cut at a slant it is an oval,
        # longer along the finger by 1 / cos(tilt).
        finger_z = bones[names[0]].head_local.z
        crossing = Vector((bar.x, bar.y + math.tan(bar_tilt) * (finger_z - bar_z)))
        zs = [bones[n].head_local.z for n in names] + [bones[names[-1]].tail_local.z]
        angles = solve_finger(
            heads,
            crossing,
            tube_radius / math.cos(bar_tilt) + FINGER_RADIUS[finger] + (SKIN_MARGIN if wheel_contact else 0.0),
            obstacles if wheel_contact else None,
            zs,
            FINGER_RADIUS[finger] + SKIN_MARGIN,
        )
        for name, angle in zip(names[:3], angles):
            pose_bone_about_world_z(arm, name, angle)
        report[finger] = [round(math.degrees(a)) for a in angles]
    thumb_tip = None
    if thumb_spoke:
        turn_m, proximal, distal, thumb_report = solve_thumb(bones, obstacles, spoke, avoid="--thumb-break" not in args)
        pose_bone_world(arm, THUMB[0], turn_m)
        pose_bone_about_world_z(arm, THUMB[1], proximal)
        pose_bone_about_world_z(arm, THUMB[2], distal)
        chain = thumb_chain(bones, turn_m, proximal, distal)
        thumb_tip = chain[3].lerp(chain[4], THUMB_PAD)
        report["Thumb"] = thumb_report
    else:
        # The thumb closes over the rim's top a little; its range is judged on the renders.
        pose_bone_about_world_z(arm, "Thumb_Proximal_R", math.radians(25))
        pose_bone_about_world_z(arm, "Thumb_Distal_R", math.radians(35))
    print("finger angles (deg):", report)

    bpy.context.view_layer.objects.active = hand
    for modifier in hand.modifiers:
        if modifier.type == "ARMATURE":
            bpy.ops.object.modifier_apply(modifier=modifier.name)
    wrist_h = bones["Wrist_R"].head_local.copy()
    bpy.data.objects.remove(arm)

    hand.data.transform(place @ hand.matrix_world)
    hand.matrix_world = Matrix.Identity(4)
    wrist_w = place @ wrist_h
    turn = place.to_3x3()
    forearm_w = (turn @ Vector((0, -1, 0))).normalized()
    back_w = (turn @ Vector((1, 0, 0))).normalized()
    width_w = (turn @ Vector((0, 0, 1))).normalized()
    cuff = cuff_mesh(wrist_w + turn @ Vector((-0.004, 0, -0.002)), forearm_w, width_w, back_w, "Cuff")

    centre, xw, yw, zw = wheel_frame(points)
    results = {}
    def mirrored(v, mirror):
        return Vector((v.x * mirror, v.y, v.z))

    for side, mirror in (("R", 1), ("L", -1)):
        pieces = {}
        for name, source in (("hand", hand), ("cuff", cuff)):
            ob = source.copy()
            ob.data = source.data.copy()
            bpy.context.collection.objects.link(ob)
            if mirror < 0:
                ob.data.transform(Matrix.Scale(-1, 4, (1, 0, 0)))
                ob.data.flip_normals()
            export_studs(ob, os.path.join(out, f"{name}_{side}.glb"))
            ob.name = f"Check_{name}_{side}"
            pieces[name] = ob
        results[side] = {
            "centre": studs(bounds_centre(pieces["hand"])),
            "cuffCentre": studs(bounds_centre(pieces["cuff"])),
            "wrist": studs(mirrored(wrist_w, mirror)),
            "forearm": [round(c, 4) for c in mirrored(forearm_w, mirror)],
            "back": [round(c, 4) for c in mirrored(back_w, mirror)],
        }
        if thumb_tip is not None:
            results[side]["thumbTip"] = studs(mirrored(place @ thumb_tip, mirror))

    results["fingerAngles"] = report
    results["gripAngleDeg"] = round(math.degrees(grip_angle), 2)
    results["barTiltDeg"] = round(math.degrees(bar_tilt), 2)
    results["wristTurnDeg"] = round(math.degrees(wrist_turn), 2)
    json.dump(results, open(os.path.join(out, "hands.json"), "w"), indent=1)
    print(json.dumps(results, indent=1))

    # Check renders: the wheel in its own frame with both hands, from the driver and from above.
    bpy.data.objects.remove(hand)
    bpy.data.objects.remove(cuff)
    bpy.ops.import_scene.gltf(filepath=wheel_path)
    wheel = next(o for o in bpy.context.scene.objects if o.type == "MESH" and "Steering" in o.name)
    basis = Matrix((xw, yw, zw)).to_4x4()
    wheel.data.transform(basis @ Matrix.Scale(1 / EXPORT_STUDS_PER_METRE, 4) @ Matrix.Translation(-centre * EXPORT_STUDS_PER_METRE) @ wheel.matrix_world)
    wheel.matrix_world = Matrix.Identity(4)
    for o in list(bpy.context.scene.objects):
        if o.type == "MESH" and o not in (wheel,) and not o.name.startswith("Check_"):
            bpy.data.objects.remove(o)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    scene.render.resolution_x, scene.render.resolution_y = 1200, 900
    for o in scene.objects:
        if o.name.startswith("Check_hand"):
            o.color = (0.85, 0.62, 0.5, 1)
        elif o.name.startswith("Check_cuff"):
            o.color = (0.08, 0.08, 0.09, 1)
    camera_data = bpy.data.cameras.new("Camera")
    camera = bpy.data.objects.new("Camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    # The renders are in the wheel's frame, where up is +y (not Blender's +z).
    views = {
        "driver": (Vector((0.0, 0.05, 0.6)), Vector((0, 0.02, 0))),
        "right_front": (Vector((0.45, 0.1, -0.35)), Vector((0.15, 0.07, 0))),
        "right_driver": (Vector((0.3, 0.12, 0.35)), Vector((0.15, 0.07, 0))),
        "above": (Vector((0.12, 0.5, 0.02)), Vector((0.12, 0.05, 0))),
    }
    for name, (eye, target) in views.items():
        forward = (target - eye).normalized()
        right = forward.cross(Vector((0, 1, 0))).normalized()
        up = right.cross(forward)
        camera.matrix_world = Matrix((
            (right.x, up.x, -forward.x, eye.x),
            (right.y, up.y, -forward.y, eye.y),
            (right.z, up.z, -forward.z, eye.z),
            (0, 0, 0, 1),
        ))
        camera_data.lens = 45
        scene.render.filepath = os.path.join(out, f"check_{name}.png")
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1 :])
