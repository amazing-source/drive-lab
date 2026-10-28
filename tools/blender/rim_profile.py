"""
Prints slices of a car's steering wheel around 3 o'clock, in the wheel's own frame and metres,
to find the rim tube's centre and thickness and where the spoke joins it.

    blender -b --factory-startup -P tools/blender/rim_profile.py -- <wheel.glb> <points.json>
"""
import bpy, sys, json
from mathutils import Vector
args = sys.argv[sys.argv.index("--") + 1:]
glb, points = args[0], json.load(open(args[1]))
SPM = 3.5714285714  # export studs per metre
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
ob = next(o for o in bpy.context.scene.objects if o.type == "MESH" and "Steering" in o.name)
def blender(v):  # Roblox (x, y, z) -> Blender (-x, z, y)
    return Vector((-v[0], v[2], v[1]))
c = blender(points["wheel_centre"])
zw = blender(points["wheel_axis"]).normalized()
xw = Vector((-1, 0, 0))
xw = (xw - zw * xw.dot(zw)).normalized()
yw = zw.cross(xw)
pts = []
for v in ob.data.vertices:
    p = ob.matrix_world @ v.co - c
    pts.append((p.dot(xw) / SPM, p.dot(yw) / SPM, p.dot(zw) / SPM))
print("extent x", min(p[0] for p in pts), max(p[0] for p in pts), "y", min(p[1] for p in pts), max(p[1] for p in pts), "z", min(p[2] for p in pts), max(p[2] for p in pts))
for y0 in [-0.08, -0.06, -0.04, -0.02, 0.0, 0.02, 0.04, 0.06, 0.08, 0.10]:
    s = [p for p in pts if abs(p[1] - y0) < 0.006 and p[0] > 0.05]
    if s:
        print(f"y {y0:+.2f} n {len(s):4d} x {min(p[0] for p in s):.4f}..{max(p[0] for p in s):.4f} z {min(p[2] for p in s):+.4f}..{max(p[2] for p in s):+.4f}")
