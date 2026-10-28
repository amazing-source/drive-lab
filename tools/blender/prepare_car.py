"""
Prepares a downloaded car model for Roblox, run headless by Blender:

    blender --background --factory-startup --python tools/blender/prepare_car.py -- \
        <model.glb|.gltf|.fbx> <out dir> [--length 15] [--budget 24000] [--forward +x|-x|+y|-y]
        [--texture 1024]

1. Imports the model and bakes every transform, so all geometry is in world space.
2. Turns it so the nose points along +X (--forward names the model's own nose direction),
   centres it, stands it on z = 0 and scales it to --length studs long.
3. Splits every mesh into its loose pieces and finds the four wheels by shape: the largest
   round, thin piece near each bottom corner is a tyre, and everything inside it (rim,
   spokes, brake disc) belongs to that wheel. Wheels are named WheelFL/FR/RL/RR.
4. Drops parts nobody sees (engine internals, suspension, bolts too small to render) and
   merges what is left by material, then decimates to --budget triangles in total, keeping
   every part under Roblox's per-mesh limit.
5. Shrinks every texture to at most --texture pixels on its long side, since every car
   template downloads to every player.
6. Exports car.glb with textures, a manifest.json describing every part (colour,
   transparency, whether it is textured, and the role the game gives it: body paint, glass,
   light, chrome, rubber, trim or interior), and preview.png, a three-quarter render to
   check before uploading.
"""

import json
import math
import re
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

PER_MESH_LIMIT = 9000
HIDDEN_WORDS = ("suspension", "driveshaft", "spring", "shock", "brake_line")
ROLE_WORDS = {
    "glass": ("glass", "window", "windshield", "windscreen"),
    "light": ("light", "lamp", "headl", "taill", "emiss", "led", "indicator", "reflector"),
    "chrome": ("chrome", "nickel", "alum", "metal", "silver", "steel"),
    "rubber": ("tire", "tyre", "tread", "rubber"),
    "interior": ("interior", "leather", "seat", "dash", "carpet", "steering", "wood"),
    "paint": ("paint", "body", "carpaint", "car_paint", "color"),
}


def arguments():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    options = {"length": 15.0, "budget": 24000, "forward": "auto", "texture": 1024}
    positional = []
    index = 0
    while index < len(argv):
        flag = argv[index]
        if flag in ("--length", "--budget", "--forward", "--texture"):
            value = argv[index + 1]
            options[flag[2:]] = value if flag == "--forward" else float(value)
            index += 2
        else:
            positional.append(flag)
            index += 1
    return Path(positional[0]), Path(positional[1]), options


def meshes():
    return [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]


def select(objects, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = active or (objects[0] if objects else None)


def load(path: Path):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    if path.suffix.lower() in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=str(path))
    else:
        bpy.ops.import_scene.fbx(filepath=str(path))
    for obj in bpy.context.scene.objects:
        obj.hide_set(False)
        obj.hide_viewport = False
    select(list(bpy.context.scene.objects), meshes()[0])
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)
    for obj in meshes():
        if obj.data.users > 1:
            obj.data = obj.data.copy()
    select(meshes())
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def box(objects):
    low = Vector((math.inf,) * 3)
    high = Vector((-math.inf,) * 3)
    for obj in objects:
        for vertex in obj.data.vertices:
            low = Vector(map(min, low, vertex.co))
            high = Vector(map(max, high, vertex.co))
    return low, high


def transform_all(matrix: Matrix):
    for obj in meshes():
        obj.data.transform(matrix)
        obj.data.update()


def orient(options):
    low, high = box(meshes())
    size = high - low
    forward = options["forward"]
    if forward == "auto":
        forward = "+x" if size.x >= size.y else "+y"
    turns = {"+x": 0, "+y": -90, "-x": 180, "-y": 90}
    transform_all(Matrix.Rotation(math.radians(turns[forward]), 4, "Z"))
    low, high = box(meshes())
    centre = (low + high) / 2
    transform_all(Matrix.Translation(Vector((-centre.x, -centre.y, -low.z))))
    transform_all(Matrix.Scale(options["length"] / (high.x - low.x), 4))


def split_loose():
    for obj in meshes():
        select([obj])
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.separate(type="LOOSE")
        bpy.ops.object.mode_set(mode="OBJECT")
    pieces = []
    for obj in meshes():
        low, high = box([obj])
        pieces.append((obj, low, high))
    return pieces


def find_wheels(pieces, low, high):
    """Each corner's tyre is the largest round, thin piece there; its envelope claims the rest."""
    length, width, height = high - low
    corners = {}
    for obj, a, b in pieces:
        size = b - a
        centre = (a + b) / 2
        if not (0.15 * height <= size.z <= 0.62 * height and centre.z < 0.4 * height):
            continue
        if abs(size.x - size.z) > 0.25 * size.z or size.y > 0.75 * size.z:
            continue
        if abs(centre.x) < 0.18 * length / 2 or abs(centre.y) < 0.2 * width / 2:
            continue
        key = ("F" if centre.x > 0 else "R") + ("L" if centre.y > 0 else "R")
        if key not in corners or size.z > corners[key][1].z:
            corners[key] = (centre, size, obj)
    wheels = {key: [] for key in corners}
    for obj, a, b in pieces:
        for key, (centre, size, _) in corners.items():
            outward = 1 if centre.y > 0 else -1
            inner_y = centre.y - outward * size.y * 0.9
            outer_y = centre.y + outward * size.y * 0.6
            y_low, y_high = min(inner_y, outer_y), max(inner_y, outer_y)
            pad = size.z * 0.06
            inside = (
                a.x >= centre.x - size.x / 2 - pad
                and b.x <= centre.x + size.x / 2 + pad
                and a.z >= centre.z - size.z / 2 - pad
                and b.z <= centre.z + size.z / 2 + pad
                and a.y >= y_low
                and b.y <= y_high
            )
            if inside:
                wheels[key].append(obj)
                break
    tyres = {tyre for _, _, tyre in corners.values()}
    return wheels, corners, tyres


def material_info(material):
    info = {"name": material.name if material else "none", "color": (0.6, 0.6, 0.6), "alpha": 1.0, "textured": False}
    if material and material.use_nodes:
        for node in material.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                base = node.inputs["Base Color"]
                info["color"] = tuple(base.default_value[:3])
                info["alpha"] = node.inputs["Alpha"].default_value
                transmission = node.inputs.get("Transmission Weight")
                if transmission and transmission.default_value > 0.3:
                    info["alpha"] = min(info["alpha"], 0.45)
                info["textured"] = any(link.from_node.type == "TEX_IMAGE" for link in base.links)
    return info


def keyword_role(text):
    text = text.lower()
    for role, words in ROLE_WORDS.items():
        if any(word in text for word in words):
            return role
    return None


def role_of(info, object_name):
    """The object's own name is the most reliable hint, then its material's, then its look:
    some models name every material after one part, but their objects stay meaningful."""
    named = keyword_role(object_name)
    if named:
        return named
    if info["alpha"] < 0.9:
        return "glass"
    by_material = keyword_role(info["name"])
    if by_material:
        return by_material
    if max(info["color"]) < 0.06:
        return "trim"
    return "paint"


def triangles(obj):
    return sum(len(polygon.vertices) - 2 for polygon in obj.data.polygons)


def join(objects, name):
    select(objects)
    if len(objects) > 1:
        bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    # Roblox names imported MeshParts after the mesh data, not the object.
    joined.data.name = name
    return joined


def merge_by_material(objects, prefix, roles, tyres=frozenset()):
    """Joins pieces that share a material and a role, recording each result's role. The
    tyre pieces wheel detection found are rubber whatever their material says."""
    groups = {}
    for obj in objects:
        material = obj.active_material
        role = "rubber" if obj in tyres else role_of(material_info(material), obj.name)
        groups.setdefault((material.name if material else "none", role), []).append(obj)
    joined = []
    for index, ((_, role), group) in enumerate(groups.items()):
        part = join(group, f"{prefix}_{index}")
        roles[part.name] = role
        joined.append(part)
    return joined


def decimate(obj, ratio):
    ratio = min(ratio, PER_MESH_LIMIT / max(triangles(obj), 1))
    if ratio >= 1:
        return
    modifier = obj.modifiers.new("Decimate", "DECIMATE")
    modifier.ratio = max(ratio, 0.05)
    select([obj])
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def shrink_textures(limit: int):
    for image in bpy.data.images:
        width, height = image.size
        if max(width, height) > limit:
            scale = limit / max(width, height)
            image.scale(max(1, round(width * scale)), max(1, round(height * scale)))


def render_preview(path: Path):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.display.shading.show_cavity = True
    scene.render.resolution_x = 960
    scene.render.resolution_y = 540
    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera_data.lens = 50
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    scene.collection.objects.link(camera)
    low, high = box(meshes())
    span = (high - low).length
    target = (low + high) / 2
    camera.location = target + Vector((span * 1.05, -span * 1.05, span * 0.55))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(camera, do_unlink=True)


def main():
    source, out, options = arguments()
    out.mkdir(parents=True, exist_ok=True)
    load(source)
    orient(options)
    low, high = box(meshes())
    smallest = (high - low).length * 0.004

    pieces = split_loose()
    wheels, corners, tyres = find_wheels(pieces, low, high)
    in_wheels = {obj for group in wheels.values() for obj in group}
    body = []
    for obj, a, b in pieces:
        if obj in in_wheels:
            continue
        if any(word in obj.name.lower() for word in HIDDEN_WORDS) or (b - a).length < smallest:
            bpy.data.objects.remove(obj, do_unlink=True)
        else:
            body.append(obj)

    roles = {}
    parts = merge_by_material(body, "Body", roles)
    wheel_parts = {key: merge_by_material(group, f"Wheel{key}", roles, tyres) for key, group in wheels.items() if group}

    everything = parts + [part for group in wheel_parts.values() for part in group]
    ratio = options["budget"] / max(sum(triangles(part) for part in everything), 1)
    for part in everything:
        decimate(part, ratio)

    manifest = {"source": source.parent.name, "length": options["length"], "parts": [], "wheels": {}}
    for part in everything:
        info = material_info(part.active_material)
        manifest["parts"].append(
            {
                "name": part.name,
                "role": roles.get(part.name, "paint"),
                "color": "#%02X%02X%02X" % tuple(round(min(max(c, 0), 1) ** (1 / 2.2) * 255) for c in info["color"]),
                "transparency": round(1 - info["alpha"], 2),
                "textured": info["textured"],
                "triangles": triangles(part),
            }
        )
    paint = [p for p in manifest["parts"] if p["role"] == "paint" and p["name"].startswith("Body")]
    if paint:
        max(paint, key=lambda p: p["triangles"])["role"] = "body"
    for key, (centre, size, _) in corners.items():
        manifest["wheels"][key] = {
            "centre": [round(centre.x, 3), round(centre.z, 3), round(-centre.y, 3)],
            "radius": round(size.z / 2, 3),
        }

    shrink_textures(int(options["texture"]))
    select(everything)
    bpy.ops.export_scene.gltf(filepath=str(out / "car.glb"), export_format="GLB", use_selection=True, export_yup=True)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1))
    render_preview(out / "preview.png")
    summary = {
        "parts": len(parts),
        "wheels": {key: len(group) for key, group in wheel_parts.items()},
        "triangles": sum(p["triangles"] for p in manifest["parts"]),
        "roles": sorted({p["role"] for p in manifest["parts"]}),
    }
    print("SUMMARY " + json.dumps(summary))


main()
