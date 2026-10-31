"""Prepare the DR458 for Roblox from the assembled car: pieces, names, a glb and its checks (dry run).

blender -b <assembled car.blend> --factory-startup -P tools/blender/dr458/export_dr458.py -- <manifest.json> <out dir> [--limit 10000]

Nothing is uploaded and the .blend is never saved. Steps:
1. Every visible mesh outside Replaced_* has its modifiers applied (the auto-smooth node sets the
   sharp edges the glTF splits at).
2. Each manifest part gathers its objects (its "objects" list, else the object of its own name),
   hidden alternatives included (the deployed window net); pivots with no mesh are skipped. A part with one material keeps its name; a part with several
   splits into <Name>_<Material>. Objects in no part merge per area (Body, Cabin, Engine, Evo,
   Lights, Glass, Wheels, Cockpit) and material into <Area>_<Material>_<nn>.
3. A piece over --limit triangles (the plan's 10,000 per MeshPart; Roblox simplifies above 20,000)
   is halved along its longest axis by whole faces until it fits.
4. Metres become studs (1 stud = 0.28 m) about the manifest's origin, the rear-axle midpoint on the
   ground. Pieces are baked with their origin at their bounds centre and no rotation, except a part
   whose manifest entry has "lit_face": it is rotated so Roblox's Back face (+Z, Blender's +Y here)
   is its lit face's normal toward the driver, with its up as close to the car's up as the lean allows.
5. car.glb: normals and tangents, materials without images, extras Part / Group on every node. A
   piece with no UV layer, or one whose UVs have no area, gets planar UVs in metres, in this export
   only, so its tangents exist.
   export.json: each piece's name, part, group, material, triangles, origin and size in Roblox axes
   (studs; X right, Y up, -Z forward: to_roblox(v) = (-x, z, y), the importer's half turn).
6. The glb is read back: node names, triangles per mesh, a TANGENT on every primitive, every
   manifest mesh part present. Exit 1 when any check fails.
"""
import json
import re
import struct
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:]
manifest_path, out = args[0], Path(args[1])
LIMIT = int(args[args.index("--limit") + 1]) if "--limit" in args else 10000
STUDS = 1 / 0.28
out.mkdir(parents=True, exist_ok=True)
AREA = {"Body": "Body", "Doors": "Body", "Cabin": "Cabin", "Engine": "Engine", "Evo": "Evo", "Glass": "Glass",
        "Lights": "Lights", "Wheels": "Wheels", "Unsorted": "Body"}
PREFIXES = ("fer_f142_10_cockpit_s_", "fer_f142_10_s_lod0_", "fer_f142_10_")
problems = []


def area_of(o):
    for c in o.users_collection:
        if c.name in AREA:
            return AREA[c.name]
        if c.name.startswith("Parts_"):
            return "Cockpit"
    return "Body"


def mat_label(name):
    for p in PREFIXES:
        name = name.replace(p, "")
    parts = [w for w in re.split(r"[^A-Za-z0-9]+", name) if w]
    return "".join(w[:1].upper() + w[1:] for w in parts) or "None"


def tri_count(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


def select_only(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


meta = json.load(open(manifest_path))
wanted = {n for p in meta["parts"] if p.get("mesh") is not False for n in (p.get("objects") or [p["name"]])}
live = [o for o in bpy.context.scene.objects if o.type == "MESH" and (not o.hide_render or o.name in wanted) and len(o.data.polygons)
        and not any(c.name.startswith("Replaced") for c in o.users_collection)
        and not o.name.endswith("__back") and not o.name.startswith("CONTROL")]
select_only(live)
bpy.ops.object.convert(target="MESH")
live = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.name in {x.name for x in live}]
by_name = {o.name: o for o in live}

owner, parts = {}, []
for p in meta["parts"]:
    if p.get("mesh") is False:
        continue
    names = p.get("objects") or [p["name"]]
    objs = [by_name[n] for n in names if n in by_name]
    missing = [n for n in names if n not in by_name]
    if missing:
        problems.append(f"{p['name']}: objects not in the car: {missing}")
    for o in objs:
        if o.name in owner:
            problems.append(f"{o.name} belongs to {owner[o.name]} and {p['name']}")
        owner[o.name] = p["name"]
    if objs:
        parts.append((p, objs))

bpy.ops.object.select_all(action="DESELECT")
for o in live:
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
bpy.context.view_layer.update()


def lit_frame(o):
    """Rotation whose +Y (Roblox +Z, the Back face) is the lit face's normal toward the driver (+Y here)."""
    n = Vector()
    for f in o.data.polygons:
        if f.normal.y > 0:
            n += f.normal * f.area
    y = n.normalized()
    z = (Vector((0, 0, 1)) - y * y.z).normalized()
    return Matrix((y.cross(z), y, z)).transposed()


def bake(o, keep_rotation):
    o.data.transform(o.matrix_world)
    o.data.transform(Matrix.Scale(STUDS, 4))
    o.matrix_world = Matrix.Identity(4)
    R = lit_frame(o) if keep_rotation else Matrix.Identity(3)
    pts = [R.transposed() @ v.co for v in o.data.vertices]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    c = R @ ((lo + hi) / 2)
    o.data.transform(R.transposed().to_4x4() @ Matrix.Translation(-c))
    o.matrix_world = Matrix.Translation(c) @ R.to_4x4()


def uv_area(o):
    uv = o.data.uv_layers.active.data
    total = 0.0
    for f in o.data.polygons:
        a, b, c = (uv[f.loop_start + i].uv for i in (0, 1, 2)) if f.loop_total >= 3 else (Vector((0, 0)),) * 3
        total += abs((b - a).cross(c - a))
    return total


def fallback_uv(o):
    """Planar UVs in metres by each face's dominant axis, so glTF can write tangents (export copy only)."""
    o.data.uv_layers.new(name="UVMap")
    bm = bmesh.new()
    bm.from_mesh(o.data)
    uv = bm.loops.layers.uv.active
    for f in bm.faces:
        ax = max(range(3), key=lambda i: abs(f.normal[i]))
        a, b = [i for i in range(3) if i != ax]
        for lp in f.loops:
            lp[uv].uv = (lp.vert.co[a] / STUDS, lp.vert.co[b] / STUDS)
    bm.to_mesh(o.data)
    bm.free()


def split_material(o):
    """One object per material: slots holding the same material (several sources mapped to one set) merge first."""
    first = {}
    remap = [first.setdefault(s.material.name if s.material else None, i) for i, s in enumerate(o.material_slots)]
    idx = [0] * len(o.data.polygons)
    o.data.polygons.foreach_get("material_index", idx)
    idx = [remap[i] if i < len(remap) else i for i in idx]
    o.data.polygons.foreach_set("material_index", idx)
    o.data.update()
    if len(set(idx)) <= 1:
        return [o]
    select_only([o])
    bpy.ops.mesh.separate(type="MATERIAL")
    return list(bpy.context.selected_objects)


def halve(o):
    pts = [o.matrix_world @ v.co for v in o.data.vertices]
    size = [max(p[i] for p in pts) - min(p[i] for p in pts) for i in range(3)]
    axis = max(range(3), key=lambda i: size[i])
    mids = sorted((o.matrix_world @ f.center)[axis] for f in o.data.polygons)
    cut = mids[len(mids) // 2]
    select_only([o])
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(o.data)
    mw = o.matrix_world
    for f in bm.faces:
        f.select_set((mw @ f.calc_center_median())[axis] >= cut)
    bmesh.update_edit_mesh(o.data)
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    return list(bpy.context.selected_objects)


def fit(o):
    queue, done = [o], []
    while queue:
        cur = queue.pop()
        n = tri_count(cur)
        if n > LIMIT:
            queue.extend(halve(cur))
        elif n:
            done.append(cur)
    return done


def material_of(o):
    m = o.material_slots[o.data.polygons[0].material_index].material if o.material_slots else None
    return m.name if m else "none"


pieces = []


def emit(objs, base, numbered, part=None, group=None, keep_rotation=False):
    select_only(objs)
    if len(objs) > 1:
        bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    singles = split_material(joined)
    multi = len(singles) > 1
    for s in singles:
        mat = material_of(s)
        name = f"{base}_{mat_label(mat)}" if multi or numbered else base
        fitted = fit(s)
        for k, f in enumerate(sorted(fitted, key=lambda x: -tri_count(x)), 1):
            f.name = f"{name}_{k:02d}" if (numbered or len(fitted) > 1) else name
            f.data.name = f.name
            pieces.append({"obj": f, "part": part, "group": group, "material": mat, "keep_rotation": keep_rotation})


rest = {}
for o in live:
    if o.name not in owner:
        rest.setdefault(area_of(o), []).append(o.name)
for p, objs in parts:
    emit(objs, p["name"], False, p["name"], p.get("group"), bool(p.get("lit_face")))
for area, names_ in rest.items():
    emit([bpy.data.objects[n] for n in names_], area, True, None, None, False)

names = [x["obj"].name for x in pieces]
dupes = sorted({n for n in names if names.count(n) > 1 or "." in n})
if dupes:
    problems.append(f"duplicate or suffixed names: {dupes[:10]}")
no_uv = []
for x in pieces:
    o = x["obj"]
    bake(o, x["keep_rotation"])
    o["Part"] = x["part"] or o.name
    o["Group"] = x["group"] or "Chassis"
    ngons = [f.index for f in o.data.polygons if f.loop_total > 4]
    if ngons:  # Blender computes tangents for triangles and quads only: an n-gon cap left the piece without any
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.faces.ensure_lookup_table()
        bmesh.ops.triangulate(bm, faces=[bm.faces[i] for i in ngons])
        bm.to_mesh(o.data)
        bm.free()
    if not o.data.uv_layers or uv_area(o) < 1e-10:
        no_uv.append(o.name)
        while o.data.uv_layers:
            o.data.uv_layers.remove(o.data.uv_layers[0])
        fallback_uv(o)
bpy.context.view_layer.update()


def to_roblox(v):
    return [round(-v.x, 4), round(v.z, 4), round(v.y, 4)]


rows = []
for x in pieces:
    o = x["obj"]
    pts = [o.matrix_world @ v.co for v in o.data.vertices]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    row = {"name": o.name, "part": o["Part"], "group": o["Group"], "material": x["material"], "triangles": tri_count(o),
           "origin": to_roblox(o.matrix_world.translation), "size": [round(hi.x - lo.x, 4), round(hi.z - lo.z, 4), round(hi.y - lo.y, 4)],
           "uv_maps": len(o.data.uv_layers)}
    if x["keep_rotation"]:
        q = o.matrix_world.to_quaternion()
        row["rotation_blender_wxyz"] = [round(q.w, 5), round(q.x, 5), round(q.y, 5), round(q.z, 5)]
        row["lit_face_normal_roblox"] = to_roblox(o.matrix_world.to_3x3() @ Vector((0, 1, 0)))
    rows.append(row)
select_only([x["obj"] for x in pieces])
bpy.ops.export_scene.gltf(filepath=str(out / "car.glb"), export_format="GLB", use_selection=True, export_yup=True,
                          export_apply=True, export_normals=True, export_tangents=True, export_extras=True,
                          export_materials="EXPORT", export_image_format="NONE")

raw = (out / "car.glb").read_bytes()
jlen = struct.unpack_from("<I", raw, 12)[0]
gl = json.loads(raw[20:20 + jlen])
glb_tris, no_tangent = {}, []
for node in gl["nodes"]:
    if "mesh" not in node:
        continue
    mesh = gl["meshes"][node["mesh"]]
    t = 0
    for prim in mesh["primitives"]:
        t += gl["accessors"][prim["indices"]]["count"] // 3
        if "TANGENT" not in prim["attributes"]:
            no_tangent.append(node["name"])
    glb_tris[node["name"]] = t
over = {k: v for k, v in glb_tris.items() if v > LIMIT}
mesh_parts = [p["name"] for p in meta["parts"] if p.get("mesh") is not False]
absent = [n for n in mesh_parts if not any(r["part"] == n for r in rows)]
if over:
    problems.append(f"pieces over {LIMIT} triangles in the glb: {over}")
if no_tangent:
    problems.append(f"primitives without tangents: {sorted(set(no_tangent))[:12]}")
if absent:
    problems.append(f"manifest parts with no piece: {absent}")
if set(glb_tris) != set(names):
    problems.append(f"glb nodes differ from the pieces: {sorted(set(glb_tris) ^ set(names))[:10]}")
by_area = {}
for r in rows:
    k = r["part"] if r["part"] != r["name"] and not re.match(r"^(Body|Cabin|Engine|Evo|Lights|Glass|Wheels|Cockpit)_", r["name"]) else r["name"].split("_")[0]
    by_area[k] = by_area.get(k, 0) + r["triangles"]
report = {"limit": LIMIT, "studs_per_metre": STUDS, "frame": "manifest frame scaled to studs, Roblox axes (X right, Y up, -Z forward)",
          "pieces": len(rows), "triangles": sum(r["triangles"] for r in rows), "largest": max(r["triangles"] for r in rows),
          "glb_bytes": len(raw), "no_uv": no_uv, "problems": problems, "parts": rows}
(out / "export.json").write_text(json.dumps(report, indent=1))
print(f"EXPORT {len(rows)} pieces, {report['triangles']} triangles, largest {report['largest']}, glb {len(raw) / 1e6:.1f} MB, "
      f"{sum(1 for r in rows if r['uv_maps'] > 1)} with 2+ UV maps, {len(no_uv)} without UVs (fallback UVs given)")
for r in sorted(rows, key=lambda r: -r["triangles"])[:10]:
    print(f"EXPORT   {r['triangles']:6d}  {r['name']}  ({r['material']})")
for r in rows:
    if "lit_face_normal_roblox" in r:
        print(f"EXPORT lit {r['name']}: +Z -> Roblox {r['lit_face_normal_roblox']}")
print("EXPORT", "PASS" if not problems else "FAIL", *problems, sep="\n  ")
sys.exit(1 if problems else 0)
