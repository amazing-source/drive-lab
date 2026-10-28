"""
Builds the roadside furniture of Drive Lab's test road and exports it for Roblox in one file.

    blender -b --factory-startup -P tools/blender/roadside_props.py -- <out dir>

The road is an Italian two-lane extra-urban road, so the props follow Italian rules and
products (research 2026-10-28):
- Delineator (delineatore normale di margine, DPR 495/1992 art. 173): a white post 1.05 m out of
  the ground, its section a trapezoid inside 10 x 12 cm (the 10 cm side along the road), a black
  band 25 cm deep at the top, the top cut sloping down towards the road. On a two-way road it
  carries a red reflector on the face drivers on its side see, a white one on the face the
  oncoming drivers see, each over 60 cm^2 (4.5 x 14 cm here). Placed at most 50 m apart, at the
  outer edge of the shoulder, at least 50 cm from the carriageway.
- Guardrail (two-wave W-beam, class N2, EN 1317; the Marcegaglia N2 sheet: posts 2 m apart,
  750 mm high, 205-285 mm overall depth): a W-beam 310 mm deep and 83 mm thick, its top at
  0.75 m, on 80 x 120 mm spacers on C-posts 120 x 80 mm. Two 12 m sections, A and B, whose six
  posts each stand at a seeded jitter of up to 0.25 m off the 2 m grid: a strictly regular row
  strobes at speed (at 300 km/h the car moves 1.4 m a frame at 60 FPS, 0.7 of the 2 m period,
  so a regular row seems to crawl backwards). One reflector pair per section in the valley.
  GuardrailStart and GuardrailEnd are the buried terminals: 4 m of beam sloping into the ground
  and flaring 0.5 m away from the road.
- SignGantry (portale): two 0.42 m tube columns on concrete footings 8.5 m either side of the
  centreline, a four-chord box truss 0.9 x 1.4 m across 17 m, its underside at 5.58 m, above
  the 5.10 m minimum for signs over the carriageway (DPR 495/1992 art. 81). Two 4.4 x 2.4 m sign
  backs, one over each lane facing that lane's traffic, their bottoms at 5.2 m; the sign faces
  are Parts with Decals added in the place.

Frames, in the Roblox frame after import (the street lamp's convention, see street_lamp.py):
+X along the road (the direction of travel in the right-hand lane), +Y up, +Z to the road's
right. Built in Blender as (x, y, z) = (-along, right, up) in metres, scaled to studs at export.
- Delineator, guardrail pieces: origin on the ground at the post's centre (delineator) or at
  the beam's road face (guardrail), for a prop on the road's right; the game turns a left-side
  prop half a turn, so its red reflector still faces the traffic on its own side (-X, towards
  drivers approaching in the direction of travel).
- Guardrail sections start at their origin and run to +X 12 m; GuardrailStart ends at its origin
  (it occupies -4..0 m), GuardrailEnd starts there (0..4 m).
- SignGantry: origin on the road's centreline at the road surface.

Output, in <out dir>: roadside_props.glb, one object per Roblox part, named <Model>_<Part>
(Delineator_Body, GuardrailA_Steel, SignGantry_Concrete...); roadside_props.json (each model's
bounds in studs, triangle counts, the guardrail post positions); check_props.png (all models
side by side) and check_closeup.png (a delineator in front of a guardrail). Every part is a
closed, outward-facing shell, checked by its signed volume before it is kept; the export is
re-imported to check names, triangle counts, UVs and face direction survived.
"""

import json
import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from street_lamp import bar, bounds, is_closed, polygon, render, signed_volume, triangles  # noqa: E402

STUDS_PER_METRE = 1.5 / 0.28
ROUND_8, ROUND_16 = polygon(8, math.pi / 8), polygon(16)
SECTION_LENGTH = 12.0
TERMINAL_LENGTH = 4.0


def road(a, o, u):
    """A point in the road frame (along, right, up) as a Blender vector."""
    return Vector((-a, o, u))


def outward(verts, faces):
    """Faces flipped if needed so the shell's signed volume is positive (normals out)."""
    if signed_volume(verts, faces) < 0:
        faces = [tuple(reversed(f)) for f in faces]
    return verts, faces


def prism(section, bottom, top):
    """A vertical prism over a polygon of (along, right) points; bottom and top give the height
    at each point, so either end can slope. Flat-shaded."""
    ring = [road(a, o, 0) for a, o in section]
    verts = [Vector((p.x, p.y, bottom(a, o))) for p, (a, o) in zip(ring, section)]
    verts += [Vector((p.x, p.y, top(a, o))) for p, (a, o) in zip(ring, section)]
    n = len(section)
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    faces.append(tuple(reversed(range(n))))
    faces.append(tuple(n + i for i in range(n)))
    return (*outward(verts, faces), None)


def box(centre, half, axes=None):
    """A box at a road-frame centre with half sizes along (along, right, up) or given axes."""
    c = road(*centre)
    ex, ey, ez = axes or (road(1, 0, 0), road(0, 1, 0), road(0, 0, 1))
    verts = [c + ex * (sx * half[0]) + ey * (sy * half[1]) + ez * (sz * half[2]) for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
    faces = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
    return (*outward(verts, faces), None)


def tube(p0, p1, radius, sides=ROUND_8):
    """A round bar between two road-frame points, smooth with sharp cap rims."""
    a, b = road(*p0), road(*p1)
    t = (b - a).normalized()
    hint = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
    verts, faces, sharp = bar(a, b, hint, radius, radius, sides)
    verts2, faces2 = outward(verts, faces)
    return verts2, faces2, sharp


def sweep(profile, stations):
    """A closed (right, up) profile swept through stations (along, right offset, up offset),
    capped at both ends. Smooth along the profile, sharp at the caps."""
    m = len(profile)
    verts = [road(a, o + po, u + pu) for a, o, u in stations for po, pu in profile]
    faces = [(i * m + j, i * m + (j + 1) % m, (i + 1) * m + (j + 1) % m, (i + 1) * m + j) for i in range(len(stations) - 1) for j in range(m)]
    faces.append(tuple(reversed(range(m))))
    faces.append(tuple((len(stations) - 1) * m + j for j in range(m)))
    verts, faces = outward(verts, faces)
    last = (len(stations) - 1) * m
    sharp = [(j, (j + 1) % m) for j in range(m)] + [(last + j, last + (j + 1) % m) for j in range(m)]
    return verts, faces, sharp


def delineator():
    # Section: 12 cm across, 10 cm along on the field side, 5 cm on the road side, so the two
    # reflector faces look slightly towards the carriageway. Corners chamfered 4 mm.
    corners = [(-0.025, -0.06), (0.025, -0.06), (0.05, 0.06), (-0.05, 0.06)]
    section = []
    for i, (a, o) in enumerate(corners):
        prev, nxt = corners[i - 1], corners[(i + 1) % 4]
        for other in (prev, nxt):
            d = Vector((other[0] - a, other[1] - o))
            d.normalize()
            section.append((a + d.x * 0.004, o + d.y * 0.004))

    def top(a, o):
        return 1.015 + o / 0.12 * 0.07

    def band(a, o):
        return top(a, o) - 0.25

    parts = [
        ("Delineator_Body", *prism(section, lambda a, o: -0.2, band)),
        ("Delineator_Band", *prism(section, band, top)),
    ]
    # The reflectors, 2 mm proud of each sloping face, centred in the band.
    for name, sign in (("Delineator_ReflectorRed", -1), ("Delineator_ReflectorWhite", 1)):
        p, q = Vector((sign * 0.025, -0.06)), Vector((sign * 0.05, 0.06))
        along_face = (q - p).normalized()
        normal = Vector((along_face.y, -along_face.x))
        if normal.x * sign < 0:
            normal = -normal
        mid = (p + q) / 2 + normal * 0.0011
        centre = (mid.x, mid.y, band(0, 0) + 0.125)
        axes = (road(normal.x, normal.y, 0), road(along_face.x, along_face.y, 0), road(0, 0, 1))
        parts.append((name, *box(centre, (0.0011, 0.0225, 0.07), axes)))
    return parts


W_HALF_HEIGHT = 0.155
W_DEPTH = 0.083
W_THICK = 0.003
BEAM_CENTRE = 0.75 - W_HALF_HEIGHT


def w_profile(samples=32):
    """The W-beam's closed section, (right, up) about its centre: crests towards the road
    (right = 0), the valley and the rolled edges back on the post side (right = 0.083)."""
    face = []
    for k in range(samples + 1):
        u = -W_HALF_HEIGHT + 2 * W_HALF_HEIGHT * k / samples
        o = W_DEPTH / 2 + W_DEPTH / 2 * math.cos(2 * math.pi * u / (W_HALF_HEIGHT * 2) * 2)
        slope = -W_DEPTH / 2 * math.sin(2 * math.pi * u / (W_HALF_HEIGHT * 2) * 2) * 2 * math.pi / W_HALF_HEIGHT
        length = math.hypot(1, slope)
        face.append((o, u, -1 / length, slope / length))
    road_side = [(o + n_o * W_THICK / 2, u + n_u * W_THICK / 2) for o, u, n_o, n_u in face]
    post_side = [(o - n_o * W_THICK / 2, u - n_u * W_THICK / 2) for o, u, n_o, n_u in reversed(face)]
    return road_side + post_side


def c_post(a, top, shift):
    """A C-post 120 mm along the road, 80 mm deep, 5 mm steel, its web facing the road."""
    o0, t = 0.203 + shift, 0.005
    section = [
        (a - 0.06, o0), (a + 0.06, o0), (a + 0.06, o0 + 0.08), (a + 0.06 - t, o0 + 0.08),
        (a + 0.06 - t, o0 + t), (a - 0.06 + t, o0 + t), (a - 0.06 + t, o0 + 0.08), (a - 0.06, o0 + 0.08),
    ]
    return prism(section, lambda *_: -0.45, lambda *_: top)


def post_hardware(a, centre_u, shift=0.0):
    """Spacer block, post and the two button-head bolts in the beam's valley; shift moves it all
    away from the road with a flaring beam."""
    parts = [
        ("Steel", *box((a, 0.143 + shift, centre_u), (0.04, 0.06, 0.11))),
        ("Steel", *c_post(a, centre_u + 0.125, shift)),
    ]
    for da in (-0.025, 0.025):
        head = (a + da, W_DEPTH - 0.001 + shift, centre_u)
        parts.append(("Steel", *tube(head, (a + da, W_DEPTH - 0.016 + shift, centre_u), 0.011, polygon(6))))
    return parts


def guardrail(name, seed):
    rng = random.Random(seed)
    posts = [round(1.0 + 2.0 * k + rng.uniform(-0.25, 0.25), 3) for k in range(6)]
    parts = [("Steel", *sweep(w_profile(), [(0, 0, BEAM_CENTRE), (SECTION_LENGTH, 0, BEAM_CENTRE)]))]
    for a in posts:
        parts += post_hardware(a, BEAM_CENTRE)
    # A reflector pair standing in the valley at the third post, proud of the crests.
    at = posts[2]
    for part, side in (("ReflectorRed", -1), ("ReflectorWhite", 1)):
        parts.append((part, *box((at + side * 0.0021, 0.02, BEAM_CENTRE + 0.1), (0.002, 0.045, 0.045))))
    return [(f"{name}_{part}", verts, faces, sharp) for part, verts, faces, sharp in parts], posts


def terminal(name, direction):
    """The beam's buried end: direction -1 runs back from the origin (a start), +1 ahead (an end)."""
    stations = []
    steps = 8
    for k in range(steps + 1):
        f = k / steps
        ease = f * f * (3 - 2 * f)
        stations.append((direction * TERMINAL_LENGTH * f, 0.5 * ease, BEAM_CENTRE - 0.75 * ease))
    if direction < 0:
        stations.reverse()
    parts = [("Steel", *sweep(w_profile(), stations))]
    post = 0.25
    ease = post * post * (3 - 2 * post)
    parts += post_hardware(direction * TERMINAL_LENGTH * post, BEAM_CENTRE - 0.75 * ease, 0.5 * ease)
    return [(f"{name}_{part}", verts, faces, sharp) for part, verts, faces, sharp in parts]


GANTRY_LEG = 8.5
TRUSS = {"halfDepth": 0.45, "bottom": 5.65, "top": 7.05, "chord": 0.07, "lace": 0.03, "bays": 16}
SIGN = {"width": 4.4, "height": 2.4, "bottom": 5.2, "offset": 2.5, "standoff": 0.17, "thick": 0.08}


def gantry():
    steel, concrete, back = [], [], []
    d, lo, hi = TRUSS["halfDepth"], TRUSS["bottom"], TRUSS["top"]
    for side in (-1, 1):
        o = side * GANTRY_LEG
        concrete.append(box((0, o, -0.1), (0.55, 0.55, 0.5)))
        steel.append(box((0, o, 0.42), (0.36, 0.36, 0.02)))
        steel.append(tube((0, o, 0.44), (0, o, hi + 0.2), 0.21, ROUND_16))
        steel.append(box((0, o, hi + 0.21), (0.25, 0.25, 0.012)))
    nodes = [-GANTRY_LEG + 2 * GANTRY_LEG * k / TRUSS["bays"] for k in range(TRUSS["bays"] + 1)]
    for a in (-d, d):
        for u in (lo, hi):
            steel.append(tube((a, -GANTRY_LEG, u), (a, GANTRY_LEG, u), TRUSS["chord"]))
    lace = TRUSS["lace"]
    for k, o in enumerate(nodes):
        if 0 < k < len(nodes) - 1:
            for a in (-d, d):
                steel.append(tube((a, o, lo), (a, o, hi), lace))
            for u in (lo, hi):
                steel.append(tube((-d, o, u), (d, o, u), lace))
        if k < len(nodes) - 1:
            o2 = nodes[k + 1]
            flip = k % 2 == 0
            for a in (-d, d):
                steel.append(tube((a, o, lo if flip else hi), (a, o2, hi if flip else lo), lace))
            for u in (lo, hi):
                steel.append(tube((-d if flip else d, o, u), (d if flip else -d, o2, u), lace))
    # Sign backs, one over each lane facing its traffic: the right lane's (+right) faces -along,
    # towards drivers coming in the direction of travel; the left lane's faces +along.
    for facing, o in ((-1, SIGN["offset"]), (1, -SIGN["offset"])):
        a = facing * (d + SIGN["standoff"] + SIGN["thick"] / 2)
        centre_u = SIGN["bottom"] + SIGN["height"] / 2
        back.append(box((a, o, centre_u), (SIGN["thick"] / 2, SIGN["width"] / 2, SIGN["height"] / 2)))
        for bracket_o in (o - SIGN["width"] / 3, o + SIGN["width"] / 3):
            for u in (lo, hi):
                steel.append(box((facing * (d + SIGN["standoff"] / 2), bracket_o, u), (SIGN["standoff"] / 2 + 0.02, 0.04, 0.04)))
    return (
        [("SignGantry_Steel", *p) for p in steel]
        + [("SignGantry_Concrete", *p) for p in concrete]
        + [("SignGantry_SignBack", *p) for p in back]
    )


def all_parts():
    parts = delineator()
    posts = {}
    for name, seed in (("GuardrailA", 11), ("GuardrailB", 29)):
        section, posts[name] = guardrail(name, seed)
        parts += section
    parts += terminal("GuardrailStart", -1)
    parts += terminal("GuardrailEnd", 1)
    parts += gantry()
    return parts, posts


def build(parts):
    """One object per part (each keeps its shading), joined by name, smart-UV-projected."""
    groups = {}
    for i, (name, verts, faces, sharp) in enumerate(parts):
        volume = signed_volume(verts, faces)
        if volume <= 0 or not is_closed(faces):
            raise RuntimeError(f"part {i} ({name}) is not a closed outward shell: volume {volume:.3g}")
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata([tuple(v) for v in verts], [], faces)
        if sharp is None:
            mesh.shade_flat()
        else:
            mesh.shade_smooth()
            index = {tuple(sorted(e.vertices)): e.index for e in mesh.edges}
            flags = [False] * len(mesh.edges)
            for a, b in sharp:
                flags[index[tuple(sorted((a, b)))]] = True
            attribute = mesh.attributes.get("sharp_edge") or mesh.attributes.new("sharp_edge", "BOOLEAN", "EDGE")
            attribute.data.foreach_set("value", flags)
        ob = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(ob)
        groups.setdefault(name, []).append(ob)
    joined = {}
    for name, obs in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for ob in obs:
            ob.select_set(True)
        bpy.context.view_layer.objects.active = obs[0]
        bpy.ops.object.join()
        ob = bpy.context.view_layer.objects.active
        bpy.data.orphans_purge(do_recursive=True)
        ob.name = ob.data.name = name
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.003)
        bpy.ops.object.mode_set(mode="OBJECT")
        joined[name] = ob
    return joined


def to_roblox(v):
    return [round(c * STUDS_PER_METRE, 4) + 0.0 for c in (-v.x, v.z, v.y)]


def report(objects, posts):
    models = {}
    for name, ob in objects.items():
        models.setdefault(name.split("_")[0], []).append(ob)
    out = {"units": f"studs, 1 m = {STUDS_PER_METRE:.4f} studs", "frame": "Roblox axes after import: +X along the road, +Y up, +Z to the road's right", "models": {}}
    for model, obs in models.items():
        lo, hi = bounds([v.co for ob in obs for v in ob.data.vertices])
        rlo, rhi = to_roblox(lo), to_roblox(hi)
        out["models"][model] = {
            "min": [min(a, b) for a, b in zip(rlo, rhi)],
            "max": [max(a, b) for a, b in zip(rlo, rhi)],
            "triangles": {ob.name.split("_", 1)[1]: triangles(ob) for ob in obs},
        }
    out["guardrailPostsMetres"] = posts
    out["triangles"] = {name: triangles(ob) for name, ob in objects.items()}
    out["triangles"]["total"] = sum(out["triangles"].values())
    return out


def setup_renders(objects):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_percentage = 100
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "MATERIAL"
    shading.show_cavity = True
    shading.show_object_outline = True
    scene.world = bpy.data.worlds.new("World")
    scene.world.color = (0.78, 0.82, 0.86)
    colours = {
        "Body": (0.92, 0.92, 0.9, 1), "Band": (0.03, 0.03, 0.03, 1), "ReflectorRed": (0.8, 0.05, 0.03, 1),
        "ReflectorWhite": (0.95, 0.95, 0.95, 1), "Steel": (0.55, 0.57, 0.58, 1), "Concrete": (0.6, 0.6, 0.57, 1),
        "SignBack": (0.0, 0.25, 0.5, 1),
    }
    for name, ob in objects.items():
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = colours[name.split("_", 1)[1]]
        ob.data.materials.append(mat)
    return scene


def lay_out(objects, offsets):
    for name, ob in objects.items():
        ob.location = offsets.get(name.split("_")[0], Vector())


def check_export(path, expected):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    found = {ob.name: ob for ob in bpy.context.scene.objects if ob.type == "MESH"}
    names = sorted(n for n in expected["triangles"] if n != "total")
    if sorted(found) != names:
        raise RuntimeError(f"export holds {sorted(found)}, expected {names}")
    for name, ob in found.items():
        ob.data.calc_loop_triangles()
        if len(ob.data.loop_triangles) != expected["triangles"][name]:
            raise RuntimeError(f"{name}: {len(ob.data.loop_triangles)} triangles after export, {expected['triangles'][name]} before")
        if not ob.data.uv_layers:
            raise RuntimeError(f"{name} lost its UVs")
        verts = [ob.matrix_world @ v.co for v in ob.data.vertices]
        faces = [tuple(t.vertices) for t in ob.data.loop_triangles]
        if signed_volume(verts, faces) <= 0:
            raise RuntimeError(f"{name}'s faces point inward after export")
    print("export check: names, triangle counts, UVs and outward faces survive the round trip")


def main(args):
    out = args[0]
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    parts, posts = all_parts()
    objects = build(parts)
    for name, ob in objects.items():
        if triangles(ob) >= 20000:
            raise RuntimeError(f"{name} has {triangles(ob)} triangles; Roblox caps a mesh at 20,000")
    results = report(objects, posts)
    print(json.dumps(results, indent=1))

    scene = setup_renders(objects)
    # Line-up: guardrails behind, the gantry over them, a delineator in front.
    lay_out(objects, {
        "GuardrailStart": Vector((0, 0, 0)), "GuardrailA": Vector((0, 0, 0)), "GuardrailB": Vector((-12, 0, 0)),
        "GuardrailEnd": Vector((-24, 0, 0)), "Delineator": Vector((-6, -1.2, 0)), "SignGantry": Vector((-10, -9.0, 0)),
    })
    render(scene, os.path.join(out, "check_props.png"), (1600, 900), Vector((-8, -34, 6)), Vector((-12, -4, 2.8)), lens=35)
    render(scene, os.path.join(out, "check_closeup.png"), (1200, 900), Vector((-3.4, -3.2, 1.3)), Vector((-6, 0.0, 0.6)), lens=40)
    lay_out(objects, {})

    for ob in objects.values():
        ob.data.materials.clear()
        ob.data.transform(Matrix.Scale(STUDS_PER_METRE, 4))
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects.values():
        ob.select_set(True)
    glb = os.path.join(out, "roadside_props.glb")
    bpy.ops.export_scene.gltf(filepath=glb, use_selection=True, export_materials="NONE", export_yup=True)
    with open(os.path.join(out, "roadside_props.json"), "w") as f:
        json.dump(results, f, indent=1)
    check_export(glb, results)


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1 :])
