"""
The car-entry scene file (as car_entry_prep.py writes for the SVJ) for a car whose cabin comes from a
manifest-built model instead of a Studio-measured import: the cockpit dumped from the assembled
blend in car metres, the seat at the manifest's hip point, the door on its manifest hinge.

  python -I car_entry_prep_manifest.py --dump cockpit.npz --manifest manifest.json
      --pose seated_pose.json --mark <right,forward> [--open-deg 75] --out scene.npz

Frames: the dump is Blender metres (x = car's left, y = -forward, z up, origin the rear-axle midpoint
on the ground); the seat frame is the DriverSeat part's (x right, y up, z back, world studs), at the
manifest's Driver_HPoint; the authoring frame is r6_rig's RobloxSpace at scale 1 with the standing
root at the mark at (0, 3, 0) facing -Z, the car divided by the driver's scale about it.
`--pose` gives the driver's scale and the root above the seat (the SeatWeld's offset).
"""
import argparse
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from car_scene import yaw_frame  # noqa: E402

STUD = 0.28 / 1.5
TO_SEAT = np.array([[-1.0, 0, 0], [0, 0, 1.0], [0, 1.0, 0]])
# Object name prefixes -> scene groups (the check reports and allows by group).
GROUPS = (
    ("cage", ("Cage_", "WindowNet")),
    ("seat", ("Seat_",)),
    ("harness", ("Harness_",)),
    ("wheel", ("SteeringWheel", "WheelButton", "WheelRotary", "SteeringColumn", "Paddle_")),
    ("sill", ("fer_f142_10_s_lod0_body_rubber_trim_",)),
    ("cabin", ("Cabin", "Tunnel", "Switch", "Panel", "Pedal", "Binnacle", "Duct", "ShiftLight", "fer_f142_10_cockpit_s_interior")),
)


def group_of(name):
    for group, prefixes in GROUPS:
        if name.startswith(prefixes):
            return group
    return "body"


def to_blender(p):
    return np.array([-p["right"], -p["forward"], p["up"]], dtype=float)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--dump", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--pose", required=True)
    ap.add_argument("--mark", required=True)
    ap.add_argument("--open-deg", type=float, default=None)
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)
    manifest = json.load(open(args.manifest, encoding="utf-8"))
    pose = json.load(open(args.pose, encoding="utf-8"))
    parts = {p["name"]: p for p in manifest["parts"]}
    seat_point = to_blender(next(v for k, v in (manifest.get("points") or {}).items() if k == "Driver_HPoint")) if manifest.get("points") else None
    if seat_point is None:
        sp = pose["seat_point_manifest"]
        seat_point = to_blender(sp)
    k = float(pose["scale"])

    def seat(p):
        return (np.asarray(p, float) - seat_point) @ TO_SEAT.T / STUD

    ground_y = float(seat([seat_point[0], seat_point[1], 0.0])[1])
    right, forward = (float(v) for v in args.mark.split(","))
    point = np.array([right / STUD, 0.0, -forward / STUD])
    mark = yaw_frame(point, -point)
    mark[1, 3] = ground_y + 3.0 * k
    a = np.identity(4)
    a[:3, :3] /= k
    shift = np.identity(4)
    shift[1, 3] = 3.0
    a = shift @ a @ np.linalg.inv(mark)

    def author(p):
        s = seat(p)
        return s @ a[:3, :3].T + a[:3, 3]

    d = np.load(args.dump)
    v, t, o = d["vertices"].astype(float), d["triangles"], d["object"]
    names = [str(n) for n in d["names"]]
    door_names = {"Door_L_Card", "Door_L_PullLoop"}
    for part in manifest["parts"]:
        if part.get("group") == "Door_L":
            door_names.update(part.get("objects") or [])
    is_door = np.array([n in door_names for n in names])
    out = {}
    groups = {}
    for i, name in enumerate(names):
        tri = t[o == i]
        if not len(tri):
            continue
        g = "door" if is_door[i] else group_of(name)
        groups.setdefault(g, []).append(tri)
    authored = author(v)
    for g, tris in groups.items():
        tri = np.concatenate(tris)
        used, inverse = np.unique(tri, return_inverse=True)
        out[f"v_{g}"] = authored[used].astype(np.float32)
        out[f"f_{g}"] = inverse.reshape(-1, 3).astype(np.int32)
    out["groups"] = np.array(sorted(g for g in groups if g != "door"))
    hinge = parts["Door_L_Skin"]
    out["hinge_pivot"] = author(to_blender(hinge["pivot"]))
    axis = to_blender(hinge["axis"]) @ TO_SEAT.T
    axis = axis @ (a[:3, :3] * k).T
    out["hinge_axis"] = axis / np.linalg.norm(axis)
    out["open_angle"] = np.array(np.radians(args.open_deg) if args.open_deg else float(hinge["range"]))
    root = np.identity(4)
    root[:3, 3] = np.array(pose["root_seat_studs_ASSUMED"], dtype=float)
    out["seat_to_authoring"] = a
    out["scale"] = np.array(k)
    out["driver_scale"] = np.array(k)
    out["root_in_seat"] = root
    out["mark_in_seat"] = mark
    out["ground_y_seat"] = np.array(ground_y)
    out["map_error"] = np.array([0.0, 0.0])
    seat_a = author(seat_point)
    mid = (seat_a + np.array([0.0, 3.0, 0.0])) / 2
    cams = {
        "side": [[mid[0] - 12.0, 3.4, mid[2] - 6.0], [mid[0] + 0.5, 2.8, mid[2]], 26],
        "game": [[0.0, 6.2, 13.5], [mid[0], 3.2, mid[2]], 22],
        "top": [[mid[0], 24.0, mid[2] + 0.01], [mid[0], 0.0, mid[2]], 30],
    }
    out["cameras"] = np.array(json.dumps(cams))
    np.savez_compressed(args.out, **out)
    print(f"scale {k}  groups {sorted(groups)}  ground y seat {ground_y:.3f}")
    print("seat point in authoring", np.round(seat_a, 3), "seated root in authoring", np.round(author(seat_point + TO_SEAT.T @ (root[:3, 3] * STUD)), 3))
    print("hinge", np.round(out["hinge_pivot"], 3), "axis", np.round(out["hinge_axis"], 3), "open deg", round(float(np.degrees(out["open_angle"])), 1))


if __name__ == "__main__":
    main(sys.argv[1:])
