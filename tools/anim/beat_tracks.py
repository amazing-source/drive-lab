"""
Authoring by beats: a body is a set of tracks (pelvis point, torso angles, neck angles, a target
per limb, door openness), each a few beat values at chosen frames, interpolated with a monotone
cubic (no overshoot, continuous speed), and solved every frame into R6 joint angles by aiming each
rigid limb at its target (r6_fk). The solved poses are then keyed densely, so Blender's curves
follow the solve and every contact is exact at its keys.

A beat value may be a function of the frame (a hand riding a moving door): the track takes it
literally for every frame inside an `attach` span and passes through its value at the span's ends.
"""
import json
import math

import numpy as np
from scipy.interpolate import PchipInterpolator

import r6_fk

# Frames over which a solved standing height eases into the authored pelvis at a support's ends.
SUPPORT_EASE = 6


class Track:
    def __init__(self, size):
        self.size = size
        self.beats = {}
        self.attached = []

    def at(self, frame, value):
        self.beats[frame] = value
        return self

    def attach(self, start, end, fn):
        """fn(frame) -> value for start <= frame <= end."""
        self.attached.append((start, end, fn))
        self.beats[start] = fn
        self.beats[end] = fn
        return self

    def _points(self):
        frames = sorted(self.beats)
        values = []
        for f in frames:
            v = self.beats[f]
            values.append(np.asarray(v(f) if callable(v) else v, dtype=float))
        return np.array(frames, dtype=float), np.array(values)

    def sample(self, frames):
        xs, ys = self._points()
        out = np.empty((len(frames), self.size))
        if len(xs) == 1:
            out[:] = ys[0]
        else:
            curve = PchipInterpolator(xs, ys, axis=0, extrapolate=False)
            clamped = np.clip(frames, xs[0], xs[-1])
            out[:] = curve(clamped)
        for i, f in enumerate(frames):
            for start, end, fn in self.attached:
                if start <= f <= end:
                    out[i] = np.asarray(fn(f), dtype=float)
        return out


class Body:
    """Tracks for one continuous timeline. Limb targets are authoring-frame points; a limb's
    `point` is the spot on it that goes to the target (palm, sole)."""

    LIMB_POINT = {
        "right_arm": r6_fk.HAND,
        "left_arm": r6_fk.HAND,
        "right_leg": r6_fk.FOOT,
        "left_leg": r6_fk.FOOT,
    }

    def __init__(self, frames, fps=30):
        self.frames = frames
        self.fps = fps
        self.pelvis = Track(3)
        self.torso = Track(3)
        self.neck = Track(3)
        self.door = Track(1)
        self.targets = {limb: Track(3) for limb in self.LIMB_POINT}
        self.twist = {limb: Track(1) for limb in self.LIMB_POINT}
        self.points = dict(self.LIMB_POINT)
        self.guess = {"right_arm": (0, 0), "left_arm": (0, 0), "right_leg": (0, 0), "left_leg": (0, 0)}
        self.contact = []  # (start, end) spans keyed every frame
        self.support = []  # (start, end, [legs]): the pelvis height follows these planted legs

    def _standing_height(self, pelvis, rot, legs, targets, guess):
        """The pelvis height at which each supporting straight leg just reaches its sole spot on
        the ground, standing on its lowest corner: higher and the leg falls short of the spot,
        lower and it would go through the ground. The highest of the legs, so no foot digs."""
        heights = []
        for limb in legs:
            joint = r6_fk.LIMB_JOINT[limb]
            part = r6_fk.JOINTS[joint][1]
            spot = np.array(targets[limb], dtype=float)
            lo, hi = pelvis[1] - 0.6, pelvis[1] + 0.6
            for _ in range(16):
                mid = (lo + hi) / 2
                p = np.array([pelvis[0], mid, pelvis[2]])
                loc = r6_fk.torso_root_offset(rot, p - np.array([0.0, r6_fk.ROOT_HEIGHT, 0.0]))
                pose = {"RootJoint": (rot, tuple(loc))}
                # From a neutral start as well as the last frame's: a planted leg's best aim must
                # not depend on where the previous frame's swing left it.
                tries = [r6_fk.aim(pose, limb, spot, self.points[limb], guess=g, restart=False) for g in (guess[limb], (0.0, 0.0))]
                angles, _ = min(tries, key=lambda t: t[1])
                pose[joint] = (angles, (0, 0, 0))
                leg = r6_fk.pose_parts(pose)[part]
                sole = r6_fk.point(leg, self.points[limb])
                lift = sole[1] - r6_fk.lowest_corner(leg)
                pivot = r6_fk.point(r6_fk.pose_parts(pose)["Torso"], r6_fk.JOINTS[joint][2][:3, 3])
                want = np.array([spot[0], lift, spot[2]])
                if np.linalg.norm(want - pivot) > np.linalg.norm(sole - pivot):
                    hi = mid
                else:
                    lo = mid
            heights.append((lo + hi) / 2)
        return max(heights)

    def torso_frame(self, frame):
        """The torso's frame (authoring frame) at `frame`, from the pelvis and torso tracks."""
        cache = getattr(self, "_frames_cache", None)
        if cache is not None and frame in cache:
            return cache[frame]
        lean, yaw, roll = self.torso.sample(np.array([frame]))[0]
        pelvis = self.pelvis.sample(np.array([frame]))[0]
        m = np.identity(4)
        m[:3, :3] = r6_fk.body_turn(lean, yaw, roll)
        m[:3, 3] = pelvis - m[:3, :3] @ np.asarray(r6_fk.PELVIS, dtype=float)
        return m

    def on_torso(self, local):
        """A beat value that rides the torso: a point in the torso's frame."""
        local = np.asarray(local, dtype=float)
        return lambda f: self.torso_frame(f)[:3, :3] @ local + self.torso_frame(f)[:3, 3]

    def hang(self, limb, start, end, local=None):
        """The limb rides the torso from start to end, at `local` (its idle end by default)."""
        if local is None:
            local = IDLE_LOCAL[limb]
        self.targets[limb].attach(start, end, self.on_torso(local))

    def solve(self):
        frames = np.arange(self.frames)
        pel = self.pelvis.sample(frames)
        tor = self.torso.sample(frames)
        guess = {k: np.array(v, dtype=float) for k, v in self.guess.items()}
        # The body first: where a foot is planted the pelvis height is solved from the legs (their
        # targets are points on the ground, never riding the body). Then every target that rides
        # the body (a hanging hand, a hand finding a surface within reach, the strap) is read off
        # the SOLVED body, so a contact hand sees the shoulder it will really have.
        self._frames_cache = None
        legs = {k: self.targets[k].sample(frames) for k in ("right_leg", "left_leg")}
        solved = np.array(pel, dtype=float)
        supported = np.zeros(len(frames), dtype=bool)
        for i in frames:
            support = [limb for start, end, limbs in self.support if start <= i <= end for limb in limbs]
            if support:
                supported[i] = True
                rot = r6_fk.body_turn(*tor[i])
                solved[i][1] = self._standing_height(solved[i], rot, support, {k: legs[k][i] for k in support}, guess)
        # Where support starts or ends, the solved height and the authored one differ; easing that
        # difference in and out over a few frames keeps the hips from popping (a pop drags a foot
        # that was planted a frame before).
        lift = solved[:, 1] - pel[:, 1]
        for i in np.flatnonzero(~supported):
            near = [j for j in range(max(0, i - SUPPORT_EASE), min(len(frames), i + SUPPORT_EASE + 1)) if supported[j]]
            if near:
                j = min(near, key=lambda k: abs(k - i))
                u = 1.0 - abs(i - j) / (SUPPORT_EASE + 1)
                solved[i][1] = pel[i][1] + lift[j] * u * u * (3 - 2 * u)
        cache = {}
        for i in frames:
            m = np.identity(4)
            m[:3, :3] = r6_fk.body_turn(*tor[i])
            m[:3, 3] = solved[i] - m[:3, :3] @ np.asarray(r6_fk.PELVIS, dtype=float)
            cache[int(i)] = m
        self._frames_cache = cache
        nek = self.neck.sample(frames)
        door = self.door.sample(frames)[:, 0]
        tgt = {k: t.sample(frames) for k, t in self.targets.items()}
        tw = {k: t.sample(frames)[:, 0] for k, t in self.twist.items()}
        poses, misses = [], []
        for i in frames:
            # Torso angles are body-relative (lean, yaw, roll); RootJoint gets the matrix.
            rot = r6_fk.body_turn(*tor[i])
            pelvis = np.array(solved[i])
            pose = {"Neck": (tuple(nek[i]), (0, 0, 0))}
            # Root part sits at (0, 3, 0): its frame is the authoring frame shifted up 3.
            loc = r6_fk.torso_root_offset(rot, pelvis - np.array([0.0, r6_fk.ROOT_HEIGHT, 0.0]))
            pose["RootJoint"] = (rot, tuple(loc))
            miss = {}
            for limb in ("right_arm", "left_arm", "right_leg", "left_leg"):
                target = np.array(tgt[limb][i])
                angles, err = r6_fk.aim(
                    pose, limb, target, self.points[limb], twist=float(tw[limb][i]), guess=guess[limb]
                )
                if limb.endswith("leg"):
                    # A box foot stands on its lowest corner: a sole asked onto the ground is lifted
                    # until that corner touches (R6_ANIMATION.md section 4), and no foot goes into
                    # the ground, whatever its target.
                    wanted = tgt[limb][i][1] if tgt[limb][i][1] < 0.05 else None
                    for _ in range(4):
                        trial = dict(pose)
                        trial[r6_fk.LIMB_JOINT[limb]] = (angles, (0, 0, 0))
                        leg = r6_fk.pose_parts(trial)[r6_fk.JOINTS[r6_fk.LIMB_JOINT[limb]][1]]
                        low = r6_fk.lowest_corner(leg)
                        floor = wanted if wanted is not None else (0.0 if low < 0 else None)
                        if floor is None or abs(low - floor) < 1e-4:
                            break
                        target = target + np.array([0.0, floor - low, 0.0])
                        angles, err = r6_fk.aim(
                            pose, limb, target, self.points[limb], twist=float(tw[limb][i]), guess=angles[::2]
                        )
                guess[limb] = np.array([angles[0], angles[2]])
                pose[r6_fk.LIMB_JOINT[limb]] = (angles, (0, 0, 0))
                miss[limb] = err
            poses.append(pose)
            misses.append(miss)
        self.poses, self.misses, self.door_values = poses, misses, door
        return poses

    def keys(self, every=2, clips=(), markers=()):
        """Keys every `every` frames, every frame inside contact spans, and the last frame."""
        keyed = set(range(0, self.frames, every)) | {self.frames - 1}
        for start, end in self.contact:
            keyed |= set(range(start, end + 1))
        for clip in clips:
            keyed |= {clip["start"], clip["end"]}
        keyed = sorted(keyed)
        joints = {name: [] for name in r6_fk.ORDER}
        unwrap = {}
        quat = {}
        previous_q = None
        for f in keyed:
            q = matrix_quat(r6_fk.rotation(self.poses[f]["RootJoint"][0]))
            if previous_q is not None and np.dot(q, previous_q) < 0:
                q = -q
            quat[f] = previous_q = q
        for f in keyed:
            for name, (rot, loc) in self.poses[f].items():
                rot = r6_fk.to_euler_xyz(rot) if isinstance(rot, np.ndarray) else list(rot)
                previous = unwrap.get(name)
                if previous is not None:
                    rot = [r + 360 * round((p - r) / 360) for r, p in zip(rot, previous)]
                unwrap[name] = rot
                entry = {"frame": int(f), "rot": [round(r, 4) for r in rot]}
                if name == "RootJoint":
                    entry["loc"] = [round(float(v), 5) for v in loc]
                    entry["quat"] = [round(float(v), 6) for v in quat[f]]
                joints[name].append(entry)
        door = [{"frame": int(f), "value": round(float(self.door_values[f]), 5)} for f in keyed]
        return {
            "fps": self.fps,
            "frames": self.frames,
            "joints": joints,
            "door": door,
            "clips": list(clips),
            "markers": [{"name": n, "frame": f} for n, f in markers],
        }

    def fk_bake(self):
        """The solved poses in r6_rig's bake format (parts only, every frame), for checking the
        choreography before Blender; Blender's own bake is the one that ships."""
        frames = []
        for f, pose in enumerate(self.poses):
            parts = r6_fk.pose_parts(pose)
            world = {
                name: list(m[:3, 3]) + list(m[:3, :3].ravel())
                for name, m in parts.items()
            }
            frames.append({"frame": f, "time": f / self.fps, "parts": world, "door": float(self.door_values[f])})
        return {"fps": self.fps, "frames": frames}

    def report_misses(self, limit=0.08):
        """Frames where a rigid limb could not put its point on the target (studs, scale 1)."""
        out = []
        for f, miss in enumerate(self.misses):
            for limb, err in miss.items():
                if err > limit:
                    out.append((f, limb, round(err, 3)))
        return out


def matrix_quat(m):
    """(w, x, y, z) of a rotation matrix."""
    t = np.trace(m)
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        return np.array([0.25 * s, (m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s])
    i = int(np.argmax(np.diag(m)))
    if i == 0:
        s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        return np.array([(m[2, 1] - m[1, 2]) / s, 0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s])
    if i == 1:
        s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        return np.array([(m[0, 2] - m[2, 0]) / s, (m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s])
    s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
    return np.array([(m[1, 0] - m[0, 1]) / s, (m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s])


def _idle_local():
    """Each limb's end point at rest, in the torso's frame."""
    rest = {name: ((0, 0, 0), (0, 0, 0)) for name in r6_fk.ORDER}
    parts = r6_fk.pose_parts(rest)
    torso_inv = np.linalg.inv(parts["Torso"])
    out = {}
    for limb, joint in r6_fk.LIMB_JOINT.items():
        part = r6_fk.JOINTS[joint][1]
        world = r6_fk.point(parts[part], Body.LIMB_POINT[limb])
        out[limb] = torso_inv[:3, :3] @ world + torso_inv[:3, 3]
    return out


IDLE_LOCAL = _idle_local()


def look_angles(pose_parts, head_target):
    """Neck (nod, turn) degrees for the head to face a point, from the torso's frame."""
    torso = pose_parts["Torso"]
    neck = r6_fk.point(torso, (0, 1, 0))
    d = np.linalg.inv(torso[:3, :3]) @ (np.asarray(head_target) - neck)
    yaw = math.degrees(math.atan2(-d[0], -d[2]))
    pitch = math.degrees(math.atan2(d[1], math.hypot(d[0], d[2])))
    return pitch, yaw


def write(path, data):
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(data, handle, indent=1)
