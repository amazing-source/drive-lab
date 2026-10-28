"""
Marks the hero car's driver door and START flap, and closes the opening the door leaves, run
headless by Blender:

    blender -b --factory-startup -P tools/blender/hero_car_door.py -- <car.blend> <out dir>

The .blend is the car in metres, nose along -Y, Z up, the driver on +X (left-hand drive). The
door is not cut out of anything: it is whole mesh islands, so the source keeps its shading and
UVs. Nothing is separated here either. Each face gets an integer attribute `door_part` (0 body,
1 door, 2 flap, 3 opening); the hinge fit, the renders and the export all read that one tag.
Writes <out dir>/svj_door.blend and <out dir>/door_selection.json.

Which islands are the door, measured on the SVJ (Forza-sourced mesh, 2026-10-28):
1. An island is door if 85 % of its vertices sit inside the door box (DOOR_BOX), outboard of the
   cabin (per mesh: 0.55 m, the interior 0.64 m).
2. The front quarter glass, its frame and the divider bar behind the mirror are door too
   (QUARTER_BOX, every vertex inside): on the real car the glass is one piece up to the A-pillar
   and a black cap at the door's front rises with it (Commons photo, Tuner tom, CC BY-SA 3.0:
   File:Lamborghini_Aventador_front_with_scissor_doors_up_and_Transparent_Engine_Bonnet.JPG).
3. At the front end the model carries its own hinge: an arm bolted inside the door's front face
   (six bolt heads at y -0.80) reaching forward to the pivot hardware at y -0.93. Islands there
   (FRONT_BOX) follow the door when their centre is behind FRONT_SPLIT_Y, else the body.
4. A door island must sit inside the door's side outline (outer skin and glass, grown 1 cm) for
   half its vertices, and, glass aside, average outboard of INNER_X: this drops the roof seal,
   slivers of the fender and the sill's inner wall that the box caught. The mirror (the whole
   door share of the carbon mesh) is exempt: it stands proud of the outline.
5. EXCLUDE lists islands checked by eye in renders and found to be body (reason beside each).
6. The door's inner window surround tucks inboard toward the roof, past the interior limit, so
   its islands sit only half in the box: an interior island half in, centred above FRAME_Z, wholly
   inside the outline, averaging outboard of INNER_X and reaching no further in than FRAME_X is door. Left on the body, the hinge check
   showed the door's inner carbon cutting it between 8 and 36 degrees.

The flap is the Interior island inside FLAP_BOX. The opening is closed with a sill (carbon), the
real SVJ's wide carbon tub sill: its top runs SILL_GAP under the door's lowest edge along the
whole opening, from under the cabin-side trim to the outer skirt, with a face up the skirt's
inside, so the open door shows no slot to the ground. A START button is modelled under the flap.
"""

import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

DOOR_BOX = {"y0": -0.95, "y1": 0.47, "z0": 0.10, "z1": 1.0}
SOURCES = {
    "body:Kit1_Paint_Geo_lodABody_lodA": 0.55,
    "Kit1_Carbon1_Geo_lodA": 0.55,
    "Kit1_Coloured_Geo_lodA": 0.55,
    "Carbon1M_Geo_lodA": 0.55,
    "Interior_Geo_lodA": 0.64,
    "Window_Geo_lodA": 0.55,
    "WindowInside_Geo_lodA": 0.55,
    # Black structure: the door's window channel along its beltline and the glass's edges.
    "Base_Geo_lodA": 0.55,
}
GLASS = ("Window_Geo_lodA", "WindowInside_Geo_lodA")
MIRROR = "Kit1_Carbon1_Geo_lodA"
QUARTER_MESHES = ("Window_Geo_lodA", "WindowInside_Geo_lodA", "Kit1_Coloured_Geo_lodA", "Interior_Geo_lodA", "Base_Geo_lodA")
QUARTER_BOX = {"x0": 0.60, "x1": 0.90, "y0": -1.13, "y1": -0.66, "z0": 0.58, "z1": 0.86}
FRONT_BOX = {"x0": 0.84, "y1": -0.80, "z0": 0.12, "z1": 0.65}
FRONT_SPLIT_Y = -0.89
# The door's inner window surround tucks inboard of the box's interior limit toward the roof: an
# interior island half in the box, centred above FRAME_Z, is door if it lies wholly inside the
# door's side outline and averages outboard of INNER_X (rule 6).
FRAME_MESH = "Interior_Geo_lodA"
FRAME_Z = 0.45
# ...and reaches no further inboard than the door glass's top edge (0.60 m), less a margin.
FRAME_X = 0.58
INNER_X = 0.63
OUTLINE_GROW = 0.01
# (mesh, centre box) of islands that the rules call door but renders show to be body.
EXCLUDE = [
    # The seat-belt guide on the B-pillar (190 faces): it rode up with the door.
    ("Interior_Geo_lodA", {"x0": 0.63, "x1": 0.68, "y0": 0.22, "y1": 0.34, "z0": 0.64, "z1": 0.73}),
    # The bonnet release lever on the footwell's side wall (77 faces): it floated up with the door.
    ("Interior_Geo_lodA", {"x0": 0.64, "x1": 0.70, "y0": -0.84, "y1": -0.76, "z0": 0.19, "z1": 0.34}),
]
FLAP_BOX = {"x0": -0.025, "x1": 0.025, "y0": -0.356, "y1": -0.315, "z0": 0.43, "z1": 0.46}
SILL_GAP = 0.006
SILL_STEP = 0.025
# The sill spans this band of x (metres) and ends where the door's bottom does: no door surface
# under SILL_DOOR_MAX_Z above it.
SILL_X = (0.72, 0.95)
SILL_DOOR_MAX_Z = 0.35
CARBON = "Lamborghini_AventadorSVJRewardRecycled_2019Carbon1_Material"
CARBON_UV_PER_METRE = 37.5  # median of the carbon mesh's own faces
BUTTON_RADIUS = 0.008
BUTTON_HEIGHT = 0.0015

DOOR, FLAP, OPENING = 1, 2, 3

blend, out = (Path(arg).resolve() for arg in sys.argv[sys.argv.index("--") + 1 :][:2])
out.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(blend))
scene = bpy.context.scene


def islands(mesh):
    # Read only: a bmesh written back would drop the model's custom split normals.
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    seen = set()
    found = []
    for face in bm.faces:
        if face.index in seen:
            continue
        stack, comp = [face], []
        seen.add(face.index)
        while stack:
            current = stack.pop()
            comp.append(current.index)
            for edge in current.edges:
                for other in edge.link_faces:
                    if other.index not in seen:
                        seen.add(other.index)
                        stack.append(other)
        found.append(comp)
    bm.free()
    return found


def world_points(obj, faces):
    mesh = obj.data
    indices = sorted({v for f in faces for v in mesh.polygons[f].vertices})
    local = np.array([tuple(mesh.vertices[i].co) for i in indices])
    matrix = np.array(obj.matrix_world)
    return local @ matrix[:3, :3].T + matrix[:3, 3]


def inside(points, box):
    keep = np.ones(len(points), bool)
    for axis, key in enumerate("xyz"):
        if f"{key}0" in box:
            keep &= points[:, axis] > box[f"{key}0"]
        if f"{key}1" in box:
            keep &= points[:, axis] < box[f"{key}1"]
    return keep


def triangles(obj, faces):
    mesh = obj.data
    matrix = obj.matrix_world
    out_tris = []
    for f in faces:
        vs = [matrix @ mesh.vertices[i].co for i in mesh.polygons[f].vertices]
        for k in range(1, len(vs) - 1):
            out_tris.append((vs[0], vs[k], vs[k + 1]))
    return out_tris


# 1. Candidates by the box, island by island.
records = []
for name, xmin in SOURCES.items():
    obj = bpy.data.objects[name]
    for number, faces in enumerate(islands(obj.data)):
        points = world_points(obj, faces)
        box = dict(DOOR_BOX, x0=xmin)
        share = inside(points, box).mean()
        quarter = name in QUARTER_MESHES and inside(points, QUARTER_BOX).all()
        frame = name == FRAME_MESH and share >= 0.5 and points[:, 2].mean() > FRAME_Z
        if share < 0.85 and not quarter and not frame:
            continue
        records.append(
            {"mesh": name, "island": number, "faces": faces, "points": points, "share": float(share), "quarter": bool(quarter), "frame": bool(frame and share < 0.85)}
        )

# 2. The door's side outline from its outer skin and main glass: a 2 mm raster in (y, z).
H = 0.002
Y0, Z0, NY, NZ = -1.2, 0.0, 950, 525
outline = np.zeros((NZ, NY), bool)


def rasterise(tri_list, mask):
    for a, b, c in tri_list:
        ys, zs = (a.y, b.y, c.y), (a.z, b.z, c.z)
        i0, i1 = int((min(ys) - Y0) / H), int((max(ys) - Y0) / H) + 1
        j0, j1 = int((min(zs) - Z0) / H), int((max(zs) - Z0) / H) + 1
        gy, gz = np.meshgrid(Y0 + (np.arange(i0, i1) + 0.5) * H, Z0 + (np.arange(j0, j1) + 0.5) * H)
        d = (b.y - a.y) * (c.z - a.z) - (c.y - a.y) * (b.z - a.z)
        if abs(d) < 1e-12:
            continue
        l1 = ((gy - a.y) * (c.z - a.z) - (c.y - a.y) * (gz - a.z)) / d
        l2 = ((b.y - a.y) * (gz - a.z) - (gy - a.y) * (b.z - a.z)) / d
        hit = (l1 >= -0.02) & (l2 >= -0.02) & (l1 + l2 <= 1.02)
        mask[j0:j1, i0:i1] |= hit


for rec in records:
    is_skin = rec["mesh"].startswith("body:") and len(rec["faces"]) >= 20
    is_glass = rec["mesh"] == "Window_Geo_lodA" and len(rec["faces"]) >= 40
    if is_skin or is_glass:
        rasterise(triangles(bpy.data.objects[rec["mesh"]], rec["faces"]), outline)
# Fill each row between its ends, then grow by OUTLINE_GROW.
for row in range(NZ):
    cols = np.nonzero(outline[row])[0]
    if len(cols):
        outline[row, cols[0] : cols[-1] + 1] = True
grow = int(OUTLINE_GROW / H)
grown = outline.copy()
for _ in range(grow):
    grown[1:] |= grown[:-1]
    grown[:-1] |= grown[1:]
    grown[:, 1:] |= grown[:, :-1]
    grown[:, :-1] |= grown[:, 1:]


def outline_share(points):
    i = ((points[:, 1] - Y0) / H).astype(int).clip(0, NY - 1)
    j = ((points[:, 2] - Z0) / H).astype(int).clip(0, NZ - 1)
    return grown[j, i].mean()


# 3. Rules 3 to 5.
door = {name: set() for name in SOURCES}
# Each door island's id, mesh order * 10000 + island number, so a check can name what collides.
island_of = {name: {} for name in SOURCES}
decisions = []
for rec in records:
    pts, name = rec["points"], rec["mesh"]
    centre = pts.mean(0)
    rule = "box"
    keep = True
    in_front = centre[0] > FRONT_BOX["x0"] and centre[1] < FRONT_BOX["y1"] and FRONT_BOX["z0"] < centre[2] < FRONT_BOX["z1"]
    if rec["quarter"]:
        rule = "quarter"
    elif rec["frame"]:
        rule = "frame"
        keep = outline_share(pts) >= 0.999 and centre[0] >= INNER_X and pts[:, 0].min() >= FRAME_X
    elif in_front:
        rule = "front"
        keep = centre[1] >= FRONT_SPLIT_Y
    elif name != MIRROR:
        if outline_share(pts) < 0.5:
            rule, keep = "outline", False
        elif name not in GLASS and centre[0] < INNER_X:
            rule, keep = "inner", False
    for mesh_name, box in EXCLUDE:
        if name == mesh_name and inside(centre[None, :], box)[0]:
            rule, keep = "exclude", False
    ident = (list(SOURCES).index(name) + 1) * 10000 + rec["island"]
    if keep:
        door[name].update(rec["faces"])
        island_of[name].update({f: ident for f in rec["faces"]})
    if rule != "box" or len(rec["faces"]) >= 100 or centre[1] < -0.95:
        decisions.append(
            {"mesh": name, "island": rec["island"], "id": ident, "faces": len(rec["faces"]), "rule": rule, "door": bool(keep),
             "centre": [round(float(c), 3) for c in centre]}
        )

# 4. The flap.
interior = bpy.data.objects["Interior_Geo_lodA"]
flap = set()
for faces in islands(interior.data):
    if inside(world_points(interior, faces), FLAP_BOX).all():
        flap.update(faces)
assert 150 < len(flap) < 260, f"flap selection has {len(flap)} faces"

# 5. Tag the faces.
for name in SOURCES:
    mesh = bpy.data.objects[name].data
    values = np.zeros(len(mesh.polygons), dtype=np.int32)
    values[list(door[name])] = DOOR
    if name == "Interior_Geo_lodA":
        values[list(flap)] = FLAP
    attr = mesh.attributes.get("door_part") or mesh.attributes.new("door_part", "INT", "FACE")
    attr.data.foreach_set("value", values)
    ids = np.zeros(len(mesh.polygons), dtype=np.int32)
    for f, ident in island_of[name].items():
        ids[f] = ident
    attr = mesh.attributes.get("door_island") or mesh.attributes.new("door_island", "INT", "FACE")
    attr.data.foreach_set("value", ids)
for obj in bpy.context.scene.objects:
    if obj.type == "MESH" and obj.name not in SOURCES and "door_part" not in obj.data.attributes:
        obj.data.attributes.new("door_part", "INT", "FACE")

# 6. Measure the opening with the door out of the way: a scratch copy of the car without door
# faces, used for rays only.
scratch = []
for name in SOURCES:
    src = bpy.data.objects[name]
    copy = src.copy()
    copy.data = src.data.copy()
    scene.collection.objects.link(copy)
    bm = bmesh.new()
    bm.from_mesh(copy.data)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in door[name]], context="FACES")
    bm.to_mesh(copy.data)
    bm.free()
    src.hide_viewport = True
    scratch.append((src, copy))
bpy.context.view_layer.update()
depsgraph = bpy.context.evaluated_depsgraph_get()


def ray(origin, direction):
    hit, loc, _normal, _index, obj, _ = scene.ray_cast(depsgraph, Vector(origin), Vector(direction).normalized())
    return (loc, obj.name) if hit else None


door_tris = [t for n, f in door.items() for t in triangles(bpy.data.objects[n], sorted(f))]
door_bvh = BVHTree.FromPolygons(
    [v for t in door_tris for v in t], [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(door_tris))]
)


def door_bottom(y):
    # The door's skin runs long triangles along its bottom, so its vertices say little: rays up
    # from under the car find its lowest surface across the width of the sill.
    heights = []
    for x in np.arange(SILL_X[0], SILL_X[1], 0.02):
        hit = door_bvh.ray_cast(Vector((x, y, -0.05)), Vector((0, 0, 1)))
        if hit[0] is not None and hit[0].z < SILL_DOOR_MAX_Z:
            heights.append(hit[0].z)
    return min(heights) if heights else None


front_wall = ray((0.80, -0.5, 0.10), (0, -1, 0))
sill_y0 = front_wall[0].y if front_wall else -0.876
slices = []
y = sill_y0
while True:
    bottom = door_bottom(y + 0.005)
    if bottom is None:
        break
    top = bottom - SILL_GAP
    # Outer skirt: the highest height at which a ray from outside still meets the skin.
    lip_z, lip_x = top, 0.95
    for z in np.arange(top, top + 0.12, 0.004):
        hit = ray((1.4, y, z), (-1, 0, 0))
        if hit and hit[0].x > 0.88:
            lip_z, lip_x = float(z), float(hit[0].x)
    # Cabin side: the outermost x whose downward ray meets the low cabin trim above the sill top.
    in_x, in_z = 0.70, top + 0.04
    for x in np.arange(0.62, 0.80, 0.005):
        hit = ray((x, y, SILL_DOOR_MAX_Z), (0, 0, -1))
        if hit and hit[1].startswith("Interior") and hit[0].z > top + 0.01:
            in_x, in_z = float(x), float(hit[0].z)
    slices.append((float(y), top, lip_x - 0.008, lip_z, in_x + 0.004, in_z))
    y += SILL_STEP
sill_y1 = slices[-1][0]


def steady(ys, values):
    # A straight line through the values, refitted without those more than a centimetre off it:
    # at its ends a slice meets the door's front face or rear corner, not its bottom.
    ys, values = np.array(ys), np.array(values)
    keep = np.ones(len(ys), bool)
    for _ in range(3):
        slope, offset = np.polyfit(ys[keep], values[keep], 1)
        keep = np.abs(values - (slope * ys + offset)) < 0.01
    return slope * ys + offset


ys = [s[0] for s in slices]
fit_top, fit_lip, fit_in = (steady(ys, [s[k] for s in slices]) for k in (1, 3, 5))
# Never above the measurement: the sill stays under the door and the lip under the skirt's edge.
slices = [
    (y, min(top, ft), lip_x, max(min(lip_z, fl), min(top, ft)), in_x, max(min(in_z, fi), min(top, ft) + 0.02))
    for (y, top, lip_x, lip_z, in_x, in_z), ft, fl, fi in zip(slices, fit_top, fit_lip, fit_in)
]

# Rays for the START button: the gap between the flap's underside and the base under it.
flap_points = world_points(interior, sorted(flap))
flap_centre = flap_points.mean(0)
console_normal = Vector((0.0, 0.43, 0.90)).normalized()
for src, copy in scratch:
    bpy.data.objects.remove(copy, do_unlink=True)
    src.hide_viewport = False
bpy.context.view_layer.update()
depsgraph = bpy.context.evaluated_depsgraph_get()
# The base under the flap, found with the flap's own faces left out: the flap rests on it, its
# underside within the base's depth, so the button is a disc BUTTON_HEIGHT proud of the base,
# hidden in the shut flap's footprint and shown when it lifts.
near_faces = [
    f for f in range(len(interior.data.polygons))
    if f not in flap and (interior.matrix_world @ interior.data.polygons[f].center - Vector(flap_centre)).length < 0.05
]
base_bvh = BVHTree.FromPolygons(
    [v for t in triangles(interior, near_faces) for v in t], [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(triangles(interior, near_faces)))]
)
base_point, _, _, _ = base_bvh.ray_cast(Vector(flap_centre) + console_normal * 0.02, -console_normal)
base_hit = (base_point, "Interior_Geo_lodA") if base_point is not None else None
gap = 0.0

# 7. The sill mesh: per slice, cabin-side wall top -> sill top -> skirt lip, quads between slices.
carbon = bpy.data.materials[CARBON]
bm = bmesh.new()
uv_layer = bm.loops.layers.uv.new("UVChannel_1")
part_layer = bm.faces.layers.int.new("door_part")
rows = []
for y, top, lip_x, lip_z, in_x, in_z in slices:
    rows.append([bm.verts.new((in_x, y, in_z)), bm.verts.new((in_x, y, top)), bm.verts.new((lip_x, y, top)), bm.verts.new((lip_x, y, lip_z))])
for a, b in zip(rows, rows[1:]):
    # The top and the skirt-side face. No wall up the cabin side: the door's bin and the bottom of
    # its card sit over the cabin trim when shut and sweep outward through that line as it opens.
    for k in (1, 2):
        # Winding chosen so each strip faces the opening: top up, skirt side inboard.
        face = bm.faces.new((a[k], a[k + 1], b[k + 1], b[k]))
        face[part_layer] = OPENING
        for loop in face.loops:
            co = loop.vert.co
            second = co.x if k == 1 else co.z
            loop[uv_layer].uv = (co.y * CARBON_UV_PER_METRE, second * CARBON_UV_PER_METRE)
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
sill_mesh = bpy.data.meshes.new("DoorSill")
bm.to_mesh(sill_mesh)
bm.free()
sill_mesh.materials.append(carbon)
sill = bpy.data.objects.new("DoorSill", sill_mesh)
scene.collection.objects.link(sill)
# Point every face at the opening (top up, walls toward the opening's middle).
middle = Vector((0.83, 0, 0))
flipped = 0
for poly in sill_mesh.polygons:
    centre = poly.center
    want = Vector((0, 0, 1)) if abs(poly.normal.z) > 0.5 else Vector((math.copysign(1, middle.x - centre.x), 0, 0))
    if poly.normal.dot(want) < 0:
        poly.flip()
        flipped += 1
sill_mesh.update()

# 8. The START button: a short black cylinder on the base under the flap, its UVs on the base's.
base_uv = None
if base_hit and base_hit[1].startswith("Interior"):
    hit_loc = base_hit[0]
    uv_data = interior.data.uv_layers.active.data
    centres = np.array([tuple(interior.matrix_world @ p.center) for p in interior.data.polygons])
    centres[sorted(flap)] = 1e6
    nearest = int(np.argmin(np.linalg.norm(centres - np.array(tuple(hit_loc)), axis=1)))
    loops = interior.data.polygons[nearest].loop_indices
    base_uv = tuple(float(c) for c in np.mean([tuple(uv_data[i].uv) for i in loops], axis=0))
height = BUTTON_HEIGHT
bm = bmesh.new()
uv_layer = bm.loops.layers.uv.new("UVChannel_1")
part_layer = bm.faces.layers.int.new("door_part")
bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=BUTTON_RADIUS, radius2=BUTTON_RADIUS * 0.9, depth=height)
axis_from = Vector((0, 0, 1))
rotation = axis_from.rotation_difference(console_normal).to_matrix().to_4x4()
bmesh.ops.transform(bm, matrix=rotation, verts=bm.verts)
anchor = Vector(base_hit[0]) if base_hit else Vector(flap_centre)
bmesh.ops.translate(bm, vec=anchor + console_normal * (height / 2), verts=bm.verts)
for face in bm.faces:
    face[part_layer] = OPENING
    for loop in face.loops:
        loop[uv_layer].uv = base_uv or (0.5, 0.5)
button_top = anchor + console_normal * height
# The flap turns about its front edge (the end away from its finger notch), along the car's width.
flap_front = float(flap_points[:, 1].min())
flap_edge = flap_points[flap_points[:, 1] < flap_front + 0.002]
flap_hinge = {"pivot": [0.0, round(flap_front, 4), round(float(flap_edge[:, 2].min()), 4)], "axis": [1.0, 0.0, 0.0]}
button_mesh = bpy.data.meshes.new("StartButton")
bm.to_mesh(button_mesh)
bm.free()
button_mesh.materials.append(interior.data.materials[0])
button = bpy.data.objects.new("StartButton", button_mesh)
scene.collection.objects.link(button)

# 9. Save and report.
bpy.ops.wm.save_as_mainfile(filepath=str(out / "svj_door.blend"), compress=True)


def tri_count(obj, faces):
    return sum(len(obj.data.polygons[f].vertices) - 2 for f in faces)


report = {
    "source": str(blend),
    "doorTriangles": {n: tri_count(bpy.data.objects[n], f) for n, f in door.items()},
    "flapTriangles": tri_count(interior, flap),
    "flapCentre": [round(float(c), 4) for c in flap_centre],
    "flapGap": round(gap, 4),
    "buttonHeight": round(height, 4),
    "buttonUv": base_uv,
    "buttonTop": [round(float(c), 4) for c in button_top],
    "flapHinge": flap_hinge,
    "sill": {"y0": round(sill_y0, 3), "y1": round(sill_y1, 3), "slices": [[round(v, 4) for v in s] for s in slices], "flippedFaces": flipped},
    "decisions": decisions,
}
(out / "door_selection.json").write_text(json.dumps(report, indent=1))
print("DOOR triangles", report["doorTriangles"], "total", sum(report["doorTriangles"].values()))
print("FLAP triangles", report["flapTriangles"], "gap", report["flapGap"], "button", report["buttonHeight"])
print("SILL", report["sill"]["y0"], report["sill"]["y1"], len(slices), "slices, flipped", flipped)
for d in decisions:
    if d["rule"] != "box":
        print("RULE", d)
