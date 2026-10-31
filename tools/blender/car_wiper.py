"""Fit, build and check a windscreen wiper: arm and blade as one hinged part, modelled parked, plus its spindle boss.

blender -b <car.blend> --factory-startup --python-exit-code 1 -P tools/blender/car_wiper.py --
        <spec.json> --out <out.blend> [--report <report.json>] [--break clear|edge|sign]

Spec (Blender frame, metres): `pane` / `band` (the clear glass and its printed band: both are glass the
blade may ride), `scuttle` (the boss stands on it), `pivot_xy`, `boss_height_m`, the parked blade from the
photos (`parked_outer` x and z on the pane, `parked_inner` x and how far above the pane's lowest point),
`blade_length_m`, `blade_clear_m`, `edge_margin_m`, `min_sweep_deg`, `tilt_search_deg`, `min_clear_m`,
`steps`, `names`, `materials`, `parent`, `collection`, optional `range_deg`, `quad` (four points of the
area the game clears, e.g. the manifest's Windshield_* corners) and `eye` (the driver's eye): the report
then gives the quad's swept share and whether the eye's level line of sight, and lines 1-8 deg below it,
cross the swept area. `parked_inner` takes x and either z on the pane or `up_m` above its lowest point.

Fit: for each spindle-axis tilt about the inward glass normal at the pivot, the parked blade (straight in
the plane across the axis) is swept by 1 degree steps until its edge leaves the glass or comes within
`edge_margin_m` of the glass's outer edge. A rigid blade cannot follow a doubly curved screen at every
angle, so its rubber edge is placed, at each radius, on the highest glass point it passes over plus
`blade_clear_m` (the surface of revolution about the axis that clears the glass); the tilt kept is the one
with the smallest worst gap among those sweeping at least `min_sweep_deg`.

Build, parked: the boss (static), the arm's head with its nut on the spindle, the arm cranked to stay
`min_clear_m` over everything it passes, the blade's frame and rubber edge and the clip. UVs at
metres / 0.1 (the tiled sets), one material slot per set; shaded smooth, edges sharper than `sharp_deg` kept.

Checks over `steps` + 1 angles from park to the range (exit 1): no triangle of the arm crosses the glass,
the scuttle, the bonnet or the body (BVH overlap); every arm vertex at least `min_clear_m` from them; every
rubber-edge sample over the glass. `--break clear` lowers the blade 6 mm, `--break edge` sweeps 25 degrees
past the range, `--break sign` turns the axis round (the blade sweeps down into the scuttle).
Report: pivot, axis (positive = the right-hand rule, lifting the blade off its park line), range, the
parked rubber edge's ends, the clear-pane and quad shares per step, gaps, triangles, and every value in the
manifest frame (forward = -y, right = -x, up = z).
"""
import json
import math
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


OUT, REPORT, BREAK = opt("--out"), opt("--report"), opt("--break")
sc = bpy.context.scene
problems = []
report = {"problems": problems}
N_FIT = 41
N_MESH = 21


def world_tris(objs):
    verts, tris = [], []
    dg = bpy.context.evaluated_depsgraph_get()
    for o in objs:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        me.calc_loop_triangles()
        base = len(verts)
        verts += [o.matrix_world @ v.co for v in me.vertices]
        tris += [tuple(i + base for i in t.vertices) for t in me.loop_triangles]
        ev.to_mesh_clear()
    return verts, tris


def bvh(objs):
    v, t = world_tris(objs)
    return BVHTree.FromPolygons(v, t), v, t


PANE = [bpy.data.objects[n] for n in S["pane"]]
BAND = [bpy.data.objects[n] for n in S["band"]]
pane_bvh, PV, PT = bvh(PANE)
glass_bvh, GV, GT = bvh(PANE + BAND)
scut = bpy.data.objects[S["scuttle"]]
scut_bvh, _, _ = bvh([scut])


def outer_edges():
    """Glass boundary edges that are not the seam between the pane and the band."""
    bv, bt = world_tris(BAND)
    cnt = {}
    for a, b, c in bt:
        for e in ((a, b), (b, c), (c, a)):
            k = tuple(sorted(e))
            cnt[k] = cnt.get(k, 0) + 1
    pv = np.array([list(p) for p in PV])
    segs = []
    for (a, b), n in cnt.items():
        if n != 1:
            continue
        pa, pb = np.array(list(bv[a])), np.array(list(bv[b]))
        near_a = np.linalg.norm(pv - pa, axis=1).min() < 0.002
        near_b = np.linalg.norm(pv - pb, axis=1).min() < 0.002
        if not (near_a and near_b):
            segs.append((pa, pb))
    return np.array([s[0] for s in segs]), np.array([s[1] for s in segs])


OA, OB = outer_edges()


def edge_dist(pts):
    P = np.array([list(p) for p in pts])
    ab = OB - OA
    ap = P[:, None, :] - OA[None]
    t = np.clip((ap * ab[None]).sum(-1) / (ab * ab).sum(-1)[None], 0, 1)
    return np.linalg.norm(ap - t[..., None] * ab[None], axis=-1).min(1)


def down_hit(x, y, tree):
    hit = tree.ray_cast(Vector((x, y, 5.0)), Vector((0, 0, -1)))
    return hit[0]


def pane_point_at_z(x, z, ys):
    best = None
    for y in ys:
        p = down_hit(x, y, pane_bvh)
        if p is not None and (best is None or abs(p.z - z) < abs(best.z - z)):
            best = p
    return best


def pane_lowest(x, up, ys):
    pts = [p for p in (down_hit(x, y, pane_bvh) for y in ys) if p is not None]
    zl = min(p.z for p in pts)
    return min(pts, key=lambda p: abs(p.z - (zl + up)))


ys_fine = np.linspace(S["search_y"][0], S["search_y"][1], 701)
OUTER = pane_point_at_z(S["parked_outer"]["x"], S["parked_outer"]["z"], ys_fine)
if "z" in S["parked_inner"]:
    INNER_AIM = pane_point_at_z(S["parked_inner"]["x"], S["parked_inner"]["z"], ys_fine)
else:
    INNER_AIM = pane_lowest(S["parked_inner"]["x"], S["parked_inner"]["up_m"], ys_fine)
sp = down_hit(S["pivot_xy"][0], S["pivot_xy"][1], scut_bvh)
if sp is None:
    raise SystemExit(f"no scuttle under the pivot {S['pivot_xy']}")
PIVOT = sp + Vector((0, 0, S["boss_height_m"]))
report["scuttle_under_pivot"] = list(sp)


def base_normal():
    """Inward glass normal at the pane's lowest point nearest the pivot."""
    loc, nrm, _, _ = pane_bvh.find_nearest(PIVOT)
    if nrm.z > 0:
        nrm = -nrm
    return nrm.normalized()


A0 = base_normal()
UPG = Vector((0, 0, 1)) - A0 * A0.z
UPG.normalize()


def tilted(tx, ty):
    q = Matrix.Rotation(math.radians(ty), 3, UPG) @ Matrix.Rotation(math.radians(tx), 3, Vector((1, 0, 0)))
    return (q @ A0).normalized()


def frame(a):
    e1 = Vector((-1, 0, 0)) + a * a.x
    e1.normalize()
    return e1, a.cross(e1)


def heights(a, rho, alpha, tree):
    """Glass height along w = -a above the pivot plane at polar points, None where no glass."""
    e1, e2 = frame(a)
    w = -a
    out = []
    for r, al in zip(rho, alpha):
        p = PIVOT + (e1 * math.cos(al) + e2 * math.sin(al)) * r
        hit = tree.ray_cast(p - w * 0.5, w, 1.0)
        out.append(None if hit[0] is None else hit[3] - 0.5)
    return out


def parked_polar(a, n):
    e1, e2 = frame(a)
    po, pg = OUTER - PIVOT, INNER_AIM - PIVOT
    o2 = Vector((po.dot(e1), po.dot(e2)))
    g2 = Vector((pg.dot(e1), pg.dot(e2)))
    d = (g2 - o2).normalized()
    i2 = o2 + d * S["blade_length_m"] * 0.985
    s = np.linspace(0, 1, n)
    pts = [i2.lerp(o2, float(k)) for k in s]
    return [p.length for p in pts], [math.atan2(p.y, p.x) for p in pts]


def sweep(a, n, theta_max=None):
    rho, psi = parked_polar(a, n)
    e1, e2 = frame(a)
    w = -a
    H, thetas, shares = [], [], []
    for deg in range(0, 181):
        th = math.radians(deg)
        if theta_max is not None and deg > theta_max + 1e-9:
            break
        al = [p + th for p in psi]
        h = heights(a, rho, al, glass_bvh)
        if any(x is None for x in h):
            break
        pts = [PIVOT + (e1 * math.cos(x) + e2 * math.sin(x)) * r + w * hh for r, x, hh in zip(rho, al, h)]
        if theta_max is None and deg > 30 and edge_dist(pts).min() < S["edge_margin_m"]:
            break
        hp = heights(a, rho, al, pane_bvh)
        shares.append(sum(x is not None for x in hp) / n)
        H.append(h)
        thetas.append(deg)
    if not H:  # the parked blade is not wholly over the glass for this axis: not a candidate
        return None
    H = np.array(H)
    env = H.max(0) + S["blade_clear_m"]
    gap = env[None] - H
    return {"rho": rho, "psi": psi, "H": H, "env": env, "gap": gap, "end_deg": thetas[-1], "shares": shares}


def score(a):
    r = sweep(a, 21)
    return (float("inf"), -1) if r is None else (r["gap"].max(), r["end_deg"])


best = None
lo, hi = S["tilt_search_deg"]
grid = [(tx, ty) for tx in range(lo, hi + 1, 4) for ty in range(lo, hi + 1, 4)]
for step in (4, 1, 0.5):
    results = []
    for tx, ty in grid:
        g, e = score(tilted(tx, ty))
        if e >= S["min_sweep_deg"]:
            results.append((g, tx, ty, e))
    results.sort()
    if not results:
        raise SystemExit("no axis tilt sweeps min_sweep_deg")
    best = results[0]
    if step == 0.5:
        break
    nxt = 1 if step == 4 else 0.5
    span = 3 if step == 4 else 1
    grid = sorted({(best[1] + i * nxt, best[2] + j * nxt) for i in range(-span, span + 1) for j in range(-span, span + 1)}
                  | {(r[1] + i * nxt, r[2] + j * nxt) for r in results[1:3] for i in range(-span, span + 1)
                     for j in range(-span, span + 1)})
AXIS = tilted(best[1], best[2])
if BREAK == "sign":
    AXIS_USED = -AXIS
else:
    AXIS_USED = AXIS
fit = sweep(AXIS, N_FIT)
RANGE_DEG = S.get("range_deg") or fit["end_deg"]
report["fit"] = {"tilt_deg": [best[1], best[2]], "sweep_end_deg": fit["end_deg"], "range_deg": RANGE_DEG,
                 "worst_gap_mm": float(fit["gap"].max() * 1e3), "p95_gap_mm": float(np.percentile(fit["gap"], 95) * 1e3),
                 "mean_gap_mm": float(fit["gap"].mean() * 1e3),
                 "gap_by_radius_max_mm": [round(float(x) * 1e3, 1) for x in fit["gap"].max(0)],
                 "clear_pane_share_by_deg": [round(x, 3) for x in fit["shares"]],
                 "base_normal": list(A0), "parked_outer_aim": list(OUTER), "parked_inner_aim": list(INNER_AIM)}

# ---------------------------------------------------------------------------------------------- build
e1, e2 = frame(AXIS)
w = -AXIS
rho_f, psi_f, env_f = fit["rho"], fit["psi"], fit["env"]
if BREAK == "clear":
    env_f = env_f - 0.006


def blade_point(t, lift=0.0, side=0.0):
    """Point on the parked rubber edge's line, t 0 (inner) .. 1 (outer), lifted along w, moved across it."""
    x = t * (N_FIT - 1)
    k = min(int(x), N_FIT - 2)
    f = x - k
    r = rho_f[k] * (1 - f) + rho_f[k + 1] * f
    al = psi_f[k] * (1 - f) + psi_f[k + 1] * f
    h = env_f[k] * (1 - f) + env_f[k + 1] * f
    base = PIVOT + (e1 * math.cos(al) + e2 * math.sin(al)) * r + w * (h + lift)
    p_in = PIVOT + (e1 * math.cos(psi_f[0]) + e2 * math.sin(psi_f[0])) * rho_f[0]
    p_out = PIVOT + (e1 * math.cos(psi_f[-1]) + e2 * math.sin(psi_f[-1])) * rho_f[-1]
    along = (p_out - p_in).normalized()
    across = w.cross(along).normalized()
    return base + across * side, along, across


def ring_sweep(rings):
    """Faces joining consecutive rings of equal size, closed round, capped at both ends."""
    verts, faces = [], []
    m = len(rings[0])
    for r in rings:
        verts += r
    for i in range(len(rings) - 1):
        for k in range(m):
            a, b = i * m + k, i * m + (k + 1) % m
            faces.append((a, b, b + m, a + m))
    faces.append(tuple(range(m - 1, -1, -1)))
    last = (len(rings) - 1) * m
    faces.append(tuple(range(last, last + m)))
    return verts, faces


parts = {}
# rubber edge: 4 mm wide, 6 mm tall, its lowest line on the envelope
rings = []
for t in np.linspace(0, 1, N_MESH):
    p, along, across = blade_point(float(t))
    rings.append([p + across * 0.0008, p + across * 0.002 + w * 0.006, p - across * 0.002 + w * 0.006,
                  p - across * 0.0008])
parts["rubber"] = [ring_sweep(rings)]
# frame/spoiler: a tapered six-sided section over the rubber, ends drawn in
rings = []
ts = np.linspace(0.0, 1.0, N_MESH)
for t in ts:
    end = min(t, 1 - t)
    taper = 0.55 + 0.45 * min(1.0, end / 0.06)
    p, along, across = blade_point(float(t), 0.006)
    wd, ht = 0.011 * taper, 0.013 * taper
    rings.append([p + across * wd, p + across * wd * 0.8 + w * ht * 0.55, p + across * wd * 0.15 + w * ht,
                  p - across * wd * 0.6 + w * ht * 0.75, p - across * wd + w * ht * 0.2, p - across * wd * 0.7])
parts["blade_frame"] = [ring_sweep(rings)]
# clip block at the blade's middle
cp, along, across = blade_point(0.5, 0.006 + 0.012)
clip = []
for sx in (-1, 1):
    for sy in (-1, 1):
        for sz in (0, 1):
            clip.append(cp + along * sx * 0.016 + across * sy * 0.009 + w * sz * 0.012)
clip_f = [(0, 2, 6, 4), (1, 5, 7, 3), (0, 4, 5, 1), (2, 3, 7, 6), (0, 1, 3, 2), (4, 6, 7, 5)]
clip_top = cp + w * 0.012
# arm: from the head over the spindle to the clip, cranked to clear what it passes over the whole sweep
head_len = 0.065
arm_dir_p = (clip_top - PIVOT) - w * (clip_top - PIVOT).dot(w)
arm_dir = arm_dir_p.normalized()
r_clip = arm_dir_p.length
arm_side = w.cross(arm_dir)
samples_r = np.linspace(head_len, r_clip, 9)
psi_arm = math.atan2(arm_dir.dot(e2), arm_dir.dot(e1))
need = []
for r in samples_r:
    hs = []
    for deg in range(0, int(RANGE_DEG) + 1, 3):
        al = psi_arm + math.radians(deg)
        hh = heights(AXIS, [r] * 3, [al - 0.03, al, al + 0.03], glass_bvh)
        hs += [x for x in hh if x is not None]
    need.append(max(hs) if hs else -1.0)
head_top = 0.016
arm_h = []
for r, nd in zip(samples_r, need):
    straight = head_top + (r - head_len) / (r_clip - head_len) * ((clip_top - PIVOT).dot(w) - head_top)
    arm_h.append(max(straight, nd + 0.012))
arm_h[-1] = (clip_top - PIVOT).dot(w)
rings = []
for r, h in zip(samples_r, arm_h):
    f = (r - head_len) / (r_clip - head_len)
    wd, ht = 0.009 - 0.003 * f, 0.007 - 0.002 * f
    c = PIVOT + arm_dir * r + w * h
    rings.append([c + arm_side * wd, c + arm_side * wd + w * ht, c - arm_side * wd + w * ht, c - arm_side * wd,
                  c - arm_side * wd * 0.6 - w * ht * 0.3, c + arm_side * wd * 0.6 - w * ht * 0.3])
arm_v, arm_f = ring_sweep(rings)
# head: a block on the spindle reaching to the arm's start, and the nut
hb = []
for sx, sy, sz in ((-1, -1, 0), (1, -1, 0), (1, 1, 0), (-1, 1, 0), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)):
    along_r = -0.016 if sx < 0 else head_len + 0.004
    if sx < 0:
        hz = 0.002 if not sz else head_top
    else:
        hz = arm_h[0] - 0.004 if not sz else arm_h[0] + 0.008
    hb.append(PIVOT + arm_dir * along_r + arm_side * sy * 0.012 + w * hz)
hb_f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
nut = []
for z in (head_top, head_top + 0.007):
    for k in range(6):
        a = math.pi / 3 * k
        nut.append(PIVOT + (e1 * math.cos(a) + e2 * math.sin(a)) * 0.0075 + w * z)
nut_v, nut_f = ring_sweep([nut[:6], nut[6:]])
parts["arm"] = [(arm_v, arm_f), (hb, hb_f), (nut_v, nut_f), (clip, clip_f)]
# boss: static, from 6 mm under the scuttle up to 1 mm under the head
boss_rings = []
for z0 in (-(PIVOT - sp).dot(w) - 0.006, 0.001):
    boss_rings.append([PIVOT + (e1 * math.cos(2 * math.pi * k / 12) + e2 * math.sin(2 * math.pi * k / 12)) * 0.014 + w * z0
                       for k in range(12)])
boss_v, boss_f = ring_sweep(boss_rings)


def smooth_by_angle(bm, deg):
    """Faces smooth, an edge sharp where its two faces meet at more than `deg` (the glTF splits there)."""
    lim = math.radians(deg)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        e.smooth = not (len(e.link_faces) == 2 and e.link_faces[0].normal.angle(e.link_faces[1].normal, 0.0) > lim)


def make(name, groups, col, parent):
    verts, faces, mats = [], [], []
    slot_of = {}
    for set_name, geo in groups:
        slot = slot_of.setdefault(set_name, len(slot_of))
        for vv, ff in geo:
            base = len(verts)
            verts += [list(x) for x in vv]
            faces += [tuple(i + base for i in f) for f in ff]
            mats += [slot] * len(ff)
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.validate()
    me.polygons.foreach_set("material_index", mats)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    smooth_by_angle(bm, S.get("sharp_deg", 40))
    uvl = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        ax = max(range(3), key=lambda i: abs(f.normal[i]))
        i0, i1 = [i for i in range(3) if i != ax]
        for lp in f.loops:
            lp[uvl].uv = (lp.vert.co[i0] / 0.1, lp.vert.co[i1] / 0.1)
    bm.to_mesh(me)
    bm.free()
    for set_name in slot_of:
        me.materials.append(bpy.data.materials.get(set_name) or bpy.data.materials.new(set_name))
    o = bpy.data.objects.new(name, me)
    col.objects.link(o)
    if parent:
        o.parent = parent
        o.matrix_parent_inverse = parent.matrix_world.inverted()
    return o


for nm in (S["names"]["arm"], S["names"]["boss"]):
    if nm in bpy.data.objects:
        bpy.data.objects.remove(bpy.data.objects[nm])
col = bpy.data.collections[S["collection"]]
parent = bpy.data.objects.get(S["parent"])
M = S["materials"]
arm = make(S["names"]["arm"], [(M["arm"], parts["arm"]), (M["blade_frame"], parts["blade_frame"]),
                               (M["rubber"], parts["rubber"])], col, parent)
boss = make(S["names"]["boss"], [(M["boss"], [(boss_v, boss_f)])], col, parent)
bpy.context.view_layer.update()

# ---------------------------------------------------------------------------------------------- checks
new = {arm.name, boss.name}
cv, ct = world_tris([arm])
bound_lo = Vector([min(p[i] for p in cv) for i in range(3)])
bound_hi = Vector([max(p[i] for p in cv) for i in range(3)])
reach = max((p - PIVOT).length for p in cv) + 0.05
others = []
for o in sc.objects:
    if o.type != "MESH" or o.name in new or o.hide_render or not len(o.data.polygons):
        continue
    if any(cl.name.startswith("Replaced") for cl in o.users_collection):
        continue
    ob = [o.matrix_world @ Vector(x) for x in o.bound_box]
    if all(min(p[i] for p in ob) <= PIVOT[i] + reach and max(p[i] for p in ob) >= PIVOT[i] - reach for i in range(3)):
        others.append(o)
obs_v, obs_t, obs_owner = [], [], []
for o in others:
    v_, t_ = world_tris([o])
    base_ = len(obs_v)
    obs_v += v_
    obs_t += [tuple(i + base_ for i in t) for t in t_]
    obs_owner += [o.name] * len(t_)
obs_bvh = BVHTree.FromPolygons(obs_v, obs_t)



def pose(deg, axis):
    T = Matrix.Translation(PIVOT) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-PIVOT)
    vv = [T @ p for p in cv]
    pairs = BVHTree.FromPolygons(vv, ct).overlap(obs_bvh)
    near = [obs_bvh.find_nearest(p) for p in vv]
    k = min(range(len(vv)), key=lambda i: near[i][3])
    return vv, pairs, near[k][3], vv[k], obs_owner[near[k][2]]


# The range: the glass-limited sweep, cut back to the last whole degree at which the built part still keeps
# min_clear + 0.5 mm from the car (the inner end can meet the scuttle before the outer end meets the edge).
body_limit = None
if not S.get("range_deg"):
    for deg in range(0, int(fit["end_deg"]) + 1):
        _, pairs, dmin, _, _ = pose(deg, AXIS)
        if pairs or dmin < S["min_clear_m"] + 0.0005:
            body_limit = deg
            break
    if body_limit is not None:
        RANGE_DEG = max(0, body_limit - 2)
report["fit"]["body_limit_deg"] = body_limit
report["fit"]["range_deg"] = RANGE_DEG
end_deg = RANGE_DEG + (25 if BREAK == "edge" else 0)
steps = S["steps"]
rows = []
rho_m, psi_m = parked_polar(AXIS, N_FIT)
quad = S.get("quad")
for k in range(steps + 1):
    deg = end_deg * k / steps
    vv, pairs, dmin, near_p, near_name = pose(deg, AXIS_USED)
    crossings = len(pairs)
    hit_names = sorted({obs_owner[j] for _, j in pairs})
    al = [p + math.radians(deg) * (1 if BREAK != "sign" else -1) for p in psi_m]
    hg = heights(AXIS, rho_m, al, glass_bvh)
    hp = heights(AXIS, rho_m, al, pane_bvh)
    on_glass = sum(x is not None for x in hg) / N_FIT
    on_pane = sum(x is not None for x in hp) / N_FIT
    in_quad = None
    if quad:
        Q = [Vector(q) for q in quad]
        qn = (Q[1] - Q[0]).cross(Q[3] - Q[0]).normalized()
        inside = 0
        for r, a_ in zip(rho_m, al):
            p = PIVOT + (e1 * math.cos(a_) + e2 * math.sin(a_)) * r
            p = p - qn * (p - Q[0]).dot(qn)
            sgn = [((Q[(i + 1) % 4] - Q[i]).cross(p - Q[i])).dot(qn) for i in range(4)]
            inside += all(s >= 0 for s in sgn) or all(s <= 0 for s in sgn)
        in_quad = inside / N_FIT
    rows.append({"deg": round(deg, 2), "crossings": crossings, "crossed": hit_names,
                 "nearest": near_name, "nearest_at": [round(x, 4) for x in near_p],
                 "nearest_from_pivot_m": round((near_p - PIVOT).length, 3), "min_clear_mm": round(dmin * 1e3, 2),
                 "edge_on_glass": on_glass, "edge_on_clear_pane": round(on_pane, 3), "edge_in_quad": in_quad})
    if crossings:
        problems.append(f"{deg:.1f} deg: the arm crosses {hit_names} ({crossings} triangle pairs)")
    if dmin < S["min_clear_m"]:
        problems.append(f"{deg:.1f} deg: the arm is {dmin * 1e3:.2f} mm from the car (wants {S['min_clear_m'] * 1e3:.1f})")
    if on_glass < 1:
        problems.append(f"{deg:.1f} deg: {100 * (1 - on_glass):.0f} % of the rubber edge is off the glass")
report["steps"] = rows


def swept(p):
    """Whether the rubber edge passes over a point during the sweep (polar test in the plane across the axis)."""
    q = p - PIVOT
    r = math.hypot(q.dot(e1), q.dot(e2))
    al = math.atan2(q.dot(e2), q.dot(e1))
    for k in range(N_FIT - 1):
        r0, r1 = rho_m[k], rho_m[k + 1]
        if min(r0, r1) - 0.002 <= r <= max(r0, r1) + 0.002:
            f = 0.0 if r1 == r0 else (r - r0) / (r1 - r0)
            a0 = psi_m[k] + (psi_m[k + 1] - psi_m[k]) * min(1.0, max(0.0, f))
            d = (al - a0) % (2 * math.pi)
            if d <= math.radians(RANGE_DEG) + 1e-9:
                return True
    return False


if quad:
    Q = [Vector(q) for q in quad]
    hits = total = 0
    for i in range(61):
        for j in range(31):
            u_, v_ = i / 60, j / 30
            top = Q[0].lerp(Q[1], u_)
            bot = Q[3].lerp(Q[2], u_)
            p = top.lerp(bot, v_)
            total += 1
            hits += swept(p)
    report["quad_swept_share"] = hits / total
if S.get("eye"):
    eye = Vector(S["eye"])
    hit = glass_bvh.ray_cast(eye, Vector((0, -1, 0)))
    report["eye_level"] = {"eye": list(eye), "glass_point": list(hit[0]) if hit[0] else None,
                           "swept": bool(hit[0] is not None and swept(hit[0]))}
    downs = {}
    for deg_ in (1, 2, 3, 5, 8):
        dvec = Vector((0, -math.cos(math.radians(deg_)), -math.sin(math.radians(deg_))))
        h2 = glass_bvh.ray_cast(eye, dvec)
        downs[deg_] = bool(h2[0] is not None and swept(h2[0]))
    report["eye_level"]["swept_looking_down_deg"] = downs
report["near_objects"] = [o.name for o in others]


def man(v):
    return {"forward": round(-v.y, 5), "right": round(-v.x, 5), "up": round(v.z, 5)}


inner_edge = PIVOT + (e1 * math.cos(psi_f[0]) + e2 * math.sin(psi_f[0])) * rho_f[0] + w * env_f[0]
outer_edge = PIVOT + (e1 * math.cos(psi_f[-1]) + e2 * math.sin(psi_f[-1])) * rho_f[-1] + w * env_f[-1]
tri = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in (arm, boss)}
report["result"] = {
    "pivot": list(PIVOT), "axis": list(AXIS), "range_rad": math.radians(RANGE_DEG), "range_deg": RANGE_DEG,
    "positive": "lifts the blade off its park line along the screen's base, up across the driver's side",
    "blade_inner": list(inner_edge), "blade_outer": list(outer_edge),
    "blade_length_m": (outer_edge - inner_edge).length, "triangles": tri,
    "manifest": {"pivot": man(PIVOT), "axis": man(AXIS), "range": round(math.radians(RANGE_DEG), 5),
                 "Wiper_BladeInner": man(inner_edge), "Wiper_BladeOuter": man(outer_edge)}}
if tri[arm.name] > S.get("max_triangles", 1000):
    problems.append(f"{arm.name}: {tri[arm.name]} triangles, over {S.get('max_triangles', 1000)}")
if OUT:
    bpy.ops.wm.save_as_mainfile(filepath=OUT, compress=True)
if REPORT:
    Path(REPORT).write_text(json.dumps(report, indent=1, default=str))
print("WIPER fit tilt", report["fit"]["tilt_deg"], "glass sweep", report["fit"]["sweep_end_deg"], "body limit",
      body_limit, "range", RANGE_DEG,
      "worst gap %.1f mm, p95 %.1f" % (report["fit"]["worst_gap_mm"], report["fit"]["p95_gap_mm"]))
print("WIPER manifest", json.dumps(report["result"]["manifest"]))
print("WIPER triangles", tri)
print("WIPER quad swept share", report.get("quad_swept_share"), "eye level", json.dumps(report.get("eye_level")))
for r in rows[:: max(1, steps // 8)] + ([rows[-1]] if steps % max(1, steps // 8) else []):
    print("WIPER step", json.dumps(r))
print("WIPER", "PASS" if not problems else "FAIL", *problems[:12], sep="\n  ")
sys.exit(1 if problems else 0)
