"""List every mesh the driver can see, with its materials and UV health.

blender -b <assembled.blend> --factory-startup --python-exit-code 1 -P tools/blender/car_eye_inventory.py -- <out dir> --eye x,y,z

Visibility: object-ID renders (Workbench, flat, single-sided, glass hidden, no AA, Raw view) from
a 3 x 3 grid over the cockpit eye range (Config/CarCamera EYE_RANGE: forward -0.15..0.12 m, up
-0.05..0.15 m around the seated eye, in the car's metres and Blender axes, nose along -Y; the DR458's
is 0.36,-1.45,0.98), at the cockpit field of view (60 deg vertical), looking
at yaw 0, +-30, +-60, +-100 and pitch +10, -10, -30. Pixel counts per object are written per view
group: `ahead` (yaw 0 and +-30, pitch -10 and +10) and `around` (everything else).
"""
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
out = Path(args[0])
out.mkdir(parents=True, exist_ok=True)
sc = bpy.context.scene
for c in bpy.data.collections:
    if c.name.startswith("Replaced"):
        c.hide_render = True
GLASS = ("_glass", "_window_", "glassLHL", "glassRHL", "glassLTL", "glassRTL", "glassLF")
meshes = [o for o in sc.objects if o.type == "MESH" and not o.hide_render
          and not any(c.hide_render for c in o.users_collection)]
glass = [o for o in meshes if any(s in o.name for s in GLASS)]
for o in glass:
    o.hide_render = True
meshes = [o for o in meshes if o not in glass]


def code(i):
    return ((i % 32) * 8 + 4) / 255, (((i // 32) % 32) * 8 + 4) / 255, ((i // 1024) * 8 + 4) / 255


for o in bpy.data.objects:
    o.color = (0, 0, 0, 1)
for i, o in enumerate(meshes, start=1):
    o.color = (*code(i), 1)

sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "FLAT"
sc.display.shading.color_type = "OBJECT"
sc.display.shading.show_backface_culling = True
sc.display.render_aa = "OFF"
sc.view_settings.view_transform = "Raw"
sc.view_settings.look = "None"
sc.view_settings.exposure = 0.0
sc.view_settings.gamma = 1.0
sc.render.dither_intensity = 0.0
sc.render.resolution_x, sc.render.resolution_y = 640, 360
sc.render.resolution_percentage = 100
sc.render.image_settings.file_format = "PNG"
sc.world = sc.world or bpy.data.worlds.new("W")
sc.world.color = (0, 0, 0)
cam = bpy.data.objects.new("IdCam", bpy.data.cameras.new("IdCam"))
cam.data.clip_start = 0.02
cam.data.sensor_fit = "VERTICAL"
cam.data.angle_y = math.radians(60)
sc.collection.objects.link(cam)
sc.camera = cam

EYE = Vector([float(v) for v in args[args.index("--eye") + 1].split(",")])
counts = {o.name: {"ahead": 0, "around": 0} for o in meshes}
views = 0
for fwd in (-0.15, 0.0, 0.12):
    for up in (-0.05, 0.05, 0.15):
        eye = EYE + Vector((0, -fwd, up))
        for yaw in (0, 30, -30, 60, -60, 100, -100):
            for pitch in (10, -10, -30):
                group = "ahead" if abs(yaw) <= 30 and pitch in (10, -10) else "around"
                y, p = math.radians(yaw), math.radians(pitch)
                d = Vector((math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p)))
                cam.location = eye
                cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
                path = out / "ids" / f"f{fwd:+.2f}_u{up:+.2f}_y{yaw:+d}_p{pitch:+d}.png"
                sc.render.filepath = str(path)
                bpy.ops.render.render(write_still=True)
                img = bpy.data.images.load(str(path))
                img.colorspace_settings.name = "Non-Color"
                px = (np.array(img.pixels[:]).reshape(-1, 4)[:, :3] * 255).round().astype(int)
                bpy.data.images.remove(img)
                idx = (px[:, 0] // 8) + (px[:, 1] // 8) * 32 + (px[:, 2] // 8) * 1024
                ok = (px[:, 0] % 8 == 4) & (px[:, 1] % 8 == 4) & (px[:, 2] % 8 == 4)
                ids, n = np.unique(idx[ok], return_counts=True)
                for i, c in zip(ids.tolist(), n.tolist()):
                    if 1 <= i <= len(meshes):
                        counts[meshes[i - 1].name][group] += c
                views += 1
                if path.parent.exists() and not (fwd == 0.0 and up == 0.05):
                    path.unlink()


def principled(m):
    if not m or not m.node_tree:
        return None
    return next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)


def mat_info(m):
    if m is None:
        return {"name": None}
    b = principled(m)
    imgs = []
    if m.node_tree:
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image:
                fp = bpy.path.abspath(n.image.filepath, library=n.image.library)
                imgs.append({"image": n.image.name, "path": n.image.filepath, "exists": Path(fp).exists()
                             or bool(n.image.packed_file)})
    info = {"name": m.name, "images": imgs, "viewport": [round(x, 3) for x in m.diffuse_color[:3]]}
    if b:
        bc = b.inputs["Base Color"]
        info["base_linked"] = bc.is_linked
        info["base"] = [round(x, 3) for x in bc.default_value[:3]]
        info["placeholder"] = (not bc.is_linked and not imgs
                               and all(abs(x - 0.8) < 1e-3 for x in bc.default_value[:3]))
    return info


def uv_health(o):
    me = o.data
    if not me.uv_layers:
        return {"layers": 0}
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.transform(o.matrix_world)
    uv = bm.loops.layers.uv.active
    ratios, area3, zero = [], 0.0, 0
    for f in bm.faces:
        a3 = f.calc_area()
        if a3 < 1e-9:
            continue
        pts = [l[uv].uv for l in f.loops]
        a2 = 0.0
        for k in range(1, len(pts) - 1):
            e1, e2 = pts[k] - pts[0], pts[k + 1] - pts[0]
            a2 += abs(e1.x * e2.y - e1.y * e2.x) / 2
        area3 += a3
        if a2 < 1e-12:
            zero += 1
            continue
        ratios.append(math.sqrt(a3 / a2))  # metres per UV unit
    bm.free()
    r = np.array(ratios) if ratios else np.array([0.0])
    return {"layers": len(me.uv_layers), "active": me.uv_layers.active.name, "area_m2": round(area3, 4),
            "zero_uv_faces": zero, "faces": len(me.polygons),
            "m_per_uv_p10_p50_p90": [round(float(np.percentile(r, q)), 4) for q in (10, 50, 90)]}


rows = []
for o in meshes:
    c = counts[o.name]
    if c["ahead"] + c["around"] == 0:
        continue
    pts = [o.matrix_world @ Vector(v) for v in o.bound_box]
    rows.append({
        "object": o.name,
        "collection": [col.name for col in o.users_collection],
        "library": o.library.filepath if o.library else None,
        "px_ahead": c["ahead"], "px_around": c["around"],
        "tris": sum(len(p.vertices) - 2 for p in o.data.polygons),
        "bounds_min": [round(min(p[k] for p in pts), 3) for k in range(3)],
        "bounds_max": [round(max(p[k] for p in pts), 3) for k in range(3)],
        "materials": [mat_info(s.material) for s in o.material_slots],
        "uv": uv_health(o),
    })
rows.sort(key=lambda r: -(r["px_ahead"] * 4 + r["px_around"]))
json.dump({"views": views, "visible_objects": len(rows), "meshes": len(meshes), "glass_hidden": [o.name for o in glass],
           "objects": rows}, open(out / "inventory_eye.json", "w"), indent=1)
print("INVENTORY", views, "views,", len(rows), "visible of", len(meshes), "meshes ->", out / "inventory_eye.json")
