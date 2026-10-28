"""
Builds the seated driver's leg meshes for Roblox: a thigh and a shin trouser sleeve, the trousers'
seat under the torso and a pair of shoes, real-sized (the legs reach the car's real pedals).

    blender -b --factory-startup -P tools/blender/driver_legs.py -- <out dir> <shoe.obj|.glb>
        [--shoe-length 0.285] [--keep -x|+x|both] [--toe -y]

Trousers: oval tubes like the arm sleeves of driver_sleeves.py, a little fuller where cloth
bunches at the hip and the knee; the shin's end is an open hem a little wider than the ankle,
so it hangs over the shoe's collar. Exported one stud long along z (the end nearer the body at
+z), cross-sections real; the game stretches each to its bone.

Shoe: a source mesh, measured and turned into the shoe's frame (origin at the ankle joint, x to
the car's right, y up out of the instep, z from the toes to the heel), scaled to --shoe-length
from heel to toe, its sole's lowest point at y = -ANKLE_UP and its heel's back ANKLE_ALONG
behind the ankle. --keep keeps one shoe of a pair (MakeHuman's right shoe is -x). The left shoe
is the right mirrored. UVs are kept; the colour map is uploaded on its own and set as the
shoes' SurfaceAppearance in the place.

Output: thigh.glb, shin.glb, pelvis.glb, shoe_R.glb, shoe_L.glb in studs at the world scale (1 m = 1.5 / 0.28
studs); legs.json (the shoe's mesh centre in its frame, metres, and its sole points); renders.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

STUDS_PER_METRE = 1.5 / 0.28
RINGS = 30
SEGMENTS = 24
# The shoe frame's numbers, as Config/DriverLegs has them: the ankle joint along the sole from
# where the heel meets the ground, and up off it.
ANKLE_ALONG = 0.075
ANKLE_UP = 0.085


def option(args, name, default):
    return args[args.index(name) + 1] if name in args else default


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def tube(name, radius_at, folds, open_end):
    """A closed oval tube, t = 0 at the body end (+z) to 1 at the far end (-z), length 1. With
    open_end the far end is a hem: the cloth turns in a little instead of closing."""
    mesh = bmesh.new()
    rings = []
    for i in range(RINGS + 1):
        t = i / RINGS
        rx, ry = radius_at(t)
        end = min(t, 1 - t) if not open_end else t
        dome = math.sqrt(max(0.0, 1 - (max(0.0, 0.05 - end) / 0.05) ** 2)) if end < 0.05 else 1.0
        ring = []
        for j in range(SEGMENTS):
            theta = 2 * math.pi * j / SEGMENTS
            fold = folds(t, theta)
            ring.append(mesh.verts.new((rx * dome * (1 + fold) * math.cos(theta), ry * dome * (1 + fold) * math.sin(theta), 0.5 - t)))
        rings.append(ring)
    if open_end:
        # The hem's thickness: an inner ring a few millimetres in, back up the leg.
        rx, ry = radius_at(1.0)
        inner = [mesh.verts.new((v.co.x * (1 - 0.006 / rx), v.co.y * (1 - 0.006 / ry), v.co.z + 0.012)) for v in rings[-1]]
        rings.append(inner)
    for a, b in zip(rings, rings[1:]):
        for j in range(SEGMENTS):
            k = (j + 1) % SEGMENTS
            mesh.faces.new((a[j], a[k], b[k], b[j]))
    mesh.faces.new(list(reversed(rings[0])))
    if not open_end:
        mesh.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(mesh, faces=mesh.faces)
    data = bpy.data.meshes.new(name)
    mesh.to_mesh(data)
    for polygon in data.polygons:
        polygon.use_smooth = True
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return obj


def thigh_radius(t):
    # 17 x 15 cm at the hip, 12.5 x 12 cm at the knee: a seated thigh flattens on the cushion.
    rx = lerp(0.085, 0.0625, smoothstep(0.0, 1.0, t))
    ry = lerp(0.075, 0.06, smoothstep(0.0, 1.0, t))
    return rx, ry


def shin_radius(t):
    # 12 cm at the knee, the calf at a third, then straight trousers to an ankle hem of 11.5 cm.
    calf = 0.004 * math.exp(-(((t - 0.3) / 0.15) ** 2))
    rx = lerp(0.06, 0.056, smoothstep(0.0, 1.0, t)) + calf
    ry = lerp(0.058, 0.054, smoothstep(0.0, 1.0, t)) + calf
    return rx, ry


def thigh_folds(t, theta):
    weight = 0.35 * math.exp(-((t - 0.08) / 0.1) ** 2) + 0.5 * math.exp(-((t - 0.92) / 0.1) ** 2)
    wave = 0.6 * math.sin(2 * math.pi * 6 * t + 0.8 * math.cos(theta)) + 0.4 * math.sin(2 * math.pi * 10 * t + 1.2 * math.sin(2 * theta))
    return 0.05 * weight * wave


def shin_folds(t, theta):
    # Bunched under the knee and where the hem breaks over the shoe.
    weight = 0.5 * math.exp(-((t - 0.08) / 0.1) ** 2) + 0.4 * math.exp(-((t - 0.88) / 0.08) ** 2)
    wave = 0.6 * math.sin(2 * math.pi * 7 * t + 0.9 * math.sin(theta)) + 0.4 * math.sin(2 * math.pi * 12 * t + 1.3 * math.cos(2 * theta))
    return 0.06 * weight * wave


# The trousers' seat under the R6 torso, metres at Driving.DRIVER_SCALE: from inside the torso
# down to the bucket's cushion, wide as the torso, reaching forward under the start of the thighs.
PELVIS = (0.33, 0.22, 0.25)


def pelvis(name):
    """A rounded block (a superellipsoid), x across, y up, z back, soft folds round its waist."""
    width, height, depth = PELVIS
    obj_mesh = bmesh.new()
    rings = []
    stacks, segments, power = 16, 32, 4.0

    def signed_pow(value, exponent):
        return math.copysign(abs(value) ** exponent, value)

    for i in range(stacks + 1):
        v = -math.pi / 2 + math.pi * i / stacks
        ring = []
        for j in range(segments):
            u = 2 * math.pi * j / segments
            fold = 1 + 0.02 * math.sin(6 * u) * math.cos(v) ** 2
            x = width / 2 * signed_pow(math.cos(v), 2 / power) * signed_pow(math.cos(u), 2 / power) * fold
            z = depth / 2 * signed_pow(math.cos(v), 2 / power) * signed_pow(math.sin(u), 2 / power) * fold
            y = height / 2 * signed_pow(math.sin(v), 2 / power)
            ring.append(obj_mesh.verts.new((x, y, z)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for j in range(segments):
            k = (j + 1) % segments
            obj_mesh.faces.new((a[j], a[k], b[k], b[j]))
    bmesh.ops.remove_doubles(obj_mesh, verts=obj_mesh.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(obj_mesh, faces=obj_mesh.faces)
    data = bpy.data.meshes.new(name)
    obj_mesh.to_mesh(data)
    for polygon in data.polygons:
        polygon.use_smooth = True
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return obj


def export(obj, path, stretch_z):
    """Roblox (x, y, z) is Blender (-x, z, y) after the glTF importer's half turn."""
    copy = obj.copy()
    copy.data = obj.data.copy()
    bpy.context.collection.objects.link(copy)
    swap = Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    scale = Matrix.Diagonal((STUDS_PER_METRE, STUDS_PER_METRE, STUDS_PER_METRE if stretch_z else 1, 1))
    copy.data.transform(swap @ scale)
    bpy.ops.object.select_all(action="DESELECT")
    copy.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_materials="NONE")
    bpy.data.objects.remove(copy)


def import_shoe(path, keep_side):
    """The source as one mesh in Blender's axes, transforms applied, only the shoe on `keep_side`
    of the centre line kept (a clothing source holds the pair)."""
    before = set(bpy.context.scene.objects)
    if path.lower().endswith(".obj"):
        bpy.ops.wm.obj_import(filepath=path)
    else:
        bpy.ops.import_scene.gltf(filepath=path)
    added = [o for o in bpy.context.scene.objects if o not in before]
    meshes = [o for o in added if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    shoe = bpy.context.view_layer.objects.active
    shoe.data.transform(shoe.matrix_world)
    shoe.parent = None
    shoe.matrix_world = Matrix.Identity(4)
    for obj in added:
        if obj is not shoe and obj.name in bpy.data.objects:
            bpy.data.objects.remove(obj)
    if keep_side != "both":
        sign = -1 if keep_side == "-x" else 1
        bm = bmesh.new()
        bm.from_mesh(shoe.data)
        centre = sum((v.co.x for v in bm.verts), 0.0) / len(bm.verts)
        drop = [f for f in bm.faces if sign * (f.calc_center_median().x - centre) < 0]
        bmesh.ops.delete(bm, geom=drop, context="FACES")
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bm.to_mesh(shoe.data)
        bm.free()
    shoe.data.materials.clear()
    return shoe


def to_shoe_frame(shoe, length, toe):
    """Moves the shoe into the shoe frame and scales it to `length` from heel to toe: `toe` is the
    source axis the toes point along ("-y" for MakeHuman, whose figure faces -y in Blender), z is
    up; the sole's lowest point lands at -ANKLE_UP and the heel's back at +ANKLE_ALONG."""
    axis = {"x": 0, "y": 1}[toe[-1]]
    toe_sign = -1 if toe.startswith("-") else 1
    points = [v.co.copy() for v in shoe.data.vertices]
    lo = Vector([min(p[i] for p in points) for i in range(3)])
    hi = Vector([max(p[i] for p in points) for i in range(3)])
    size = hi - lo
    k = length / size[axis]
    heel_end = hi[axis] if toe_sign < 0 else lo[axis]
    along = Vector((0, 0, 0))
    along[axis] = -toe_sign
    up = Vector((0, 0, 1))
    across = up.cross(along)
    origin = (lo + hi) / 2
    origin[axis] = heel_end
    origin.z = lo.z
    rows = Matrix((across, up, along)).to_4x4()
    shoe.data.transform(Matrix.Translation(Vector((0, -ANKLE_UP, ANKLE_ALONG))) @ Matrix.Scale(k, 4) @ rows @ Matrix.Translation(-origin))
    return k


def bounds_centre(obj):
    points = [v.co for v in obj.data.vertices]
    lo = Vector([min(p[i] for p in points) for i in range(3)])
    hi = Vector([max(p[i] for p in points) for i in range(3)])
    return (lo + hi) / 2, lo, hi


def main(args):
    out, shoe_path = args[:2]
    length = float(option(args, "--shoe-length", 0.285))
    keep_side = option(args, "--keep", "both")
    toe = option(args, "--toe", "-y")
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    thigh = tube("Thigh", thigh_radius, thigh_folds, open_end=False)
    shin = tube("Shin", shin_radius, shin_folds, open_end=True)
    export(thigh, os.path.join(out, "thigh.glb"), stretch_z=False)
    export(shin, os.path.join(out, "shin.glb"), stretch_z=False)
    seat = pelvis("Pelvis")
    export(seat, os.path.join(out, "pelvis.glb"), stretch_z=True)

    shoe = import_shoe(shoe_path, keep_side)
    scale = to_shoe_frame(shoe, length, toe)
    left = shoe.copy()
    left.data = shoe.data.copy()
    bpy.context.collection.objects.link(left)
    left.data.transform(Matrix.Scale(-1, 4, (1, 0, 0)))
    left.data.flip_normals()
    export(shoe, os.path.join(out, "shoe_R.glb"), stretch_z=True)
    export(left, os.path.join(out, "shoe_L.glb"), stretch_z=True)
    centre, lo, hi = bounds_centre(shoe)
    tris = sum(len(p.vertices) - 2 for p in shoe.data.polygons)
    report = {
        "shoeCentre": [round(c, 4) for c in centre],
        "shoeBounds": [[round(c, 4) for c in lo], [round(c, 4) for c in hi]],
        "shoeScale": round(scale, 5),
        "shoeTriangles": tris,
        "thighTriangles": sum(len(p.vertices) - 2 for p in thigh.data.polygons),
        "shinTriangles": sum(len(p.vertices) - 2 for p in shin.data.polygons),
        "pelvisSize": list(PELVIS),
        "pelvisTriangles": sum(len(p.vertices) - 2 for p in seat.data.polygons),
    }
    json.dump(report, open(os.path.join(out, "legs.json"), "w"), indent=1)
    print(json.dumps(report, indent=1))

    # Check render: a seated leg's pieces laid out at their real sizes, in the shoe frame's axes.
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    scene.render.resolution_x, scene.render.resolution_y = 1200, 700
    for obj, colour in ((thigh, (0.13, 0.14, 0.16, 1)), (shin, (0.13, 0.14, 0.16, 1)), (shoe, (0.55, 0.5, 0.45, 1)), (left, (0.55, 0.5, 0.45, 1))):
        obj.color = colour
    thigh.data.transform(Matrix.Translation((-0.35, 0.4, 0)) @ Matrix.Diagonal((1, 1, 0.45, 1)))
    shin.data.transform(Matrix.Translation((-0.05, 0.4, 0)) @ Matrix.Diagonal((1, 1, 0.44, 1)))
    left.data.transform(Matrix.Translation((0.3, 0, 0)))
    camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    scene.collection.objects.link(camera)
    scene.camera = camera
    for name, eye, target in (("side", (0.9, 0.35, 0.6), (0.0, 0.2, 0.0)), ("front", (0.0, 0.35, -1.2), (0.0, 0.2, 0.0))):
        eye, target = Vector(eye), Vector(target)
        forward = (target - eye).normalized()
        right = forward.cross(Vector((0, 1, 0))).normalized()
        upv = right.cross(forward)
        camera.matrix_world = Matrix(((right.x, upv.x, -forward.x, eye.x), (right.y, upv.y, -forward.y, eye.y), (right.z, upv.z, -forward.z, eye.z), (0, 0, 0, 1)))
        camera.data.lens = 35
        scene.render.filepath = os.path.join(out, f"check_legs_{name}.png")
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1 :])
