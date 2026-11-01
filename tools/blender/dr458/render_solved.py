"""Render a master through a photo's solved camera (overlay/v2 solve.py output), for a side-by-side
with the photo at the same framing.

blender -b <master.blend> --factory-startup -P tools/blender/dr458/render_solved.py -- <solve.json> <out.png> [scale]

Pinhole camera: focal_px over the photo width gives the lens on a 36 mm sensor; camera_rotation_cv
rows are the camera's right, down and forward in Blender's world frame, so the Blender camera's
axes are (right, -down, -forward). A principal point off the image centre becomes a lens shift.
Workbench, studio light, each material's viewport colour, single-sided as Roblox draws; glass
hidden; rendered at `scale` of the photo's size (default 0.5).
"""
import json
import math
import sys

import bpy
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:]
sol = json.load(open(args[0]))
out = args[1]
scale = float(args[2]) if len(args) > 2 else 0.5
W, H = sol.get("size") or sol.get("image_size") or [3470, 2313]
f = sol["focal_px"]
R = [Vector(r) for r in sol["camera_rotation_cv"]]
C = Vector(sol["camera_position_m"])
pp = sol.get("principal_point_px") or [W / 2, H / 2]
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"
sc.display.shading.color_type = "MATERIAL"
sc.display.shading.show_backface_culling = True
sc.display.render_aa = "8"
sc.view_settings.view_transform = "Standard"
sc.render.resolution_x, sc.render.resolution_y = int(W * scale), int(H * scale)
sc.render.film_transparent = True
for c in bpy.data.collections:
    c.hide_render = c.name.startswith("Replaced")
for o in sc.objects:
    if o.type == "MESH" and any(s in o.name for s in ("_glass", "_window_")):
        o.hide_render = True
cam = bpy.data.objects.new("SolvedCam", bpy.data.cameras.new("SolvedCam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.sensor_fit = "HORIZONTAL"
cam.data.sensor_width = 36.0
cam.data.lens = f * 36.0 / W
cam.data.shift_x = -(pp[0] - W / 2) / W
cam.data.shift_y = (pp[1] - H / 2) / W
cam.data.clip_start = 0.05
right, down, fwd = R
cam.matrix_world = Matrix((
    (right.x, -down.x, -fwd.x, C.x),
    (right.y, -down.y, -fwd.y, C.y),
    (right.z, -down.z, -fwd.z, C.z),
    (0, 0, 0, 1)))
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("SOLVED render", out, f"lens {cam.data.lens:.2f} mm", sc.render.resolution_x, sc.render.resolution_y)
