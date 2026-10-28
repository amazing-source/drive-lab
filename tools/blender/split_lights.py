"""
Splits a car export's light mesh into the lamps the game drives, and its window glass into the
windows and the lamps' glass, run headless by Blender:

    blender -b --factory-startup -P tools/blender/split_lights.py -- <car.glb> <emissive.png> <colour.png> <out dir>

<car.glb> is the hero car export (tools/blender/hero_car_export.py); the two images are the light
mesh's emissive mask and colour map as Studio has them (maps_v3/light_emissive_2k.png and
light_colour_2k.png for the SVJ).

1. The light mesh is cut in four corners by face centre (front or rear of the middle, left or
   right of the centre line), then each corner into its lamps. A lamp is a connected group of
   faces (vertices welded by position, so UV seams do not cut one) named by what it is, read off
   the SVJ's model in Studio and from the lens meshes over it (issue #41):
   - front: the V-shaped light guide (daytime running light and indicator), the round projector
     with its bezel (the faces textured from the atlas's lens disc), the seven small LED modules
     beside it, and the side marker under the amber lens at the bumper's corner;
   - rear: the three Y segments (tail and brake: the emissive groups), the cells above them under
     the amber lens (indicator), the clear inboard chevron (reversing light) and the part of it
     under the red lens (rear fog), the half of the high stop strip across the engine cover, the
     plate lamp below, and the side marker.
   What is left of a corner is its housing, which keeps the corner's old name.
2. The window glass (outer and inner meshes) also forms every lamp's cover. A connected group of
   it that overlaps a lamp's box is lamp glass; the rest stays window.
3. Exports lights.glb (Light_<Corner> housings, Light_<Corner>_<Lamp>, LampGlass, and the two
   window meshes without the covers; no materials, tangents kept) and lights.json: each piece's
   triangle count and box in Roblox axes, the boxes of the pieces it was cut from, so Studio can
   place every piece where its faces were.

Every count is checked against what the SVJ gives: another source stops here rather than
mislabel a lamp.

Axes: the export is Roblox (x, y, z) = Blender (-x, z, y); Roblox's front is -z (Blender -y)
and its right is +x (Blender -x).
"""

import json
import os
import sys

import bmesh
import bpy
import numpy as np

CORNERS = (("FrontLeft", True, False), ("FrontRight", True, True), ("RearLeft", False, False), ("RearRight", False, True))
LIGHT = "Light_LightA_Material_1"
WINDOWS = ("Window_Window_Material_1", "WindowInside_Window_Material_1")
AMBER_LENSES = {True: "Window_ORANGE_GLASS_1", False: "WindowInside_ORANGE_GLASS_1"}
RED_LENS = "WindowInside_RED_GLASS_1"
# The atlas's lens disc (UV, v down as glTF): the projector's lens.
LENS_DISC = (0.0, 0.3, 0.69, 1.0)
# Studs a window group may sit outside a lamp's box and still be its cover.
COVER_MARGIN = 0.05
EXPECTED = {
    "Front": {"Drl": 118, "Projector": 300, "Modules": 518, "Marker": 18, "": 371},
    "Rear": {"Tail": 837, "Indicator": 250, "Reverse": 47, "Fog": 53, "Bar": 14, "Plate": 13, "Marker": 17, "": 701},
    "LampGlass": 1718,
}


def to_roblox(points: np.ndarray) -> np.ndarray:
    return np.stack([-points[:, 0], points[:, 2], points[:, 1]], axis=1)


def baked(name: str):
    obj = next(o for o in bpy.context.scene.objects if o.type == "MESH" and o.name.startswith(name))
    obj.data.transform(obj.matrix_world)
    obj.matrix_world.identity()
    return obj


def faces_of(obj) -> dict:
    """Per face: Roblox centre, corner positions, area, UV centre (wrapped, v down) and welded group."""
    mesh = obj.data
    points = to_roblox(np.array([v.co[:] for v in mesh.vertices]))
    weld = {}
    parent = list(range(len(points)))

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for index, point in enumerate(np.round(points, 4)):
        key = tuple(point)
        if key in weld:
            parent[root(index)] = root(weld[key])
        else:
            weld[key] = index
    uv = mesh.uv_layers.active.data if mesh.uv_layers else None
    centres, areas, uvs, groups, corners = [], [], [], [], []
    for polygon in mesh.polygons:
        ids = list(polygon.vertices)
        tri = points[ids]
        centres.append(tri.mean(axis=0))
        corners.append(tri)
        areas.append(polygon.area)
        if uv is not None:
            loop_uv = np.array([uv[i].uv[:] for i in polygon.loop_indices]).mean(axis=0)
            # Blender's v runs up; the maps are read with glTF's, down.
            u, v = loop_uv[0], 1 - loop_uv[1]
            uvs.append((u - np.floor(u), v - np.floor(v)))
        else:
            uvs.append((0.0, 0.0))
        for i in ids[1:]:
            parent[root(i)] = root(ids[0])
    for polygon in mesh.polygons:
        groups.append(root(polygon.vertices[0]))
    return {
        "centre": np.array(centres),
        "area": np.array(areas),
        "uv": np.array(uvs),
        "group": np.array(groups),
        "tris": corners,
    }


def image(path: str) -> np.ndarray:
    picture = bpy.data.images.load(path)
    picture.colorspace_settings.name = "Non-Color"
    width, height = picture.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    picture.pixels.foreach_get(pixels)
    # Rows bottom-up in Blender; flip so row 0 is the image's top, as glTF's v reads it.
    return pixels.reshape(height, width, 4)[::-1]


def sample(picture: np.ndarray, uv: np.ndarray) -> np.ndarray:
    height, width = picture.shape[:2]
    x = np.clip((uv[:, 0] * width).astype(int), 0, width - 1)
    y = np.clip((uv[:, 1] * height).astype(int), 0, height - 1)
    return picture[y, x]


def inside(points: np.ndarray, triangles: np.ndarray) -> np.ndarray:
    """Whether each 2D point lies in any of the 2D triangles."""
    hit = np.zeros(len(points), dtype=bool)
    for a, b, c in triangles:
        d1 = (points[:, 0] - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (points[:, 1] - b[1])
        d2 = (points[:, 0] - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (points[:, 1] - c[1])
        d3 = (points[:, 0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (points[:, 1] - a[1])
        negative = (d1 < 0) | (d2 < 0) | (d3 < 0)
        positive = (d1 > 0) | (d2 > 0) | (d3 > 0)
        hit |= ~(negative & positive)
    return hit


def front_lamp(mean, area, tris, albedo, disc_share) -> str:
    side = abs(mean[0])
    if mean[2] > -2:
        return ""  # a small lamp under the sill, unlit in the game: housing
    if side > 3.3:
        return "Marker"
    if disc_share > 0.1:
        return "Projector"
    if 20 <= tris <= 60 and 1.95 < side < 2.45:
        return "Modules"
    if albedo > 0.3 and area > 0.5:
        return "Drl"
    return ""


def rear_lamp(mean, area, emission, albedo, amber_share) -> str:
    side = abs(mean[0])
    if side > 3.4:
        return "Marker"
    if mean[1] < 1.6:
        return "Plate"
    if side < 1.0 and mean[1] > 2.75:
        return "Bar"
    if emission > 0.25:
        return "Tail"
    if amber_share > 0.5 and albedo > 0.6:
        return "Indicator"
    if side < 2.0 and albedo > 0.3 and area > 0.1:
        return "Inner"
    return ""


def classify(
    faces: dict, front: bool, emissive: np.ndarray, colour: np.ndarray, amber: np.ndarray, red: np.ndarray
) -> np.ndarray:
    emission = sample(emissive, faces["uv"])[:, 0]
    albedo = sample(colour, faces["uv"])[:, :3].mean(axis=1)
    u, v = faces["uv"][:, 0], faces["uv"][:, 1]
    disc = (u >= LENS_DISC[0]) & (u < LENS_DISC[1]) & (v >= LENS_DISC[2]) & (v < LENS_DISC[3])
    under_amber = inside(faces["centre"][:, :2], amber[:, :, :2])
    lamps = np.empty(len(faces["area"]), dtype=object)
    for group in np.unique(faces["group"]):
        members = faces["group"] == group
        weights = faces["area"][members] / max(faces["area"][members].sum(), 1e-12)
        mean = (faces["centre"][members] * weights[:, None]).sum(axis=0)
        area = faces["area"][members].sum()
        share = lambda flags: float((flags[members] * weights).sum())  # noqa: E731
        if front:
            lamp = front_lamp(mean, area, int(members.sum()), share(albedo), share(disc))
        else:
            lamp = rear_lamp(mean, area, share(emission), share(albedo), share(under_amber))
        lamps[members] = lamp
    if not front:
        # The inboard chevron is clear but for a red lamp inside it, under the red lens.
        under_red = inside(faces["centre"][:, :2], red[:, :, :2])
        inner = lamps == "Inner"
        lamps[inner & under_red] = "Fog"
        lamps[inner & ~under_red] = "Reverse"
    return lamps


def build(name: str, source, keep: np.ndarray):
    mesh = bmesh.new()
    mesh.from_mesh(source.data)
    mesh.faces.ensure_lookup_table()
    bmesh.ops.delete(mesh, geom=[f for f in mesh.faces if not keep[f.index]], context="FACES")
    data = bpy.data.meshes.new(name)
    mesh.to_mesh(data)
    mesh.free()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return obj


def box(obj) -> dict:
    points = to_roblox(np.array([v.co[:] for v in obj.data.vertices]))
    return {"min": np.round(points.min(axis=0), 5).tolist(), "max": np.round(points.max(axis=0), 5).tolist()}


def triangles(obj) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def main(car: str, emissive_path: str, colour_path: str, out: str):
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=car)
    emissive, colour = image(emissive_path), image(colour_path)
    light = baked(LIGHT)
    windows = [baked(name) for name in WINDOWS]
    amber = {front: baked(name) for front, name in AMBER_LENSES.items()}
    red = np.array(faces_of(baked(RED_LENS))["tris"])
    report = {"sources": {LIGHT: box(light), **{w.name: box(w) for w in windows}}, "pieces": {}}
    # The pieces take the sources' names, so the sources step aside.
    for source in (light, *windows):
        source.name = f"Source_{source.name}"
        source.data.name = source.name
    faces = faces_of(light)
    pieces = []
    lamp_boxes = []
    for corner, front, right in CORNERS:
        in_corner = ((faces["centre"][:, 2] < 0) == front) & ((faces["centre"][:, 0] > 0) == right)
        lens = np.array(faces_of(amber[front])["tris"])
        lens = lens[(lens.mean(axis=1)[:, 0] > 0) == right]
        red_lens = red[(red.mean(axis=1)[:, 0] > 0) == right]
        sub = {key: value[in_corner] for key, value in faces.items() if key != "tris"}
        lamps = np.full(len(faces["area"]), None, dtype=object)
        lamps[in_corner] = classify(sub, front, emissive, colour, lens, red_lens)
        for lamp, count in EXPECTED["Front" if front else "Rear"].items():
            name = f"Light_{corner}" + (f"_{lamp}" if lamp else "")
            obj = build(name, light, lamps == lamp)
            assert triangles(obj) == count, f"{name}: {triangles(obj)} triangles, expected {count}"
            pieces.append(obj)
            if lamp:
                lamp_boxes.append(box(obj))
        corner_points = np.concatenate([faces["tris"][i] for i in np.where(in_corner)[0]])
        report["sources"][f"Light_{corner}"] = {
            "min": np.round(corner_points.min(axis=0), 5).tolist(),
            "max": np.round(corner_points.max(axis=0), 5).tolist(),
        }
    glass_pieces = []
    for window in windows:
        glass = faces_of(window)
        cover = np.zeros(len(glass["area"]), dtype=bool)
        for group in np.unique(glass["group"]):
            members = glass["group"] == group
            points = np.concatenate([glass["tris"][i] for i in np.where(members)[0]])
            low, high = points.min(axis=0), points.max(axis=0)
            cover[members] = any(
                np.all(high >= np.array(lamp["min"]) - COVER_MARGIN)
                and np.all(low <= np.array(lamp["max"]) + COVER_MARGIN)
                for lamp in lamp_boxes
            )
        glass_pieces.append(build(f"{window.name}_cover", window, cover))
        pieces.append(build(window.name.removeprefix("Source_"), window, ~cover))
    bpy.ops.object.select_all(action="DESELECT")
    for piece in glass_pieces:
        piece.select_set(True)
    bpy.context.view_layer.objects.active = glass_pieces[0]
    bpy.ops.object.join()
    lamp_glass = glass_pieces[0]
    lamp_glass.name = "LampGlass"
    lamp_glass.data.name = "LampGlass"
    assert triangles(lamp_glass) == EXPECTED["LampGlass"], f"LampGlass: {triangles(lamp_glass)} triangles"
    pieces.append(lamp_glass)
    for obj in pieces:
        report["pieces"][obj.name] = {"triangles": triangles(obj), **box(obj)}
    bpy.ops.object.select_all(action="DESELECT")
    for obj in pieces:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = pieces[0]
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(out, "lights.glb"),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_normals=True,
        export_tangents=True,
        export_materials="NONE",
    )
    with open(os.path.join(out, "lights.json"), "w") as handle:
        json.dump(report, handle, indent=1)
    print(json.dumps({name: piece["triangles"] for name, piece in report["pieces"].items()}, indent=1))


if __name__ == "__main__":
    main(*sys.argv[sys.argv.index("--") + 1 :][:4])
