"""
Keyframes the driver's hands through the SVJ's start-up against the real cabin, bakes the wrist
paths and writes them into the game's config, with review renders.

    blender -b <svj_interior_v2_wheel.blend> --factory-startup -P tools/blender/startup_paths.py --
        <inputs.json> <Config/DriverStartup.luau> <out dir>

inputs.json names the measured pieces (absolute paths): seatWeld (SEAT_WELD.json, the seated R6
in the DriverSeat frame), restPose (REST_POSE.json), poses (hand_poses.py's poses.json and its
glb folder), grip (hand_grip.py's hands.json and glb folder), startup (Config/CarEntry's STARTUP
times), flap (the START flap's hinge and free edge, and the button, Blender metres) and seat (the
DriverSeat's origin in the blend, Blender metres).

Everything here works in the seat frame as the game sees it: x right, y up, z back, studs of
the 1.5x world. The cabin is moved into that frame first, so a key placed against the console
here is the key the game plays.

The right hand: off the thigh, the Point hand's index under the flap's free edge, lifting it as
the flap opens (keyed every 0.05 s along the edge's arc), forward onto the button, a push of
PRESS_DEPTH, back out from under the flap before it falls, then onto the wheel. The left hand:
off the thigh onto the wheel early, so the driver holds the wheel while starting. Poses are keyed
on an Empty with Blender's Bezier easing and baked every BAKE_STEP seconds.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

STUDS = 1.5 / 0.28
BAKE_STEP = 1 / 30
FPS = 60
# Config/DriverArms at character scale 1, and the driver's scale.
UPPER, LOWER, SHOULDER_INSET = 0.82, 0.77, 0.2
ELBOW_BIAS = Vector((0.3, -0.3, 0))
DRIVER_SCALE = 1.5 / 1.75
# How far the index pushes START (studs: 4 mm).
PRESS_DEPTH = 0.004 * STUDS
# Wrists stay this far inside the arm's reach.
REACH_SHARE = 0.96
# How far below the flap's underside the index's end rides, metres.
FINGER_UNDER = 0.006


def option(args, name, default):
    return args[args.index(name) + 1] if name in args else default


class Seat:
    """Blender metres of the car blend <-> the seat frame in studs."""

    def __init__(self, origin):
        self.origin = Vector(origin)
        self.turn = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))

    def point(self, p):
        return (self.turn @ (Vector(p) - self.origin)) * STUDS

    def vector(self, v):
        return self.turn @ Vector(v)

    def matrix(self):
        return Matrix.Scale(STUDS, 4) @ self.turn.to_4x4() @ Matrix.Translation(-self.origin)


def frame(position, x, y, z):
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = position
    return m


def look_frame(position, z_axis, up):
    z = z_axis.normalized()
    y = (up - z * up.dot(z)).normalized()
    return frame(position, y.cross(z), y, z)


def from_quaternion(position, q):
    m = Quaternion(q).to_matrix().to_4x4()
    m.translation = Vector(position)
    return m


def shoulder_point(sign, seat_weld):
    joint = Vector(seat_weld["robloxSit"]["pointsInSeat"]["rightShoulder"])
    return Vector((sign * (abs(joint.x) - SHOULDER_INSET * DRIVER_SCALE), joint.y, joint.z))


def elbow(shoulder, wrist, along, sign):
    """Controllers/DriverArms' elbow: bent toward where the forearm would lie straight down the
    hand's axis, nudged out and down."""
    upper, lower = UPPER * DRIVER_SCALE, LOWER * DRIVER_SCALE
    to_wrist = wrist - shoulder
    distance = min(max(to_wrist.length, abs(upper - lower) + 1e-6), upper + lower - 1e-6)
    bend = math.acos(max(-1, min(1, (upper * upper + distance * distance - lower * lower) / (2 * upper * distance))))
    pole = (wrist + along * lower - shoulder).normalized() + Vector((sign * ELBOW_BIAS.x, ELBOW_BIAS.y, ELBOW_BIAS.z))
    unit = to_wrist.normalized()
    out = (pole - unit * pole.dot(unit)).normalized()
    return shoulder + unit * (upper * math.cos(bend)) + out * (upper * math.sin(bend)), distance


def aimed(tip_target, tip_offset, shoulder, sign, roll, up=Vector((0, 1, 0))):
    """A wrist frame whose index tip lands on `tip_target` with the hand in line with the forearm
    the arm controller would draw: the hand's axis set from the elbow, three passes."""
    z = (shoulder - tip_target).normalized()
    m = None
    for _ in range(4):
        m = look_frame(Vector(), z, up)
        m = m @ Matrix.Rotation(roll, 4, "Z")
        wrist = tip_target - m.to_3x3() @ tip_offset
        joint, _ = elbow(shoulder, wrist, z, sign)
        z = (z + (joint - wrist).normalized()).normalized()
    m.translation = tip_target - m.to_3x3() @ tip_offset
    return m


def tip_of(m, tip_offset):
    return m.to_3x3() @ tip_offset + m.translation


class Flap:
    """The START flap: turns about its hinge line (seat x) to lift its free edge."""

    def __init__(self, seat, data, angle):
        self.hinge = seat.point(data["hinge"])
        self.edge = seat.point(data["edgeUnder"])
        self.button = seat.point(data["buttonTop"])
        self.normal = seat.vector(data["consoleNormal"]).normalized()
        self.angle = angle

    def turned(self, point, openness):
        # Opening lifts the free edge, which lies behind the hinge (+z): about seat x by -angle.
        return self.hinge + Matrix.Rotation(-self.angle * openness, 3, "X") @ (point - self.hinge)


def openness(t, startup):
    move = startup["flapMove"]
    if t < startup["flapDownAt"]:
        return max(0.0, min(1.0, (t - (startup["flapUpAt"] - move)) / move))
    return max(0.0, min(1.0, 1 - (t - startup["flapDownAt"]) / move))


def right_keys(inputs, seat_weld, rest, flap, startup, tip, grip_frame):
    shoulder = shoulder_point(1, seat_weld)
    rest_m = from_quaternion(rest["wrist"], rest["rotation"])
    keys = [(0.0, rest_m)]
    lifted = rest_m.copy()
    lifted.translation = rest_m.translation + Vector((0.05, 0.16, -0.05))
    keys.append((0.15, lifted))
    # The index's end sits on the finger's centre line: 6 mm under the edge puts its top on it.
    under = flap.edge - flap.normal * FINGER_UNDER * STUDS
    start = startup["flapUpAt"] - startup["flapMove"]
    roll_lift, roll_press = math.radians(-35), math.radians(-10)
    approach = under + Vector((0.0, -0.02, 0.12)) * STUDS
    keys.append((0.45, aimed(approach + Vector((0.0, 0.25, 0.25)), tip, shoulder, 1, roll_lift)))
    keys.append((start - 0.12, aimed(approach, tip, shoulder, 1, roll_lift)))
    # Under the free edge from just before it starts to lift, then riding it up.
    steps = 6
    for k in range(steps + 1):
        t = start - 0.03 + (startup["flapMove"] + 0.03) * k / steps
        contact = flap.turned(under, openness(t, startup))
        keys.append((t, aimed(contact, tip, shoulder, 1, roll_lift)))
    above = flap.button + flap.normal * 0.035 * STUDS
    on = flap.button + flap.normal * 0.004 * STUDS
    pushed = on - flap.normal * PRESS_DEPTH
    press_at = startup["pressAt"]
    keys.append((startup["flapUpAt"] + 0.12, aimed(above, tip, shoulder, 1, roll_press)))
    keys.append((press_at - 0.16, aimed(on, tip, shoulder, 1, roll_press)))
    keys.append((press_at - 0.04, aimed(pushed, tip, shoulder, 1, roll_press)))
    keys.append((press_at + 0.08, aimed(pushed, tip, shoulder, 1, roll_press)))
    keys.append((press_at + 0.2, aimed(above, tip, shoulder, 1, roll_press)))
    # Out from under the flap, back past its free edge, before it falls.
    clear = flap.turned(flap.edge, 1.0) + Vector((0.0, 0.03, 0.06)) * STUDS
    keys.append((startup["flapDownAt"] - 0.08, aimed(clear, tip, shoulder, 1, roll_lift)))
    wheel_at = startup["wheelAt"]
    mid = grip_frame.translation.lerp(clear, 0.45) + Vector((0, 0.25, 0.2))
    keys.append((wheel_at - 0.45, look_frame(mid, grip_frame.col[2].xyz.lerp((shoulder - mid).normalized(), 0.5), grip_frame.col[1].xyz)))
    keys.append((wheel_at, grip_frame))
    shapes = [(0.0, "Rest"), (0.2, "Point"), (wheel_at - 0.4, "Grip")]
    return keys, shapes, wheel_at - 0.5


def left_keys(inputs, seat_weld, rest, grip_frame, done_at):
    rest_m = from_quaternion(rest["wrist"], rest["rotation"])
    keys = [(0.0, rest_m)]
    lifted = rest_m.copy()
    lifted.translation = rest_m.translation + Vector((-0.05, 0.16, -0.05))
    keys.append((0.25, lifted))
    mid = rest_m.translation.lerp(grip_frame.translation, 0.55) + Vector((-0.1, 0.12, 0.1))
    keys.append((0.6, look_frame(mid, grip_frame.col[2].xyz.lerp(rest_m.col[2].xyz, 0.4), grip_frame.col[1].xyz)))
    keys.append((done_at, grip_frame))
    shapes = [(0.0, "Rest"), (0.4, "Grip")]
    return keys, shapes, 0.55


def key_empty(name, keys):
    empty = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(empty)
    empty.rotation_mode = "QUATERNION"
    previous = None
    for t, m in keys:
        loc, rot, _ = m.decompose()
        if previous is not None and previous.dot(rot) < 0:
            rot = -rot
        previous = rot
        empty.location = loc
        empty.rotation_quaternion = rot
        frame_no = t * FPS
        empty.keyframe_insert("location", frame=frame_no)
        empty.keyframe_insert("rotation_quaternion", frame=frame_no)
    # Factory settings key with Bezier interpolation and auto-clamped handles: eased, no overshoot.
    return empty


def bake(empty, finish):
    scene = bpy.context.scene
    samples = []
    count = int(round(finish / BAKE_STEP))
    for k in range(count + 1):
        t = min(k * BAKE_STEP, finish)
        scene.frame_set(int(math.floor(t * FPS)), subframe=(t * FPS) % 1)
        m = empty.matrix_world.copy()
        loc, rot, _ = m.decompose()
        samples.append((t, loc, rot.normalized()))
    return samples


def check_reach(samples, shoulder, label):
    worst = 0.0
    for _, loc, _ in samples:
        worst = max(worst, (loc - shoulder).length / ((UPPER + LOWER) * DRIVER_SCALE))
    print(f"{label}: furthest wrist at {worst:.3f} of the arm's reach")
    return worst


def luau_number(value):
    text = f"{value:.5f}".rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def write_config(path, tracks, meshes, cuff, about, made_against):
    lines = [
        "--!strict",
        "--[[",
        "\tThe driver's hands through the start-up, keyed in Blender against the SVJ's console, START",
        "\tflap and wheel and baked by tools/blender/startup_paths.py, which writes this file: do not",
        "\tedit by hand, re-run the script (docs/pipelines/DRIVER_HANDS.md, section 8).",
        "",
        "\tA key is { seconds after the start key, x, y, z, qw, qx, qy, qz }: the wrist frame in the",
        "\tdriver's seat frame (the DriverSeat part: x right, y up, z back; metres), whose z axis runs up",
        "\tthe forearm and y out of the back of the hand. The left hand's keys are its own (not mirrored).",
        f"\t{about}",
        "]]",
        'export type Shape = "Rest" | "Point" | "Grip"',
        "export type Point = { x: number, y: number, z: number }",
        "export type Key = { number }",
        "export type ShapeChange = { at: number, shape: Shape }",
        "export type Track = {",
        "\tkeys: { Key },",
        "\tshapes: { ShapeChange },",
        "\t-- From here the path bends toward the hand's live grip on the wheel, reached at the last key.",
        "\tgripFrom: number,",
        "}",
        "",
        "export type DriverStartup = {",
        "\tRIGHT: Track,",
        "\tLEFT: Track,",
        "\t-- The right hand's posed meshes' centres in the wrist frame, metres (hand_poses.py); the left",
        "\t-- hand mirrors x.",
        "\tMESHES: { Rest: Point, Point: Point },",
        "\tCUFF: Point,",
        "\t-- What the keys were made against, for the specs: the Point hand's index tip in its wrist",
        "\t-- frame; START's top face, the console's normal there and the push; the flap's hinge line",
        "\t-- (along x) and the point under its free edge the index rides (seat frame, metres).",
        "\tFINGERTIP: Point,",
        "\tBUTTON: { top: Point, normal: Point, depth: number },",
        "\tFLAP: { hinge: Point, edge: Point },",
        "}",
        "",
    ]
    for name, (samples, shapes, grip_from) in tracks.items():
        lines.append(f"local {name}: Track = {{")
        lines.append("\tkeys = {")
        for t, loc, rot in samples:
            values = [t, loc.x / STUDS, loc.y / STUDS, loc.z / STUDS, rot.w, rot.x, rot.y, rot.z]
            lines.append("\t\t{ " + ", ".join(luau_number(v) for v in values) + " },")
        lines.append("\t},")
        lines.append("\tshapes = {")
        for at, shape in shapes:
            lines.append(f'\t\t{{ at = {luau_number(at)}, shape = "{shape}" }},')
        lines.append("\t},")
        lines.append(f"\tgripFrom = {luau_number(grip_from)},")
        lines.append("}")
        lines.append("")

    def point(p):
        return f"table.freeze({{ x = {luau_number(p[0])}, y = {luau_number(p[1])}, z = {luau_number(p[2])} }})"

    lines += [
        "local DriverStartup: DriverStartup = table.freeze({",
        "\tRIGHT = table.freeze(RIGHT),",
        "\tLEFT = table.freeze(LEFT),",
        "\tMESHES = table.freeze({",
        f"\t\tRest = {point(meshes['Rest'])},",
        f"\t\tPoint = {point(meshes['Point'])},",
        "\t}),",
        f"\tCUFF = {point(cuff)},",
        f"\tFINGERTIP = {point(made_against['fingertip'])},",
        "\tBUTTON = table.freeze({",
        f"\t\ttop = {point(made_against['button'])},",
        f"\t\tnormal = {point(made_against['normal'])},",
        f"\t\tdepth = {luau_number(made_against['depth'])},",
        "\t}),",
        "\tFLAP = table.freeze({",
        f"\t\thinge = {point(made_against['hinge'])},",
        f"\t\tedge = {point(made_against['edge'])},",
        "\t}),",
        "})",
        "",
        "return DriverStartup",
        "",
    ]
    with open(path, "wb") as handle:
        handle.write("\n".join(lines).encode("utf-8"))


def import_glb(path, name):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    added = [o for o in bpy.context.scene.objects if o not in before]
    mesh = next(o for o in added if o.type == "MESH")
    mesh.data.transform(mesh.matrix_world)
    mesh.parent = None
    mesh.matrix_world = Matrix.Identity(4)
    # Blender axes after the glTF import are (-x, z, y) of the Roblox axes the mesh was made in.
    mesh.data.transform(Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1))))
    for o in added:
        if o is not mesh:
            bpy.data.objects.remove(o)
    mesh.name = name
    return mesh


def main(args):
    inputs_path, config_path, out = args[:3]
    inputs = json.load(open(inputs_path))
    os.makedirs(out, exist_ok=True)
    seat = Seat(inputs["seat"])
    seat_weld = json.load(open(inputs["seatWeld"]))
    rest = json.load(open(inputs["restPose"]))
    poses = json.load(open(inputs["poses"]))
    grip = json.load(open(inputs["grip"]))
    startup = inputs["startup"]
    flap = Flap(seat, inputs["flap"], math.radians(startup["flapAngleDeg"]))

    # The cabin into the seat frame.
    to_seat = seat.matrix()
    for ob in list(bpy.data.objects):
        if ob.type == "MESH":
            ob.data.transform(ob.matrix_world)
            ob.parent = None
            ob.matrix_world = Matrix.Identity(4)
            ob.data.transform(to_seat)
        elif ob.type != "MESH":
            bpy.data.objects.remove(ob)

    # The wheel's frame as the rig rests it: A's measured pivot, lifted by steeringWheelLift.
    pivot = seat_weld["car"]["steeringPivotInSeat"]
    rows = pivot[3:]
    wheel = Matrix(((rows[0], rows[1], rows[2]), (rows[3], rows[4], rows[5]), (rows[6], rows[7], rows[8]))).to_4x4()
    wheel.translation = Vector(pivot[:3]) + Vector((0, inputs["steeringWheelLift"] * STUDS, 0))

    def grip_wrist(side):
        sign = 1 if side == "R" else -1
        g = grip[side]
        z = Vector(g["forearm"]).normalized()
        y = Vector(g["back"])
        y = (y - z * y.dot(z)).normalized()
        return wheel @ frame(Vector(g["wrist"]), y.cross(z), y, z), sign

    tip = Vector(poses["shapes"]["Point"]["R"]["fingertip"])
    right_grip, _ = grip_wrist("R")
    left_grip, _ = grip_wrist("L")
    r_keys, r_shapes, r_grip_from = right_keys(inputs, seat_weld, rest["right"], flap, startup, tip, right_grip)
    l_keys, l_shapes, l_grip_from = left_keys(inputs, seat_weld, rest["left"], left_grip, startup["leftOnWheelAt"])
    scene = bpy.context.scene
    scene.render.fps = FPS
    right_empty = key_empty("RightWrist", r_keys)
    left_empty = key_empty("LeftWrist", l_keys)
    right = bake(right_empty, r_keys[-1][0])
    left = bake(left_empty, l_keys[-1][0])
    # The lift is keyed on the edge's arc; the bake must not wander off it between keys.
    worst_edge = 0.0
    lift_from = startup["flapUpAt"] - startup["flapMove"]
    for t, loc, rot in right:
        if lift_from <= t <= startup["flapUpAt"]:
            contact = flap.turned(flap.edge - flap.normal * FINGER_UNDER * STUDS, openness(t, startup))
            worst_edge = max(worst_edge, (tip_of(from_quaternion(loc, rot), tip) - contact).length)
    reach_r = check_reach(right, shoulder_point(1, seat_weld), "right")
    reach_l = check_reach(left, shoulder_point(-1, seat_weld), "left")
    pressed_tip = None
    for t, loc, rot in right:
        if abs(t - startup["pressAt"]) < BAKE_STEP / 2:
            pressed_tip = tip_of(from_quaternion(loc, rot), tip)
    report = {
        "rightKeys": len(right),
        "leftKeys": len(left),
        "furthestReachShare": {"right": round(reach_r, 4), "left": round(reach_l, 4)},
        "edgeFollowWorstStuds": round(worst_edge, 4),
        "edgeFollowWorstMm": round(worst_edge / STUDS * 1000, 2),
        "buttonTop": [round(c, 4) for c in flap.button],
        "fingertipAtPress": [round(c, 4) for c in pressed_tip] if pressed_tip else None,
        "fingertipBelowButtonTopMm": round((flap.button - pressed_tip).dot(flap.normal) / STUDS * 1000, 2) if pressed_tip else None,
        "flapHinge": [round(c, 4) for c in flap.hinge],
        "fingertip": [round(c, 4) for c in tip],
        "buttonSeat": [round(c, 4) for c in flap.button],
        "consoleNormal": [round(c, 4) for c in flap.normal],
    }
    assert reach_r <= REACH_SHARE and reach_l <= REACH_SHARE, report
    meshes = {name: [c / STUDS for c in poses["shapes"][name]["R"]["centre"]] for name in ("Rest", "Point")}
    write_config(
        config_path,
        {"RIGHT": (right, r_shapes, r_grip_from), "LEFT": (left, l_shapes, l_grip_from)},
        meshes,
        [c / STUDS for c in poses["cuff"]["R"]],
        f"Baked every {BAKE_STEP:.4f} s; START pushed {PRESS_DEPTH / STUDS * 1000:.1f} mm.",
        {
            "fingertip": [c / STUDS for c in tip],
            "button": [c / STUDS for c in flap.button],
            "normal": list(flap.normal),
            "depth": PRESS_DEPTH / STUDS,
            "hinge": [c / STUDS for c in flap.hinge],
            "edge": [c / STUDS for c in flap.edge - flap.normal * FINGER_UNDER * STUDS],
        },
    )
    json.dump(report, open(os.path.join(out, "paths.json"), "w"), indent=1)
    print(json.dumps(report, indent=1))
    render_review(inputs, out, (right, r_shapes), (left, l_shapes), flap, startup, grip, seat_weld, seat)


def render_review(inputs, out, right_track, left_track, flap, startup, grip, seat_weld, seat):
    """Frames of the start-up from the cockpit eye and from beside the car: the cabin, the flap
    turned as the game turns it, the posed hands and the arms the controller would draw."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    scene.render.resolution_x, scene.render.resolution_y = 960, 600
    glb = inputs["posesDir"]
    shapes = {}
    for side in ("R", "L"):
        for shape in ("Rest", "Point"):
            shapes[(shape, side)] = import_glb(os.path.join(glb, f"hand_{shape}_{side}.glb"), f"{shape}_{side}")
        shapes[("Grip", side)] = import_glb(os.path.join(inputs["gripDir"], f"hand_{side}.glb"), f"Grip_{side}")
    skin = (0.85, 0.62, 0.5, 1)
    for obj in shapes.values():
        obj.color = skin
    base = {key: obj.data.copy() for key, obj in shapes.items()}
    flap_faces = None
    interior = next((o for o in bpy.data.objects if o.name.startswith("Interior")), None)
    camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.data.clip_start = 0.02
    head = Vector(seat_weld["robloxSit"]["pointsInSeat"]["headCentre"])
    eye = head + Vector((0, 0.07 * STUDS, 0))
    # The cockpit eye looking down at the console (the game hides the head and torso there), the
    # passenger seat looking across at the driver, and the flap close up.
    views = {
        "cockpit": (eye, eye + Vector((0.55, -0.85, -1.0)), 30, False),
        "passenger": (Vector((4.3, 2.9, 0.4)), Vector((0.9, 1.2, -1.1)), 22, True),
        "flap": (Vector((1.35, 1.75, -0.55)), Vector((2.0, 0.9, -1.45)), 40, True),
    }
    arms = []
    body = driver_body(seat_weld, startup)

    def tube(name, a, b, radius, colour):
        mesh = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=radius, radius2=radius, depth=(b - a).length)
        bm.to_mesh(mesh)
        obj = bpy.data.objects.new(name, mesh)
        scene.collection.objects.link(obj)
        direction = (b - a).normalized()
        obj.matrix_world = Matrix.Translation((a + b) / 2) @ direction.to_track_quat("Z", "Y").to_matrix().to_4x4()
        obj.color = colour
        arms.append(obj)

    moments = [0.0, 0.5, startup["flapUpAt"] - startup["flapMove"] + 0.01, startup["flapUpAt"], startup["pressAt"], startup["flapDownAt"] + 0.12, startup["wheelAt"] - 0.3, startup["wheelAt"]]
    for index, t in enumerate(moments):
        for obj in arms:
            bpy.data.objects.remove(obj)
        arms.clear()
        for side, (samples, track_shapes), sign in (("R", right_track, 1), ("L", left_track, -1)):
            t_side = min(t, samples[-1][0])
            sample = min(samples, key=lambda s: abs(s[0] - t_side))
            m = from_quaternion(sample[1], sample[2])
            shape = "Rest"
            for at, name in track_shapes:
                if t >= at:
                    shape = name
            for (name, s), obj in shapes.items():
                if s != side:
                    continue
                obj.hide_render = name != shape
                obj.data = base[(name, s)].copy()
                if name == "Grip":
                    g = grip[side]
                    z = Vector(g["forearm"]).normalized()
                    y = Vector(g["back"])
                    y = (y - z * y.dot(z)).normalized()
                    grip_local = frame(Vector(g["wrist"]), y.cross(z), y, z)
                    obj.data.transform(m @ grip_local.inverted())
                else:
                    obj.data.transform(m)
            shoulder = shoulder_point(sign, seat_weld)
            joint, _ = elbow(shoulder, m.translation, m.col[2].xyz, sign)
            sleeve = (0.08, 0.08, 0.09, 1)
            tube(f"Upper{side}", shoulder, joint, 0.28, sleeve)
            tube(f"Lower{side}", joint, m.translation, 0.21, sleeve)
        open_now = openness(t, startup)
        if interior is not None and flap_faces is None:
            flap_faces = flap_mesh(interior, inputs["flap"]["bounds"], seat)
        if flap_faces is not None:
            flap_faces.matrix_world = Matrix.Translation(flap.hinge) @ Matrix.Rotation(-flap.angle * open_now, 4, "X") @ Matrix.Translation(-flap.hinge)
        for name, (eye_at, target, lens, show_body) in views.items():
            for obj in body:
                obj.hide_render = not show_body and obj.name in ("Torso", "Head")
            forward = (target - eye_at).normalized()
            right_axis = forward.cross(Vector((0, 1, 0))).normalized()
            up = right_axis.cross(forward)
            camera.matrix_world = Matrix(
                (
                    (right_axis.x, up.x, -forward.x, eye_at.x),
                    (right_axis.y, up.y, -forward.y, eye_at.y),
                    (right_axis.z, up.z, -forward.z, eye_at.z),
                    (0, 0, 0, 1),
                )
            )
            camera.data.lens = lens
            scene.render.filepath = os.path.join(out, f"startup_{index}_{t:.2f}s_{name}.png")
            bpy.ops.render.render(write_still=True)


def driver_body(seat_weld, startup):
    """The seated R6's torso and head as Roblox's sit holds them, and the legs Rules/DriverLegs
    draws while the car starts (the right foot holding the brake), for the renders."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import rest_pose

    objects = []
    points = seat_weld["robloxSit"]["pointsInSeat"]
    for name, centre, size in (
        ("Torso", points["torsoCentre"], (1.714, 1.714, 0.857)),
        ("Head", points["headCentre"], (1.714, 0.857, 0.857)),
    ):
        bpy.ops.mesh.primitive_cube_add(size=1, location=centre)
        obj = bpy.context.active_object
        obj.scale = size
        obj.name = name
        obj.color = (0.45, 0.47, 0.52, 1) if name == "Torso" else (0.85, 0.62, 0.5, 1)
        objects.append(obj)
    trouser = (0.13, 0.14, 0.16, 1)

    def limb(name, a, b, radius):
        mesh = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=14, radius1=radius, radius2=radius, depth=(b - a).length)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        obj.matrix_world = Matrix.Translation((a + b) / 2) @ (b - a).normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
        obj.color = trouser
        objects.append(obj)

    brake_angle = math.radians(12) * startup["brake"]
    torso = Vector(points["torsoCentre"])
    for sign in (1, -1):
        hip_studs = torso + Vector((sign * rest_pose.HIP[0], rest_pose.HIP[1], rest_pose.HIP[2])) * DRIVER_SCALE
        hip = tuple(hip_studs / STUDS)
        if sign > 0:
            brake = rest_pose.BRAKE
            ball = rest_pose.turned(brake["hinge"], brake["ball"], brake_angle)
            heel = brake["heel"]
        else:
            heel, ball = rest_pose.FOOTREST["heel"], rest_pose.FOOTREST["ball"]
        knee, ankle = rest_pose.leg(hip, heel, ball, rest_pose.KNEE_TOWARD[sign])
        hip_v, knee_v, ankle_v = Vector(hip) * STUDS, Vector(knee) * STUDS, Vector(ankle) * STUDS
        limb(f"Thigh{sign}", hip_v, knee_v, 0.075 * STUDS)
        limb(f"Shin{sign}", knee_v, ankle_v, 0.057 * STUDS)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.06 * STUDS, location=knee_v)
        bpy.context.active_object.color = trouser
        objects.append(bpy.context.active_object)
        sole = (Vector(ball) - Vector(heel)).normalized()
        toe = Vector(heel) + sole * 0.285
        limb(f"Shoe{sign}", Vector(heel) * STUDS, toe * STUDS, 0.045 * STUDS)
    return objects


def flap_mesh(interior, bounds, seat):
    """Moves the flap's island (every face whose vertices all lie inside its measured bounds,
    Blender metres, plus a millimetre) out of the cabin mesh into its own object; renders only."""
    corners = [seat.point((x, y, z)) for x in (bounds[0][0], bounds[1][0]) for y in (bounds[0][1], bounds[1][1]) for z in (bounds[0][2], bounds[1][2])]
    lo = Vector([min(c[i] for c in corners) for i in range(3)]) - Vector((1, 1, 1)) * 0.001 * STUDS
    hi = Vector([max(c[i] for c in corners) for i in range(3)]) + Vector((1, 1, 1)) * 0.001 * STUDS
    bm = bmesh.new()
    bm.from_mesh(interior.data)
    bm.faces.ensure_lookup_table()
    picked = [f for f in bm.faces if all(lo.x <= v.co.x <= hi.x and lo.y <= v.co.y <= hi.y and lo.z <= v.co.z <= hi.z for v in f.verts)]
    if not picked:
        bm.free()
        return None
    copy = bmesh.new()
    lookup = {}
    for f in picked:
        verts = []
        for v in f.verts:
            if v not in lookup:
                lookup[v] = copy.verts.new(v.co)
            verts.append(lookup[v])
        try:
            copy.faces.new(verts)
        except ValueError:
            pass
    bmesh.ops.delete(bm, geom=picked, context="FACES")
    bm.to_mesh(interior.data)
    bm.free()
    data = bpy.data.meshes.new("Flap")
    copy.to_mesh(data)
    copy.free()
    obj = bpy.data.objects.new("Flap", data)
    bpy.context.scene.collection.objects.link(obj)
    obj.color = (0.75, 0.05, 0.05, 1)
    return obj


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1 :])
