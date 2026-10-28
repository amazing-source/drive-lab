"""
The car as the entry animations see it, outside Blender: the export's meshes (car.glb, studs at
real scale, Roblox axes once read) moved into the driver's SEAT frame of a rigged car, and the
frames the clips are authored in. Every number that places the car comes from a Studio
measurement (SEAT_WELD.json), never from a hand-copied offset.

Frames, all studs of the 1.5x world unless named otherwise:
  import  CarImport at scale 1 in the place (the export's own frame plus the model's offset)
  seat    the DriverSeat part of a rigged car (CarRig.addSeat): +X right, +Y up, -Z forward
  root    the seated HumanoidRootPart: seat * SeatWeld.C0 * SeatWeld.C1^-1
  mark    the standing HumanoidRootPart at the door mark (Config.MARK), facing the seat

  import numpy as np; from car_scene import load_glb, Scene
"""
import json
import math
import struct

import numpy as np

STUDS_PER_METRE = 1.5 / 0.28  # Units.metresToStuds(1): the world is 1.5x Roblox's


def load_glb(path):
    """{node name: (vertices (n,3), triangles (m,3))} in the export's frame read as Roblox axes:
    the glTF importer turns +Z forward into Roblox's -Z forward, so (x, y, z) -> (-x, y, -z)."""
    data = open(path, "rb").read()
    length0 = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20 : 20 + length0])
    binary = data[20 + length0 + 8 :]
    views, accessors = gltf["bufferViews"], gltf["accessors"]

    def read(index):
        acc = accessors[index]
        view = views[acc["bufferView"]]
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        kind = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[acc["componentType"]]
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
        out = np.frombuffer(binary, dtype=kind, count=acc["count"] * width, offset=start)
        return out.reshape(acc["count"], width) if width > 1 else out

    meshes = {}
    for node in gltf["nodes"]:
        if "mesh" not in node:
            continue
        offset = np.array(node.get("translation", (0, 0, 0)), dtype=float)
        verts, tris, base = [], [], 0
        for prim in gltf["meshes"][node["mesh"]]["primitives"]:
            v = read(prim["attributes"]["POSITION"]).astype(float) + offset
            f = read(prim["indices"]).astype(np.int64).reshape(-1, 3)
            verts.append(v)
            tris.append(f + base)
            base += len(v)
        v = np.concatenate(verts) * np.array([-1.0, 1.0, -1.0])
        # Mirroring two axes keeps the winding.
        meshes[node["name"]] = (v, np.concatenate(tris))
    return meshes


def bounds_centre(vertices):
    return (vertices.min(axis=0) + vertices.max(axis=0)) / 2


def cframe(values):
    """A Roblox CFrame's 12 components (x, y, z, R00..R22) as a 4x4 matrix."""
    m = np.identity(4)
    m[:3, 3] = values[0:3]
    m[:3, :3] = np.array(values[3:12]).reshape(3, 3)
    return m


def apply(m, points):
    return points @ m[:3, :3].T + m[:3, 3]


def yaw_frame(position, look):
    """CFrame.lookAt(position, position + look) with look flattened, as Roblox builds it."""
    look = np.array([look[0], 0.0, look[2]])
    back = -look / np.linalg.norm(look)
    up = np.array([0.0, 1.0, 0.0])
    right = np.cross(up, back)
    m = np.identity(4)
    m[:3, 0], m[:3, 1], m[:3, 2], m[:3, 3] = right, up, back, position
    return m


class Scene:
    """The rigged car around the driver's seat, from a SEAT_WELD.json measurement."""

    def __init__(self, seat_json, glb_path, mark=None):
        self.data = json.load(open(seat_json, encoding="utf-8"))
        d = self.data
        self.scale = d["driverScale"]
        weld = d["seatWeld"]
        self.root = cframe(weld["C0"]) @ np.linalg.inv(cframe(weld["C1"]))
        self.meshes = load_glb(glb_path)
        self._import_to_seat()
        # Ground under the car, seat frame: the wheels' contact patches.
        bottoms = d["car"]["wheelBottomsInSeat"]
        self.ground_y = float(np.mean([p[1] for p in bottoms.values()]))
        self.hull = d["car"]["hullInSeat"]
        self.set_mark(mark or (-0.92, 0.0))

    def _import_to_seat(self):
        """Body and wheels map differently (the body is raised at rig time): each is
        seat = k * (import centre) + offset, solved from measured samples, checked on the others."""
        d = self.data
        k = None
        groups = {"body": [], "wheel": []}
        for name, s in d["mapSamples"].items():
            if name not in self.meshes:
                continue
            centre = bounds_centre(self.meshes[name][0])
            k = float(np.mean(np.array(s["riggedSize"]) / np.array(s["importSize"])))
            groups["wheel" if name.startswith("Wheel_") else "body"].append((name, centre, np.array(s["inSeat"])))
        self.k = k
        self.offsets, self.map_error = {}, {}
        for group, rows in groups.items():
            offsets = [seat - k * centre for _, centre, seat in rows]
            mean = np.mean(offsets, axis=0)
            self.offsets[group] = mean
            self.map_error[group] = max(float(np.linalg.norm(o - mean)) for o in offsets)

    def car_in_seat(self, name):
        v, f = self.meshes[name]
        group = "wheel" if name.startswith("Wheel_") or name.startswith("Caliper_") else "body"
        return v * self.k + self.offsets[group], f

    def set_mark(self, mark):
        """mark = (right, forward) metres from the seat, as Config.MARK. Root standing on the
        ground there, facing the seat across the ground (DoorMark.frame + standingFrame)."""
        self.mark_metres = mark
        right, forward = mark
        point = np.array([right * STUDS_PER_METRE, 0.0, -forward * STUDS_PER_METRE])
        toward = -point
        frame = yaw_frame(point, toward)
        frame[1, 3] = self.ground_y + 3.0 * self.scale
        self.mark = frame

    def mark_to_root(self):
        """The standing root expressed in the seated root's frame."""
        return np.linalg.inv(self.root) @ self.mark


def sample_triangles(vertices, triangles, spacing):
    """Points over every triangle no further apart than `spacing`, plus each triangle's corners."""
    a, b, c = (vertices[triangles[:, i]] for i in range(3))
    longest = np.maximum.reduce(
        [np.linalg.norm(b - a, axis=1), np.linalg.norm(c - b, axis=1), np.linalg.norm(a - c, axis=1)]
    )
    steps = np.clip(np.ceil(longest / spacing).astype(int), 1, 60)
    out = [vertices]
    for n in np.unique(steps):
        if n <= 1:
            continue
        pick = steps == n
        i, j = np.meshgrid(np.arange(n + 1), np.arange(n + 1), indexing="ij")
        keep = (i + j) <= n
        u = (i[keep] / n)[None, :, None]
        w = (j[keep] / n)[None, :, None]
        pa, pb, pc = a[pick][:, None, :], b[pick][:, None, :], c[pick][:, None, :]
        out.append((pa + u * (pb - pa) + w * (pc - pa)).reshape(-1, 3))
    return np.concatenate(out)


def rotation_about(axis, angle):
    axis = np.asarray(axis, dtype=float)
    axis = axis / np.linalg.norm(axis)
    x, y, z = axis
    c, s = math.cos(angle), math.sin(angle)
    t = 1 - c
    m = np.identity(4)
    m[:3, :3] = [
        [t * x * x + c, t * x * y - s * z, t * x * z + s * y],
        [t * x * y + s * z, t * y * y + c, t * y * z - s * x],
        [t * x * z - s * y, t * y * z + s * x, t * z * z + c],
    ]
    return m
