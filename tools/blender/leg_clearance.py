"""
How far the driver's trousers and knees stay off the cabin, for every pose tools/legs/poses.luau
samples from Rules/DriverLegs.

    lune run tools/legs/poses <SEAT_WELD.json> <poses.json>
    blender -b <car.blend> --factory-startup -P tools/blender/leg_clearance.py -- <poses.json>
        [--seat 0.38,-0.061,0.2814] [--wheel-lift 0.02]

<car.blend> is the car in Blender metres (the door-cut cabin, svj_door.blend or its pedal-tagged
copy). --seat is the DriverSeat part's origin in the blend (the frame the poses are in);
--wheel-lift raises the object named SteeringWheel as the rig does (SVJModel.steeringWheelLift).

Each pose's thigh and shin are the trouser tubes of driver_legs.py (elliptical: wider across than
deep), the knee the ball of Config/DriverLegs' KNEE_SIZE. For points along each tube the nearest
cabin surface is found, and the tube's own radius toward it is taken off: a negative gap is that
deep inside the cabin. The tube's ends are left out: the thigh's first 30 % lies on the seat, the
shin's last 20 % is the shoe's collar over the pedals. Prints one line per pose and the worst
per side and part.

The nearest surface can be the column or the console beside the knee as well as the dash above
it, and the mesh name does not tell them apart (one cabin object holds all three). So each line
also gives the knee's room straight above it, `above`: the shortest hit of rays fanned within
ABOVE_CONE degrees of the seat's up, less the knee's radius. That is the knee against the dash.

And `under`: the air below the thigh tube (rays straight down from its centre line, less its
depth), the shortest and the longest along the thigh's first 70 %: the room the trousers' seat
(tools/blender/seat_fill.py) fills down to the cushion.
"""

import json
import math
import sys

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

KNEE_RADIUS = 0.06
SEAT_UP = Vector((0, 0, 1))
ABOVE_CONE = 40


def option(args, name, default):
    return args[args.index(name) + 1] if name in args else default


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(t):
    return t * t * (3 - 2 * t)


# driver_legs.py's thigh_radius and shin_radius: (across, deep) half-sizes along the tube.
def thigh_radius(t):
    return lerp(0.085, 0.0625, smoothstep(t)), lerp(0.075, 0.06, smoothstep(t))


def shin_radius(t):
    calf = 0.004 * math.exp(-(((t - 0.3) / 0.15) ** 2))
    return lerp(0.06, 0.056, smoothstep(t)) + calf, lerp(0.058, 0.054, smoothstep(t)) + calf


def cabin(wheel_lift):
    trees = []
    for obj in bpy.data.objects:
        if obj.type != "MESH" or len(obj.data.polygons) == 0 or "Belt" in obj.name:
            continue
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bm.transform(obj.matrix_world)
        if obj.name == "SteeringWheel":
            for vert in bm.verts:
                vert.co.z += wheel_lift
        trees.append((obj.name, BVHTree.FromBMesh(bm)))
        bm.free()
    return trees


def nearest(trees, point):
    best = None
    for name, tree in trees:
        hit = tree.find_nearest(point, 1.0)
        if hit[0] is not None and (best is None or hit[3] < best[2]):
            best = (name, hit[0], hit[3])
    return best


def room_above(trees, point):
    best = 9.0
    for ring in range(5):
        tilt = math.radians(ABOVE_CONE * ring / 4)
        for step in range(1 if ring == 0 else 12):
            turn = 2 * math.pi * step / 12
            direction = Vector((math.sin(tilt) * math.cos(turn), math.sin(tilt) * math.sin(turn), math.cos(tilt)))
            for _, tree in trees:
                hit = tree.ray_cast(point, direction, 1.0)
                if hit[0] is not None and hit[3] < best:
                    best = hit[3]
    return best - KNEE_RADIUS


def drop(trees, point):
    best = 9.0
    for _, tree in trees:
        hit = tree.ray_cast(point, -SEAT_UP, 1.0)
        if hit[0] is not None and hit[3] < best:
            best = hit[3]
    return best


def under_thigh(trees, hip, knee):
    gaps = []
    for i in range(8):
        t = 0.7 * i / 7
        gaps.append(drop(trees, hip.lerp(knee, t)) - thigh_radius(t)[1])
    return min(gaps), max(gaps)


def tube_gap(trees, start, end, radius_at, ts):
    axis = (end - start).normalized()
    across = axis.cross(SEAT_UP).normalized()
    deep = across.cross(axis)
    worst = (None, 9.0)
    for t in ts:
        centre = start.lerp(end, t)
        name, point, distance = nearest(trees, centre)
        offset = point - centre
        side = offset - axis * offset.dot(axis)
        rx, ry = radius_at(t)
        if side.length < 1e-9:
            radius = min(rx, ry)
        else:
            c, s = side.normalized().dot(across), side.normalized().dot(deep)
            radius = 1 / math.sqrt((c / rx) ** 2 + (s / ry) ** 2)
        if distance - radius < worst[1]:
            worst = (name, distance - radius)
    return worst


def main(args):
    poses = json.load(open(args[0]))
    seat = Vector(tuple(float(v) for v in option(args, "--seat", "0.38,-0.061,0.2814").split(",")))
    trees = cabin(float(option(args, "--wheel-lift", "0.02")))

    def blend(p):
        return seat + Vector((-p[0], p[2], p[1]))

    summary = {}
    for pose in poses:
        if pose["side"] == "seat":
            continue
        hip, knee, ankle = blend(pose["hip"]), blend(pose["knee"]), blend(pose["ankle"])
        name, _, distance = nearest(trees, knee)
        gaps = {
            "knee": (name, distance - KNEE_RADIUS),
            "thigh": tube_gap(trees, hip, knee, thigh_radius, [0.3 + 0.65 * i / 8 for i in range(9)]),
            "shin": tube_gap(trees, knee, ankle, shin_radius, [0.8 * i / 8 for i in range(9)]),
            "above": ("dash", room_above(trees, knee)),
        }
        line = "  ".join(f"{part} {gap * 100:5.1f} cm ({mesh})" for part, (mesh, gap) in gaps.items())
        low, high = under_thigh(trees, hip, knee)
        print(f"POSE {pose['side']:5s} {pose['name']:13s} {line}  under {low * 100:5.1f}..{high * 100:5.1f} cm")
        on_pedal = pose["side"] == "left" or not pose["name"].startswith("across") or pose["name"] in ("across 0.00", "across 1.00")
        group = f"{pose['side']} {'on a pedal' if on_pedal else 'across'}"
        gaps["under"] = ("cushion", low)
        for part, (mesh, gap) in gaps.items():
            key = (group, part)
            if key not in summary or gap < summary[key][1]:
                summary[key] = (pose["name"], gap, mesh)
    for (group, part), (pose, gap, mesh) in sorted(summary.items()):
        print(f"WORST {group:16s} {part:5s} {gap * 100:5.1f} cm at {pose} ({mesh})")


main(sys.argv[sys.argv.index("--") + 1 :])
