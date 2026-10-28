"""
Prepares a drawn effect sheet for a Roblox ParticleEmitter flipbook: a square power-of-two
texture (Roblox flipbooks need one, at most 1024), the faint haze an image generator leaves
around strokes cut away, and fully transparent texels set to white so texture filtering at a
stroke's edge never pulls in a dark fringe. Writes a grey preview next to it, since chat and
image viewers show the colour of invisible pixels and make a clean sheet look noisy.

    python -I tools/assets/flipbook_atlas.py <in.png> <out.png> [--size 1024] [--haze 48]

A sheet with a black background and no alpha (additive art) needs no cleaning: use it with
ParticleEmitter.LightEmission = 1 instead.
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source")
    parser.add_argument("out")
    parser.add_argument("--size", type=int, default=1024, help="output edge, a power of two up to 1024")
    parser.add_argument("--haze", type=int, default=48, help="alpha below this becomes fully transparent")
    args = parser.parse_args()
    if args.size & (args.size - 1) or args.size > 1024:
        raise SystemExit("--size must be a power of two up to 1024")

    image = Image.open(args.source).convert("RGBA").resize((args.size, args.size), Image.LANCZOS)
    pixels = np.asarray(image).astype(float)
    alpha = np.where(pixels[..., 3] < args.haze, 0, pixels[..., 3])
    pixels[..., 3] = alpha
    pixels[..., :3] = np.where(alpha[..., None] == 0, 255, pixels[..., :3])
    Image.fromarray(pixels.clip(0, 255).astype(np.uint8)).save(args.out)

    weight = alpha[..., None] / 255
    preview = (pixels[..., :3] * weight + 90 * (1 - weight)).clip(0, 255).astype(np.uint8)
    preview_path = Path(args.out).with_name(Path(args.out).stem + "_preview.png")
    Image.fromarray(preview).save(preview_path)
    print(f"{args.out}: {args.size}px, {(alpha > 0).mean():.1%} of texels drawn; preview {preview_path}")


if __name__ == "__main__":
    main()
