"""
Lists every material of the hero car as Roblox will need it, run headless by Blender:

    blender --background --python tools/blender/hero_car_materials.py -- <car.blend> <out.json>

The glTF export drops most of this car's textures (its materials come from an FBX and route
textures through nodes the exporter cannot follow), so the Studio side builds SurfaceAppearances
itself. For each material this records the image files feeding each input of its shader, found
by walking every node upstream of the output, plus the base values (colour, metalness,
roughness, alpha) and the blend mode. Image roles are also read from the file names, which this
model's source game names by purpose (DiffuseAOSO, Normal, Material, MaterialOpacity, Emissive).
"""

import json
import sys
from pathlib import Path

import bpy

blend, out = (Path(arg) for arg in sys.argv[sys.argv.index("--") + 1 :][:2])
bpy.ops.wm.open_mainfile(filepath=str(blend))

SUFFIXES = ("DiffuseAOSO", "Diffuse", "Normal", "MaterialOpacity", "Material", "Emissive", "Opacity", "SpecularTint")


def role_from_name(name: str) -> str:
    stem = Path(name).stem.replace(".dds", "")
    for suffix in SUFFIXES:
        if stem.endswith(suffix) or f"_{suffix}" in stem:
            return suffix
    if "norm" in stem.lower():
        return "Normal"
    if "diff" in stem.lower():
        return "Diffuse"
    return "unknown"


def upstream_images(node, seen):
    found = []
    if node in seen:
        return found
    seen.add(node)
    if node.type == "TEX_IMAGE" and node.image:
        found.append(node.image)
    for socket in node.inputs:
        for link in socket.links:
            found.extend(upstream_images(link.from_node, seen))
    return found


def value(socket):
    if socket is None or socket.is_linked:
        return None
    default = socket.default_value
    try:
        return [round(v, 4) for v in default]
    except TypeError:
        return round(default, 4)


report = {}
used = {slot.material for o in bpy.data.objects if o.type == "MESH" for slot in o.material_slots if slot.material}
for material in sorted(used, key=lambda m: m.name):
    entry = {"blend": getattr(material, "surface_render_method", None) or getattr(material, "blend_method", None)}
    if material.use_nodes:
        principled = next((n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if principled:
            entry["baseColor"] = value(principled.inputs.get("Base Color"))
            entry["metallic"] = value(principled.inputs.get("Metallic"))
            entry["roughness"] = value(principled.inputs.get("Roughness"))
            entry["alpha"] = value(principled.inputs.get("Alpha"))
            per_input = {}
            for name in ("Base Color", "Normal", "Alpha", "Roughness", "Metallic", "Emission Color", "Specular IOR Level"):
                socket = principled.inputs.get(name)
                if socket and socket.is_linked:
                    images = upstream_images(socket.links[0].from_node, set())
                    per_input[name] = sorted({Path(bpy.path.abspath(i.filepath)).name for i in images})
            entry["inputs"] = per_input
        all_images = upstream_images(next(n for n in material.node_tree.nodes if n.type == "OUTPUT_MATERIAL"), set()) if any(
            n.type == "OUTPUT_MATERIAL" for n in material.node_tree.nodes
        ) else []
        entry["images"] = {Path(bpy.path.abspath(i.filepath)).name: role_from_name(i.filepath) for i in all_images}
    report[material.name] = entry

out.write_text(json.dumps(report, indent=1))
for name, entry in report.items():
    print(name, "|", entry.get("blend"), "| base", entry.get("baseColor"), "| a", entry.get("alpha"),
          "| m", entry.get("metallic"), "r", entry.get("roughness"), "|", entry.get("images"))
