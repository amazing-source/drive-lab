"""
Cuts a baked car-entry timeline into the clips CarEntry plays and writes, per clip:

  <Clip>.seated.json    the bake rebased onto the SEATED root (the character's root is welded to
                        the driver's seat for the whole sequence): only RootJoint changes
  <Clip>.standing.json  as authored, root standing at the door mark (OutsideOpen, OutsideClose)
  <Clip>.door.json      the door's openness over the clip, {times, values}, thinned to what a
                        linear curve needs within --door-tol
  <Clip>.seatparts.json every part's CFrame in the SEAT frame (game studs), for the Studio check

each ready for `lune run tools/anim/build_keyframes`. Times start at 0 in every clip.

  python car_entry_export.py <baked.json> <scene.npz> <out_dir> [--standing OutsideOpen,OutsideClose]

The rebase: torso = root * C0 * T * C1^-1, so for a root R_s instead of R_m,
T_s = C0^-1 * R_s^-1 * R_m * C0 * T_m (C0 = C1 = the RootJoint's fixed turn). Translations stay
in scale-1 studs: the Animator scales them with the character (measured, SEAT_WELD.json).
"""
import argparse
import json
import os
import sys

import numpy as np

ROOT_ROT = np.array([[-1, 0, 0], [0, 0, 1], [0, 1, 0]], dtype=float)


def mat(values):
    m = np.identity(4)
    m[:3, 3] = values[0:3]
    m[:3, :3] = np.array(values[3:12]).reshape(3, 3)
    return m


def flat(m):
    return [float(v) for v in m[:3, 3]] + [float(v) for v in m[:3, :3].ravel()]


def rigid_to_authoring(a, frame):
    turn = a[:3, :3] / np.cbrt(np.linalg.det(a[:3, :3]))
    out = np.identity(4)
    out[:3, :3] = turn @ frame[:3, :3]
    out[:3, 3] = a[:3, :3] @ frame[:3, 3] + a[:3, 3]
    return out


def thin(times, values, tol):
    """Fewest samples whose linear interpolation stays within tol of every sample."""
    keep = [0]
    i = 0
    n = len(times)
    while i < n - 1:
        j = i + 1
        while j + 1 < n:
            t0, t1 = times[i], times[j + 1]
            ok = True
            for k in range(i + 1, j + 1):
                share = (times[k] - t0) / (t1 - t0)
                if abs(values[i] + (values[j + 1] - values[i]) * share - values[k]) > tol:
                    ok = False
                    break
            if not ok:
                break
            j += 1
        keep.append(j)
        i = j
    return [times[k] for k in keep], [values[k] for k in keep]


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("baked")
    parser.add_argument("scene")
    parser.add_argument("out_dir")
    parser.add_argument("--standing", default="OutsideOpen,OutsideClose")
    parser.add_argument("--door-tol", type=float, default=0.004)
    args = parser.parse_args(argv)
    baked = json.load(open(args.baked, encoding="utf-8"))
    scene = np.load(args.scene, allow_pickle=False)
    a = scene["seat_to_authoring"]
    scale = float(scene["scale"])
    root_s = rigid_to_authoring(a, scene["root_in_seat"])
    root_m = np.identity(4)
    root_m[1, 3] = 3.0
    c0 = np.identity(4)
    c0[:3, :3] = ROOT_ROT
    rebase = np.linalg.inv(c0) @ np.linalg.inv(root_s) @ root_m @ c0
    a_inv = np.linalg.inv(a)
    standing = set(args.standing.split(","))
    fps = baked["fps"]
    by_frame = {round(f["frame"]): f for f in baked["frames"]}
    os.makedirs(args.out_dir, exist_ok=True)
    summary = {}
    for clip in baked["clips"]:
        name, start, end = clip["name"], clip["start"], clip["end"]
        frames = [by_frame[f] for f in range(start, end + 1)]
        seated, stood, seat_parts = [], [], []
        for f in frames:
            t = (f["frame"] - start) / fps
            poses = dict(f["poses"])
            stood.append({"frame": f["frame"] - start, "time": t, "poses": dict(poses)})
            poses["RootJoint"] = flat(rebase @ mat(f["poses"]["RootJoint"]))
            seated.append({"frame": f["frame"] - start, "time": t, "poses": poses})
            parts = {}
            for part, values in f["parts"].items():
                m = mat(values)
                world = np.identity(4)
                world[:3, :3] = (a_inv[:3, :3] / scale) @ m[:3, :3]
                world[:3, 3] = a_inv[:3, :3] @ m[:3, 3] + a_inv[:3, 3]
                parts[part] = flat(world)
            seat_parts.append({"time": t, "parts": parts})
        with open(os.path.join(args.out_dir, f"{name}.seated.json"), "w", encoding="utf-8", newline="\n") as h:
            json.dump({"fps": fps, "frames": seated}, h)
        if name in standing:
            with open(os.path.join(args.out_dir, f"{name}.standing.json"), "w", encoding="utf-8", newline="\n") as h:
                json.dump({"fps": fps, "frames": stood}, h)
        with open(os.path.join(args.out_dir, f"{name}.seatparts.json"), "w", encoding="utf-8", newline="\n") as h:
            json.dump({"fps": fps, "frames": seat_parts}, h)
        door = [float(f.get("door", 0.0)) for f in frames]
        moving = max(door) - min(door) > 1e-4
        entry = {"duration": round((end - start) / fps, 4), "frames": end - start + 1}
        if moving:
            times = [round((f["frame"] - start) / fps, 4) for f in frames]
            values = [round(min(1.0, max(0.0, v)), 4) for v in door]
            # The ends are exact rests: an opening clip runs 0 to 1, a closing one 1 to 0.
            values[0] = round(values[0])
            values[-1] = round(values[-1])
            # Trim the held stretches at both ends: the curve holds past its ends anyway.
            first = next(i for i in range(len(values)) if values[i] != values[0]) - 1
            last = len(values) - next(i for i in range(len(values)) if values[-1 - i] != values[-1])
            tt, vv = thin(times[first : last + 1], values[first : last + 1], args.door_tol)
            entry["door"] = {"times": tt, "values": vv}
            with open(os.path.join(args.out_dir, f"{name}.door.json"), "w", encoding="utf-8", newline="\n") as h:
                json.dump(entry["door"], h)
        summary[name] = entry
    with open(os.path.join(args.out_dir, "clips.json"), "w", encoding="utf-8", newline="\n") as h:
        json.dump(summary, h, indent=1)
    for name, entry in summary.items():
        door = entry.get("door")
        print(f"{name}: {entry['duration']} s, {entry['frames']} frames" + (f", door {len(door['times'])} points" if door else ""))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
