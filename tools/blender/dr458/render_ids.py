"""Render the master from seeded random viewpoints with one flat colour per object, for before/after
comparisons (render_diff.py) that catch visible geometry lost or moved by a clean-up or decimation.

blender -b <master.blend> --factory-startup -P render_ids.py -- <out dir> [seed] [count]

Viewpoints: `count` exterior points (distance 3.5-7 m, height 0.3-2.5 m, any azimuth) and four
points around the driver's eye looking forward, left, right and down at the dash, all drawn from the
seed, so they differ from the fixed viewpoints the clean-up itself used. Colours are a hash of each
object's name, so deleting one object never recolours another; colours.json maps them back. Workbench,
flat, no anti-aliasing, Standard view transform (so a pixel's value identifies its object).
"""
import hashlib
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
out = Path(args[0])
out.mkdir(parents=True, exist_ok=True)
seed = int(args[1]) if len(args) > 1 else 5
count = int(args[2]) if len(args) > 2 else 12
rng = np.random.default_rng(seed)
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "FLAT"
sc.display.shading.color_type = "OBJECT"
sc.display.render_aa = "OFF"
sc.view_settings.view_transform = "Standard"
sc.view_settings.look = "None"
sc.view_settings.exposure = 0.0
sc.view_settings.gamma = 1.0
sc.render.resolution_x, sc.render.resolution_y = 800, 500
sc.render.image_settings.file_format = "PNG"
sc.world = sc.world or bpy.data.worlds.new("W")
sc.world.color = (0, 0, 0)
for c in bpy.data.collections:
    c.hide_render = c.name.startswith("Replaced")
for o in bpy.data.objects:
    h = hashlib.md5(o.name.encode()).digest()
    o.color = (h[0] / 255, h[1] / 255, h[2] / 255, 1)
cam = bpy.data.objects.new("IdCam", bpy.data.cameras.new("IdCam"))
sc.collection.objects.link(cam)
sc.camera = cam


def aim(loc, tgt, lens):
    cam.location = loc
    cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = lens


shots = []
for k in range(count):
    az, d, h = rng.uniform(0, 2 * math.pi), rng.uniform(3.5, 7.0), rng.uniform(0.3, 2.5)
    shots.append((f"ext{k:02d}", (d * math.cos(az), -1.4 + 1.2 * d * math.sin(az), h), (0, -1.4 + rng.uniform(-1, 1), 0.5), 35))
eye = Vector((0.36, -1.45, 0.98)) + Vector(rng.uniform(-0.05, 0.05, 3))
for name, tgt in (("int_fwd", (0.36, -3.0, 0.75)), ("int_left", (1.5, -1.6, 0.8)),
                  ("int_right", (-1.2, -1.8, 0.7)), ("int_dash", (0.1, -2.2, 0.55))):
    shots.append((name, tuple(eye), tgt, 18))
for name, loc, tgt, lens in shots:
    aim(loc, tgt, lens)
    sc.render.filepath = str(out / f"{name}.png")
    bpy.ops.render.render(write_still=True)
import json
json.dump({o.name: list(o.color[:3]) for o in bpy.data.objects if o.type == "MESH" and not o.hide_render
           and not any(c.name.startswith("Replaced") for c in o.users_collection)}, open(out / "colours.json", "w"))
print("IDS", out, len(shots), "views, seed", seed)
