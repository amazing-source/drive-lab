"""
Shapes the trousers' seat to the car's bucket: the cloth that fills the room between the seated
R6 and the cushion, so the driver sits in the seat instead of over it.

    lune run tools/legs/poses <SEAT_WELD.json> <poses.json>
    blender -b <car.blend> --factory-startup -P tools/blender/seat_fill.py -- <poses.json> <out dir>
        [--seat 0.38,-0.061,0.2814] [--front -0.31] [--sink 0.005]

Roblox's upright sit holds the R6 torso's bottom about 35 cm above the SVJ driver's cushion at the
hips and the thighs 15 to 19 cm above its front (measured on the cabin mesh, 2026-10-28), and the
hips cannot come down: the resting hands would be out of the arms' reach. So the cloth comes down
instead. Over a grid of the seat frame (metres: x right, y up, z back, the DriverSeat part's) the
cushion is found by rays straight down; the seat's underside is that surface sunk by --sink; its
top runs inside the torso's bottom under the torso, then just inside the thigh tubes (the lowest
of every pose in poses.json, so no pose opens a seam) as far forward as the cushion goes
(--front, its front edge). Its sides follow the thighs as they splay toward the knees.

Writes pelvis.glb (studs, x right, y up, z back about its own box centre, like driver_legs.py's
meshes), seat_fill.json (the box centre in the R6 torso's own space at character scale 1, the
studs Config/DriverLegs.PELVIS_CENTRE takes; its size; how far its underside lies from the cabin
and the seam against every thigh pose). Look at it in Studio: in the blend the door is shut.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

STUDS_PER_METRE = 1.5 / 0.28
# Into the torso's bottom and up inside the thigh tubes, so the joins never show.
INTO_TORSO = 0.02
# The right thigh's underside moves up to 3.8 cm between its poses at the cushion's front edge:
# the cloth runs this far inside its lowest pose.
INTO_THIGH = 0.045
# Beyond each thigh's centre line, across the car: about the tube's own half-width; never past
# the bucket's bolsters, where a ray would find the sill or the floor instead of the cushion.
THIGH_SIDE = 0.07
BUCKET_HALF_WIDTH = 0.19
# Grid across and along, and the soft edge's inset.
COLUMNS = 18
ROWS = 26
EDGE = 0.012
# The sides are cloth, not a box: top and bottom pull in by this much and the wall swells back out
# to the footprint half way down, over WALL_STEPS rings.
SWELL = 0.03
WALL_STEPS = 8


def option(args, name, default):
    return args[args.index(name) + 1] if name in args else default


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def cabin():
    trees = []
    for obj in bpy.data.objects:
        if obj.type != "MESH" or len(obj.data.polygons) == 0 or "Belt" in obj.name:
            continue
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bm.transform(obj.matrix_world)
        trees.append(BVHTree.FromBMesh(bm))
        bm.free()
    return trees


def first_below(trees, point):
    best = None
    for tree in trees:
        hit = tree.ray_cast(point, Vector((0, 0, -1)), 1.0)
        if hit[0] is not None and (best is None or hit[3] < best):
            best = hit[3]
    return best


# driver_legs.py's thigh tube depth (half-size, metres) along the thigh.
def thigh_depth(t):
    return lerp(0.075, 0.06, smoothstep(t))


def thigh_at(pose, z):
    """The thigh's centre line where it crosses z: (x, y, t along the thigh)."""
    hip, knee = pose["hip"], pose["knee"]
    t = (hip[2] - z) / (hip[2] - knee[2])
    t = min(max(t, 0.0), 1.0)
    return lerp(hip[0], knee[0], t), lerp(hip[1], knee[1], t), t


def main(args):
    entries = json.load(open(args[0]))
    out = args[1]
    os.makedirs(out, exist_ok=True)
    seat = Vector(tuple(float(v) for v in option(args, "--seat", "0.38,-0.061,0.2814").split(",")))
    front = float(option(args, "--front", "-0.31"))
    sink = float(option(args, "--sink", "0.005"))
    torso = next(e for e in entries if e["name"] == "torso")
    right = [e for e in entries if e["side"] == "right"]
    left = [e for e in entries if e["side"] == "left"]
    trees = cabin()

    def blend(x, y, z):
        return seat + Vector((-x, z, y))

    centre, size = torso["centre"], torso["size"]
    torso_bottom = centre[1] - size[1] / 2
    torso_front = centre[2] - size[2] / 2
    back = centre[2] + size[2] / 2 - 0.01

    def thigh(poses, z):
        """One thigh at z over its poses: the lowest underside, and its centre line's x range."""
        lowest, low_x, high_x = 9.0, 9.0, -9.0
        for pose in poses:
            x, y, t = thigh_at(pose, z)
            lowest = min(lowest, y - thigh_depth(t))
            low_x, high_x = min(low_x, x), max(high_x, x)
        return lowest, low_x, high_x

    def top(x, z):
        """Inside the torso, then inside each thigh's lowest underside, blended across between."""
        left_under, _, left_x = thigh(left, z)
        right_under, right_x, _ = thigh(right, z)
        across = smoothstep((x - left_x) / (right_x - left_x))
        under = lerp(left_under, right_under, across)
        share = smoothstep((torso_front + 0.01 - z) / 0.05)
        return lerp(torso_bottom + INTO_TORSO, under + INTO_THIGH, share)

    def sides(z):
        _, low_x, _ = thigh(left, z)
        _, _, high_x = thigh(right, z)
        low_x, high_x = low_x - THIGH_SIDE, high_x + THIGH_SIDE
        half = size[0] / 2
        share = smoothstep((torso_front - z) / 0.06)
        return (
            max(lerp(-half, low_x, share), -BUCKET_HALF_WIDTH),
            min(lerp(half, high_x, share), BUCKET_HALF_WIDTH),
        )

    # The grid: rows along z from the back to the front edge, columns across.
    grid_top, grid_bottom, missed = [], [], 0
    for i in range(ROWS + 1):
        z = lerp(back - SWELL, front + SWELL, i / ROWS)
        x0, x1 = sides(z)
        x0, x1 = x0 + SWELL, x1 - SWELL
        row_top, row_bottom = [], []
        for j in range(COLUMNS + 1):
            x = lerp(x0, x1, j / COLUMNS)
            y_top = top(x, z)
            start = y_top - 0.005
            drop = first_below(trees, blend(x, start, z))
            if drop is None:
                missed += 1
                drop = 0.2
            bottom = start - drop - sink
            # A soft edge: the outermost ring pulls in by EDGE top and bottom.
            edge = i in (0, ROWS) or j in (0, COLUMNS)
            row_top.append(Vector((x, y_top - (EDGE if edge else 0), z)))
            row_bottom.append(Vector((x, bottom + (EDGE if edge else 0), z)))
        grid_top.append(row_top)
        grid_bottom.append(row_bottom)

    bm = bmesh.new()
    tops = [[bm.verts.new(p) for p in row] for row in grid_top]
    bottoms = [[bm.verts.new(p) for p in row] for row in grid_bottom]
    for i in range(ROWS):
        for j in range(COLUMNS):
            bm.faces.new((tops[i][j], tops[i][j + 1], tops[i + 1][j + 1], tops[i + 1][j]))
            bm.faces.new((bottoms[i][j], bottoms[i + 1][j], bottoms[i + 1][j + 1], bottoms[i][j + 1]))
    ring = (
        [(0, j) for j in range(COLUMNS + 1)]
        + [(i, COLUMNS) for i in range(1, ROWS + 1)]
        + [(ROWS, j) for j in range(COLUMNS - 1, -1, -1)]
        + [(i, 0) for i in range(ROWS - 1, 0, -1)]
    )

    def outward(i, j):
        x = (1 if j == COLUMNS else -1 if j == 0 else 0)
        z = (1 if i == 0 else -1 if i == ROWS else 0)
        direction = Vector((x, 0, z))
        return direction.normalized()

    walls = []
    for i, j in ring:
        upper, lower = grid_top[i][j], grid_bottom[i][j]
        out_dir = outward(i, j)
        column = [tops[i][j]]
        for step in range(1, WALL_STEPS):
            share = step / WALL_STEPS
            point = upper.lerp(lower, share) + out_dir * SWELL * math.sin(math.pi * share)
            column.append(bm.verts.new(point))
        column.append(bottoms[i][j])
        walls.append(column)
    for k in range(len(ring)):
        a, b = walls[k], walls[(k + 1) % len(ring)]
        for step in range(WALL_STEPS):
            bm.faces.new((a[step], a[step + 1], b[step + 1], b[step]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # About its box centre, where Roblox puts an imported mesh's origin; the box in the seat frame.
    low = Vector(tuple(min(v.co[k] for v in bm.verts) for k in range(3)))
    high = Vector(tuple(max(v.co[k] for v in bm.verts) for k in range(3)))
    box = (low + high) / 2
    for vert in bm.verts:
        vert.co -= box
    data = bpy.data.meshes.new("Pelvis")
    bm.to_mesh(data)
    bm.free()
    for polygon in data.polygons:
        polygon.use_smooth = True
    obj = bpy.data.objects.new("Pelvis", data)
    bpy.context.collection.objects.link(obj)

    # driver_legs.py's export: Roblox (x, y, z) is Blender (-x, z, y) after the glTF importer.
    copy = obj.copy()
    copy.data = obj.data.copy()
    bpy.context.collection.objects.link(copy)
    swap = Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    copy.data.transform(swap @ Matrix.Diagonal((STUDS_PER_METRE,) * 3 + (1,)))
    bpy.ops.object.select_all(action="DESELECT")
    copy.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, "pelvis.glb"), use_selection=True, export_materials="NONE")
    bpy.data.objects.remove(copy)

    # The seam: how far the cloth's top runs inside each thigh pose's underside along the cushion.
    seam = 9.0
    for pose in right + left:
        for i in range(1, ROWS):
            z = lerp(back, front, i / ROWS)
            if z > torso_front - 0.05:
                continue
            x, y, t = thigh_at(pose, z)
            seam = min(seam, top(x, z) - (y - thigh_depth(t)))

    # Checked on the built mesh, by another route than the rays that shaped it: each underside
    # vertex's nearest cabin surface (the soft edge's ring is left out, it is pulled up on purpose).
    nearest = []
    for i in range(1, ROWS):
        for j in range(1, COLUMNS):
            point = grid_bottom[i][j]
            found = min(
                (tree.find_nearest(blend(point.x, point.y, point.z), 1.0) for tree in trees),
                key=lambda hit: hit[3] if hit[0] is not None else 9.0,
            )
            nearest.append(found[3] if found[0] is not None else 9.0)

    unit = torso["studsPerTorsoUnit"]
    report = {
        "pelvisCentreStuds": [round((box[k] - centre[k]) / unit, 4) for k in range(3)],
        "sizeMetres": [round(high[k] - low[k], 4) for k in range(3)],
        "sizeStuds": [round((high[k] - low[k]) * STUDS_PER_METRE, 4) for k in range(3)],
        "undersideToCabinCm": [round(min(nearest) * 100, 2), round(max(nearest) * 100, 2)],
        "raysMissed": missed,
        "seamInsideThighsCm": round(seam * 100, 2),
        "front": front,
        "triangles": sum(len(p.vertices) - 2 for p in data.polygons),
    }
    json.dump(report, open(os.path.join(out, "seat_fill.json"), "w"), indent=1)
    print("SEAT_FILL " + json.dumps(report))


main(sys.argv[sys.argv.index("--") + 1 :])
