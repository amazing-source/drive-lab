"""
Shared by the locomotion key scripts: a cycle is one authored step plus its mirror, so every
cycle plants the left foot first and blends with the others without swapping feet. Angles are
degrees in body axes (signs in tools/blender/r6_rig.py).
"""
import json

PARTS = {
    "root": "RootJoint",
    "neck": "Neck",
    "right_arm": "Right Shoulder",
    "left_arm": "Left Shoulder",
    "right_leg": "Right Hip",
    "left_leg": "Left Hip",
}
MIRROR = {"right_arm": "left_arm", "left_arm": "right_arm", "right_leg": "left_leg", "left_leg": "right_leg"}


def mirrored(key, step):
    """The same pose on the other side: swap left and right, negate yaw, roll and sideways shift."""
    out = {"frame": key["frame"] + step}
    for name, value in key.items():
        if name == "frame":
            continue
        target = MIRROR.get(name, name)
        if name == "root":
            (x, y, z), (lx, ly, lz) = value
            out[target] = ((x, -y, -z), (-lx, ly, lz))
        else:
            x, y, z = value
            out[target] = (x, -y, -z)
    return out


def keys_file(step_a, step, fps, linear=None, markers=()):
    """linear: {part: frames of step A whose keys interpolate linearly}, mirrored for step B.
    markers: (name, frame) pairs in step A, repeated in step B."""
    linear = linear or {}
    cycle = step_a + [mirrored(k, step) for k in step_a]
    cycle.append(dict(step_a[0], frame=2 * step))
    linear_frames = {}
    for part, frames in linear.items():
        linear_frames.setdefault(part, set()).update(frames)
        linear_frames.setdefault(MIRROR.get(part, part), set()).update(f + step for f in frames)
    joints = {joint: [] for joint in PARTS.values()}
    for key in cycle:
        for name, joint in PARTS.items():
            value = key.get(name)
            if value is None:
                continue
            if name == "root":
                rot, loc = value
                entry = {"frame": key["frame"], "rot": list(rot), "loc": list(loc)}
            else:
                entry = {"frame": key["frame"], "rot": list(value)}
            if key["frame"] in linear_frames.get(name, ()):
                entry["interp"] = "LINEAR"
            joints[joint].append(entry)
    out_markers = []
    for name, frame in markers:
        out_markers += [{"name": name, "frame": frame}, {"name": name, "frame": frame + step}]
    return {"fps": fps, "frames": 2 * step + 1, "cyclic": True, "joints": joints, "markers": out_markers}


def write(path, data):
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=1)
