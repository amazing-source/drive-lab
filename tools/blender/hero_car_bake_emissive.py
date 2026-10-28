"""
Bakes the hero car's emissive textures into each mesh's first UV set, run headless by Blender:

    blender --background --python tools/blender/hero_car_bake_emissive.py -- <car.blend> \
        <texture dir> <out dir> [--size 2048]

The cockpit and the lights carry a second UV set, UVChannel_2, and their emissive textures
(instrument cluster, switch glyphs, light elements) are laid out for it, not for the first set
the colour, normal and material maps use. A Roblox MeshPart has a single UV set, so each
emissive texture is read through UVChannel_2 and baked into UVChannel_1's layout, after which
it lines up with the colour map pixel for pixel. Merging the two without this step painted
cluster glyphs over the steering wheel and the mirror.
"""

import sys
from pathlib import Path

import bpy

TARGETS = {
    "Interior_Geo_lodA": ("Lamborghini_AventadorSVJ_2019_InteriorA_Emissive.png", "interior_emissive_uv1.png"),
    "Light_Geo_lodA": ("Lamborghini_AventadorSVJ_2019_LightA_Emissive.png", "light_emissive_uv1.png"),
}

args = sys.argv[sys.argv.index("--") + 1 :]
blend, textures, out = Path(args[0]), Path(args[1]), Path(args[2])
size = int(args[args.index("--size") + 1]) if "--size" in args else 2048
out.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(blend))

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 1

for object_name, (source_name, out_name) in TARGETS.items():
    obj = bpy.data.objects[object_name]
    target = bpy.data.images.new(out_name, size, size, alpha=False)

    material = bpy.data.materials.new(f"Bake_{object_name}")
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    nodes.clear()
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = "UVChannel_2"
    source = nodes.new("ShaderNodeTexImage")
    source.image = bpy.data.images.load(str(textures / source_name))
    emission = nodes.new("ShaderNodeEmission")
    output = nodes.new("ShaderNodeOutputMaterial")
    links.new(uv.outputs["UV"], source.inputs["Vector"])
    links.new(source.outputs["Color"], emission.inputs["Color"])
    links.new(emission.outputs["Emission"], output.inputs["Surface"])
    destination = nodes.new("ShaderNodeTexImage")
    destination.image = target
    nodes.active = destination

    obj.data.materials.clear()
    obj.data.materials.append(material)
    obj.data.uv_layers.active = obj.data.uv_layers["UVChannel_1"]

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.bake(type="EMIT", margin=4, use_clear=True)

    target.filepath_raw = str(out / out_name)
    target.file_format = "PNG"
    target.save()
    print(f"baked {source_name} -> {out / out_name} ({size} px)")
