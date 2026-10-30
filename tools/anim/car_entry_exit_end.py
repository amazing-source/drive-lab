"""
Finds where getting out ends and prints the exitEnd field of a car's door
(games/drive-lab/src/shared/Config/Cars/<Car>/Door.luau) from the exit timeline's bake.

OutsideClose shuts the door, then walks back in to the door mark, where the car's collision box
is too close for the body to turn. Getting out ends earlier, at a frame of that walk back where
the body stands as at rest (feet together, upright, facing the car) and far enough out: the
server puts the root under it there, so nothing jumps.

  python car_entry_exit_end.py <exit.baked.json> --mark -0.88,0 [--min-outward 1.0] [--max-pose 0.1]

--min-outward: game studs the stance must stand further out than the mark. Measured in Studio on
the SVJ (2026-10-28): the collision box's side is 0.659 studs in front of the mark and a scale-1
R6 torso sweeps 1.118 studs from its root as it turns, so anything under 0.46 hits the box.
--max-pose: game studs any corner of any body part may stand off the rest pose, the root moved
under the torso.

The bake's frame is the exporter's: the standing root at the mark at (0, 3, 0), -Z toward the
seat, +X toward the car's rear, in studs at body scale 1. The mark stands left of the seat
facing it (a negative `right`), as for the SVJ's driver's door.
"""
import argparse
import json
import sys

import numpy as np

DRIVER_SCALE = 1.5 / 1.75
METRES_PER_STUD = 0.28 / 1.5
PARTS = {
    "Torso": (2, 2, 1),
    "Head": (2, 1, 1),
    "Right Arm": (1, 2, 1),
    "Left Arm": (1, 2, 1),
    "Right Leg": (1, 2, 1),
    "Left Leg": (1, 2, 1),
}
CORNERS = {
    name: np.array([[sx * x / 2, sy * y / 2, sz * z / 2] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)])
    for name, (x, y, z) in PARTS.items()
}


def body_points(frame):
    """Every corner of every part, with the torso's horizontal position taken out."""
    torso = np.array(frame["parts"]["Torso"][:3])
    shift = np.array([torso[0], 0.0, torso[2]])
    points = []
    for name in PARTS:
        cframe = frame["parts"][name]
        rotation = np.array(cframe[3:]).reshape(3, 3)
        points.append(CORNERS[name] @ rotation.T + np.array(cframe[:3]) - shift)
    return np.concatenate(points)


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("baked")
    parser.add_argument("--mark", required=True)
    parser.add_argument("--min-outward", type=float, default=1.0)
    parser.add_argument("--max-pose", type=float, default=0.1)
    args = parser.parse_args(argv)
    mark_right, mark_forward = (float(v) for v in args.mark.split(","))
    if mark_right >= 0:
        sys.exit("the mark must stand left of the seat (negative right)")
    data = json.load(open(args.baked, encoding="utf-8"))
    fps, frames = data["fps"], data["frames"]
    clip = next(c for c in data["clips"] if c["name"] == "OutsideClose")
    start, end = clip["start"], clip["end"]
    rest = body_points(frames[end])
    shut = next(i for i in range(start, end + 1) if (frames[i].get("door") or 0) <= 0)
    best = None
    print(f"OutsideClose frames {start}-{end}, door shut from frame {shut}")
    for index in range(shut, end + 1):
        frame = frames[index]
        pose = float(np.max(np.linalg.norm(body_points(frame) - rest, axis=1))) * DRIVER_SCALE
        torso = frame["parts"]["Torso"]
        outward = torso[2] * DRIVER_SCALE
        if pose <= args.max_pose:
            print(f"  frame {index}: {(index - start) / fps:.4f} s, pose {pose:.4f}, outward {outward:.4f}")
            if outward >= args.min_outward and (best is None or pose < best[1]):
                best = (index, pose, torso)
    if best is None:
        sys.exit("no stance stands far enough out within the pose tolerance")
    index, pose, torso = best
    at = (index - start) / fps
    right = mark_right - torso[2] * DRIVER_SCALE * METRES_PER_STUD
    forward = mark_forward - torso[0] * DRIVER_SCALE * METRES_PER_STUD
    print(f"chosen frame {index}: pose {pose:.4f} studs off rest, torso height {torso[1]:.4f} (rest 3)")
    print(f"\texitEnd = table.freeze({{ at = {at:.3f}, right = {right:.4f}, forward = {forward:.4f} }}),")


if __name__ == "__main__":
    main(sys.argv[1:])
