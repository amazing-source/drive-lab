"""
Finds the SVJ's pedals in the cabin mesh, tags their faces for the export, and measures the
footwell the driver's feet work in.

    blender -b <car.blend> --factory-startup -P tools/blender/footwell.py -- <out dir> [--save <tagged.blend>]

The SVJ has two pedals and a footrest (Gigazine's Aventador S review: "the accelerator was organ
pedal style, the brake was hanging type"). In Interior_Geo_lodA, metres, driver on +x, nose -y:
- the throttle's plate: the islands lying within a few millimetres of its ribbed face's plane
  (the base it hinges on, its housing and its rod stay with the cabin);
- the brake: every island of the pad and its arm, which hangs from under the dash;
- the footrest: islands too, but it does not move, so it stays.

With --save, each pedal's faces get the integer face attribute `door_part` (4 throttle, 5 brake; 1 to 3 are the door's)
that tools/blender/hero_car_door_export.py turns into parts, and the blend is saved under a new
name; the source blend is never written. Prints and writes footwell.json: per pedal its hinge (a
line along the car's width), the sole's heel and ball points at rest, in metres in the driver's
seat frame (the car's footwell in Config/Cars/<Car>/Driver), and a render of the selection.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

PEDAL_TAGS = {"throttle": 4, "brake": 5}
# The DriverSeat part's origin in the blend (SVJModel.seat from the centre of mass, before the
# body raise): the frame the car's footwell is written in.
SEAT = Vector((0.38, -0.061, 0.2814))
BOXES = {
    "throttle": (Vector((0.13, -1.20, 0.025)), Vector((0.275, -0.88, 0.31))),
    "brake": (Vector((0.28, -1.10, 0.17)), Vector((0.41, -0.90, 0.392))),
    "footrest": (Vector((0.43, -1.09, 0.025)), Vector((0.53, -0.92, 0.29))),
}
# The throttle's ribbed face: a point on it and its normal (the rubber strips are flat on it).
PLATE_POINT = Vector((0.2018, -0.9369, 0.1142))
PLATE_NORMAL = Vector((0.0024, 0.8964, 0.4433)).normalized()
PLATE_BEHIND, PLATE_FRONT = 0.025, 0.006
FLOOR = 0.048
# A sole from heel to the ball of the foot.
FOOT = 0.2


def option(args, name, default):
    return args[args.index(name) + 1] if name in args else default


def islands(bm):
    seen = set()
    for f in bm.faces:
        if f.index in seen:
            continue
        stack = [f]
        seen.add(f.index)
        comp = []
        while stack:
            g = stack.pop()
            comp.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        yield comp


def seat_frame(p):
    """Blender metres -> the seat frame (x right, y up, z back), metres."""
    d = Vector(p) - SEAT
    return [round(-d.x, 4), round(d.z, 4), round(d.y, 4)]


def select(obj):
    mw = obj.matrix_world
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    chosen = {name: [] for name in BOXES}
    for comp in islands(bm):
        pts = [mw @ v.co for v in {v for f in comp for v in f.verts}]
        for name, (lo, hi) in BOXES.items():
            if not all(lo.x <= p.x <= hi.x and lo.y <= p.y <= hi.y and lo.z <= p.z <= hi.z for p in pts):
                continue
            if name == "throttle":
                offsets = [(p - PLATE_POINT).dot(PLATE_NORMAL) for p in pts]
                if not (min(offsets) > -PLATE_BEHIND and max(offsets) < PLATE_FRONT and min(p.z for p in pts) > 0.045):
                    continue
            chosen[name].extend(f.index for f in comp)
    return bm, chosen


def bounds(bm, mw, faces):
    pts = [mw @ v.co for i in faces for v in bm.faces[i].verts]
    lo = Vector([min(p[k] for p in pts) for k in range(3)])
    hi = Vector([max(p[k] for p in pts) for k in range(3)])
    return pts, lo, hi


def measure(bm, mw, chosen):
    out = {}
    pts, lo, hi = bounds(bm, mw, chosen["throttle"])
    # Hinged where the plate meets its base: its lowest edge, across its width.
    bottom = min(pts, key=lambda p: p.z)
    hinge = Vector(((lo.x + hi.x) / 2, bottom.y, bottom.z))
    along = Vector((0, -PLATE_NORMAL.z, PLATE_NORMAL.y)).normalized()
    if along.z < 0:
        along = -along
    heel = hinge + PLATE_NORMAL * 0.004 + along * 0.008
    # The plate leans inboard as it rises: the ball follows its centre line.
    top_band = [p for p in pts if p.z > heel.z + FOOT * along.z - 0.02]
    ball = heel + along * FOOT
    if top_band:
        ball.x = sum(p.x for p in top_band) / len(top_band)
    out["throttle"] = {"hinge": seat_frame(hinge), "heel": seat_frame(heel), "ball": seat_frame(ball), "triangles": sum(len(bm.faces[i].verts) - 2 for i in chosen["throttle"])}
    pts, lo, hi = bounds(bm, mw, chosen["brake"])
    top = max(pts, key=lambda p: p.z)
    hinge = Vector(((lo.x + hi.x) / 2, top.y, top.z - 0.006))
    # The pad's face: the faces low on the pedal that look back at the driver, their middle by
    # area, a few millimetres out along their normal.
    face = [bm.faces[i] for i in chosen["brake"]]
    pad_faces = [f for f in face if (mw.to_3x3() @ f.normal).y > 0.6 and (mw @ f.calc_center_median()).z < 0.26]
    area = sum(f.calc_area() for f in pad_faces)
    pad = sum(((mw @ f.calc_center_median()) * f.calc_area() for f in pad_faces), Vector()) / area
    normal = sum(((mw.to_3x3() @ f.normal) * f.calc_area() for f in pad_faces), Vector()).normalized()
    pad = pad + normal * 0.004
    rise = pad.z - FLOOR
    heel = Vector((pad.x, pad.y + math.sqrt(max(0.0, FOOT * FOOT - rise * rise)), FLOOR))
    out["brake"] = {"hinge": seat_frame(hinge), "heel": seat_frame(heel), "ball": seat_frame(pad), "triangles": sum(len(bm.faces[i].verts) - 2 for i in chosen["brake"])}
    pts, lo, hi = bounds(bm, mw, chosen["footrest"])
    face_n = Vector((0, 0.9168, 0.3994))
    up_along = Vector((0, -face_n.z, face_n.y)).normalized()
    heel = Vector(((lo.x + hi.x) / 2, hi.y, lo.z + 0.01))
    out["footrest"] = {"heel": seat_frame(heel), "ball": seat_frame(heel + up_along * FOOT)}
    return out


def tag(obj, bm, chosen):
    layer = bm.faces.layers.int.get("door_part") or bm.faces.layers.int.new("door_part")
    for name, value in PEDAL_TAGS.items():
        for i in chosen[name]:
            assert bm.faces[i][layer] == 0, f"face {i} is already tagged {bm.faces[i][layer]}"
            bm.faces[i][layer] = value
    bm.to_mesh(obj.data)


def render(obj, chosen, out):
    mesh = obj.data
    colours = {"throttle": (0.1, 0.8, 0.2, 1), "brake": (0.9, 0.1, 0.1, 1), "footrest": (0.1, 0.4, 0.95, 1)}
    base = bpy.data.materials.new("Base")
    base.diffuse_color = (0.55, 0.55, 0.58, 1)
    mesh.materials.clear()
    mesh.materials.append(base)
    for slot, name in enumerate(colours, start=1):
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = colours[name]
        mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.material_index = 0
    for slot, name in enumerate(colours, start=1):
        for i in chosen[name]:
            mesh.polygons[i].material_index = slot
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o is not obj and "Steering" not in o.name:
            o.hide_render = True
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.render.resolution_x, scene.render.resolution_y = 1200, 900
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    for name, eye, target, lens in (
        ("driver", (0.36, -0.35, 0.42), (0.33, -0.98, 0.15), 24),
        ("inboard", (0.05, -0.75, 0.33), (0.32, -0.98, 0.17), 20),
    ):
        eye, target = Vector(eye), Vector(target)
        forward = (target - eye).normalized()
        right = forward.cross(Vector((0, 0, 1))).normalized()
        up = right.cross(forward)
        cam.matrix_world = Matrix(((right.x, up.x, -forward.x, eye.x), (right.y, up.y, -forward.y, eye.y), (right.z, up.z, -forward.z, eye.z), (0, 0, 0, 1)))
        cam.data.lens = lens
        cam.data.clip_start = 0.01
        scene.render.filepath = os.path.join(out, f"pedals_{name}.png")
        bpy.ops.render.render(write_still=True)


def main(args):
    out = args[0]
    save = option(args, "--save", None)
    os.makedirs(out, exist_ok=True)
    obj = bpy.data.objects["Interior_Geo_lodA"]
    bm, chosen = select(obj)
    report = measure(bm, obj.matrix_world, chosen)
    report["faces"] = {name: len(faces) for name, faces in chosen.items()}
    if save:
        tag(obj, bm, chosen)
        bpy.ops.wm.save_as_mainfile(filepath=save, copy=True)
        report["saved"] = save
    bm.free()
    json.dump(report, open(os.path.join(out, "footwell.json"), "w"), indent=1)
    print(json.dumps(report, indent=1))
    render(obj, chosen, out)


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1 :])
