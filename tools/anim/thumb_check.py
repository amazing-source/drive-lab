"""Contact and penetration check for thumb presses (tools/blender/thumb_press.py's output): each
press hand against the wheel it grips, and against the rest of the cabin with the wheel turned.

  python tools/anim/thumb_check.py <thumbs inputs.json> <thumbs dir> [--json <out.json>]
      [--steer <degrees>,...] [--break <metres>]

For every button thumbs.json reports reached:
- the hand mesh against the wheel's own parts, in the wheel's frame: a vertex is inside when most
  of its eight nearest surface samples face away from it, within MAX_DEPTH of them, and on a
  closed object a ray's parity agrees (as tools/anim/startup_check.py, samples fixed per
  triangle). Allowed: the pressed button up to PRESS_LIMIT (the pad pushes it
  2 mm), the rim up to GRIP_LIMIT (the grip's own fit); anything else fails above HAND_LIMIT;
- the pad must touch: some vertex within TOUCH_GAP of the button's face;
- the hand turned with the wheel to each steering angle (default 0 and +-90 degrees: the hands
  follow the wheel to 110 in Controllers/DriverArms) against every cabin part that does not turn
  with it (the column, the paddles, the binnacle, the dash, the cage), failing above HAND_LIMIT.

With `--pick`, each button's candidates (thumb_press.py exports every pose that reaches, in the
order its inputs list them) are checked in turn, and the first that passes is copied to
hand_{side}_{name}.glb and written as the button's entry in thumbs.json, with every candidate's
result kept under "picked". A button with no passing candidate keeps none.

`--break 0.01` pushes every press hand 1 cm along the wheel's axis into the wheel to show the
check failing. Exits 1 on any failure.
"""

import hashlib
import json
import math
import os
import shutil
import sys

import numpy as np
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from startup_check import inside_depth, parity_inside, read_glb, surface_samples  # noqa: E402

HAND_LIMIT = 0.002
PRESS_LIMIT = 0.003
GRIP_LIMIT = 0.003
TOUCH_GAP = 0.001
WHEEL_PARTS = ("SteeringWheel", "WheelButton", "WheelRotary")


def wheel_frame(config):
    hub = config["steeringHub"]
    z = np.array(hub["axis"], float)
    z /= np.linalg.norm(z)
    x = np.array([1.0, 0, 0])
    x -= z * (x @ z)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    centre = np.array(hub["pivot"], float) + np.array([0, config.get("steeringWheelLift", 0), 0])
    return np.stack([x, y, z], 1), centre


def rotation_z(degrees):
    a = math.radians(degrees)
    return np.array([[math.cos(a), -math.sin(a), 0], [math.sin(a), math.cos(a), 0], [0, 0, 1]])


def main(argv):
    inputs = json.load(open(argv[0]))
    out_dir = argv[1]
    report = json.load(open(os.path.join(out_dir, "thumbs.json")))
    steer = [float(a) for a in argv[argv.index("--steer") + 1].split(",")] if "--steer" in argv else [0.0, 90.0, -90.0]
    push = float(argv[argv.index("--break") + 1]) if "--break" in argv else 0.0
    config = json.load(open(inputs["startupConfig"]))
    axes, centre = wheel_frame(config)
    data = np.load(inputs["cabin"])
    rel = data["vertices"].astype(float) - np.array(inputs["seat"])
    seat = np.stack([-rel[:, 0], rel[:, 2], rel[:, 1]], 1)
    wheel_local = (seat - centre) @ axes
    names = list(data["names"])
    owner, tris = data["object"], data["triangles"]
    turning = np.array([names[o].startswith(WHEEL_PARTS) for o in owner])
    near_wheel = np.all(np.abs(wheel_local[tris].mean(1)) < 0.35, 1)

    # Samples fixed per triangle, and ray parity on closed objects, as tools/anim/startup_check.py.
    p, n, tri = surface_samples(wheel_local, tris[turning], 0.0015, np.flatnonzero(turning))
    wheel_obj = owner[turning][tri]
    wheel_tree = cKDTree(p)
    fixed = ~turning & near_wheel
    q, m, tri2 = surface_samples(wheel_local, tris[fixed], 0.0015, np.flatnonzero(fixed))
    fixed_obj = owner[fixed][tri2]
    fixed_tree = cKDTree(q)
    closed = {}

    def confirmed(points, depth, idx, objects):
        """Keep a vote only where the object's surface is open, or a ray's parity agrees."""
        flagged = np.flatnonzero(depth > 0)
        for obj in np.unique(objects[idx[flagged]]):
            if obj not in closed:
                faces = tris[owner == obj]
                edges = np.sort(np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]]), axis=1)
                _, counts = np.unique(edges, axis=0, return_counts=True)
                closed[obj] = wheel_local[faces] if np.all(counts == 2) else None
            if closed[obj] is not None:
                mine = flagged[objects[idx[flagged]] == obj]
                depth[mine[~parity_inside(points[mine], closed[obj])]] = 0.0
        return depth

    def check(name, entry, path):
        found = []
        hand = read_glb(path)
        hand = hand + np.array([0, 0, -push])
        depth, idx = inside_depth(wheel_tree, p, n, hand)
        depth = confirmed(hand, depth, idx, wheel_obj)
        worst = {}
        for k in np.flatnonzero(depth > 0):
            obj = names[wheel_obj[idx[k]]]
            worst[obj] = max(worst.get(obj, 0.0), float(depth[k]))
        row = {"button": name, "side": entry["side"], "slideDeg": entry.get("slideDeg", 0), "rollDeg": entry.get("rollDeg", 0), "wheelMm": {k: round(v * 1000, 2) for k, v in worst.items()}}
        for obj, d in worst.items():
            limit = PRESS_LIMIT if obj == entry["part"] or obj.startswith(entry["part"]) else GRIP_LIMIT if obj.startswith("SteeringWheel_Rim") else HAND_LIMIT
            if d > limit:
                found.append((name, obj, round(d * 1000, 2), "wheel"))
        face = np.array(entry["faceWheel"])
        touch = float(np.linalg.norm(hand - face, axis=1).min())
        pad_gap = max(0.0, touch - 0.0)
        own = np.flatnonzero([names[o] == entry["part"] for o in wheel_obj])
        if len(own):
            pad_gap = float(cKDTree(p[own]).query(hand)[0].min())
        row["touchMm"] = round(pad_gap * 1000, 2)
        if pad_gap > TOUCH_GAP:
            found.append((name, entry["part"], round(pad_gap * 1000, 2), "float"))
        row["steeredMm"] = {}
        for angle in steer:
            turned = hand @ rotation_z(angle).T
            d2, idx2 = inside_depth(fixed_tree, q, m, turned)
            d2 = confirmed(turned, d2, idx2, fixed_obj)
            hit = {}
            for k in np.flatnonzero(d2 > 0):
                obj = names[fixed_obj[idx2[k]]]
                hit[obj] = max(hit.get(obj, 0.0), float(d2[k]))
            row["steeredMm"][str(angle)] = {k: round(v * 1000, 2) for k, v in hit.items()}
            for obj, d in hit.items():
                if d > HAND_LIMIT:
                    found.append((name, obj, round(d * 1000, 2), f"steered {angle:g}"))
        return row, found

    failures, rows = [], []
    for name, entry in report["buttons"].items():
        if "--pick" in argv and entry.get("candidates"):
            tried = []
            for candidate in entry["candidates"]:
                row, found = check(name, candidate, os.path.join(out_dir, candidate["file"]))
                tried.append({"file": candidate["file"], "pass": not found, "row": row, "failures": found})
                if not found:
                    chosen = dict(candidate)
                    chosen["candidates"] = entry["candidates"]
                    chosen["picked"] = tried
                    shutil.copyfile(os.path.join(out_dir, candidate["file"]), os.path.join(out_dir, f"hand_{entry['side']}_{name}.glb"))
                    report["buttons"][name] = entry = chosen
                    break
            else:
                entry["reached"] = False
                entry["picked"] = tried
                print(name, "no candidate passes:", [t["failures"][:2] for t in tried])
        if not entry["reached"]:
            rows.append({"button": name, "reached": False})
            failures.append((name, entry["part"], None, "unreached"))
            continue
        row, found = check(name, entry, os.path.join(out_dir, f"hand_{entry['side']}_{name}.glb"))
        failures.extend(found)
        rows.append(row)
        print(json.dumps(row))
    if "--pick" in argv:
        json.dump(report, open(os.path.join(out_dir, "thumbs.json"), "w"), indent=1)
    result = {
        "thumbs": os.path.join(out_dir, "thumbs.json"),
        "thumbsSha256": hashlib.sha256(open(os.path.join(out_dir, "thumbs.json"), "rb").read()).hexdigest(),
        "cabinSha256": hashlib.sha256(open(inputs["cabin"], "rb").read()).hexdigest(),
        "mutation": push or None,
        "steerDeg": steer,
        "rows": rows,
        "failures": failures,
        "pass": not failures,
    }
    for f in failures[:20]:
        print("FAIL", f)
    print("PASS" if result["pass"] else f"FAIL ({len(failures)})", "mutation:", result["mutation"])
    if "--json" in argv:
        json.dump(result, open(argv[argv.index("--json") + 1], "w"), indent=1)
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
