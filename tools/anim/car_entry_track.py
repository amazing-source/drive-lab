"""
Tracks the body through a span frame by frame with a local pattern search, for spans where the
authored beats pass through a narrow opening that car_entry_clear.py's optimiser cannot follow (it
settles into the nearest clear pose, which can be on the wrong side of a bar for the rest of the
span). Each frame searches the pelvis, the torso's turn and the neck around two centres, the
authored pose and the previous frame's solution moved by the authored step, then each limb on its
own around its previous angles and its authored target. Candidates are ranked deepest excess first
(how far any part goes past its named allowance, in steps of 0.002 stud), then by distance from the
authored pose and from the previous frame, so a clear pose always wins and among clear poses the
closest to the choreography and the smoothest wins.

  python car_entry_track.py <keys module> <scene.npz> <keys args...> --from F --to F --out table.json
      [--step 1] [--pin F] [--spacing 0.05]

Same keys module contract and table format as car_entry_clear.py.
"""
import argparse
import importlib
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r6_fk  # noqa: E402
from car_entry_check import HALF  # noqa: E402
from car_entry_clear import CORNERS, LIMB_PART, POINT, Scene, allowed, fast_aim, group_depths  # noqa: E402

QUANTUM = 0.002
MARGIN = 0.002  # kept under every allowance: the house check samples its own cloud
LIMB_SPEED = 7.0  # degrees a frame a limb turns freely; past it the move costs like a missed target
# The most a frame may move off the previous one (a limb's swing and spread, the pelvis, the
# torso's and the neck's angles), so a search can never flip a limb onto its other branch or pop
# the body: a contact that cannot be cleared within it is reported, not jumped over.
MAX_LIMB_TURN = 2 * LIMB_SPEED
MAX_BODY_STEP = np.array([0.08, 0.08, 0.08, 5.0, 5.0, 5.0, 12.0, 12.0])
BODY_LEVELS = ((0.2, 10.0), (0.1, 5.0), (0.05, 2.5), (0.025, 1.25))
LIMB_LEVELS = (16.0, 8.0, 4.0, 2.0)


def part_depth(scene, door, part, m):
    half = HALF[part]
    r = float(np.linalg.norm(half))
    idx = np.asarray(scene.tree.query_ball_point(m[:3, 3], r, return_sorted=False), dtype=int)
    g = group_depths(scene.cloud[idx], scene.labels[idx], m, half, scene.names) if len(idx) else {}
    idx = np.asarray(door[1].query_ball_point(m[:3, 3], r, return_sorted=False), dtype=int)
    if len(idx):
        g.update(group_depths(door[0][idx], np.full(len(idx), len(scene.names) - 1), m, half, scene.names))
    low = float(((CORNERS * np.asarray(half)) @ m[:3, :3].T + m[:3, 3])[:, 1].min())
    if low < 0:
        g["ground"] = -low
    return g


def rank(e):
    return math.ceil(max(e, 0.0) / QUANTUM - 1e-9)


class Frame:
    def __init__(self, scene, allow, f, door, neck_loc, neck_turn):
        self.scene, self.allow, self.f, self.door = scene, allow, f, door
        self.neck_loc, self.neck_turn = neck_loc, neck_turn

    def excess(self, part, m):
        worst = 0.0
        for g, d in part_depth(self.scene, self.door, part, m).items():
            worst = max(worst, d - allowed(self.allow, self.f, part, g, 0.04) + MARGIN)
        return worst

    def root(self, pel, tor):
        rot = r6_fk.body_turn(*tor)
        loc = r6_fk.torso_root_offset(rot, np.asarray(pel) - np.array([0.0, r6_fk.ROOT_HEIGHT, 0.0]))
        return (rot, tuple(loc))

    def torso_head(self, pel, tor, nod_roll):
        pose = {"RootJoint": self.root(pel, tor), "Neck": ((nod_roll[0], self.neck_turn, nod_roll[1]), self.neck_loc)}
        parts = r6_fk.pose_parts(pose)
        return parts["Torso"], parts["Head"]


def pattern(evaluate, x, scales, rng, samples=16, rounds=4):
    """Coordinate pattern search with a few random trials per scale; `evaluate` returns a sortable
    key, lower is better."""
    best = (evaluate(x), x)
    for scale in scales:
        scale = np.asarray(scale, float)
        for _ in range(samples):
            trial = best[1] + scale * rng.uniform(-2.0, 2.0, len(x))
            k = evaluate(trial)
            if k < best[0]:
                best = (k, trial)
        for _ in range(rounds):
            improved = False
            for d in range(len(x)):
                for sign in (-1.0, 1.0):
                    trial = best[1].copy()
                    trial[d] += sign * scale[d]
                    k = evaluate(trial)
                    if k < best[0]:
                        best, improved = (k, trial), True
            if not improved:
                break
    return best


def search_body(fr, centres, auth, pred, w_pred, step, rng, w_auth=1.0, bounded=False, held=None):
    """(pelvis, torso angles, neck nod and roll) from each centre; the best per centre. `bounded`:
    within MAX_BODY_STEP of the previous frame (`pred` less the authored step). `held`: {limb:
    (target, guess)}, limbs whose point must stay on its target, scored with the body (a hand
    pushing a door can only reach it through the body's pose)."""
    pel_a, tor_a, nek_a = auth
    pel_p, tor_p, nek_p = pred
    torso_cache = {}
    mid = np.concatenate([np.asarray(v, float) for v in pred])
    reach = MAX_BODY_STEP * step

    def evaluate(x):
        if bounded:
            x = np.clip(x, mid - reach, mid + reach)
        pel, tor, nek = x[0:3], x[3:6], x[6:8]
        # Close to the authored pose, and to the previous frame moved by the authored step; the
        # weights let an offset forced by a contact decay by about a third a frame once it is
        # free (the per-frame bounds keep the return smooth).
        d = w_auth * (float(np.sum((pel - pel_a) ** 2)) / 0.15 ** 2 + float(np.sum(((tor - tor_a) / 10.0) ** 2)) + float(np.sum(((nek - nek_a) / 15.0) ** 2)))
        d += w_pred * (float(np.sum((pel - pel_p) ** 2)) / (0.12 * step) ** 2 + float(np.sum(((tor - tor_p) / (8.0 * step)) ** 2)) + float(np.sum(((nek - nek_p) / (12.0 * step)) ** 2)))
        torso_m, head_m = fr.torso_head(pel, tor, nek)
        key = tuple(np.round(x[0:6], 6))
        if key not in torso_cache:
            worst = fr.excess("Torso", torso_m)
            for limb, (target, guess) in (held or {}).items():
                angles, miss = fast_aim(torso_m, limb, target, POINT[limb], guess, 12)
                limb_m = r6_fk.limb_frame(torso_m, r6_fk.LIMB_JOINT[limb], angles)
                worst = max(worst, fr.excess(LIMB_PART[limb], limb_m), miss - 0.02)
            torso_cache[key] = worst
        return (rank(max(torso_cache[key], fr.excess("Head", head_m))), d)

    out = []
    for centre in centres:
        x0 = np.concatenate([np.asarray(v, float) for v in centre])
        k, x = pattern(evaluate, x0, [(dp, dp, dp, dt, dt, dt, 2 * dt, 2 * dt) for dp, dt in BODY_LEVELS], rng)
        if bounded:
            x = np.clip(x, mid - reach, mid + reach)
        out.append((k, x[0:3], x[3:6], x[6:8]))
    return sorted(out, key=lambda r: r[0])


def held_aim(root, limb, target, guess):
    """A held limb as the bake solves it (beat_tracks.Body.solve): aimed from the last frame's
    angles, a sole lifted until its lowest corner is on the ground."""
    joint = r6_fk.LIMB_JOINT[limb]
    part = r6_fk.JOINTS[joint][1]
    pose = {"RootJoint": root}
    target = np.array(target, float)
    angles, err = r6_fk.aim(pose, limb, target, POINT[limb], guess=tuple(guess))
    if limb.endswith("leg"):
        wanted = target[1] if target[1] < 0.05 else None
        for _ in range(4):
            trial = dict(pose)
            trial[joint] = (angles, (0, 0, 0))
            low = r6_fk.lowest_corner(r6_fk.pose_parts(trial)[part])
            floor = wanted if wanted is not None else (0.0 if low < 0 else None)
            if floor is None or abs(low - floor) < 1e-4:
                break
            target = target + np.array([0.0, floor - low, 0.0])
            angles, err = r6_fk.aim(pose, limb, target, POINT[limb], guess=angles[::2])
    return angles, err


def search_limbs(fr, pel, tor, nek, held, targets, prev, guess, pin, rng, fixed=None, goal=None, step=1):
    """Each limb on its own: (worst rank, distance, {limb: angles}, {limb: miss}). A limb with fixed
    angles keeps them; a free limb with a goal (angles, pull) is drawn toward those angles."""
    torso_m = r6_fk.pose_parts({"RootJoint": fr.root(pel, tor)})["Torso"]
    total_rank, total_dist, angles, misses = 0, 0.0, {}, {}
    fixed, goal = fixed or {}, goal or {}
    for limb, part in LIMB_PART.items():
        joint = r6_fk.LIMB_JOINT[limb]
        lo, hi = (np.array(v) for v in r6_fk.LIMITS["leg" if limb.endswith("leg") else "arm"])
        if limb in fixed:
            m = r6_fk.limb_frame(torso_m, joint, (fixed[limb][0], 0.0, fixed[limb][1]))
            end = m[:3, :3] @ np.asarray(POINT[limb]) + m[:3, 3]
            total_rank, angles[limb] = max(total_rank, rank(fr.excess(part, m))), fixed[limb]
            misses[limb] = float(np.linalg.norm(end - targets[limb]))
            continue
        aimed, miss = fast_aim(torso_m, limb, targets[limb], POINT[limb], prev.get(limb, guess[limb]), 12)
        start = np.array([aimed[0], aimed[2]])
        if limb in held:
            aimed, miss = held_aim(fr.root(pel, tor), limb, targets[limb], prev.get(limb, guess[limb]))
            m = r6_fk.limb_frame(torso_m, joint, aimed)
            e = max(fr.excess(part, m), miss - 0.02)
            total_rank, angles[limb], misses[limb] = max(total_rank, rank(e)), np.array([aimed[0], aimed[2]]), miss
            continue

        if limb in prev:
            near = np.asarray(prev[limb], float)
            lo, hi = np.maximum(lo, near - MAX_LIMB_TURN * step), np.minimum(hi, near + MAX_LIMB_TURN * step)

        def evaluate(v):
            v = np.clip(v, lo, hi)
            m = r6_fk.limb_frame(torso_m, joint, (v[0], 0.0, v[1]))
            e = fr.excess(part, m)
            end = m[:3, :3] @ np.asarray(POINT[limb]) + m[:3, 3]
            d = float(np.sum((end - targets[limb]) ** 2)) / 0.5 ** 2 * (100.0 if pin else 1.0)
            if limb in prev:
                turn = np.abs(v - prev[limb])
                d += float(np.sum((turn / 10.0) ** 2)) + float(np.sum((np.maximum(turn - LIMB_SPEED * step, 0.0) / 2.0) ** 2))
            if limb in goal:
                d += 4.0 * goal[limb][1] * float(np.sum(((v - goal[limb][0]) / 10.0) ** 2))
            return (rank(e), d)

        best = None
        # From the previous angles when there are some: a start aimed afresh, or the held pose
        # ahead, can sit on the limb's other branch.
        starts = [np.asarray(prev[limb], float)] if limb in prev else [start]
        for c in starts:
            k, v = pattern(evaluate, np.clip(c, lo, hi), [(s, s) for s in LIMB_LEVELS], rng, samples=6, rounds=3)
            v = np.clip(v, lo, hi)
            if best is None or k < best[0]:
                best = (k, v)
        (r, d), v = best
        total_rank, total_dist, angles[limb] = max(total_rank, r), total_dist + d, v
    return total_rank, total_dist, angles, misses


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("module")
    ap.add_argument("scene")
    ap.add_argument("--from", dest="start", type=int, required=True)
    ap.add_argument("--to", dest="end", type=int, required=True)
    ap.add_argument("--step", type=int, default=1)
    ap.add_argument("--out", required=True)
    ap.add_argument("--spacing", type=float, default=0.05)
    ap.add_argument("--smooth", type=float, default=1.0, help="weight of the previous frame against the authored pose")
    ap.add_argument("--pin", type=int, default=None, help="from this frame the body keeps its authored pose")
    ap.add_argument("--goal-span", type=int, default=24, help="frames over which a limb is drawn toward its next fixed angles")
    a, rest = ap.parse_known_args(argv)
    mod = importlib.import_module(a.module)
    body, allow, holds = mod.build([a.scene] + rest)
    body.solve()
    frames = list(range(a.start, a.end + 1, a.step))
    if frames[-1] != a.end:
        frames.append(a.end)
    at = np.array(frames, float)
    path = body.pelvis.sample(at)
    scene = Scene(a.scene, a.spacing, box=(path.min(axis=0) - 5.0, path.max(axis=0) + 5.0))
    tor_t, nek_t = body.torso.sample(at), body.neck.sample(at)
    # The authored body is the solved one: planted stances at their solved height.
    pel_t = np.array([body._frames_cache[f][:3, 3] + body._frames_cache[f][:3, :3] @ np.asarray(r6_fk.PELVIS, float) for f in frames])
    supported = {f for s0, s1, _ in body.support for f in range(s0, s1 + 1)}
    loc_t = body.neck_loc.sample(at) if body.neck_loc.beats else np.zeros((len(frames), 3))
    door_t = body.door.sample(at)[:, 0]
    targets = {k: t.sample(at) for k, t in body.targets.items()}
    guess = {k: np.array(body.guess[k], dtype=float) for k in LIMB_PART}
    def goals_of(f):
        # Ahead of a limb's next fixed angles (a held pose), {limb: (angles, pull)}: the limb is
        # drawn toward them, and the body toward its authored pose, harder as the frame nears.
        out = {}
        for limb in LIMB_PART:
            ahead = [g for g in body.fixed.get(limb, {}) if f < g <= f + a.goal_span]
            if ahead:
                g = min(ahead)
                out[limb] = (np.asarray(body.fixed[limb][g], float), (1.0 - (g - f) / a.goal_span) ** 2)
        return out

    first = max(frames[0] - 1, 0)
    table, previous = {}, None
    # Each limb starts on the branch the solve brings it in on.
    prev_limbs = {limb: np.array(body.poses[first][r6_fk.LIMB_JOINT[limb]][0])[[0, 2]] for limb in LIMB_PART}
    rng = np.random.default_rng(458)
    for i, f in enumerate(frames):
        held = [h["limb"] for h in holds if h["from"] <= f <= h["to"]]
        fr = Frame(scene, allow, f, scene.door(float(door_t[i])), tuple(loc_t[i]), float(nek_t[i][1]))
        auth = (pel_t[i], tor_t[i], np.array([nek_t[i][0], nek_t[i][2]]))
        pin = a.pin is not None and f >= a.pin
        if previous is None or pin:
            pred, centres, w = auth, [auth], 0.0
        else:
            pred = tuple(previous[k] + (auth[k] - last[k]) for k in range(3))
            centres, w = [auth, pred], a.smooth
        # A planted frame keeps its authored body: the bake solves its stance from the authored
        # torso, and a turned torso would move the hips off the planted soles.
        if pin or f in supported:
            bodies = [((0, 0.0), auth[0], auth[1], auth[2])]
        else:
            goals = goals_of(f)
            held_now = {limb: (targets[limb][i], prev_limbs.get(limb, guess[limb])) for limb in held}
            bodies = search_body(fr, centres, auth, pred, w, a.step, rng, 1.0 + 20.0 * max([p for _, p in goals.values()] + [0.0]), previous is not None, held_now)
        tgt = {k: targets[k][i] for k in LIMB_PART}
        fixed = {limb: np.asarray(body.fixed[limb][f], float) for limb in LIMB_PART if f in body.fixed.get(limb, {})}
        goals = goals_of(f)
        best = None
        for (b_rank, b_dist), pel, tor, nek in bodies:
            l_rank, l_dist, angles, misses = search_limbs(fr, pel, tor, nek, held, tgt, prev_limbs, guess, pin, rng, fixed, goals, a.step)
            key = (max(b_rank, l_rank), b_dist + 0.2 * l_dist)
            if best is None or key < best[0]:
                best = (key, pel, tor, nek, angles, misses)
        (worst_rank, _), pel, tor, nek, angles, misses = best
        for limb in held:
            guess[limb] = angles[limb]
        prev_limbs = {limb: angles[limb] for limb in LIMB_PART}
        previous, last = (pel, tor, nek), auth
        pose = {"RootJoint": fr.root(pel, tor), "Neck": ((nek[0], fr.neck_turn, nek[1]), fr.neck_loc)}
        for limb, v in angles.items():
            pose[r6_fk.LIMB_JOINT[limb]] = ((v[0], 0.0, v[1]), (0, 0, 0))
        parts = r6_fk.pose_parts(pose)
        worst = []
        for part in HALF:
            for g, d in part_depth(scene, fr.door, part, parts[part]).items():
                lim = allowed(allow, f, part, g, 0.04)
                if d > lim:
                    worst.append(f"{part}/{g} {d:.3f}>{lim:.3f}")
        row = {
            "pelvis": [round(float(v), 4) for v in pel],
            "torso": [round(float(v), 3) for v in tor],
            "neck": [round(float(nek[0]), 3), round(fr.neck_turn, 3), round(float(nek[1]), 3)],
            "targets": {limb: [round(float(v), 4) for v in r6_fk.point(parts[LIMB_PART[limb]], POINT[limb])] for limb in LIMB_PART if limb not in held},
            # Held limbs are aimed by the bake itself, which arrives at the same angles.
            "angles": {limb: [round(float(v[0]), 3), round(float(v[1]), 3)] for limb, v in angles.items() if limb not in held},
        }
        table[str(f)] = row
        moved = float(np.linalg.norm(pel - auth[0]))
        miss = max(misses.values()) if misses else 0.0
        print(f"f{f}: moved {moved:.3f}, miss {miss:.3f}, {'; '.join(worst) or 'clear'}", flush=True)
        json.dump(table, open(a.out, "w", encoding="utf-8", newline="\n"), indent=0)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
