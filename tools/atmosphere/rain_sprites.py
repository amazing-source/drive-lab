"""
Draws Drive Lab's rain textures, white with the shape in alpha so a particle's Color and the
scene's light decide the colour (the lens drops alone carry their own shading).

    python -I rain_sprites.py <out dir>

All sheets are square powers of two at most 1024, as flipbooks need, and every cell keeps a
clear border so filtering never bleeds one cell into the next. The falling streaks and the
ripples are the owner's rain pack (drive-lab-assets/chatgpt_rain_2026-10-28), RGBA sprites
uploaded as they are; this script no longer draws streaks.

- DriveLabRainSplash.png  1024, 4 x 4 frames, played once: an upright crown seen from the side
  (base on the cell's centre line, rising into the top half), breaking into droplets that fall
  back, over 16 frames.
- DriveLabRainMist.png    1024, 2 x 2 cells: soft fractal-noise puffs for tyre spray.
- DriveLabLensDrops.png   1024, 4 x 4 cells: irregular water drops on a lens, dark rim, faint
  body, a highlight; the last four run down with a trail.
"""

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def rgba_white(alpha: np.ndarray) -> Image.Image:
    alpha = np.clip(alpha, 0, 1)
    rgba = np.zeros(alpha.shape + (4,), dtype=np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = np.round(alpha * 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def atlas(cells: list, grid: int) -> np.ndarray:
    size = cells[0].shape[0]
    out = np.zeros((size * grid, size * grid) + cells[0].shape[2:], dtype=np.float64)
    for index, cell in enumerate(cells):
        row, column = divmod(index, grid)
        out[row * size : (row + 1) * size, column * size : (column + 1) * size] = cell
    return out


def border(size: int, pad: int) -> np.ndarray:
    ramp = np.clip((np.minimum(np.arange(size), size - 1 - np.arange(size)) - pad) / pad, 0, 1)
    return np.outer(ramp, ramp)


def smooth(edge0: float, edge1: float, value: np.ndarray) -> np.ndarray:
    t = np.clip((value - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)


def dot(cell: np.ndarray, x: float, y: float, radius: float, opacity: float):
    size = cell.shape[0]
    x0, x1 = int(max(0, x - 3 * radius - 2)), int(min(size, x + 3 * radius + 3))
    y0, y1 = int(max(0, y - 3 * radius - 2)), int(min(size, y + 3 * radius + 3))
    if x0 >= x1 or y0 >= y1:
        return
    ys, xs = np.mgrid[y0:y1, x0:x1].astype(np.float64)
    layer = np.exp(-0.5 * ((xs - x) ** 2 + (ys - y) ** 2) / radius**2) * opacity
    patch = cell[y0:y1, x0:x1]
    cell[y0:y1, x0:x1] = 1 - (1 - patch) * (1 - np.clip(layer, 0, 1))


def splash_frames(seed: int = 7, size: int = 256, count: int = 16) -> list:
    """An upright crown, side view with a slight look down: base ellipse on the centre line."""
    rng = np.random.default_rng(seed)
    centre_x, base_y = size / 2, size / 2
    fingers = 14
    angles = (np.arange(fingers) + rng.uniform(0.2, 0.8, fingers)) / fingers * 2 * math.pi
    tall = rng.uniform(0.7, 1.0, fingers)
    # Droplets leave finger tips at the crown's peak and fly ballistically (pixels, frame units).
    launches = [(a, rng.uniform(0.6, 1.4), rng.uniform(1.6, 2.6), rng.uniform(1.4, 2.4)) for a in angles[::2]]
    frames = []
    for frame in range(count):
        t = frame / (count - 1)
        cell = np.zeros((size, size))
        radius = 10 + 34 * (1 - (1 - min(t / 0.7, 1)) ** 2)
        height = 62 * math.sin(math.pi * min(t / 0.62, 1)) ** 0.8
        fade = 1 - smooth(0.55, 1.0, np.array(t))
        squash = 0.28
        if t < 0.1:
            # The impact itself: a bright bead where the drop lands.
            dot(cell, centre_x, base_y, 5 - 20 * t, 0.9)
        if height > 1:
            for angle, share in zip(angles, tall):
                near = 0.55 + 0.45 * max(0.0, math.sin(angle))
                x = centre_x + radius * math.cos(angle)
                y = base_y + radius * squash * math.sin(angle)
                reach = height * share
                # The crown flares: each finger leans outward as it rises.
                for step in np.linspace(0, 1, 48):
                    dot(cell, x + math.cos(angle) * reach * 0.5 * step, y - reach * step, 1.5 - 0.6 * step, 0.3 * near * float(fade))
            # The thin sheet joining the fingers, strongest on the near side.
            ys, xs = np.mgrid[0:size, 0:size].astype(np.float64)
            ellipse = np.sqrt(((xs - centre_x) / radius) ** 2 + ((ys - base_y) / (radius * squash)) ** 2)
            wall = np.exp(-0.5 * ((ellipse - 1) / 0.08) ** 2) * (ys >= base_y - radius * squash) * 0.35
            cell = 1 - (1 - cell) * (1 - wall * float(fade))
        for angle, spread, lift, fall in launches:
            age = t - 0.32
            if age <= 0:
                continue
            tip_x = centre_x + 62 * math.cos(angle)
            tip_y = base_y + 30 * squash * math.sin(angle) - 52
            x = tip_x + math.cos(angle) * spread * 40 * age
            y = tip_y - lift * 60 * age + fall * 160 * age * age
            if y < size - 8:
                dot(cell, x, y, 2.2, 0.85 * float(fade))
        frames.append(cell * border(size, 6))
    return frames


def noise(size: int, rng, octaves: int = 5) -> np.ndarray:
    total = np.zeros((size, size))
    weight = 1.0
    for octave in range(octaves):
        cells = 4 * 2**octave
        grid = rng.uniform(0, 1, (cells + 1, cells + 1))
        image = Image.fromarray((grid * 255).astype(np.uint8)).resize((size, size), Image.BICUBIC)
        total += weight * np.asarray(image, dtype=np.float64) / 255
        weight *= 0.55
    total -= total.min()
    return total / total.max()


def mist_cell(seed: int, size: int = 512) -> np.ndarray:
    rng = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float64)
    u, v = (xs - size / 2) / (size / 2), (ys - size / 2) / (size / 2)
    radius = np.sqrt(u * u + v * v)
    body = smooth(1.0, 0.25, radius)
    wisps = smooth(0.35, 0.85, noise(size, rng))
    return np.clip(body * (0.35 + 0.65 * wisps) * 0.85, 0, 1) * border(size, 10)


def lens_cell(seed: int, size: int = 256, trail: bool = False) -> np.ndarray:
    """RGBA floats: a drop on a lens, with the colour of its own shading."""
    rng = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float64)
    radius = rng.uniform(28, 40) if trail else rng.uniform(22, 88)
    centre_x = size / 2 + rng.uniform(-6, 6)
    centre_y = size * (0.66 if trail else 0.5)
    angle = np.arctan2(ys - centre_y, xs - centre_x)
    wobble = np.ones_like(angle)
    for harmonic in range(2, 6):
        wobble += rng.uniform(0.02, 0.07) * np.cos(harmonic * angle + rng.uniform(0, 6.3))
    # Gravity flattens the top and fills the bottom a little.
    wobble *= 1 + 0.08 * np.sin(angle)
    distance = np.sqrt((xs - centre_x) ** 2 + (ys - centre_y) ** 2) / (radius * wobble)
    if trail:
        width = radius * 0.32 * (1 - smooth(centre_y - 4, 8, ys) * 0.6)
        track = np.abs(xs - centre_x - 3 * np.sin(ys / 23)) / np.maximum(width, 1)
        track = np.where(ys < centre_y, track, 9)
        distance = np.minimum(distance, track)
    inside = smooth(1.02, 0.96, distance)
    rim = np.exp(-0.5 * ((distance - 0.93) / 0.06) ** 2) * (0.55 + 0.45 * smooth(-0.2, 0.9, (ys - centre_y) / radius))
    caustic = np.exp(-0.5 * (((xs - centre_x) / (radius * 0.45)) ** 2 + ((ys - centre_y - radius * 0.5) / (radius * 0.16)) ** 2))
    glint = np.exp(-0.5 * (((xs - centre_x + radius * 0.35) / (radius * 0.13)) ** 2 + ((ys - centre_y + radius * 0.4) / (radius * 0.09)) ** 2))
    alpha = np.clip(inside * 0.14 + rim * 0.55 + caustic * inside * 0.3 + glint * 0.85, 0, 1)
    dark = np.array([42, 47, 55]) / 255
    light = np.array([214, 220, 228]) / 255
    share = np.clip((rim * 0.55) / np.maximum(alpha, 1e-4), 0, 1)[..., None]
    colour = light * (1 - share) + dark * share
    colour = np.where((glint > 0.3)[..., None], np.array([1.0, 1.0, 1.0]), colour)
    fade = border(size, 6)
    return np.concatenate([colour, (alpha * fade)[..., None]], axis=2)


def save_rgba(pixels: np.ndarray, path: Path):
    rgba = np.round(np.clip(pixels, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(path)


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    rgba_white(atlas(splash_frames(), 4)).save(out / "DriveLabRainSplash.png")
    rgba_white(atlas([mist_cell(51 + index) for index in range(4)], 2)).save(out / "DriveLabRainMist.png")
    lens = [lens_cell(71 + index, trail=index >= 12) for index in range(16)]
    save_rgba(atlas(lens, 4), out / "DriveLabLensDrops.png")


if __name__ == "__main__":
    main()
