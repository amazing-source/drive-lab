"""
Lists a model's mesh objects with their triangle counts, world bounds and materials, run
headless by Blender, to see how a downloaded model is split before preparing it.

    blender --background --factory-startup --python tools/blender/inspect_model.py -- <model>
"""

import sys
from pathlib import Path

import bpy
from mathutils import Vector

path = Path(sys.argv[sys.argv.index("--") + 1])
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
if path.suffix.lower() in (".glb", ".gltf"):
    bpy.ops.import_scene.gltf(filepath=str(path))
else:
    bpy.ops.import_scene.fbx(filepath=str(path))

meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
total = 0
low = Vector((1e9, 1e9, 1e9))
high = Vector((-1e9, -1e9, -1e9))
rows = []
for obj in meshes:
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    a = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    b = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    low = Vector(map(min, low, a))
    high = Vector(map(max, high, b))
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    total += tris
    materials = ",".join(slot.material.name for slot in obj.material_slots if slot.material)[:70]
    rows.append((tris, obj.name[:34], a, b, materials))
print(f"MESHES {len(meshes)} TRIS {total} BOUNDS {tuple(round(v, 2) for v in low)} -> {tuple(round(v, 2) for v in high)}")
for tris, name, a, b, materials in sorted(rows, key=lambda row: -row[0])[:40]:
    size = b - a
    centre = (a + b) / 2
    print(f"  {tris:>7} {name:<34} c=({centre.x:6.2f},{centre.y:6.2f},{centre.z:6.2f}) s=({size.x:5.2f},{size.y:5.2f},{size.z:5.2f}) [{materials}]")
