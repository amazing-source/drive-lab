"""
The driver's door pull strap (#31): measures where it can hang, builds it, and renders it, run
headless by Blender on the door rig (hero_car_door_render.py's svj_door_rig.blend):

    blender -b --factory-startup -P tools/blender/hero_car_door_strap.py -- measure <rig.blend> <out dir> [--full-length]
    blender -b --factory-startup -P tools/blender/hero_car_door_strap.py -- build <rig.blend> <door manifest.json> <out dir>
    blender -b --factory-startup -P tools/blender/hero_car_door_strap.py -- render <rig.blend> <out dir>
    blender -b --factory-startup -P tools/blender/hero_car_door_strap.py -- tilt <rig.blend> <out dir>

Blender metres of the rig (nose along -Y, Z up, the driver's door on +X). The strap is a 25 cm
loop hanging from ANCHOR, the door card's inner lower edge nearest the seated left shoulder. It is
soft: with the door nearly shut the cabin trim is closer below the anchor than the strap is long,
so it hangs straight down only as far as the trim lets it (the rest of a real strap would lie on
the trim), and while the seated driver pulls the door down by it, it runs taut from the anchor to
the palm. The game does the same (Rules/DoorStrap); this script gives it its numbers.

`measure` writes <out dir>/strap.json: the card's facing at the anchor; the free length straight
down at every degree of the door's swing (strap-wide rays against the body and the door, less
MARGIN), simplified to a table the binding carries; and the old short strap's faces on the door
card (red texels in OLD_STRAP_BOX), which `build` cuts out, since the strap moves rather than
doubles. It then checks every pose against the meshes: hanging at the table's length from shut
to fully open, held toward the palm from the grab angle to shut, and the swing between the two at
both ends; it exits 1 on any pose that cuts the car. `--full-length` hangs the whole 25 cm at every
angle instead, the deliberately wrong pose the check must fail on.

`build` writes strap.glb and manifest.json in import studs, as hero_car_door_export.py does
(placement from the door's manifest): DoorStrap, the loop modelled shut and hanging, its top at
the anchor, its texture coordinates inside the old strap's red island so it takes the door card's
own look; and DoorInterior without the old strap, which must keep the place part's size and
origin so ApplyMesh swaps it in place.

`render` renders the strap hanging shut, at 5 degrees and fully open, held toward the palm (a
yellow ball) at 30, 20, 10 and 2 degrees, from the cabin and (shut, 30, open) from outside, plus
the door card before and after the cut.

`tilt` writes tilt.json: the alternative to shortening the hanging strap, the smallest turn about
its top that lets all 25 cm clear the trim at each angle up to 16 degrees. Measured 2026-10-28 and
not adopted: shut, it is a 57-63 degree swing along the card (the strap no longer hangs), and from
2 to 8 degrees the clearing turn jumps between unrelated directions a quarter degree apart, so a
strap following it would flick about.
"""

import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

STUDS_PER_METRE = 1 / 0.28
CENTRE_OF_MASS = Vector((0.0, 0.279, 0.4314))
PIVOT = Vector((0.9, -1.14, 0.67))
AXIS = Vector((0.82364, -0.26762, -0.5)).normalized()
OPEN_DEGREES = 90.8
# The door card's inner lower edge nearest the seated left shoulder over 0 to 30 degrees (#9), the
# point the animation's palm is aimed through (tools/anim car_entry_keys.py strap_grab).
ANCHOR = Vector((0.646, -0.264, 0.212))
# The strap's top sits this far off the card's face (half its thickness and a little air), and its
# first DRAPE rests against the door it is sewn to: a door face there is contact, not a cut.
OFF_CARD = 0.004
DRAPE = 0.04
# The strap hangs leaned this many degrees off the card into the cabin: fully open, the card leans
# over the anchor and a strap straight down ran into it 5 cm below its top.
LEAN = 5.0
# The seated driver's left shoulder joint and the rigid R6 arm's reach to the palm, in car metres
# (drive-lab-assets/door/strap.log; tools/anim car_entry_keys.py ARM_REACH at Driving.DRIVER_SCALE).
SHOULDER = Vector((0.54, -0.061, 0.652))
REACH = 0.2304
GRAB_DEGREES = 30.0
LENGTH = 0.25
WIDTH = 0.03
THICKNESS = 0.003
# Clear of the trim by this much at the strap's end.
MARGIN = 0.005
MIN_LENGTH = 0.02
# The strap's top must sit on the door: no further than this from its mesh.
ATTACHED = 0.008
# A table point is kept where leaving it out would misplace the strap's end by more than this.
TABLE_TOLERANCE = 0.004
OLD_STRAP_BOX = ((0.70, -0.39, 0.38), (0.76, -0.29, 0.55))
DOWN = Vector((0, 0, -1))


def args():
    rest = sys.argv[sys.argv.index("--") + 1 :]
    return rest[0], [a for a in rest[1:] if not a.startswith("--")], [a for a in rest[1:] if a.startswith("--")]


def car_point(v):
    return {"forward": round(-(v.y - CENTRE_OF_MASS.y), 5), "right": round(-v.x, 5), "up": round(v.z - CENTRE_OF_MASS.z, 5)}


def car_direction(v):
    return {"forward": round(-v.y, 5), "right": round(-v.x, 5), "up": round(v.z, 5)}


def turn(degrees):
    return Matrix.Translation(PIVOT) @ Matrix.Rotation(math.radians(degrees), 4, AXIS) @ Matrix.Translation(-PIVOT)


def spin(degrees):
    return Matrix.Rotation(math.radians(degrees), 3, AXIS)


def door_hinge():
    return bpy.data.objects["DoorHinge"]


def tree(objs, matrix=None):
    bm = bmesh.new()
    for obj in objs:
        piece = bmesh.new()
        piece.from_mesh(obj.data)
        piece.transform((matrix or Matrix()) @ obj.matrix_world)
        mesh = bpy.data.meshes.new("tree")
        piece.to_mesh(mesh)
        bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
        piece.free()
    return BVHTree.FromBMesh(bm)


class Car:
    def __init__(self):
        hinge = door_hinge()
        self.door = list(hinge.children)
        self.body = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.parent is not hinge]
        self.body_tree = tree(self.body)
        self.door_trees = {}

    def door_tree(self, degrees):
        key = round(degrees, 3)
        if key not in self.door_trees:
            self.door_trees[key] = tree(self.door, turn(degrees))
        return self.door_trees[key]

    def clearance(self, degrees, direction, facing, length):
        """How far a strap-wide band runs from the strap's top along `direction` before it meets the car."""
        anchor = turn(degrees) @ TOP
        across = direction.cross(facing)
        if across.length < 1e-6:
            across = AXIS.cross(direction)
        across.normalize()
        through = across.cross(direction).normalized()
        nearest = length
        for a in (-WIDTH / 2 + 0.001, 0.0, WIDTH / 2 - 0.001):
            for t in (-THICKNESS / 2, THICKNESS / 2):
                start = anchor + across * a + through * t
                hit = self.body_tree.ray_cast(start, direction, length)
                if hit[0] is not None:
                    nearest = min(nearest, hit[3])
                if length > DRAPE:
                    hit = self.door_tree(degrees).ray_cast(start + direction * DRAPE, direction, length - DRAPE)
                    if hit[0] is not None:
                        nearest = min(nearest, hit[3] + DRAPE)
        return nearest


def card_facing():
    """Area-weighted normal of the door card's cabin-facing faces within 4 cm of the anchor."""
    card = bpy.data.objects["Door_Interior"]
    bm = bmesh.new()
    bm.from_mesh(card.data)
    bm.transform(card.matrix_world)
    total = Vector()
    for face in bm.faces:
        if (face.calc_center_median() - ANCHOR).length < 0.04 and face.normal.x < -0.3:
            total += face.normal * face.calc_area()
    bm.free()
    return total.normalized()


def strap_top(facing):
    return ANCHOR + facing * OFF_CARD


def hanging(degrees):
    """Straight down, leaned LEAN off the card into the cabin (Rules/DoorStrap.rest)."""
    facing = spin(degrees) @ FACING
    away = facing - DOWN * facing.dot(DOWN)
    away = away.normalized() if away.length > 1e-6 else Vector((-1, 0, 0))
    return (DOWN * math.cos(math.radians(LEAN)) + away * math.sin(math.radians(LEAN))).normalized()


def grab_point(degrees):
    anchor = turn(degrees) @ ANCHOR
    return SHOULDER + REACH * (anchor - SHOULDER).normalized()


def simplify(samples):
    """The fewest (degrees, length) rows whose straight lines never run longer than a sample and
    never more than TABLE_TOLERANCE shorter."""
    kept = [samples[0]]
    start = 0
    for end in range(2, len(samples)):
        a, b = samples[start], samples[end]
        for s in samples[start + 1 : end]:
            length = a[1] + (b[1] - a[1]) * (s[0] - a[0]) / (b[0] - a[0])
            if length > s[1] + 1e-4 or length < s[1] - TABLE_TOLERANCE:
                kept.append(samples[end - 1])
                start = end - 1
                break
    kept.append(samples[-1])
    return kept


def hang_length(table, degrees):
    """The table's length at a door angle, linear between rows, held past either end."""
    if degrees >= table[-1][0]:
        return table[-1][1]
    for a, b in zip(table, table[1:]):
        if degrees <= b[0]:
            return a[1] + (b[1] - a[1]) * (degrees - a[0]) / (b[0] - a[0])
    return table[-1][1]


def texture_pixels(name):
    image = bpy.data.images[name]
    width, height = image.size
    return np.array(image.pixels[:], dtype=np.float32).reshape(height, width, 4), width, height


def old_strap(card):
    """Faces of the door card's old short strap: whole islands with red texels inside OLD_STRAP_BOX."""
    pixels, width, height = texture_pixels("interior_color.png")
    low, high = (Vector(c) for c in OLD_STRAP_BOX)
    bm = bmesh.new()
    bm.from_mesh(card.data)
    bm.transform(card.matrix_world)
    bm.faces.ensure_lookup_table()
    uv = bm.loops.layers.uv.active
    seen, picked, islands = set(), [], []
    for face in bm.faces:
        if face.index in seen:
            continue
        island, stack = [], [face]
        seen.add(face.index)
        while stack:
            current = stack.pop()
            island.append(current)
            for edge in current.edges:
                for other in edge.link_faces:
                    if other.index not in seen:
                        seen.add(other.index)
                        stack.append(other)
        points = [v.co for f in island for v in f.verts]
        if not all(low[i] <= p[i] <= high[i] for p in points for i in range(3)):
            continue
        red = 0
        for f in island:
            u = sum(loop[uv].uv.x for loop in f.loops) / len(f.loops)
            v = sum(loop[uv].uv.y for loop in f.loops) / len(f.loops)
            r, g, b, _ = pixels[int((v % 1) * height) % height, int((u % 1) * width) % width]
            red += r > 0.35 and g < 0.12 and b < 0.12
        if red:
            uvs = [loop[uv].uv.copy() for f in island for loop in f.loops]
            area = sum(f.calc_area() for f in island)
            islands.append({"faces": len(island), "area": area, "uv": [min(u.x for u in uvs), min(u.y for u in uvs), max(u.x for u in uvs), max(u.y for u in uvs)]})
            picked.extend(f.index for f in island)
    bm.free()
    return sorted(picked), islands


def red_rect(islands):
    """The old strap's largest island whose texels are a flat red: the new strap's texture coordinates."""
    pixels, width, height = texture_pixels("interior_color.png")
    best = None
    for island in sorted(islands, key=lambda i: -i["area"]):
        u0, v0, u1, v1 = island["uv"]
        block = pixels[int(v0 * height) : int(v1 * height) + 1, int(u0 * width) : int(u1 * width) + 1, :3]
        mean, spread = block.reshape(-1, 3).mean(axis=0), block.reshape(-1, 3).std(axis=0).max()
        if mean[0] > 0.35 and mean[1] < 0.15 and spread < 0.08:
            best = {"uv": island["uv"], "meanColour": [round(float(c), 3) for c in mean], "spread": round(float(spread), 3)}
            break
    assert best, "no flat red island in the old strap"
    return best


def free_length(car, degrees):
    free = car.clearance(degrees, hanging(degrees), spin(degrees) @ FACING, LENGTH + MARGIN) - MARGIN
    return max(MIN_LENGTH, min(LENGTH, free))


def measure(out, full_length):
    car = Car()
    nearest = car.door_tree(0.0).find_nearest(TOP)
    assert nearest[3] <= ATTACHED, f"the strap's top is {nearest[3]:.4f} m off the door"
    angles = [step / 4 for step in range(0, 4 * int(OPEN_DEGREES) + 1)] + [OPEN_DEGREES]
    free = [free_length(car, degrees) for degrees in angles]
    # Each sample no longer than its neighbours, so a straight line between two never crosses a
    # narrow ridge between them.
    samples = [
        (degrees, round(min(free[max(0, i - 1) : i + 2]), 4)) for i, degrees in enumerate(angles)
    ]
    table = simplify(samples)
    card = bpy.data.objects["Door_Interior"]
    faces, islands = old_strap(card)
    held = []
    for degrees in (GRAB_DEGREES, 25, 20, 15, 10, 5, 2, 0):
        top = turn(degrees) @ TOP
        hand = grab_point(degrees)
        held.append({"degrees": degrees, "top": list(top), "palm": list(hand), "palmCar": car_point(hand), "distance": round((hand - top).length, 4)})
    report = {
        "anchorBlender": list(ANCHOR),
        "topBlender": [round(c, 5) for c in TOP],
        "topCar": car_point(TOP),
        "topOffDoor": round(nearest[3], 4),
        "facingBlender": [round(c, 5) for c in FACING],
        "facingCar": car_direction(FACING),
        "length": LENGTH,
        "leanDegrees": LEAN,
        "hangTable": [{"degrees": a, "radians": round(math.radians(a), 5), "length": l} for a, l in table],
        "hangSamples": samples,
        "held": held,
        "oldStrap": {"faces": len(faces), "islands": islands},
        "redRect": red_rect(islands),
    }
    (out / "strap.json").write_text(json.dumps(report, indent=1))
    print("TOP", [round(c, 4) for c in TOP], car_point(TOP), "off the door", round(nearest[3], 4))
    print("FACING", [round(c, 4) for c in FACING], car_direction(FACING))
    print("HANG TABLE", table)
    print("HELD", [(h["degrees"], h["distance"]) for h in held])
    print("OLD STRAP", len(faces), "faces in", len(islands), "islands; red rect", report["redRect"])
    failures = check(car, table, full_length)
    for failure in failures:
        print("CUTS", failure)
    print(f"CHECK {'FAILED' if failures else 'PASSED'}: {len(failures)} poses cut the car")
    return 1 if failures else 0


def check(car, table, full_length):
    """Every pose the game can show: hanging at every tenth of a degree, held from the grab angle to
    shut, and the swing up to the hand at the grab angle. The hand lets go at shut and the strap
    drops back in one frame (the swing down through the cabin would cross the seat's bolster)."""
    failures = []

    def pose(label, degrees, direction, length):
        found = car.clearance(degrees, direction, spin(degrees) @ FACING, length)
        if found < length - 1e-4:
            failures.append(f"{label} at {degrees:.2f} deg: meets the car {found:.3f} m along a {length:.3f} m strap")

    for step in range(0, 10 * int(OPEN_DEGREES) + 9):
        degrees = min(step / 10, OPEN_DEGREES)
        pose("hanging", degrees, hanging(degrees), LENGTH if full_length else hang_length(table, degrees))
    for step in range(0, 2 * int(GRAB_DEGREES) + 1):
        degrees = step / 2
        top = turn(degrees) @ TOP
        hand = grab_point(degrees)
        pose("held", degrees, (hand - top).normalized(), min(LENGTH, (hand - top).length))
    top = turn(GRAB_DEGREES) @ TOP
    hand = grab_point(GRAB_DEGREES)
    aim = (hand - top).normalized()
    rest = hanging(GRAB_DEGREES)
    length = hang_length(table, GRAB_DEGREES)
    for k in range(1, 8):
        share = k / 8
        direction = (rest * (1 - share) + aim * share).normalized()
        pose(f"swing {share:.2f}", GRAB_DEGREES, direction, length * (1 - share) + min(LENGTH, (hand - top).length) * share)
    return failures


def tilt(out):
    """The alternative to shortening (asked by the entry lead): at every door angle where the trim
    stops a full-length strap hanging straight down, the smallest turn about its top that lets
    all 25 cm hang clear, as a soft strap pushed aside by the trim would lie. Two turns: a swing
    along the card (about its facing) and a lean away from it into the cabin. Beyond the clearance
    check's own rays, a tilted strap must also clear the door from 5 mm below its top, since it
    then runs along the card rather than away from it."""
    car = Car()
    rows = []
    for step in range(0, 4 * 16 + 1):
        degrees = step / 4
        facing = spin(degrees) @ FACING
        rest = hanging(degrees)
        straight = car.clearance(degrees, rest, facing, LENGTH + MARGIN) - MARGIN
        if straight >= LENGTH - 1e-4:
            rows.append({"degrees": degrees, "straight": round(straight, 4), "swing": 0, "lean": 0})
            continue
        inboard = facing - rest * facing.dot(rest)
        inboard.normalize()
        top = turn(degrees) @ TOP
        best = None
        for swing in range(-90, 91, 3):
            for lean in range(0, 91, 3):
                leaned = rest * math.cos(math.radians(lean)) + inboard * math.sin(math.radians(lean))
                direction = Matrix.Rotation(math.radians(swing), 3, facing) @ leaned
                cost = math.hypot(swing, lean)
                if best and cost >= best[0]:
                    continue
                if car.clearance(degrees, direction, facing, LENGTH + MARGIN) < LENGTH + MARGIN - 1e-4:
                    continue
                hit = car.door_tree(degrees).ray_cast(top + direction * 0.005, direction, LENGTH)
                if hit[0] is not None:
                    continue
                best = (cost, swing, lean)
        rows.append(
            {
                "degrees": degrees,
                "straight": round(straight, 4),
                "swing": best[1] if best else None,
                "lean": best[2] if best else None,
            }
        )
        print("TILT", rows[-1])
    (out / "tilt.json").write_text(json.dumps(rows, indent=1))
    return 0


def strap_mesh(rect):
    """The loop, top at the origin, hanging along -Z, its faces across X, folded at the bottom."""
    u0, v0, u1, v1 = rect
    inset_u, inset_v = (u1 - u0) * 0.15, (v1 - v0) * 0.25
    u0, u1, v0, v1 = u0 + inset_u, u1 - inset_u, v0 + inset_v, v1 - inset_v
    radius = THICKNESS / 2
    profile = [(radius, 0.0), (radius, -LENGTH + radius)]
    for k in range(1, 6):
        angle = math.pi * k / 6
        profile.append((radius * math.cos(angle), -LENGTH + radius - radius * math.sin(angle)))
    profile += [(-radius, -LENGTH + radius), (-radius, 0.0)]
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    rings = [[bm.verts.new((x, y, z)) for y, z in profile] for x in (-WIDTH / 2, WIDTH / 2)]
    count = len(profile)

    def coords(vert):
        along = -vert.co.z / LENGTH
        across = (vert.co.x + WIDTH / 2) / WIDTH
        return (u0 + (u1 - u0) * along, v0 + (v1 - v0) * across)

    faces = []
    for i in range(count):
        j = (i + 1) % count
        faces.append(bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i])))
    faces.append(bm.faces.new(list(reversed(rings[0]))))
    faces.append(bm.faces.new(rings[1]))
    for face in faces:
        for loop in face.loops:
            loop[uv].uv = coords(loop.vert)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("DoorStrap")
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def strap_frame(direction, facing):
    """World matrix of the strap: its -Z along `direction`, its faces' normal (Y) near `facing`."""
    z = -direction.normalized()
    y = facing - z * facing.dot(z)
    y = y.normalized() if y.length > 1e-6 else AXIS.cross(z).normalized()
    x = y.cross(z)
    return Matrix((x, y, z)).transposed().to_4x4()


def bounds(obj):
    points = [obj.matrix_world @ v.co for v in obj.data.vertices]
    low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    return low, high


def to_roblox(v):
    return [round(-v.x, 4), round(v.z, 4), round(v.y, 4)]


def build(manifest_path, out):
    report = json.loads((out / "strap.json").read_text())
    door_manifest = json.loads(Path(manifest_path).read_text())
    placement = Vector(tuple(door_manifest["placementMetres"][k] for k in ("x", "y", "z")))
    place = {p["name"]: p for p in door_manifest["parts"]}
    to_studs = Matrix.Scale(STUDS_PER_METRE, 4) @ Matrix.Translation(placement)
    card = bpy.data.objects["Door_Interior"]
    faces, _ = old_strap(card)
    assert len(faces) == report["oldStrap"]["faces"], "the old strap changed since measure"

    # The door card without the old strap, in import studs and centred like the place's part.
    cut = card.copy()
    cut.data = card.data.copy()
    cut.parent = None
    bpy.context.scene.collection.objects.link(cut)
    bm = bmesh.new()
    bm.from_mesh(cut.data)
    bm.transform(to_studs @ card.matrix_world)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in faces], context="FACES")
    bm.to_mesh(cut.data)
    bm.free()
    cut.matrix_world = Matrix()
    cut.name = cut.data.name = "DoorInterior"
    low, high = bounds(cut)
    centre = (low + high) / 2
    cut.data.transform(Matrix.Translation(-centre))
    cut.location = centre
    entry = place["DoorInterior"]
    size = [high.x - low.x, high.z - low.z, high.y - low.y]
    drift = max(max(abs(a - b) for a, b in zip(to_roblox(centre), entry["origin"])), max(abs(a - b) for a, b in zip(size, entry["size"])))
    print(f"DoorInterior: origin {to_roblox(centre)} size {[round(s, 4) for s in size]} vs place {entry['origin']} {entry['size']} (drift {drift:.4f})")
    assert drift < 2e-3, "DoorInterior would move: its origin or size changed"

    # The strap in its own frame, full length and centred: it hangs along the part's -Y (Blender
    # -Z), its faces' normal along Z (Blender Y), so the game aims it by its CFrame and sets its
    # length by Size.Y (Rules/DoorStrap). The place part is posed from `strap` below.
    strap = bpy.data.objects.new("DoorStrap", strap_mesh(report["redRect"]["uv"]))
    strap.data.materials.append(card.material_slots[0].material)
    bpy.context.scene.collection.objects.link(strap)
    shut_length = report["hangTable"][0]["length"]
    facing = Vector(report["facingBlender"])
    shut_direction = hanging(0.0)
    strap.data.transform(Matrix.Scale(STUDS_PER_METRE, 4))
    low, high = bounds(strap)
    strap.data.transform(Matrix.Translation(-(low + high) / 2))
    strap.location = Vector()
    top = to_studs @ TOP
    frame = strap_frame(shut_direction, facing)
    bpy.context.view_layer.update()

    bpy.ops.object.select_all(action="DESELECT")
    for obj in (cut, strap):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = strap
    bpy.ops.export_scene.gltf(
        filepath=str(out / "strap.glb"),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_normals=True,
        export_tangents=True,
        # The place part keeps its own SurfaceAppearance; the strap copies the door card's.
        export_materials="NONE",
    )
    parts = []
    for obj in (cut, strap):
        obj.data.calc_loop_triangles()
        low, high = bounds(obj)
        parts.append({"name": obj.name, "triangles": len(obj.data.loop_triangles), "origin": to_roblox(obj.location), "size": [round(high.x - low.x, 5), round(high.z - low.z, 5), round(high.y - low.y, 5)]})
    manifest = {
        "studsPerMetre": STUDS_PER_METRE,
        "placementMetres": door_manifest["placementMetres"],
        "parts": parts,
        # Where the place part goes, hanging with the door shut: its top at topStuds, its -Y
        # along shutDirection, its Z near facing, Size.Y = shutLengthStuds.
        "strap": {
            "topStuds": to_roblox(top),
            "lengthStuds": round(LENGTH * STUDS_PER_METRE, 5),
            "shutLengthStuds": round(shut_length * STUDS_PER_METRE, 5),
            # The part's axes: its mesh is the Blender mesh through to_roblox, so its X is Blender
            # local -X, its Y local Z (up the strap) and its Z local Y (the faces' normal).
            "xAxis": [-c for c in to_roblox(frame.col[0].to_3d())],
            "yAxis": to_roblox(frame.col[2].to_3d()),
            "zAxis": to_roblox(frame.col[1].to_3d()),
            "note": "import studs and Roblox axes (to_roblox)",
        },
        # The model binding's numbers (Config/Cars/SVJModel door.strap): car frame from the
        # centre of mass, metres, door angles in radians.
        "binding": {
            "top": report["topCar"],
            "facing": report["facingCar"],
            "length": LENGTH,
            "lean": round(math.radians(LEAN), 5),
            "hang": [{"angle": row["radians"], "length": row["length"]} for row in report["hangTable"]],
        },
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1))
    for part in parts:
        print("EXPORTED", part)
    return 0


def pose_door(degrees):
    hinge = door_hinge()
    hinge.matrix_world = REST_HINGE @ Matrix.Rotation(math.radians(degrees), 4, "X")
    bpy.context.view_layer.update()


def render(out):
    report = json.loads((out / "strap.json").read_text())
    table = [(p["degrees"], p["length"]) for p in report["hangTable"]]
    facing = Vector(report["facingBlender"])
    card = bpy.data.objects["Door_Interior"]
    strap = bpy.data.objects.new("DoorStrap", strap_mesh(report["redRect"]["uv"]))
    strap.data.materials.append(card.material_slots[0].material)
    bpy.context.scene.collection.objects.link(strap)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 800

    def place(degrees, held):
        pose_door(degrees)
        anchor = turn(degrees) @ TOP
        if held:
            hand = grab_point(degrees)
            direction, length = (hand - anchor).normalized(), min(LENGTH, (hand - anchor).length)
        else:
            direction, length = hanging(degrees), hang_length(table, degrees)
        strap.matrix_world = Matrix.Translation(anchor) @ strap_frame(direction, spin(degrees) @ facing) @ Matrix.Diagonal((1, 1, length / LENGTH, 1))
        bpy.context.view_layer.update()
        return anchor + direction * (length / 2)

    def shot(name, location, target, lens):
        data = bpy.data.cameras.new(name)
        data.lens = lens
        data.clip_start = 0.005
        camera = bpy.data.objects.new(name, data)
        scene.collection.objects.link(camera)
        camera.location = Vector(location)
        camera.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
        scene.camera = camera
        scene.render.filepath = str(out / f"{name}.png")
        bpy.ops.render.render(write_still=True)

    # A small yellow ball at the palm where the hand holds the strap (the avatar is not in the rig).
    ball = bmesh.new()
    bmesh.ops.create_uvsphere(ball, u_segments=16, v_segments=8, radius=0.012)
    mesh = bpy.data.meshes.new("Palm")
    ball.to_mesh(mesh)
    ball.free()
    marker = bpy.data.materials.new("Palm")
    marker.diffuse_color = (1.0, 0.85, 0.1, 1.0)
    mesh.materials.append(marker)
    palm = bpy.data.objects.new("Palm", mesh)
    scene.collection.objects.link(palm)
    poses = (
        ("shut", 0.0, False),
        ("hang05", 5.0, False),
        ("grab", GRAB_DEGREES, True),
        ("held20", 20.0, True),
        ("held10", 10.0, True),
        ("held02", 2.0, True),
        ("open", OPEN_DEGREES, False),
    )
    # Cameras look at the strap's middle: from the driver's side of the cabin, and from outboard
    # behind the door (an offset from the strap).
    cabin = {
        "shut": (0.30, 0.15, 0.80),
        "hang05": (0.30, 0.15, 0.80),
        "grab": (0.30, 0.25, 0.85),
        "held20": (0.30, 0.25, 0.85),
        "held10": (0.30, 0.25, 0.85),
        "held02": (0.30, 0.25, 0.85),
        "open": (0.25, 0.20, 0.70),
    }
    outside = {"shut": (0.95, 0.45, 0.75), "grab": (1.1, 0.95, 0.3), "open": (1.3, 0.9, -0.2)}
    # The card around the old strap before the cut (the rig as it is), then without it, as the
    # game's DoorInterior will be, for every pose and for card_after.
    pose_door(0.0)
    strap.hide_render = True
    palm.hide_render = True
    shot("card_before", (0.25, -0.20, 0.55), (0.72, -0.32, 0.38), 35)
    faces, _ = old_strap(card)
    bm = bmesh.new()
    bm.from_mesh(card.data)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in faces], context="FACES")
    bm.to_mesh(card.data)
    bm.free()
    strap.hide_render = False
    for label, degrees, held in poses:
        middle = place(degrees, held)
        palm.location = grab_point(degrees)
        palm.hide_render = not held
        shot(f"strap_{label}_cabin", cabin[label], middle, 30)
        if label in outside:
            shot(f"strap_{label}_outside", middle + Vector(outside[label]), middle, 35)
    palm.hide_render = True
    strap.hide_render = False
    place(0.0, False)
    shot("card_after", (0.25, -0.20, 0.55), (0.72, -0.32, 0.38), 35)
    print("RENDERED", sorted(p.name for p in out.glob("*.png")))
    return 0


mode, positional, flags = args()
bpy.ops.wm.open_mainfile(filepath=str(Path(positional[0]).resolve()))
REST_HINGE = door_hinge().matrix_world.copy()
FACING = card_facing()
TOP = strap_top(FACING)
target = Path(positional[-1]).resolve()
target.mkdir(parents=True, exist_ok=True)
if mode == "measure":
    code = measure(target, "--full-length" in flags)
elif mode == "build":
    code = build(positional[1], target)
elif mode == "render":
    code = render(target)
elif mode == "tilt":
    code = tilt(target)
else:
    raise SystemExit(f"unknown mode {mode}")
sys.exit(code)
