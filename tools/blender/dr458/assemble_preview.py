"""Assemble the whole car for checks and renders: a master plus the cockpit modeller's parts and the
lead's cockpit pieces, appended (their own objects only; a file's linked master is not taken).

blender -b <master.blend> --factory-startup -P tools/blender/dr458/assemble_preview.py -- <out.blend> [<parts.blend> ...]

Default parts (DR458_WORK set to the work folder): cockpit/cockpit_hardware.blend and cockpit/lead_pieces.blend. Objects a parts file
marks `shown = False` (alternatives such as a deployed net) stay hidden. Each file's objects go in
their own collection, Parts_<file>. The output is for checking only, never a master.
"""
import os
import sys
from pathlib import Path

import bpy

args = sys.argv[sys.argv.index("--") + 1:]
out = args[0]
WORK = Path(os.environ["DR458_WORK"])
files = args[1:] or [str(WORK / "cockpit" / "cockpit_hardware.blend"), str(WORK / "cockpit" / "lead_pieces.blend")]
for f in files:
    col = bpy.data.collections.new("Parts_" + Path(f).stem)
    bpy.context.scene.collection.children.link(col)
    with bpy.data.libraries.load(f, link=False) as (src, dst):
        dst.objects = list(src.objects)
    n = 0
    for o in dst.objects:
        if o is None:
            continue
        if o.type == "MESH" and o.name.startswith("Cube") and len(o.data.polygons) == 6:
            print("ASSEMBLE skipped a default cube left in", Path(f).name, o.name)
            continue
        col.objects.link(o)  # every object, empties too: a child whose parent is not in the scene lands at the origin
        if o.type == "MESH":
            o.hide_render = o.hide_render or o.get("shown") is False
            n += 1
    print("ASSEMBLE", Path(f).name, n, "mesh objects")
bpy.context.view_layer.update()
linked = [o.name for o in bpy.data.objects if o.library is not None]
print("ASSEMBLE library-linked objects:", len(linked), linked[:8])
for name in ("SteeringWheel", "SteeringWheel_Rim", "Binnacle_Screen"):
    o = bpy.data.objects.get(name)
    if o:
        print("ASSEMBLE", name, "at", tuple(round(x, 3) for x in o.matrix_world.translation))
bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
print("ASSEMBLE saved", out)
