"""Cut the rear bumper where the exhaust barrels pass through it, so the two never depth-fight.

blender -b <master.blend> --factory-startup --python-exit-code 1 -P tools/blender/dr458/exhaust_cut.py -- <out.blend> [--margin 0.002] [--break]

Nothing moves. For each barrel, a closed cutter is turned about the barrel's own long axis (its
principal axis) from the barrel's radius profile: in each slice along the axis, the largest radius of
the barrel's vertices near that slice plus --margin. The bumper takes an exact boolean difference
with each cutter (hole tolerant, the bumper being an open surface), so its new edge follows the
barrel 2 mm outside it. Verify: no bumper face centre is left inside a barrel's profile plus half the
margin, and nothing beyond 5 cm of every barrel moved (the same vertex positions there). --break skips the cut, so the verify fails and names the faces.
"""
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
out = args[0]
MARGIN = float(args[args.index("--margin") + 1]) if "--margin" in args else 0.002
BREAK = "--break" in args
BUMPER = "Rear bumper"
BARRELS = ("Rolled titanium exhaust barrel", "Rolled titanium exhaust barrel.001")
SLICES, SEGMENTS = 40, 64


def world_verts(o):
    mw = o.matrix_world
    return np.array([mw @ v.co for v in o.data.vertices])


def profile(o):
    v = world_verts(o)
    c = v.mean(0)
    vt = np.linalg.svd(v - c, full_matrices=False)[2]
    ax = vt[int(np.argmax(np.abs(vt[:, 1])))]  # the barrels run fore and aft (Blender y)
    t = (v - c) @ ax
    r = np.linalg.norm((v - c) - np.outer(t, ax), axis=1)
    lo, hi = t.min() - MARGIN, t.max() + MARGIN
    ts = np.linspace(lo, hi, SLICES)
    half = (hi - lo) / (SLICES - 1) * 1.5
    rs = np.array([r[np.abs(t - x) <= half].max() if np.any(np.abs(t - x) <= half) else r.max() for x in ts]) + MARGIN
    return c, ax, ts, rs


def inside(points, prof, extra):
    c, ax, ts, rs = prof
    t = (points - c) @ ax
    r = np.linalg.norm((points - c) - np.outer(t, ax), axis=1)
    lim = np.interp(t, ts, rs) - MARGIN + extra
    return (t >= ts[0] - extra) & (t <= ts[-1] + extra) & (r < lim)


def cutter(name, prof):
    c, ax, ts, rs = prof
    a = Vector(ax)
    u = a.orthogonal().normalized()
    w = a.cross(u).normalized()
    bm = bmesh.new()
    rings = []
    for x, rad in zip(ts, rs):
        centre = Vector(c) + a * float(x)
        rings.append([bm.verts.new(centre + (u * np.cos(k * 2 * np.pi / SEGMENTS) + w * np.sin(k * 2 * np.pi / SEGMENTS)) * float(rad))
                      for k in range(SEGMENTS)])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(SEGMENTS):
            bm.faces.new((r0[k], r0[(k + 1) % SEGMENTS], r1[(k + 1) % SEGMENTS], r1[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


bump = bpy.data.objects[BUMPER]
profs = [profile(bpy.data.objects[n]) for n in BARRELS]


def centres(o):
    mw = o.matrix_world
    return np.array([mw @ f.center for f in o.data.polygons])


def far_verts(o):
    """Vertex positions (0.1 mm) beyond 5 cm of every barrel: a cut that stays at the barrels leaves them all."""
    mw = o.matrix_world
    v = np.array([mw @ x.co for x in o.data.vertices])
    far = np.ones(len(v), bool)
    for p in profs:
        far &= ~inside(v, p, 0.05)
    return {tuple(x) for x in np.round(v[far] * 10000).astype(np.int64)}


faces_before, tris_before = len(bump.data.polygons), sum(len(f.vertices) - 2 for f in bump.data.polygons)
far_before = far_verts(bump)
inside_before = [int(inside(centres(bump), p, 0).sum()) for p in profs]
if not BREAK:
    cutters = [cutter(f"EXHAUST_CUTTER_{i}", p) for i, p in enumerate(profs)]
    for i, cu in enumerate(cutters):
        m = bump.modifiers.new(f"exhaust_cut_{i}", "BOOLEAN")
        m.operation, m.solver, m.object = "DIFFERENCE", "EXACT", cu
        m.use_hole_tolerant, m.use_self = True, False
        bpy.context.view_layer.objects.active = bump
        bpy.ops.object.modifier_move_to_index(modifier=m.name, index=0)
        bpy.ops.object.modifier_apply(modifier=m.name)
    for cu in cutters:
        bpy.data.objects.remove(cu, do_unlink=True)
    # Hole tolerant on an open surface, the boolean keeps the cutter's own faces where they fall inside the
    # bumper's winding (its forward caps): a face with every vertex on a cutter's cap or wall is the cutter's.
    mw = bump.matrix_world
    vs = np.array([mw @ x.co for x in bump.data.vertices])
    on = {"cap": np.zeros(len(vs), bool), "wall": np.zeros(len(vs), bool)}
    tol = 1e-4
    for c, ax, ts, rs in profs:
        t = (vs - c) @ ax
        r = np.linalg.norm((vs - c) - np.outer(t, ax), axis=1)
        within = (t > ts[0] - tol) & (t < ts[-1] + tol)
        on["cap"] |= ((np.abs(t - ts[0]) < tol) | (np.abs(t - ts[-1]) < tol)) & (r < np.interp(t, ts, rs) + tol)
        on["wall"] |= within & (np.abs(r - np.interp(t, ts, rs)) < tol + float(rs.max()) * (1 - np.cos(np.pi / SEGMENTS)))
    bm = bmesh.new()
    bm.from_mesh(bump.data)
    junk = {"cap": [], "wall": []}
    for f in bm.faces:
        ids = [v.index for v in f.verts]
        for kind in ("cap", "wall"):
            if all(on[kind][i] for i in ids):
                junk[kind].append(f)
                break
    bmesh.ops.delete(bm, geom=junk["cap"] + junk["wall"], context="FACES")
    bm.to_mesh(bump.data)
    bm.free()
    print(f"EXHAUST_CUT removed the cutter's own faces kept by the boolean: {len(junk['cap'])} on its caps, {len(junk['wall'])} on its walls")

fc = centres(bump)
left = [int(inside(fc, p, MARGIN / 2).sum()) for p in profs]
far_after = far_verts(bump)
for i, p in enumerate(profs):
    c, ax, ts, rs = p
    for k in np.where(inside(fc, p, MARGIN / 2))[0]:
        f = bump.data.polygons[int(k)]
        t = float((fc[k] - c) @ ax)
        r = float(np.linalg.norm((fc[k] - c) - t * ax))
        print(f"EXHAUST_CUT left barrel {i} face {k}: t {t:.4f} (cutter {ts[0]:.4f}..{ts[-1]:.4f}), r {r:.4f} "
              f"(cutter {np.interp(t, ts, rs):.4f}), area {f.area * 1e4:.2f} cm2, {len(f.vertices)} verts")
tris_after = sum(len(f.vertices) - 2 for f in bump.data.polygons)
problems = []
if any(left):
    problems.append(f"bumper faces left inside a barrel's profile + {MARGIN / 2 * 1000:.1f} mm: {left}")
if far_after != far_before:
    problems.append(f"vertices beyond 5 cm of the barrels changed: {len(far_before - far_after)} gone, {len(far_after - far_before)} new")
print(f"EXHAUST_CUT bumper faces {faces_before} -> {len(bump.data.polygons)}, tris {tris_before} -> {tris_after}; "
      f"inside before {inside_before}, left {left}; far vertices {len(far_before)} -> {len(far_after)}; "
      f"barrel radius {[round(float(p[3].min() - MARGIN), 4) for p in profs]}..{[round(float(p[3].max() - MARGIN), 4) for p in profs]} m")
print("EXHAUST_CUT", "PASS" if not problems else "FAIL", *problems, sep="\n  ")
if problems:
    sys.exit(1)
bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
print("EXHAUST_CUT saved", out)
