"""
Gives the hero car's cockpit real material detail, run headless by Blender:

    blender -b --python tools/blender/hero_car_interior_detail.py -- <car.blend> <texture dir> \
        <upscaled colour.png> <out dir> [--size 2048] [--stages layout,bake,render] \
        [--before-color <png>] [--before-emissive <png>] [--flip-source-green]

Why the cockpit looked flat. Interior_Geo_lodA's UVChannel_1 maps 94% of its surface (12.7 of
13.5 m2: dash top, wheel rim, seats, door cards, headliner, floor) onto a grid of twelve flat
16-pixel swatches in the 512 atlas, at about 7.5 texels per metre, and mirrored or repeated
parts share the same texels (75% of the area overlaps). Each of those faces gets one colour, one
gloss value and a flat normal, so no texture resolution can give them material, and object-space
detail cannot be baked into a layout where most of the area overlaps. Only buttons, glyphs, vents
and stitch strips (0.8 m2) carry real texture.

So this script rebuilds UVChannel_1, then bakes into it:

1. layout:
   - Deletes the SV seat emblems and the headrest shields. They are separate decal meshes
     floating on the upholstery (white and red swatch faces), so painting them over left their
     relief showing; the hub's shield recess is real geometry and is painted over instead.
   - Keeps the old UV set as UVChannel_1_atlas (the bake source; glTF writes it as a later
     TEXCOORD, which Roblox ignores) and rewrites UVChannel_1 as a unique layout. It reuses the
     artist's islands, which are sound unwraps that were only shrunk (median anisotropy 1.05);
     the 79 swatch islands that fold over themselves (harmless while they sampled one flat
     colour) are re-unwrapped with Smart UV Project.
   - Density follows what the driver sees: wheel x3, carbon x2.5, surfaces near the driver's eye
     x1.6, faces turned away x0.45, the frunk liner x0.25; the base is the largest that packs.
     Buttons, glyphs and vents stay one rigid block in their old atlas arrangement at 1.5x their
     old texel density, so copies that shared texels still share them. Long stitch strips get
     2.5x the surface around them, up to 1100 texels/m.
   - Packs with its own raster packer (Blender's pack_islands filled about a third of the square
     on this mix of 2,500 islands), checks that no face that owns its texels overlaps another,
     and checks that no other mesh in the car changed.
   - Gives every face a material zone (see ZONE RULES). Saves svj_interior_v2.blend: the whole
     car with the new UVs. Export from that file: the maps fit only its UVChannel_1.
2. bake: bakes into UVChannel_1 at --size: AO, colour (upscaled atlas for decals, swatch colour
   times per-zone variation for the rest, times AO, glow colour merged in as hero_car_maps.py
   does), tangent normal (source normal map plus object-space micro-detail through a Bump node,
   OpenGL green-up), roughness, metalness and the emissive map (read through UVChannel_2, as
   hero_car_bake_emissive.py does). 16 samples per texel, which Cycles jitters inside the texel,
   so procedural detail is filtered, not aliased.
3. render: Cycles renders from the driver's eye, the wheel, the console and a seat bolster, before
   (the current maps on the old UV set, uniform roughness 0.7) and after (the new maps), into
   <out dir>/renders.

ZONE RULES (per face; "swatch" = the flat atlas cell a face sampled in the old layout):
  metal       swatch metal mask (R) > 128                                    rough 0.30, metal 1
              (every metal texel: base colour 0.25 + 1.6 x atlas, clamped 0.25-0.9; rough >= 0.25)
  red suede   swatch red (R > 150, G < 80)                                   rough 0.88
  carbon      swatch gloss (G) > 180 (console face, lower wheel spokes)      rough 0.15
  suede       swatch gloss < 35 (dash top, rim, seats, doors, headliner)     rough 0.90
  carpet      swatch metal < 28 and gloss 30-55 (floor, frunk liner)         rough 0.95
  satin       any other swatch (gloss 55-180: console sides, trims)          rough 0.50
  leather     satin inside the fitted wheel hub, or on a seat                rough 0.60
  perforated  suede on the fitted rim torus within 55-125 deg of 12 o'clock  rough 0.60, colour x1.8
  decal       faces with real texture: colour, normal, gloss and metal come from the atlas
              (rough = 1 - gloss^0.8, metal = smoothstep(0.45, 0.65, R))
"""

import json
import math
import struct
import sys
import time
import zlib
from pathlib import Path

import bmesh
import bpy
import numpy as np
from bpy_extras import bmesh_utils
from mathutils import Vector

OBJECT = "Interior_Geo_lodA"
NEW_UV, OLD_UV, EMISSIVE_UV = "UVChannel_1", "UVChannel_1_atlas", "UVChannel_2"
PREFIX = "Lamborghini_AventadorSVJ_2019_InteriorA_"
EYES = (Vector((0.36, -0.05, 0.86)), Vector((-0.36, -0.05, 0.86)))  # driver (LHD, +X), passenger
DRIVER_EYE = EYES[0]

DECAL, SUEDE, RED_SUEDE, LEATHER, PERFORATED, CARBON, SATIN, CARPET, METAL = range(9)
ZONE_NAMES = ["decal", "suede", "red suede", "leather", "perforated leather", "carbon", "satin plastic", "carpet", "metal"]
ROUGHNESS = {SUEDE: 0.90, RED_SUEDE: 0.88, LEATHER: 0.60, PERFORATED: 0.60, CARBON: 0.15, SATIN: 0.50, CARPET: 0.95, METAL: 0.30}

# Old-atlas boxes in 512-map pixels, top-left origin: (x0, y0, x1, y1).
SHIELD_BOX = (274, 91, 396, 212)  # the debadged shield: hub badge and headrest patches sample it
WHITE_SWATCH = (460, 298, 482, 320)  # the SV emblem's white letters
RED_SWATCHES = (290, 270, 311, 313)  # the emblem's red slash (shared with the red accents)

SWATCH_DENSITY = 60  # old texels (512 map) per metre below which an island is a flat swatch
DECAL_GAIN = 1.5  # shared decals keep this multiple of their old 512-map texel density
MAX_ISLAND_EXTENT = 0.45  # of the texture, so long islands still pack
CELL = 4  # packing grid cell, in texels; packed islands keep at least one cell between them

args = sys.argv[sys.argv.index("--") + 1 :]


def option(name, default=None):
    return args[args.index(name) + 1] if name in args else default


BLEND, TEXTURES, UPSCALED, OUT = Path(args[0]), Path(args[1]), Path(args[2]), Path(args[3])
SIZE = int(option("--size", 2048))
STAGES = option("--stages", "layout,bake,render").split(",")
FLIP_SOURCE_GREEN = "--flip-source-green" in args
V2_BLEND = OUT / "svj_interior_v2.blend"
LAYOUT_JSON = OUT / "layout.json"
OUT.mkdir(parents=True, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0  # no .blend1 backups next to the outputs


def log(*parts):
    print("[interior]", *parts, flush=True)


def peak_memory_mb() -> float:
    import ctypes
    from ctypes import wintypes

    class Counters(ctypes.Structure):
        _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD)] + [
            (n, ctypes.c_size_t)
            for n in ("PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage", "QuotaPagedPoolUsage",
                      "QuotaPeakNonPagedPoolUsage", "QuotaNonPagedPoolUsage", "PagefileUsage", "PeakPagefileUsage")
        ]

    counters = Counters()
    counters.cb = ctypes.sizeof(Counters)
    current = ctypes.windll.kernel32.GetCurrentProcess
    current.restype = wintypes.HANDLE
    query = ctypes.windll.psapi.GetProcessMemoryInfo
    query.argtypes = [wintypes.HANDLE, ctypes.POINTER(Counters), wintypes.DWORD]
    query(current(), ctypes.byref(counters), counters.cb)
    return counters.PeakWorkingSetSize / 2**20


# ---------------------------------------------------------------------------------------------
# Small helpers: images as arrays, a dependency-free PNG writer, colour transfer functions.

def image_array(path: Path) -> np.ndarray:
    """Raw stored values in 0..1, row 0 = bottom (v = 0), as Blender keeps them."""
    image = bpy.data.images.load(str(path), check_existing=True)
    pixels = np.empty(image.size[0] * image.size[1] * 4, np.float32)
    image.pixels.foreach_get(pixels)
    return pixels.reshape(image.size[1], image.size[0], 4)


def write_png(path: Path, pixels: np.ndarray):
    """8-bit PNG from a float array in 0..1, row 0 = bottom. Grey (H, W) or RGB/RGBA (H, W, C)."""
    data = np.clip(np.round(pixels[::-1] * 255), 0, 255).astype(np.uint8)
    height, width = data.shape[:2]
    channels = 1 if data.ndim == 2 else data.shape[2]
    rows = np.concatenate([np.zeros((height, 1), np.uint8), data.reshape(height, width * channels)], axis=1)

    def chunk(tag: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, {1: 0, 3: 2, 4: 6}[channels], 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(rows.tobytes(), 6)) + chunk(b"IEND", b""))


def to_linear(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(c):
    c = np.clip(np.asarray(c, dtype=np.float64), 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def in_box(px, py, box):
    return (px >= box[0]) & (px < box[2]) & (py >= box[1]) & (py < box[3])


def raster(points, start, total, faces, res, values=None):
    """How many triangles cover each texel centre of a res x res grid over UV 0-1 (row 0 = v 0),
    and optionally paints each face's value into the texels it covers."""
    count = np.zeros((res, res), np.int32)
    paint = None if values is None else np.zeros((res, res, values.shape[1]), np.float32)
    for f in faces:
        s = start[f]
        for k in range(1, total[f] - 1):
            tri = points[[s, s + k, s + k + 1]] * res
            x0, y0 = np.maximum(np.floor(tri.min(0)).astype(int), 0)
            x1, y1 = np.minimum(np.ceil(tri.max(0)).astype(int), res)
            if x1 <= x0 or y1 <= y0:
                continue
            xs, ys = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
            (ax, ay), (bx, by), (cx, cy) = tri
            d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(d) < 1e-12:
                continue
            l1 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / d
            l2 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / d
            inside = (l1 >= 0) & (l2 >= 0) & (l1 + l2 <= 1)
            count[y0:y1, x0:x1] += inside
            if paint is not None:
                paint[y0:y1, x0:x1][inside] = values[f]
    return count, paint


def union_area(points, start, total, faces, res) -> float:
    return float((raster(points, start, total, faces, res)[0] > 0).mean())


def self_overlaps(points, start, total, faces) -> bool:
    """Whether an island covers some texel twice, rasterised at about 96 texels across."""
    loops = np.concatenate([np.arange(start[f], start[f] + total[f]) for f in faces])
    span = np.ptp(points[loops], axis=0).max()
    if span < 1e-12:
        return False
    local = points.copy()
    local[loops] = (points[loops] - points[loops].min(0)) / span * 0.96 + 0.02
    count, _ = raster(local, start, total, faces, 96)
    return int((count > 1).sum()) > 3


def overlap_texels(points, start, total, unique_face, res) -> int:
    """Texels where a face that must own its texels is covered by more than one triangle."""
    every, _ = raster(points, start, total, range(len(start)), res)
    own, _ = raster(points, start, total, np.where(unique_face)[0], res)
    return int(((own > 0) & (every > 1)).sum())


ZONE_COLOURS = np.array([(0.85, 0.85, 0.85), (0.9, 0.2, 0.2), (1.0, 0.55, 0.1), (0.2, 0.75, 0.25), (0.1, 0.5, 0.15),
                         (0.55, 0.25, 0.9), (0.95, 0.9, 0.2), (0.2, 0.4, 0.95), (0.2, 0.9, 0.9)])


def write_layout_image(path, points, start, total, zone, res):
    """The new UV layout, each face filled with its zone's colour (legend in the report)."""
    path.parent.mkdir(exist_ok=True)
    _, paint = raster(points, start, total, range(len(start)), res, ZONE_COLOURS[zone])
    write_png(path, paint)


def face_uv_area(points, start, total):
    out = np.zeros(len(start))
    for k in range(1, total.max() - 1):
        has = total > k + 1
        a, b, c = points[start[has]], points[start[has] + k], points[start[has] + k + 1]
        out[has] += 0.5 * np.abs((b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1]) - (c[:, 0] - a[:, 0]) * (b[:, 1] - a[:, 1]))
    return out


def cell_mask(points, tris):
    """Grid cells a set of triangles touches (points in cell units, minimum at 1), dilated by one
    cell so packed islands keep a cell of margin between them."""
    w = int(np.ceil(points[:, 0].max())) + 2
    h = int(np.ceil(points[:, 1].max())) + 2
    m = np.zeros((h, w), bool)
    a, b, c = points[tris[:, 0]], points[tris[:, 1]], points[tris[:, 2]]
    samples = [a, b, c, (a + b + c) / 3] + [p + (q - p) * t for t in (0.25, 0.5, 0.75) for p, q in ((a, b), (b, c), (c, a))]
    hits = np.concatenate(samples).astype(int)
    m[hits[:, 1], hits[:, 0]] = True
    longest = np.max([np.linalg.norm(b - a, axis=1), np.linalg.norm(c - b, axis=1), np.linalg.norm(a - c, axis=1)], axis=0)
    for i in np.where(longest > 1.0)[0]:  # triangles larger than a cell: edges and interior too
        tri = np.array([a[i], b[i], c[i]])
        for p, q in ((0, 1), (1, 2), (2, 0)):
            e = tri[p] + (tri[q] - tri[p]) * np.linspace(0, 1, int(np.linalg.norm(tri[q] - tri[p]) * 2) + 2)[:, None]
            m[e[:, 1].astype(int), e[:, 0].astype(int)] = True
        x0, y0 = np.floor(tri.min(0)).astype(int)
        x1, y1 = np.ceil(tri.max(0)).astype(int)
        xs, ys = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
        (ax, ay), (bx, by), (cx, cy) = tri
        d = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(d) > 1e-12:
            l1 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / d
            l2 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / d
            m[y0:y1, x0:x1] |= (l1 >= 0) & (l2 >= 0) & (l1 + l2 <= 1)
    grown = m.copy()
    grown[1:] |= m[:-1]
    grown[:-1] |= m[1:]
    out = grown.copy()
    out[:, 1:] |= grown[:, :-1]
    out[:, :-1] |= grown[:, 1:]
    return out


def raster_pack(units, size, n_loops):
    """Packs units into a size x size texture on a grid of CELL texels: largest first, each at the
    lowest free spot in whichever of its orientations sits lower. A unit needs its bounding box
    empty, then marks only the cells it covers, so later, smaller units fill its hollows. Returns
    UVs per loop, or None if the units do not fit."""
    grid = size // CELL
    occupied = np.zeros((grid, grid), bool)
    table = np.zeros((grid + 1, grid + 1), np.int64)  # summed-area table of occupied cells
    options = []
    for u in units:
        found = []
        for t in u["texels"]:
            origin = t.min(0) / CELL - 1
            found.append((cell_mask(t / CELL - origin, u["tris"]), origin))
        options.append(found)
    order = sorted(range(len(units)), key=lambda n: (0 if "fixed" in units[n] else 1, -max(m.size for m, _ in options[n])))
    out = np.zeros((n_loops, 2))
    for n in order:
        best = None
        for k, (mask, _) in enumerate(options[n]):
            h, w = mask.shape
            if h > grid or w > grid:
                continue
            free = (table[h:, w:] - table[:-h, w:] - table[h:, :-w] + table[:-h, :-w]) == 0
            if not free.any():
                continue
            y, x = divmod(int(np.argmax(free)), free.shape[1])
            if best is None or (y + h, x) < best[0]:
                best = ((y + h, x), k, y, x)
        if best is None:
            return None
        _, k, y, x = best
        mask, origin = options[n][k]
        occupied[y:y + mask.shape[0], x:x + mask.shape[1]] |= mask
        table[1:, 1:] = occupied.cumsum(0).cumsum(1)
        out[units[n]["loops"]] = (units[n]["texels"][k] / CELL - origin + (x, y)) * CELL / size
    return out


# ---------------------------------------------------------------------------------------------
# Stage 1: unique layout and zones.

def face_arrays(obj):
    me = obj.data
    mw = np.array(obj.matrix_world)
    count = len(me.polygons)
    centre = np.empty(count * 3); me.polygons.foreach_get("center", centre)
    normal = np.empty(count * 3); me.polygons.foreach_get("normal", normal)
    area = np.empty(count); me.polygons.foreach_get("area", area)
    centre = centre.reshape(-1, 3) @ mw[:3, :3].T + mw[:3, 3]
    normal = normal.reshape(-1, 3) @ mw[:3, :3].T
    return centre, normal, area


def loop_arrays(obj, uv_name):
    me = obj.data
    uv = np.empty(len(me.loops) * 2); me.uv_layers[uv_name].data.foreach_get("uv", uv)
    vert = np.empty(len(me.loops), np.int64); me.loops.foreach_get("vertex_index", vert)
    start = np.empty(len(me.polygons), np.int64); me.polygons.foreach_get("loop_start", start)
    total = np.empty(len(me.polygons), np.int64); me.polygons.foreach_get("loop_total", total)
    co = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", co)
    mw = np.array(obj.matrix_world)
    co = co.reshape(-1, 3) @ mw[:3, :3].T + mw[:3, 3]
    face_of_loop = np.repeat(np.arange(len(me.polygons)), total)
    return uv.reshape(-1, 2), co[vert], start, total, face_of_loop


def loose_parts(obj):
    """Face -> part id, joining faces that share a vertex position (FBX splits vertices at seams)."""
    me = obj.data
    co = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", co)
    _, weld = np.unique(np.round(co.reshape(-1, 3) * 1e4).astype(np.int64), axis=0, return_inverse=True)
    weld = weld.ravel()
    parent = list(range(weld.max() + 1))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for poly in me.polygons:
        keys = [weld[v] for v in poly.vertices]
        root = find(keys[0])
        for k in keys[1:]:
            other = find(k)
            if other != root:
                parent[other] = root
    return np.array([find(weld[poly.vertices[0]]) for poly in me.polygons])


def fit_wheel(centre, area, part, loop_pos, face_of_loop):
    """Finds the steering wheel (rim, spokes and hub are one welded part: a flat, round disc about
    0.37 m across in front of the driver) and fits the rim: plane, centre, ring radius R and tube
    radius r, from the outer ring of its vertices only, since the spokes pull the centroid down."""
    box = (centre[:, 0] > 0.12) & (centre[:, 0] < 0.62) & (centre[:, 1] > -0.75) & (centre[:, 1] < -0.25) & (centre[:, 2] > 0.35) & (centre[:, 2] < 0.95)
    best = None
    seen = []
    for pid in np.unique(part[box]):
        faces = np.where(part == pid)[0]
        if len(faces) < 40:
            continue
        pts = loop_pos[np.isin(face_of_loop, faces)]
        mid = pts.mean(0)
        evals, evecs = np.linalg.eigh(np.cov((pts - mid).T))
        axis = evecs[:, 0]
        q = pts - mid
        rho = np.linalg.norm(q - np.outer(q @ axis, axis), axis=1)
        outer = np.percentile(rho, 95)
        disc = evals[0] < 0.1 * evals[1] and evals[1] > 0.6 * evals[2] and 0.15 < outer < 0.23 and mid[0] > 0
        seen.append((round(float(area[faces].sum()), 4), len(faces), np.round(mid, 3).tolist(), np.round(evals / evals[2], 3).tolist(),
                     round(float(outer), 3)))
        if disc and (best is None or area[faces].sum() > best[1]):
            best = (pid, area[faces].sum(), mid, axis, pts)
    if best is None:
        for row in sorted(seen, reverse=True)[:15]:
            log("candidate part: area, faces, centre, eigenvalue ratios, 95th-percentile radius", row)
        raise RuntimeError("steering wheel not found")
    _, _, mid, axis, pts = best
    if axis[1] < 0:  # point the axis back toward the driver (+Y)
        axis = -axis
    up = np.array([0.0, 0.0, 1.0]) - axis[2] * axis
    up /= np.linalg.norm(up)
    right = np.cross(up, axis)
    q = pts - mid
    rho = np.linalg.norm(q - np.outer(q @ axis, axis), axis=1)
    rim = rho > 0.8 * np.percentile(rho, 95)
    centre_fit = mid
    for _ in range(3):  # circle fit in the wheel plane, then keep the vertices near that circle
        q = pts[rim] - centre_fit
        x, y = q @ right, q @ up
        sol, *_ = np.linalg.lstsq(np.c_[2 * x, 2 * y, np.ones_like(x)], x**2 + y**2, rcond=None)
        centre_fit = centre_fit + sol[0] * right + sol[1] * up + np.median(q @ axis) * axis
        ring_r = math.sqrt(sol[2] + sol[0] ** 2 + sol[1] ** 2)
        q = pts - centre_fit
        h = q @ axis
        rho = np.linalg.norm(q - np.outer(h, axis), axis=1)
        rim = (np.abs(rho - ring_r) < 0.035) & (np.abs(h) < 0.035)
    tube_r = float(np.median(np.hypot(rho[rim] - ring_r, h[rim])))
    return {"centre": centre_fit, "axis": axis, "up": up, "right": right, "R": float(ring_r), "r": tube_r}


def wheel_coords(points, wheel):
    q = points - wheel["centre"]
    h = q @ wheel["axis"]
    inplane = q - np.outer(h, wheel["axis"])
    rho = np.linalg.norm(inplane, axis=1)
    theta = np.arctan2(inplane @ wheel["right"], inplane @ wheel["up"])  # 0 at 12 o'clock
    phi = np.arctan2(h, rho - wheel["R"])
    return h, rho, theta, phi


def swatch_zone(colour, mask):
    """Material zone of a flat swatch, from its colour and its material mask (0..255)."""
    if mask[0] > 128:
        return METAL
    if colour[0] > 150 and colour[1] < 80:
        return RED_SUEDE
    if mask[1] > 180:
        return CARBON
    if mask[1] < 35:
        return SUEDE
    if mask[0] < 28 and 30 <= mask[1] < 55:
        return CARPET
    return SATIN


def badge_candidates(px, py, centre):
    """Faces of the SV seat emblems (white letters plus the red slash beside them) and faces that
    sample the debadged shield box (headrest patches and the hub's badge recess)."""
    letters = in_box(px, py, WHITE_SWATCH) & (np.abs(centre[:, 0]) > 0.35) & (centre[:, 1] > -0.25)
    slash = np.zeros(len(px), bool)
    if letters.any():
        reds = np.where(in_box(px, py, RED_SWATCHES))[0]
        d = np.linalg.norm(centre[reds][:, None] - centre[letters][None], axis=2).min(1)
        slash[reds[d < 0.05]] = True
    return letters, slash, in_box(px, py, SHIELD_BOX)


def edit_alone(obj):
    """Edit Mode on this object only. The car file keeps other objects selected, and Edit Mode
    takes every selected mesh with it, so mesh operators would also delete or re-unwrap faces of
    the door cards and carbon trims (they did, before this)."""
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")


def mesh_fingerprint(skip):
    """Face count and UV checksum of every other mesh, to prove the cockpit work left them alone."""
    out = {}
    for o in bpy.data.objects:
        if o.type == "MESH" and o.name != skip:
            uv = np.zeros(len(o.data.loops) * 2)
            if o.data.uv_layers:
                o.data.uv_layers[0].data.foreach_get("uv", uv)
            out[o.name] = (len(o.data.polygons), round(float(uv.sum()), 3))
    return out


def delete_floating_badges(obj):
    """The SV seat emblems and the headrest shields are separate decal meshes floating on the
    upholstery: loose parts made only of badge faces. Painted over they still show their relief,
    so they are deleted (in Edit Mode, which keeps the custom split normals a bmesh round trip
    would drop). Badge faces that are part of a real surface stay and get painted over."""
    centre, _, _ = face_arrays(obj)
    uv, _, start, total, _ = loop_arrays(obj, NEW_UV)  # still the old atlas layout here
    face_uv = np.mod(np.array([uv[s:s + t].mean(0) for s, t in zip(start, total)]), 1.0)
    letters, slash, shield = badge_candidates(face_uv[:, 0] * 512, (1 - face_uv[:, 1]) * 512, centre)
    candidate = letters | slash | shield
    part = loose_parts(obj)
    doomed = [pid for pid in np.unique(part[candidate]) if candidate[part == pid].all()]
    kill = np.where(np.isin(part, doomed))[0]
    centres = [np.round(centre[part == pid].mean(0), 3).tolist() for pid in doomed]
    edit_alone(obj)
    bpy.context.scene.tool_settings.mesh_select_mode = (False, False, True)
    bm = bmesh.from_edit_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    for f in bm.faces:
        f.select_set(False)
    for i in kill:
        bm.faces[i].select_set(True)
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.mesh.delete(type="FACE")
    bpy.ops.object.mode_set(mode="OBJECT")
    log(f"deleted {len(doomed)} floating badge meshes ({len(kill)} faces) at {centres}")
    return centres


def stage_layout():
    bpy.ops.wm.open_mainfile(filepath=str(BLEND))
    obj = bpy.data.objects[OBJECT]
    me = obj.data
    others_before = mesh_fingerprint(OBJECT)
    removed_badges = delete_floating_badges(obj)
    if OLD_UV not in me.uv_layers:
        keep = me.uv_layers.new(name=OLD_UV, do_init=False)
        buf = np.empty(len(me.loops) * 2, np.float32)
        me.uv_layers[NEW_UV].data.foreach_get("uv", buf)
        keep.data.foreach_set("uv", buf)

    colour512 = image_array(TEXTURES / f"{PREFIX}DiffuseAOSO.png")
    mask512 = image_array(TEXTURES / f"{PREFIX}MaterialOpacity.png")
    n512 = colour512.shape[0]
    centre, normal, area = face_arrays(obj)
    uv, loop_pos, start, total, face_of_loop = loop_arrays(obj, OLD_UV)
    faces = len(area)

    # Islands of the old layout, with their old density.
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    islands = [[f.index for f in isl] for isl in bmesh_utils.bmesh_linked_uv_islands(bm, bm.loops.layers.uv[OLD_UV])]
    bm.free()
    island_of = np.empty(faces, np.int64)
    for i, isl in enumerate(islands):
        island_of[isl] = i
    tri_uv_area = np.zeros(faces)
    for k in range(1, total.max() - 1):
        has = total > k + 1
        a, b, c = uv[start[has]], uv[start[has] + k], uv[start[has] + k + 1]
        tri_uv_area[has] += 0.5 * np.abs((b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1]) - (c[:, 0] - a[:, 0]) * (b[:, 1] - a[:, 1]))
    isl_area = np.bincount(island_of, weights=area)
    isl_uv_area = np.bincount(island_of, weights=tri_uv_area)
    isl_density512 = np.sqrt(isl_uv_area / np.maximum(isl_area, 1e-12)) * n512
    face_uv = np.array([uv[s:s + t].mean(0) for s, t in zip(start, total)])
    isl_uv = np.c_[np.bincount(island_of, weights=face_uv[:, 0] * area), np.bincount(island_of, weights=face_uv[:, 1] * area)] / np.maximum(isl_area, 1e-12)[:, None]
    swatch_isl = isl_density512 < SWATCH_DENSITY
    swatch = swatch_isl[island_of]

    def sample(uv_points):
        m = np.mod(uv_points, 1.0)
        px = np.clip((m[:, 0] * n512).astype(int), 0, n512 - 1)
        row = np.clip((m[:, 1] * n512).astype(int), 0, n512 - 1)
        return px, n512 - 1 - row, colour512[row, px, :3] * 255, mask512[row, px, :3] * 255

    _, _, isl_colour, isl_mask = sample(isl_uv)
    fpx, fpy, _, _ = sample(face_uv)

    zone = np.full(faces, DECAL)
    base = np.zeros((faces, 3))
    for i in np.where(swatch_isl)[0]:
        zone[islands[i]] = swatch_zone(isl_colour[i], isl_mask[i])
        base[islands[i]] = to_linear(isl_colour[i] / 255)

    # Steering wheel.
    part = loose_parts(obj)
    wheel = fit_wheel(centre, area, part, loop_pos, face_of_loop)
    h, rho, theta, phi = wheel_coords(centre, wheel)
    R, r = wheel["R"], wheel["r"]
    on_wheel = (rho < R + 3 * r) & (np.abs(h) < 0.10)
    on_rim = (np.abs(rho - R) < 2.2 * r) & (np.abs(h) < 2.2 * r)
    grip = on_rim & (np.abs(np.degrees(theta)) > 55) & (np.abs(np.degrees(theta)) < 125)
    zone[grip & (zone == SUEDE)] = PERFORATED
    hub = on_wheel & (rho < R - 2.5 * r)
    zone[hub & (zone == SATIN)] = LEATHER
    seat = (np.abs(centre[:, 0]) > 0.13) & (np.abs(centre[:, 0]) < 0.66) & (centre[:, 1] > -0.15) & (centre[:, 1] < 0.62)
    zone[seat & (zone == SATIN)] = LEATHER
    log(f"wheel centre {np.round(wheel['centre'], 3)} axis {np.round(wheel['axis'], 3)} R {R:.3f} r {r:.4f}; "
        f"rim faces {on_rim.sum()}, grip faces {(zone == PERFORATED).sum()}, hub leather {(hub & (zone == LEATHER)).sum()}")

    # Badge faces left after the floating ones were deleted (the hub's shield recess) take the
    # material of the surface around them.
    letters, slash, shield = badge_candidates(fpx, fpy, centre)
    shield &= ~swatch
    badge = shield | letters | slash
    donors = np.where(~badge & (zone != DECAL))[0]
    for f in np.where(badge)[0]:
        d = np.linalg.norm(centre[donors] - centre[f], axis=1) - 0.02 * (normal[donors] @ normal[f])
        nearest = donors[np.argmin(d)]
        zone[f], base[f] = zone[nearest], base[nearest]
    log(f"badge faces painted over: shield {shield.sum()}, SV letters {letters.sum()}, SV slash {slash.sum()}"
        f" at {[np.round(centre[letters & (np.sign(centre[:, 0]) == s)].mean(0), 2).tolist() for s in (-1, 1) if (letters & (np.sign(centre[:, 0]) == s)).any()]}")

    # Pattern coordinates (metres) for the two regular patterns: rim torus coords for the wheel,
    # one planar projection per island for carbon elsewhere.
    pst = np.zeros((len(uv), 2))
    lh, lrho, ltheta, lphi = wheel_coords(loop_pos, wheel)
    for f in np.where(on_rim & ((zone == PERFORATED) | (zone == CARBON)))[0]:
        s = slice(start[f], start[f] + total[f])
        th, ph = np.unwrap(ltheta[s]), np.unwrap(lphi[s])
        pst[s, 0], pst[s, 1] = th * R, ph * r
    for i in np.unique(island_of[(zone == CARBON) & ~on_rim]):
        fs = [f for f in islands[i] if zone[f] == CARBON]
        n = (normal[fs] * area[fs, None]).sum(0)
        n /= max(np.linalg.norm(n), 1e-9)
        along = np.array([0.0, 1.0, 0.0]) - n[1] * n
        along = along / np.linalg.norm(along) if np.linalg.norm(along) > 0.2 else np.cross(n, [1.0, 0.0, 0.0])
        across = np.cross(n, along)
        for f in fs:
            s = slice(start[f], start[f] + total[f])
            pst[s, 0], pst[s, 1] = loop_pos[s] @ along, loop_pos[s] @ across

    # Target densities, in texels per metre at SIZE.
    facing = np.zeros(faces, bool)
    for eye in EYES:
        facing |= ((np.array(eye) - centre) * normal).sum(1) > 0
    near = np.linalg.norm(centre - np.array(DRIVER_EYE), axis=1) < 0.85
    weight = np.where(facing, np.where(near, 1.6, 1.0), 0.45)
    weight = np.where(zone == CARBON, 2.5, weight)
    weight = np.where(on_wheel, 3.0, weight)
    weight = np.where(centre[:, 1] < -1.25, 0.25, weight)  # frunk liner, outside the cabin
    scale_to_size = SIZE / 2048

    # Swatch islands that fold over themselves: harmless while every texel of a swatch had the
    # same colour, but with texels of their own they would bake two places into one texel. Those,
    # and islands with no UV area at all, are re-unwrapped with Smart UV Project; every other
    # island keeps the artist's unwrap. The layout is built from UVChannel_1 from here on.
    folded = [i for i in np.where(swatch_isl)[0] if self_overlaps(uv, start, total, islands[i])]
    no_area = [i for i in range(len(islands)) if isl_uv_area[i] < 1e-14]
    redo = [f for i in folded + no_area for f in islands[i]]
    if redo:
        me.uv_layers.active = me.uv_layers[NEW_UV]
        edit_alone(obj)
        bpy.context.scene.tool_settings.use_uv_select_sync = True
        bm = bmesh.from_edit_mesh(me)
        bm.faces.ensure_lookup_table()
        for f in bm.faces:
            f.select_set(False)
        for f in redo:
            bm.faces[f].select_set(True)
        bmesh.update_edit_mesh(me)
        bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.0, area_weight=0.0, scale_to_bounds=False)
        bpy.ops.object.mode_set(mode="OBJECT")
    log(f"re-unwrapped {len(folded)} folded swatch islands and {len(no_area)} with no UV area ({len(redo)} faces)")
    uv = loop_arrays(obj, NEW_UV)[0]
    bm = bmesh.new()
    bm.from_mesh(me)
    islands = [[f.index for f in isl] for isl in bmesh_utils.bmesh_linked_uv_islands(bm, bm.loops.layers.uv[NEW_UV])]
    bm.free()
    for i, isl in enumerate(islands):
        island_of[isl] = i
    tri_uv_area = face_uv_area(uv, start, total)
    isl_area = np.bincount(island_of, weights=area)
    isl_uv_area = np.bincount(island_of, weights=tri_uv_area)
    face_uv = np.array([uv[s:s + t].mean(0) for s, t in zip(start, total)])
    isl_uv = np.c_[np.bincount(island_of, weights=face_uv[:, 0] * area), np.bincount(island_of, weights=face_uv[:, 1] * area)] / np.maximum(isl_area, 1e-12)[:, None]
    swatch_isl = np.bincount(island_of, weights=swatch.astype(float), minlength=len(islands)) > 0
    isl_weight = np.sqrt(np.bincount(island_of, weights=area * weight**2) / np.maximum(isl_area, 1e-12))

    # Which islands need texels of their own. Zone islands do (object-space detail differs
    # everywhere), and so do decal islands that cannot keep the old atlas geometry: tiled or
    # stretched strips (stitching, piping), islands holding painted-over badge faces, and islands
    # with no UV area. The rest of the decals (buttons, glyphs, vents) stay as one rigid block in
    # their old atlas arrangement at 1.5x their old texel density, so copies that shared texels
    # still share them instead of each paying for its own.
    old_extent = np.array([np.ptp(uv[np.concatenate([np.arange(start[f], start[f] + total[f]) for f in isl])], axis=0) for isl in islands])
    inside = np.all((isl_uv >= 0) & (isl_uv <= 1), axis=1)
    elongated = old_extent.max(1) / np.maximum(old_extent.min(1), 1e-9) > 6
    has_badge = np.bincount(island_of, weights=badge.astype(float), minlength=len(islands)) > 0
    degenerate_isl = (isl_uv_area < 1e-14) | (isl_area < 1e-10)
    isl_length = np.array([np.ptp(centre[isl], axis=0).max() for isl in islands])
    # Long strips (stitching, piping along a seat edge) would cost thousands of texels in length at
    # the decal density; they get 2.5x the surface around them, up to 1100 texels/m (a 5 mm stitch
    # then still spans five texels).
    strip = ~inside | (old_extent.max(1) > 0.5) | (elongated & (isl_length > 0.25))
    unique = swatch_isl | has_badge | degenerate_isl | strip
    unique_face = unique[island_of]
    shared_faces = np.where(~unique_face)[0]

    def targets(base_density):
        t = base_density * isl_weight
        return np.where(strip & ~swatch_isl, np.minimum(2.5 * t, 1100.0 * scale_to_size), t)

    # Pack units: the shared-decal block, every unique island, and every face of a degenerate
    # island on its own (projected on its plane), each as texel coordinates around its centre.
    shared_loops = np.concatenate([np.arange(start[f], start[f] + total[f]) for f in shared_faces])
    units = [{"faces": shared_faces, "loops": shared_loops, "fixed": uv[shared_loops] * DECAL_GAIN * 512 * scale_to_size, "rotate": False}]
    for i in np.where(unique)[0]:
        if degenerate_isl[i]:
            for f in islands[i]:
                s = slice(start[f], start[f] + total[f])
                p = loop_pos[s] - loop_pos[s].mean(0)
                ax = p[1] - p[0]
                ax = ax / np.linalg.norm(ax) if np.linalg.norm(ax) > 1e-9 else np.array([1.0, 0.0, 0.0])
                units.append({"faces": [f], "loops": np.arange(start[f], start[f] + total[f]), "metres": np.c_[p @ ax, p @ np.cross(normal[f], ax)], "island": i})
            continue
        loops = np.concatenate([np.arange(start[f], start[f] + total[f]) for f in islands[i]])
        metres = (uv[loops] - uv[loops].mean(0)) / math.sqrt(isl_uv_area[i] / isl_area[i])
        units.append({"faces": islands[i], "loops": loops, "metres": metres, "island": i})
    loop_index = np.full(len(uv), -1)
    for u in units:
        loop_index[u["loops"]] = np.arange(len(u["loops"]))
    for u in units:  # triangles as indices into the unit's own loop list
        u["tris"] = np.array([(loop_index[start[f]], loop_index[start[f] + k], loop_index[start[f] + k + 1])
                              for f in u["faces"] for k in range(1, total[f] - 1)], dtype=np.int64).reshape(-1, 3)
        if "metres" in u:
            m = u["metres"] - u["metres"].mean(0)
            evals, evecs = np.linalg.eigh(np.cov(m.T) if len(m) > 2 else np.eye(2))
            u["metres"] = m @ evecs[:, ::-1]  # longest axis along u

    def attempt(base_density):
        target = targets(base_density)
        for u in units:
            if "fixed" in u:
                u["texels"] = [u["fixed"]]
                continue
            t = u["metres"] * target[u["island"]]
            t *= min(1.0, MAX_ISLAND_EXTENT * SIZE / max(np.ptp(t, axis=0).max(), 1e-9))
            u["texels"] = [t, np.c_[-t[:, 1], t[:, 0]]]
        return raster_pack(units, SIZE, len(uv))

    lo, hi = 50.0, 2000.0
    best = None
    t0 = time.time()
    for _ in range(9):
        mid = math.sqrt(lo * hi)
        placed = attempt(mid)
        if placed is not None:
            lo, best = mid, (mid, placed)
        else:
            hi = mid
    if best is None:
        raise RuntimeError("nothing packed")
    base_density, packed = best
    me.uv_layers[NEW_UV].data.foreach_set("uv", packed.ravel().astype(np.float32))
    new_area = face_uv_area(packed, start, total)
    density = np.sqrt(new_area / np.maximum(area, 1e-12)) * SIZE
    fill = union_area(packed, start, total, range(faces), 1024)
    overlap = overlap_texels(packed, start, total, unique_face, 1024)
    log(f"packed {len(units)} units in {time.time() - t0:.0f} s: base {base_density:.0f} texels/m, fill {fill:.1%}, "
        f"{overlap} texels at 1024 where a face that owns its texels overlaps another face")
    write_layout_image(OUT / "work" / "uv_layout.png", packed, start, total, zone, 1024)
    report = {"size": SIZE, "fill": fill, "base_density": base_density, "wheel": {k: (v.tolist() if hasattr(v, "tolist") else v) for k, v in wheel.items()}, "zones": {}}
    for zid, name in enumerate(ZONE_NAMES):
        sel = zone == zid
        if sel.any():
            report["zones"][name] = {"area_m2": round(float(area[sel].sum()), 3), "faces": int(sel.sum()),
                                     "texels_per_m_median": round(float(np.median(density[sel])), 1)}
    for label, sel in (("wheel", on_wheel), ("near driver", near & facing & ~on_wheel), ("turned away", ~facing), ("frunk", centre[:, 1] < -1.25)):
        report.setdefault("regions", {})[label] = round(float(np.median(density[sel])), 1)
    # Render targets: the centre stack's button panels (decal faces on the centreline between the
    # seats and the dash) and the bolsters the SV emblems were removed from.
    console = (zone == DECAL) & (np.abs(centre[:, 0]) < 0.18) & (centre[:, 1] > -1.0) & (centre[:, 1] < -0.3) & (centre[:, 2] > 0.25) & (centre[:, 2] < 0.7)
    report["console_centre"] = ((centre[console] * area[console, None]).sum(0) / area[console].sum()).tolist() if console.any() else [0.0, -0.7, 0.45]
    report["badge_centres"] = [c for c in removed_badges if abs(c[0]) > 0.45]
    LAYOUT_JSON.write_text(json.dumps(report, indent=1))
    log("zones", json.dumps(report["zones"]), "regions (median texels/m)", report["regions"])

    # Zone attributes for the bake.
    for name in ("zone", "base_colour", "pst", "shared"):
        if name in me.attributes:
            me.attributes.remove(me.attributes[name])
    me.attributes.new("zone", "FLOAT", "FACE").data.foreach_set("value", zone.astype(np.float32))
    me.attributes.new("shared", "FLOAT", "FACE").data.foreach_set("value", (~unique_face).astype(np.float32))
    me.attributes.new("base_colour", "FLOAT_COLOR", "FACE").data.foreach_set("color", np.c_[base, np.ones(faces)].ravel().astype(np.float32))
    me.attributes.new("pst", "FLOAT2", "CORNER").data.foreach_set("vector", pst.ravel().astype(np.float32))
    me.uv_layers.active = me.uv_layers[NEW_UV]
    me.uv_layers[NEW_UV].active_render = True
    changed = [name for name, value in mesh_fingerprint(OBJECT).items() if others_before.get(name) != value]
    if changed:
        raise RuntimeError(f"the layout stage changed other meshes: {changed}")
    log(f"checked: the other {len(others_before)} meshes are unchanged (face counts and UVs)")
    bpy.ops.wm.save_as_mainfile(filepath=str(V2_BLEND), relative_remap=True)
    log("saved", V2_BLEND, f"peak memory {peak_memory_mb():.0f} MB")


# ---------------------------------------------------------------------------------------------
# Stage 2: bake.

class Graph:
    """Thin builder for shader node graphs: numbers and sockets are interchangeable inputs."""

    def __init__(self, tree):
        self.tree = tree

    def node(self, kind, inputs=None, **props):
        n = self.tree.nodes.new(kind)
        for key, value in props.items():
            setattr(n, key, value)
        for key, value in (inputs or {}).items():
            socket = next(s for s in n.inputs if s.name == key and s.enabled) if isinstance(key, str) else n.inputs[key]
            self.feed(socket, value)
        return n

    def feed(self, socket, value):
        if isinstance(value, bpy.types.NodeSocket):
            self.tree.links.new(value, socket)
        else:
            socket.default_value = value

    def out(self, n, name=None):
        return next(s for s in n.outputs if s.enabled and (name is None or s.name == name))

    def math(self, op, a, b=0.0, c=None, clamp=False):
        inputs = {0: a, 1: b}
        if c is not None:
            inputs[2] = c
        return self.out(self.node("ShaderNodeMath", inputs, operation=op, use_clamp=clamp))

    def add(self, *terms):
        total = terms[0]
        for t in terms[1:]:
            total = self.math("ADD", total, t)
        return total

    def mul(self, a, b):
        return self.math("MULTIPLY", a, b)

    def lerp(self, a, b, t):
        return self.math("ADD", a, self.mul(self.math("SUBTRACT", b, a), t))

    def vec(self, op, a, b=None):
        inputs = {0: a} if b is None else {0: a, 1: b}
        return self.out(self.node("ShaderNodeVectorMath", inputs, operation=op), "Vector")

    def vlerp(self, a, b, t):
        return self.vec("ADD", a, self.vec("MULTIPLY", self.vec("SUBTRACT", b, a), self.out(self.node("ShaderNodeCombineXYZ", {0: t, 1: t, 2: t}))))

    def vscale(self, a, s):
        return self.vec("MULTIPLY", a, self.out(self.node("ShaderNodeCombineXYZ", {0: s, 1: s, 2: s})))

    def smooth(self, value, lo, hi):
        return self.out(self.node("ShaderNodeMapRange", {"Value": value, "From Min": lo, "From Max": hi}, interpolation_type="SMOOTHSTEP"))

    def noise(self, coord, feature_m, detail=2.0, roughness=0.5):
        return self.out(self.node("ShaderNodeTexNoise", {"Vector": coord, "Scale": 1.0 / feature_m, "Detail": detail, "Roughness": roughness}), "Factor")

    def voronoi(self, coord, cell_m, feature="F1", output="Distance"):
        return self.out(self.node("ShaderNodeTexVoronoi", {"Vector": coord, "Scale": 1.0 / cell_m}, feature=feature), output)

    def image(self, path, uv_name, data, interpolation="Linear"):
        img = bpy.data.images.load(str(path), check_existing=True)
        img.colorspace_settings.name = "Non-Color" if data else "sRGB"
        uvmap = self.node("ShaderNodeUVMap", uv_map=uv_name)
        return self.node("ShaderNodeTexImage", {"Vector": self.out(uvmap)}, image=img, interpolation=interpolation, extension="REPEAT")


def build_bake_material(ao_image):
    """One material whose outputs are switched per pass. Returns (material, outputs, target node)."""
    mat = bpy.data.materials.new("InteriorDetailBake")
    tree = mat.node_tree
    tree.nodes.clear()
    g = Graph(tree)
    obj_coord = g.out(g.node("ShaderNodeTexCoord"), "Object")

    zone = g.out(g.node("ShaderNodeAttribute", attribute_name="zone", attribute_type="GEOMETRY"), "Factor")
    base = g.out(g.node("ShaderNodeAttribute", attribute_name="base_colour", attribute_type="GEOMETRY"), "Color")
    pst = g.out(g.node("ShaderNodeAttribute", attribute_name="pst", attribute_type="GEOMETRY"), "Vector")
    shared = g.out(g.node("ShaderNodeAttribute", attribute_name="shared", attribute_type="GEOMETRY"), "Factor")
    z = {k: g.math("COMPARE", zone, float(k), 0.5) for k in range(9)}
    is_zone = g.math("SUBTRACT", 1.0, z[DECAL])

    atlas_colour = g.out(g.image(UPSCALED, OLD_UV, data=False), "Color")
    atlas_normal_rgb = g.out(g.image(TEXTURES / f"{PREFIX}Normal.png", OLD_UV, data=True), "Color")
    if FLIP_SOURCE_GREEN:
        sep = g.node("ShaderNodeSeparateColor", {"Color": atlas_normal_rgb})
        atlas_normal_rgb = g.out(g.node("ShaderNodeCombineColor", {"Red": g.out(sep, "Red"), "Green": g.math("SUBTRACT", 1.0, g.out(sep, "Green")), "Blue": g.out(sep, "Blue")}))
    atlas_normal = g.out(g.node("ShaderNodeNormalMap", {"Color": atlas_normal_rgb}, space="TANGENT", uv_map=OLD_UV))
    mask = g.node("ShaderNodeSeparateColor", {"Color": g.out(g.image(TEXTURES / f"{PREFIX}MaterialOpacity.png", OLD_UV, data=True), "Color")})
    emissive = g.out(g.image(TEXTURES / f"{PREFIX}Emissive.png", EMISSIVE_UV, data=False), "Color")
    em = g.node("ShaderNodeSeparateColor", {"Color": emissive})
    glow = g.smooth(g.math("MAXIMUM", g.math("MAXIMUM", g.out(em, "Red"), g.out(em, "Green")), g.out(em, "Blue")), 0.06, 0.2)
    ao = g.out(g.node("ShaderNodeTexImage", {"Vector": g.out(g.node("ShaderNodeUVMap", uv_map=NEW_UV))}, image=ao_image), "Color") if ao_image else None

    # --- Per-zone micro-structure. Heights in metres; colour factors around 1. ------------------
    # Suede: soft fibre grain (3 mm) and nap mottling (2.5 cm), no structure, no highlight.
    suede_fine = g.noise(obj_coord, 0.003, detail=4, roughness=0.65)
    suede_mottle = g.noise(obj_coord, 0.025, detail=3, roughness=0.55)
    suede_nap = g.noise(obj_coord, 0.008, detail=3, roughness=0.6)  # survives 3-4 mm texels
    suede_h = g.mul(g.add(g.math("SUBTRACT", suede_fine, 0.5), g.mul(g.math("SUBTRACT", suede_nap, 0.5), 0.8),
                          g.mul(g.math("SUBTRACT", suede_mottle, 0.5), 0.3)), 0.00012)
    suede_col = g.add(1.0, g.mul(g.math("SUBTRACT", suede_mottle, 0.5), 0.24), g.mul(g.math("SUBTRACT", suede_nap, 0.5), 0.14),
                      g.mul(g.math("SUBTRACT", suede_fine, 0.5), 0.10))
    suede_rough = g.add(g.mul(g.math("SUBTRACT", suede_mottle, 0.5), 0.08), g.mul(g.math("SUBTRACT", suede_nap, 0.5), 0.05))
    # Leather: pebble grain, 1.8 mm cells with soft grooves.
    grain_edge = g.voronoi(obj_coord, 0.0018, feature="DISTANCE_TO_EDGE")
    pebble = g.smooth(grain_edge, 0.0, 0.18)
    leather_h = g.mul(g.add(pebble, g.mul(g.noise(obj_coord, 0.006), 0.4)), 0.00006)
    leather_col = g.add(0.9, g.mul(pebble, 0.12))
    leather_rough = g.mul(g.math("SUBTRACT", 1.0, pebble), 0.08)
    # Perforation: staggered holes, 1.3 mm across on a 4 mm pitch, in rim torus coordinates.
    pitch = 0.004
    pst_sep = g.node("ShaderNodeSeparateXYZ", {0: pst})
    ps, pt = g.math("DIVIDE", g.out(pst_sep, "X"), pitch), g.math("DIVIDE", g.out(pst_sep, "Y"), pitch)
    row = g.math("FLOOR", pt)
    ps = g.add(ps, g.mul(g.math("FLOORED_MODULO", row, 2.0), 0.5))
    dx, dy = g.math("SUBTRACT", g.math("FRACT", ps), 0.5), g.math("SUBTRACT", g.math("FRACT", pt), 0.5)
    hole_d = g.mul(g.math("SQRT", g.add(g.mul(dx, dx), g.mul(dy, dy))), pitch)
    hole = g.math("SUBTRACT", 1.0, g.smooth(hole_d, 0.00045, 0.00068))
    perf_h = g.add(leather_h, g.mul(hole, -0.0003))
    perf_col = g.mul(g.mul(leather_col, 1.8), g.math("SUBTRACT", 1.0, g.mul(hole, 0.8)))  # grips read lighter than the suede (R01)
    perf_rough = g.add(leather_rough, g.mul(hole, 0.3))
    # Carbon: 2x2 twill of 3 mm tows; each tow bulges across its width; warp and weft tows take
    # different tones (the anisotropic sheen real carbon shows), under a smooth clear coat.
    tow = 0.003
    ca, cb = g.math("DIVIDE", g.out(pst_sep, "X"), tow), g.math("DIVIDE", g.out(pst_sep, "Y"), tow)
    warp = g.math("LESS_THAN", g.math("FLOORED_MODULO", g.add(g.math("FLOOR", ca), g.math("FLOOR", cb)), 4.0), 2.0)
    across = g.lerp(g.math("FRACT", cb), g.math("FRACT", ca), warp)
    along = g.lerp(g.math("FRACT", ca), g.math("FRACT", cb), warp)
    bulge = g.math("SINE", g.mul(across, math.pi))
    fibres = g.noise(g.out(g.node("ShaderNodeCombineXYZ", {0: g.lerp(ca, g.mul(ca, 30.0), warp), 1: g.lerp(g.mul(cb, 30.0), cb, warp), 2: 0.0})), 1.0, detail=1)
    carbon_h = g.mul(g.add(g.math("POWER", bulge, 0.6), g.mul(g.math("SINE", g.mul(along, math.pi)), 0.15)), 0.00004)
    carbon_col = g.mul(g.add(g.lerp(0.75, 1.7, warp), g.mul(g.math("SUBTRACT", fibres, 0.5), 0.5)), g.add(0.75, g.mul(bulge, 0.35)))
    # Satin plastic: fine orange peel.
    peel = g.noise(obj_coord, 0.0025, detail=2)
    satin_h = g.mul(g.math("SUBTRACT", peel, 0.5), 0.00002)
    satin_col = g.add(1.0, g.mul(g.math("SUBTRACT", g.noise(obj_coord, 0.04), 0.5), 0.05))
    satin_rough = g.mul(g.math("SUBTRACT", peel, 0.5), 0.06)
    # Carpet: coarse loops.
    loops = g.voronoi(obj_coord, 0.0025)
    carpet_h = g.mul(g.add(loops, g.mul(g.noise(obj_coord, 0.002, detail=3), 0.6)), 0.0002)
    carpet_col = g.add(0.85, g.mul(loops, 0.25))
    # Metal: faint brushing noise.
    metal_n = g.noise(obj_coord, 0.004)
    metal_col = g.add(0.96, g.mul(metal_n, 0.08))
    metal_rough = g.mul(g.math("SUBTRACT", metal_n, 0.5), 0.08)

    def by_zone(table, default=0.0):
        terms = [g.mul(z[k], v) for k, v in table.items()]
        return g.add(*terms) if terms else default

    height = by_zone({SUEDE: suede_h, RED_SUEDE: suede_h, LEATHER: leather_h, PERFORATED: perf_h, CARBON: carbon_h, SATIN: satin_h, CARPET: carpet_h})
    variation = by_zone({SUEDE: suede_col, RED_SUEDE: g.add(0.4, g.mul(suede_col, 0.6)), LEATHER: leather_col, PERFORATED: perf_col,
                         CARBON: carbon_col, SATIN: satin_col, CARPET: carpet_col, METAL: metal_col, DECAL: 1.0})
    variation = g.lerp(variation, 1.0, glow)

    # --- Pass outputs. --------------------------------------------------------------------------
    zone_colour = g.vscale(base, variation)
    colour = g.vlerp(atlas_colour, zone_colour, is_zone)
    metalness = g.lerp(g.smooth(g.out(mask, "Red"), 0.45, 0.65), z[METAL], is_zone)
    # The source is a diffuse + specular set: its metal texels carry a dark "diffuse" (the knob caps
    # are 0.04 linear), which as a metal base colour is black chrome and rendered the knobs as
    # holes. Metal texels get a plausible reflectance instead: 0.25 + 1.6 x atlas, 0.25 to 0.9.
    metal_colour = g.vec("MINIMUM", g.vec("MAXIMUM", g.vec("ADD", g.vscale(colour, 1.6), (0.25, 0.25, 0.25)), (0.25, 0.25, 0.25)), (0.9, 0.9, 0.9))
    colour = g.vlerp(colour, metal_colour, metalness)
    if ao is not None:
        # Shared decal texels get no AO: several copies bake into them and the last one wins, so an
        # occluded copy blackened a visible knob cap. The atlas colour already carries their AO.
        ao_strength = g.mul(g.mul(g.lerp(0.45, 0.9, is_zone), g.math("SUBTRACT", 1.0, glow)), g.math("SUBTRACT", 1.0, shared))
        colour = g.vscale(colour, g.lerp(1.0, g.out(g.node("ShaderNodeSeparateColor", {"Color": ao}), "Red"), ao_strength))
    # Roblox lights a SurfaceAppearance as ColorMap x EmissiveMask, so glowing texels carry their
    # glow colour in the colour map (the hero_car_maps.py convention).
    colour = g.vec("MAXIMUM", colour, emissive)
    gloss = g.out(mask, "Green")
    decal_rough = g.math("MAXIMUM", g.math("MINIMUM", g.math("SUBTRACT", 1.0, g.math("POWER", gloss, 0.8)), 0.95), 0.06)
    zone_rough = by_zone({k: g.add(v, extra) for k, v, extra in (
        (SUEDE, ROUGHNESS[SUEDE], suede_rough), (RED_SUEDE, ROUGHNESS[RED_SUEDE], suede_rough), (LEATHER, ROUGHNESS[LEATHER], leather_rough),
        (PERFORATED, ROUGHNESS[PERFORATED], perf_rough), (CARBON, ROUGHNESS[CARBON], 0.0), (SATIN, ROUGHNESS[SATIN], satin_rough),
        (CARPET, ROUGHNESS[CARPET], 0.0), (METAL, ROUGHNESS[METAL], metal_rough))})
    roughness = g.math("MINIMUM", g.math("MAXIMUM", g.lerp(decal_rough, zone_rough, is_zone), 0.04), 1.0)
    roughness = g.lerp(roughness, g.math("MAXIMUM", roughness, 0.25), metalness)  # metal ~0.3, not a mirror
    geometric = g.out(g.node("ShaderNodeNewGeometry"), "Normal")
    normal_in = g.vec("NORMALIZE", g.vlerp(atlas_normal, geometric, is_zone))
    bumped = g.out(g.node("ShaderNodeBump", {"Strength": 1.0, "Distance": 1.0, "Height": height, "Normal": normal_in}))
    diffuse = g.node("ShaderNodeBsdfDiffuse", {"Color": (0.5, 0.5, 0.5, 1.0), "Normal": bumped})
    plain = g.node("ShaderNodeBsdfDiffuse", {"Color": (0.8, 0.8, 0.8, 1.0)})
    emission = g.node("ShaderNodeEmission", {"Strength": 1.0})
    output = g.node("ShaderNodeOutputMaterial")
    target = g.node("ShaderNodeTexImage")
    tree.nodes.active = target

    def colour_socket(value):
        return value if value.type in ("RGBA", "VECTOR") else g.out(g.node("ShaderNodeCombineXYZ", {0: value, 1: value, 2: value}))

    sources = {"colour": colour, "roughness": roughness, "metalness": metalness, "emissive": emissive}

    def route(pass_name):
        for link in list(output.inputs["Surface"].links):
            tree.links.remove(link)
        if pass_name == "normal":
            g.feed(output.inputs["Surface"], g.out(diffuse))
        elif pass_name == "ao":
            g.feed(output.inputs["Surface"], g.out(plain))
        else:
            for link in list(emission.inputs["Color"].links):
                tree.links.remove(link)
            g.feed(emission.inputs["Color"], colour_socket(sources[pass_name]))
            g.feed(output.inputs["Surface"], g.out(emission))

    return mat, route, target


def bake_pass(obj, route, target, pass_name, kind, samples, fill):
    image = bpy.data.images.new(f"bake_{pass_name}", SIZE, SIZE, alpha=True, float_buffer=True)
    image.colorspace_settings.is_data = True
    image.generated_color = (*fill, 1.0)
    target.image = image
    route(pass_name)
    bpy.context.scene.cycles.samples = samples
    t0 = time.time()
    bpy.ops.object.bake(type=kind, margin=max(4, SIZE // 256), margin_type="ADJACENT_FACES", use_clear=False,
                        normal_space="TANGENT", uv_layer=NEW_UV, target="IMAGE_TEXTURES")
    pixels = np.empty(SIZE * SIZE * 4, np.float32)
    image.pixels.foreach_get(pixels)
    log(f"baked {pass_name} ({kind}, {samples} spp) in {time.time() - t0:.0f} s, peak memory {peak_memory_mb():.0f} MB")
    return image, pixels.reshape(SIZE, SIZE, 4)


def stage_bake():
    bpy.ops.wm.open_mainfile(filepath=str(V2_BLEND))
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.use_denoising = False
    scene.render.bake.use_pass_direct = False
    for o in bpy.data.objects:
        if o.name.startswith("Window"):
            o.hide_render = True  # glass would occlude the AO
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.light_settings.distance = 0.12
    obj = bpy.data.objects[OBJECT]
    me = obj.data
    me.uv_layers.active = me.uv_layers[NEW_UV]
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    mat, route, target = build_bake_material(None)
    me.materials.clear()
    me.materials.append(mat)
    ao_image, ao = bake_pass(obj, route, target, "ao", "AO", 48, (1, 1, 1))

    mat, route, target = build_bake_material(ao_image)
    me.materials.clear()
    me.materials.append(mat)
    _, normal = bake_pass(obj, route, target, "normal", "NORMAL", 16, (0.5, 0.5, 1.0))
    _, colour = bake_pass(obj, route, target, "colour", "EMIT", 16, (0.02, 0.02, 0.02))
    _, rough = bake_pass(obj, route, target, "roughness", "EMIT", 16, (0.8, 0.8, 0.8))
    _, metal = bake_pass(obj, route, target, "metalness", "EMIT", 8, (0, 0, 0))
    _, glow = bake_pass(obj, route, target, "emissive", "EMIT", 8, (0, 0, 0))

    opaque = np.ones((SIZE, SIZE, 1))
    write_png(OUT / "interior_color.png", np.concatenate([to_srgb(colour[..., :3]), opaque], axis=2))
    write_png(OUT / "interior_normal.png", np.clip(normal[..., :3], 0, 1))
    write_png(OUT / "interior_roughness.png", np.clip(rough[..., 0], 0, 1))
    write_png(OUT / "interior_metalness.png", np.clip(metal[..., 0], 0, 1))
    write_png(OUT / "interior_emissive.png", to_srgb(glow[..., :3]))
    (OUT / "work").mkdir(exist_ok=True)
    write_png(OUT / "work" / "ao.png", np.clip(ao[..., 0], 0, 1))
    log("wrote maps to", OUT)

    # Leave the v2 car with a Principled material on the new maps (what Roblox will get).
    me.materials.clear()
    me.materials.append(principled_material("InteriorDetail", OUT / "interior_color.png", OUT / "interior_normal.png",
                                            OUT / "interior_roughness.png", OUT / "interior_metalness.png",
                                            OUT / "interior_emissive.png", NEW_UV))
    for o in bpy.data.objects:
        if o.name.startswith("Window"):
            o.hide_render = False
    bpy.ops.wm.save_as_mainfile(filepath=str(V2_BLEND), relative_remap=True)
    log("saved", V2_BLEND)


def principled_material(name, colour, normal, roughness, metalness, emissive, uv_name, uniform_roughness=None, flip_green=False):
    """Roblox's SurfaceAppearance as a Principled BSDF: colour, normal, roughness, metalness maps,
    emission = colour x emissive mask (Roblox's EmissiveMask), F0 0.04, no coat, no sheen."""
    mat = bpy.data.materials.new(name)
    tree = mat.node_tree
    tree.nodes.clear()
    g = Graph(tree)
    bsdf = g.node("ShaderNodeBsdfPrincipled")
    col = g.out(g.image(colour, uv_name, data=False), "Color")
    g.feed(bsdf.inputs["Base Color"], col)
    nrgb = g.out(g.image(normal, uv_name, data=True), "Color")
    if flip_green:
        sep = g.node("ShaderNodeSeparateColor", {"Color": nrgb})
        nrgb = g.out(g.node("ShaderNodeCombineColor", {"Red": g.out(sep, "Red"), "Green": g.math("SUBTRACT", 1.0, g.out(sep, "Green")), "Blue": g.out(sep, "Blue")}))
    g.feed(bsdf.inputs["Normal"], g.out(g.node("ShaderNodeNormalMap", {"Color": nrgb}, space="TANGENT", uv_map=uv_name)))
    if uniform_roughness is None:
        g.feed(bsdf.inputs["Roughness"], g.out(g.node("ShaderNodeSeparateColor", {"Color": g.out(g.image(roughness, uv_name, data=True), "Color")}), "Red"))
        g.feed(bsdf.inputs["Metallic"], g.out(g.node("ShaderNodeSeparateColor", {"Color": g.out(g.image(metalness, uv_name, data=True), "Color")}), "Red"))
    else:
        g.feed(bsdf.inputs["Roughness"], uniform_roughness)
        g.feed(bsdf.inputs["Metallic"], 0.0)
    if emissive:
        glow = g.out(g.image(emissive, uv_name, data=False), "Color")
        sep = g.node("ShaderNodeSeparateColor", {"Color": glow})
        level = g.math("MAXIMUM", g.math("MAXIMUM", g.out(sep, "Red"), g.out(sep, "Green")), g.out(sep, "Blue"))
        g.feed(bsdf.inputs["Emission Color"], g.vscale(col, level))
        g.feed(bsdf.inputs["Emission Strength"], 3.0)
    g.feed(g.node("ShaderNodeOutputMaterial").inputs["Surface"], g.out(bsdf))
    return mat


# ---------------------------------------------------------------------------------------------
# Stage 3: verification renders.

def look(cam, position, target):
    cam.location = Vector(position)
    cam.rotation_euler = (Vector(target) - Vector(position)).to_track_quat("-Z", "Y").to_euler()


def render_views(label, layout):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = int(option("--render-samples", 160))
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 6
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.exposure = float(option("--exposure", 0.6))
    for o in bpy.data.objects:
        if o.name.startswith("Window"):
            o.hide_render = True  # Roblox-side glass is a separate tinted part; here it only adds noise
    world = bpy.data.worlds.new("Sky")
    world.use_nodes = True
    scene.world = world
    tree = world.node_tree
    tree.nodes.clear()
    g = Graph(tree)
    up = g.out(g.node("ShaderNodeSeparateXYZ", {0: g.out(g.node("ShaderNodeTexCoord"), "Generated")}), "Z")
    ramp = g.node("ShaderNodeValToRGB", {0: g.smooth(up, -0.2, 0.6)})
    ramp.color_ramp.elements[0].color = (0.18, 0.17, 0.16, 1)
    ramp.color_ramp.elements[1].color = (0.75, 0.85, 1.0, 1)
    bg = g.node("ShaderNodeBackground", {"Color": g.out(ramp, "Color"), "Strength": 1.4})
    g.feed(g.node("ShaderNodeOutputWorld").inputs["Surface"], g.out(bg))
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 3.5
    sun_data.angle = math.radians(1.5)
    sun = bpy.data.objects.new("Sun", sun_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler = Vector((0.35, 0.55, -0.75)).to_track_quat("-Z", "Y").to_euler()
    cam_data = bpy.data.cameras.new("Eye")
    cam = bpy.data.objects.new("Eye", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam_data.sensor_fit = "VERTICAL"
    cam_data.clip_start = 0.02

    wheel = layout["wheel"]
    wc, wup, wright, wax = (Vector(wheel[k]) for k in ("centre", "up", "right", "axis"))
    grip = wc - wright * wheel["R"]  # 9 o'clock from the driver's seat
    console = Vector(layout["console_centre"])
    views = {
        "driver": (DRIVER_EYE, DRIVER_EYE + Vector((0, -1, -0.21)), 70),
        "wheel": (grip + wax * 0.30 + wup * 0.10 + wright * 0.12, wc - wright * wheel["R"] * 0.55, 42),
        "console": (console + Vector((0.16, 0.32, 0.30)), console, 50),
    }
    for i, badge in enumerate(layout.get("badge_centres", [])[:1]):
        b = Vector(badge)
        views["seat_bolster"] = (b + Vector((-0.25 * math.copysign(1, b.x), -0.35, 0.10)), b, 40)
    out = OUT / "renders"
    out.mkdir(exist_ok=True)
    for name, (position, target, fov) in views.items():
        look(cam, position, target)
        cam_data.angle = math.radians(fov)
        scene.render.filepath = str(out / f"{label}_{name}.png")
        t0 = time.time()
        bpy.ops.render.render(write_still=True)
        log(f"rendered {label}_{name} in {time.time() - t0:.0f} s")


def stage_render():
    layout = json.loads(LAYOUT_JSON.read_text())
    if "before" in option("--render-which", "before,after"):
        bpy.ops.wm.open_mainfile(filepath=str(BLEND))
        obj = bpy.data.objects[OBJECT]
        before_colour = Path(option("--before-color", str(UPSCALED)))
        before_emissive = option("--before-emissive")
        obj.data.materials.clear()
        obj.data.materials.append(principled_material("InteriorBefore", before_colour, TEXTURES / f"{PREFIX}Normal.png", None, None,
                                                      Path(before_emissive) if before_emissive else None, NEW_UV,
                                                      uniform_roughness=float(option("--before-roughness", 0.7))))
        render_views("before", layout)
    if "after" in option("--render-which", "before,after"):
        bpy.ops.wm.open_mainfile(filepath=str(V2_BLEND))
        render_views("after", layout)


if "layout" in STAGES:
    stage_layout()
if "bake" in STAGES:
    stage_bake()
if "render" in STAGES:
    stage_render()
log("done", f"peak memory {peak_memory_mb():.0f} MB")
