"""Retire master objects into a hidden Replaced_<Area> collection (kept in the file, never exported).

blender -b <master.blend> --factory-startup --python-exit-code 1 -P tools/blender/dr458/retire_objects.py -- <out.blend> <collection> <list.json | name ...>

A list.json is read for its "retire" list (the cockpit modeller's cockpit/fit/dash_report.json). Each
object leaves every other collection; the collection is hidden for render and viewport, as the other
Replaced_* are. Fails on a name not in the file. Verify: every named object sits only in the
collection, and the triangles left outside Replaced_* drop by exactly the retired objects' own.
"""
import json
import sys

import bpy

args = sys.argv[sys.argv.index("--") + 1:]
out, cname, rest = args[0], args[1], args[2:]
names = json.load(open(rest[0]))["retire"] if len(rest) == 1 and rest[0].endswith(".json") else rest
if not cname.startswith("Replaced_"):
    raise SystemExit(f"RETIRE the collection must be a Replaced_* one, got {cname}")
missing = [n for n in names if n not in bpy.data.objects]
if missing:
    raise SystemExit(f"RETIRE objects not found: {missing}")


def tris(o):
    return sum(len(f.vertices) - 2 for f in o.data.polygons) if o.type == "MESH" else 0


def live_tris():
    return sum(tris(o) for o in bpy.data.objects if o.type == "MESH" and o.users_collection
               and not any(c.name.startswith("Replaced") for c in o.users_collection))


before = live_tris()
col = bpy.data.collections.get(cname) or bpy.data.collections.new(cname)
if col.name not in bpy.context.scene.collection.children:
    bpy.context.scene.collection.children.link(col)
col.hide_render = col.hide_viewport = True
own = 0
for n in names:
    o = bpy.data.objects[n]
    if any(c.name.startswith("Replaced") for c in o.users_collection):
        continue
    own += tris(o)
    for c in list(o.users_collection):
        c.objects.unlink(o)
    col.objects.link(o)
after = live_tris()
problems = [n for n in names if [c.name for c in bpy.data.objects[n].users_collection] != [cname]]
if before - after != own:
    problems.append(f"live triangles dropped {before - after}, the retired objects hold {own}")
print(f"RETIRE {len(names)} objects into {cname}: live triangles {before} -> {after} (-{own})")
print("RETIRE", "PASS" if not problems else "FAIL", *problems, sep="\n  ")
if problems:
    sys.exit(1)
bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
print("RETIRE saved", out)
