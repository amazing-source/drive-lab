"""
Turns VFX textures drawn on pure black into transparent PNGs for Roblox particles and beams.

    python -I tools/assets/black_to_alpha.py <in dir> <out dir> <mode:file:size> ...

Modes:
- glow: alpha is the brightest channel and the colour is un-premultiplied, so a flame or a
  spark keeps its colours and fades exactly as it faded into black.
- smoke: the same, left grey so a ParticleEmitter's Color can tint it.
- solid: an opaque object on black (a coin): a soft-edged mask, colours untouched.
Size is the longest side in pixels; the aspect ratio is kept.
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image

# Below this (0-1) the pixel is treated as background, so noise is not blown up into colour.
FLOOR = 2 / 255
# A solid object's mask ramps from fully clear to fully opaque over this brightness band.
SOLID_FROM, SOLID_TO = 8 / 255, 28 / 255


def convert(image: Image.Image, mode: str) -> Image.Image:
    rgb = np.asarray(image.convert("RGB"), dtype=np.float64) / 255
    brightest = rgb.max(axis=2)
    if mode == "solid":
        alpha = np.clip((brightest - SOLID_FROM) / (SOLID_TO - SOLID_FROM), 0, 1)
        colour = rgb
    else:
        alpha = np.where(brightest < FLOOR, 0, brightest)
        safe = np.maximum(alpha, FLOOR)[..., None]
        colour = np.clip(rgb / safe, 0, 1)
        if mode == "smoke":
            grey = colour.mean(axis=2, keepdims=True)
            colour = np.repeat(grey, 3, axis=2)
    out = np.dstack([colour, alpha[..., None]])
    return Image.fromarray(np.round(out * 255).astype(np.uint8), "RGBA")


def main():
    source, target = Path(sys.argv[1]), Path(sys.argv[2])
    target.mkdir(parents=True, exist_ok=True)
    for spec in sys.argv[3:]:
        mode, name, size = spec.split(":")
        image = Image.open(source / name)
        longest = int(size)
        scale = longest / max(image.size)
        if scale < 1:
            image = image.resize((round(image.size[0] * scale), round(image.size[1] * scale)), Image.LANCZOS)
        converted = convert(image, mode)
        out = target / name.replace(" ", "_")
        converted.save(out, optimize=True)
        print(f"{out.name}: {converted.size[0]}x{converted.size[1]} {mode}")


if __name__ == "__main__":
    main()
