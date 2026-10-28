"""
Builds a Victorian twin-lantern street lamp from nothing and exports it for Roblox, with the
numbers the game needs to light it.

    blender -b --factory-startup -P tools/blender/street_lamp.py -- <out dir> [--photo <reference.jpg>]

Reference: the owner's photo of a black cast-iron twin-lantern lamp post on a park drive (960 x
1200 px). Every dimension here was read off gridded zooms of it at PHOTO_SCALE = 268.7 px per
metre, the scale that makes the post 3.9 m from the underside of its base to the lantern finials.
The photo is taken from far off with a long lens, so it is close to orthographic: the slim pole's
taper (11 cm at its foot, 6.5 cm under the crosshead) is the post's own, not perspective.

The post, bottom to top (heights from the ground, metres):
- base: a square with chamfered corners, 0.47 m across the flats, on a 0.54 m flange, with a
  cornice, a sloped wash and a smaller second tier, to 0.35 m;
- a round foot and ring, then a fluted cone 0.23 m across at 0.46 m, 0.16 m at 0.95 m;
- a bead, a neck, a collar nut and a ring, to 1.16 m;
- the slim pole, tapering from 0.11 to 0.065 m, with double-bead collars at 1.92 and 2.74 m and
  a bead and ring under the crosshead at 3.16-3.23 m;
- the crosshead, a 0.12 m block from 3.23 to 3.46 m, with a round finial to 3.57 m;
- each side, a C-scroll arm: it leaves the crosshead at 3.36 m, sweeps out and down to
  horizontal at 3.26 m and runs into the lantern's socket; its top end curls into a volute, and a
  small scroll below braces it from the crosshead;
- each lantern sits upright on its arm's end, centred 0.30 m off the axis. It is HEXAGONAL: the
  photo shows a face-on front pane and two side panes at half its width, which is how a hexagon
  looks square-on. Socket and concave bowl from 3.23 m, a tray, a tapered glass body from 3.42 to
  3.63 m (0.21 m across the corners at its foot, 0.28 m at its top), a flared eave 0.33 m across,
  a domed roof and a spike finial to 3.9 m. Lead cames make a diamond on each pane, tied to the
  posts at its sides; a candle sleeve and flame bulb stand inside.
Lantern centres are 0.60 m apart, as the photo measures; 0.92 m is the overall width across the
two lantern caps.

Fit: compare.png lays the model's silhouette over the photo at the photo's own scale. Pole,
collars, column, base, crosshead, arms and the left lantern sit within 1-2 px (under 1 cm); the
photo's right lantern is turned a few degrees on its arm, so it shows narrower than the model's,
which faces the road square like the left one.

Export: street_lamp.glb with three meshes: Iron, Glass (both lanterns' panes, a 3 mm closed shell
so it shows from inside and out) and Bulb (both candles, for the game to make glow). Built Z-up
in metres with the base centre at the origin and the arms along +-X, then scaled to studs at the
world scale (1 m = 1.5 / 0.28 = 5.3571 studs). Blender's glTF exporter turns Z-up into Y-up and
Roblox's importer turns the model half a turn about the vertical, so Roblox (x, y, z) = Blender
(-x, z, y): the lamp stands along Roblox +Y with its arms along Roblox +-X. No materials are
exported; the game sets each part's colour and material. UVs are a smart projection packed into
0..1. Round parts are smooth with sharp edges kept at their steps; faceted parts are flat. Every
part is a closed shell with outward normals, checked by its signed volume before it is kept, and
the .glb is re-imported to check names, triangle counts, UVs, size and face direction survived.

Output, in <out dir>: street_lamp.glb; street_lamp.json (height, base footprint, each bulb's
centre and each object's bounds in Roblox axes and studs, triangle counts); check renders
check_front.png, check_side.png, check_three_quarter.png, check_head.png; with --photo,
compare.png: the photo, the model's front view at the photo's scale, and the model's silhouette
in red over the photo, for the whole post (top row) and the head (bottom row).
"""

import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

STUDS_PER_METRE = 1.5 / 0.28
# Where the photo puts the post: pixels per metre, the post's axis (column) and the ground (row).
PHOTO_SCALE = 268.7
PHOTO_AXIS_X = 478.9
PHOTO_GROUND_Y = 1161


def polygon(n, phase=0.0):
    return [(math.cos(phase + 2 * math.pi * k / n), math.sin(phase + 2 * math.pi * k / n)) for k in range(n)]


def chamfered_square(b):
    """A square of half-width 1 with its corners cut from (b, 1) to (1, b), counter-clockwise."""
    return [(1, -b), (1, b), (b, 1), (-b, 1), (-1, b), (-1, -b), (-b, -1), (b, -1)]


def fluted(flutes, depth):
    return [
        ((1 - depth * (k % 2)) * math.cos(math.pi * k / flutes), (1 - depth * (k % 2)) * math.sin(math.pi * k / flutes))
        for k in range(2 * flutes)
    ]


ROUND_24, ROUND_16, ROUND_12 = polygon(24), polygon(16), polygon(12)
# A corner on +X: the arms meet the lanterns' corners and the road sees their flats, as in the photo.
HEX = polygon(6)
OCTAGON = polygon(8, math.pi / 8)
SQUARE = [(1, -1), (1, 1), (-1, 1), (-1, -1)]


def bead(z0, z1, r0, peak, r1, steps=4):
    """A half-round from (r0, z0) out to `peak` and back in to (r1, z1)."""
    points = []
    for k in range(steps + 1):
        f = k / steps
        base = r0 + (r1 - r0) * f
        points.append((base + (peak - base) * math.sin(math.pi * f), z0 + (z1 - z0) * (1 - math.cos(math.pi * f)) / 2))
    return points


# Profiles, (radius, height) in metres from the bottom of the part up its outside. A polygonal
# shape's radius is its corner radius, except the chamfered square's, which is across its flats.
BASE = [
    (0, 0), (0.268, 0), (0.268, 0.028), (0.258, 0.042),  # flange
    (0.236, 0.044), (0.231, 0.220),  # box
    (0.241, 0.226), (0.241, 0.238), (0.228, 0.246),  # cornice
    (0.202, 0.278), (0.193, 0.280), (0.193, 0.330), (0.166, 0.352),  # wash and second tier
    (0.135, 0.354), (0, 0.354),
]
COLUMN_FOOT = [(0, 0.340), (0.130, 0.340)] + bead(0.418, 0.466, 0.130, 0.137, 0.112) + [(0, 0.466)]
FLUTED_CONE = [(0, 0.460), (0.114, 0.460), (0.098, 0.705), (0.082, 0.955), (0, 0.955)]
COLUMN_NECK = (
    [(0, 0.948), (0.080, 0.948)]
    + bead(0.950, 0.998, 0.080, 0.089, 0.070)
    + [(0.069, 1.055), (0.078, 1.057), (0.082, 1.062), (0.082, 1.100), (0.073, 1.113), (0.067, 1.115),
       (0.067, 1.150), (0.060, 1.157), (0, 1.157)]
)
CROSSHEAD = [
    (0, 3.232), (0.059, 3.232), (0.059, 3.256), (0.0575, 3.260), (0.0575, 3.434),
    (0.053, 3.446), (0.044, 3.454), (0.030, 3.459), (0, 3.460),
]
POLE_FINIAL = (
    [(0, 3.455), (0.022, 3.455), (0.022, 3.465)]
    + bead(3.470, 3.517, 0.014, 0.022, 0.0093)
    + [(0.0093, 3.526), (0.012, 3.528), (0.012, 3.533), (0.0085, 3.536), (0.0095, 3.547), (0, 3.567)]
)


def pole_radius(z):
    """The slim pole's taper, read at its foot (1.157 m) and under the crosshead (3.167 m)."""
    return 0.056 + (0.0327 - 0.056) * (z - 1.157) / (3.167 - 1.157)


def collar(z0, z1, peak, waist):
    """Two beads with a waist between them, round the slim pole."""
    h = min(0.022, (z1 - z0) / 3)
    return bead(z0, z0 + h, pole_radius(z0), peak, waist) + bead(z1 - h, z1, waist, peak, pole_radius(z1))


POLE = (
    [(0, 1.150), (pole_radius(1.150), 1.150)]
    + collar(1.917, 2.021, 0.0525, 0.0495)
    + collar(2.739, 2.829, 0.0458, 0.0425)
    + bead(3.163, 3.193, pole_radius(3.163), 0.040, 0.0365)
    + [(0.0365, 3.200), (0.043, 3.203), (0.045, 3.207), (0.045, 3.230), (0.043, 3.234), (0.040, 3.240), (0, 3.240)]
)

# The lantern, in its own frame (axis at the origin, heights from the ground).
LANTERN_X = 80.4 / PHOTO_SCALE
BOWL = [
    (0, 3.286), (0.020, 3.286), (0.028, 3.294), (0.041, 3.309), (0.050, 3.323), (0.057, 3.338),
    (0.069, 3.353), (0.090, 3.368), (0.108, 3.378),  # concave bowl, necking into the socket
    (0.117, 3.379), (0.117, 3.388), (0.112, 3.392), (0.112, 3.420), (0, 3.420),  # tray
]
SOCKET = [(0, 3.226), (0.012, 3.226), (0.015, 3.231), (0.015, 3.288), (0, 3.288)]
CAP = [
    (0, 3.645), (0.137, 3.645), (0.137, 3.628), (0.151, 3.628), (0.151, 3.658),  # ceiling, top band
    (0.163, 3.658), (0.163, 3.666), (0.120, 3.694), (0.115, 3.696), (0.115, 3.714),  # eave, roof band
    (0.112, 3.722), (0.103, 3.732), (0.091, 3.743), (0.075, 3.756), (0.057, 3.768), (0.038, 3.779),
    (0.029, 3.785), (0, 3.788),  # dome
]
CAP_FINIAL = [
    (0, 3.784), (0.024, 3.784), (0.024, 3.799), (0.018, 3.806), (0.0075, 3.809), (0.0075, 3.827),
    (0.016, 3.829), (0.016, 3.835), (0.006, 3.838), (0.0075, 3.858), (0.0068, 3.872), (0, 3.900),
]
CANDLE = [(0, 3.416), (0.026, 3.416), (0.026, 3.496), (0.021, 3.500), (0, 3.500)]
FLAME = [(0, 3.496), (0.011, 3.500), (0.017, 3.511), (0.018, 3.522), (0.014, 3.537), (0.006, 3.549), (0, 3.557)]
# The glass body: corner radius at its foot and top. Posts run up the corners; the glass is a
# 3 mm shell between them; cames are lead strips 3.6 mm wide standing 1.5 mm proud each side.
BODY_Z = (3.420, 3.632)
BODY_R = (0.106, 0.141)
POST_HALF = 0.0055
GLASS_HALF = 0.0015
CAME_HALF = (0.003, 0.0018)
# The leading on each pane, as in the photo: a diamond whose side corners are tied to the posts
# by short horizontal cames, with vertical cames from its top and bottom corners to the pane's
# edges. Heights of its top, side and bottom corners as fractions of the pane's height; how far
# in from each post its side corners sit, as a fraction of the pane's width.
DIAMOND = (0.93, 0.62, 0.38)
DIAMOND_INSET = 0.2

# The arm and its brace, read off the photo: (pixels right of the post's axis, photo row, half
# the bar's width in pixels). The arm runs from the lantern's socket in to the crosshead and up
# into its volute; the brace from inside the crosshead out and down into its curl.
ARM = [
    (80.4, 285.5, 3.0), (66, 285.5, 3.0), (52, 285, 3.0), (39, 281.5, 3.0), (28.5, 274.5, 3.0),
    (22.5, 266, 3.0), (20.5, 257, 3.0), (21.5, 252, 2.7), (24, 248, 2.4), (28, 246, 2.2),
    (31.5, 247.5, 2.0), (31.5, 251.5, 1.8), (28.5, 253, 1.6), (27, 251, 1.4),
]
BRACE = [
    (14, 281.5, 2.4), (19, 281, 2.4), (24, 279, 2.2), (28.5, 280.5, 2.0), (30, 285, 1.9),
    (28.5, 290, 1.7), (24.5, 292.5, 1.5), (21.5, 291, 1.4), (22, 288.5, 1.2),
]
ARM_HALF_DEPTH = 0.009
# The stubs joining the arm (at its innermost point) and the brace to the crosshead: row, half height.
STUBS = [(257, 0.012), (281.5, 0.011)]


def photo_point(u, row):
    return Vector((u / PHOTO_SCALE, 0, (PHOTO_GROUND_Y - row) / PHOTO_SCALE))


def turns(points, closed):
    """At each point of a 2D polyline: how far it turns (degrees) and its longer neighbouring segment."""
    out = []
    for i in range(len(points)):
        if not closed and i in (0, len(points) - 1):
            out.append((180.0, 0.0))
            continue
        p, q, r = points[i - 1], points[i], points[(i + 1) % len(points)]
        a, b = (q[0] - p[0], q[1] - p[1]), (r[0] - q[0], r[1] - q[1])
        la, lb = math.hypot(*a), math.hypot(*b)
        if min(la, lb) < 1e-6:
            raise ValueError(f"repeated point {q} in a profile: it would make zero-area faces")
        cos =(a[0] * b[0] + a[1] * b[1]) / (la * lb)
        out.append((math.degrees(math.acos(max(-1.0, min(1.0, cos)))), max(la, lb)))
    return out


def is_crease(turn, longest):
    """A sharp edge: a real corner, or any visible bend next to a long flat face, whose shading
    would otherwise smear along its whole length."""
    return turn > 40 or (turn > 10 and longest > 0.05)


def lathe(profile, shape, closed=False):
    """Turns a profile about Z with the given cross-section. Walking the profile up the outside
    (or counter-clockwise, for a closed loop) gives outward faces; a zero radius is a pole.
    Returns the sharp edges too: the profile's creases and the cross-section's corners."""
    verts, rings = [], []
    for r, z in profile:
        if r == 0:
            rings.append([len(verts)])
            verts.append(Vector((0, 0, z)))
        else:
            rings.append(list(range(len(verts), len(verts) + len(shape))))
            verts += [Vector((r * x, r * y, z)) for x, y in shape]
    n = len(shape)
    pairs = list(zip(rings, rings[1:])) + ([(rings[-1], rings[0])] if closed else [])
    faces = []
    for a, b in pairs:
        for j in range(n):
            k = (j + 1) % n
            face = []
            for v in (a[j % len(a)], a[k % len(a)], b[k % len(b)], b[j % len(b)]):
                if v not in face:
                    face.append(v)
            faces.append(tuple(face))
    sharp = []
    for ring, bend in zip(rings, turns(profile, closed)):
        if len(ring) > 1 and is_crease(*bend):
            sharp += [(ring[j], ring[(j + 1) % n]) for j in range(n)]
    for j, (turn, _) in enumerate(turns(shape, True)):
        if turn > 40:
            sharp += [(a[j % len(a)], b[j % len(b)]) for a, b in pairs]
    return verts, faces, sharp


def tube(centres, frames, sizes, section):
    """Rings of a counter-clockwise 2D section at each centre, along (n, b) per frame, capped.
    (n, b, direction of travel) must be right-handed for the faces to point out. Sharp edges:
    the caps' rims."""
    verts = []
    for c, (n, b), (sn, sb) in zip(centres, frames, sizes):
        verts += [c + n * (sn * x) + b * (sb * y) for x, y in section]
    m, rings = len(section), len(centres)
    faces = [
        (i * m + j, i * m + (j + 1) % m, (i + 1) * m + (j + 1) % m, (i + 1) * m + j)
        for i in range(rings - 1)
        for j in range(m)
    ]
    faces.append(tuple(reversed(range(m))))
    faces.append(tuple((rings - 1) * m + j for j in range(m)))
    sharp = [(i * m + j, i * m + (j + 1) % m) for i in (0, rings - 1) for j in range(m)]
    return verts, faces, sharp


def bar(a, b, hint, half_n, half_s, section=SQUARE):
    """A straight bar from a to b; `half_n` is its half size along `hint`."""
    t = (b - a).normalized()
    n = (hint - t * hint.dot(t)).normalized()
    s = t.cross(n)
    return tube([a, b], [(n, s)] * 2, [(half_n, half_s)] * 2, section)


def catmull_rom(points, samples):
    padded = [points[0]] + points + [points[-1]]
    out = []
    for i in range(1, len(padded) - 2):
        p0, p1, p2, p3 = padded[i - 1 : i + 3]
        for s in range(samples):
            t = s / samples
            out.append(
                0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (3 * p1 - p0 - 3 * p2 + p3) * t ** 3)
            )
    out.append(points[-1])
    return out


def scroll(path, samples=3):
    """A bar swept along a path in the XZ plane, from photo pixels, tapering as the path says."""
    centres = catmull_rom([photo_point(u, row) for u, row, _ in path], samples)
    widths = []
    for i in range(len(path) - 1):
        widths += [path[i][2] + (path[i + 1][2] - path[i][2]) * s / samples for s in range(samples)]
    widths.append(path[-1][2])
    frames = []
    for i in range(len(centres)):
        t = (centres[min(i + 1, len(centres) - 1)] - centres[max(i - 1, 0)]).normalized()
        frames.append((Vector((t.z, 0, -t.x)), Vector((0, 1, 0))))
    sizes = [(w / PHOTO_SCALE, ARM_HALF_DEPTH) for w in widths]
    return tube(centres, frames, sizes, OCTAGON)


def body_radius(z):
    return BODY_R[0] + (BODY_R[1] - BODY_R[0]) * (z - BODY_Z[0]) / (BODY_Z[1] - BODY_Z[0])


def corner(z, k):
    a = math.radians(60 * k)
    r = body_radius(z)
    return Vector((r * math.cos(a), r * math.sin(a), z))


def lantern():
    """The right-hand lantern about its own axis: [(object, verts, faces, sharp edges or None for flat)]."""
    parts = [
        ("Iron", *lathe(BOWL, HEX)),
        ("Iron", *lathe(SOCKET, ROUND_12)),
        ("Iron", *lathe(CAP, HEX)),
        ("Iron", *lathe(CAP_FINIAL, ROUND_12)),
        ("Bulb", *lathe(CANDLE, ROUND_16)),
        ("Bulb", *lathe(FLAME, ROUND_12)),
    ]
    # Glass: a closed shell 3 mm thick, a little past the body's ends into the tray and top band.
    offset = GLASS_HALF / math.cos(math.radians(30))
    z0, z1 = BODY_Z[0] - 0.006, BODY_Z[1] + 0.006
    shell = [(body_radius(z0) + offset, z0), (body_radius(z1) + offset, z1), (body_radius(z1) - offset, z1), (body_radius(z0) - offset, z0)]
    parts.append(("Glass", *lathe(shell, HEX, closed=True)[:2], None))
    for k in range(6):
        a = math.radians(60 * k)
        radial = Vector((math.cos(a), math.sin(a), 0))
        parts.append(("Iron", *bar(corner(BODY_Z[0] - 0.002, k), corner(BODY_Z[1] + 0.002, k), radial, POST_HALF, POST_HALF)[:2], None))
        b0, b1, t0, t1 = corner(BODY_Z[0], k), corner(BODY_Z[0], k + 1), corner(BODY_Z[1], k), corner(BODY_Z[1], k + 1)
        normal = (b1 - b0).cross(t0 - b0).normalized()

        def pane(s, t):
            return b0.lerp(b1, s).lerp(t0.lerp(t1, s), t)

        top, side, bottom = DIAMOND
        left, right = DIAMOND_INSET, 1 - DIAMOND_INSET
        for a_st, b_st in [
            ((0.5, top), (right, side)), ((right, side), (0.5, bottom)),
            ((0.5, bottom), (left, side)), ((left, side), (0.5, top)),
            ((0, side), (left, side)), ((right, side), (1, side)),
            ((0.5, 1), (0.5, top)), ((0.5, bottom), (0.5, 0)),
        ]:
            parts.append(("Iron", *bar(pane(*a_st), pane(*b_st), normal, *CAME_HALF)[:2], None))
    return parts


def mirrored(verts, faces):
    return [Vector((-v.x, v.y, v.z)) for v in verts], [tuple(reversed(f)) for f in faces]


def signed_volume(verts, faces):
    volume = 0.0
    for f in faces:
        for i in range(1, len(f) - 1):
            volume += verts[f[0]].dot(verts[f[i]].cross(verts[f[i + 1]])) / 6
    return volume


def is_closed(faces):
    edges = {}
    for f in faces:
        for i in range(len(f)):
            e = tuple(sorted((f[i], f[(i + 1) % len(f)])))
            edges[e] = edges.get(e, 0) + 1
    return all(count == 2 for count in edges.values())


def all_parts():
    parts = [
        ("Iron", *lathe(BASE, chamfered_square(0.51))),
        ("Iron", *lathe(COLUMN_FOOT, ROUND_24)),
        ("Iron", *lathe(FLUTED_CONE, fluted(12, 0.06))),
        ("Iron", *lathe(COLUMN_NECK, ROUND_24)),
        ("Iron", *lathe(POLE, ROUND_16)),
        ("Iron", *lathe(CROSSHEAD, chamfered_square(0.85))),
        ("Iron", *lathe(POLE_FINIAL, ROUND_16)),
    ]
    right = [("Iron", *scroll(ARM)), ("Iron", *scroll(BRACE))]
    for row, half in STUBS:
        z = photo_point(0, row).z
        right.append(("Iron", *bar(Vector((0.050, 0, z)), Vector((0.080, 0, z)), Vector((0, 0, 1)), half, ARM_HALF_DEPTH)[:2], None))
    shift = Vector((LANTERN_X, 0, 0))
    for name, verts, faces, sharp in lantern():
        right.append((name, [v + shift for v in verts], faces, sharp))
    for name, verts, faces, sharp in right:
        parts.append((name, verts, faces, sharp))
        parts.append((name, *mirrored(verts, faces), sharp))
    return parts


def build():
    """Makes one object per part (so each keeps its own shading), then joins them by name."""
    groups = {}
    for i, (name, verts, faces, sharp) in enumerate(all_parts()):
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
        # The joined parts' meshes are orphans now; clear them so the names come out exact.
        bpy.data.orphans_purge(do_recursive=True)
        ob.name = ob.data.name = name
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.003)
        bpy.ops.object.mode_set(mode="OBJECT")
        joined[name] = ob
    return joined


def triangles(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def to_roblox(v):
    """Blender metres -> Roblox studs and axes."""
    return [round(c * STUDS_PER_METRE, 4) + 0.0 for c in (-v.x, v.z, v.y)]


def bounds(points):
    lo = Vector([min(p[i] for p in points) for i in range(3)])
    hi = Vector([max(p[i] for p in points) for i in range(3)])
    return lo, hi


def report(objects):
    out = {"units": f"studs, 1 m = {STUDS_PER_METRE:.4f} studs", "frame": "Roblox axes after import: +Y up, origin at the base centre on the ground, arms along +-X"}
    every = [v.co for ob in objects.values() for v in ob.data.vertices]
    lo, hi = bounds(every)
    out["height"] = round(hi.z * STUDS_PER_METRE, 4)
    out["heightMetres"] = round(hi.z, 4)
    out["overallWidth"] = round((hi.x - lo.x) * STUDS_PER_METRE, 4)
    base = [v for v in every if v.z < 0.05]
    blo, bhi = bounds(base)
    out["baseFootprint"] = {"x": round((bhi.x - blo.x) * STUDS_PER_METRE, 4), "z": round((bhi.y - blo.y) * STUDS_PER_METRE, 4)}
    bulbs = []
    for sign in (1, -1):
        side = [v.co for v in objects["Bulb"].data.vertices if v.co.x * sign > 0]
        blo, bhi = bounds(side)
        centre = to_roblox((blo + bhi) / 2)
        bulbs.append({"side": "+X" if centre[0] > 0 else "-X", "centre": centre, "size": [abs(c) for c in to_roblox(bhi - blo)]})
    out["bulbs"] = sorted(bulbs, key=lambda b: b["side"])
    out["objects"] = {}
    for name, ob in objects.items():
        olo, ohi = bounds([v.co for v in ob.data.vertices])
        out["objects"][name] = {"centre": to_roblox((olo + ohi) / 2), "size": [abs(c) for c in to_roblox(ohi - olo)]}
    out["triangles"] = {name: triangles(ob) for name, ob in objects.items()}
    out["triangles"]["total"] = sum(out["triangles"].values())
    return out


def camera(scene, eye, target, ortho=None, lens=50):
    data = bpy.data.cameras.new("Camera")
    ob = bpy.data.objects.new("Camera", data)
    scene.collection.objects.link(ob)
    ob.location = eye
    ob.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()
    if ortho:
        data.type = "ORTHO"
        data.ortho_scale = ortho
    else:
        data.lens = lens
    data.clip_end = 100
    scene.camera = ob
    return ob


def render(scene, path, size, eye, target, ortho=None, lens=50):
    scene.render.resolution_x, scene.render.resolution_y = size
    cam = camera(scene, eye, target, ortho, lens)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


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
    colours = {"Iron": (0.035, 0.035, 0.04, 1), "Glass": (0.75, 0.85, 0.9, 0.35), "Bulb": (1.0, 0.82, 0.45, 1)}
    for name, ob in objects.items():
        mat = bpy.data.materials.new(name)
        mat.diffuse_color = colours[name]
        if colours[name][3] < 1:
            mat.surface_render_method = "BLENDED"
        ob.data.materials.append(mat)
    return scene


def load_pixels(path):
    """An image's RGBA, top row first."""
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)[::-1].copy()


def resized(px, w, h):
    img = bpy.data.images.new("tmp", px.shape[1], px.shape[0], alpha=True)
    img.pixels.foreach_set(px[::-1].ravel())
    img.scale(w, h)
    out = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(out)
    bpy.data.images.remove(img)
    return out.reshape(h, w, 4)[::-1].copy()


def save_pixels(px, path):
    img = bpy.data.images.new("sheet", px.shape[1], px.shape[0], alpha=False)
    img.pixels.foreach_set(px[::-1].ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def compare(scene, photo_path, out):
    """Front orthographic views at the photo's own scale, next to the photo and over it."""
    photo = load_pixels(photo_path)
    rows = []
    # (photo crop: left, top, right, bottom in photo pixels; enlargement)
    for left, top, right, bottom, zoom in [
        (round(PHOTO_AXIS_X) - 220, 90, round(PHOTO_AXIS_X) + 220, 1180, 1),
        (round(PHOTO_AXIS_X) - 150, 100, round(PHOTO_AXIS_X) + 150, 300, 2),
    ]:
        crop = photo[top:bottom, left:right]
        w, h = (right - left) * zoom, (bottom - top) * zoom
        if zoom != 1:
            crop = resized(crop, w, h)
        cx = ((left + right) / 2 - PHOTO_AXIS_X) / PHOTO_SCALE
        cz = (PHOTO_GROUND_Y - (top + bottom) / 2) / PHOTO_SCALE
        span = max(right - left, bottom - top) / PHOTO_SCALE
        tmp = os.path.join(out, "_compare_tmp.png")
        # A true silhouette: the drawn outline would widen every part by a pixel or two.
        scene.render.film_transparent = True
        scene.display.shading.show_object_outline = False
        render(scene, tmp, (w, h), Vector((cx, -30, cz)), Vector((cx, 0, cz)), ortho=span)
        scene.display.shading.show_object_outline = True
        scene.render.film_transparent = False
        model = load_pixels(tmp)
        os.remove(tmp)
        alpha = model[..., 3:4]
        on_sky = np.concatenate([np.full((h, w, 3), 0.78, np.float32), np.ones((h, w, 1), np.float32)], -1)
        model_panel = model * alpha + on_sky * (1 - alpha)
        grey = crop[..., :3].mean(-1, keepdims=True).repeat(3, -1)
        red = np.array([0.9, 0.05, 0.05], np.float32)
        overlay = grey * (1 - 0.55 * alpha) + red * 0.55 * alpha
        overlay = np.concatenate([overlay, np.ones((h, w, 1), np.float32)], -1)
        gap = np.ones((h, 12, 4), np.float32)
        rows.append(np.concatenate([crop, gap, model_panel, gap, overlay], 1))
    width = max(r.shape[1] for r in rows)
    padded = []
    for r in rows:
        pad = width - r.shape[1]
        padded.append(np.pad(r, ((0, 12), (pad // 2, pad - pad // 2), (0, 0)), constant_values=1))
    save_pixels(np.concatenate(padded, 0), os.path.join(out, "compare.png"))


def check_export(path, expected):
    """Re-imports the .glb and checks the names, triangle counts and size survived the export."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    found = {ob.name: ob for ob in bpy.context.scene.objects if ob.type == "MESH"}
    if sorted(found) != sorted(expected["objects"]):
        raise RuntimeError(f"export holds {sorted(found)}, expected {sorted(expected['objects'])}")
    for name, ob in found.items():
        ob.data.calc_loop_triangles()
        if len(ob.data.loop_triangles) != expected["triangles"][name]:
            raise RuntimeError(f"{name}: {len(ob.data.loop_triangles)} triangles after export, {expected['triangles'][name]} before")
        if not ob.data.uv_layers:
            raise RuntimeError(f"{name} lost its UVs")
        # Every part is a closed outward shell, so each object's signed volume must stay positive:
        # an axis conversion that flipped the winding would turn it negative.
        verts = [ob.matrix_world @ v.co for v in ob.data.vertices]
        faces = [tuple(t.vertices) for t in ob.data.loop_triangles]
        if signed_volume(verts, faces) <= 0:
            raise RuntimeError(f"{name}'s faces point inward after export")
    points = [ob.matrix_world @ v.co for ob in found.values() for v in ob.data.vertices]
    lo, hi = bounds(points)
    # Re-imported, glTF's Y-up is Blender's Z-up again: height along Z, arms along X.
    if abs(hi.z - expected["height"]) > 0.01 or abs(lo.z) > 0.01 or abs((hi.x - lo.x) - expected["overallWidth"]) > 0.01:
        raise RuntimeError(f"re-imported bounds {tuple(lo)} .. {tuple(hi)} do not match")
    print("export check: names, triangle counts, UVs, size and outward faces survive the round trip")


def option(args, name, default):
    return args[args.index(name) + 1] if name in args else default


def main(args):
    out = args[0]
    photo = option(args, "--photo", None)
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objects = build()
    for name, ob in objects.items():
        if triangles(ob) >= 20000:
            raise RuntimeError(f"{name} has {triangles(ob)} triangles; Roblox caps a mesh at 20,000")
    results = report(objects)
    print(json.dumps(results, indent=1))

    scene = setup_renders(objects)
    mid = Vector((0, 0, 1.95))
    render(scene, os.path.join(out, "check_front.png"), (640, 1100), Vector((0, -30, 1.95)), mid, ortho=4.2)
    render(scene, os.path.join(out, "check_side.png"), (640, 1100), Vector((30, 0, 1.95)), mid, ortho=4.2)
    render(scene, os.path.join(out, "check_three_quarter.png"), (700, 1100), Vector((-3.6, -5.4, 3.0)), mid, lens=50)
    render(scene, os.path.join(out, "check_head.png"), (1100, 800), Vector((-0.9, -1.45, 3.15)), Vector((0, 0, 3.5)), lens=50)
    if photo:
        compare(scene, photo, out)

    # Export: metres -> studs, no materials (the game sets them).
    for ob in objects.values():
        ob.data.materials.clear()
        ob.data.transform(Matrix.Scale(STUDS_PER_METRE, 4))
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects.values():
        ob.select_set(True)
    glb = os.path.join(out, "street_lamp.glb")
    bpy.ops.export_scene.gltf(filepath=glb, use_selection=True, export_materials="NONE", export_yup=True)
    json.dump(results, open(os.path.join(out, "street_lamp.json"), "w"), indent=1)
    check_export(glb, results)


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1 :])
