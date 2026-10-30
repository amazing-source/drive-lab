"""Render the game's own views of the assembled car for side-by-sides with the reference photos.

blender -b <assembled car.blend> --factory-startup -P tools/blender/dr458/look_views.py -- <out dir> <manifest.json>

Workbench, material colours, studio light with cavity and shadows, single-sided as Roblox draws,
glass hidden (its placeholder colour would hide the cabin), 1280 x 720 at a 60-degree vertical
field (Config/CarCamera). Views:
- driver: the manifest's Driver_Eye looking 4 m ahead at bonnet height, and the same eye looking
  45 degrees left at the mirror and door, as the player looks around;
- chase: the default chase camera (orbit about the centre of mass, 3.3 m back, 1.2 m up, aimed
  4 m ahead of the rear axle, tilted 2 degrees up) and the same orbit looked 35 degrees either way.
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

out = Path(sys.argv[sys.argv.index("--") + 1])
manifest = sys.argv[sys.argv.index("--") + 2]
out.mkdir(parents=True, exist_ok=True)
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light, sh.color_type, sh.show_backface_culling = "STUDIO", "MATERIAL", True
sh.show_cavity, sh.show_shadows, sh.show_specular_highlight = True, True, True
sc.display.render_aa = "8"
sc.view_settings.view_transform = "Standard"
sc.render.resolution_x, sc.render.resolution_y = 1280, 720
sc.world = sc.world or bpy.data.worlds.new("W")
sc.world.color = (0.55, 0.6, 0.65)
GLASS = ("_glass", "_window_", "glassLHL", "glassRHL", "glassLTL", "glassRTL")
for o in sc.objects:
    if o.type == "MESH" and any(s in o.name for s in GLASS):
        o.hide_render = True
for c in bpy.data.collections:
    if c.name.startswith("Replaced"):
        c.hide_render = True
cam = bpy.data.objects.new("LookCam", bpy.data.cameras.new("LookCam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.sensor_fit, cam.data.angle_y, cam.data.clip_start = "VERTICAL", math.radians(60), 0.02

e = json.load(open(manifest))["points"]["Driver_Eye"]
eye = Vector((-e["right"], -e["forward"], e["up"]))
centre, look_at = Vector((0.0, -2.65 * 0.42, 0.345)), Vector((0.0, -4.0, 0.345))


def shot(name, loc, quat):
    cam.location = loc
    cam.rotation_euler = quat.to_euler()
    sc.render.filepath = str(out / f"{name}.png")
    bpy.ops.render.render(write_still=True)
    print("LOOK", name, tuple(round(x, 3) for x in loc))


ahead = (Vector((eye.x, eye.y - 4.0, 0.75)) - eye).to_track_quat("-Z", "Y")
shot("driver", eye, ahead)
shot("driver_left45", eye, Matrix.Rotation(math.radians(45), 3, "Z").to_quaternion() @ ahead)
for yaw in (0, 35, -35):
    R = Matrix.Rotation(math.radians(yaw), 3, "Z")
    loc = centre + R @ Vector((0.0, 3.3 + 2.65 * 0.42, 1.2))
    q = ((centre + R @ (look_at - centre)) - loc).to_track_quat("-Z", "Y") @ Matrix.Rotation(math.radians(2), 3, "X").to_quaternion()
    shot(f"chase_yaw{yaw:+d}", loc, q)
