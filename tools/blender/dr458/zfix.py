"""Resolve depth fighting left after clean_v11.py, pair by pair, with the scan's own test.

blender -b <budgeted master.blend> --factory-startup -P tools/blender/dr458/zfix.py -- <out.blend> <report.json>

Test (as tools/blender/dr458/zfight_scan.py, own seed): an area sample fights when another object's face lies
within 1.5 mm, facing the same way (normals within 25 degrees), along the sample's normal (at most
0.3 mm to the side, so a seam where two panels only meet is not a fight).
Cabin_InnerSkin (a filler copied 3 mm inside the body) never moves: sunk, its outline left the door
frames and the roof trims it meets and opened slits seen from the seat. Where it fights, only its
faces lying entirely within 2 mm of the other surface are deleted (that surface already covers the
shell there), except under the driver's door, which opens; what it fights over a partial face, or
under that door, stays and is reported.
Per other pair over 1 cm2 the overlay moves and the other surface stays: the overlay is the object
whose fighting share of its own area is larger (a stitch line, a trim strip, a lamp rim), except
that body_metal_ (the door-sill scuff plate with the wordmark, which the unbadged car drops) is
always the one to move, and always sinks. Otherwise the
signed offset (overlay minus other, along the overlay's normal, averaged over its fighting samples)
decides: in front or level, the overlay's fighting faces lift 2.5 mm and the other's faces lying
entirely within 2 mm of it (hidden behind it) are deleted; behind, the overlay sinks 2.5 mm. A
vertex moves along the mean normal of its fighting faces, at most twice (5 mm). Moving the overlay
works whatever the other surface's tessellation: a narrow strip over large faces has no vertex of
the other surface under it to move.
Pairs whose fighting samples sit on both sides (surfaces crossing at a shallow angle) are counted
as crossings in the report.
All changes of a pass come from that pass's scan and are applied together. Pairs inside the Wheels
collection are listed, not touched (a spinning tyre against a static caliper is a fit question).
Glass and lenses: what lies behind glass stays visible through it, so nothing under glass is ever
deleted, and glass never sinks. Glass in front of an opaque surface lifts; glass that also fights
another glass layer stays put (a frit band moved between the clear glass and the surround bounced
from one to the other pass after pass and opened a strip of sky along the windscreen's top).
A skin pair left after the skin's own deletion is treated as any pair, with the skin staying.
Repeats until no treatable pair is over 1 cm2, at most 8 passes.
"""
import json
import math
import sys
import time

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

out_blend, out_json = sys.argv[sys.argv.index("--") + 1:][:2]
T0 = time.time()
DIST, COS, LATERAL, SAMPLE_CM2, MAX_SAMPLES, LIMIT = 0.0015, math.cos(math.radians(25)), 0.0003, 0.5, 40000, 1.0
GONE_MM, SINK, PASSES = 0.002, 0.0025, 8
LOSERS = ("body_metal_",)
YIELDS = ("Cabin_InnerSkin",)
OPENS = ("doorLF_", "glassLF", "mirrorL_", "Door_L")  # the driver's door swings open: never delete what it covers
rng = np.random.default_rng(37)
report = {"passes": [], "skipped_wheels": []}


def log(*a):
    print(f"ZFIX {time.time() - T0:7.1f}s", *a, flush=True)


def live():
    return [o for c in bpy.data.collections if not c.name.startswith("Replaced")
            for o in c.objects if o.type == "MESH" and not o.hide_render and len(o.data.polygons)]


def scan():
    cur = live()
    T, own, poly = [], [], []
    for k, o in enumerate(cur):
        me = o.data
        me.calc_loop_triangles()
        v = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", v)
        M = np.array(o.matrix_world)
        v = v.reshape(-1, 3) @ M[:3, :3].T + M[:3, 3]
        t = np.empty(len(me.loop_triangles) * 3, np.int64)
        me.loop_triangles.foreach_get("vertices", t)
        pi = np.empty(len(me.loop_triangles), np.int64)
        me.loop_triangles.foreach_get("polygon_index", pi)
        T.append(v[t.reshape(-1, 3)])
        own.append(np.full(len(pi), k))
        poly.append(pi)
    T, own, poly = np.concatenate(T), np.concatenate(own), np.concatenate(poly)
    nrm = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
    area = 0.5 * np.linalg.norm(nrm, axis=1)
    nrm /= np.maximum(2 * area, 1e-12)[:, None]
    bvh = BVHTree.FromPolygons([tuple(p) for p in T.reshape(-1, 3)], [(3 * i, 3 * i + 1, 3 * i + 2) for i in range(len(T))], epsilon=0.0)
    pair_area, fight, offset, sides = {}, {}, {}, {}
    for k in range(len(cur)):
        idx = np.where(own == k)[0]
        a = area[idx]
        if a.sum() <= 0:
            continue
        n = int(min(MAX_SAMPLES, max(50, a.sum() * 1e4 / SAMPLE_CM2)))
        pick = idx[rng.choice(len(idx), n, p=a / a.sum())]
        r1, r2 = np.sqrt(rng.random(n)), rng.random(n)
        pts = (1 - r1)[:, None] * T[pick, 0] + (r1 * (1 - r2))[:, None] * T[pick, 1] + (r1 * r2)[:, None] * T[pick, 2]
        w = a.sum() * 1e4 / n
        for p, ti in zip(pts, pick):
            seen = set()
            for loc, _nr, fi, _d in bvh.find_nearest_range(Vector(p), DIST):
                j = int(own[fi])
                if j == k or j in seen or float(nrm[fi] @ nrm[ti]) < COS:
                    continue
                dv = p - np.asarray(loc)
                if np.linalg.norm(dv - (dv @ nrm[ti]) * nrm[ti]) > LATERAL:
                    continue
                seen.add(j)
                pair_area[(k, j)] = pair_area.get((k, j), 0.0) + w
                fight.setdefault((k, j), set()).add(int(poly[ti]))
                off = float(dv @ nrm[ti])
                offset[(k, j)] = offset.get((k, j), 0.0) + off
                sd = sides.setdefault((k, j), [0, 0, 0])
                sd[0 if off > 0.0003 else 1 if off < -0.0003 else 2] += 1
    total = {k: float(area[own == k].sum() * 1e4) for k in range(len(cur))}
    return cur, pair_area, fight, total, offset, sides


def obj_bvh(o):
    mw = o.matrix_world
    return BVHTree.FromPolygons([mw @ v.co for v in o.data.vertices], [list(p.vertices) for p in o.data.polygons])


def loser(o):
    return any(s in o.name for s in LOSERS)


def yields(o):
    return o.name in YIELDS


def glassy(o):
    n = o.name.lower()
    return "glass" in n or "_window_" in n or "lens" in n


MOVES = {}
YIELDED = set()
report["yield_kept"] = []
for npass in range(PASSES + 1):
    cur, pair_area, fight, total, offset, sides = scan()
    over = sorted(((a, b, v) for (a, b), v in pair_area.items() if v > LIMIT), key=lambda r: -r[2])
    wheels = [(a, b, v) for a, b, v in over if cur[a].users_collection[0].name == "Wheels" and cur[b].users_collection[0].name == "Wheels"]
    glass = [(a, b, v) for a, b, v in over if glassy(cur[a]) or glassy(cur[b])]
    sandwiched = {k for a, b, _v in glass if glassy(cur[a]) and glassy(cur[b]) for k in (a, b)}
    todo = [r for r in over if r not in wheels and not (glassy(cur[r[0]]) and glassy(cur[r[1]]))
            and not (r in glass and (r[0] in sandwiched or r[1] in sandwiched))]
    if npass:
        report["yield_kept"] = [{"a": cur[a].name, "b": cur[b].name, "cm2": round(v, 1)} for a, b, v in over
                                if frozenset((cur[a].name, cur[b].name)) in YIELDED]
    log(f"pass {npass}: {len(over)} sampled pairs over {LIMIT} cm2 ({len(wheels)} inside Wheels, not treated)")
    entry = {"pass": npass, "pairs_over": len(over), "wheels_pairs": len(wheels),
             "top": [{"a": cur[a].name, "b": cur[b].name, "cm2": round(v, 1)} for a, b, v in over[:30]], "treated": []}
    report["passes"].append(entry)
    if npass == 0:
        report["skipped_wheels"] = [{"a": cur[a].name, "b": cur[b].name, "cm2": round(v, 1)} for a, b, v in wheels]
        report["skipped_glass"] = [{"a": cur[a].name, "b": cur[b].name, "cm2": round(v, 1)} for a, b, v in glass]
    if not todo or npass == PASSES:
        break
    deletions, moves, done = {}, {}, set()
    for a, b, _v in todo:
        key = frozenset((a, b))
        if key in done:
            continue
        done.add(key)
        forced = None
        if (yields(cur[a]) or yields(cur[b])) and frozenset((cur[a].name, cur[b].name)) in YIELDED:
            forced = (b, a) if yields(cur[a]) else (a, b)
        elif glassy(cur[a]) != glassy(cur[b]):
            forced = (a, b) if glassy(cur[a]) else (b, a)
        if forced is None and (yields(cur[a]) or yields(cur[b])):
            sk, ot = (a, b) if yields(cur[a]) else (b, a)
            S, N = cur[sk], cur[ot]
            gone = []
            if not any(s in N.name for s in OPENS) and not glassy(N):
                nt = obj_bvh(N)
                mw = S.matrix_world
                gone = [i for i in fight.get((sk, ot), set())
                        if all(nt.find_nearest(p, GONE_MM)[0] is not None
                               for p in [mw @ S.data.polygons[i].center] + [mw @ S.data.vertices[vi].co for vi in S.data.polygons[i].vertices])]
            deletions.setdefault(sk, set()).update(gone)
            YIELDED.add(frozenset((S.name, N.name)))
            entry["treated"].append({"yields": S.name, "covered_by": N.name, "faces_deleted": len(gone),
                                     "fighting_faces": len(fight.get((sk, ot), ()))})
            continue
        sa = pair_area.get((a, b), 0.0) / max(total[a], 1e-9)
        sb = pair_area.get((b, a), 0.0) / max(total[b], 1e-9)
        mov, oth = (a, b) if sa >= sb else (b, a)
        if loser(cur[oth]) and not loser(cur[mov]):
            mov, oth = oth, mov
        if forced is not None:
            mov, oth = forced
        M, N = cur[mov], cur[oth]
        nfs = sum(sides.get((mov, oth), [0, 0, 0]))
        front = (not loser(M)) and offset.get((mov, oth), 0.0) >= 0.0
        if glassy(M) and not front:
            entry["treated"].append({"glass_behind_left": M.name, "over": N.name})
            continue
        sd = sides.get((mov, oth), [0, 0, 0])
        crossing = min(sd[0], sd[1]) >= 0.25 * max(1, nfs)
        gone = []
        if front and not glassy(M):
            mt = obj_bvh(M)
            mw = N.matrix_world
            for i in fight.get((oth, mov), set()):
                f = N.data.polygons[i]
                pts = [mw @ f.center] + [mw @ N.data.vertices[vi].co for vi in f.vertices]
                if all(mt.find_nearest(p, GONE_MM)[0] is not None for p in pts):
                    gone.append(i)
            deletions.setdefault(oth, set()).update(gone)
        rot = M.matrix_world.to_3x3()
        nmat = rot.inverted().transposed()
        acc = moves.setdefault(mov, {})
        for i in fight.get((mov, oth), set()):
            f = M.data.polygons[i]
            nw = (nmat @ f.normal).normalized() * (1.0 if front else -1.0)
            for vi in f.vertices:
                acc.setdefault(vi, Vector((0.0, 0.0, 0.0)))
                acc[vi] += nw
        entry["treated"].append({"moves": M.name, "stays": N.name, "lift": front, "crossing": crossing,
                                 "faces_deleted_under": len(gone), "fighting_faces_moved": len(fight.get((mov, oth), ())),
                                 "mean_offset_mm": round(1000 * offset.get((mov, oth), 0.0) / max(1, nfs), 3)})
    for k, acc in moves.items():
        o = cur[k]
        inv = o.matrix_world.to_3x3().inverted()
        for vi, d in acc.items():
            if MOVES.get((o.name, vi), 0) >= 2 or d.length < 1e-9:
                continue
            MOVES[(o.name, vi)] = MOVES.get((o.name, vi), 0) + 1
            o.data.vertices[vi].co += inv @ (d.normalized() * SINK)
        o.data.update()
    for k, idxs in deletions.items():
        if not idxs:
            continue
        o = cur[k]
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.faces[i] for i in sorted(idxs)], context="FACES")
        bm.to_mesh(o.data)
        o.data.update()
        bm.free()
    for o in [o for o in bpy.data.objects if o.type == "MESH" and o.users_collection and not len(o.data.polygons)
              and not o.users_collection[0].name.startswith("Replaced")]:
        entry.setdefault("emptied", []).append(o.name)
        bpy.data.objects.remove(o, do_unlink=True)
report["vertices_moved_once"] = sum(1 for v in MOVES.values() if v == 1)
report["vertices_moved_twice"] = sum(1 for v in MOVES.values() if v >= 2)
report["tris_after"] = {c.name: sum(len(p.vertices) - 2 for o in c.objects if o.type == "MESH" for p in o.data.polygons)
                        for c in bpy.data.collections if not c.name.startswith("Replaced")}
report["seconds"] = round(time.time() - T0, 1)
bpy.ops.wm.save_as_mainfile(filepath=out_blend, compress=True)
json.dump(report, open(out_json, "w"), indent=1)
log("done", report["passes"][-1]["pairs_over"], "pairs over at the end;", report["vertices_moved_once"], "vertices moved once,",
    report["vertices_moved_twice"], "twice;", report["tris_after"])
