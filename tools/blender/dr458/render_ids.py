"""Render the master from seeded random viewpoints with one flat colour per object, for before/after
comparisons (tools/assets/dr458/render_diff.py) that catch visible geometry lost or moved by a clean-up or decimation.

blender -b <master.blend> --factory-startup -P tools/blender/dr458/render_ids.py -- <out dir> [seed] [count]

Drawn as Roblox draws MeshParts: single-sided (backface culling on), and through glass (glass and
lamp lenses hidden, so what lies behind them is compared too). Viewpoints, all drawn from the seed
so they differ from the fixed ones the clean-up itself used:
- `count` exterior points (3.5-7 m, 0.3-2.5 m high, any azimuth);
- six close on-foot points (0.4-1.5 m outside the body, 0.4-2.4 m high) aimed into the cabin;
- the cockpit eye anywhere in the camera's range (Config/CarCamera EYE_RANGE), looking forward,
  left, right, at the dash, down into the driver's footwell and across to the passenger's;
- three points at the open driver's door, with the door's own objects hidden.
Each cockpit-eye view is also rendered with the glass shown (`<name>_holes.png`): from inside the
closed car every pixel should be car or glass, so a background pixel there is a hole (holes_check.py).
Colours are a hash of each object's name, so deleting one object never recolours another;
colours.json maps them back. Workbench, flat, no anti-aliasing, Standard view transform.
"""
import hashlib
import json
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
sc.display.shading.show_backface_culling = True
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
cam.data.clip_start = 0.02
sc.collection.objects.link(cam)
sc.camera = cam
meshes = [o for o in sc.objects if o.type == "MESH"]
base_hidden = {o.name: o.hide_render for o in meshes}
GLASS = ("_glass", "_window_", "glassLHL", "glassRHL", "glassLTL", "glassRTL")
DOOR_L = ("doorLF_", "mirrorL_", "glassLF_", "Door_L")


def shoot(name, loc, tgt, fov_v_deg, hide, holes=False):
    for o in meshes:
        o.hide_render = base_hidden[o.name] or any(s in o.name for s in hide)
    cam.location = Vector(loc)
    cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle_y = math.radians(fov_v_deg)
    sc.render.filepath = str(out / f"{name}.png")
    bpy.ops.render.render(write_still=True)
    if holes:
        for o in meshes:
            o.hide_render = base_hidden[o.name] or any(s in o.name for s in hide if s not in GLASS)
        sc.render.filepath = str(out / f"{name}_holes.png")
        bpy.ops.render.render(write_still=True)


n = 0
for k in range(count):
    az, d, h = rng.uniform(0, 2 * math.pi), rng.uniform(3.5, 7.0), rng.uniform(0.3, 2.5)
    shoot(f"ext{k:02d}", (d * math.cos(az), -1.4 + 1.2 * d * math.sin(az), h), (0, -1.4 + rng.uniform(-1, 1), 0.5), 30, GLASS)
    n += 1
for k in range(6):
    az, off, h = rng.uniform(0, 2 * math.pi), rng.uniform(0.4, 1.5), rng.uniform(0.4, 2.4)
    loc = ((0.98 + off) * math.cos(az), -1.48 + (2.15 + off) * math.sin(az), h)
    shoot(f"near{k:02d}", loc, (rng.uniform(-0.4, 0.4), rng.uniform(-2.2, -1.0), rng.uniform(0.2, 0.8)), 60, GLASS)
    n += 1
eye = Vector((0.36 + rng.uniform(-0.06, 0.06), -1.45 - rng.uniform(-0.15, 0.12), 0.98 + rng.uniform(-0.05, 0.15)))
for name, tgt in (("int_fwd", (0.36, -3.0, 0.75)), ("int_left", (1.5, -1.6, 0.8)), ("int_right", (-1.2, -1.8, 0.7)),
                  ("int_dash", (0.1, -2.2, 0.55)), ("int_own_footwell", (0.36, -2.35, 0.12)),
                  ("int_pass_footwell", (-0.40, -2.30, 0.15))):
    jitter = Vector(rng.uniform(-0.08, 0.08, 3))
    shoot(name, tuple(eye), tuple(Vector(tgt) + jitter), 60, GLASS, holes=True)
    n += 1
for k in range(3):
    loc = (rng.uniform(1.0, 2.0), rng.uniform(-2.3, -0.9), rng.uniform(0.5, 2.0))
    shoot(f"door{k:02d}", loc, (rng.uniform(-0.2, 0.5), rng.uniform(-2.3, -1.2), rng.uniform(0.15, 0.6)), 60, GLASS + DOOR_L)
    n += 1
json.dump({o.name: list(o.color[:3]) for o in meshes if not base_hidden[o.name]
           and not any(c.name.startswith("Replaced") for c in o.users_collection)}, open(out / "colours.json", "w"))
print("IDS", out, n, "views, seed", seed)
