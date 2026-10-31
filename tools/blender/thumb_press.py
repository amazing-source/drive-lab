"""
Thumb presses on the steering wheel's buttons: the grip hand of tools/blender/hand_grip.py with
only its thumb moved from the spoke onto each button the car uses, the fingers still round the
rim, exported as one more grip mesh per button and checked against the wheel.

    blender -b --factory-startup --python-exit-code 1 -P tools/blender/thumb_press.py -- <inputs.json> <out dir>

inputs.json names the CC0 source hand (hand), the grip's hands.json and its folder (grip,
gripDir: the grip must have been made with --thumb-spoke, so its thumb pose is recorded), the
cabin dump the wheel's buttons are measured on (cabin, seat: the DriverSeat's origin in it), the
wheel's hub in the seat frame (startupConfig: games/drive-lab/tools/startup_config.luau's
steeringHub) and the buttons: [{"name", "part", "side"}], each pressed by that side's thumb.

The grip is rebuilt, not re-solved: the fingers turned by hands.json's fingerAngles, the hand
placed in the wheel's frame from its wrist, forearm and back; the rebuild is measured against the
exported grip mesh before anything is trusted. The left hand is the right mirrored, so a left
button is solved as the right hand on the mirrored wheel.

For each button the thumb's metacarpal turn and its two curls are searched (coarse, then fine)
for the skin of the thumb's pad (its distal vertices, posed through the chain) on the button's
face, pressing up to PRESS deep within CAP_RADIUS of its centre, the rest of the thumb's skin off
the wheel, and the least change from the thumb's pose on the spoke. The skin, not a point along
the end bone: that bone runs past the skin and off its axis, and a bone point on the button left
the skin 14 to 17 mm off it. A button's slidesDeg (about the wheel's axis) and rollsDeg (about
the rim tube's tangent) list where the hand may go when the thumb cannot reach from the grip,
in order of preference. Every pose that reaches is exported as a candidate,
hand_{side}_{name}_s{slide}_r{roll}.glb; a button the pad cannot reach within REACH_GAP is
reported unreachable. tools/anim/thumb_check.py --pick keeps the first candidate whose exported
mesh passes.

Output: the candidates' glbs (studs, the wheel's frame, as hand_{side}.glb) and thumbs.json (per
button and candidate: the pad's height over the face and distance from its centre, the thumb's
clearance from the wheel, the joint turns, the moved grip's wrist frame and the mesh's centre).
"""

import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.kdtree import KDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hand_grip import STUDS_PER_METRE, bounds_centre, export_studs, studs  # noqa: E402

FINGERS = ("Index", "Middle", "Ring", "Little")
THUMB = ("Thumb_Metacarpal_R", "Thumb_Proximal_R", "Thumb_Distal_R", "Thumb_Tip_R")
# How deep the pad pushes the button's face, and how far off it may stop, metres.
PRESS = 0.002
REACH_GAP = 0.0005
# The pad's skin meets the face within this of the button's centre (its cap is 11.2 mm across).
CAP_RADIUS = 0.0045
# Away from the pad, the thumb's skin stays this far off the wheel.
SKIN_CLEAR = 0.001
WORLD_STUD = 0.28 / 1.5


def pose_about_world_z(arm, name, angle):
    bone = arm.pose.bones[name]
    axis = (bone.bone.matrix_local.to_3x3().inverted() @ Vector((0, 0, 1))).normalized()
    bone.rotation_mode = "QUATERNION"
    bone.rotation_quaternion = Quaternion(axis, angle)


def pose_world(arm, name, turn):
    bone = arm.pose.bones[name]
    rest = bone.bone.matrix_local.to_3x3()
    bone.rotation_mode = "QUATERNION"
    bone.rotation_quaternion = (rest.inverted() @ turn @ rest).to_quaternion()


def metacarpal(mz, mx, my):
    rad = math.radians
    return Matrix.Rotation(rad(mz), 3, "Z") @ Matrix.Rotation(rad(mx), 3, "X") @ Matrix.Rotation(rad(my), 3, "Y")


def read_glb_studs(path):
    import struct

    data = open(path, "rb").read()
    length = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20 : 20 + length])
    blob = data[20 + length + 8 :]
    verts = []
    for mesh in gltf["meshes"]:
        for prim in mesh["primitives"]:
            acc = gltf["accessors"][prim["attributes"]["POSITION"]]
            view = gltf["bufferViews"][acc["bufferView"]]
            start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
            verts.append(np.frombuffer(blob, dtype=np.float32, count=acc["count"] * 3, offset=start).reshape(-1, 3))
    # The exporter's half turn about y; studs -> metres: the wheel's frame.
    return np.concatenate(verts).astype(float) * np.array([-1.0, 1.0, -1.0]) * WORLD_STUD


def wheel_frame(config):
    hub = config["steeringHub"]
    z = Vector(hub["axis"]).normalized()
    x = Vector((1, 0, 0))
    x = (x - z * x.dot(z)).normalized()
    m = Matrix((x, z.cross(x), z)).transposed().to_4x4()
    m.translation = Vector(hub["pivot"]) + Vector((0, config.get("steeringWheelLift", 0), 0))
    return m


def wheel_parts(cabin, seat_origin, to_wheel):
    """The wheel's objects from the cabin dump, in the wheel's frame (metres), by name."""
    data = np.load(cabin)
    names = list(data["names"])
    verts, tris, owner = data["vertices"].astype(float), data["triangles"], data["object"]
    rel = verts - np.array(seat_origin)
    seat = np.stack([-rel[:, 0], rel[:, 2], rel[:, 1]], 1)
    rot = np.array(to_wheel.to_3x3())
    pos = np.array(to_wheel.translation)
    parts = {}
    for index, name in enumerate(names):
        if not name.startswith(("SteeringWheel", "WheelButton", "WheelRotary")):
            continue
        faces = tris[owner == index]
        used = np.unique(faces)
        local = (seat[used] - pos) @ rot
        remap = {int(v): k for k, v in enumerate(used)}
        parts[name] = (local, np.array([[remap[int(v)] for v in f] for f in faces]))
    return parts


def surface(points, faces, spacing=0.002):
    a, b, c = points[faces[:, 0]], points[faces[:, 1]], points[faces[:, 2]]
    area = 0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=1)
    k = np.maximum(1, np.ceil(area / (spacing * spacing * 0.5))).astype(int)
    tri = np.repeat(np.arange(len(faces)), k)
    rng = np.random.default_rng(0)
    r1, r2 = rng.random(len(tri)), rng.random(len(tri))
    f = r1 + r2 > 1
    r1[f], r2[f] = 1 - r1[f], 1 - r2[f]
    return a[tri] + (b[tri] - a[tri]) * r1[:, None] + (c[tri] - a[tri]) * r2[:, None]


def kd(points):
    tree = KDTree(len(points))
    for i, p in enumerate(points):
        tree.insert(Vector(p), i)
    tree.balance()
    return tree


def grip_place(grip_side, wrist_rest):
    """The grip's rest-space -> wheel-frame transform, from hands.json's wrist (studs) and its
    forearm (the rest space's -y turned) and back (+x turned) directions."""
    back = Vector(grip_side["back"]).normalized()
    forearm = Vector(grip_side["forearm"]).normalized()
    y = -forearm
    x = (back - y * back.dot(y)).normalized()
    turn = Matrix((x, y, x.cross(y))).transposed()
    m = turn.to_4x4()
    m.translation = Vector(grip_side["wrist"]) / STUDS_PER_METRE - turn @ wrist_rest
    return m


class ThumbSkin:
    """The thumb's skin vertices (rest space), each carried by the bone that weighs most on it,
    posed through the same chain as thumb_chain: a pose is scored on the real skin, not on a
    point along a bone (the end bone runs past the skin and off its axis)."""

    def __init__(self, hand, bones):
        groups = {g.index: g.name for g in hand.vertex_groups}
        self.rest = [bones[THUMB[0]].head_local.copy()] + [bones[n].tail_local.copy() for n in THUMB]
        heads = {THUMB[0]: 0, THUMB[1]: 1, THUMB[2]: 2, THUMB[3]: 3}
        points, carried = [], []
        for v in hand.data.vertices:
            if not v.groups:
                continue
            g = max(v.groups, key=lambda g: g.weight)
            name = groups.get(g.group)
            if name in heads and g.weight > 0.5:
                points.append(hand.matrix_world @ v.co)
                carried.append(heads[name])
        self.local = np.array([tuple(p - self.rest[b]) for p, b in zip(points, carried)])
        self.bone = np.array(carried)
        # The pad is on the last two bones (the distal phalanx and its end).
        self.end = self.bone >= 2

    def posed(self, pose):
        mz, mx, my, curl = pose
        turn = metacarpal(mz, mx, my)
        proximal, distal = math.radians(curl * 0.4), math.radians(curl * 0.6)
        chain = thumb_chain_from(self.rest, turn, proximal, distal)
        r1 = turn @ Matrix.Rotation(proximal, 3, "Z")
        r2 = r1 @ Matrix.Rotation(distal, 3, "Z")
        rots = [np.array(turn), np.array(r1), np.array(r2), np.array(r2)]
        out = np.empty_like(self.local)
        for b in range(4):
            m = self.bone == b
            out[m] = self.local[m] @ rots[b].T + np.array(chain[b])
        return out


def thumb_chain_from(rest, turn, proximal, distal):
    out = [rest[0]]
    rot = turn
    out.append(out[0] + rot @ (rest[1] - rest[0]))
    rot = turn @ Matrix.Rotation(proximal, 3, "Z")
    out.append(out[1] + rot @ (rest[2] - rest[1]))
    rot = rot @ Matrix.Rotation(distal, 3, "Z")
    out.append(out[2] + rot @ (rest[3] - rest[2]))
    out.append(out[3] + rot @ (rest[4] - rest[3]))
    return out


def solve(skin, obstacles, face, normal, start):
    """The thumb pose whose pad skin meets the button's face (rest space: its centre and outward
    normal) PRESS deep within CAP_RADIUS of the centre, the rest of the thumb's skin at least
    SKIN_CLEAR off the wheel (`obstacles`, a KD tree without the button), with the least change
    from `start` (mz, mx, my, curl). Returns the pose, the pad's height over the face (negative:
    pressed in), its distance from the face's centre, and the thumb's least clearance."""
    f, nrm = np.array(face), np.array(normal)
    ends = np.flatnonzero(skin.end)

    def contact(pose):
        pts = skin.posed(pose)
        rel = pts[ends] - f
        h = rel @ nrm
        lateral = np.linalg.norm(rel - np.outer(h, nrm), axis=1)
        inside = lateral < CAP_RADIUS
        if not inside.any():
            k = int(np.argmin(lateral))
            return 1.0 + lateral[k], h[k], lateral[k], pts
        k = int(np.flatnonzero(inside)[np.argmin(h[inside])])
        return abs(h[k] + PRESS / 2), h[k], lateral[k], pts

    def clearance(pts):
        # The pad's own neighbourhood is where it presses; the rest of the thumb keeps clear.
        keep = np.ones(len(pts), bool)
        keep[ends[np.linalg.norm(pts[ends] - f, axis=1) < CAP_RADIUS * 2]] = False
        least = 1.0
        for p in pts[keep]:
            found = obstacles.find(Vector(p))
            if found[0] is not None:
                least = min(least, found[2])
        return least

    def change(pose):
        return sum(abs(a - b) for a, b in zip(pose, start)) * 0.00002

    def total(c, pose, clear):
        return c[0] + change(pose) + max(0.0, SKIN_CLEAR - clear) * 5

    scored = []
    for mz in range(-60, 61, 10):
        for mx in range(-70, 51, 10):
            for my in range(-70, 51, 10):
                for curl in range(-20, 91, 15):
                    pose = (mz, mx, my, curl)
                    scored.append((contact(pose)[0] + change(pose), pose))
    scored.sort(key=lambda s: s[0])
    best = None
    for _, pose in scored[:150]:
        c = contact(pose)
        clear = clearance(c[3])
        score = total(c, pose, clear)
        if best is None or score < best[0]:
            best = (score, pose, c, clear)
    for step in (4, 2, 1):
        centre = best[1]
        for dz in (-step, 0, step):
            for dx in (-step, 0, step):
                for dy in (-step, 0, step):
                    for dc in (-2 * step, 0, 2 * step):
                        pose = (centre[0] + dz, centre[1] + dx, centre[2] + dy, centre[3] + dc)
                        c = contact(pose)
                        if c[0] > best[2][0] + 0.002:
                            continue
                        clear = clearance(c[3])
                        score = total(c, pose, clear)
                        if score < best[0]:
                            best = (score, pose, c, clear)
    _, pose, c, clear = best
    return pose, c[1], c[2], clear


def export_recorded(recorded_path, out, posed_mesh, place, rim_roll, report):
    """Re-exports each button's recorded pose (a thumbs.json checked by thumb_check.py --pick)
    without searching again, and measures every vertex of the new mesh against the recorded mesh
    of the same name beside that thumbs.json: the same pose within 0.01 mm."""
    recorded = json.load(open(recorded_path))
    folder = os.path.dirname(os.path.abspath(recorded_path))
    for name, entry in recorded["buttons"].items():
        sign = 1 if entry["side"] == "R" else -1
        slid = Matrix.Rotation(math.radians(entry["slideDeg"]), 4, "Z") @ rim_roll(math.radians(entry["rollDeg"])) @ place
        pose = (*entry["metacarpalDeg"], entry["curlDeg"])
        mesh = posed_mesh(pose, slid)
        obj = bpy.data.objects.new(f"Thumb_{name}", mesh)
        bpy.context.collection.objects.link(obj)
        if sign < 0:
            obj.data.transform(Matrix.Scale(-1, 4, (1, 0, 0)))
            obj.data.flip_normals()
        file_name = f"hand_{entry['side']}_{name}.glb"
        export_studs(obj, os.path.join(out, file_name))
        new = read_glb_studs(os.path.join(out, file_name))
        old = read_glb_studs(os.path.join(folder, file_name))
        tree = kd([tuple(p) for p in new])
        far = max(tree.find(Vector(p))[2] for p in old)
        back = max(kd([tuple(p) for p in old]).find(Vector(p))[2] for p in new)
        assert max(far, back) < 0.00001, (name, far, back)
        entry = dict(entry)
        entry["file"] = file_name
        entry["centre"] = studs(bounds_centre(obj))
        entry["matchesRecordedMm"] = round(max(far, back) * 1000, 4)
        report.setdefault("buttons", {})[name] = entry
        print(name, "re-exported:", file_name, "vertices", len(obj.data.vertices), "off the recorded mesh", entry["matchesRecordedMm"], "mm")
        bpy.data.objects.remove(obj)
    json.dump(report, open(os.path.join(out, "thumbs.json"), "w"), indent=1, default=lambda o: o.item())


def main(args):
    inputs = json.load(open(args[0]))
    out = args[1]
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    grip = json.load(open(inputs["grip"]))
    config = json.load(open(inputs["startupConfig"]))
    to_wheel = wheel_frame(config)
    parts = wheel_parts(inputs["cabin"], inputs["seat"], to_wheel)

    bpy.ops.import_scene.gltf(filepath=inputs["hand"])
    arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    hand = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    bones = arm.data.bones
    for finger in FINGERS:
        for part, angle in zip(("Proximal", "Intermediate", "Distal"), grip["fingerAngles"][finger]):
            pose_about_world_z(arm, f"{finger}_{part}_R", math.radians(angle))
    skin = ThumbSkin(hand, bones)
    spoke = grip["fingerAngles"]["Thumb"]
    start = (*spoke["metacarpal_deg"], spoke["curl_deg"])
    wrist_rest = bones["Wrist_R"].head_local.copy()
    place = grip_place(grip["R"], wrist_rest)
    to_rest = place.inverted()

    def posed_mesh(pose, place=place):
        # The deformed hand as a mesh of its own, keeping its UVs and smooth normals (the glove's
        # detail map needs the UVs), moved into the wheel's frame.
        mz, mx, my, curl = pose
        pose_world(arm, THUMB[0], metacarpal(mz, mx, my))
        pose_about_world_z(arm, THUMB[1], math.radians(curl * 0.4))
        pose_about_world_z(arm, THUMB[2], math.radians(curl * 0.6))
        bpy.context.view_layer.update()
        evaluated = hand.evaluated_get(bpy.context.evaluated_depsgraph_get())
        copy = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=bpy.context.evaluated_depsgraph_get())
        copy.transform(place @ hand.matrix_world)
        return copy

    # The rebuild against the exported grip, before anything is trusted.
    rebuilt = posed_mesh(start)
    exported = read_glb_studs(os.path.join(inputs["gripDir"], "hand_R.glb"))
    tree = kd([v.co[:] for v in rebuilt.vertices])
    near = np.array([tree.find(Vector(p))[2] for p in exported])
    report = {"rebuild": {"medianMm": round(float(np.median(near)) * 1000, 3), "maxMm": round(float(near.max()) * 1000, 3)}}
    print("grip rebuilt against hand_R.glb:", report["rebuild"])
    assert near.max() < 0.002, report

    # The rim tube's centre and tangent where the right hand grips (its mesh, at the grip's angle).
    rim_points = parts["SteeringWheel_Rim"][0]
    angle = math.radians(grip["gripAngleDeg"])
    polar = np.arctan2(rim_points[:, 1], rim_points[:, 0])
    near_grip = rim_points[np.abs(polar - angle) < math.radians(3)]
    tube = Vector(near_grip.mean(0))
    tangent = Vector((-math.sin(angle), math.cos(angle), 0))

    def rim_roll(turn):
        return Matrix.Translation(tube) @ Matrix.Rotation(turn, 4, tangent) @ Matrix.Translation(-tube)

    if "--export-from" in args:
        export_recorded(args[args.index("--export-from") + 1], out, posed_mesh, place, rim_roll, report)
        return

    results = {}
    for button in inputs["buttons"]:
        sign = 1 if button["side"] == "R" else -1
        flip = np.array([sign, 1.0, 1.0])
        others = [surface(points * flip, faces) for name, (points, faces) in parts.items() if name != button["part"]]
        mine = parts[button["part"]][0] * flip
        # The face the thumb meets: the button's points nearest the driver (wheel +z).
        top = mine[:, 2].max()
        face = mine[mine[:, 2] > top - 0.001].mean(0)
        normal = Vector((0, 0, 1))
        wheel_points = [Vector(p) for p in np.concatenate(others)]
        # The hand may slide round the rim (about the wheel's axis) and roll over it (about the rim
        # tube's tangent through its centre at the grip), keeping the rim in its fingers.
        mirror = Vector((sign, 1, 1))

        def make_entry(slide, roll, slid, pose, height, off_centre, clearance, reached):
            turn = slid.to_3x3()
            return {
                "side": button["side"],
                "part": button["part"],
                "slideDeg": slide,
                "rollDeg": roll,
                "padHeightMm": round(height * 1000, 2),
                "padOffCentreMm": round(off_centre * 1000, 2),
                "thumbClearanceMm": round(clearance * 1000, 2),
                "metacarpalDeg": pose[:3],
                "curlDeg": pose[3],
                "faceWheel": [round(c * sign if i == 0 else c, 5) for i, c in enumerate(face)],
                # The slid grip's wrist frame in the wheel's frame (studs; as hands.json's grip).
                "wrist": [round(c * STUDS_PER_METRE, 4) for c in (slid @ wrist_rest) * mirror],
                "forearm": [round(c, 4) for c in (turn @ Vector((0, -1, 0))).normalized() * mirror],
                "back": [round(c, 4) for c in (turn @ Vector((1, 0, 0))).normalized() * mirror],
                "reached": bool(reached),
            }

        def export(entry, slid, pose, file_name):
            mesh = posed_mesh(pose, slid)
            obj = bpy.data.objects.new(f"Thumb_{button['name']}", mesh)
            bpy.context.collection.objects.link(obj)
            if sign < 0:
                obj.data.transform(Matrix.Scale(-1, 4, (1, 0, 0)))
                obj.data.flip_normals()
            export_studs(obj, os.path.join(out, file_name))
            entry["file"] = file_name
            entry["centre"] = studs(bounds_centre(obj))
            bpy.data.objects.remove(obj)

        # The hand may slide round the rim (about the wheel's axis) and roll over it (about the rim
        # tube's tangent through its centre at the grip), keeping the rim in its fingers. Every
        # pose that reaches is exported as a candidate (tools/anim/thumb_check.py --pick keeps the
        # first, in the order given, that passes on the exported mesh); otherwise the closest
        # miss is reported.
        best, candidates = None, []
        for slide in button.get("slidesDeg", [0]):
            for roll in button.get("rollsDeg", [0]):
                slid = Matrix.Rotation(math.radians(slide), 4, "Z") @ rim_roll(math.radians(roll)) @ place
                to_rest_slid = slid.inverted()
                obstacles = kd([to_rest_slid @ p for p in wheel_points])
                pose, height, off_centre, clearance = solve(skin, obstacles, to_rest_slid @ Vector(face), to_rest_slid.to_3x3() @ normal, start)
                reached = -PRESS - 0.001 <= height <= REACH_GAP and off_centre < CAP_RADIUS and clearance >= SKIN_CLEAR
                print(button["name"], "slide", slide, "roll", roll, "pad height", round(height * 1000, 2), "off centre", round(off_centre * 1000, 2), "clearance", round(clearance * 1000, 2))
                entry = make_entry(slide, roll, slid, pose, height, off_centre, clearance, reached)
                if reached:
                    export(entry, slid, pose, f"hand_{button['side']}_{button['name']}_s{slide}_r{roll}.glb")
                    candidates.append(entry)
                if best is None or abs(height + PRESS / 2) < abs(best["padHeightMm"] / 1000 + PRESS / 2):
                    best = entry
        entry = dict(candidates[0]) if candidates else best
        entry["candidates"] = candidates
        results[button["name"]] = entry
        print(button["name"], {k: v for k, v in entry.items() if k != "candidates"}, len(candidates), "candidates")
    report["buttons"] = results
    # numpy scalars to plain numbers.
    json.dump(report, open(os.path.join(out, "thumbs.json"), "w"), indent=1, default=lambda o: o.item())


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1 :])
