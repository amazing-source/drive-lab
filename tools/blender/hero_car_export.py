"""
Exports the whole hero car for Roblox, run headless by Blender:

    blender --background --python tools/blender/hero_car_export.py -- <car.blend> <out dir>

The .blend is the debadged car in metres, nose along -Y, Z up. The import pilot
(hero_car_pilot.py) showed three things this script relies on: one glTF unit imports as one
stud with no rescaling, triangle counts arrive unchanged under 20,000 per mesh, and Roblox's
importer turns a glTF model 180 degrees about the vertical axis. So the nose stays along -Y
here (glTF +Z), and the importer's turn points it along Roblox's -Z, the direction an
unrotated CFrame looks along.

1. Records which pieces make each wheel and each caliper, then bakes every transform.
2. Puts the ground under the tyres at z = 0, the centreline at x = 0 and the midpoint between
   the axles at y = 0, and scales metres to studs (1 stud = 0.28 m).
3. Joins each wheel's pieces into Wheel_FL/FR/RL/RR and each corner's caliper pieces into
   Caliper_FL/FR/RL/RR, origins at their centres.
4. Splits every other mesh by material, then cuts it along its longest axis until each piece is
   under PIECE_LIMIT triangles; faces are assigned whole, so nothing is cut through.
5. Exports car.glb (textures embedded) and manifest.json: per part its name, role, material,
   triangles, origin and size in Roblox space (studs; X right, Y up, -Z forward), plus the
   wheel centres, so the Studio assembly can place and check every piece.
"""

import json
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

STUDS_PER_METRE = 1 / 0.28
PIECE_LIMIT = 18000
WHEELS = {"FL": "3DWheel Front L", "FR": "3DWheel Front R", "RL": "3DWheel Rear L", "RR": "3DWheel Rear R"}
ROLES = [
    ("Wheel_", "wheel"),
    ("Caliper_", "caliper"),
    ("Interior", "interior"),
    ("SeatBelt", "interior"),
    ("WindowInside", "glass"),
    ("Window", "glass"),
    ("Light", "light"),
    ("Engine", "engine"),
    ("body:Kit1_Paint", "paint"),
    ("Carbon", "carbon"),
    ("Kit1_Coloured", "trim"),
    ("Grille", "trim"),
    ("Base", "underbody"),
    ("ManufacturerPlate", "plate"),
]

blend, out = (Path(arg) for arg in sys.argv[sys.argv.index("--") + 1 :][:2])
out.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(blend))


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def ancestors(obj):
    parent = obj.parent
    while parent is not None:
        yield parent
        parent = parent.parent


def bounds(objs):
    # From the vertices: Object.bound_box goes stale after Mesh.transform().
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
    # glTF Y-up export maps (x, y, z) to (x, z, -y); the importer's half turn then flips x and z.
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


# 1. Group membership first, while the hierarchy still exists.
wheel_parts = {key: [o for o in meshes() if any(p.name == n for p in ancestors(o))] for key, n in WHEELS.items()}
caliper_pieces = [o for o in meshes() if "Calliper" in o.name or any("Calliper" in p.name for p in ancestors(o))]

select_only(meshes())
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for obj in [o for o in bpy.context.scene.objects if o.type != "MESH"]:
    bpy.data.objects.remove(obj, do_unlink=True)

# 2. Ground, centre, studs.
low, high = bounds(meshes())
centres = {}
for key, parts in wheel_parts.items():
    wlow, whigh = bounds(parts)
    centres[key] = (wlow + whigh) / 2
axle_mid_y = sum(c.y for c in centres.values()) / 4
placement = Matrix.Scale(STUDS_PER_METRE, 4) @ Matrix.Translation(Vector((-(low.x + high.x) / 2, -axle_mid_y, -low.z)))
for obj in meshes():
    obj.data.transform(placement)
centres = {key: placement @ c for key, c in centres.items()}

# 3. Wheels and calipers, one part per corner.
parts = []
for key in WHEELS:
    parts.append(join(wheel_parts[key], f"Wheel_{key}"))
by_corner = {key: [] for key in WHEELS}
for piece in caliper_pieces:
    plow, phigh = bounds([piece])
    middle = (plow + phigh) / 2
    nearest = min(centres, key=lambda k: (centres[k] - middle).length)
    by_corner[nearest].append(piece)
for key, pieces in by_corner.items():
    if pieces:
        parts.append(join(pieces, f"Caliper_{key}"))


# 4. Everything else: by material, then halved along the longest axis until under the limit.
def split_by_material(obj):
    if len(obj.material_slots) <= 1:
        return [obj]
    select_only([obj])
    bpy.ops.mesh.separate(type="MATERIAL")
    return list(bpy.context.selected_objects)


def halve(obj):
    # Selects the upper half in Edit Mode and separates it: unlike a bmesh round trip through
    # from_mesh/to_mesh, this keeps the model's custom split normals, so the cut pieces shade
    # exactly like the whole.
    low, high = bounds([obj])
    size = high - low
    axis = max(range(3), key=lambda i: size[i])
    middles = sorted(p.center[axis] for p in obj.data.polygons)
    cut = middles[len(middles) // 2]
    select_only([obj])
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(obj.data)
    for face in bm.faces:
        face.select_set(False)
    for face in bm.faces:
        if face.calc_center_median()[axis] >= cut:
            face.select_set(True)
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    return [o for o in bpy.context.selected_objects]


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
    parts.append(piece)


def role_of(name: str) -> str:
    return next((role for prefix, role in ROLES if name.startswith(prefix) or prefix in name), "trim")


# 5. Export and manifest. Setting obj.location leaves matrix_world stale until the view layer
# updates, which made the whole-car bounds wrong in the first run.
bpy.context.view_layer.update()
manifest ={"studsPerMetre": STUDS_PER_METRE, "pieceLimit": PIECE_LIMIT, "parts": [], "wheelCentres": {}}
for obj in parts:
    plow, phigh = bounds([obj])
    size = phigh - plow
    material = obj.material_slots[0].material.name if obj.material_slots and obj.material_slots[0].material else None
    manifest["parts"].append(
        {
            "name": obj.name,
            "role": role_of(obj.name),
            "material": material,
            "triangles": triangles(obj),
            "origin": to_roblox(obj.location),
            "size": [round(size.x, 4), round(size.z, 4), round(size.y, 4)],
        }
    )
for key, centre in centres.items():
    manifest["wheelCentres"][key] = to_roblox(centre)
car_low, car_high = bounds(parts)
car_size = car_high - car_low
manifest["carSize"] = [round(car_size.x, 3), round(car_size.z, 3), round(car_size.y, 3)]
manifest["totalTriangles"] = sum(p["triangles"] for p in manifest["parts"])

select_only(parts)
bpy.ops.export_scene.gltf(
    filepath=str(out / "car.glb"),
    export_format="GLB",
    use_selection=True,
    export_yup=True,
    export_apply=True,
    export_normals=True,
    # Roblox needs mesh tangents for a SurfaceAppearance normal map to have any effect.
    export_tangents=True,
)
(out / "manifest.json").write_text(json.dumps(manifest, indent=1))
print(f"parts {len(parts)}, triangles {manifest['totalTriangles']}, largest "
      f"{max(p['triangles'] for p in manifest['parts'])}, car size {manifest['carSize']}")
for p in sorted(manifest["parts"], key=lambda p: -p["triangles"])[:8]:
    print(f"  {p['triangles']:>6}  {p['name']}  ({p['role']})")
print("wheel centres", manifest["wheelCentres"])
