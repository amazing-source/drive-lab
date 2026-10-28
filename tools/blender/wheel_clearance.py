"""
Measures how far each tyre cuts into the bodywork on an exported car, run headless by Blender:

    blender -b --factory-startup -P tools/blender/wheel_clearance.py -- <car.glb>

For each Wheel_* mesh it takes the tyre as the wheel's bounding cylinder (axis across the car)
and reports every body vertex inside it, by mesh, deepest first: the depth is how much higher
the body must sit, relative to the wheels, for the tyre to clear it. Units are the glb's
(studs). Calipers and the wheels themselves are skipped.
"""
import sys

import bpy
from mathutils import Vector


def main(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    bpy.context.view_layer.update()
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    wheels = [o for o in meshes if o.name.startswith("Wheel_")]
    body = [o for o in meshes if not o.name.startswith(("Wheel_", "Caliper_"))]
    # Blender imports glTF Y-up as Z-up: the axle runs along X, the wheel's side plane is Y-Z.
    for wheel in sorted(wheels, key=lambda o: o.name):
        points = [wheel.matrix_world @ v.co for v in wheel.data.vertices]
        lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
        hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
        centre = (lo + hi) / 2
        radius = max(hi.y - lo.y, hi.z - lo.z) / 2
        worst = {}
        for part in body:
            for v in part.data.vertices:
                p = part.matrix_world @ v.co
                if not (lo.x <= p.x <= hi.x):
                    continue
                dy, dz = p.y - centre.y, p.z - centre.z
                inside = radius - (dy * dy + dz * dz) ** 0.5
                # Only the upper half: the arch above the tyre.
                if inside > 0 and dz > 0:
                    worst[part.name] = max(worst.get(part.name, 0), inside * dz / max(1e-6, (dy * dy + dz * dz) ** 0.5))
        top = sorted(worst.items(), key=lambda kv: -kv[1])[:5]
        print(f"{wheel.name}: radius {radius:.3f}, centre height {centre.z:.3f}")
        for name, depth in top:
            print(f"   {name:40s} cuts {depth:.3f} studs into the tyre (vertically)")


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1])
