"""
The data-driven half of tools/blender/startup_paths.py: keyframes the driver's hands through a
car's start-up from a list of the controls the right hand works, the game's own times and hinges
(games/drive-lab/tools/startup_config.luau) and the cabin's meshes, so a moved control or a
changed time is a re-run, never a re-author. startup_paths.py hands an inputs file with a
"sequence" here; the SVJ's flap keeps its own path there.

What a touch does, by its "grab":
- "pinch": the Pinch hand holds the control's grip (its top TOP_GRIP of mesh) between thumb and
  index, with the blade's out side down the control's axis, and turns with it about its hinge as
  the game turns it: a key;
- "edge": the Point hand's index end rides FINGER_UNDER (or the touch's "under") behind the free edge (the vertices
  farthest from the hinge line) while the control opens: a guard;
- "tip": the same at the vertices farthest from the pivot: a toggle's lever;
- "press": the index end onto the button's face (its vertices nearest the driver along the
  press axis), held while the starter turns, then away.

Each touch is keyed every RIDE_STEP along the control's arc from just before it moves until it
stops, so the bake cannot cut a corner; between touches the hand travels through a key clear of
both controls. The left hand goes to the wheel as the SVJ's does. Keys are a Blender Empty's,
Bezier eased and baked every BAKE_STEP seconds, as for the SVJ.

Writes the car's StartupPaths.luau (typed by Config/DriverStartup, with TOUCHES for the specs),
paths.json (the bake, the touches and the measured contact for tools/anim/startup_check.py) and
quarter-speed review frames (render_frames).
"""

import json
import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

from startup_paths import (
    BAKE_STEP,
    FPS,
    REACH_SHARE,
    STUDS,
    Seat,
    aimed,
    elbow,
    frame,
    from_quaternion,
    import_glb,
    key_empty,
    look_frame,
    luau_number,
    tip_of,
)

RIDE_STEP = 0.025
# How far behind an edge or a lever's end the index's end rides, metres (its top on the edge).
FINGER_UNDER = 0.006
# How much of a pinched control, from its top, is its grip, metres: above a key's stem.
TOP_GRIP = 0.014
# How long the index holds the button in while the starter turns, seconds.
PRESS_HOLD = 0.5
# A press: from this far off the face, metres.
PRESS_FROM = 0.003
# The open hand comes onto the rim from this offset off the grip (wheel frame, metres: out from
# the hub, toward the driver), then closes.
RIM_APPROACH = (0.04, 0.0, 0.03)


def vec(v):
    return Vector(v)


def bake_at(empty, finish, step, extra):
    """The Empty's frame every `step` seconds and at each of `extra` (a control starting or
    stopping: the game samples the keys with a cubic, which rounds a corner between keys)."""
    scene = bpy.context.scene
    count = int(round(finish / step))
    times = sorted({round(min(k * step, finish), 5) for k in range(count + 1)} | {round(t, 5) for t in extra if 0 < t < finish})
    samples = []
    for t in times:
        scene.frame_set(int(math.floor(t * FPS)), subframe=(t * FPS) % 1)
        loc, rot, _ = empty.matrix_world.copy().decompose()
        samples.append((t, loc, rot.normalized()))
    return samples


def turned(point, pivot, axis, angle):
    """`point` turned about the line through `pivot` along `axis`, as Rules/Hinge.rotate."""
    return pivot + Matrix.Rotation(angle, 3, axis) @ (point - pivot)


def control_openness(t, move):
    """Rules/CarEntry.controlOpenness for a running engine."""
    back = move.get("back")
    if back is None or t < back:
        return max(0.0, min(1.0, (t - (move["at"] - move["move"])) / move["move"]))
    return max(0.0, min(1.0, 1 - (t - back) / move["move"]))


class Arm:
    def __init__(self, driver, sign):
        side = "R" if sign > 0 else "L"
        self.sign = sign
        self.shoulder = vec(driver["shoulders"][side])
        self.lengths = (driver["upper"], driver["lower"], vec(driver["elbowBias"]))
        self.reach = driver["upper"] + driver["lower"]


def load_cabin(path, seat):
    """The cabin dump (numpy: vertices in the car blend's metres, triangles, an object index per
    triangle, object names) as Blender objects in the seat frame, studs. Returns {name: object}."""
    data = np.load(path)
    verts, tris, owner, names = data["vertices"], data["triangles"], data["object"], list(data["names"])
    to_seat = seat.matrix()
    objects = {}
    for index, name in enumerate(names):
        faces = tris[owner == index]
        if len(faces) == 0:
            continue
        used = np.unique(faces)
        remap = {int(v): k for k, v in enumerate(used)}
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata([tuple(verts[v]) for v in used], [], [tuple(remap[int(v)] for v in f) for f in faces])
        mesh.transform(to_seat)
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        objects[name] = obj
    return objects


def points_of(obj):
    return [obj.matrix_world @ v.co for v in obj.data.vertices]


def mean(points):
    return sum(points, Vector()) / len(points)


def extreme(points, key, band):
    top = max(key(p) for p in points)
    return mean([p for p in points if key(p) > top - band])


def principal_axes(points):
    """Unit axes of a point set, from the most spread to the least."""
    a = np.array([tuple(p) for p in points])
    a = a - a.mean(0)
    _, _, rows = np.linalg.svd(a, full_matrices=False)
    return [Vector(r) for r in rows]


class Touch:
    """One control the hand works: where it touches at rest, how that point moves, when."""

    def __init__(self, item, cabin, config, manifest_seat):
        self.item = item
        self.grab = item["grab"]
        self.shape = item.get("shape", "Pinch" if self.grab == "pinch" else "Point")
        self.roll = math.radians(item.get("rollDeg", -10))
        # The hand's axis is aimed from the shoulder moved by this much (metres), so the index can
        # come at a control from below the line to the shoulder.
        self.aim_from = vec(item.get("aimFrom", (0, 0, 0))) * STUDS
        name = item.get("control") or item.get("press")
        self.name = name
        points = points_of(cabin[item.get("part", name)])
        if self.grab == "press":
            pivot, axis = manifest_seat[name]
            self.press = axis.normalized()
            self.normal = -self.press
            self.point = extreme(points, lambda p: p.dot(self.normal), 0.001 * STUDS)
            self.start, self.end = config["pressAt"] - 0.04, config["pressAt"] + PRESS_HOLD
            self.move = None
            return
        hinge = config["controls"][name]
        self.pivot = vec(hinge["pivot"]) * STUDS
        self.axis = vec(hinge["axis"]).normalized()
        self.move = next(m for m in config["moves"] if m["control"] == name)
        self.start = self.move["at"] - self.move["move"]
        self.end = self.move["at"]
        if self.grab == "pinch":
            top = max(p.dot(self.axis) for p in points)
            grip = [p for p in points if p.dot(self.axis) > top - TOP_GRIP * STUDS]
            self.point = mean(grip)
            spread = principal_axes(grip)
            thin = spread[2] - self.axis * spread[2].dot(self.axis)
            self.blade = thin.normalized()
        else:
            if self.grab == "edge":
                along = lambda p: ((p - self.pivot) - self.axis * (p - self.pivot).dot(self.axis)).length
            else:
                along = lambda p: (p - self.pivot).length
            self.edge = extreme(points, along, 0.002 * STUDS)
            arm = self.edge - self.pivot
            sense = 1 if self.move["angle"] >= 0 else -1
            self.motion = (self.axis.cross(arm) * sense).normalized()
            # Behind the edge against its motion, or along "underDir" (seat frame) for a cover
            # whose underside is closed.
            off = -self.motion if "underDir" not in item else vec(item["underDir"]).normalized()
            self.point = self.edge + off * item.get("under", FINGER_UNDER) * STUDS

    def angle(self, t):
        return self.move["angle"] * control_openness(t, self.move)

    def contact(self, t):
        if self.move is None:
            return self.point
        return turned(self.point, self.pivot, self.axis, self.angle(t))


def pinch_frame(touch, pinch, arm, angle):
    """The Pinch hand's wrist frame on a turned grip: its thumb-to-index axis across the blade, the
    open side of the pinch down the control's axis, the side of the blade chosen so the forearm
    runs toward the shoulder at mid-turn."""
    point_h, across_h, out_h = pinch
    a1 = across_h.normalized()
    a2 = (out_h - a1 * out_h.dot(a1)).normalized()
    hand_axes = Matrix((a1, a2, a1.cross(a2))).transposed()
    mid = touch.move["angle"] / 2
    best = None
    for side in (1, -1):
        b1 = Matrix.Rotation(mid, 3, touch.axis) @ (touch.blade * side)
        b2 = -touch.axis
        b2 = (b2 - b1 * b2.dot(b1)).normalized()
        rot = Matrix((b1, b2, b1.cross(b2))).transposed() @ hand_axes.transposed()
        wrist = touch.contact(touch.start) - rot @ point_h
        toward = (arm.shoulder - wrist).normalized().dot(rot.col[2])
        if best is None or toward > best[0]:
            best = (toward, rot)
    rot = Matrix.Rotation(angle - mid, 3, touch.axis) @ best[1]
    m = rot.to_4x4()
    centre = turned(touch.point, touch.pivot, touch.axis, angle)
    m.translation = centre - rot @ point_h
    return m


def approach_frame(grip_frame, wheel, side_sign, offset=RIM_APPROACH):
    m = grip_frame.copy()
    x, y, z = offset
    m.translation = grip_frame.translation + wheel.to_3x3() @ Vector((side_sign * x, y, z)) * STUDS
    return m


def right_keys(sequence, touches, rest, grip_frame, wheel, tips, arm, config):
    """The right hand: from its start pose, every touch in order, then the wheel."""
    sign = arm.sign
    shoulder = arm.shoulder
    lengths = arm.lengths

    def point_at(target, touch):
        return aimed(target, tips["Point"], shoulder + touch.aim_from, sign, touch.roll, arm=lengths)

    if sequence.get("start", "rest") == "rest":
        start_m = from_quaternion(rest["wrist"], rest["rotation"])
        keys = [(0.0, start_m)]
        shapes = [(0.0, "Rest")]
        lifted = start_m.copy()
        lifted.translation = start_m.translation + vec(sequence.get("liftOff", (0.0, 0.06, 0.0))) * STUDS
        keys.append((0.15, lifted))
    else:
        keys = [(0.0, grip_frame)]
        shapes = [(0.0, "Grip")]
    previous_end = 0.15
    for index, touch in enumerate(touches):
        following = touches[index + 1].start if index + 1 < len(touches) else config["wheelAt"]
        # Off a control and onto the next within the time between them, never past it.
        lead = min(0.12, 0.45 * (touch.start - previous_end))
        trail = min(0.1, 0.45 * (following - touch.end))
        transit = touch.start - previous_end
        if touch.shape != shapes[-1][1]:
            shapes.append((previous_end + transit * 0.5, touch.shape))
        if touch.grab == "pinch":
            first = pinch_frame(touch, tips["pinch"], arm, 0.0)
            above = first.copy()
            above.translation = first.translation + touch.axis * touch.item.get("above", 0.04) * STUDS
            keys.append((touch.start - 0.15, above))
            t = touch.start - 0.03
            while t < touch.end + 0.05 + 1e-9:
                keys.append((round(t, 4), pinch_frame(touch, tips["pinch"], arm, touch.angle(t))))
                t += RIDE_STEP
            last = pinch_frame(touch, tips["pinch"], arm, touch.angle(touch.end))
            off = last.copy()
            off.translation = last.translation + touch.axis * 0.05 * STUDS
            keys.append((touch.end + 0.18, off))
            previous_end = touch.end + 0.18
        elif touch.grab == "press":
            face = touch.point
            press_at = config["pressAt"]
            above = face + touch.normal * 0.035 * STUDS
            near = face + touch.normal * PRESS_FROM * STUDS
            keys.append((press_at - 0.3, point_at(above, touch)))
            keys.append((press_at - 0.16, point_at(near, touch)))
            keys.append((press_at - 0.04, point_at(face, touch)))
            keys.append((press_at + PRESS_HOLD, point_at(face, touch)))
            keys.append((press_at + PRESS_HOLD + 0.12, point_at(above, touch)))
            previous_end = press_at + PRESS_HOLD + 0.12
        else:
            away = vec(touch.item["approach"]) if "approach" in touch.item else -touch.motion * 0.03 + Vector((0, 0, 0.03))
            pre = touch.contact(touch.start) + away * STUDS
            keys.append((touch.start - lead, point_at(pre, touch)))
            t = touch.start - 0.03
            while t < touch.end + 0.04 + 1e-9:
                keys.append((round(t, 4), point_at(touch.contact(t), touch)))
                t += RIDE_STEP
            # Back out from behind the edge, toward the driver and down, before the next reach.
            done = touch.contact(touch.end)
            back = done + vec(touch.item.get("backOut", (0, -0.015, 0.035))) * STUDS
            keys.append((touch.end + trail, point_at(back, touch)))
            previous_end = touch.end + trail
        # A key clear of both controls on the way to the next, when the touch asks for one.
        if "via" in touch.item:
            via = keys[-1][1].copy()
            via.translation = via.translation + vec(touch.item["via"]["offset"]) * STUDS
            keys.append((previous_end + touch.item["via"]["after"], via))
            previous_end += touch.item["via"]["after"]
    wheel_at = config["wheelAt"]
    approach = approach_frame(grip_frame, wheel, sign, sequence.get("rimApproach", {}).get("R", RIM_APPROACH))
    # Round behind the rim, hand already turned to grip it, then forward onto it.
    behind = approach.copy()
    behind.translation = approach.translation + vec(sequence.get("behindRim", {}).get("R", (0.02, -0.02, 0.1))) * STUDS
    keys.append((wheel_at - 0.45, behind))
    keys.append((wheel_at - 0.15, approach))
    keys.append((wheel_at, grip_frame))
    for (a, _), (b, _) in zip(keys, keys[1:]):
        assert b > a + 1e-6, f"keys out of order at {a} and {b}: the touches overlap in time"
    shapes.append((wheel_at - 0.45, "Rest"))
    shapes.append((wheel_at - 0.03, "Grip"))
    return keys, shapes, wheel_at - 0.5


def left_keys(sequence, rest, grip_frame, wheel):
    """The left hand: off the thigh, round to the rim's outside, open, then onto the grip."""
    done_at = sequence["leftOnWheelAt"]
    start_m = from_quaternion(rest["wrist"], rest["rotation"])
    lifted = start_m.copy()
    lifted.translation = start_m.translation + vec(sequence.get("leftLiftOff", (0.0, 0.06, 0.0))) * STUDS
    approach = approach_frame(grip_frame, wheel, -1, sequence.get("rimApproach", {}).get("L", RIM_APPROACH))
    behind = approach.copy()
    behind.translation = approach.translation + vec(sequence.get("behindRim", {}).get("L", (-0.02, -0.02, 0.1))) * STUDS
    # Straight up off the thigh first, so the way to the rim cannot swing the palm into a strap.
    clear = start_m.copy()
    clear.translation = start_m.translation + Vector((0, 0.03, 0)) * STUDS
    keys = [
        (0.0, start_m),
        (0.1, clear),
        (0.25, lifted),
        (done_at - 0.45, behind),
        (done_at - 0.15, approach),
        (done_at, grip_frame),
    ]
    shapes = [(0.0, "Rest"), (done_at - 0.02, "Grip")]
    return keys, shapes, done_at - 0.45


def manifest_points(manifest, names):
    """Manifest parts' pivots and axes in the seat frame (the manifest's Driver_HPoint is the seat)."""
    hpoint = manifest["points"]["Driver_HPoint"]
    out = {}
    for part in manifest["parts"]:
        if part["name"] in names:
            p, a = part["pivot"], part["axis"]
            pivot = Vector((p["right"] - hpoint["right"], p["up"] - hpoint["up"], -(p["forward"] - hpoint["forward"]))) * STUDS
            out[part["name"]] = (pivot, Vector((a["right"], a["up"], -a["forward"])))
    return out


def wheel_matrix(config):
    hub = config["steeringHub"]
    z = vec(hub["axis"]).normalized()
    x = Vector((1, 0, 0))
    x = (x - z * x.dot(z)).normalized()
    m = frame(vec(hub["pivot"]) * STUDS + Vector((0, config.get("steeringWheelLift", 0) * STUDS, 0)), x, z.cross(x), z)
    return m


def grip_wrist(grip, side, wheel):
    g = grip[side]
    z = Vector(g["forearm"]).normalized()
    y = Vector(g["back"])
    y = (y - z * y.dot(z)).normalized()
    return wheel @ frame(Vector(g["wrist"]), y.cross(z), y, z)


def write_paths(path, car, tracks, meshes, cuff, fingertip, button, touches, about):
    def point(p):
        return f"table.freeze({{ x = {luau_number(p[0])}, y = {luau_number(p[1])}, z = {luau_number(p[2])} }})"

    lines = [
        "--!strict",
        "--[[",
        f"\tThe driver's hands through the {car}'s start-up, keyed in Blender against its cabin's",
        "\tcontrols and baked by tools/blender/startup_paths.py from the game's own times and hinges,",
        "\twhich writes this file: do not edit by hand, re-run the script (docs/pipelines/DRIVER_HANDS.md,",
        "\tsection 10). What a key holds is in Config/DriverStartup.",
        f"\t{about}",
        "]]",
        'local DriverStartup = require("../../DriverStartup")',
        "",
        "type Track = DriverStartup.Track",
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
    lines.append("local TOUCHES: { DriverStartup.Touch } = {")
    for touch in touches:
        lines.append(
            f'\t{{ control = "{touch["control"]}", shape = "{touch["shape"]}", '
            f'tip = {point(touch["tip"])}, point = {point(touch["point"])} }},'
        )
    lines += ["}", ""]
    lines += [
        "local StartupPaths: DriverStartup.Paths = table.freeze({",
        "\tRIGHT = table.freeze(RIGHT),",
        "\tLEFT = table.freeze(LEFT),",
        "\tMESHES = table.freeze({",
    ]
    for name in ("Rest", "Point", "Pinch"):
        lines.append(f"\t\t{name} = {point(meshes[name])},")
    lines += [
        "\t}),",
        f"\tCUFF = {point(cuff)},",
        f"\tFINGERTIP = {point(fingertip)},",
        "\tBUTTON = table.freeze({",
        f"\t\ttop = {point(button['top'])},",
        f"\t\tnormal = {point(button['normal'])},",
        f"\t\tdepth = {luau_number(button['depth'])},",
        "\t}),",
        "\tTOUCHES = table.freeze(TOUCHES),",
        "})",
        "",
        "return StartupPaths",
        "",
    ]
    with open(path, "wb") as handle:
        handle.write("\n".join(lines).encode("utf-8"))


def main(inputs, config_path, out):
    seat = Seat(inputs["seat"])
    config = json.load(open(inputs["startupConfig"]))
    manifest = json.load(open(inputs["manifest"]))
    rest = json.load(open(inputs["restPose"]))
    poses = json.load(open(inputs["poses"]))
    grip = json.load(open(inputs["grip"]))
    sequence = inputs["sequence"]
    right_arm, left_arm = Arm(inputs["driver"], 1), Arm(inputs["driver"], -1)
    # Every mesh in the open file goes; the cabin comes from its dump, in the seat frame.
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    cabin = load_cabin(inputs["cabin"], seat)
    presses = [item["press"] for item in sequence["right"] if "press" in item]
    manifest_seat = manifest_points(manifest, presses)
    touches = [Touch(item, cabin, config, manifest_seat) for item in sequence["right"]]
    shape_r = poses["shapes"]
    pinch = shape_r["Pinch"]["R"]
    pinch_point = Vector(pinch["pinch"])
    out_h = pinch_point - Vector(shape_r["Pinch"]["R"]["centre"])
    tips = {
        "Point": Vector(shape_r["Point"]["R"]["fingertip"]),
        "pinch": (pinch_point, Vector(pinch["pinchAxis"]), out_h),
    }
    wheel = wheel_matrix(config)
    right_grip, left_grip = grip_wrist(grip, "R", wheel), grip_wrist(grip, "L", wheel)
    r_keys, r_shapes, r_grip_from = right_keys(sequence, touches, rest["right"], right_grip, wheel, tips, right_arm, config)
    l_keys, l_shapes, l_grip_from = left_keys(sequence, rest["left"], left_grip, wheel)
    bpy.context.scene.render.fps = FPS
    step = inputs.get("bakeStep", BAKE_STEP)
    corners = [t for touch in touches for t in (touch.start, touch.end)]
    right = bake_at(key_empty("RightWrist", r_keys), r_keys[-1][0], step, corners)
    left = bake_at(key_empty("LeftWrist", l_keys), l_keys[-1][0], step, [])

    def shape_at(shapes, t):
        current = shapes[0][1]
        for at, name in shapes:
            if t >= at:
                current = name
        return current

    def tip_offset(shape):
        return pinch_point if shape == "Pinch" else tips["Point"]

    report = {"touches": [], "reach": {}}
    for touch in touches:
        worst = 0.0
        for t, loc, rot in right:
            if touch.start <= t <= touch.end:
                tip = tip_of(from_quaternion(loc, rot), tip_offset(touch.shape))
                worst = max(worst, (tip - touch.contact(t)).length)
        report["touches"].append({"control": touch.name, "grab": touch.grab, "from": touch.start, "to": touch.end, "worstMm": round(worst / STUDS * 1000, 2)})
    for label, samples, arm in (("right", right, right_arm), ("left", left, left_arm)):
        report["reach"][label] = round(max((loc - arm.shoulder).length for _, loc, _ in samples) / arm.reach, 4)
    print(json.dumps(report, indent=1))
    assert max(report["reach"].values()) <= REACH_SHARE, report

    press = next(t for t in touches if t.grab == "press")
    meshes = {name: [c / STUDS for c in shape_r[name]["R"]["centre"]] for name in ("Rest", "Point", "Pinch")}
    luau_touches = [
        {"control": t.name, "shape": t.shape, "tip": [c / STUDS for c in tip_offset(t.shape)], "point": [c / STUDS for c in t.point]}
        for t in touches
        if t.move is not None
    ]
    write_paths(
        config_path,
        config["car"],
        {"RIGHT": (right, r_shapes, r_grip_from), "LEFT": (left, l_shapes, l_grip_from)},
        meshes,
        [c / STUDS for c in poses["cuff"]["R"]],
        [c / STUDS for c in tips["Point"]],
        {"top": [c / STUDS for c in press.point], "normal": list(press.normal), "depth": PRESS_FROM},
        luau_touches,
        f"Baked every {step:.4f} s and where a control starts or stops; ENGINE START held {PRESS_HOLD:.1f} s from the press.",
    )

    def track(samples, shapes):
        return [{"t": round(t, 5), "p": [round(c, 5) for c in loc], "q": [round(c, 6) for c in rot], "shape": shape_at(shapes, t)} for t, loc, rot in samples]

    record = {
        "car": config["car"],
        "studsPerMetre": STUDS,
        "inputs": inputs,
        "arm": {"shoulders": inputs["driver"]["shoulders"], "upper": right_arm.lengths[0], "lower": right_arm.lengths[1], "elbowBias": inputs["driver"]["elbowBias"]},
        "tips": {"Point": list(tips["Point"]), "Pinch": list(pinch_point)},
        "gripLocal": {side: [list(r) for r in grip_wrist(grip, side, Matrix.Identity(4))] for side in ("R", "L")},
        "wheel": [list(r) for r in wheel],
        "touches": [
            {
                "control": t.name,
                "grab": t.grab,
                "shape": t.shape,
                "from": t.start,
                "to": t.end,
                "point": list(t.point),
                "pivot": list(t.pivot) if t.move else None,
                "axis": list(t.axis) if t.move else None,
                "move": t.move,
                "normal": list(t.normal) if t.move is None else None,
            }
            for t in touches
        ],
        "right": track(right, r_shapes),
        "left": track(left, l_shapes),
        "report": report,
    }
    json.dump(record, open(os.path.join(out, "paths.json"), "w"), indent=1)
    if "--no-render" not in inputs.get("flags", []):
        render_frames(inputs, out, cabin, touches, record, poses, grip, seat)


def render_frames(inputs, out, cabin, touches, record, poses, grip, seat):
    """Quarter-speed review frames (15 fps of a quarter-speed clock: four rendered frames per baked
    key) from the cockpit eye, from the passenger seat and close on the panel: the cabin with the
    controls turned as the game turns them, the posed hands, the arms the controller would draw,
    the seated torso and head."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    res = inputs.get("render", {})
    scene.render.resolution_x, scene.render.resolution_y = res.get("size", (640, 400))
    grey = (0.32, 0.33, 0.35, 1)
    for name, obj in cabin.items():
        obj.color = grey
        if any(k in name for k in ("Glass", "glass", "window")):
            obj.hide_render = True
    for name, colour in inputs.get("colours", {}).items():
        for key, obj in cabin.items():
            if key.startswith(name):
                obj.color = colour
    hands = {}
    glb = inputs["posesDir"]
    for side in ("R", "L"):
        for shape in ("Rest", "Point", "Pinch"):
            hands[(shape, side)] = import_glb(os.path.join(glb, f"hand_{shape}_{side}.glb"), f"{shape}_{side}")
        hands[("Grip", side)] = import_glb(os.path.join(inputs["gripDir"], f"hand_{side}.glb"), f"Grip_{side}")
    base = {}
    for key, obj in hands.items():
        obj.color = (0.85, 0.62, 0.5, 1)
        base[key] = obj.data.copy()
    body = seated_body(inputs)
    sleeves = []
    camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.data.clip_start = 0.02
    views = {name: (vec(v["eye"]), vec(v["target"]), v["lens"], v.get("hideHead", False)) for name, v in inputs["views"].items()}
    arm = record["arm"]
    lengths = (arm["upper"], arm["lower"], vec(arm["elbowBias"]))
    grip_local = {side: Matrix(rows) for side, rows in record["gripLocal"].items()}
    moving = [t for t in touches if t.move is not None]
    rests = {t.name: cabin[t.item.get("part", t.name)].matrix_world.copy() for t in moving}

    def tube(name, a, b, radius):
        mesh = bpy.data.meshes.new(name)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=radius, radius2=radius, depth=(b - a).length)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(name, mesh)
        scene.collection.objects.link(obj)
        obj.matrix_world = Matrix.Translation((a + b) / 2) @ (b - a).normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
        obj.color = (0.08, 0.08, 0.09, 1)
        sleeves.append(obj)

    stretch = res.get("stretch", 4)
    step = res.get("step", 2)
    finish = record["right"][-1]["t"] + 0.3
    count = int(finish * 30 * stretch / step)
    ball = {}
    for side in ("R", "L"):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.2, location=(0, 0, 0))
        ball[side] = bpy.context.active_object
        ball[side].color = (0.08, 0.08, 0.09, 1)
    moments = res.get("times") or [frame_no * step / (30 * stretch) for frame_no in range(count + 1)]
    for frame_no, t in enumerate(moments):
        for obj in sleeves:
            bpy.data.objects.remove(obj)
        sleeves.clear()
        for touch in moving:
            obj = cabin[touch.item.get("part", touch.name)]
            angle = touch.angle(t)
            obj.matrix_world = Matrix.Translation(touch.pivot) @ Matrix.Rotation(angle, 4, touch.axis) @ Matrix.Translation(-touch.pivot) @ rests[touch.name]
        for side, sign in (("R", 1), ("L", -1)):
            samples = record["right" if side == "R" else "left"]
            sample = min(samples, key=lambda s: abs(s["t"] - min(t, samples[-1]["t"])))
            m = from_quaternion(sample["p"], sample["q"])
            if t >= samples[-1]["t"]:
                m = Matrix(record["wheel"]) @ grip_local[side]
            shape = sample["shape"] if t < samples[-1]["t"] else "Grip"
            for (name, s), obj in hands.items():
                if s != side:
                    continue
                obj.hide_render = name != shape
                if name == shape:
                    obj.data = base[(name, s)].copy()
                    obj.data.transform(m @ grip_local[side].inverted() if name == "Grip" else m)
            shoulder = vec(arm["shoulders"][side])
            joint, _ = elbow(shoulder, m.translation, m.col[2].xyz, sign, lengths)
            tube(f"Upper{side}", shoulder, joint, 0.26)
            tube(f"Lower{side}", joint, m.translation, 0.2)
            ball[side].location = joint
        for name, (eye, target, lens, hide_head) in views.items():
            for obj in body:
                obj.hide_render = hide_head and obj.name in ("Torso", "Head")
            forward = (target - eye).normalized()
            right_axis = forward.cross(Vector((0, 1, 0))).normalized()
            up = right_axis.cross(forward)
            camera.matrix_world = Matrix(
                (
                    (right_axis.x, up.x, -forward.x, eye.x),
                    (right_axis.y, up.y, -forward.y, eye.y),
                    (right_axis.z, up.z, -forward.z, eye.z),
                    (0, 0, 0, 1),
                )
            )
            camera.data.lens = lens
            os.makedirs(os.path.join(out, name), exist_ok=True)
            label = f"t{t:.3f}" if res.get("times") else f"f{frame_no:04d}"
            scene.render.filepath = os.path.join(out, name, f"{label}.png")
            bpy.ops.render.render(write_still=True)


def seated_body(inputs):
    """The seated R6's torso and head boxes (the car's seated pose file, seat studs), and the legs
    as the footwell file draws them, for the renders."""
    pose = json.load(open(inputs["seatedPose"]))
    objects = []
    for name, colour in (("Torso", (0.45, 0.47, 0.52, 1)), ("Head", (0.85, 0.62, 0.5, 1))):
        box = pose["boxes"][name]
        cols = box["axes_blender_columns_xyz"]
        # Blender car axes -> seat axes: (x, y, z) -> (-x, z, y).
        axes = [Vector((-c[0], c[2], c[1])) for c in zip(*cols)]
        bpy.ops.mesh.primitive_cube_add(size=2, location=vec(box["centre_seat_studs"]))
        obj = bpy.context.active_object
        obj.name = name
        half = [h * STUDS for h in box["half_m"]]
        obj.matrix_world = frame(vec(box["centre_seat_studs"]), axes[0] * half[0], axes[1] * half[1], axes[2] * half[2])
        obj.color = colour
        objects.append(obj)
    legs = json.load(open(inputs["footwell"]))["poses_blender"]
    origin = vec(inputs["seat"])
    for pose_name in inputs.get("legPoses", []):
        points = legs[pose_name]
        chain = [Vector((-(p[0] - origin.x), p[2] - origin.z, p[1] - origin.y)) * STUDS for p in (points["hip"], points["knee"], points["ankle"], points["ball"])]
        for a, b in zip(chain, chain[1:]):
            mesh = bpy.data.meshes.new("Leg")
            bm = bmesh.new()
            bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.35, radius2=0.35, depth=(b - a).length)
            bm.to_mesh(mesh)
            bm.free()
            obj = bpy.data.objects.new("Leg", mesh)
            bpy.context.scene.collection.objects.link(obj)
            obj.matrix_world = Matrix.Translation((a + b) / 2) @ (b - a).normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
            obj.color = (0.13, 0.14, 0.16, 1)
            objects.append(obj)
    return objects
