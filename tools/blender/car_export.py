"""Prepare a car for Roblox from its assembled blend: pieces, names, a glb and its checks.

blender -b <assembled car.blend> --factory-startup --python-exit-code 1 -P car_export.py --
        <car settings.json> <manifest.json> <out dir> [--limit 10000] [--break <name>]

Nothing is uploaded and the .blend is never saved. The car's settings file (tools/cars/<car>.json,
section "export") says what differs per car: which objects are left out, the merge areas, the
material-name prefixes dropped from piece names, and parts the game needs that its manifest does not
list yet ("extraParts"). Steps:
1. Every mesh that is shown has its modifiers applied (the auto-smooth node sets the sharp edges the
   glTF splits at). Left out: objects hidden for render (unless a part names them), objects whose
   name or node chain matches the settings' `hide` rules (never included, even when named), and
   the settings' excluded collections, prefixes and suffixes.
2. Each manifest part (and each extra part) gathers its objects (its "objects" list, else the object
   of its own name); pivots with no mesh are skipped. A part with one material keeps its name; a part
   with several splits into <Name>_<Material>. Objects in no part merge per area and material into
   <Area>_<Material>_<nn>.
3. A piece over --limit triangles (Roblox simplifies above 20,000) is halved along its longest axis
   by whole faces until it fits.
4. Metres become studs (1 stud = 0.28 m) about the manifest's origin. Pieces are baked with their
   origin at their bounds centre and no rotation, except a part with "lit_face" (manifest or extra
   part): it is rotated so Roblox's Back face (+Z, Blender's +Y here) is its lit face's normal toward
   the driver, with its up as close to the car's up as the lean allows.
5. car.glb: normals and tangents, materials without images, extras Part / Group on every node. A
   piece with no UV layer, or one whose UVs have no area, gets planar UVs in metres, in this export
   only, so its tangents exist. export.json: each piece's name, part, group, material, triangles,
   origin and size in Roblox axes (studs; X right, Y up, -Z forward: to_roblox(v) = (-x, z, y)).
6. The glb is read back: node names, triangles per mesh, a TANGENT on every primitive, every part
   present. Exit 1 when any check fails.

--break drops one named object before the export, to see the "part with no piece" check fail.
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
settings_path, manifest_path, out = Path(args[0]), args[1], Path(args[2])
S = json.loads(settings_path.read_text())["export"]
LIMIT = int(args[args.index("--limit") + 1]) if "--limit" in args else int(S.get("limit", 10000))
BREAK = args[args.index("--break") + 1] if "--break" in args else None
STUDS = 1 / 0.28
out.mkdir(parents=True, exist_ok=True)
HIDE = S.get("hide", {})
PREFIXES = tuple(S.get("materialPrefixes", []))
AREA_RULES = S.get("areas", [])
DEFAULT_AREA = S.get("defaultArea", "Body")
problems = []


def base(n):
    return n.rsplit(".", 1)[0] if n[-4:-3] == "." and n[-3:].isdigit() else n


def chain(o):
    names = []
    while o is not None:
        names.append(base(o.get("kn5_name", o.name)))
        o = o.parent
    return names


def chain_hidden(o):
    names = chain(o)
    return any(h in names for h in HIDE.get("chainExact", [])) or any(
        h in n for h in HIDE.get("chainContains", []) for n in names)


def excluded(o):
    return (any(c.name.startswith(p) for c in o.users_collection for p in HIDE.get("collectionPrefixes", []))
            or any(o.name.endswith(s) for s in HIDE.get("nameSuffixes", []))
            or any(o.name.startswith(p) for p in HIDE.get("namePrefixes", [])))


def area_of(o):
    for rule in AREA_RULES:
        cols = [c.name for c in o.users_collection]
        if ("collection" in rule and rule["collection"] in cols) or (
                "collectionPrefix" in rule and any(c.startswith(rule["collectionPrefix"]) for c in cols)) or (
                "chainContains" in rule and any(rule["chainContains"] in n for n in chain(o))):
            return rule["area"]
    return DEFAULT_AREA


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
part_list = [p for p in meta["parts"] if p.get("mesh") is not False]
manifest_names = {p["name"] for p in meta["parts"]}
for x in S.get("extraParts", []):
    if x["name"] in manifest_names:
        problems.append(f"extra part {x['name']} is in the manifest already: drop it from the settings")
    else:
        part_list.append(x)
wanted = {n for p in part_list for n in (p.get("objects") or [p["name"]])}
if BREAK:
    victim = bpy.data.objects.get(BREAK)
    assert victim is not None, f"--break {BREAK}: no such object"
    bpy.data.objects.remove(victim)
named_hidden = sorted(n for n in wanted if n in bpy.data.objects and chain_hidden(bpy.data.objects[n]))
if named_hidden:
    problems.append(f"parts name objects the hide rules leave out: {named_hidden}")
live = [o for o in bpy.context.scene.objects if o.type == "MESH" and (not o.hide_render or o.name in wanted)
        and len(o.data.polygons) and not chain_hidden(o) and not excluded(o)]
left_out = sorted(o.name for o in bpy.context.scene.objects if o.type == "MESH" and o not in live)
select_only(live)
bpy.ops.object.convert(target="MESH")
live = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.name in {x.name for x in live}]
by_name = {o.name: o for o in live}

owner, parts = {}, []
for p in part_list:
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


def emit(objs, base_name, numbered, part=None, group=None, keep_rotation=False):
    select_only(objs)
    if len(objs) > 1:
        bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    singles = split_material(joined)
    multi = len(singles) > 1
    for s in singles:
        mat = material_of(s)
        name = f"{base_name}_{mat_label(mat)}" if multi or numbered else base_name
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
absent = [p["name"] for p in part_list if not any(r["part"] == p["name"] for r in rows)]
if over:
    problems.append(f"pieces over {LIMIT} triangles in the glb: {over}")
if no_tangent:
    problems.append(f"primitives without tangents: {sorted(set(no_tangent))[:12]}")
if absent:
    problems.append(f"manifest parts with no piece: {absent}")
if set(glb_tris) != set(names):
    problems.append(f"glb nodes differ from the pieces: {sorted(set(glb_tris) ^ set(names))[:10]}")
report = {"limit": LIMIT, "studs_per_metre": STUDS, "frame": "manifest frame scaled to studs, Roblox axes (X right, Y up, -Z forward)",
          "pieces": len(rows), "triangles": sum(r["triangles"] for r in rows), "largest": max(r["triangles"] for r in rows),
          "glb_bytes": len(raw), "no_uv": no_uv, "problems": problems, "parts": rows}
if "extraParts" in S or HIDE:
    report["left_out"] = left_out
(out / "export.json").write_text(json.dumps(report, indent=1))
print(f"EXPORT {len(rows)} pieces, {report['triangles']} triangles, largest {report['largest']}, glb {len(raw) / 1e6:.1f} MB, "
      f"{sum(1 for r in rows if r['uv_maps'] > 1)} with 2+ UV maps, {len(no_uv)} without UVs (fallback UVs given), "
      f"{len(left_out)} meshes left out")
for r in sorted(rows, key=lambda r: -r["triangles"])[:10]:
    print(f"EXPORT   {r['triangles']:6d}  {r['name']}  ({r['material']})")
for r in rows:
    if "lit_face_normal_roblox" in r:
        print(f"EXPORT lit {r['name']}: +Z -> Roblox {r['lit_face_normal_roblox']}")
print("EXPORT", "PASS" if not problems else "FAIL", *problems, sep="\n  ")
sys.exit(1 if problems else 0)
