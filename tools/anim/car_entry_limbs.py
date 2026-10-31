"""
Plans each limb's path through a span at once, for a car_entry_track.py table whose body is
settled: every frame's swing and spread on a grid of cells, each cell scored by how far the limb
goes past its named allowances (per group, the door at that frame's openness, the ground) and how
far its end is off the authored target, and the cheapest path through the frames found by dynamic
programming, a frame moving at most --turn cells off the last. A per-frame search can only look
one frame ahead, so a limb boxed in by a bar flips onto its other branch or gets stuck; a path
planned over the whole span goes round in time. Held limbs and limbs with fixed angles are fixed
points the path passes through.

  python car_entry_limbs.py <keys module> <scene.npz> <keys args...> --table in.json --out out.json
      --from F --to F [--cell 6] [--turn 2] [--window 60] [--spacing 0.08] [--limbs right_arm,left_arm]

Each frame scores only the cells within --window degrees of the table's angles for that limb
(the per-frame search's path, which never flips branch) and of the next fixed angles ahead.

The cells' depths come from a --spacing cloud (coarser than the house check's, for speed), so
the path is then smoothed and checked at the house spacing (car_entry_smooth.py, the checks).
"""
import argparse
import importlib
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r6_fk  # noqa: E402
from car_entry_clear import LIMB_PART, POINT, Scene, allowed  # noqa: E402
from car_entry_track import held_aim  # noqa: E402

HALF = np.array([0.5, 1.0, 0.5])
CORNERS = np.array([[sx, sy, sz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)], dtype=float) * HALF
EXCESS_COST = 1e4  # per stud past an allowance: always dearer than any detour
TARGET_SCALE = 0.5  # studs off the authored target that cost as much as a 10-degree turn


def euler_cells(xs, zs):
    """Rz @ Rx for every (x, z) pair (twist 0), shape (n, 3, 3)."""
    x, z = np.radians(xs), np.radians(zs)
    cx, sx, cz, sz = np.cos(x), np.sin(x), np.cos(z), np.sin(z)
    r = np.zeros((len(xs), 3, 3))
    r[:, 0, 0], r[:, 0, 1], r[:, 0, 2] = cz, -sz * cx, sz * sx
    r[:, 1, 0], r[:, 1, 1], r[:, 1, 2] = sz, cz * cx, -cz * sx
    r[:, 2, 1], r[:, 2, 2] = sx, cx
    return r


class Grid:
    def __init__(self, limb, cell):
        lo, hi = r6_fk.LIMITS["leg" if limb.endswith("leg") else "arm"]
        self.xs = np.arange(lo[0], hi[0] + 1e-6, cell)
        self.zs = np.arange(lo[1], hi[1] + 1e-6, cell)
        gx, gz = np.meshgrid(self.xs, self.zs, indexing="ij")
        self.angles = np.stack([gx.ravel(), gz.ravel()], axis=1)
        self.shape = gx.shape
        joint = r6_fk.LIMB_JOINT[limb]
        _, _, c0, c1 = r6_fk.JOINTS[joint]
        self.pivot = np.identity(4)
        self.pivot[:3, 3] = c0[:3, 3]
        k = np.identity(4)
        k[:3, :3] = c0[:3, :3]
        k = k @ np.linalg.inv(c1)
        rot = euler_cells(self.angles[:, 0], self.angles[:, 1])
        self.rot_local = rot @ k[:3, :3]  # the part's turn in the pivot frame
        self.pos_local = rot @ k[:3, 3]  # the part's centre in the pivot frame
        self.end_local = self.pos_local + self.rot_local @ np.asarray(POINT[limb], float)

    def nearest(self, angles):
        i = int(np.argmin(np.abs(self.xs - angles[0])))
        j = int(np.argmin(np.abs(self.zs - angles[1])))
        return i * self.shape[1] + j

    def frames(self, torso):
        p = torso @ self.pivot
        rot = np.einsum("ij,njk->nik", p[:3, :3], self.rot_local)
        pos = self.pos_local @ p[:3, :3].T + p[:3, 3]
        end = self.end_local @ p[:3, :3].T + p[:3, 3]
        return rot, pos, end


def cell_excess(rot, pos, scene, door, limits):
    """Per cell, the largest depth past its group's limit (0 when within every one): each box
    against the points within its bounding sphere."""
    out = np.zeros(len(pos))
    radius = float(np.linalg.norm(HALF))
    door_pts, door_tree = door
    near = scene.tree.query_ball_point(pos, radius, return_sorted=False)
    near_door = door_tree.query_ball_point(pos, radius, return_sorted=False)
    door_label = len(scene.names) - 1
    for c in range(len(pos)):
        idx, didx = near[c], near_door[c]
        if not idx and not didx:
            continue
        pts = np.concatenate([scene.cloud[idx], door_pts[didx]]) if didx else scene.cloud[idx]
        lab = np.concatenate([scene.labels[idx], np.full(len(didx), door_label)]) if didx else scene.labels[idx]
        d = (HALF - np.abs((pts - pos[c]) @ rot[c])).min(axis=1)
        inside = d > 0
        if inside.any():
            out[c] = max(0.0, float((d[inside] - limits[lab[inside]]).max()))
    low = (np.einsum("cij,kj->cki", rot, CORNERS) + pos[:, None, :])[:, :, 1].min(axis=1)
    return np.maximum(out, np.maximum(-low - limits[-1], 0.0))


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("module")
    ap.add_argument("scene")
    ap.add_argument("--table", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--from", dest="start", type=int, required=True)
    ap.add_argument("--to", dest="end", type=int, required=True)
    ap.add_argument("--cell", type=float, default=6.0)
    ap.add_argument("--turn", type=int, default=2, help="cells a frame may move off the last, each axis")
    ap.add_argument("--spacing", type=float, default=0.08)
    ap.add_argument("--window", type=float, default=60.0)
    ap.add_argument("--limbs", default=",".join(LIMB_PART))
    a, rest = ap.parse_known_args(argv)
    mod = importlib.import_module(a.module)
    body, allow, holds = mod.build([a.scene] + rest)
    body.solve()
    table = json.load(open(a.table, encoding="utf-8"))
    frames = list(range(a.start, a.end + 1))
    at = np.array(frames, float)
    path = body.pelvis.sample(at)
    scene = Scene(a.scene, a.spacing, box=(path.min(axis=0) - 5.0, path.max(axis=0) + 5.0))
    door_t = body.door.sample(at)[:, 0]
    targets = {k: t.sample(at) for k, t in body.targets.items()}
    torsos = []
    for f in frames:
        row = table.get(str(f))
        if row is None:
            torsos.append(body._frames_cache[f])
            continue
        rot = r6_fk.body_turn(*row["torso"])
        loc = r6_fk.torso_root_offset(rot, np.asarray(row["pelvis"]) - np.array([0.0, r6_fk.ROOT_HEIGHT, 0.0]))
        torsos.append(r6_fk.pose_parts({"RootJoint": (rot, tuple(loc))})["Torso"])
    groups = scene.names + ["ground"]
    out = {str(f): dict(table.get(str(f), {})) for f in frames}
    for limb in a.limbs.split(","):
        part = LIMB_PART[limb]
        grid = Grid(limb, a.cell)
        n = len(grid.angles)
        costs, forced = [], []
        guess = np.array(body.poses[max(frames[0] - 1, 0)][r6_fk.LIMB_JOINT[limb]][0])[[0, 2]]
        for i, f in enumerate(frames):
            held = any(h["limb"] == limb and h["from"] <= f <= h["to"] for h in holds)
            fixed = None
            if f in body.fixed.get(limb, {}):
                fixed = np.asarray(body.fixed[limb][f], float)
            elif held:
                # Aimed as the bake will aim it, from the frame before.
                row = table.get(str(f))
                if row is not None:
                    rr = r6_fk.body_turn(*row["torso"])
                    loc = r6_fk.torso_root_offset(rr, np.asarray(row["pelvis"]) - np.array([0.0, r6_fk.ROOT_HEIGHT, 0.0]))
                    pose_root = (rr, tuple(loc))
                else:
                    pose_root = body.poses[f]["RootJoint"]
                ang, _ = held_aim(pose_root, limb, targets[limb][i], guess)
                fixed = np.array([ang[0], ang[2]])
            elif (i == 0 and str(f - 1) not in table) or (i == len(frames) - 1 and str(f + 1) not in table):
                # A span's end next to frames the table leaves as authored meets them there.
                fixed = np.array(body.poses[f][r6_fk.LIMB_JOINT[limb]][0])[[0, 2]]
            if fixed is not None:
                guess = fixed
                forced.append((grid.nearest(fixed), fixed))
                costs.append(None)
                continue
            forced.append(None)
            centres = [np.asarray(table[str(f)]["angles"][limb], float)] if limb in table.get(str(f), {}).get("angles", {}) else [guess]
            ahead = [g for g in body.fixed.get(limb, {}) if f < g]
            if ahead:
                centres.append(np.asarray(body.fixed[limb][min(ahead)], float))
            live = np.zeros(n, dtype=bool)
            for c in centres:
                live |= np.all(np.abs(grid.angles - c) <= a.window, axis=1)
            cells = np.flatnonzero(live)
            rot, pos, end = grid.frames(torsos[i])
            rot, pos, end = rot[cells], pos[cells], end[cells]
            door = scene.door(float(door_t[i]))
            limits = np.array([allowed(allow, f, part, g, 0.04) for g in groups])
            excess = cell_excess(rot, pos, scene, door, limits)
            cost = np.full(n, np.inf)
            cost[cells] = EXCESS_COST * excess + np.sum((end - targets[limb][i]) ** 2, axis=1) / TARGET_SCALE ** 2
            costs.append(cost)
            guess = centres[0]
            print(f"{limb} f{f}: {len(cells)} cells, {int(np.sum(excess <= 0))} clear", flush=True)
        # Dynamic programming over the frames; a frame's cell moves at most `turn` cells each axis.
        shape = grid.shape
        value = np.full(n, np.inf)
        back = []
        for i in range(len(frames)):
            here = np.full(n, np.inf)
            if forced[i] is not None:
                here[forced[i][0]] = 0.0
            else:
                here = costs[i].copy()
            if i == 0:
                value = here
                back.append(None)
                continue
            prev = value.reshape(shape)
            best = np.full(shape, np.inf)
            arg = np.zeros(shape + (2,), dtype=int)
            for di in range(-a.turn, a.turn + 1):
                for dj in range(-a.turn, a.turn + 1):
                    shifted = np.full(shape, np.inf)
                    src_i = slice(max(0, -di), shape[0] - max(0, di))
                    dst_i = slice(max(0, di), shape[0] - max(0, -di))
                    src_j = slice(max(0, -dj), shape[1] - max(0, dj))
                    dst_j = slice(max(0, dj), shape[1] - max(0, -dj))
                    shifted[dst_i, dst_j] = prev[src_i, src_j] + ((di * a.cell) ** 2 + (dj * a.cell) ** 2) / 100.0
                    better = shifted < best
                    best = np.where(better, shifted, best)
                    arg[..., 0] = np.where(better, di, arg[..., 0])
                    arg[..., 1] = np.where(better, dj, arg[..., 1])
            value = best.ravel() + here
            back.append(arg.reshape(n, 2))
        cell = int(np.argmin(value))
        total = float(value[cell])
        chosen = [cell]
        for i in range(len(frames) - 1, 0, -1):
            di, dj = back[i][cell]
            ci, cj = divmod(cell, shape[1])
            cell = (ci - di) * shape[1] + (cj - dj)
            chosen.append(cell)
        chosen.reverse()
        bad = 0
        for i, f in enumerate(frames):
            angles = forced[i][1] if forced[i] is not None else grid.angles[chosen[i]]
            row = out[str(f)]
            if forced[i] is None:
                row.setdefault("angles", {})[limb] = [round(float(angles[0]), 3), round(float(angles[1]), 3)]
                rot, pos, end = grid.frames(torsos[i])
                row.setdefault("targets", {})[limb] = [round(float(v), 4) for v in end[chosen[i]]]
                if not costs[i][chosen[i]] < EXCESS_COST * 0.002:
                    bad += 1
        print(f"{limb}: path cost {total:.1f}, {bad} frames past an allowance on the {a.spacing} cloud", flush=True)
    json.dump(out, open(a.out, "w", encoding="utf-8", newline="\n"), indent=0)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
