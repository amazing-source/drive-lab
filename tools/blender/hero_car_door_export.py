"""
Exports the door, the flap, the opening's new parts and the body pieces that lost them, run
headless by Blender:

    blender -b --factory-startup -P tools/blender/hero_car_door_export.py -- <svj_door.blend> <place manifest.json> <out dir>

<svj_door.blend> is hero_car_door.py's output, its faces tagged by `door_part`; <place manifest.json>
is the manifest of the export already in the place (for the SVJ, export_v2_wheel/manifest.json).
The place's pieces are swapped one for one (MeshPart:ApplyMesh), so this replays
hero_car_export.py's steps exactly (wheels and calipers joined, bake, ground and centre, studs,
split by material, halved under 18,000 triangles) and stops unless every piece matches the
place's manifest in triangles, origin and size. Then each piece holding tagged faces loses them:
the rest is that piece's replacement; door faces go to one part per kind (DOOR_PARTS), each other
cut (CUTS: the flap, and any more tag values) to its own part, and the opening's new parts
(DoorSill, StartButton) are exported whole. Writes door.glb and
manifest.json: per part its name, the place part it replaces or copies its look from, origin
and size in Roblox space (studs; to_roblox as in hero_car_export.py), and triangles.
"""

import json
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

STUDS_PER_METRE = 1 / 0.28
PIECE_LIMIT = 18000
WHEELS = {"FL": "3DWheel Front L", "FR": "3DWheel Front R", "RL": "3DWheel Rear L", "RR": "3DWheel Rear R"}
NEW_PARTS = ("DoorSill", "StartButton")
DOOR = 1
# Faces cut out of the pieces by their `door_part` value: door faces go to one part per kind
# (DOOR_PARTS), any other value to the one part named here, with that place part's look. Value 3
# is hero_car_door.py's opening (NEW_PARTS, exported whole); add values from 4 for more cuts.
CUTS = {2: ("StartFlap", "Interior_InteriorA_Material_1")}
# Door faces by the piece they come from: the part they go to and the place part whose look
# (SurfaceAppearance, or glass settings) it copies.
DOOR_PARTS = [
    ("body:Kit1_Paint", "DoorPaint", "body:Kit1_Paint_RED_PAINT_2"),
    ("Kit1_Carbon1", "DoorCarbon", "Carbon1M_Carbon1_Material_1"),
    ("Carbon1M", "DoorCarbon", "Carbon1M_Carbon1_Material_1"),
    ("Kit1_Coloured", "DoorTrim", "Kit1_Coloured_PLASTIC_3"),
    ("Interior", "DoorInterior", "Interior_InteriorA_Material_1"),
    ("WindowInside", "DoorGlassInside", "WindowInside_Window_Material_1"),
    ("Window", "DoorGlass", "Window_Window_Material_1"),
    ("Base", "DoorBase", "Base_Base_Material_1"),
]
LOOK_OF_NEW = {"DoorSill": "Carbon1M_Carbon1_Material_1", "StartButton": "Interior_InteriorA_Material_1"}
# The place's interior parts kept their earlier names when the detailed interior was applied by
# ApplyMesh; the manifest has the export's names.
PLACE_NAMES = {"Interior_InteriorDetail.001_": "Interior_InteriorA_Material_"}

blend, place_manifest, out = (Path(arg).resolve() for arg in sys.argv[sys.argv.index("--") + 1 :][:3])
out.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(blend))
place = {p["name"]: p for p in json.loads(place_manifest.read_text())["parts"]}

new_objects = [bpy.data.objects[n] for n in NEW_PARTS]
for obj in new_objects:
    bpy.context.scene.collection.objects.unlink(obj)


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def ancestors(obj):
    parent = obj.parent
    while parent is not None:
        yield parent
        parent = parent.parent


def bounds(objs):
    points = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    return low, high


def select_only(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def triangles(obj) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def to_roblox(v: Vector) -> list:
    return [round(-v.x, 4), round(v.z, 4), round(v.y, 4)]


def set_origin_to_centre(obj):
    low, high = bounds([obj])
    centre = (low + high) / 2
    obj.data.transform(Matrix.Translation(-centre))
    obj.location = centre


def join(objs, name):
    select_only(objs)
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    joined.data.name = name
    set_origin_to_centre(joined)
    return joined


def parts_of(obj):
    values = np.zeros(len(obj.data.polygons), dtype=np.int32)
    attr = obj.data.attributes.get("door_part")
    if attr:
        attr.data.foreach_get("value", values)
    return values


# hero_car_export.py steps 1 to 4, unchanged.
wheel_parts = {key: [o for o in meshes() if any(p.name == n for p in ancestors(o))] for key, n in WHEELS.items()}
caliper_pieces = [o for o in meshes() if "Calliper" in o.name or any("Calliper" in p.name for p in ancestors(o))]
select_only(meshes())
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for obj in [o for o in bpy.context.scene.objects if o.type != "MESH"]:
    bpy.data.objects.remove(obj, do_unlink=True)
low, high = bounds(meshes())
centres = {}
for key, pieces in wheel_parts.items():
    wlow, whigh = bounds(pieces)
    centres[key] = (wlow + whigh) / 2
axle_mid_y = sum(c.y for c in centres.values()) / 4
placement = Matrix.Scale(STUDS_PER_METRE, 4) @ Matrix.Translation(Vector((-(low.x + high.x) / 2, -axle_mid_y, -low.z)))
for obj in meshes() + new_objects:
    obj.data.transform(placement)
parts = []
for key in WHEELS:
    parts.append(join(wheel_parts[key], f"Wheel_{key}"))
centres = {key: placement @ c for key, c in centres.items()}
by_corner = {key: [] for key in WHEELS}
for piece in caliper_pieces:
    plow, phigh = bounds([piece])
    middle = (plow + phigh) / 2
    by_corner[min(centres, key=lambda k: (centres[k] - middle).length)].append(piece)
for key, pieces in by_corner.items():
    if pieces:
        parts.append(join(pieces, f"Caliper_{key}"))


def split_by_material(obj):
    if len(obj.material_slots) <= 1:
        return [obj]
    select_only([obj])
    bpy.ops.mesh.separate(type="MATERIAL")
    return list(bpy.context.selected_objects)


def separate(obj, pick):
    # Edit-mode separation keeps the model's custom split normals (a bmesh round trip drops them).
    select_only([obj])
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(obj.data)
    for face in bm.faces:
        face.select_set(bool(pick(face)))
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    return [o for o in bpy.context.selected_objects if o is not obj]


def halve(obj):
    low_, high_ = bounds([obj])
    size = high_ - low_
    axis = max(range(3), key=lambda i: size[i])
    middles = sorted(p.center[axis] for p in obj.data.polygons)
    cut = middles[len(middles) // 2]
    return [obj] + separate(obj, lambda face: face.calc_center_median()[axis] >= cut)


rest = [o for o in meshes() if o not in parts]
pieces = []
for obj in rest:
    for single in split_by_material(obj):
        queue = [single]
        while queue:
            current = queue.pop()
            if triangles(current) > PIECE_LIMIT:
                queue.extend(halve(current))
            elif triangles(current) > 0:
                pieces.append(current)
            else:
                bpy.data.objects.remove(current, do_unlink=True)
counts = {}
for piece in pieces:
    base = piece.name.split(".")[0].replace("_Geo_lodA", "").replace("Body_lodA", "")
    material = piece.material_slots[0].material.name if piece.material_slots and piece.material_slots[0].material else "none"
    short = material.replace("Lamborghini_AventadorSVJRewardRecycled_2019", "").strip("_") or material
    label = f"{base}_{short}"[:48]
    counts[label] = counts.get(label, 0) + 1
    piece.name = f"{label}_{counts[label]}"
    piece.data.name = piece.name
    set_origin_to_centre(piece)
bpy.context.view_layer.update()


def place_name(name):
    for old, new in PLACE_NAMES.items():
        if name.startswith(old):
            return new + name[len(old) :]
    return name


# The replay must match the place piece for piece, or a swap would put the wrong mesh in a part.
mismatches = []
for piece in pieces + parts:
    entry = place.get(piece.name)
    plow, phigh = bounds([piece])
    origin, size = to_roblox(piece.location), [phigh.x - plow.x, phigh.z - plow.z, phigh.y - plow.y]
    if entry is None:
        mismatches.append(f"{piece.name}: not in the place manifest")
    elif entry["triangles"] != triangles(piece) or max(abs(a - b) for a, b in zip(entry["origin"], origin)) > 2e-3 or max(
        abs(a - b) for a, b in zip(entry["size"], size)
    ) > 2e-3:
        mismatches.append(f"{piece.name}: {triangles(piece)} tris {origin} {size} vs {entry['triangles']} {entry['origin']} {entry['size']}")
if mismatches:
    print("REPLAY MISMATCH\n  " + "\n  ".join(mismatches))
    sys.exit(1)
print(f"replay matches the place: {len(pieces) + len(parts)} pieces")

# Take the tagged faces out of the pieces that hold them, one cut value at a time.
cut_values = [DOOR, *CUTS]
replacements, groups = [], {}
for piece in pieces:
    if not np.isin(parts_of(piece), cut_values).any():
        continue
    for value in cut_values:
        tags = parts_of(piece)
        if not (tags == value).any():
            continue
        if value == DOOR:
            name = next(target for prefix, target, _ in DOOR_PARTS if piece.name.startswith(prefix))
        else:
            name = CUTS[value][0]
        groups.setdefault(name, []).extend(separate(piece, lambda face, t=tags, v=value: t[face.index] == v))
    set_origin_to_centre(piece)
    replacements.append((piece, place_name(piece.name)))

look = {target: (look, "door") for _, target, look in DOOR_PARTS}
look.update({name: (place_part, "cut") for name, place_part in CUTS.values()})
exported = []
for piece, source in replacements:
    exported.append((piece, {"role": "replacement", "replaces": source}))
for name, objs in groups.items():
    exported.append((join(objs, name), {"role": look[name][1], "looksLike": look[name][0]}))
for obj in new_objects:
    bpy.context.scene.collection.objects.link(obj)
    set_origin_to_centre(obj)
    exported.append((obj, {"role": "opening", "looksLike": LOOK_OF_NEW[obj.name]}))
bpy.context.view_layer.update()

manifest = {"studsPerMetre": STUDS_PER_METRE, "placementMetres": {"x": -(low.x + high.x) / 2, "y": -axle_mid_y, "z": -low.z}, "parts": []}
for obj, info in exported:
    plow, phigh = bounds([obj])
    tris = triangles(obj)
    assert tris < PIECE_LIMIT, f"{obj.name} has {tris} triangles"
    manifest["parts"].append(
        dict(
            name=obj.name,
            triangles=tris,
            origin=to_roblox(obj.location),
            size=[round(phigh.x - plow.x, 4), round(phigh.z - plow.z, 4), round(phigh.y - plow.y, 4)],
            **info,
        )
    )
select_only([obj for obj, _ in exported])
bpy.ops.export_scene.gltf(
    filepath=str(out / "door.glb"),
    export_format="GLB",
    use_selection=True,
    export_yup=True,
    export_apply=True,
    export_normals=True,
    export_tangents=True,
)
(out / "manifest.json").write_text(json.dumps(manifest, indent=1))
for p in manifest["parts"]:
    print(f"  {p['triangles']:>6}  {p['name']:40} {p['role']:12} {p.get('replaces') or p.get('looksLike')}")
