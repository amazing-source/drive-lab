"""Bake a side livery into the body's paint: one non-overlapping atlas per side, colours from 3D position.

blender -b <car.blend> --factory-startup --python-exit-code 1 -P tools/blender/car_livery_bake.py --
        <livery.json> <sheets dir> --out <out.blend>
        --maps <maps dir> [--px 1024] [--report <report.json>] [--break overlap|flag]

Faces taken: every face whose material (without .NNN) is in `paint_materials`, and every face of the
`carbon_objects` (wing endplates, whose base is carbon, not paint). A face goes to the left atlas
when it faces +x on the car's +x half (world normal x >= 0.25, or >= 0.08 inside an element's box),
to the right atlas mirrored; the rest of the paint takes the `rest_material` (a library set, laid
out by the apply step afterwards); endplate faces that are not on a side keep their material.

Each side atlas gets its own layout: Smart UV Project per object, then each object's block scaled to
one common texel density and shelf-packed into 0..1, the density searched to fill the atlas. Every texel is rasterised to its world position and normal, and its colour is
computed there: the base (the paint colour, or the carbon colour map projected at its tile) under
the side sheet sampled at (y, z). So text reads the right way whatever the UVs do. Gaps are
dilated 8 px. Maps written: livery_<side>_color.png (sRGB) and _roughness.png; metalness is 0 and
there is no normal map. Materials `livery_left` / `livery_right` carry dl_set, dl_kind "baked"
and dl_maps.

Checks (exit 1): no two side faces share texels (overlap under 0.5 % of the used texels), every UV
inside 0..1, and every sheet element landed on at least 50 texels of its side.
`--break overlap` skips the packing (every object's block left at 0..1); `--break flag` drops the carbon objects, so the flag cannot land.
"""
import json
import math
import re
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np

args = sys.argv[sys.argv.index("--") + 1:]
spec_path, sheets = Path(args[0]), Path(args[1])


def opt(name, default=None):
    return args[args.index(name) + 1] if name in args else default


OUT, MAPS = Path(opt("--out")), Path(opt("--maps"))
PX = int(opt("--px", "1024"))
REPORT = Path(opt("--report", str(OUT.with_suffix(".livery.json"))))
BREAK = opt("--break")
S = json.loads(spec_path.read_text())
F = S["frame"]
Y0, Z1, RES = F["y0"], F["z1"], F["res_m"]
MAPS.mkdir(parents=True, exist_ok=True)


def base(n):
    return re.sub(r"\.\d{3}$", "", n)


def srgb_to_lin(c):
    c = np.asarray(c, np.float64) / 255
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb8(c):
    c = np.clip(c, 0, 1)
    return np.round(np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055) * 255).astype(np.uint8)


def load(path, mode):
    from PIL import Image  # Blender's Python ships Pillow only when installed; fall back below
    return np.asarray(Image.open(path).convert(mode))


try:
    SHEET = {s: load(sheets / f"livery_{s}.png", "RGBA").astype(np.float64) / 255 for s in ("left", "right")}
    ROUGH = {s: load(sheets / f"livery_{s}_roughness.png", "L").astype(np.float64) / 255 for s in ("left", "right")}
    CARBON = load(S["carbon"]["color"], "RGB").astype(np.float64) / 255
    CARBON_R = load(S["carbon"]["roughness"], "L").astype(np.float64) / 255
except ImportError:
    def load_bpy(path, channels):
        img = bpy.data.images.load(str(path))
        img.colorspace_settings.name = "Non-Color"
        a = np.array(img.pixels[:]).reshape(img.size[1], img.size[0], 4)[::-1]
        bpy.data.images.remove(img)
        return a[..., :channels] if channels > 1 else a[..., 0]
    SHEET = {s: load_bpy(sheets / f"livery_{s}.png", 4) for s in ("left", "right")}
    ROUGH = {s: load_bpy(sheets / f"livery_{s}_roughness.png", 1) for s in ("left", "right")}
    CARBON = load_bpy(S["carbon"]["color"], 3)
    CARBON_R = load_bpy(S["carbon"]["roughness"], 1)


def sample(img, x, y):
    """Bilinear sample of an image (H, W[, C]) at float pixel coordinates; outside is zero."""
    h, w = img.shape[:2]
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x - x0, y - y0
    out = 0
    for dx, dy, wt in ((0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)):
        xi, yi = x0 + dx, y0 + dy
        ok = (xi >= 0) & (xi < w) & (yi >= 0) & (yi < h)
        v = img[np.clip(yi, 0, h - 1), np.clip(xi, 0, w - 1)]
        wt = np.where(ok, wt, 0.0)
        out = out + (v * (wt[..., None] if v.ndim > wt.ndim else wt))
    return out


def tile_sample(img, u, v):
    h, w = img.shape[:2]
    return sample(np.pad(img, ((0, 1), (0, 1)) + (((0, 0),) if img.ndim == 3 else ()), mode="wrap"),
                  np.mod(u, 1) * w, np.mod(1 - v, 1) * h)


# Element boxes (y, z) for the "inside an element" rule and the landing check.
BOXES = []
for el in S["elements"]:
    if "points" in el:
        ys, zs = [p[0] for p in el["points"]], [p[1] for p in el["points"]]
        b = (min(ys), min(zs), max(ys), max(zs))
    elif el["kind"] == "checker":
        b = (el["y0"], el["z0"], el["y1"], el["z1"])
    elif el["kind"] == "disc":
        b = (el["y"] - el["r"], el["z"] - el["r"], el["y"] + el["r"], el["z"] + el["r"])
    elif el["kind"] == "text":
        w = el.get("plate", {}).get("w", el["height"] * 0.8)
        h = el.get("plate", {}).get("h", el["height"])
        b = (el["y"] - w / 2, el["z"] - h / 2, el["y"] + w / 2, el["z"] + h / 2)
    else:
        b = (el["y"], el["z"], el["y"] + el["w"], el["z"] + el["h"])
    BOXES.append((el["name"], b))


def in_box(y, z, pad=0.03):
    return any(b[0] - pad <= y <= b[2] + pad and b[1] - pad <= z <= b[3] + pad for _n, b in BOXES)


report = {"problems": []}
paint = set(S["paint_materials"])
carbon_objs = set() if BREAK == "flag" else set(S["carbon_objects"])
scene = bpy.context.scene
objs = [o for o in scene.objects if o.type == "MESH" and o.library is None
        and not all(c.name.startswith("Replaced") for c in o.users_collection)]


def get_mat(name, make):
    m = bpy.data.materials.get(name)
    return m if m else make(name)


def placeholder(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    return m


side_faces = {"left": {}, "right": {}}
counts = {"left": 0, "right": 0, "rest": 0}
for o in objs:
    slots = o.material_slots
    is_carbon = o.name in carbon_objs
    paint_idx = {i for i, s in enumerate(slots) if s.material and base(s.material.name) in paint}
    if not paint_idx and not is_carbon:
        continue
    mw, rot = o.matrix_world, o.matrix_world.to_3x3()
    me = o.data
    idx = {}
    for name in ("livery_left", "livery_right") + (() if is_carbon else (S["rest_material"],)):
        mat = get_mat(name, placeholder)
        if mat.name not in [s.material.name for s in slots if s.material]:
            me.materials.append(mat)
        idx[name] = [s.material.name if s.material else None for s in o.material_slots].index(mat.name)
    for poly in me.polygons:
        if not (poly.material_index in paint_idx or is_carbon):
            continue
        c = mw @ poly.center
        n = (rot @ poly.normal).normalized()
        thr = 0.08 if in_box(c.y, c.z) else 0.25
        side = "left" if (c.x > 0 and n.x >= thr) else "right" if (c.x < 0 and n.x <= -thr) else None
        if side:
            side_faces[side].setdefault(o.name, []).append(poly.index)
            side_faces[side].setdefault("__carbon__" + o.name, is_carbon)
            poly.material_index = idx["livery_" + side]
            counts[side] += 1
        elif not is_carbon:
            poly.material_index = idx[S["rest_material"]]
            counts["rest"] += 1


def unwrap(o, faces):
    """Smart UV Project of the given faces of one object (its other faces' UVs untouched)."""
    vl = bpy.context.view_layer
    for x in vl.objects.selected:
        x.select_set(False)
    o.hide_set(False)
    o.hide_viewport = o.hide_select = False
    if not o.data.uv_layers:
        o.data.uv_layers.new(name="UVMap")
    vl.objects.active = o
    o.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(o.data)
    want = set(faces)
    for f in bm.faces:
        f.select_set(f.index in want)
    bmesh.update_edit_mesh(o.data)
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.01, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    try:
        bpy.ops.uv.pack_islands(margin=0.006, rotate=True)
    except RuntimeError as e:
        report["problems"].append(f"{o.name}: pack_islands skipped: {e}")
    bpy.ops.object.mode_set(mode="OBJECT")
    o.select_set(False)


def block(o, faces):
    """UV bounds of the faces and their metres per UV unit (world area against UV area)."""
    me = o.data
    uvl = me.uv_layers.active.data
    mw = o.matrix_world
    us, vs, a2, a3 = [], [], 0.0, 0.0
    for fi in faces:
        poly = me.polygons[fi]
        pts = [uvl[li].uv.copy() for li in poly.loop_indices]
        us += [q.x for q in pts]
        vs += [q.y for q in pts]
        a2 += abs(sum((pts[k] - pts[0]).cross(pts[k + 1] - pts[0]) / 2 for k in range(1, len(pts) - 1)))
        w = [mw @ me.vertices[vi].co for vi in poly.vertices]
        a3 += sum(((w[k] - w[0]).cross(w[k + 1] - w[0])).length / 2 for k in range(1, len(w) - 1))
    return (min(us), min(vs), max(us), max(vs)), math.sqrt(a3 / max(a2, 1e-12))


def shelf(sizes, margin):
    """Shelf-pack (w, h) blocks into width 1; returns offsets and the total height."""
    order = sorted(range(len(sizes)), key=lambda i: -sizes[i][1])
    x = y = row_h = 0.0
    off = [None] * len(sizes)
    for i in order:
        w, h = sizes[i]
        if x + w + margin > 1 and x > 0:
            x, y, row_h = 0.0, y + row_h + margin, 0.0
        off[i] = (x + margin, y + margin)
        x += w + margin
        row_h = max(row_h, h)
    return off, y + row_h + 2 * margin


def layout(side):
    names = [k for k in side_faces[side] if not k.startswith("__carbon__")]
    blocks = []
    for n in names:
        o = bpy.data.objects[n]
        unwrap(o, side_faces[side][n])
        blocks.append((o, side_faces[side][n]) + block(o, side_faces[side][n]))
    margin = 6 / PX
    lo, hi = 1e-4, 10.0  # metres per atlas unit: search the smallest that still fits
    for _ in range(40):
        mid = math.sqrt(lo * hi)
        sizes = [((b[2] - b[0]) * d / mid, (b[3] - b[1]) * d / mid) for _o, _f, b, d in blocks]
        if max(w for w, _h in sizes) + 2 * margin <= 1 and shelf(sizes, margin)[1] <= 1:
            hi = mid
        else:
            lo = mid
    scale_m = hi
    sizes = [((b[2] - b[0]) * d / scale_m, (b[3] - b[1]) * d / scale_m) for _o, _f, b, d in blocks]
    offs, _h = shelf(sizes, margin)
    for (o, faces, b, d), (ox, oy) in zip(blocks, offs):
        k = d / scale_m
        uvl = o.data.uv_layers.active.data
        for fi in faces:
            for li in o.data.polygons[fi].loop_indices:
                u, v = uvl[li].uv
                uvl[li].uv = (ox + (u - b[0]) * k, oy + (v - b[1]) * k)
    return scale_m


def rasterise(side):
    """Per texel: world position, world normal, carbon flag, and a coverage count."""
    pos = np.zeros((PX, PX, 3))
    nrm = np.zeros((PX, PX, 3))
    carb = np.zeros((PX, PX), bool)
    cover = np.zeros((PX, PX), np.int32)
    outside = 0
    for name in [k for k in side_faces[side] if not k.startswith("__carbon__")]:
        o = bpy.data.objects[name]
        is_carbon = side_faces[side]["__carbon__" + name]
        me = o.data
        me.calc_loop_triangles()
        uvl = me.uv_layers.active.data
        mw, rot = o.matrix_world, o.matrix_world.to_3x3()
        want = set(side_faces[side][name])
        for t in me.loop_triangles:
            if t.polygon_index not in want:
                continue
            uv = np.array([uvl[li].uv[:] for li in t.loops])
            if (uv < -1e-4).any() or (uv > 1 + 1e-4).any():
                outside += 1
            P = np.array([(mw @ me.vertices[vi].co)[:] for vi in t.vertices])
            N = np.array((rot @ t.normal).normalized()[:])
            q = uv * PX
            x0, y0 = np.floor(q.min(0)).astype(int)
            x1, y1 = np.ceil(q.max(0)).astype(int)
            x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, PX), min(y1, PX)
            if x1 <= x0 or y1 <= y0:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
            (ax, ay), (bx, by), (cx, cy) = q
            d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(d) < 1e-12:
                continue
            l1 = ((by - cy) * (gx - cx) + (cx - bx) * (gy - cy)) / d
            l2 = ((cy - ay) * (gx - cx) + (ax - cx) * (gy - cy)) / d
            l3 = 1 - l1 - l2
            m = (l1 >= -1e-6) & (l2 >= -1e-6) & (l3 >= -1e-6)
            if not m.any():
                continue
            yy, xx = np.nonzero(m)
            yy, xx = yy + y0, xx + x0
            w = np.stack([l1[m], l2[m], l3[m]], -1)
            rows = PX - 1 - yy  # image row 0 is the top (v = 1)
            pos[rows, xx] = w @ P
            nrm[rows, xx] = N
            carb[rows, xx] = is_carbon
            cover[rows, xx] += 1
    return pos, nrm, carb, cover, outside


def dilate(img, filled, steps=8):
    img, filled = img.copy(), filled.copy()
    for _ in range(steps):
        acc = np.zeros_like(img)
        cnt = np.zeros(filled.shape)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)):
            f = np.roll(np.roll(filled, dy, 0), dx, 1)
            acc += np.roll(np.roll(img, dy, 0), dx, 1) * (f[..., None] if img.ndim == 3 else f)
            cnt += f
        new = (~filled) & (cnt > 0)
        img[new] = (acc[new].T / cnt[new]).T if img.ndim == 3 else acc[new] / cnt[new]
        filled = filled | new
    return img


paint_lin = srgb_to_lin(S["paint_srgb"])
tile = S["carbon"]["tile_m"]
report.update({"faces": counts, "sides": {}})
fail = []
for side in ("left", "right"):
    if not [k for k in side_faces[side] if not k.startswith("__carbon__")]:
        fail.append(f"{side}: no faces")
        continue
    scale_m = layout(side) if BREAK != "overlap" else None
    if BREAK == "overlap":
        for n in [k for k in side_faces[side] if not k.startswith("__carbon__")]:
            unwrap(bpy.data.objects[n], side_faces[side][n])  # each object's islands left at 0..1: blocks overlap
    pos, nrm, carb, cover, outside = rasterise(side)
    used = cover > 0
    over = int((cover > 1).sum())
    sx = (pos[..., 1] - Y0) / RES
    sy = (Z1 - pos[..., 2]) / RES
    dec = sample(SHEET[side], sx, sy)
    rgh = sample(ROUGH[side], sx, sy)
    base_lin = np.broadcast_to(paint_lin, pos.shape).copy()
    base_r = np.full(pos.shape[:2], S["paint_roughness"])
    if carb.any():
        cu, cv = pos[..., 1] / tile, pos[..., 2] / tile
        cc = tile_sample(CARBON, cu, cv)
        base_lin[carb] = srgb_to_lin(cc[carb] * 255)
        base_r[carb] = tile_sample(CARBON_R, cu, cv)[carb]
    a = dec[..., 3]
    col = base_lin * (1 - a[..., None]) + srgb_to_lin(dec[..., :3] * 255) * a[..., None]
    rough = base_r * (1 - a) + rgh * a
    col = dilate(col, used)
    rough = dilate(rough, used)
    from_img = lin_to_srgb8(col)
    cpath, rpath = MAPS / f"livery_{side}_color.png", MAPS / f"livery_{side}_roughness.png"
    img = bpy.data.images.new(f"livery_{side}_color", PX, PX)
    img.pixels.foreach_set(np.concatenate([from_img[::-1].reshape(-1, 3) / 255, np.ones((PX * PX, 1))], 1)
                           .ravel().astype(np.float32))
    img.filepath_raw, img.file_format = str(cpath), "PNG"
    img.save()
    rimg = bpy.data.images.new(f"livery_{side}_roughness", PX, PX)
    rimg.colorspace_settings.name = "Non-Color"
    r8 = np.round(np.clip(rough, 0, 1)[::-1] * 255) / 255
    rimg.pixels.foreach_set(np.stack([r8, r8, r8, np.ones_like(r8)], -1).ravel().astype(np.float32))
    rimg.filepath_raw, rimg.file_format = str(rpath), "PNG"
    rimg.save()
    # Element landing: texels on this side whose position lies inside each element's box.
    landed = {}
    for name, b in BOXES:
        inside = used & (pos[..., 1] >= b[0]) & (pos[..., 1] <= b[2]) & (pos[..., 2] >= b[1]) & (pos[..., 2] <= b[3])
        landed[name] = int(inside.sum())
        if landed[name] < 50:
            fail.append(f"{side}: element '{name}' landed on {landed[name]} texels")
    share = over / max(int(used.sum()), 1)
    if share >= 0.005:
        fail.append(f"{side}: {over} overlapping texels ({share:.1%} of used)")
    if outside:
        fail.append(f"{side}: {outside} triangles with UVs outside 0..1")
    m = bpy.data.materials.get(f"livery_{side}")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    for n in [n for n in nt.nodes if n.type == "TEX_IMAGE"]:
        nt.nodes.remove(n)
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = bpy.data.images.load(str(cpath), check_existing=False)
    tr = nt.nodes.new("ShaderNodeTexImage")
    tr.image = bpy.data.images.load(str(rpath), check_existing=False)
    tr.image.colorspace_settings.name = "Non-Color"
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tr.outputs["Color"], bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Base Color"].default_value = (*paint_lin, 1)
    m.diffuse_color = (*paint_lin, 1)
    m["dl_set"], m["dl_kind"] = f"livery_{side}", "baked"
    m["dl_maps"] = {"color": str(cpath), "roughness": str(rpath)}
    report["sides"][side] = {"texels_used": int(used.sum()), "overlap_texels": over, "uv_outside_tris": outside,
                             "mm_per_texel": round(1000 * scale_m / PX, 2) if scale_m else None,
                             "landed": landed}
report["problems"] += fail
bpy.ops.file.make_paths_absolute()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT), relative_remap=False, compress=True)
REPORT.write_text(json.dumps(report, indent=1))
print("LIVERY faces", counts, "->", OUT)
for side, r in report["sides"].items():
    print("LIVERY", side, {k: v for k, v in r.items() if k != "landed"})
for f in fail:
    print("LIVERY FAIL", f)
if fail:
    sys.exit(1)
print("LIVERY PASS")
