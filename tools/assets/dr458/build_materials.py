"""DR458 material library: tiling 1024 px PBR sets at real-world scale for Roblox SurfaceAppearance.

    python -I build_materials.py <out dir>

Every set is four maps, the four SurfaceAppearance takes:
  <name>_color.png      sRGB colour (opaque)
  <name>_normal.png     tangent space, OpenGL convention (green = +V)
  <name>_roughness.png  linear
  <name>_metalness.png  linear
and a line in library.json with the tile's physical size, so a mesh's UVs are laid out at
`uv = metres / tile_m` and the pattern lands at its real size.

All noise is FFT-filtered white noise, so it is periodic over the tile; every regular feature
(tow, boss, hole) is an integer count per tile. The maps therefore tile without seams.
Heights are in millimetres and normals come from the real slope (height / pixel size).
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

N = 1024
RNG = np.random.default_rng(458)
YY, XX = np.mgrid[0:N, 0:N].astype(np.float64)
U = XX / N  # 0..1 across the tile, left to right
V = 1.0 - YY / N  # 0..1 bottom to top (image row 0 is the top of the tile)


def noise(sx: float, sy: float | None = None, seed: int | None = None) -> np.ndarray:
    """Periodic Gaussian-filtered noise, zero mean, unit std. sx, sy: sigma in pixels."""
    sy = sx if sy is None else sy
    rng = RNG if seed is None else np.random.default_rng(seed)
    a = rng.normal(size=(N, N))
    fy = np.fft.fftfreq(N)[:, None]
    fx = np.fft.rfftfreq(N)[None, :]
    g = np.exp(-2 * math.pi ** 2 * ((sx * fx) ** 2 + (sy * fy) ** 2))
    a = np.fft.irfft2(np.fft.rfft2(a) * g, s=(N, N))
    return a / max(a.std(), 1e-12)


def smoothstep(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def to_srgb8(lin: np.ndarray) -> np.ndarray:
    lin = np.clip(lin, 0, 1)
    s = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1 / 2.4) - 0.055)
    return np.clip(np.round(s * 255), 0, 255).astype(np.uint8)


def normal_from_height(h_mm: np.ndarray, px_mm: float) -> np.ndarray:
    """OpenGL tangent-space normal from a periodic height field in mm."""
    dhdu = (np.roll(h_mm, -1, axis=1) - np.roll(h_mm, 1, axis=1)) / (2 * px_mm)
    # Row index grows downward, V grows upward: dh/dV = -(dh/drow).
    dhdv = -(np.roll(h_mm, -1, axis=0) - np.roll(h_mm, 1, axis=0)) / (2 * px_mm)
    n = np.stack([-dhdu, -dhdv, np.ones_like(h_mm)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return np.clip(np.round((n * 0.5 + 0.5) * 255), 0, 255).astype(np.uint8)


def save_set(out: Path, name: str, color_lin: np.ndarray, h_mm: np.ndarray, rough: np.ndarray,
             metal: np.ndarray | float, tile_m: float, notes: dict) -> dict:
    d = out / name
    d.mkdir(parents=True, exist_ok=True)
    px_mm = tile_m * 1000 / N
    if color_lin.ndim == 2:
        color_lin = np.repeat(color_lin[..., None], 3, axis=-1)
    Image.fromarray(to_srgb8(color_lin), "RGB").save(d / f"{name}_color.png", optimize=True)
    nrm = normal_from_height(h_mm, px_mm)
    Image.fromarray(nrm, "RGB").save(d / f"{name}_normal.png", optimize=True)
    Image.fromarray(np.clip(np.round(np.clip(rough, 0, 1) * 255), 0, 255).astype(np.uint8), "L").save(
        d / f"{name}_roughness.png", optimize=True)
    m = np.full((N, N), float(metal)) if np.isscalar(metal) else metal
    Image.fromarray(np.clip(np.round(np.clip(m, 0, 1) * 255), 0, 255).astype(np.uint8), "L").save(
        d / f"{name}_metalness.png", optimize=True)
    # Seam check: the wrap-around step must look like an interior step.
    srgb = to_srgb8(color_lin).astype(np.float64).mean(-1)
    inner = max(np.abs(np.diff(srgb, axis=1)).mean(), np.abs(np.diff(srgb, axis=0)).mean())
    wrap = max(np.abs(srgb[:, 0] - srgb[:, -1]).mean(), np.abs(srgb[0, :] - srgb[-1, :]).mean())
    nxy = nrm[..., :2].astype(np.float64) / 127.5 - 1
    tilt = np.degrees(np.arcsin(np.clip(np.hypot(nxy[..., 0], nxy[..., 1]), 0, 1)))
    rec = {
        "name": name, "tile_m": tile_m, "px_per_mm": round(N / (tile_m * 1000), 3),
        "albedo_srgb_mean": [int(v) for v in to_srgb8(color_lin).reshape(-1, 3).mean(0)],
        "roughness_mean": round(float(np.mean(rough)), 3), "roughness_p5_p95":
            [round(float(np.percentile(rough, 5)), 3), round(float(np.percentile(rough, 95)), 3)],
        "metalness_mean": round(float(np.mean(m)), 3),
        "normal_tilt_deg_p50_p95": [round(float(np.percentile(tilt, 50)), 2),
                                    round(float(np.percentile(tilt, 95)), 2)],
        "seam_step_vs_interior": [round(float(wrap), 3), round(float(inner), 3)],
        **notes,
    }
    print(json.dumps(rec))
    return rec


# ---------------------------------------------------------------- materials

def alcantara(out: Path, worn: bool) -> dict:
    tile = 0.20
    fine = noise(0.55, seed=12)
    nap = noise(1.0, 4.0, seed=13)  # pile streaks laid along V (the brushing direction of the pile)
    nap2 = noise(0.7, 2.0, seed=14)
    mott = noise(28, seed=15) * 0.6 + noise(90, seed=16) * 0.4
    pills = (noise(0.8, seed=11) > 3.1).astype(float)  # sparse lighter fluff and dust specks
    base = 0.020
    col = base * (1 + 0.11 * mott + 0.045 * nap + 0.04 * nap2 + 0.05 * fine) + 0.03 * pills
    rough = 0.90 + 0.035 * nap + 0.02 * fine - 0.02 * mott
    h = 0.030 * fine + 0.022 * nap + 0.010 * nap2
    if worn:
        # Matting where hands and backs rub: flattened pile, a little darker and shinier,
        # with a lighter scuff fringe. Large blotches, so a bolster or rim gets a few per tile.
        wear = smoothstep(0.5, 1.9, noise(40, seed=21) * 0.7 + noise(10, seed=22) * 0.3)
        fringe = np.clip(smoothstep(0.2, 0.6, noise(40, seed=21)) - wear, 0, 1)
        col = col * (1 - 0.10 * wear) + 0.005 * fringe * (1 + 0.5 * fine)
        rough = rough - 0.18 * wear
        h = h * (1 - 0.65 * wear)
    return save_set(out, "alcantara_worn" if worn else "alcantara", col, h, rough, 0.0, tile, {
        "use": "dash top, lower dash, steering rim (worn), seat inserts",
        "basis": "dark anthracite microfibre; pile streaks along V, 3-40 mm mottling, sparse dust",
    })


def carbon_fields() -> tuple:
    """2x2 twill. Tow 2.5 mm (measured 2.2-2.7 mm on the switch panel, photo interior/013)."""
    tile = 0.16
    tows = 64                              # 64 x 2.5 mm = 160 mm, 4-tow repeat = 10 mm
    px = tile * 1000 / N
    warp_a = U * tows + 0.10 * noise(60, seed=31) + 0.04 * noise(12, seed=32)
    weft_b = V * tows + 0.10 * noise(60, seed=33) + 0.04 * noise(12, seed=34)
    # Slight waviness of the whole cloth: a few tenths of a tow over the tile.
    warp_a = warp_a + 0.25 * np.sin(2 * math.pi * (V * 2 + 0.3))
    weft_b = weft_b + 0.20 * np.sin(2 * math.pi * (U * 3 + 0.7))
    i = np.floor(warp_a).astype(int)
    j = np.floor(weft_b).astype(int)
    fa = warp_a - i
    fb = weft_b - j
    k = np.mod(i - j, 4)
    warp_over = k < 2
    across = np.where(warp_over, fa, fb)
    t_float = np.where(warp_over, (1 - k) + fb, (k - 2) + fa)        # 0..2 along the float
    along = np.where(warp_over, weft_b, warp_a)
    tow_id_warp = np.mod(i, tows)
    tow_id_weft = np.mod(j, tows)
    r_warp = np.random.default_rng(35).normal(0, 1, tows)
    r_weft = np.random.default_rng(36).normal(0, 1, tows)
    tow_rand = np.where(warp_over, r_warp[tow_id_warp], r_weft[tow_id_weft])
    phase = np.where(warp_over, tow_id_warp * 0.37, tow_id_weft * 0.61)
    crown = np.sin(math.pi * np.clip(across, 0.0, 1.0)) ** 0.6
    pillow = np.sin(math.pi * np.clip(t_float / 2, 0, 1)) ** 0.35
    # Filament striations run along the fibres: a few dozen per tow, irregular.
    stri = np.sin(2 * math.pi * (across * 9 + phase) + 0.8 * np.sin(2 * math.pi * along * 0.125 + phase))
    gap = 1 - smoothstep(0.0, 0.06, np.minimum(across, 1 - across))
    resin = smoothstep(0.6, 2.2, noise(40, seed=37))                # resin-rich patches, weave washes out
    # Kept low: a stronger tow relief breaks the clear coat's single highlight into blotches.
    h = (0.04 * crown * (0.55 + 0.45 * pillow) + 0.002 * stri) * (1 - 0.5 * resin) - 0.008 * gap
    dirf = np.where(warp_over, 0.93, 1.07)
    col = 0.020 * dirf * (1 + 0.07 * tow_rand + 0.10 * crown * pillow + 0.03 * stri) * (1 - 0.35 * gap)
    col = col * (1 + 0.05 * noise(80, seed=38))
    # Warp and weft differ in gloss, so the checker changes with the light's direction.
    gloss = np.where(warp_over, 0.10, 0.14) + 0.03 * (1 - crown) + 0.01 * noise(3, seed=39) + 0.02 * gap
    satin = np.where(warp_over, 0.33, 0.40) + 0.05 * (1 - crown) + 0.03 * noise(3, seed=40) + 0.03 * gap + 0.03 * noise(30, seed=41)
    return tile, col, h, gloss, satin


def carbon(out: Path) -> list[dict]:
    tile, col, h, gloss, satin = carbon_fields()
    out_g = save_set(out, "carbon_twill_gloss", col, h, gloss, 0.0, tile, {
        "use": "clear-coated cockpit carbon (door cards, centre tunnel)",
        "basis": "2x2 twill, tow 2.5 mm, float 5 mm, 4-tow repeat 10 mm; tow jitter, waviness, "
                 "per-tow tone, filament striations, resin-rich patches",
    })
    out_s = save_set(out, "carbon_twill_satin", col, h, satin, 0.0, tile, {
        "use": "satin carbon (switch panel, dash pods), same colour and normal as gloss",
        "basis": "as carbon_twill_gloss with a satin roughness map only",
    })
    # Same colour and normal maps serve both: only the roughness map differs.
    (out / "carbon_twill_satin" / "carbon_twill_satin_color.png").unlink()
    (out / "carbon_twill_satin" / "carbon_twill_satin_normal.png").unlink()
    return [out_g, out_s]


def brushed_aluminium(out: Path) -> dict:
    tile = 0.15
    # Brushed along U: the long sigma is on the U axis.
    streak = noise(260, 0.5, seed=51) * 0.6 + noise(90, 1.2, seed=52) * 0.4
    scratch = (noise(400, 0.4, seed=53) > 2.6).astype(float)
    blot = noise(60, seed=54)
    col = np.stack([0.80, 0.81, 0.82]) [None, None, :] * (1 + 0.035 * streak + 0.02 * blot)[..., None]
    rough = 0.30 + 0.06 * streak + 0.04 * blot + 0.10 * scratch
    h = 0.012 * streak + 0.015 * scratch
    return save_set(out, "aluminium_brushed", col, h, rough, 1.0, tile, {
        "use": "pedal faces, machined plates, steering quick release",
        "basis": "brushing along U; anisotropy faked with streaked roughness and grooves",
    })


def anodised_black(out: Path) -> dict:
    tile = 0.10
    fine = noise(0.6, seed=61)
    blast = noise(1.6, seed=62)
    blot = noise(45, seed=63)
    col = 0.045 * (1 + 0.05 * blast + 0.04 * blot)
    col = np.stack([col * 0.97, col * 0.98, col * 1.03], axis=-1)
    rough = 0.40 + 0.05 * blast + 0.03 * fine + 0.03 * blot
    h = 0.012 * blast + 0.004 * fine
    return save_set(out, "aluminium_anodised_black", col, h, rough, 1.0, tile, {
        "use": "harness adjusters, pedal box, steering hub, paddles; tint with SurfaceAppearance.Color "
               "only to darken (Color multiplies)",
        "basis": "bead-blasted black anodised aluminium, metal with dark colour",
    })


def carbon_gloss_worn(out: Path) -> dict:
    """The gloss twill where hands and knees rub: the clear coat hazed by fine swirls, the weave intact."""
    tile, col, h, gloss, _satin = carbon_fields()
    rub = smoothstep(-0.2, 1.6, noise(30, seed=91))                   # broad rubbed zones, about a third
    swirl = 0.5 + 0.5 * np.sin(2 * math.pi * (U * 7 + 0.3 * noise(8, seed=92)) + 3 * noise(4, seed=93))
    haze = rub * (0.6 + 0.4 * swirl)
    rough = gloss + 0.22 * haze
    col = col * (1 + 0.12 * haze)                                     # haze scatters a little light back
    return save_set(out, "carbon_twill_gloss_worn", col, h, rough, 0.0, tile, {
        "use": "clear-coated carbon on touched areas (tunnel cover, door-card tops)",
        "basis": "carbon_twill_gloss with the clear coat hazed in rubbed zones (roughness up to about 0.35)",
    })


def anodised_black_worn(out: Path) -> dict:
    """Anodising rubbed through to bare aluminium in small scuffs; the rest dulled a little."""
    tile = 0.10
    fine = noise(0.6, seed=61)
    blast = noise(1.6, seed=62)
    blot = noise(45, seed=63)
    scuff = smoothstep(1.2, 2.0, noise(6, seed=94) + 0.5 * noise(1.5, seed=95))   # a few per cent of the area
    base = 0.045 * (1 + 0.05 * blast + 0.04 * blot)
    col = np.stack([base * 0.97, base * 0.98, base * 1.03], axis=-1)
    bare = np.full_like(col, 0.55)
    col = col * (1 - scuff[..., None]) + bare * scuff[..., None]
    rough = 0.44 + 0.05 * blast + 0.03 * fine + 0.03 * blot - 0.14 * scuff
    h = 0.012 * blast + 0.004 * fine - 0.006 * scuff
    return save_set(out, "aluminium_anodised_black_worn", col, h, rough, 1.0, tile, {
        "use": "anodised parts at hand and boot contact (battery tray edges, pedal box)",
        "basis": "aluminium_anodised_black dulled, with scuffs through to bare aluminium",
    })


def rubber(out: Path) -> dict:
    tile = 0.10
    grain = noise(0.8, seed=71)
    abr = noise(120, 1.0, seed=72)          # abrasion streaks along U (rolling direction)
    blot = noise(50, seed=73)
    marbles = (noise(2.0, seed=74) > 2.7).astype(float)
    col = 0.024 * (1 + 0.08 * blot + 0.05 * abr + 0.04 * grain) + 0.010 * marbles
    rough = 0.84 + 0.04 * grain - 0.06 * smoothstep(0.5, 2.0, abr) + 0.04 * marbles
    h = 0.006 * grain + 0.004 * abr + 0.03 * marbles
    return save_set(out, "rubber", col, h, rough, 0.0, tile, {
        "use": "slick tread (rolling along U), seals, boots, pedal grips",
        "basis": "fine grain, directional abrasion, sparse pick-up specks",
    })


def treadplate_black(out: Path) -> dict:
    """The reference floor (photo interior/024): black diamond tread plate, dusty."""
    tile = 0.14
    pitch_n = 14                                  # 10 mm pitch
    g = U * pitch_n
    hgrid = V * pitch_n
    ci = np.floor(g)
    cj = np.floor(hgrid)
    lx = (g - ci - 0.5) * 10.0                    # mm from cell centre
    ly = (hgrid - cj - 0.5) * 10.0
    sign = np.where(np.mod(ci + cj, 2) == 0, 1.0, -1.0)
    c, s = math.cos(math.pi / 4), math.sin(math.pi / 4)
    rx = c * lx + sign * s * ly
    ry = -sign * s * lx + c * ly
    e = (rx / 4.0) ** 2 + (ry / 1.2) ** 2         # lens 8 x 2.4 mm
    boss = np.clip(1 - e, 0, 1) ** 0.5
    h = 0.8 * boss + 0.004 * noise(1.0, seed=81)
    top = smoothstep(0.55, 0.9, boss)
    # Every boss top is scuffed (paint thinned toward bare metal), by a varying amount, so the
    # grid reads evenly; heavy local wear such as the heel spot goes on a grime card instead.
    worn = top * (0.30 + 0.40 * smoothstep(-1.0, 1.5, noise(40, seed=83)))
    # Dust settles in a ring at each boss's base and, more lightly, over the flat.
    ring = np.exp(-((np.sqrt(e) - 1.2) / 0.25) ** 2) * (e > 0.9)
    flat = 1 - smoothstep(0.05, 0.4, boss)
    dust = np.clip(0.45 * ring + 0.40 * flat * smoothstep(-0.5, 2.0, noise(18, seed=84) * 0.6
                                                          + noise(4, seed=87) * 0.4), 0, 1)
    paint = 0.026 * (1 + 0.06 * noise(2, seed=85))
    col_paint = np.stack([paint, paint, paint * 1.04], -1)
    col_metal = np.stack([0.62, 0.63, 0.64])[None, None, :] * np.ones((N, N, 1))
    col_dust = np.stack([0.20, 0.19, 0.17])[None, None, :] * np.ones((N, N, 1))
    col = col_paint * (1 - worn[..., None]) + col_metal * worn[..., None]
    col = col * (1 - dust[..., None]) + col_dust * dust[..., None]
    metal = 0.8 * worn
    rough = 0.48 + 0.05 * noise(2, seed=86) - 0.15 * worn + 0.30 * dust
    return save_set(out, "treadplate_black", col, h, np.clip(rough, 0, 1), metal, tile, {
        "use": "cockpit floor under the driver and passenger (as in photo interior/024)",
        "basis": "black-painted diamond plate, 8x2.4 mm lenses on a 10 mm alternating grid, "
                 "every boss top scuffed toward bare aluminium, dust rings at the boss bases",
    })


def perforated_aluminium(out: Path) -> dict:
    tile = 0.10
    pitch_n = 10                                  # 10 mm square-staggered pitch, 6 mm holes
    a = U * pitch_n
    b = V * pitch_n

    def dist_to_hole(a_, b_):
        dx = (a_ - np.floor(a_) - 0.5) * 10.0
        dy = (b_ - np.floor(b_) - 0.5) * 10.0
        return np.sqrt(dx * dx + dy * dy)

    d = np.minimum(dist_to_hole(a, b), dist_to_hole(a + 0.5, b + 0.5))
    r = 3.0
    hole = 1 - smoothstep(r - 0.15, r + 0.05, d)
    chamfer = smoothstep(r - 0.1, r + 0.5, d) * (1 - smoothstep(r + 0.5, r + 0.9, d))
    streak = noise(200, 0.6, seed=91)
    h = -0.35 * hole + 0.15 * smoothstep(r, r + 0.6, d) + 0.012 * streak
    metal_col = np.stack([0.78, 0.79, 0.80])[None, None, :] * (1 + 0.03 * streak)[..., None]
    void = np.stack([0.012, 0.012, 0.013])[None, None, :] * np.ones((N, N, 1))
    col = metal_col * (1 - hole[..., None]) + void * hole[..., None]
    col = col * (1 - 0.15 * chamfer[..., None])
    rough = 0.32 + 0.05 * streak + 0.55 * hole + 0.08 * chamfer
    metal = 1 - hole
    return save_set(out, "aluminium_perforated", col, h, np.clip(rough, 0, 1), metal, tile, {
        "use": "heel plate and pedal faces (the briefed perforated floor plate)",
        "basis": "6 mm holes on a 10 mm square-staggered pitch, brushed along U; holes painted "
                 "dark, no transparency",
    })


def cage_paint(out: Path) -> dict:
    tile = 0.20
    peel = noise(7, seed=101) * 0.7 + noise(18, seed=102) * 0.3       # orange peel, 2-5 mm
    blot = noise(60, seed=103)
    scuff = (noise(300, 0.6, seed=104) > 2.9).astype(float) * smoothstep(0, 1.5, noise(40, seed=105))
    col = 0.019 * (1 + 0.05 * blot) + 0.015 * scuff
    rough = 0.42 + 0.04 * blot + 0.02 * peel + 0.18 * scuff
    h = 0.04 * peel + 0.01 * scuff
    return save_set(out, "cage_paint_satin_black", col, h, rough, 0.0, tile, {
        "use": "roll cage tubes, brackets, painted chassis metal",
        "basis": "satin black paint or powder, orange peel 2-5 mm, sparse scuffs along U",
    })


def seat_fabric(out: Path, worn: bool) -> dict:
    """Red flame-retardant velour of the race buckets (photo interior/007)."""
    tile = 0.10
    px = tile * 1000 / N
    # Fine knit: courses along U every 1.0 mm, wales every 0.8 mm, offset per course.
    cu = U * 100.0
    cv = V * 125.0
    off = np.mod(np.floor(cv), 2) * 0.5
    loop = np.sin(math.pi * np.mod(cu + off, 1.0)) ** 1.5 * np.sin(math.pi * np.mod(cv, 1.0)) ** 0.8
    fuzz = noise(0.6, seed=111)
    mott = noise(35, seed=112) * 0.6 + noise(100, seed=113) * 0.4
    pile = noise(1.2, 5, seed=114)
    red = np.stack([0.42, 0.010, 0.014])[None, None, :]
    shade = (1 + 0.10 * loop + 0.07 * fuzz + 0.06 * mott + 0.05 * pile)[..., None]
    col = red * shade
    rough = 0.93 + 0.03 * fuzz - 0.02 * loop
    h = 0.05 * loop + 0.015 * fuzz + 0.01 * pile
    if worn:
        wear = smoothstep(0.5, 1.9, noise(40, seed=115) * 0.7 + noise(10, seed=116) * 0.3)
        faded = np.stack([0.55, 0.06, 0.07])[None, None, :] * shade
        col = col * (1 - 0.45 * wear[..., None]) + faded * 0.45 * wear[..., None]
        pills = (noise(1.0, seed=117) > 2.6).astype(float) * wear
        col = col + 0.06 * pills[..., None]
        h = h * (1 - 0.5 * wear) + 0.04 * pills
        rough = rough - 0.08 * wear
    return save_set(out, "seat_fabric_red_worn" if worn else "seat_fabric_red", col, h,
                    np.clip(rough, 0, 1), 0.0, tile, {
                        "use": "race bucket upholstery; worn variant for bolsters and the base cushion",
                        "basis": "fine knit velour, 1.0 x 0.8 mm loops, mottling; worn = sun-faded "
                                 "pink with pilling",
                    })


def paint_red(out: Path) -> dict:
    tile = 0.30
    peel = noise(9, seed=121) * 0.6 + noise(22, seed=122) * 0.4      # orange peel 3-8 mm
    col = np.stack([0.46, 0.0035, 0.0050])[None, None, :] * (1 + 0.01 * noise(40, seed=123))[..., None]
    rough = 0.085 + 0.012 * noise(30, seed=124) + 0.006 * peel
    # Real orange peel slopes are a few mrad, below one 8-bit normal step (0.45 deg):
    # a visible amount here would read as heavy peel, so the paint's normal stays flat.
    h = 0.0 * peel
    return save_set(out, "paint_red_clearcoat", col, h, rough, 0.0, tile, {
        "use": "body paint under the Dream Racing livery; the livery is a separate map",
        "basis": "solid red under clear: one sharp lobe (roughness ~0.085) stands for the clear coat, "
                 "subtle orange peel",
    })


def webbing_red(out: Path) -> dict:
    """Harness webbing (photo interior/007): faded red polyester twill, along V."""
    tile = 0.05
    a = U * 70.0
    b = V * 120.0
    k = np.mod(np.floor(a) + np.floor(b), 3)
    rib = np.sin(math.pi * np.mod(b + a * 0.0, 1.0)) ** 0.7
    twill = np.where(k == 0, 1.0, 0.75)
    fuzz = noise(0.6, seed=131)
    mott = noise(40, seed=132)
    col = np.stack([0.50, 0.035, 0.040])[None, None, :] * (1 + 0.10 * rib * twill + 0.05 * fuzz + 0.05 * mott)[..., None]
    rough = 0.72 + 0.04 * fuzz - 0.03 * rib
    h = 0.03 * rib * twill + 0.006 * fuzz
    return save_set(out, "webbing_red", col, h, rough, 0.0, tile, {
        "use": "harness straps; U across the strap, V along it",
        "basis": "polyester twill webbing, faded red",
    })


# Flat sets whose colours were read off the photos named in "basis".
FLAT_ADDED = {
    "plastic_white": {"name": "plastic_white", "kind": "flat", "albedo_srgb": [222, 222, 216], "roughness": 0.5,
                      "metalness": 0.0, "roblox_material": "SmoothPlastic",
                      "basis": "photo interior/008: cooler body and inline blower", "use": "cooler, blower"},
    "plastic_blue": {"name": "plastic_blue", "kind": "flat", "albedo_srgb": [88, 150, 196], "roughness": 0.45,
                     "metalness": 0.0, "roblox_material": "SmoothPlastic",
                     "basis": "photo interior/010: PIT, SCROLL and WIPER button caps", "use": "wheel button caps"},
    "plastic_yellow": {"name": "plastic_yellow", "kind": "flat", "albedo_srgb": [226, 186, 38], "roughness": 0.45,
                       "metalness": 0.0, "roblox_material": "SmoothPlastic",
                       "basis": "photo interior/010: LEFT and RIGHT indicator caps", "use": "wheel button caps"},
    "aluminium_anodised_blue": {"name": "aluminium_anodised_blue", "kind": "flat", "albedo_srgb": [36, 66, 112],
                                "roughness": 0.4, "metalness": 1.0, "roblox_material": "Metal",
                                "basis": "photo interior/013: AC FAN knob", "use": "switch panel rotary knob"},
    "decal_sheet": {"name": "decal_sheet", "kind": "decal", "albedo_srgb": [255, 255, 255], "roughness": 0.5,
                    "metalness": 0.0, "roblox_material": "SmoothPlastic",
                    "image": "cockpit/lead_src/lead_decals.png",
                    "basis": "label cards textured from the decal sheet (colour + alpha), drawn proud of their part",
                    "use": "switch panel, paddle and wheel labels"},
}


def main() -> None:
    """Build every set, or only the named ones (merged into the existing library.json)."""
    out = Path(sys.argv[1])
    only = set(sys.argv[2:])
    out.mkdir(parents=True, exist_ok=True)
    builders = [
        (("alcantara",), lambda: [alcantara(out, worn=False)]),
        (("alcantara_worn",), lambda: [alcantara(out, worn=True)]),
        (("carbon_twill_gloss", "carbon_twill_satin"), lambda: carbon(out)),
        (("aluminium_brushed",), lambda: [brushed_aluminium(out)]),
        (("aluminium_anodised_black",), lambda: [anodised_black(out)]),
        (("aluminium_anodised_black_worn",), lambda: [anodised_black_worn(out)]),
        (("carbon_twill_gloss_worn",), lambda: [carbon_gloss_worn(out)]),
        (("rubber",), lambda: [rubber(out)]),
        (("treadplate_black",), lambda: [treadplate_black(out)]),
        (("aluminium_perforated",), lambda: [perforated_aluminium(out)]),
        (("cage_paint_satin_black",), lambda: [cage_paint(out)]),
        (("seat_fabric_red",), lambda: [seat_fabric(out, worn=False)]),
        (("seat_fabric_red_worn",), lambda: [seat_fabric(out, worn=True)]),
        (("paint_red_clearcoat",), lambda: [paint_red(out)]),
        (("webbing_red",), lambda: [webbing_red(out)]),
    ]
    prev = json.loads((out / "library.json").read_text()) if (out / "library.json").exists() else {}
    old = {m["name"]: m for m in prev.get("materials", [])}
    recs = []
    for names, build in builders:
        if not only or only & set(names):
            recs.extend(build())
        else:
            recs.extend(old[n] for n in names if n in old)
    # Sets no builder makes (the flat ones) are kept as they are, then FLAT_ADDED fills gaps.
    built = {n for names, _b in builders for n in names}
    recs.extend(m for n, m in old.items() if n not in built and n not in FLAT_ADDED)
    recs.extend(FLAT_ADDED.values())
    extras = {k: v for k, v in prev.items() if k not in ("resolution", "uv_rule", "normal_convention",
                                                        "colour_space", "carbon_twill_satin", "materials")}
    lib = {**extras,
        "resolution": N,
        "uv_rule": "uv = surface metres / tile_m (UVs outside 0..1 repeat)",
        "normal_convention": "OpenGL, green = +V",
        "colour_space": {"color": "sRGB", "normal": "linear", "roughness": "linear", "metalness": "linear"},
        "carbon_twill_satin": "reuses carbon_twill_gloss colour and normal maps",
        "materials": recs,
    }
    (out / "library.json").write_text(json.dumps(lib, indent=1))


if __name__ == "__main__":
    main()
