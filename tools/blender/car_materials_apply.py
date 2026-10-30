"""Give a car's meshes their library materials from a material map, with UVs at real scale.

    blender -b --factory-startup -P tools/blender/car_materials_apply.py -- <car.blend> <map.json> --out <out.blend>
            [--report <report.json>] [--break uv|set|images]

The map names a library directory and three tables:
- `objects`: object name -> {"set": name} (every slot of the object) or
  {"split_by_normal": {"up_z": z, "up": set, "other": set}} (faces whose world normal has z >= up_z
  take `up`); object rules win;
- `materials`: material name without its .NNN suffix -> {"set": name}, for every other object;
- `keep`: material names left as they are (listed so a coverage check can tell kept from forgotten).
A material whose name (without .NNN) is itself a library set, and that no rule or keep entry
names, takes that set: modellers name materials after sets and need no map entry.
`derived` adds sets built from a source texture (`kind: source_derived`, keeping the mesh's UVs).
`replace_images`: source file name -> replacement file (debadged copies); every image node reading
a listed file is pointed at the replacement, packed or not.

Each set becomes one material named after it, as Roblox will take it: Principled with the set's
colour (sRGB), roughness, metalness and OpenGL normal maps, or plain values for a flat set. The
material carries `dl_set`, `dl_kind`, `dl_tile_m`, `dl_roblox_material` and `dl_maps` (absolute
paths), so an exporter reads it without parsing nodes. A pre-existing material with a set's name
(a placeholder) is renamed `<name>_src` first.

UVs: a tiled set wants `uv = metres / tile_m`. For each object, the faces of each tile size are
checked by metres per UV unit (world-space areas), area-weighted: median within 15 % of tile_m,
p10 >= 0.6 and p90 <= 1.6 times it, under 1 % of the area on zero-area UVs. A group that fails is
re-projected with Smart UV Project, scaled so one UV unit is tile_m metres: only its off-scale
faces when its median is already at scale (the modeller's layout and directions are kept), all of
it otherwise (an atlas layout). Other faces' UVs are untouched; the object keeps one UV layer.

Images: every path is made absolute and missing ones are found by name under the map's
`image_roots` (car_resolve_images.py). The file is saved with absolute paths.

Self-check at the end, exit code 1 on failure: every planned slot carries its set's material,
every tiled face group passes the UV check, and no material node still reads a replaced file.
`--break uv` skips the first UV regeneration, `--break set` misassigns the first slot and
`--break images` skips the replacement, so each check can be seen failing.
"""
import json
import math
import re
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from car_resolve_images import resolve  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:]
blend, map_path = Path(args[0]), Path(args[1])


def opt(name, default=None):
    return args[args.index(name) + 1] if name in args else default


out_path = Path(opt("--out"))
report_path = Path(opt("--report", str(out_path.with_suffix(".materials.json"))))
BREAK = opt("--break")
bpy.ops.wm.open_mainfile(filepath=str(blend))
M = json.loads(map_path.read_text())
LIB = Path(M["library"])
LIBJ = json.loads((LIB / "library.json").read_text())
SETS = {m["name"]: m for m in LIBJ["materials"]}
SETS.update(M.get("derived", {}))
OBJ_RULES, MAT_RULES, KEEP = M.get("objects", {}), M.get("materials", {}), M.get("keep", {})
report = {"blend": str(blend), "map": str(map_path), "objects": [], "problems": []}


def base(name):
    return re.sub(r"\.\d{3}$", "", name)


def lin(c8):
    c = c8 / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def kind(name):
    return SETS[name].get("kind", "tiled")


def map_paths(name):
    paths = {}
    reuse = re.search(r"reuses (\w+)", str(LIBJ.get(name, "")))
    for role in ("color", "normal", "roughness", "metalness"):
        p = LIB / name / f"{name}_{role}.png"
        if not p.exists() and reuse:
            p = LIB / reuse.group(1) / f"{reuse.group(1)}_{role}.png"
        if p.exists():
            paths[role] = p
    return paths


def image_node(nodes, path, colour_space, x, y):
    img = bpy.data.images.load(str(path), check_existing=True)
    img.colorspace_settings.name = colour_space
    n = nodes.new("ShaderNodeTexImage")
    n.image, n.location = img, (x, y)
    return n


BUILT = {}


def build(name):
    if name in BUILT:
        return BUILT[name]
    spec, k = SETS[name], kind(name)
    old = bpy.data.materials.get(name)
    if old and old.get("dl_set") == name:
        BUILT[name] = old
        return old
    if old:
        old.name = name + "_src"
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    m["dl_set"], m["dl_kind"] = name, k
    maps = {}
    if k == "flat":
        c = [lin(v) for v in spec["albedo_srgb"]]
        bsdf.inputs["Base Color"].default_value = (*c, 1)
        bsdf.inputs["Roughness"].default_value = spec["roughness"]
        bsdf.inputs["Metallic"].default_value = spec["metalness"]
        m["dl_roblox_material"] = spec.get("roblox_material", "SmoothPlastic")
        if "transparency" in spec:
            bsdf.inputs["Alpha"].default_value = 1 - spec["transparency"]
            m.surface_render_method = "BLENDED"
        if spec.get("roblox_material") == "Neon":
            bsdf.inputs["Emission Color"].default_value = (*c, 1)
        m.diffuse_color = (*c, 1)
    elif k == "source_derived":
        col = image_node(nodes, spec["color"], "sRGB", -600, 300)
        links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
        if spec.get("alpha") == "color":
            links.new(col.outputs["Alpha"], bsdf.inputs["Alpha"])
            m.surface_render_method = "DITHERED"
        maps = {"color": spec["color"]}
        if spec.get("normal"):
            nrm = image_node(nodes, spec["normal"], "Non-Color", -600, -300)
            nm = nodes.new("ShaderNodeNormalMap")
            links.new(nrm.outputs["Color"], nm.inputs["Color"])
            links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
            maps["normal"] = spec["normal"]
        bsdf.inputs["Roughness"].default_value = spec["roughness"]
        bsdf.inputs["Metallic"].default_value = spec["metalness"]
        m.diffuse_color = (0.42, 0.012, 0.02, 1)
    else:
        paths = map_paths(name)
        y = 400
        for role, cs in (("color", "sRGB"), ("roughness", "Non-Color"), ("metalness", "Non-Color"), ("normal", "Non-Color")):
            if role not in paths:
                report["problems"].append(f"set {name}: no {role} map")
                continue
            n = image_node(nodes, paths[role], cs, -700, y)
            y -= 300
            maps[role] = str(paths[role])
            if role == "color":
                links.new(n.outputs["Color"], bsdf.inputs["Base Color"])
            elif role == "roughness":
                links.new(n.outputs["Color"], bsdf.inputs["Roughness"])
            elif role == "metalness":
                links.new(n.outputs["Color"], bsdf.inputs["Metallic"])
            else:
                nm = nodes.new("ShaderNodeNormalMap")
                nm.location = (-300, y + 300)
                links.new(n.outputs["Color"], nm.inputs["Color"])
                links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        a = spec.get("albedo_srgb_mean", [128, 128, 128])
        m.diffuse_color = (*[lin(v) for v in a], 1)
        # Linked inputs ignore these defaults; tools that read one flat colour per material get the mean.
        bsdf.inputs["Base Color"].default_value = (*[lin(v) for v in a], 1)
        bsdf.inputs["Roughness"].default_value = spec.get("roughness_mean", 0.5)
        bsdf.inputs["Metallic"].default_value = spec.get("metalness_mean", 0.0)
        m.roughness = spec.get("roughness_mean", 0.5)
        m.metallic = spec.get("metalness_mean", 0.0)
        m["dl_tile_m"] = spec["tile_m"]
        m["dl_roblox_material"] = "SmoothPlastic"
    m["dl_maps"] = {r: str(p) for r, p in maps.items()}
    BUILT[name] = m
    return m


fixed, missing = resolve(M.get("image_roots", []))
report["images_fixed"], report["images_missing"] = fixed, missing


def file_name(img):
    return Path(bpy.path.abspath(img.filepath).replace("\\", "/")).name.lower()


REPLACE = {k.lower(): Path(v) for k, v in M.get("replace_images", {}).items()}
replaced = []
if REPLACE and BREAK != "images":
    swap = {}
    for img in list(bpy.data.images):
        new = REPLACE.get(file_name(img))
        if new is None or img.library:
            continue
        if not new.is_file():
            report["problems"].append(f"replacement missing: {new}")
            continue
        rep = bpy.data.images.load(str(new), check_existing=True)
        rep.colorspace_settings.name = img.colorspace_settings.name
        rep.alpha_mode = img.alpha_mode
        swap[img.name] = rep
    for mat in bpy.data.materials:
        if not mat.node_tree:
            continue
        for n in mat.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image and n.image.name in swap:
                replaced.append((mat.name, n.image.name, swap[n.image.name].name))
                n.image = swap[n.image.name]
report["images_replaced"] = replaced

# 1. Plan every slot's target from the ORIGINAL names, before any material is renamed.
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.library is None
          and not all(c.name.startswith("Replaced") for c in o.users_collection)]
plans = {}
for o in meshes:
    rule = OBJ_RULES.get(o.name)
    if rule and "split_by_normal" in rule:
        plans[o.name] = {"split": rule["split_by_normal"]}
    elif rule:
        plans[o.name] = {"whole": rule["set"]}
    else:
        slots = {}
        for i, s in enumerate(o.material_slots):
            if not s.material:
                continue
            b = base(s.material.name)
            if b in MAT_RULES:
                slots[i] = MAT_RULES[b]["set"]
            elif b not in KEEP and b in SETS and kind(b) in ("tiled", "flat", "source_derived"):
                slots[i] = b
        if slots:
            plans[o.name] = {"slots": slots}
for p in plans.values():
    for s in ([p["whole"]] if "whole" in p else list(p.get("slots", {}).values())
              or [p["split"]["up"], p["split"]["other"]]):
        if s not in SETS:
            sys.exit(f"APPLY FAIL unknown set {s!r}")

# 2. Assign.
seen_data = {}
expected = []  # (object, slot index, set)
for o in meshes:
    p = plans.get(o.name)
    if not p:
        continue
    me = o.data
    if me.users > 1:
        prev = seen_data.get(me.name)
        if prev and prev[1] != p:
            report["problems"].append(f"{o.name}: shares mesh {me.name} with {prev[0]} under a different rule")
        seen_data.setdefault(me.name, (o.name, p))
    before = [s.material.name if s.material else None for s in o.material_slots]
    if "whole" in p:
        mat = build(p["whole"])
        if not o.material_slots:
            me.materials.append(mat)
        for i, slot in enumerate(o.material_slots):
            slot.material = mat
            expected.append((o.name, i, p["whole"]))
    elif "slots" in p:
        for i, s in p["slots"].items():
            o.material_slots[i].material = build(s)
            expected.append((o.name, i, s))
    else:
        sp = p["split"]
        up, other = build(sp["up"]), build(sp["other"])
        me.materials.clear()
        me.materials.append(up)
        me.materials.append(other)
        mw = o.matrix_world.to_3x3()
        for poly in me.polygons:
            n = (mw @ poly.normal).normalized()
            poly.material_index = 0 if n.z >= sp["up_z"] else 1
        expected += [(o.name, 0, sp["up"]), (o.name, 1, sp["other"])]
    report["objects"].append({"object": o.name, "before": before,
                              "after": [s.material.name if s.material else None for s in o.material_slots], "uv": []})

if BREAK == "set" and expected:
    o = bpy.data.objects[expected[0][0]]
    wrong = next(n for n in SETS if n != expected[0][2] and kind(n) == "flat")
    o.material_slots[expected[0][1]].material = build(wrong)
    print("APPLY --break set:", o.name, "slot", expected[0][1], "->", wrong)


# 3. UVs at metres / tile_m.
def density(o, faces):
    """Per face: metres per UV unit (nan where the UV face has no area) and world-space area."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.transform(o.matrix_world)
    bm.faces.ensure_lookup_table()
    uv = bm.loops.layers.uv.active
    r, a = np.full(len(faces), np.nan), np.zeros(len(faces))
    for k, fi in enumerate(faces):
        f = bm.faces[fi]
        a[k] = f.calc_area()
        pts = [lp[uv].uv for lp in f.loops]
        a2 = sum(abs((pts[j] - pts[0]).cross(pts[j + 1] - pts[0])) / 2 for j in range(1, len(pts) - 1))
        if a2 > 1e-14 and a[k] > 1e-10:
            r[k] = math.sqrt(a[k] / a2)
    bm.free()
    return r, a


def wpct(r, a, qs=(10, 50, 90)):
    m = np.isfinite(r) & (a > 0)
    if not m.any():
        return None
    order = np.argsort(r[m])
    rs, c = r[m][order], np.cumsum(a[m][order])
    c /= c[-1]
    return [float(rs[min(np.searchsorted(c, q / 100), len(rs) - 1)]) for q in qs]


def face_ok(r, tile):
    return np.isfinite(r) & (r >= 0.6 * tile) & (r <= 1.6 * tile)


def healthy(r, a, tile):
    if len(r) == 0 or a.sum() <= 0:
        return False
    zero_share = a[~np.isfinite(r)].sum() / a.sum()
    w = wpct(r, a)
    return (w is not None and zero_share < 0.01 and abs(w[1] / tile - 1) <= 0.15
            and w[0] >= 0.6 * tile and w[2] <= 1.6 * tile)


def stats(r, a, tile):
    w = wpct(r, a)
    tot = max(a.sum(), 1e-12)
    return {"m_per_uv_area_weighted_p10_p50_p90": [round(x, 4) for x in w] if w else None,
            "zero_uv_area_share": round(float(a[~np.isfinite(r)].sum() / tot), 4),
            "off_scale_area_share": round(float(a[~face_ok(r, tile)].sum() / tot), 4)}


def regenerate(o, faces, tile):
    vl = bpy.context.view_layer
    hidden = (o.hide_get(), o.hide_viewport, o.hide_select)
    o.hide_set(False)
    o.hide_viewport = o.hide_select = False
    for x in vl.objects.selected:
        x.select_set(False)
    vl.objects.active = o
    o.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(o.data)
    want = set(faces)
    for f in bm.faces:
        f.select_set(f.index in want)
    bmesh.update_edit_mesh(o.data)
    kw = dict(angle_limit=math.radians(60), island_margin=0.002, area_weight=0.0, correct_aspect=True,
              scale_to_bounds=False)
    try:
        bpy.ops.uv.smart_project(rotate_method="AXIS_ALIGNED", **kw)
    except TypeError:
        bpy.ops.uv.smart_project(**kw)
    bpy.ops.object.mode_set(mode="OBJECT")
    me = o.data
    uvl = me.uv_layers.active.data
    w = wpct(*density(o, faces))
    s = w[1] / tile if w else 1.0  # one UV unit becomes tile_m metres
    for fi in faces:
        for li in me.polygons[fi].loop_indices:
            uvl[li].uv = uvl[li].uv * s
    o.hide_set(hidden[0])
    o.hide_viewport, o.hide_select = hidden[1], hidden[2]


broke_uv = False
for entry in report["objects"]:
    o = bpy.data.objects[entry["object"]]
    me = o.data
    groups = {}
    for poly in me.polygons:
        mat = o.material_slots[poly.material_index].material if poly.material_index < len(o.material_slots) else None
        sname = mat.get("dl_set") if mat else None
        if sname and kind(sname) == "tiled":
            groups.setdefault(SETS[sname]["tile_m"], []).append(poly.index)
    if groups and not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    for tile, faces in sorted(groups.items()):
        r, a = density(o, faces)
        rec = {"tile_m": tile, "faces": len(faces), "before": stats(r, a, tile)}
        w = wpct(r, a)
        if healthy(r, a, tile):
            rec["action"] = "kept"
        elif BREAK == "uv" and not broke_uv:
            broke_uv = True
            rec["action"] = "skipped (--break uv)"
            print("APPLY --break uv: left", o.name, "tile", tile, "unfixed")
        else:
            at_scale = w is not None and abs(w[1] / tile - 1) <= 0.15
            todo = [f for f, ok in zip(faces, face_ok(r, tile)) if not ok] if at_scale else faces
            try:
                regenerate(o, todo, tile)
            except RuntimeError as e:
                report["problems"].append(f"{o.name}: UV regeneration failed: {e}")
            rec["action"] = f"repaired {len(todo)} off-scale faces" if at_scale else "smart_project"
            rec["after"] = stats(*density(o, faces), tile)
        entry["uv"].append(rec)

# 4. Self-check.
fail = []
for name, i, s in expected:
    m = bpy.data.objects[name].material_slots[i].material
    if not m or m.get("dl_set") != s:
        fail.append(f"{name} slot {i}: wants {s}, has {m.name if m else None}")
for entry in report["objects"]:
    o = bpy.data.objects[entry["object"]]
    for rec in entry["uv"]:
        sl = o.material_slots
        faces = [p.index for p in o.data.polygons
                 if p.material_index < len(sl) and sl[p.material_index].material
                 and sl[p.material_index].material.get("dl_set") in SETS
                 and kind(sl[p.material_index].material["dl_set"]) == "tiled"
                 and SETS[sl[p.material_index].material["dl_set"]]["tile_m"] == rec["tile_m"]]
        r, a = density(o, faces)
        if not healthy(r, a, rec["tile_m"]):
            fail.append(f"{o.name} tile {rec['tile_m']}: UV density {stats(r, a, rec['tile_m'])}")
for mat in bpy.data.materials:
    if mat.users and mat.node_tree:
        for n in mat.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image and file_name(n.image) in REPLACE:
                fail.append(f"material {mat.name} still reads {file_name(n.image)}")
report["problems"] += fail
report["materials_built"] = {n: {k: str(v) for k, v in m["dl_maps"].items()} for n, m in BUILT.items()}
bpy.ops.file.make_paths_absolute()
out_path.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(out_path), relative_remap=False, compress=True)
report_path.write_text(json.dumps(report, indent=1))
n_uv = sum(1 for e in report["objects"] for u in e["uv"] if u["action"] == "smart_project")
print(f"APPLY {len(report['objects'])} objects, {len(expected)} slots, {len(BUILT)} sets, {n_uv} UV groups regenerated, "
      f"images fixed {len(fixed)} missing {len(missing)}, {len(replaced)} image nodes repointed -> {out_path}")
for f in fail:
    print("APPLY FAIL", f)
for p in report["problems"]:
    if p not in fail:
        print("APPLY NOTE", p)
if fail:
    sys.exit(1)
print("APPLY PASS")
