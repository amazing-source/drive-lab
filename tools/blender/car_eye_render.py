"""Look-dev renders of the cockpit from fixed cameras, with fixed light, materials untouched.

blender -b <car.blend> --factory-startup --python-exit-code 1 -P tools/blender/car_eye_render.py -- <out dir> [<view> ...]
        [--res 1280x720] [--light sun|overcast|hdri:<name>] [--views <views.json>] [--show-glass]

Views (the DR458's, in its metres; --views replaces them with {name: [[eye], [target], fov_deg]}):
- driver: eye 0.36, -1.42, 0.98 looking at 0.36, -3.0, 0.80, 70 deg (the team's reference driver view);
- wheel:  from the driver's eye at the wheel and binnacle, framed like photo interior/010;
- across: from the passenger door across the dash to the driver's side, framed like photo 002;
- down:   from the eye down at the footwell, tunnel and floor;
- duct:   from the eye at the cooling duct up the passenger A-pillar (photo 002, right).
Light `sun` (default, the team's reference light): Nishita sky at 35 deg (strength 0.35), sun 3.0 at
55/150 deg; light `overcast`: a neutral sky, 1.0 overhead to 0.35 below, no sun, as the photos were
taken; light `hdri:<name>`: one of Blender's bundled world HDRIs (city, courtyard, ...), so gloss
shows. All: EEVEE with screen-space ray tracing and fast GI (occlusion inside the cabin), AgX, exposure 0.6.
Glass is hidden (Roblox draws through it) unless --show-glass. Placeholder materials are
NOT recoloured, so what renders is what the file carries.
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
out = Path(args[0])
out.mkdir(parents=True, exist_ok=True)
res = args[args.index("--res") + 1] if "--res" in args else "1280x720"
skip = {res, "sun", "overcast", args[args.index("--light") + 1] if "--light" in args else ""}
views = [a for a in args[1:] if not a.startswith("--") and a not in skip and not a.endswith(".json")]
views = views or ["driver", "wheel", "across", "down", "duct"]
W, H = (int(x) for x in res.split("x"))
sc = bpy.context.scene

GLASS = ("_glass", "_window_", "glassLHL", "glassRHL", "glassLTL", "glassRTL", "glassLF")
for o in sc.objects:
    if o.type == "MESH" and any(s in o.name for s in GLASS) and "--show-glass" not in args:
        o.hide_render = True
for c in bpy.data.collections:
    if c.name.startswith("Replaced"):
        c.hide_render = True

LIGHT = args[args.index("--light") + 1] if "--light" in args else "sun"
world = bpy.data.worlds.new("Daylight")
world.use_nodes = True
nt = world.node_tree
bg = nt.nodes["Background"]
if LIGHT == "sun":
    sky = nt.nodes.new("ShaderNodeTexSky")
    types = [i.identifier for i in sky.bl_rna.properties["sky_type"].enum_items]
    if "NISHITA" in types:
        sky.sky_type = "NISHITA"
    sky.sun_elevation = math.radians(35)
    sky.sun_rotation = math.radians(150)
    nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.35
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.0
    sun.data.angle = math.radians(1.0)
    sc.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(55), 0, math.radians(150))
elif LIGHT.startswith("hdri:"):
    # A recorded environment, so gloss has something to reflect (Blender's bundled studio lights).
    hdri = Path(bpy.utils.resource_path("LOCAL")) / "datafiles" / "studiolights" / "world" / (LIGHT[5:] + ".exr")
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(str(hdri))
    nt.links.new(env.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.0
else:
    # Overcast: a neutral sky brighter overhead than at the horizon, no sun, as in the photos.
    grad = nt.nodes.new("ShaderNodeTexGradient")
    grad.gradient_type = "LINEAR"
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position, ramp.color_ramp.elements[0].color = 0.0, (0.35, 0.35, 0.36, 1)
    ramp.color_ramp.elements[1].position, ramp.color_ramp.elements[1].color = 1.0, (1.0, 1.0, 1.02, 1)
    nt.links.new(tc.outputs["Generated"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.0
sc.world = world

cam = bpy.data.objects.new("Eye", bpy.data.cameras.new("Eye"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.sensor_fit = "VERTICAL"
cam.data.clip_start = 0.02
engines = [e.identifier for e in sc.render.bl_rna.properties["engine"].enum_items]
sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = W, H, 100
sc.render.image_settings.file_format = "PNG"
try:
    sc.view_settings.view_transform = "AgX"
except TypeError:
    sc.view_settings.view_transform = "Filmic"
sc.view_settings.look = "None"
sc.view_settings.exposure = 0.6
ee = sc.eevee
for attr, val in (("use_raytracing", True), ("ray_tracing_method", "SCREEN"), ("use_fast_gi", True),
                  ("fast_gi_method", "GLOBAL_ILLUMINATION"), ("use_shadows", True), ("taa_render_samples", 64)):
    if hasattr(ee, attr):
        setattr(ee, attr, val)

VIEWS = {
    "driver": ((0.36, -1.42, 0.98), (0.36, -3.0, 0.80), 70),
    "wheel": ((0.36, -1.40, 0.96), (0.36, -2.10, 0.74), 48),
    "across": ((-0.62, -1.55, 0.98), (0.30, -2.05, 0.62), 62),
    "down": ((0.36, -1.45, 1.00), (0.20, -2.25, 0.20), 70),
    "duct": ((0.30, -1.50, 1.00), (-0.55, -1.75, 0.50), 55),
}
if "--views" in args:
    VIEWS = {k: tuple(v) for k, v in json.loads(Path(args[args.index("--views") + 1]).read_text()).items()}
for v in views:
    loc, tgt, fov = VIEWS[v]
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    cam.data.angle_y = math.radians(fov)
    sc.render.filepath = str(out / f"{v}.png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", sc.render.filepath)
