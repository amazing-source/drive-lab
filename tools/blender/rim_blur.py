"""
Builds the pieces of Drive Lab's rim blur from the car's own wheels, run headless by Blender:

    blender -b --factory-startup -P tools/blender/rim_blur.py -- <car.glb> <maps dir> <out dir>

<car.glb> is the hero car export (tools/blender/hero_car_export.py; studs, Wheel_FL/FR/RL/RR one
mesh each, axle along Blender x); <maps dir> holds the wheel's maps as Studio has them
(wheel_color.png, wheel_metalness.png, wheel_roughness.png).

1. Splits each wheel into the rim face (spokes, hub face, bolts, lip: what turns visibly) and the
   rest (tyre, barrel, brake disc, hub cylinder: rotationally symmetric, so the same sharp or
   blurred). A connected island of the mesh is rim face when it lies wholly in front of the
   wheel's FACE_DEPTH plane and inside FACE_RADIUS_SHARE of the tyre's radius.
2. Renders each rim face front-on, orthographic down the axle, unlit (emission), in two passes on
   black: its colour map, and (metalness, roughness, coverage). Black is no surface, so every
   pass comes out multiplied by coverage.
3. Averages each render over every rotation about the axle: the mean around each circle centred
   on the axle. That is the limit of accumulating rotated renders (for an unlit orthographic view
   down the axle, turning the rim and turning the image are the same), without the angular
   banding a finite set of rotations leaves at the rim's edge. Saves the radial profiles; the
   textures are made from them by tools/assets/rim_blur_maps.py.
4. Builds a disc per wheel that follows the front envelope of its rim face, a little in front of
   it, UV-mapped front-on into the textures' atlas (front axle left half, rear right half).
5. Exports rim_blur.glb (Tyre_*, Face_*, Disc_* per corner, no textures) and manifest.json: each
   piece's centre and size in Roblox space and its offset from its wheel's centre, which the game
   uses to place the pieces on the wheel.

Axes: Roblox (x, y, z) = Blender (-x, z, y), as hero_car_export.py writes them.
"""

import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

CORNERS = ("FL", "FR", "RL", "RR")
# Studs outward from a wheel's centre plane. Measured on the SVJ export: the front hub cylinder
# ends 0.15 out and the front spokes start 0.19 out; the rear ones 0.25 and 0.29.
FACE_DEPTH = {"F": 0.17, "R": 0.27}
# An island reaching past this share of the tyre's radius is tyre (its sidewall), not rim.
FACE_RADIUS_SHARE = 0.9
RENDER_PIXELS = 2048
RENDER_SAMPLES = 32
# Studs per radial sample of the profiles, at import scale (about 0.07 mm).
PROFILE_STEP = 0.00025
# The textures cover the rim face's radius times this, so the disc's edge is not the atlas's.
TEXTURE_MARGIN = 1.03
DISC_SEGMENTS = 64
DISC_RINGS = 32
# Studs the disc stands in front of the spokes' front envelope, so the two never interleave.
DISC_STANDOFF = 0.004
# Envelope bins per disc ring. Each ring takes the maximum over a ring spacing either side, so
# the straight segment between two rings stays in front of every peak between them.
ENVELOPE_BINS_PER_RING = 4
# The angular coverage is sampled here, as a share of the rim face's radius, for the spoke count.
SPOKE_RADIUS_SHARE = 0.55


def to_roblox(v) -> list:
    return [round(-v[0], 5), round(v[2], 5), round(v[1], 5)]


def bounds(obj):
    points = np.array([v.co[:] for v in obj.data.vertices])
    return points.min(axis=0), points.max(axis=0)


def islands(mesh: bmesh.types.BMesh) -> list:
    """Each connected group of vertices, as lists of face indices."""
    label = [-1] * len(mesh.verts)
    count = 0
    for start in mesh.verts:
        if label[start.index] >= 0:
            continue
        label[start.index] = count
        stack = [start]
        while stack:
            vert = stack.pop()
            for edge in vert.link_edges:
                other = edge.other_vert(vert)
                if label[other.index] < 0:
                    label[other.index] = count
                    stack.append(other)
        count += 1
    groups = [[] for _ in range(count)]
    for face in mesh.faces:
        groups[label[face.verts[0].index]].append(face.index)
    return groups


def mesh_object(name: str, mesh: bmesh.types.BMesh):
    data = bpy.data.meshes.new(name)
    mesh.to_mesh(data)
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return obj


def split(wheel, corner: str):
    """(tyre object, face object, report): the wheel's faces divided by island."""
    low, high = bounds(wheel)
    centre = (low + high) / 2
    radius = (high[2] - low[2]) / 2
    outward = 1.0 if centre[0] > 0 else -1.0
    depth = FACE_DEPTH[corner[0]]
    mesh = bmesh.new()
    mesh.from_mesh(wheel.data)
    mesh.verts.ensure_lookup_table()
    mesh.faces.ensure_lookup_table()
    face_islands = set()
    groups = islands(mesh)
    for index, group in enumerate(groups):
        points = np.array([v.co[:] for f in group for v in mesh.faces[f].verts]) - centre
        out = points[:, 0] * outward
        reach = np.hypot(points[:, 1], points[:, 2])
        if out.min() > depth and reach.max() < FACE_RADIUS_SHARE * radius:
            face_islands.add(index)
    is_face = [False] * len(mesh.faces)
    for index in face_islands:
        for f in groups[index]:
            is_face[f] = True
    pieces = {}
    for name, keep in (("Tyre", False), ("Face", True)):
        piece = mesh.copy()
        doomed = [f for index, f in enumerate(piece.faces) if is_face[index] != keep]
        bmesh.ops.delete(piece, geom=doomed, context="FACES")
        pieces[name] = mesh_object(f"{name}_{corner}", piece)
        piece.free()
    mesh.free()
    for obj in pieces.values():
        obj.data.materials.clear()
        for material in wheel.data.materials:
            obj.data.materials.append(material)
        # The source model's second colour set has alpha 0 on every vertex. Roblox ignores it
        # while a part is opaque and multiplies it in once the part is partly transparent, so a
        # fading face vanished outright (seen in Studio, 2026-10-28).
        for attribute in list(obj.data.color_attributes):
            obj.data.color_attributes.remove(attribute)
    report = {
        "islands": len(groups),
        "faceIslands": len(face_islands),
        "faceDepth": depth,
        "faceRadiusLimit": round(FACE_RADIUS_SHARE * radius, 4),
    }
    return pieces["Tyre"], pieces["Face"], report


def triangles(obj) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def envelope(face, centre, outward: float, extent: float, bins: int) -> np.ndarray:
    """The rim face's furthest reach outward in each radial bin, studs from the centre plane,
    from points spread over every triangle (vertices alone leave big faces' middles out)."""
    face.data.calc_loop_triangles()
    corners = np.array([v.co[:] for v in face.data.vertices])
    tris = np.array([t.vertices[:] for t in face.data.loop_triangles])
    weights = [(a / 6, b / 6, 1 - (a + b) / 6) for a in range(7) for b in range(7 - a)]
    reach = np.full(bins, -np.inf)
    for wa, wb, wc in weights:
        points = corners[tris[:, 0]] * wa + corners[tris[:, 1]] * wb + corners[tris[:, 2]] * wc - centre
        rho = np.hypot(points[:, 1], points[:, 2])
        index = np.minimum((rho / extent * bins).astype(int), bins - 1)
        np.maximum.at(reach, index, points[:, 0] * outward)
    known = np.isfinite(reach)
    middles = (np.arange(bins) + 0.5) / bins * extent
    reach = np.interp(middles, middles[known], reach[known])
    span = ENVELOPE_BINS_PER_RING
    return np.array([reach[max(0, i - span) : i + span + 1].max() for i in range(bins)])


def disc(corner: str, centre, outward: float, extent: float, texture_radius: float, reach: np.ndarray):
    """A dish over the rim face: rings of DISC_SEGMENTS vertices at the envelope's depth plus the
    stand-off, UVs front-on into this axle's half of the atlas."""
    mesh = bmesh.new()
    uv = mesh.loops.layers.uv.new("UVMap")
    bins = len(reach)
    middles = (np.arange(bins) + 0.5) / bins * extent
    half_centre = 0.25 if corner[0] == "F" else 0.75
    rings = []
    for ring in range(DISC_RINGS + 1):
        rho = extent * ring / DISC_RINGS
        depth = float(np.interp(rho, middles, reach)) + DISC_STANDOFF
        count = 1 if ring == 0 else DISC_SEGMENTS
        verts = []
        for step in range(count):
            angle = 2 * math.pi * step / DISC_SEGMENTS
            across, up = rho * math.cos(angle), rho * math.sin(angle)
            vert = mesh.verts.new((centre[0] + outward * depth, centre[1] + across, centre[2] + up))
            verts.append((vert, half_centre + 0.25 * across / texture_radius, 0.5 + 0.5 * up / texture_radius))
        rings.append(verts)

    def add(corners):
        face = mesh.faces.new([c[0] for c in corners])
        for loop, c in zip(face.loops, corners):
            loop[uv].uv = (c[1], c[2])

    for step in range(DISC_SEGMENTS):
        following = (step + 1) % DISC_SEGMENTS
        add([rings[0][0], rings[1][step], rings[1][following]])
        for ring in range(1, DISC_RINGS):
            inner, outer = rings[ring], rings[ring + 1]
            add([inner[step], outer[step], outer[following], inner[following]])
    mesh.normal_update()
    mesh.faces.ensure_lookup_table()
    # Its front must face outward: Roblox draws one side of a mesh.
    if mesh.faces[0].normal.x * outward < 0:
        for face in mesh.faces:
            face.normal_flip()
    obj = mesh_object(f"Disc_{corner}", mesh)
    mesh.free()
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def emission_material(name: str, build) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    nodes.clear()
    emission = nodes.new("ShaderNodeEmission")
    output = nodes.new("ShaderNodeOutputMaterial")
    links.new(emission.outputs["Emission"], output.inputs["Surface"])
    build(nodes, links, emission.inputs["Color"])
    return material


def texture(nodes, image: bpy.types.Image):
    node = nodes.new("ShaderNodeTexImage")
    node.image = image
    node.interpolation = "Cubic"
    return node


def pass_materials(maps: str) -> dict:
    def load(name: str, colour_space: str) -> bpy.types.Image:
        image = bpy.data.images.load(os.path.join(maps, name))
        image.colorspace_settings.name = colour_space
        image.alpha_mode = "CHANNEL_PACKED"
        return image

    colour = load("wheel_color.png", "sRGB")
    metalness = load("wheel_metalness.png", "Non-Color")
    roughness = load("wheel_roughness.png", "Non-Color")

    def albedo(nodes, links, socket):
        links.new(texture(nodes, colour).outputs["Color"], socket)

    def data(nodes, links, socket):
        combine = nodes.new("ShaderNodeCombineColor")
        for image, channel in ((metalness, "Red"), (roughness, "Green")):
            separate = nodes.new("ShaderNodeSeparateColor")
            links.new(texture(nodes, image).outputs["Color"], separate.inputs["Color"])
            links.new(separate.outputs["Red"], combine.inputs[channel])
        combine.inputs["Blue"].default_value = 1.0
        links.new(combine.outputs["Color"], socket)

    return {"albedo": emission_material("RimAlbedo", albedo), "data": emission_material("RimData", data)}


def setup_render(scratch: str):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = RENDER_SAMPLES
    scene.cycles.use_adaptive_sampling = False
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 0
    scene.render.film_transparent = False
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "OPEN_EXR"
    scene.render.image_settings.color_depth = "32"
    scene.render.image_settings.color_mode = "RGB"
    world = bpy.data.worlds.new("Black")
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0, 0, 0, 1)
    background.inputs["Strength"].default_value = 0
    scene.world = world
    camera_data = bpy.data.cameras.new("Front")
    camera_data.type = "ORTHO"
    camera_data.clip_start = 0.01
    camera_data.clip_end = 100
    camera = bpy.data.objects.new("Front", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    return scene, camera, scratch


def render(scene, path: str, pixels: int) -> np.ndarray:
    """One render to EXR (scene-linear, no view transform), read back as rows top to bottom."""
    scene.render.resolution_x = pixels
    scene.render.resolution_y = pixels
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    image = bpy.data.images.load(path)
    image.colorspace_settings.name = "Non-Color"
    buffer = np.empty(pixels * pixels * 4, dtype=np.float32)
    image.pixels.foreach_get(buffer)
    bpy.data.images.remove(image)
    os.remove(path)
    return buffer.reshape(pixels, pixels, 4)[::-1, :, :3].copy()


def only_visible(target) -> None:
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            obj.hide_render = obj is not target


def aim(camera, centre, outward: float, radius: float) -> None:
    direction = Vector((-outward, 0, 0))
    camera.location = Vector(centre) - direction * 20
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    camera.data.ortho_scale = 2 * radius


def calibrate(scene, camera, scratch: str) -> float:
    """Renders a plane emitting 0.5 and returns what comes back: the readback must be linear."""
    bpy.ops.mesh.primitive_plane_add(size=1, location=(50, 0, 0), rotation=(0, math.pi / 2, 0))
    plane = bpy.context.active_object
    material = emission_material("Calibration", lambda n, l, socket: setattr(socket, "default_value", (0.5, 0.5, 0.5, 1)))
    plane.data.materials.append(material)
    only_visible(plane)
    aim(camera, (50, 0, 0), 1.0, 0.25)
    value = float(render(scene, os.path.join(scratch, "calibration.exr"), 64)[32, 32, 0])
    bpy.data.objects.remove(plane)
    return value


def radial_profile(image: np.ndarray, radius: float, step: float) -> np.ndarray:
    """The mean of `image` around every circle centred on the axle, at radii 0, step, 2 step ...
    up to `radius` (studs); the image spans [-radius, radius] square."""
    pixels = image.shape[0]
    per_stud = pixels / (2 * radius)
    centre = pixels / 2 - 0.5
    out = []
    for rho in np.arange(0, radius, step):
        r = rho * per_stud
        count = max(16, int(math.ceil(4 * math.pi * r)))
        angle = (np.arange(count) + 0.5) / count * 2 * math.pi
        x = np.clip(centre + r * np.cos(angle), 0, pixels - 1.001)
        y = np.clip(centre + r * np.sin(angle), 0, pixels - 1.001)
        x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
        fx, fy = (x - x0)[:, None], (y - y0)[:, None]
        sample = (
            image[y0, x0] * (1 - fx) * (1 - fy)
            + image[y0, x0 + 1] * fx * (1 - fy)
            + image[y0 + 1, x0] * (1 - fx) * fy
            + image[y0 + 1, x0 + 1] * fx * fy
        )
        out.append(sample.mean(axis=0))
    return np.array(out)


def spoke_period(coverage: np.ndarray, radius: float, at: float) -> dict:
    """The rim's angular repeat, degrees, from the coverage around one circle."""
    pixels = coverage.shape[0]
    r = at / (2 * radius) * pixels
    count = 3600
    angle = np.arange(count) / count * 2 * math.pi
    x = (pixels / 2 - 0.5 + r * np.cos(angle)).round().astype(int)
    y = (pixels / 2 - 0.5 + r * np.sin(angle)).round().astype(int)
    ring = coverage[y, x] - coverage[y, x].mean()
    spectrum = np.abs(np.fft.rfft(ring))[:40]
    strongest = [int(k) for k in np.argsort(spectrum[1:])[::-1][:3] + 1]
    return {
        "radius": round(at, 4),
        "strongestRepeats": strongest,
        "strength": [round(float(spectrum[k] / spectrum[strongest[0]]), 3) for k in strongest],
        "spokeShare": round(float((coverage[y, x] > 0.5).mean()), 3),
    }


def vertex_coloured(glb: str) -> list:
    """Names of the meshes in a .glb whose primitives carry a COLOR_n attribute."""
    with open(glb, "rb") as handle:
        handle.read(12)
        length = int.from_bytes(handle.read(4), "little")
        handle.read(4)
        document = json.loads(handle.read(length))
    return [
        mesh["name"]
        for mesh in document["meshes"]
        if any(name.startswith("COLOR_") for primitive in mesh["primitives"] for name in primitive["attributes"])
    ]


def main(car: str, maps: str, out: str):
    os.makedirs(out, exist_ok=True)
    scratch = os.path.join(out, "scratch")
    os.makedirs(scratch, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=car)
    for obj in list(bpy.context.scene.objects):
        if obj.type == "MESH" and not obj.name.startswith("Wheel_"):
            bpy.data.objects.remove(obj)
    scene, camera, scratch = setup_render(scratch)
    linear = calibrate(scene, camera, scratch)
    assert abs(linear - 0.5) < 1e-3, f"the readback is not linear: an emission of 0.5 came back as {linear}"
    materials = pass_materials(maps)

    manifest = {"calibration": round(linear, 5), "corners": {}, "profiles": {}}
    profiles = {}
    exported = []
    for corner in CORNERS:
        wheel = bpy.context.scene.objects[f"Wheel_{corner}"]
        wheel.data.transform(wheel.matrix_world)
        wheel.matrix_world.identity()
        low, high = bounds(wheel)
        centre = (low + high) / 2
        outward = 1.0 if centre[0] > 0 else -1.0
        tyre, face, split_report = split(wheel, corner)
        corners = np.array([v.co[:] for v in face.data.vertices]) - centre
        extent = float(np.hypot(corners[:, 1], corners[:, 2]).max())
        texture_radius = extent * TEXTURE_MARGIN
        reach = envelope(face, centre, outward, extent, DISC_RINGS * ENVELOPE_BINS_PER_RING)
        plate = disc(corner, centre, outward, extent, texture_radius, reach)
        record = {
            "wheelCentre": to_roblox(centre),
            "wheelSize": [round(high[0] - low[0], 5), round(high[2] - low[2], 5), round(high[1] - low[1], 5)],
            "wheelTriangles": triangles(wheel),
            "faceRadius": round(extent, 5),
            "textureRadius": round(texture_radius, 5),
            "envelope": [round(float(v), 4) for v in reach[:: max(1, len(reach) // 16)]],
            **split_report,
            "pieces": {},
        }
        for piece in (tyre, face, plate):
            piece_low, piece_high = bounds(piece)
            piece_centre = (piece_low + piece_high) / 2
            record["pieces"][piece.name.split("_")[0]] = {
                "name": piece.name,
                "triangles": triangles(piece),
                "centre": to_roblox(piece_centre),
                "size": [
                    round(piece_high[0] - piece_low[0], 5),
                    round(piece_high[2] - piece_low[2], 5),
                    round(piece_high[1] - piece_low[1], 5),
                ],
                "offset": to_roblox(piece_centre - centre),
            }
            exported.append(piece)

        aim(camera, centre, outward, texture_radius)
        only_visible(face)
        face.data.materials.clear()
        face.data.materials.append(materials["albedo"])
        albedo = render(scene, os.path.join(scratch, f"albedo_{corner}.exr"), RENDER_PIXELS)
        face.data.materials.clear()
        face.data.materials.append(materials["data"])
        data = render(scene, os.path.join(scratch, f"data_{corner}.exr"), RENDER_PIXELS)
        face.data.materials.clear()
        for material in wheel.data.materials:
            face.data.materials.append(material)
        # Premultiplied albedo (3), premultiplied metalness, premultiplied roughness, coverage.
        stack = np.concatenate([albedo, data], axis=2)
        profile = radial_profile(stack, texture_radius, PROFILE_STEP)
        profiles[corner] = profile
        record["spokes"] = spoke_period(data[:, :, 2], texture_radius, SPOKE_RADIUS_SHARE * extent)
        sharp = stack[:: RENDER_PIXELS // 512, :: RENDER_PIXELS // 512]
        np.save(os.path.join(out, f"front_{corner}.npy"), sharp.astype(np.float32))
        manifest["corners"][corner] = record
        print(corner, json.dumps({k: v for k, v in record.items() if k != "pieces"}))

    for left, right in (("FL", "FR"), ("RL", "RR")):
        size = min(len(profiles[left]), len(profiles[right]))
        difference = np.abs(profiles[left][:size] - profiles[right][:size]).max(axis=0)
        manifest["profiles"][f"{left}-{right}"] = [round(float(v), 5) for v in difference]
    np.savez(
        os.path.join(out, "profiles.npz"),
        step=PROFILE_STEP,
        **{corner: profile.astype(np.float32) for corner, profile in profiles.items()},
        **{f"radius_{c}": manifest["corners"][c]["textureRadius"] for c in CORNERS},
        **{f"extent_{c}": manifest["corners"][c]["faceRadius"] for c in CORNERS},
    )
    os.rmdir(scratch)

    bpy.ops.object.select_all(action="DESELECT")
    for piece in exported:
        piece.hide_render = False
        piece.select_set(True)
    bpy.context.view_layer.objects.active = exported[0]
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(out, "rim_blur.glb"),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_normals=True,
        # The tyre and face keep the wheel's normal map, which needs tangents in Roblox.
        export_tangents=True,
        export_materials="NONE",
    )
    coloured = vertex_coloured(os.path.join(out, "rim_blur.glb"))
    assert not coloured, f"meshes still carry vertex colours: {coloured}"
    with open(os.path.join(out, "manifest.json"), "w") as handle:
        json.dump(manifest, handle, indent=1)
    print("profiles left-right max difference", manifest["profiles"])


if __name__ == "__main__":
    main(*sys.argv[sys.argv.index("--") + 1 :][:3])
