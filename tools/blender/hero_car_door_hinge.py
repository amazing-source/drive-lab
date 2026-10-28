"""
Fits the hinge of the door marked by hero_car_door.py, or checks one, run headless by Blender:

    blender -b --factory-startup -P tools/blender/hero_car_door_hinge.py -- <svj_door.blend> <out dir> fit <degrees>
    blender -b --factory-startup -P tools/blender/hero_car_door_hinge.py -- <svj_door.blend> <out dir> check <degrees> px,py,pz ax,ay,az
    blender -b --factory-startup -P tools/blender/hero_car_door_hinge.py -- <svj_door.blend> <out dir> set 0 px,py,pz <toe> <camber>

A hinge is a pivot and a unit axis in Blender metres (nose along -Y, Z up, the driver's door on
+X); the door opens by a positive turn about the axis, by the right-hand rule. `check` turns the
door from shut to <degrees> one degree at a time and counts the pairs of door and body triangles
that cut each other, leaving out pairs that already touch when shut (the shut lines, where the
model's door and body meet with no gap). Door triangles within NEAR_AXIS of the axis are left
out too: the model's own hinge arm turns there, inside its bracket. Every pair still found is
listed by door island and body part, with where it is. Exits 1 if any pair is found.

`set` records one hinge, given by its pivot, toe and camber, as `fit` records its pick. `fit`
searches pivots and axes tilted from the car's cross axis by a toe (about Z) and a camber
(down outboard), sweeping each to <degrees> every 10 degrees, refines the best, and keeps the
fewest collisions, then the open door's outward lean nearest TARGET_OUTWARD (a photograph). The
open angle is where the door's length stands at FORWARD_LEAN (another photograph); the chosen
hinge is re-checked at every degree to it, and <out dir>/hinge.json gets the hinge, the angle,
the lean when open, every collision left and the clearance. Every point ahead of and above a
pivot moves forward and down as the door opens, every point below it rearward: the front quarter
window wants the pivot near its tip, far forward and high (the model's own hinge parts, at about
(0.90, -0.93, 0.50), send it into the fender), and the rear edge's lower corner then needs the
camber to carry it outward.
"""

import itertools
import json
import math
import sys
from collections import Counter
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

DOOR = 1
NEAR_AXIS = 0.06
# The game mesh has no shut gaps (a real door has 4 to 5 mm): along its seams door and body
# touch or overlap, so the first degree of any turn slides triangles into their neighbours. A
# pair counts once the door triangle has moved CONTACT_TRAVEL from where it sits shut.
CONTACT_TRAVEL = 0.02
# Body triangles within SEAM of the shut door are its shut faces: the door may slide along them
# for its first SEAM_TRAVEL of travel, as a real door leaves its seals, and must clear them after.
SEAM = 0.015
SEAM_TRAVEL = 0.08
# Inside the front fender, around the model's hinge: no one sees it.
HINGE_POCKET = {"x0": 0.84, "x1": 1.0, "y0": -1.0, "y1": -0.84, "z0": 0.30, "z1": 0.66}
REGION = {"x0": 0.25, "y0": -1.9, "y1": 1.3}
PIVOT_X = 0.90
PIVOT_Y = (-1.22, -1.10)
PIVOT_Z = (0.62, 0.77)
TOE = (-32.0, -12.0)
CAMBER = (24.0, 36.0)
# Of the hinges that clear, the one whose open door leans outward nearest this, in degrees: the
# open door's top stands about 12 degrees outboard in a front photograph (Commons, Tuner tom,
# File:Lamborghini_Aventador_front_with_scissor_doors_up_and_Transparent_Engine_Bonnet.JPG).
TARGET_OUTWARD = 12.0
# The open angle: where the door's bottom edge, its length when open, stands this many degrees
# forward of vertical (negative: its top rearward). Measured on a rear three-quarter photograph
# (Commons, Axion23, CC BY 2.0, File:Orange_Lamborghini_Aventador_LP700_(13958653933).jpg): the
# raised door's bottom shut face leans 1.2 degrees from vertical in the image, top rearward; the
# view stands 31 to 40 degrees off the car's side (rear wheel's ellipse 0.86 wide for tall), so
# about 1.5 degrees on the car.
FORWARD_LEAN = -1.5

args = sys.argv[sys.argv.index("--") + 1 :]
blend, out, mode, degrees = Path(args[0]).resolve(), Path(args[1]).resolve(), args[2], float(args[3])
out.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(blend))


def faces_of(obj):
    attr = obj.data.attributes.get("door_part")
    values = np.zeros(len(obj.data.polygons), dtype=np.int32)
    if attr:
        attr.data.foreach_get("value", values)
    return values


door_v, door_owner, door_island, body_v, body_owner = [], [], [], [], []
for obj in bpy.context.scene.objects:
    if obj.type != "MESH":
        continue
    mesh = obj.data
    matrix = np.array(obj.matrix_world)
    co = np.array([tuple(v.co) for v in mesh.vertices]) @ matrix[:3, :3].T + matrix[:3, 3]
    parts = faces_of(obj)
    islands = np.zeros(len(mesh.polygons), dtype=np.int32)
    if mesh.attributes.get("door_island"):
        mesh.attributes["door_island"].data.foreach_get("value", islands)
    for poly in mesh.polygons:
        vs = list(poly.vertices)
        for k in range(1, len(vs) - 1):
            tri = co[[vs[0], vs[k], vs[k + 1]]]
            if parts[poly.index] == DOOR:
                door_v.append(tri)
                door_owner.append(obj.name)
                door_island.append(int(islands[poly.index]))
            elif tri[:, 0].max() > REGION["x0"] and REGION["y0"] < tri[:, 1].mean() < REGION["y1"]:
                body_v.append(tri)
                body_owner.append(obj.name)
door_v = np.array(door_v)
body_v = np.array(body_v)
door_index = [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(door_v))]
body_bvh = BVHTree.FromPolygons([tuple(p) for p in body_v.reshape(-1, 3)], [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(body_v))])
door_centres = door_v.mean(1)
print(f"door triangles {len(door_v)}, body triangles near it {len(body_v)}")


def rotation(pivot, axis, angle_deg):
    r = np.array(Matrix.Rotation(math.radians(angle_deg), 3, Vector(axis)))
    return r, np.array(pivot) - r @ np.array(pivot)


def pairs_at(pivot, axis, angle_deg):
    r, t = rotation(pivot, axis, angle_deg)
    moved = door_v.reshape(-1, 3) @ r.T + t
    bvh = BVHTree.FromPolygons([tuple(p) for p in moved], door_index)
    return set(bvh.overlap(body_bvh))


def near_axis(pivot, axis):
    a = np.array(axis) / np.linalg.norm(axis)
    d = door_centres - np.array(pivot)
    radial = d - np.outer(d @ a, a)
    return np.linalg.norm(radial, axis=1) < NEAR_AXIS


rest = pairs_at((0, 0, 0), (1, 0, 0), 0)
print(f"pairs touching when shut (shut lines): {len(rest)}")


body_centres = body_v.mean(1)
in_pocket = np.ones(len(body_v), bool)
for k, key in enumerate("xyz"):
    in_pocket &= (body_centres[:, k] > HINGE_POCKET[f"{key}0"]) & (body_centres[:, k] < HINGE_POCKET[f"{key}1"])


door_bvh_shut = BVHTree.FromPolygons([tuple(p) for p in door_v.reshape(-1, 3)], door_index)
seam = np.array([(door_bvh_shut.find_nearest(Vector(c))[3] or 9.0) < SEAM for c in body_centres])
print(f"body triangles on the door's seams: {int(seam.sum())}")


def new_pairs(pivot, axis, angle_deg, skip, hidden=False):
    r, t = rotation(pivot, axis, angle_deg)
    travel = np.linalg.norm(door_centres @ r.T + t - door_centres, axis=1)
    found = set()
    for i, j in pairs_at(pivot, axis, angle_deg) - rest:
        if skip[i] or travel[i] < CONTACT_TRAVEL or (seam[j] and travel[i] < SEAM_TRAVEL):
            continue
        found.add((i, j))
    return {p for p in found if in_pocket[p[1]] == hidden}


def axis_of(toe, camber):
    # Cross axis (+X), turned by `toe` about Z so its outboard end points rearward, then tilted
    # down outboard by `camber`.
    a = Matrix.Rotation(math.radians(toe), 3, "Z") @ Matrix.Rotation(math.radians(camber), 3, "Y") @ Vector((1, 0, 0))
    return tuple(a.normalized())


def lean(axis, angle_deg):
    # The door's length (its bottom edge, front to rear) once open: degrees outward of vertical
    # and degrees forward of vertical.
    r, _ = rotation((0, 0, 0), axis, angle_deg)
    edge = r @ np.array([0.0, 1.0, 0.048])
    edge /= np.linalg.norm(edge)
    return math.degrees(math.atan2(edge[0], edge[2])), math.degrees(math.atan2(-edge[1], edge[2]))


def describe(pivot, axis, angle_deg, found):
    owners = Counter((door_owner[i].split("_Geo")[0], body_owner[j].split("_Geo")[0]) for i, j in found)
    spots = Counter(door_island[i] for i, _ in found)
    centres = np.array([door_centres[i] for i, _ in found])
    r, t = rotation(pivot, axis, angle_deg)
    moved = centres @ r.T + t
    return {
        "angle": angle_deg,
        "pairs": len(found),
        "byPart": {f"{a} x {b}": n for (a, b), n in owners.most_common(8)},
        "doorIslands": {str(k): n for k, n in spots.most_common(6)},
        "islandExtents": {
            str(k): [[round(float(c), 3) for c in door_v[[i for i, _ in found if door_island[i] == k]].reshape(-1, 3).min(0)],
                     [round(float(c), 3) for c in door_v[[i for i, _ in found if door_island[i] == k]].reshape(-1, 3).max(0)]]
            for k, _ in spots.most_common(4)
        },
        "bodyExtents": [[round(float(c), 3) for c in body_v[[j for _, j in found]].reshape(-1, 3).min(0)],
                        [round(float(c), 3) for c in body_v[[j for _, j in found]].reshape(-1, 3).max(0)]],
        "shutPosition": [[round(float(c), 3) for c in centres.min(0)], [round(float(c), 3) for c in centres.max(0)]],
        "where": [[round(float(c), 3) for c in moved.min(0)], [round(float(c), 3) for c in moved.max(0)]],
    }


def sweep(pivot, axis, step):
    skip = near_axis(pivot, axis)
    report, hidden = [], 0
    for angle in np.arange(step, degrees + 1e-6, step):
        found = new_pairs(pivot, axis, float(angle), skip)
        hidden += len(new_pairs(pivot, axis, float(angle), skip, hidden=True))
        if found:
            report.append(describe(pivot, axis, float(angle), found))
    return report, int(skip.sum()), hidden


def clearance(pivot, axis, step=5.0):
    # The closest any moved door vertex comes to the body over the sweep, away from the axis
    # and from the shut lines (vertices that start within 2 mm of the body).
    flat = door_v.reshape(-1, 3)
    a = np.array(axis)
    d = flat - np.array(pivot)
    far = np.linalg.norm(d - np.outer(d @ a, a), axis=1) >= NEAR_AXIS
    start = np.array([body_bvh.find_nearest(Vector(p))[3] or 9 for p in flat[::3]])
    free = far[::3] & (start > 0.002)
    worst = (9.0, None, None)
    for angle in np.arange(step, degrees + 1e-6, step):
        r, t = rotation(pivot, axis, float(angle))
        moved = flat[::3][free] @ r.T + t
        for p in moved:
            hit = body_bvh.find_nearest(Vector(p))
            if hit[3] is not None and hit[3] < worst[0]:
                worst = (hit[3], float(angle), [round(float(c), 3) for c in p])
    return {"metres": round(worst[0], 4), "atDegrees": worst[1], "where": worst[2]}


def record(chosen):
    global degrees
    # The door's length leans further forward as it opens: bisect for the photographed lean.
    low_angle, high_angle = 60.0, 120.0
    for _ in range(40):
        middle = (low_angle + high_angle) / 2
        if lean(chosen["axis"], middle)[1] < FORWARD_LEAN:
            low_angle = middle
        else:
            high_angle = middle
    degrees = round((low_angle + high_angle) / 2, 1)
    report, skipped, hidden = sweep(chosen["pivot"], chosen["axis"], 1.0)
    write(chosen, report, skipped, hidden)


def write(chosen, report, skipped, hidden):
    result = {
        "pivot": [round(v, 4) for v in chosen["pivot"]],
        "axis": [round(v, 5) for v in chosen["axis"]],
        "toeDegrees": chosen["toe"],
        "camberDegrees": chosen["camber"],
        "openDegrees": degrees,
        "leanWhenOpen": {k: round(v, 1) for k, v in zip(("outwardDegrees", "forwardDegrees"), lean(chosen["axis"], degrees))},
        "collisionsEveryDegree": report,
        "doorTrianglesNearAxisLeftOut": skipped,
        "pairsInsideHingePocket": hidden,
        "clearance": clearance(chosen["pivot"], chosen["axis"]),
    }
    (out / "hinge.json").write_text(json.dumps(result, indent=1))
    print("FIT RESULT", json.dumps({k: v for k, v in result.items() if k != "collisionsEveryDegree"}))
    print(f"FIT every degree: {sum(r['pairs'] for r in report)} new pairs")
    for row in report[:12]:
        print("COLLIDE", json.dumps(row))


if mode == "set":
    toe, camber = float(args[5]), float(args[6])
    record({"pivot": tuple(float(v) for v in args[4].split(",")), "toe": toe, "camber": camber, "axis": axis_of(toe, camber)})
    sys.exit(0)

if mode == "check":
    pivot = tuple(float(v) for v in args[4].split(","))
    axis = tuple(float(v) for v in args[5].split(","))
    axis = tuple(np.array(axis) / np.linalg.norm(axis))
    report, skipped, hidden = sweep(pivot, axis, 1.0)
    print(f"CHECK pivot={pivot} axis={tuple(round(a, 4) for a in axis)} to {degrees} deg: door triangles near the axis left out {skipped}, pairs inside the hinge pocket {hidden}")
    for row in report:
        print("COLLIDE", json.dumps(row))
    print(f"CHECK RESULT {'FAIL' if report else 'PASS'}: {sum(r['pairs'] for r in report)} new pairs over {len(report)} of {int(degrees)} angles")
    sys.exit(1 if report else 0)

# fit
candidates = []
grid = itertools.product(
    np.arange(PIVOT_Y[0], PIVOT_Y[1] + 1e-6, 0.04),
    np.arange(PIVOT_Z[0], PIVOT_Z[1] + 1e-6, 0.05),
    np.arange(TOE[0], TOE[1] + 1e-6, 5.0),
    np.arange(CAMBER[0], CAMBER[1] + 1e-6, 4.0),
)
for py, pz, toe, camber in grid:
    pivot = (PIVOT_X, float(py), float(pz))
    axis = axis_of(toe, camber)
    skip = near_axis(pivot, axis)
    total, first = 0, None
    for angle in np.arange(10.0, degrees + 1e-6, 10.0):
        n = len(new_pairs(pivot, axis, float(angle), skip))
        total += n
        if n and first is None:
            first = float(angle)
        if total > 2000:
            break
    candidates.append({"pivot": pivot, "toe": float(toe), "camber": float(camber), "axis": axis, "pairs": total, "first": first})
candidates.sort(key=lambda c: (c["pairs"], abs(lean(c["axis"], degrees)[0] - TARGET_OUTWARD)))
print("FIT coarse best:")
for c in candidates[:15]:
    print("  ", {k: (round(v, 3) if isinstance(v, float) else v) for k, v in c.items() if k != "axis"}, "lean", [round(v, 1) for v in lean(c["axis"], degrees)])
best = candidates[0]
# Refine around the best: half steps.
refined = []
for dy, dz, dt, dc in itertools.product((-0.02, 0, 0.02), (-0.03, 0, 0.03), (-3, 0, 3), (-3, 0, 3)):
    pivot = (PIVOT_X, best["pivot"][1] + dy, best["pivot"][2] + dz)
    toe, camber = best["toe"] + dt, best["camber"] + dc
    axis = axis_of(toe, camber)
    skip = near_axis(pivot, axis)
    total = sum(len(new_pairs(pivot, axis, float(a), skip)) for a in np.arange(5.0, degrees + 1e-6, 5.0))
    refined.append({"pivot": pivot, "toe": toe, "camber": camber, "axis": axis, "pairs": total})
refined.sort(key=lambda c: (c["pairs"], abs(lean(c["axis"], degrees)[0] - TARGET_OUTWARD)))
chosen = refined[0]
record(chosen)
