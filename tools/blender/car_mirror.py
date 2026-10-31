"""Mount, aim and bake a car's interior rear-view mirror, from the bare glass plate a game model ships.

Build (on the master, which holds the plate and the windscreen):
    blender -b <master.blend> --factory-startup --python-exit-code 1 -P tools/blender/car_mirror.py --
            <spec.json> --out <out.blend> [--report <report.json>] [--break pad|aim|recess]
Bake (on the assembled car, so the cage and the seats are in the mirror):
    blender -b <assembled.blend> --factory-startup --python-exit-code 1 -P tools/blender/car_mirror.py --
            <spec.json> --bake <maps dir> [--library <library.json>] [--report <report.json>] [--break hide|uv]

Build:
1. The plate's plane (normal toward the eye) and its outline in that plane, resampled by angle (or, with
   `outline: {shape: superellipse, exponent}`, a superellipse of the plate's half-sizes).
2. The head (housing and glass) is turned about its ball joint until the eye's ray reflected at the glass
   centre meets `aim_object`'s bounds centre (the rear window), the glass's long side kept level.
3. Pieces, all from the outline: the glass, recessed `recess_m` behind a lip; the housing (lip, rim,
   domed back `depth_m` deep); a ball joint high on the back; a stalk from the ball to a pad lying
   `pad_gap_m` inside the nearest point of `mount_objects` (the windscreen); a day/night tab under the
   housing. Glass -> `names.glass`; the rest joined -> `names.head`; both in `collection` (else the plate's)
   and under the plate's parent; a rerun replaces them. Shaded smooth, edges sharper than `sharp_deg` kept. The plate goes to `retire_collection`.
4. Glass UVs: the projection of each glass vertex into the bake camera (below), so the bake lands on them.
Checks (exit 1): every pad vertex 0.5 x to 2 x `pad_gap_m` inside the glass; the reflected centre ray within
`aim_tolerance_m` of the aim point; every glass vertex at least 1 mm behind the lip; no triangle of a new
piece crossing another mesh of the car. `--break pad` lays the pad on the glass, `--break aim` skips the
aim, `--break recess` puts the glass in the lip's plane.

Bake: the camera sits at the eye mirrored in the glass plane, looking through the glass outline, framed
on it exactly (the glass UVs). Cycles, `bake.hide` objects hidden (glazing, so the view passes through;
the mirror itself), a uniform sky and, with `bake.ground`, a ground plane at z 0 (the road behind). The image is scaled so its 99th percentile is `bake.p99`, times `bake.reflectance`,
resized to `bake.map_px` square (the SurfaceAppearance export wants square maps). Writes
<set>_color.png and a uniform <set>_roughness.png; the glass's material carries dl_set, dl_kind "baked"
and dl_maps; `--library` adds the set to library.json (a copy of the old file is kept once).
Checks (exit 1): rays from the camera to points of the glass meet nothing before the glass plane (else a
hidden list is missing something); the glass's UVs equal the camera's projection within 1e-4; the
map is not blank. `--break hide` shows the windscreen to the camera, `--break uv` shifts the UVs.
"""
import json
import math
import shutil
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

args = sys.argv[sys.argv.index("--") + 1:]
S = json.loads(Path(args[0]).read_text())


def opt(name, default=None):
    return args[args.index(name) + 1] if name in args else default


OUT, REPORT, BAKE, LIBRARY, BREAK = opt("--out"), opt("--report"), opt("--bake"), opt("--library"), opt("--break")
sc = bpy.context.scene
problems = []
report = {"mode": "bake" if BAKE else "build", "problems": problems}
NAMES = S["names"]
EYE = Vector(S["eye"])


def world_tris(o):
    me = o.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    me.calc_loop_triangles()
    mw = o.matrix_world
    v = [mw @ x.co for x in me.vertices]
    t = [tuple(x.vertices) for x in me.loop_triangles]
    o.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh_clear()
    return v, t


def bvh_of(objs):
    verts, tris = [], []
    for o in objs:
        v, t = world_tris(o)
        base = len(verts)
        verts += v
        tris += [(a + base, b + base, c + base) for a, b, c in t]
    return BVHTree.FromPolygons(verts, tris)


def reflect_dir(d, n):
    return d - 2 * d.dot(n) * n


def level_frame(n):
    u = Vector((0, 0, 1)).cross(n).normalized()
    return u, n.cross(u)


def camera_for(glass_pts, plane_c, plane_n):
    """Camera at the eye mirrored in the glass plane, axes and the tangent box framing the glass."""
    e2 = EYE - 2 * (EYE - plane_c).dot(plane_n) * plane_n
    d = (plane_c - e2).normalized()
    zc = -d
    yc = level_frame(plane_n)[1]
    yc = (yc - yc.dot(zc) * zc).normalized()
    xc = yc.cross(zc)
    R = Matrix((xc, yc, zc)).transposed()
    pts = [R.transposed() @ (p - e2) for p in glass_pts]
    tx = [p.x / -p.z for p in pts]
    ty = [p.y / -p.z for p in pts]
    pad_x, pad_y = (max(tx) - min(tx)) * 0.01, (max(ty) - min(ty)) * 0.01
    box = (min(tx) - pad_x, max(tx) + pad_x, min(ty) - pad_y, max(ty) + pad_y)
    return e2, R, box


def project_uv(p, e2, R, box):
    q = R.transposed() @ (p - e2)
    x, y = q.x / -q.z, q.y / -q.z
    return ((x - box[0]) / (box[1] - box[0]), (y - box[2]) / (box[3] - box[2]))


def set_material(o, name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    o.data.materials.clear()
    o.data.materials.append(m)
    return m


def clash_check(new, pts):
    """No triangle of a new piece may cross another visible mesh within 5 cm of the pieces."""
    others = [o for o in sc.objects if o.type == "MESH" and o not in new and not o.hide_render
              and not any(cl.name.startswith("Replaced") for cl in o.users_collection) and len(o.data.polygons)]
    lo = Vector([min(p[i] for p in pts) - 0.05 for i in range(3)])
    hi = Vector([max(p[i] for p in pts) + 0.05 for i in range(3)])
    near = []
    for o in others:
        ob = [o.matrix_world @ Vector(x) for x in o.bound_box]
        if all(min(p[i] for p in ob) <= hi[i] and max(p[i] for p in ob) >= lo[i] for i in range(3)):
            near.append(o)
    clashes = {}
    for nw_ in new:
        b1 = bvh_of([nw_])
        for o in near:
            k = len(b1.overlap(bvh_of([o])))
            if k:
                clashes[f"{nw_.name} x {o.name}"] = k
    report["clashes"] = clashes
    report["near_objects"] = [o.name for o in near]
    if clashes:
        problems.append(f"clashes: {clashes}")


# ---------------------------------------------------------------------------------------------- build
def build():
    plate = bpy.data.objects[S["plate"]]
    pv, pt = world_tris(plate)
    P = np.array([list(v) for v in pv])
    nsum = Vector()
    for a, b, c in pt:
        nsum += (pv[b] - pv[a]).cross(pv[c] - pv[a])
    n = nsum.normalized()
    c0 = Vector(P.mean(0))
    if n.dot(EYE - c0) < 0:
        n = -n
    u, v = level_frame(n)
    # outline: radius by angle about the 2D centre, from the plate's boundary edges
    me = plate.data
    edges = {}
    for poly in me.polygons:
        for k in range(len(poly.vertices)):
            e = tuple(sorted((poly.vertices[k], poly.vertices[(k + 1) % len(poly.vertices)])))
            edges[e] = edges.get(e, 0) + 1
    bnd = [e for e, cnt in edges.items() if cnt == 1]
    mw = plate.matrix_world
    seg = [((mw @ me.vertices[a].co) - c0, (mw @ me.vertices[b].co) - c0) for a, b in bnd]
    seg2 = [((p.dot(u), p.dot(v)), (q.dot(u), q.dot(v))) for p, q in seg]
    cu = (min(min(a[0], b[0]) for a, b in seg2) + max(max(a[0], b[0]) for a, b in seg2)) / 2
    cv = (min(min(a[1], b[1]) for a, b in seg2) + max(max(a[1], b[1]) for a, b in seg2)) / 2
    c = c0 + u * cu + v * cv
    K = S.get("outline_segments", 48)
    radii = []
    for k in range(K):
        ang = 2 * math.pi * k / K
        dx, dy = math.cos(ang), math.sin(ang)
        best = 0.0
        for (ax, ay), (bx, by) in seg2:
            ax, ay, bx, by = ax - cu, ay - cv, bx - cu, by - cv
            ex, ey = bx - ax, by - ay
            den = dx * ey - dy * ex
            if abs(den) < 1e-12:
                continue
            t = (ax * ey - ay * ex) / den
            s = (ax * dy - ay * dx) / den
            if t > 0 and -1e-9 <= s <= 1 + 1e-9:
                best = max(best, t)
        radii.append(best)
    radii = [(radii[k - 1] + 2 * radii[k] + radii[(k + 1) % K]) / 4 for k in range(K)]
    outline = [(radii[k] * math.cos(2 * math.pi * k / K), radii[k] * math.sin(2 * math.pi * k / K)) for k in range(K)]
    A = max(abs(x) for x, _ in outline)
    B = max(abs(y) for _, y in outline)
    shape = S.get("outline", {})
    if shape.get("shape") == "superellipse":
        # a game plate is often a coarse polygon: a superellipse of the same half-sizes reads as the photo's oval
        e = shape["exponent"]
        outline = []
        for k in range(K):
            t = 2 * math.pi * k / K
            c_, s_ = math.cos(t), math.sin(t)
            outline.append((A * math.copysign(abs(c_) ** (2 / e), c_), B * math.copysign(abs(s_) ** (2 / e), s_)))
    report["plate"] = {"centre": list(c), "normal": list(n), "half_size_m": [A, B]}

    rim, lip, recess, depth = S["rim_m"], S["lip_m"], S["recess_m"], S["depth_m"]
    if BREAK == "recess":
        recess = -lip

    def grow(pt2, by):
        x, y = pt2
        r = math.hypot(x, y)
        return (x * (r + by) / r, y * (r + by) / r)

    # head geometry in local (U, V, N), N toward the eye, origin at the glass centre
    rings = [([grow(p, 0.0005) for p in outline], -recess), ([grow(p, 0.0005) for p in outline], lip),
             ([grow(p, rim) for p in outline], lip), ([grow(p, rim + 0.0015) for p in outline], lip - 0.002),
             ([grow(p, rim + 0.0015) for p in outline], -0.006)]
    outer = [grow(p, rim + 0.0015) for p in outline]
    for k in range(1, 5):
        phi = math.radians(18 * k)
        s = math.cos(phi)
        rings.append(([(x * s, y * s) for x, y in outer], -0.006 - (depth - 0.006) * math.sin(phi)))
    head_v, head_f = [], []
    for pts, nn in rings:
        head_v += [Vector((x, y, nn)) for x, y in pts]
    for r in range(len(rings) - 1):
        for k in range(K):
            a, b = r * K + k, r * K + (k + 1) % K
            head_f.append((a, b, b + K, a + K))
    cap = len(head_v)
    head_v.append(Vector((0, 0, rings[-1][1] - 0.001)))
    last = (len(rings) - 1) * K
    for k in range(K):
        head_f.append((last + k, last + (k + 1) % K, cap))
    glass_v = [Vector((x, y, -recess)) for x, y in outline] + [Vector((0, 0, -recess))]
    glass_f = [(k, (k + 1) % K, K) for k in range(K)]
    # ball high on the back, tab under the housing
    jl = Vector((0, 0.35 * B, -(depth - 0.004)))
    tab_c = Vector((0, -(B + rim + 0.004), -0.012))

    def to_world(local, R, J0):
        p0 = c + u * local.x + v * local.y + n * local.z
        return J0 + R @ (p0 - J0)

    J0 = c + u * jl.x + v * jl.y + n * jl.z
    R = Matrix.Identity(3)
    aim_obj = bpy.data.objects[S["aim_object"]]
    bb = [aim_obj.matrix_world @ Vector(x) for x in aim_obj.bound_box]
    T = sum(bb, Vector()) / 8
    if BREAK != "aim":
        for _ in range(6):
            cc = J0 + R @ (c - J0)
            nt = ((EYE - cc).normalized() + (T - cc).normalized()).normalized()
            ut, vt = level_frame(nt)
            R = Matrix((ut, vt, nt)).transposed() @ Matrix((u, v, n))
    cc = J0 + R @ (c - J0)
    nn_ = R @ n
    refl = reflect_dir((cc - EYE).normalized(), nn_)
    miss = ((T - cc) - (T - cc).dot(refl) * refl).length
    report["aim"] = {"target": list(T), "glass_centre": list(cc), "normal": list(nn_), "reflected": list(refl),
                     "miss_m": miss, "turn_deg": math.degrees(math.acos(max(-1, min(1, n.dot(nn_)))))}
    if miss > S["aim_tolerance_m"]:
        problems.append(f"aim: the reflected centre ray misses the aim point by {miss:.3f} m")

    hv = [to_world(p, R, J0) for p in head_v]
    gv = [to_world(p, R, J0) for p in glass_v]
    lip_n = nn_
    # ball
    ball_r = S["ball_m"]
    ball_c = J0
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=5, radius=ball_r)
    ball_v = [ball_c + R @ (u * x.co.x + v * x.co.y + n * x.co.z) for x in bm.verts]
    ball_f = [tuple(x.index for x in f.verts) for f in bm.faces]
    bm.free()
    # pad on the nearest point of the windscreen
    mount = [bpy.data.objects[nm] for nm in S["mount_objects"]]
    mbvh = bvh_of(mount)
    q, qn, _, _ = mbvh.find_nearest(ball_c)
    if qn.dot(ball_c - q) > 0:
        qn = -qn
    gap = 0.0 if BREAK == "pad" else S["pad_gap_m"]
    pw, ph, pthk = S["pad_m"]
    pu = Vector((0, 0, 1)).cross(qn).normalized()
    pvv = qn.cross(pu)
    corners = []
    for k in range(16):
        a = 2 * math.pi * k / 16
        cx, cy = math.cos(a), math.sin(a)
        rr = 0.008
        x = math.copysign(pw / 2 - rr, cx) + rr * cx
        y = math.copysign(ph / 2 - rr, cy) + rr * cy
        corners.append((x, y))
    # the pad follows the glass: each outline point dropped onto the glass, then offset along its normal
    pad_in, pad_out = [], []
    for x, y in corners:
        gq, gn, _, _ = mbvh.find_nearest(q + pu * x + pvv * y)
        if gn.dot(qn) < 0:
            gn = -gn
        pad_in.append(gq - gn * gap)
        pad_out.append(gq - gn * (gap + pthk))
    pad_v = pad_in + pad_out
    pad_f = [tuple(range(15, -1, -1)), tuple(range(16, 32))] + \
            [(k, (k + 1) % 16, 16 + (k + 1) % 16, 16 + k) for k in range(16)]
    pad_back = q - qn * (gap + pthk - 0.001)
    # stalk: a tapered box from inside the ball to inside the pad
    axis = (pad_back - ball_c).normalized()
    side = Vector((0, 0, 1)).cross(axis)
    side = side.normalized() if side.length > 1e-6 else u
    up2 = axis.cross(side)
    sw0, st0 = S["stalk_mm"][0] / 2000, S["stalk_mm"][1] / 2000
    st_v = []
    for p0, sc_ in ((ball_c + axis * ball_r * 0.3, 1.0), (pad_back, 0.8)):
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            st_v.append(p0 + side * sx * sw0 * sc_ + up2 * sy * st0 * sc_)
    st_f = [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (3, 2, 1, 0), (4, 5, 6, 7)]
    # tab
    tw, td, th = S["tab_m"]
    tab_v = []
    for sx, sy, sz in ((-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)):
        tab_v.append(to_world(tab_c + Vector((sx * tw / 2, sy * th / 2, sz * td / 2)), R, J0))
    tab_f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]

    def make(name, parts, collection, parent):
        verts, faces = [], []
        for vv, ff in parts:
            base = len(verts)
            verts += [list(x) for x in vv]
            faces += [tuple(i + base for i in f) for f in ff]
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(verts, [], faces)
        mesh.validate()
        bmx = bmesh.new()
        bmx.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bmx, faces=bmx.faces)
        bmx.to_mesh(mesh)
        bmx.free()
        mesh.shade_smooth()
        mesh.set_sharpness_by_angle(angle=math.radians(S.get("sharp_deg", 40)))
        o = bpy.data.objects.new(name, mesh)
        collection.objects.link(o)
        if parent:
            o.parent = parent
            o.matrix_parent_inverse = parent.matrix_world.inverted()
        return o

    for old in (NAMES["head"], NAMES["glass"]):
        if old in bpy.data.objects:
            bpy.data.objects.remove(bpy.data.objects[old])
    col = bpy.data.collections.get(S.get("collection", "")) or next(
        cl for cl in plate.users_collection if cl.name != S["retire_collection"])
    head = make(NAMES["head"], [(hv, head_f), (ball_v, ball_f), (st_v, st_f), (pad_v, pad_f), (tab_v, tab_f)],
                col, plate.parent)
    glass = make(NAMES["glass"], [(gv, glass_f)], col, plate.parent)
    # glass faces the eye; recalc may flip a single open fan: force it
    glass.data.update()
    if glass.data.polygons[0].normal.dot(lip_n) < 0:
        glass.data.flip_normals()
    # tiled set UVs on the head: metres / tile_m, box-projected per face
    hm = set_material(head, S["materials"]["housing"])
    tile = S.get("housing_tile_m", 0.1)
    bmx = bmesh.new()
    bmx.from_mesh(head.data)
    uvl = bmx.loops.layers.uv.new("UVMap")
    hw = head.matrix_world
    for f in bmx.faces:
        nw = (hw.to_3x3() @ f.normal)
        ax = max(range(3), key=lambda i: abs(nw[i]))
        i0, i1 = [i for i in range(3) if i != ax]
        for lp in f.loops:
            p = hw @ lp.vert.co
            lp[uvl].uv = (p[i0] / tile, p[i1] / tile)
    bmx.to_mesh(head.data)
    bmx.free()
    gm = set_material(glass, S["materials"]["glass"])
    # glass UVs from the bake camera
    plane_c, plane_n = cc, nn_
    gpts = [glass.matrix_world @ x.co for x in glass.data.vertices]
    e2, Rc, box = camera_for(gpts[:-1], plane_c, plane_n)
    uvg = glass.data.uv_layers.new(name="UVMap")
    for poly in glass.data.polygons:
        for li in poly.loop_indices:
            vi = glass.data.loops[li].vertex_index
            uvg.data[li].uv = project_uv(glass.matrix_world @ glass.data.vertices[vi].co, e2, Rc, box)
    glass["dl_mirror_plane"] = list(plane_c) + list(plane_n)
    # retire the plate
    ret = bpy.data.collections.get(S["retire_collection"])
    if ret is None:
        ret = bpy.data.collections.new(S["retire_collection"])
        sc.collection.children.link(ret)
    for cl in list(plate.users_collection):
        cl.objects.unlink(plate)
    ret.objects.link(plate)
    bpy.context.view_layer.update()

    # checks
    gbvh = bvh_of(mount)
    pad_d = []
    for p in pad_v[:16]:
        qq, qqn, _, dist = gbvh.find_nearest(p)
        inside = (p - qq).dot(qn) < 0
        pad_d.append(dist if inside else -dist)
    report["pad"] = {"glass_point": list(q), "gap_mm_min": min(pad_d) * 1e3, "gap_mm_max": max(pad_d) * 1e3,
                     "stalk_m": (pad_back - ball_c).length}
    want = S["pad_gap_m"]
    if min(pad_d) < 0.5 * want or max(pad_d) > 2 * want:
        problems.append(f"pad: gap to the glass {min(pad_d) * 1e3:.2f}-{max(pad_d) * 1e3:.2f} mm, wants "
                        f"{0.5 * want * 1e3:.2f}-{2 * want * 1e3:.2f}")
    lip_plane = cc + nn_ * lip
    worst = max((p - lip_plane).dot(nn_) for p in gv)
    report["recess_mm"] = -worst * 1e3
    if worst > -0.001:
        problems.append(f"recess: the glass is {-worst * 1e3:.2f} mm behind the lip (wants >= 1 mm)")
    new = [head, glass]
    clash_check(new, hv + list(pad_v))
    report["triangles"] = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in new}
    report["camera"] = {"eye_mirrored": list(e2), "box": list(box)}
    report["materials"] = {head.name: hm.name, glass.name: gm.name}
    if OUT:
        bpy.ops.wm.save_as_mainfile(filepath=OUT, compress=True)


# ----------------------------------------------------------------------------------------------- bake
def bake():
    glass = bpy.data.objects[NAMES["glass"]]
    pl = list(glass["dl_mirror_plane"])
    plane_c, plane_n = Vector(pl[:3]), Vector(pl[3:])
    gpts = [glass.matrix_world @ x.co for x in glass.data.vertices]
    rim_pts = gpts[:-1]
    e2, Rc, box = camera_for(rim_pts, plane_c, plane_n)
    # the UVs must be the camera's projection
    uvl = glass.data.uv_layers.active
    err = 0.0
    for poly in glass.data.polygons:
        for li in poly.loop_indices:
            vi = glass.data.loops[li].vertex_index
            want = project_uv(gpts[vi], e2, Rc, box)
            got = uvl.data[li].uv
            if BREAK == "uv":
                got = (got[0] + 0.01, got[1])
            err = max(err, abs(got[0] - want[0]), abs(got[1] - want[1]))
    report["uv_error"] = err
    if err > 1e-4:
        problems.append(f"uv: glass UVs differ from the camera projection by {err:.5f}")
    head = bpy.data.objects[NAMES["head"]]
    clash_check([head, glass], [head.matrix_world @ x.co for x in head.data.vertices] + gpts)
    hide = S["bake"]["hide"]
    hidden = []
    for o in sc.objects:
        if o.type != "MESH":
            continue
        rep_col = any(cl.name.startswith("Replaced") for cl in o.users_collection)
        h = rep_col or any(s in o.name for s in hide)
        if BREAK == "hide" and "glassF" in o.name:
            h = False
        if h and not o.hide_render:
            hidden.append(o.name)
        o.hide_render = o.hide_render or h
        o.hide_viewport = o.hide_render
    bpy.context.view_layer.update()
    if S["bake"].get("ground"):
        gme = bpy.data.meshes.new("MirrorGround")
        g = 400.0
        gme.from_pydata([(-g, -g, 0), (g, -g, 0), (g, g, 0), (-g, g, 0)], [], [(0, 1, 2, 3)])
        gob = bpy.data.objects.new("MirrorGround", gme)
        gmat = bpy.data.materials.new("MirrorGround")
        gmat.use_nodes = True
        gb = next(n for n in gmat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        gb.inputs["Base Color"].default_value = (*S["bake"]["ground"], 1)
        gb.inputs["Roughness"].default_value = 0.9
        gme.materials.append(gmat)
        sc.collection.objects.link(gob)
    bpy.context.view_layer.update()
    # nothing may stand between the camera and the glass plane
    dg = bpy.context.evaluated_depsgraph_get()
    blocked = []
    samples = rim_pts[::8] + [gpts[-1]]
    for p in samples:
        p_in = plane_c + (p - plane_c) * 0.97
        dvec = (p_in - e2)
        ok, loc, nrm, idx, ob, mw = sc.ray_cast(dg, e2, dvec.normalized(), distance=dvec.length - 0.002)
        if ok:
            blocked.append(ob.name)
    report["blocked_before_glass"] = sorted(set(blocked))
    if blocked:
        problems.append(f"hide: the camera meets {sorted(set(blocked))} before the glass plane")
    # what the mirror shows: first hits of a ray grid through the glass outline's box
    seen = {}
    for gy in np.linspace(0.05, 0.95, 8):
        for gx in np.linspace(0.03, 0.97, 32):
            x = box[0] + gx * (box[1] - box[0])
            y = box[2] + gy * (box[3] - box[2])
            dvec = Rc @ Vector((x, y, -1.0))
            ok, loc, nrm, idx, ob, mw = sc.ray_cast(dg, e2, dvec.normalized())
            key = ob.name if ok else "(sky)"
            seen[key] = seen.get(key, 0) + 1
    report["seen"] = dict(sorted(seen.items(), key=lambda kv: -kv[1])[:12])
    cam = bpy.data.objects.new("MirrorCam", bpy.data.cameras.new("MirrorCam"))
    sc.collection.objects.link(cam)
    cam.matrix_world = Matrix.Translation(e2) @ Rc.to_4x4()
    W, H = box[1] - box[0], box[3] - box[2]
    px_w = S["bake"]["px"]
    px_h = max(16, round(px_w * H / W))
    cam.data.sensor_fit = "HORIZONTAL"
    cam.data.angle_x = 2 * math.atan(W / 2)
    cam.data.shift_x = ((box[0] + box[1]) / 2) / W
    cam.data.shift_y = ((box[2] + box[3]) / 2) / W
    cam.data.clip_start = 0.01
    sc.camera = cam
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = S["bake"]["samples"]
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = px_w, px_h, 100
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.render.image_settings.file_format = "PNG"
    world = bpy.data.worlds.new("MirrorWorld")
    if not world.use_nodes:
        world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (*S["bake"]["world"], 1)
    bg.inputs[1].default_value = S["bake"]["world_strength"]
    sc.world = world
    sun = bpy.data.objects.new("MirrorSun", bpy.data.lights.new("MirrorSun", "SUN"))
    sun.data.energy = S["bake"]["sun"]
    sun.rotation_euler = (math.radians(35), 0, math.radians(160))
    sc.collection.objects.link(sun)
    out = Path(BAKE)
    out.mkdir(parents=True, exist_ok=True)
    raw = out / f"{S['materials']['glass']}_raw.png"
    sc.render.filepath = str(raw)
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(str(raw))
    a = np.array(img.pixels[:]).reshape(img.size[1], img.size[0], 4)[::-1, :, :3]
    p99 = float(np.percentile(a, 99))
    scale = S["bake"]["p99"] / p99 if p99 > 0 else 1.0
    a = np.clip(a * scale * S["bake"]["reflectance"], 0, 1)
    report["bake"] = {"px": [px_w, px_h], "p99_raw": p99, "scale": scale, "mean_srgb": float(a.mean() * 255),
                      "hidden": hidden, "images_missing": [i.name for i in bpy.data.images
                                                            if i.source == "FILE" and not i.has_data and i.users]}
    if a.mean() * 255 < 3:
        problems.append("bake: the map is blank")
    from_np = (a * 255 + 0.5).astype(np.uint8)
    mp = S["bake"]["map_px"]
    tmp = bpy.data.images.new("mirror_tmp", px_w, px_h, alpha=False)
    rgba = np.concatenate([from_np[::-1].astype(np.float32) / 255, np.ones((px_h, px_w, 1), np.float32)], 2)
    tmp.pixels[:] = rgba.ravel()
    tmp.scale(mp, mp)
    cpath = out / f"{S['materials']['glass']}_color.png"
    tmp.filepath_raw = str(cpath)
    tmp.file_format = "PNG"
    tmp.save()
    rpath = out / f"{S['materials']['glass']}_roughness.png"
    rimg = bpy.data.images.new("mirror_r", 16, 16, alpha=False)
    rv = S["bake"]["roughness"]
    rimg.pixels[:] = [rv, rv, rv, 1.0] * 256
    rimg.colorspace_settings.name = "Non-Color"
    rimg.filepath_raw = str(rpath)
    rimg.file_format = "PNG"
    rimg.save()
    report["maps"] = {"color": cpath.as_posix(), "roughness": rpath.as_posix()}
    if LIBRARY:
        lp = Path(LIBRARY)
        keep = lp.with_name(f"library_pre_{S['materials']['glass']}.json")
        if not keep.exists():
            shutil.copyfile(lp, keep)
        lib = json.loads(lp.read_text())
        rec = {"name": S["materials"]["glass"], "kind": "baked", "color": cpath.as_posix(), "roughness": rpath.as_posix(),
               "metalness": 0.0, "basis": S["bake"]["basis"], "use": S["bake"]["use"]}
        lib["materials"] = [m for m in lib["materials"] if m["name"] != rec["name"]] + [rec]
        lp.write_text(json.dumps(lib, indent=1))
        report["library"] = {"file": str(lp), "kept_copy": str(keep), "sets": len(lib["materials"])}


def glass_material(cpath, rpath):
    """The baked material for the build file: called by the build when maps already exist."""
    m = bpy.data.materials.get(S["materials"]["glass"])
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    for n in [n for n in nt.nodes if n.type == "TEX_IMAGE"]:
        nt.nodes.remove(n)
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = bpy.data.images.load(str(cpath), check_existing=True)
    tr = nt.nodes.new("ShaderNodeTexImage")
    tr.image = bpy.data.images.load(str(rpath), check_existing=True)
    tr.image.colorspace_settings.name = "Non-Color"
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tr.outputs["Color"], bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = 0.0
    m["dl_set"], m["dl_kind"] = S["materials"]["glass"], "baked"
    m["dl_maps"] = {"color": Path(cpath).as_posix(), "roughness": Path(rpath).as_posix()}


if BAKE:
    bake()
else:
    build()
    maps = S.get("maps_dir")
    if maps:
        cp = Path(maps) / f"{S['materials']['glass']}_color.png"
        rp = Path(maps) / f"{S['materials']['glass']}_roughness.png"
        if cp.exists() and rp.exists():
            glass_material(cp, rp)
            report["glass_material"] = "baked maps linked"
            if OUT:
                bpy.ops.wm.save_as_mainfile(filepath=OUT, compress=True)
        else:
            report["glass_material"] = "maps not baked yet: run --bake on the assembly, then this build again"
if REPORT:
    Path(REPORT).write_text(json.dumps(report, indent=1, default=str))
print("MIRROR", report["mode"], "PASS" if not problems else "FAIL", *problems, sep="\n  ")
for k in ("aim", "pad", "recess_mm", "clashes", "triangles", "uv_error", "blocked_before_glass", "seen", "bake", "library"):
    if k in report:
        print("MIRROR", k, json.dumps(report[k], default=str)[:400])
sys.exit(1 if problems else 0)
