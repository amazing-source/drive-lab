"""Back the master's faces that the driver sees from behind, so Roblox's single-sided parts show no sky.

blender -b <assembled car.blend> --factory-startup -P tools/blender/dr458/backing.py -- find <faces.json> <manifest.json> [--skip a,b] [--min-px 4]
blender -b <master.blend> --factory-startup -P tools/blender/dr458/backing.py -- apply <faces.json> <out.blend>

find: from the cockpit eye moved over EYE_RANGE (forward -0.15..0.12 m, up -0.05..0.15 m, 3 x 3, as
Config/CarCamera) within the look-around reach, a master face is seen from behind when one of its
points (its centre, and each corner pulled a fifth of the way in) faces away from the eye and no
front face of any part (cockpit parts included, glass excluded since it is transparent) lies in
front of it and none right behind it (within 2 mm along the ray: the eye sees that surface, and a
copy there would depth-fight it); a face whose centre has a front face within 2 mm either side is
skipped whole, since a copy of a face half over another surface fights it there. Roblox culls the face, so the driver sees through it. A face is kept when, from one
eye, its share of open points times its area seen at that angle reaches --min-px pixels at 1080p and
a 60-degree vertical field (a sliver behind a gap costs triangles and shows nothing). Glass and lenses are skipped
(one sees through them anyway), and so are objects named in --skip.
apply: each listed face gets a copy with reversed winding in its own object (same material and
UVs), so a door's backing moves with the door. The copy and the face are back to back: whichever
the camera faces is drawn, the other is culled, so they cannot depth-fight.
"""
import json
import math
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

args = sys.argv[sys.argv.index("--") + 1:]
mode = args[0]
MASTER = ("Body", "Cabin", "Doors", "Engine", "Evo", "Glass", "Lights", "Wheels", "Unsorted")
GLASS = ("_glass", "_window_", "glassLHL", "glassRHL", "glassLTL", "glassRTL", "Glass_", "Lens", "lens")


def live():
    return [o for o in bpy.context.scene.objects if o.type == "MESH" and not o.hide_render and len(o.data.polygons)
            and not any(c.name.startswith("Replaced") for c in o.users_collection)]


def is_master(o):
    return any(c.name in MASTER for c in o.users_collection)


def is_glass(o):
    return any(s in o.name for s in GLASS)


if mode == "find":
    out, manifest = args[1], args[2]
    skip = set(args[args.index("--skip") + 1].split(",")) if "--skip" in args else set()
    min_px = float(args[args.index("--min-px") + 1]) if "--min-px" in args else 4.0
    px_sr = (math.radians(60) / 1080) ** 2
    objs = live()
    T, own = [], []
    for k, o in enumerate(objs):
        me = o.data
        me.calc_loop_triangles()
        v = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", v)
        M = np.array(o.matrix_world)
        v = v.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3]
        t = np.empty(len(me.loop_triangles) * 3, np.int64)
        me.loop_triangles.foreach_get("vertices", t)
        T.append(v[t.reshape(-1, 3)])
        own.append(np.full(len(t) // 3, k))
    T, own = np.concatenate(T), np.concatenate(own)
    nrm = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1), 1e-12)[:, None]
    glass = np.array([is_glass(o) for o in objs])
    bvh = BVHTree.FromPolygons([tuple(p) for p in T.reshape(-1, 3)], [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(T))], epsilon=0.0)
    e = json.load(open(manifest))["points"]["Driver_Eye"]
    eye0 = Vector((-e["right"], -e["forward"], e["up"]))
    eyes = [eye0 + Vector((0, -f, u)) for f in (-0.15, 0.0, 0.12) for u in (-0.05, 0.05, 0.15)]
    reach_yaw = math.radians(110) + math.atan(math.tan(math.radians(30)) * 16 / 9)
    reach_pitch = math.radians(70)

    def covered(eye, p):
        """True when a front face lies within 2 mm of p along the ray, in front of it or behind it."""
        d = p - eye
        dist = d.length
        d.normalize()
        o, gone = eye.copy(), 0.0
        for _ in range(64):
            loc, _n, fi, h = bvh.ray_cast(o, d, dist - gone + 0.002)
            if loc is None:
                return False
            gone += h + 1e-5
            if not glass[own[fi]] and float(nrm[fi] @ np.asarray(d)) < 0 and gone >= dist - 0.002:
                return True
            o = loc + d * 1e-5
        return False

    def in_reach(eye, p):
        d = p - eye
        return abs(math.atan2(d.x, -d.y)) <= reach_yaw and abs(math.atan2(d.z, math.hypot(d.x, d.y))) <= reach_pitch

    def open_line(eye, p):
        """True when no front face (glass aside) lies between the eye and p, nor within 2 mm behind it."""
        d = p - eye
        dist = d.length
        d.normalize()
        o, gone = eye.copy(), 0.0
        for _ in range(64):
            loc, _n, fi, h = bvh.ray_cast(o, d, dist - gone + 0.002)
            if loc is None:
                return True
            gone += h + 1e-5
            if glass[own[fi]] or float(nrm[fi] @ np.asarray(d)) >= 0:
                o = loc + d * 1e-5
                continue
            return False
        return False

    found, stats = {}, {}
    for o in objs:
        if not is_master(o) or is_glass(o) or o.name in skip:
            continue
        mw = o.matrix_world
        nm = mw.to_3x3().inverted().transposed()
        faces = []
        for f in o.data.polygons:
            c = mw @ f.center
            n = (nm @ f.normal).normalized()
            pts = [c] + [c.lerp(mw @ o.data.vertices[vi].co, 0.8) for vi in f.vertices]
            area = f.area * mw.to_3x3().determinant() ** (2 / 3)
            for eye in eyes:
                to_eye = eye - c
                if n.dot(to_eye) >= 0 or to_eye.length > 4.0:
                    continue
                if covered(eye, c):
                    continue
                share = sum(1 for p in pts if n.dot(eye - p) < 0 and in_reach(eye, p) and open_line(eye, p)) / len(pts)
                if share and share * area * abs(n.dot(to_eye.normalized())) / to_eye.length_squared / px_sr >= min_px:
                    faces.append(f.index)
                    break
        if faces:
            area = sum(o.data.polygons[i].area for i in faces) * 1e4
            tris = sum(len(o.data.polygons[i].vertices) - 2 for i in faces)
            zs = [(mw @ o.data.polygons[i].center).z for i in faces]
            ys = [(mw @ o.data.polygons[i].center).y for i in faces]
            found[o.name] = faces
            stats[o.name] = {"faces": len(faces), "tris": tris, "cm2": round(area, 1), "z": [round(min(zs), 3), round(max(zs), 3)],
                             "y": [round(min(ys), 3), round(max(ys), 3)], "collection": o.users_collection[0].name}
        print("BACKING scanned", o.name, len(faces), flush=True)
    json.dump({"eyes": [list(x) for x in eyes], "skip": sorted(skip), "min_px": min_px, "faces": found, "stats": stats}, open(out, "w"), indent=1)
    print("BACKING found", sum(s["tris"] for s in stats.values()), "triangles in", len(stats), "objects")
    for k, s in sorted(stats.items(), key=lambda r: -r[1]["cm2"]):
        print(f"BACKING {s['tris']:6d} tris {s['cm2']:8.1f} cm2  {k}  z {s['z']} y {s['y']}")
elif mode == "apply":
    src, out = args[1], args[2]
    data = json.load(open(src))
    added = {}
    for name, idxs in data["faces"].items():
        o = bpy.data.objects[name]
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.faces.ensure_lookup_table()
        geom = bmesh.ops.duplicate(bm, geom=[bm.faces[i] for i in idxs])["geom"]
        new = [g for g in geom if isinstance(g, bmesh.types.BMFace)]
        bmesh.ops.reverse_faces(bm, faces=new, flip_multires=False)
        added[name] = sum(len(f.verts) - 2 for f in new)
        bm.to_mesh(o.data)
        bm.free()
        o.data.update()
    tot = {c.name: sum(len(p.vertices) - 2 for o in c.objects if o.type == "MESH" for p in o.data.polygons)
           for c in bpy.data.collections if not c.name.startswith("Replaced")}
    bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
    print("BACKING applied", sum(added.values()), "triangles:", json.dumps(added))
    print("BACKING collections", json.dumps(tot), "total", sum(tot.values()))
