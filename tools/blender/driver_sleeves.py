"""
Builds the driver's two sleeve meshes, upper arm and forearm, for the arms drawn over a seated
R6 character: an oval tube with soft fabric folds, closed at the elbow and shoulder, and on the
forearm a cuff wide enough to take the hand's wrist (tools/blender/hand_grip.py).

    blender -b --factory-startup -P tools/blender/driver_sleeves.py -- <out dir>

Sizes are real (the hands are real-sized against the steering wheel); the wrist of the CC0 hand
used is 6.4 x 4.8 cm, so the cuff is 8.0 x 6.4 cm outside. Exported in Roblox studs at the
world scale (1 m = 1.5 / 0.28 studs), one stud long: the game stretches each sleeve along its
length to the bone it covers and keeps the cross-section. Axes as Roblox will see them: length
along z, from the joint nearer the body at +z to the far one at -z; the oval's long axis on x
(the hand's width at the cuff), the short one on y (palm to back of the hand).
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix

STUDS_PER_METRE = 1.5 / 0.28
RINGS = 28
SEGMENTS = 22


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def sleeve(name, radius_at, folds, cuff):
    """A closed oval tube, t = 0 at the body end (+z) to 1 at the far end (-z), length 1."""
    mesh = bmesh.new()
    rings = []
    for i in range(RINGS + 1):
        t = i / RINGS
        rx, ry = radius_at(t)
        # Rounded ends: the radius closes over the last few percent of the length.
        end = min(t, 1 - t)
        dome = math.sqrt(max(0.0, 1 - (max(0.0, 0.05 - end) / 0.05) ** 2)) if end < 0.05 else 1.0
        if cuff and t > 0.5:
            dome = 1.0 if t < 0.999 else 0.97
        ring = []
        for j in range(SEGMENTS):
            theta = 2 * math.pi * j / SEGMENTS
            fold = folds(t, theta)
            x = rx * dome * (1 + fold) * math.cos(theta)
            y = ry * dome * (1 + fold) * math.sin(theta)
            ring.append(mesh.verts.new((x, y, 0.5 - t)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for j in range(SEGMENTS):
            k = (j + 1) % SEGMENTS
            mesh.faces.new((a[j], a[k], b[k], b[j]))
    mesh.faces.new(list(reversed(rings[0])))
    mesh.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(mesh, faces=mesh.faces)
    data = bpy.data.meshes.new(name)
    mesh.to_mesh(data)
    for polygon in data.polygons:
        polygon.use_smooth = True
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return obj


def forearm_radius(t):
    # 9.6 x 8.4 cm at the elbow, narrowing to the wrist, then the cuff band.
    rx = lerp(0.048, 0.036, smoothstep(0.0, 0.85, t))
    ry = lerp(0.042, 0.029, smoothstep(0.0, 0.85, t))
    band = smoothstep(0.86, 0.9, t)
    groove = 0.004 * math.exp(-(((t - 0.875) / 0.012) ** 2))
    return rx + 0.004 * band - groove, ry + 0.003 * band - groove


def upper_radius(t):
    # A little fuller at the shoulder, 11 x 10 cm.
    rx = lerp(0.056, 0.05, smoothstep(0.1, 1.0, t))
    ry = lerp(0.052, 0.046, smoothstep(0.1, 1.0, t))
    return rx, ry


def forearm_folds(t, theta):
    # Fabric bunches toward the elbow and above the cuff; none on the cuff band itself.
    weight = 0.6 * math.exp(-((t - 0.12) / 0.12) ** 2) + 0.45 * math.exp(-((t - 0.72) / 0.1) ** 2)
    wave = 0.6 * math.sin(2 * math.pi * 7 * t + 0.8 * math.sin(theta)) + 0.4 * math.sin(2 * math.pi * 11 * t + 1.4 * math.cos(2 * theta))
    return 0.07 * weight * wave * (1 - smoothstep(0.84, 0.86, t))


def upper_folds(t, theta):
    weight = 0.5 * math.exp(-((t - 0.85) / 0.12) ** 2) + 0.2
    wave = 0.6 * math.sin(2 * math.pi * 5 * t + 0.9 * math.cos(theta)) + 0.4 * math.sin(2 * math.pi * 9 * t + 1.1 * math.sin(2 * theta))
    return 0.05 * weight * wave


def export(obj, path):
    # Roblox (x, y, z) is Blender (-x, z, y) after the glTF importer's half turn.
    swap = Matrix(((-1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
    scale = Matrix.Diagonal((STUDS_PER_METRE, STUDS_PER_METRE, 1, 1))
    obj.data.transform(swap @ scale)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_materials="NONE")


def main(out):
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    forearm = sleeve("Forearm", forearm_radius, forearm_folds, cuff=True)
    upper = sleeve("UpperArm", upper_radius, upper_folds, cuff=False)
    for obj in (forearm, upper):
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        print(obj.name, "triangles", tris)

    # Check render: both sleeves at a driver's proportions, before the export scale.
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.render.resolution_x, scene.render.resolution_y = 1000, 600
    preview = []
    for obj, length, offset in ((upper, 0.26, (-0.2, 0, 0)), (forearm, 0.24, (0.15, 0, 0))):
        copy = obj.copy()
        copy.data = obj.data.copy()
        copy.data.transform(Matrix.Translation(offset) @ Matrix.Diagonal((1, 1, length, 1)))
        bpy.context.collection.objects.link(copy)
        preview.append(copy)
    camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.location = (0, -0.9, 0.25)
    camera.rotation_euler = (math.radians(75), 0, 0)
    scene.render.filepath = os.path.join(out, "check_sleeves.png")
    bpy.ops.render.render(write_still=True)
    for copy in preview:
        bpy.data.objects.remove(copy)

    export(forearm, os.path.join(out, "sleeve_forearm.glb"))
    export(upper, os.path.join(out, "sleeve_upper.glb"))


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1])
