"""
Builds the car-entry scene file the Blender scene and the checks read: the car's meshes in the
AUTHORING frame (r6_rig's RobloxSpace: the door mark's standing root at (0, 3, 0) facing -Z,
the world divided by the driver's scale), the door split off on its hinge, the frames the clips
are exported in, and the review cameras.

  python -I car_entry_prep.py --seat SEAT_WELD.json --glb car.glb --manifest manifest.json
      [--door door_dump.npz --handoff HANDOFF.json] --mark -0.92,0 --out scene.npz

Without a door dump the closed car stands in, with the door's hinge left at rest (used before
the door is cut out, for the seat and the mark).
"""
import argparse
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from car_scene import Scene, apply  # noqa: E402


def authoring_matrix(scene):
    """Seat frame -> authoring frame: T(0, 3, 0) * S(1 / scale) * mark^-1."""
    m = np.identity(4)
    m[:3, :3] /= scene.scale
    shift = np.identity(4)
    shift[1, 3] = 3.0
    return shift @ m @ np.linalg.inv(scene.mark)


def rigid_to_authoring(a, frame):
    """A rigid frame in the seat frame as a rigid frame in the authoring frame: same turn,
    position divided by the scale."""
    out = np.identity(4)
    turn = a[:3, :3] / np.cbrt(np.linalg.det(a[:3, :3]))
    out[:3, :3] = turn @ frame[:3, :3]
    out[:3, 3] = apply(a, frame[:3, 3][None, :])[0]
    return out


def cameras(a, scene):
    """Review cameras, authoring frame (Roblox axes): beside the car, the game's third-person
    framing from behind the mark, from above, and the driver's eye."""
    seat = apply(a, np.zeros((1, 3)))[0]
    mid = (seat + np.array([0.0, 3.0, 0.0])) / 2
    return {
        # Outside, ahead of the door and low: the body's profile as it goes in, the sill and the
        # raised door in one view.
        "side": [[mid[0] - 12.0, 3.4, mid[2] + 4.5], [mid[0] + 0.5, 2.8, mid[2]], 26],
        # Roblox's default third person: behind and above the character as it faces the car.
        "game": [[0.0, 6.2, 13.5], [mid[0], 3.2, mid[2]], 22],
        "top": [[mid[0], 24.0, mid[2] + 0.01], [mid[0], 0.0, mid[2]], 30],
        # "eye" is not here: it rides the animated head (car_entry_scene.py render).
    }


BLENDER_TO_IMPORT = 1 / 0.28  # the hero car .blend is in metres at real scale


def blender_to_import(points, placement):
    """The hero car .blend (metres; nose -Y, Z up, driver +X) to CarImport's frame, through the
    export's own placement (points.json "placement": Blender -> its studs, Blender axes), then
    Roblox's axes as the glTF import reads them: (x, y, z) -> (-x, z, y) (a proper rotation)."""
    p = np.asarray(points, dtype=float)
    m = np.asarray(placement, dtype=float)
    studs = p @ m[:3, :3].T + m[:3, 3]
    return np.stack([-studs[..., 0], studs[..., 2], studs[..., 1]], axis=-1)


def blender_axis_to_import(axis):
    a = np.asarray(axis, dtype=float)
    return np.array([-a[0], a[2], a[1]])


def door_proxy(scene, roles, a, box_import, margin=0.02):
    """Until the cut door exists: the closed car's triangles wholly inside the door's shut box."""
    lo, hi = box_import.min(axis=0) - margin, box_import.max(axis=0) + margin
    verts, tris, base = [], [], 0
    rest = {}
    for name, (v_imp, f) in scene.meshes.items():
        inside = np.all((v_imp >= lo) & (v_imp <= hi), axis=1)
        tri_in = inside[f].all(axis=1)
        role = roles.get(name, "trim")
        if tri_in.any() and role not in ("wheel", "caliper", "underbody", "engine", "light", "plate"):
            v, _ = scene.car_in_seat(name)
            verts.append(apply(a, v))
            tris.append(f[tri_in] + base)
            base += len(v)
        rest[name] = ~tri_in
    if not verts:
        return None, rest
    return (np.concatenate(verts), np.concatenate(tris)), rest


def role_of(name):
    """A rendering colour group from a .blend object's name."""
    lowered = name.lower()
    for key, role in (
        ("sill", "sill"),
        ("window", "glass"),
        ("glass", "glass"),
        ("paint", "paint"),
        ("carbon", "carbon"),
        ("interior", "interior"),
        ("steering", "interior"),
        ("engine", "engine"),
        ("light", "light"),
        ("base", "underbody"),
        ("wheel", "wheel"),
        ("tyre", "wheel"),
        ("rim", "wheel"),
        ("caliper", "wheel"),
    ):
        if key in lowered:
            return role
    return "trim"


def sill_mesh(slices):
    """The sill agent B models where the door used to cover it, from its slices
    [y, top z, lip x, lip z, inner x, inner z] (.blend metres): a flat top from the inner wall to
    the lip, the lip standing up on the outside, the cabin wall on the inside."""
    verts, tris = [], []
    for i, (y, tz, lx, lz, ix, iz) in enumerate(slices):
        verts += [(ix, y, iz), (ix, y, tz), (lx, y, tz), (lx, y, lz)]
        if i:
            a, b = 4 * (i - 1), 4 * i
            for k in range(3):
                tris += [(a + k, a + k + 1, b + k + 1), (a + k, b + k + 1, b + k)]
    return np.array(verts, dtype=float), np.array(tris, dtype=np.int64)


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--seat", required=True)
    parser.add_argument("--glb", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--points", help="the export's points.json (its Blender placement)")
    parser.add_argument("--hinge", help="hinge JSON in .blend metres: pivot, axis, openDegrees, shutBox")
    parser.add_argument("--door-points", help="JSON {name: [x, y, z]} door points in .blend metres, shut")
    parser.add_argument("--sill", help="agent B's door_selection.json (its sill slices)")
    parser.add_argument("--dump", help="tools/blender/car_entry_dump.py of the rigged door blend: the cut car, the door")
    parser.add_argument("--mark", default="-0.92,0")
    parser.add_argument("--out", required=True)
    parser.add_argument("--door-json", help="write the door spec (authoring frame) the keys read")
    args = parser.parse_args(argv)
    mark = tuple(float(v) for v in args.mark.split(","))
    scene = Scene(args.seat, args.glb, mark)
    roles = {p["name"]: p["role"] for p in json.load(open(args.manifest, encoding="utf-8"))["parts"]}
    a = authoring_matrix(scene)

    def blend_to_authoring(points):
        imp = blender_to_import(points, placement)
        body = imp * scene.k + scene.offsets["body"]
        return apply(a, np.atleast_2d(body))

    door, keep = None, {}
    if args.hinge:
        placement = json.load(open(args.points, encoding="utf-8"))["placement"]
        hinge = json.load(open(args.hinge, encoding="utf-8"))
        if not args.dump:
            box = blender_to_import(np.array(hinge["shutBox"]), placement)
            door, keep = door_proxy(scene, roles, a, box)
        pivot = blend_to_authoring([hinge["pivot"]])[0]
        turn = a[:3, :3] / np.cbrt(np.linalg.det(a[:3, :3]))
        axis = turn @ blender_axis_to_import(hinge["axis"])
        axis /= np.linalg.norm(axis)
        points = json.load(open(args.door_points, encoding="utf-8"))
        spec = {
            "about": "Door hinge and contact points in the authoring frame (car_entry_prep.py).",
            "source": {"hinge": args.hinge, "points": args.door_points},
            "hinge": {"pivot": pivot.tolist(), "axis": axis.tolist(), "openDegrees": hinge["openDegrees"]},
            "points": {k: blend_to_authoring([v])[0].tolist() for k, v in points.items() if k != "about"},
        }
        if args.door_json:
            with open(args.door_json, "w", encoding="utf-8", newline="\n") as handle:
                json.dump(spec, handle, indent=1)
    groups = {}
    if args.dump:
        # The cut car from the rigged door blend: the body without its door (the sill is B's
        # DoorSill object), the door's parts posed on their own.
        placement = json.load(open(args.points, encoding="utf-8"))["placement"]
        dump = np.load(args.dump, allow_pickle=False)
        door_parts = []
        for k, name in enumerate(dump["names"]):
            v = blend_to_authoring(dump[f"v{k}"].astype(float))
            f = dump[f"f{k}"].astype(np.int64)
            if dump["door"][k]:
                door_parts.append((v, f))
            else:
                groups.setdefault(role_of(str(name)), []).append((v, f))
        base, verts, tris = 0, [], []
        for v, f in door_parts:
            verts.append(v)
            tris.append(f + base)
            base += len(v)
        door = (np.concatenate(verts), np.concatenate(tris))
    else:
        for name in scene.meshes:
            v, f = scene.car_in_seat(name)
            if name in keep:
                f = f[keep[name]]
            role = roles.get(name, "trim")
            role = "wheel" if role == "caliper" else role
            groups.setdefault(role, []).append((apply(a, v), f))
    if args.sill and not args.dump:
        if not args.points:
            raise SystemExit("--sill needs --points (the .blend placement)")
        placement = json.load(open(args.points, encoding="utf-8"))["placement"]
        slices = json.load(open(args.sill, encoding="utf-8"))["sill"]["slices"]
        sv, sf = sill_mesh(slices)
        groups["sill"] = [(blend_to_authoring(sv), sf)]
    out = {}
    for role, items in groups.items():
        base, verts, tris = 0, [], []
        for v, f in items:
            verts.append(v)
            tris.append(f + base)
            base += len(v)
        out[f"v_{role}"] = np.concatenate(verts).astype(np.float32)
        out[f"f_{role}"] = np.concatenate(tris).astype(np.int32)
    out["groups"] = np.array(sorted(groups))
    if door is not None:
        out["v_door"] = door[0].astype(np.float32)
        out["f_door"] = door[1].astype(np.int32)
        out["hinge_pivot"] = np.array(spec["hinge"]["pivot"])
        out["hinge_axis"] = np.array(spec["hinge"]["axis"])
        out["open_angle"] = np.array(np.radians(spec["hinge"]["openDegrees"]))
    else:
        out["hinge_pivot"] = np.zeros(3)
        out["hinge_axis"] = np.array([1.0, 0.0, 0.0])
        out["open_angle"] = np.array(0.0)
    out["seat_to_authoring"] = a
    out["scale"] = np.array(scene.scale)
    out["root_in_seat"] = scene.root
    out["mark_in_seat"] = scene.mark
    out["ground_y_seat"] = np.array(scene.ground_y)
    out["map_error"] = np.array([scene.map_error["body"], scene.map_error.get("wheel", 0.0)])
    out["cameras"] = np.array(json.dumps(cameras(a, scene)))
    np.savez_compressed(args.out, **out)
    seat_root = scene.root[:3, 3]
    print(f"scale {scene.scale:.4f}  k {scene.k:.4f}  map error body {scene.map_error['body']:.4f} studs")
    print(f"root in seat {np.round(seat_root, 3)}  mark in seat {np.round(scene.mark[:3, 3], 3)}")
    print(f"ground in seat y {scene.ground_y:.3f}; groups {sorted(groups)}")


if __name__ == "__main__":
    main(sys.argv[1:])
