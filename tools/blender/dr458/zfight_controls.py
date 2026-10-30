"""Control scene for zfight_scan.py: three pairs of 10 x 10 cm quads whose answers are known.

blender -b --factory-startup -P tools/blender/dr458/zfight_controls.py -- <out.blend>

- Abut_A / Abut_B: coplanar, sharing an edge, no overlap: nothing can flicker, expected 0 cm2.
- Lap_A / Lap_B: same facing, 0.5 mm apart, overlapping 5 x 10 cm: expected about 50 cm2 each way.
- Back_A / Back_B: the same square back to back (opposite normals): never fights single-sided, 0.
Run zfight_scan.py on the saved file with and without --any-direction to see both tests.
"""
import sys

import bpy

out = sys.argv[sys.argv.index("--") + 1]
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
col = bpy.data.collections.new("Controls")
bpy.context.scene.collection.children.link(col)


def quad(name, x0, y0, z, flip=False, size=0.1):
    v = [(x0, y0, z), (x0 + size, y0, z), (x0 + size, y0 + size, z), (x0, y0 + size, z)]
    f = [(0, 1, 2, 3)] if not flip else [(3, 2, 1, 0)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    o = bpy.data.objects.new(name, me)
    col.objects.link(o)


quad("Abut_A", 0.0, 0.0, 0.0)
quad("Abut_B", 0.1, 0.0, 0.0)
quad("Lap_A", 0.0, 1.0, 0.0)
quad("Lap_B", 0.05, 1.0, 0.0005)
quad("Back_A", 0.0, 2.0, 0.0)
quad("Back_B", 0.0, 2.0, 0.0, flip=True)
bpy.ops.wm.save_as_mainfile(filepath=out)
print("CONTROLS saved", out)
