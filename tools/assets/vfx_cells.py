"""
Cuts a sheet of independent sprite variants drawn on pure black (an image generator's atlas)
into keyed cells and packs the chosen ones into a 2 x 2 flipbook for a ParticleEmitter, which
shows one variant per particle with FlipbookFramerate 0 and FlipbookStartRandom. Writes a
preview over asphalt, sky and grey next to it, since an image viewer hides the colour of
invisible texels.

    python -I tools/assets/vfx_cells.py <sheet.png> <grid> <out.png> <cell px> <mode> <cell> ...

Cells are numbered 1.. row by row; a trailing "m" mirrors one (a fourth variant from three).
Modes:
- smoke: a puff's own grey kept. Alpha ramps from the floor (8/255 and below is clear) to the
  puff's denser half, which is opaque and keeps its self-shadowing; thinner texels and the
  clear ones take that half's grey, so no edge carries a dark fringe. Cells are not cropped.
- solid: an opaque object (gravel, crumbs, a leaf): a black key closed over dark specks inside
  the object, its grey shading kept, edge texels coloured from the inside.
- soft: dust and water: alpha is the brightness, the colour white.
- streak: as soft, turned so the bulb leads along +X and the smear trails along -X (a drop with
  a motion smear, for VelocityParallel particles, which lay the texture's X along the motion).
solid, soft and streak cells are cropped to the sprite and padded so it fills FILL of the cell.
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

FLOOR = 8 / 255
# A solid object's key ramps from clear to opaque over this brightness band.
SOLID_FROM, SOLID_TO = 8 / 255, 30 / 255
# Smoke: texels from this brightness percentile of the puff up are opaque; the darkest opaque
# shade is this share of the brightest.
SMOKE_OPAQUE_PERCENTILE = 35
SMOKE_SHADE_FLOOR = 0.62
FILL = 0.86
BACKDROPS = ((52, 54, 58), (128, 172, 214), (128, 128, 128))


def luminance(rgb: np.ndarray) -> np.ndarray:
    return rgb @ np.array([0.2126, 0.7152, 0.0722])


def blur(values: np.ndarray, sigma: float) -> np.ndarray:
    reach = max(1, int(np.ceil(sigma * 3)))
    taps = np.exp(-0.5 * (np.arange(-reach, reach + 1) / sigma) ** 2)
    taps /= taps.sum()
    padded = np.pad(values, reach, mode="constant")
    rows = np.apply_along_axis(lambda line: np.convolve(line, taps, mode="valid"), 1, padded)
    return np.apply_along_axis(lambda line: np.convolve(line, taps, mode="valid"), 0, rows)


def smoke(rgb: np.ndarray) -> np.ndarray:
    """A render on black holds lit colour times density, and cannot tell a shadowed lobe from
    a thin one. The body (from the puff's SMOKE_OPAQUE_PERCENTILE brightness up) is opaque and
    keeps its shading, compressed so its darkest is SMOKE_SHADE_FLOOR of its brightest; below
    that the smoke thins out in alpha at that same floor colour, so no edge is darker than the
    body's own shadow."""
    light = luminance(rgb)
    inside = light[light > 0.1]
    opaque = np.percentile(inside, SMOKE_OPAQUE_PERCENTILE) if inside.size else 1.0
    density = blur(light, 1.0)
    alpha = np.clip((density - FLOOR) / (opaque - FLOOR), 0, 1)
    alpha[light <= FLOOR] = 0
    top = light.max()
    grey = SMOKE_SHADE_FLOOR + (1 - SMOKE_SHADE_FLOOR) * np.clip((light - opaque) / (top - opaque), 0, 1)
    return np.dstack([grey, grey, grey, alpha])


def solid(rgb: np.ndarray) -> np.ndarray:
    light = luminance(rgb)
    key = np.clip((light - SOLID_FROM) / (SOLID_TO - SOLID_FROM), 0, 1)
    image = Image.fromarray(np.round(key * 255).astype(np.uint8), "L")
    closed = image.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
    alpha = np.maximum(key, np.asarray(closed, dtype=np.float64) / 255)
    alpha = np.clip(blur(alpha, 0.6) * 1.15, 0, 1)
    alpha[light <= FLOOR * 0.5] = np.minimum(alpha[light <= FLOOR * 0.5], blur(key, 1.0)[light <= FLOOR * 0.5])
    inner = (key >= 0.999).astype(np.float64)
    weight = blur(inner, 2.5)
    out = np.empty(rgb.shape[:2] + (4,))
    for channel in range(3):
        spread = blur(rgb[..., channel] * inner, 2.5) / np.maximum(weight, 1e-6)
        out[..., channel] = np.where(inner > 0, rgb[..., channel], np.where(weight > 1e-4, spread, 0.5))
    out[..., 3] = alpha
    return out


def soft(rgb: np.ndarray) -> np.ndarray:
    light = luminance(rgb)
    top = max(np.percentile(light[light > FLOOR], 98) if (light > FLOOR).any() else 1.0, FLOOR * 2)
    alpha = np.clip((light - FLOOR) / (top - FLOOR), 0, 1)
    return np.dstack([np.ones_like(light)] * 3 + [alpha])


def lead_with_bulb(cell: np.ndarray) -> np.ndarray:
    """Turns a streak so its long axis is horizontal, the bulb (the end nearer the alpha
    centroid; the thin smear reaches further from it) on the right."""
    alpha = cell[..., 3]
    ys, xs = np.nonzero(alpha > 0.05)
    weights = alpha[ys, xs]
    cx, cy = np.average(xs, weights=weights), np.average(ys, weights=weights)
    dx, dy = xs - cx, ys - cy
    covariance = np.cov(np.vstack([dx, dy]), aweights=weights)
    values, vectors = np.linalg.eigh(covariance)
    axis = vectors[:, np.argmax(values)]
    along = dx * axis[0] + dy * axis[1]
    if abs(along.max()) > abs(along.min()):
        axis = -axis
    # Image y runs down; PIL rotates counter-clockwise by the angle given.
    angle = np.degrees(np.arctan2(-axis[1], axis[0]))
    image = Image.fromarray(np.round(cell * 255).astype(np.uint8), "RGBA")
    return np.asarray(image.rotate(-angle, resample=Image.BICUBIC, expand=True), dtype=np.float64) / 255


def fit(cell: np.ndarray, size: int) -> np.ndarray:
    alpha = cell[..., 3]
    ys, xs = np.nonzero(alpha > 0.02)
    cropped = cell[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]
    side = int(np.ceil(max(cropped.shape[:2]) / FILL))
    square = np.zeros((side, side, 4))
    square[..., :3] = 1
    top, left = (side - cropped.shape[0]) // 2, (side - cropped.shape[1]) // 2
    square[top : top + cropped.shape[0], left : left + cropped.shape[1]] = cropped
    # Colour under clear texels comes from the nearest sprite colour, so filtering at the
    # edge blends toward the sprite, never toward white or black.
    weight = blur(square[..., 3], 3)
    for channel in range(3):
        spread = blur(square[..., channel] * square[..., 3], 3) / np.maximum(weight, 1e-6)
        square[..., channel] = np.where(square[..., 3] > 0.02, square[..., channel], np.where(weight > 1e-4, spread, 1))
    image = Image.fromarray(np.round(np.clip(square, 0, 1) * 255).astype(np.uint8), "RGBA")
    return np.asarray(image.resize((size, size), Image.LANCZOS), dtype=np.float64) / 255


KEYS = {"smoke": smoke, "solid": solid, "soft": soft, "streak": soft}


def cell_of(sheet: np.ndarray, grid: int, label: str) -> np.ndarray:
    mirrored = label.endswith("m")
    index = int(label.rstrip("m")) - 1
    edge = sheet.shape[0] // grid
    row, column = divmod(index, grid)
    cell = sheet[row * edge : (row + 1) * edge, column * edge : (column + 1) * edge]
    return cell[:, ::-1] if mirrored else cell


def preview(packed: np.ndarray, path: Path):
    alpha = packed[..., 3:4]
    tiles = [packed[..., :3] * alpha + np.array(colour) / 255 * (1 - alpha) for colour in BACKDROPS]
    Image.fromarray(np.round(np.hstack(tiles) * 255).astype(np.uint8), "RGB").save(path)


def main():
    source, grid, out, size, mode = sys.argv[1], int(sys.argv[2]), Path(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
    labels = sys.argv[6:]
    if len(labels) != 4 or mode not in KEYS:
        raise SystemExit("four cells and a mode: smoke, solid, soft or streak")
    sheet = np.asarray(Image.open(source).convert("RGB"), dtype=np.float64) / 255
    packed = np.zeros((size * 2, size * 2, 4))
    for slot, label in enumerate(labels):
        cell = KEYS[mode](cell_of(sheet, grid, label))
        if mode == "streak":
            cell = lead_with_bulb(cell)
        if mode == "smoke":
            image = Image.fromarray(np.round(np.clip(cell, 0, 1) * 255).astype(np.uint8), "RGBA")
            cell = np.asarray(image.resize((size, size), Image.LANCZOS), dtype=np.float64) / 255
        else:
            cell = fit(cell, size)
        row, column = divmod(slot, 2)
        packed[row * size : (row + 1) * size, column * size : (column + 1) * size] = cell
    out.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.round(np.clip(packed, 0, 1) * 255).astype(np.uint8), "RGBA").save(out, optimize=True)
    preview(packed, out.with_name(out.stem + "_preview.png"))
    print(f"{out.name}: {size * 2}x{size * 2} {mode} cells {' '.join(labels)}")


if __name__ == "__main__":
    main()
