"""
Review renders of a car's gear-lever hand (tools/anim/shift_paths.py's paths.json) at quarter speed:
the right hand leaves the wheel, rides the knob through a shift and goes back, played as the game
plays it. The gearbox's plan (Vehicle/ShiftPlan, ported below) times the lever from the car's own
shift timing; the hand's share runs 0 to 1 over the reach and back over the release (Vehicle/HBox);
the hand on its way is Rules/ShiftHand.pose. Gloves only, as the local driver sees them in the
cockpit view (DriverArms.COCKPIT_GLOVES_ONLY): no sleeves, no torso, no head.

    blender -b --factory-startup --python-exit-code 1 -P tools/blender/shift_render.py -- \\
        <paths.json> <shift_config.json> <abs out dir> [--shifts 1-2,2-3,3-2] [--views cockpit,knob]
        [--stretch 4] [--size 640x360] [--quick]

Frames are game time every 1/60 s; at 15 frames a second they play at quarter speed (--stretch 4).
Writes <out>/<shift>/<view>/f0000.png ... and <out>/<shift>/frames.json (the time, phase, share and
lever place of every frame).
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
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "anim"))
from shift_paths import Frame, Shifter, compose, hand_on_way, inputs_of, key_frame  # noqa: E402
from startup_paths import STUDS, Seat, import_glb  # noqa: E402
from startup_sequence import load_cabin  # noqa: E402

GLOVE = tuple(((c / 255 + 0.055) / 1.055) ** 2.4 for c in (34, 34, 38)) + (1.0,)
LEVER_PARTS = ("GEO_INT_shifter_01", "GEO_INT_shifter_decal", "GEO_INT_shifter_00", "GEO_INT_shifter_02")
# The game's cockpit eye in the seat frame (metres): the seated head's centre plus Camera.eye.
EYE = (0.0, 0.6115, 0.0801)
COCKPIT_FOV = 70


def option(args, name, default):
    return args[args.index(name) + 1] if name in args else default


def ease(u):
    u = min(1.0, max(0.0, u))
    return u * u * (3 - 2 * u)


def unease(share):
    low, high = 0.0, 1.0
    for _ in range(40):
        middle = (low + high) / 2
        if ease(middle) < share:
            low = middle
        else:
            high = middle
    return (low + high) / 2


class Plan:
    """Vehicle/ShiftPlan.plan, lever and knob, for a shift started with the hand and foot away."""

    def __init__(self, gates, timing, frm, to, hand_at=0.0, foot_at=0.0):
        self.gates, self.frm, self.to = gates, frm, to
        c0, r0 = gates[frm]
        c1, r1 = gates[to]
        self.c0, self.r0 = c0, r0
        self.reach_end = timing["reach"] * (1 - hand_at)
        foot_end = timing["footMove"] * (1 - foot_at)
        self.press_start = max(self.reach_end, foot_end)
        self.clutch_down = self.press_start + timing["clutchIn"]
        into_reverse = to == "R" and frm != "R"
        self.knob_down = into_reverse
        self.leave = timing["leave"] * abs(r0)
        self.push = timing["push"] if into_reverse else 0.0
        columns = abs(c1 - c0)
        self.cross = timing["crossBase"] + timing["crossPerColumn"] * columns if columns > 1e-9 else 0.0
        self.enter = timing["enter"] * abs(r1)
        self.travel = self.leave + self.push + self.cross + self.enter
        self.gate_in = self.clutch_down + self.travel
        self.clutch_up = self.gate_in + timing["clutchOut"]

    def progress(self, t):
        if self.travel <= 0 or t >= self.gate_in:
            return self.travel
        return self.travel * ease((t - self.clutch_down) / self.travel)

    def lever(self, t):
        c1, r1 = self.gates[self.to]
        if t >= self.gate_in:
            return c1, r1
        done = self.progress(t)
        if done < self.leave:
            return self.c0, self.r0 * (1 - done / self.leave)
        done -= self.leave + self.push
        if done < 0:
            return self.c0, 0.0
        if done < self.cross:
            return self.c0 + (c1 - self.c0) * done / self.cross, 0.0
        done -= self.cross
        if self.enter <= 0:
            return c1, r1
        return c1, r1 * min(1.0, done / self.enter)

    def knob(self, t):
        if not self.knob_down or t >= self.gate_in:
            return 0.0
        done = self.progress(t) - self.leave
        return 0.0 if done <= 0 else min(1.0, done / self.push)

    def phase(self, t):
        for name, end in (("reach", self.press_start), ("clutchIn", self.clutch_down), ("lever", self.gate_in), ("clutchOut", self.clutch_up)):
            if t < end:
                return name
        return "done"


def to_blender(frame):
    """A seat-frame Frame in metres as a Blender matrix in the seat frame's studs."""
    m = Matrix([list(map(float, row)) for row in frame.rot]).to_4x4()
    m.translation = Vector(frame.pos) * STUDS
    return m


def steering_grip(paths_inputs):
    """The right hand's wrist on the wheel (seat frame), its frame in the wheel's, and the wheel's
    frame (seat frame, metres)."""
    hands = json.load(open(paths_inputs["grip"], encoding="utf-8"))["R"]
    hub = paths_inputs["wheel"]
    z = np.array(hub["axis"], float)
    z /= np.linalg.norm(z)
    x = np.array([1.0, 0, 0]) - z * z[0]
    x /= np.linalg.norm(x)
    axes = np.stack([x, np.cross(z, x), z], 1)
    centre = np.array(hub["pivot"], float) + np.array([0, hub.get("lift", 0), 0])
    local = Frame.grip(hands["wrist"], hands["forearm"], hands["back"])
    return Frame(axes @ local.rot, axes @ local.pos + centre), local, Frame(axes, centre)


def main(args):
    paths_path, config_path, out = args[0], args[1], args[2]
    shifts = option(args, "--shifts", "1-2,2-3,3-2").split(",")
    views = option(args, "--views", "cockpit,knob").split(",")
    stretch = float(option(args, "--stretch", "4"))
    width, height = (int(v) for v in option(args, "--size", "640x360").split("x"))
    paths = json.load(open(paths_path, encoding="utf-8"))
    inputs = json.load(open(inputs_of(paths_path, paths), encoding="utf-8"))
    config = json.load(open(config_path, encoding="utf-8"))
    timing = dict(config["timing"])
    if "--quick" in args:
        timing.update(reach=paths["quick"]["reach"], release=paths["quick"]["release"], footMove=paths["quick"]["foot"])
    release = timing["release"]
    gates = {k: tuple(v) for k, v in paths["gates"].items()}
    spec = paths["shifter"]
    shifter = Shifter(
        {
            "pivot": [spec["pivot"][k] for k in "xyz"],
            "knob": [spec["knob"][k] for k in "xyz"],
            "right": [spec["right"][k] for k in "xyz"],
            "back": [spec["back"][k] for k in "xyz"],
            "knobRadius": spec["knobRadius"],
            "columns": [[c["column"], c["degrees"]] for c in spec["columns"]],
            "forward": spec["forward"],
            "backward": spec["backward"],
            "push": spec["push"],
        }
    )
    grip_local = key_frame(paths["grip"])
    keys, shape_changes = paths["hand"]["keys"], paths["hand"]["shapes"]
    wheel_grip, grip_in_wheel, wheel_frame = steering_grip(inputs)

    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    seat = Seat(inputs["seat"])
    cabin = load_cabin(inputs["cabin"], seat)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    scene.render.resolution_x, scene.render.resolution_y = width, height
    for name, obj in cabin.items():
        obj.color = (0.32, 0.33, 0.35, 1)
        if any(k in name.lower() for k in ("glass", "window")):
            obj.hide_render = True
        if name.startswith("GEO_INT_shifter"):
            obj.color = (0.12, 0.12, 0.13, 1)
        if name.startswith("GEO_INT_STwheel"):
            obj.color = (0.1, 0.1, 0.1, 1)
    neutral = shifter.lever(*gates["N"])
    modelled = to_blender(neutral)
    lever_rest = {n: cabin[n].matrix_world.copy() for n in LEVER_PARTS if n in cabin}

    poses_dir = os.path.dirname(inputs["poses"])
    meshes = {name: import_glb(os.path.join(poses_dir, f"hand_{name}_R.glb"), f"Hand_{name}") for name in ("Rest", "Knob")}
    meshes["Grip"] = import_glb(os.path.join(os.path.dirname(inputs["grip"]), "hand_R.glb"), "Hand_Grip")
    grip_offset = to_blender(Frame(grip_in_wheel.rot, grip_in_wheel.pos)).inverted()
    base = {}
    for name, obj in meshes.items():
        obj.color = GLOVE
        base[name] = obj.data.copy()
    # The left hand stays on the wheel (its grip mesh is posed in the wheel's frame).
    left = import_glb(os.path.join(os.path.dirname(inputs["grip"]), "hand_L.glb"), "Hand_Left")
    left.data.transform(to_blender(wheel_frame))
    left.color = GLOVE

    camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.data.clip_start = 0.02
    camera.data.sensor_fit = "VERTICAL"
    eye = Vector(EYE) * STUDS
    knob_at = Vector(shifter.knob) * STUDS

    def aim(position, target, fov):
        forward = (target - position).normalized()
        right = forward.cross(Vector((0, 1, 0))).normalized()
        up = right.cross(forward)
        camera.matrix_world = Matrix(
            ((right.x, up.x, -forward.x, position.x), (right.y, up.y, -forward.y, position.y), (right.z, up.z, -forward.z, position.z), (0, 0, 0, 1))
        )
        camera.data.angle_y = math.radians(fov)

    view_setups = {
        # The game's cockpit camera: level, straight ahead, 70 degrees high.
        "cockpit": (eye, eye + Vector((0, 0, -1)), COCKPIT_FOV),
        # The same eye, head turned down to the knob.
        "knob": (eye, knob_at, 50),
        # From the passenger side, low: the lever and the hand.
        "side": (Vector((0.75, 0.55, -0.05)) * STUDS, knob_at, 40),
    }

    for shift in shifts:
        frm, to = shift.split("-")
        plan = Plan(gates, timing, frm, to)
        hold = plan.clutch_up + 0.15
        finish = hold + release + 0.15
        frames = []
        count = int(round(finish * 60))
        for index in range(count + 1):
            t = index / 60
            if t < hold:
                share = min(1.0, t / timing["reach"])
                c, r = plan.lever(t)
                k = plan.knob(t)
            else:
                share = max(0.0, 1 - (t - hold) / release)
                c, r = gates[to]
                k = 0.0
            lever = shifter.lever(c, r, k)
            knob_wrist = compose(lever, grip_local)
            if share >= 1.0:
                wrist, shape = knob_wrist, "Knob"
            else:
                wrist, shape = hand_on_way(keys, shape_changes, share, wheel_grip, knob_wrist)
            frames.append({"t": round(t, 4), "phase": plan.phase(t) if t < hold else "release", "share": round(share, 4), "column": round(c, 4), "row": round(r, 4), "knob": round(k, 4), "shape": shape})
            turn = to_blender(lever) @ modelled.inverted()
            for name, rest in lever_rest.items():
                cabin[name].matrix_world = turn @ rest
            m = to_blender(wrist)
            for name, obj in meshes.items():
                obj.hide_render = name != shape
                if name == shape:
                    obj.data = base[name].copy()
                    obj.data.transform(m @ grip_offset if name == "Grip" else m)
            for view in views:
                position, target, fov = view_setups[view]
                aim(position, target, fov)
                folder = os.path.join(out, shift, view)
                os.makedirs(folder, exist_ok=True)
                scene.render.filepath = os.path.join(folder, f"f{index:04d}.png")
                bpy.ops.render.render(write_still=True)
        record = {
            "shift": shift,
            "timing": timing,
            "plan": {"reachEnd": plan.reach_end, "clutchDown": plan.clutch_down, "gateIn": plan.gate_in, "clutchUp": plan.clutch_up, "hold": hold, "finish": finish},
            "stretch": stretch,
            "playbackFps": 60 / stretch,
            "frames": frames,
        }
        json.dump(record, open(os.path.join(out, shift, "frames.json"), "w"), indent=1)
        print(f"{shift}: {count + 1} frames, gate in at {plan.gate_in:.3f} s")


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1 :])
