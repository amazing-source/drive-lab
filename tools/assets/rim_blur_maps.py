"""
Turns the radial profiles written by tools/blender/rim_blur.py into the blurred rims' maps: one
2048 x 1024 atlas per channel, the front rim in the left half and the rear rim in the right half,
each half spanning its rim's texture radius. Drive Lab's rim blur gives every blurred disc a
SurfaceAppearance with these, AlphaMode Transparency.

    python -I tools/assets/rim_blur_maps.py <build dir> <out dir>

Writes rim_blur_colour.png (sRGB colour, alpha = the share of each circle the rim covers),
rim_blur_metalness.png, rim_blur_roughness.png, and previews/ for the eye: each corner's
front-on render beside its blurred disc, both over the same grey, and the atlas over grey.

Colour, metalness and roughness are coverage-weighted means around each circle, so a circle
that is half spoke and half gap carries the spokes' colour at half opacity. Where a circle has no
rim at all, colour and data are carried in from the nearest circle that has, so filtering at the
disc's edges never pulls in black.
"""

import json
import os
import sys

import numpy as np
from PIL import Image

HALF = 1024
# Corners whose profiles make the atlas; the right-hand wheels' rims are their mirror images,
# whose mean around a circle is the same (rim_blur.py reports the measured difference).
SOURCES = {"front": "FL", "rear": "RL"}
# A circle with less coverage than this carries the nearest covered circle's colour and data.
COVERED = 0.02
PREVIEW_GREY = 0.18


def srgb(linear: np.ndarray) -> np.ndarray:
    linear = np.clip(linear, 0, 1)
    return np.where(linear <= 0.0031308, 12.92 * linear, 1.055 * linear ** (1 / 2.4) - 0.055)


def straight(profile: np.ndarray) -> np.ndarray:
    """Columns 0-2 albedo, 3 metalness, 4 roughness divided by coverage (column 5), carried in
    from the nearest covered radius where there is none; coverage unchanged."""
    coverage = profile[:, 5]
    covered = np.nonzero(coverage > COVERED)[0]
    out = np.empty_like(profile)
    index = np.arange(len(profile))
    for column in range(5):
        values = profile[covered, column] / coverage[covered]
        out[:, column] = np.interp(index, covered, values)
    out[:, 5] = np.clip(coverage, 0, 1)
    return out


def half(profile: np.ndarray, step: float, radius: float) -> np.ndarray:
    """A HALF x HALF image of the profile spun about its centre, spanning [-radius, radius]."""
    centres = (np.arange(HALF) + 0.5) / HALF * 2 * radius - radius
    x, y = np.meshgrid(centres, centres)
    position = np.hypot(x, y) / step
    radii = np.arange(len(profile))
    image = np.stack([np.interp(position, radii, profile[:, c]) for c in range(6)], axis=2)
    outside = position > radii[-1]
    image[outside, 5] = 0
    return image


def over_grey(colour_linear: np.ndarray, coverage: np.ndarray) -> np.ndarray:
    return srgb(colour_linear * coverage[..., None] + PREVIEW_GREY * (1 - coverage[..., None]))


def save(path: str, array: np.ndarray, mode: str):
    Image.fromarray(np.round(np.clip(array, 0, 1) * 255).astype(np.uint8), mode).save(path)


def main(build: str, out: str):
    os.makedirs(os.path.join(out, "previews"), exist_ok=True)
    data = np.load(os.path.join(build, "profiles.npz"))
    step = float(data["step"])
    halves = {}
    report = {}
    for axle, corner in SOURCES.items():
        profile = straight(data[corner].astype(np.float64))
        radius = float(data[f"radius_{corner}"])
        halves[axle] = half(profile, step, radius)
        coverage = profile[:, 5]
        report[axle] = {
            "corner": corner,
            "textureRadius": radius,
            "faceRadius": float(data[f"extent_{corner}"]),
            "meanCoverage": round(float(coverage[coverage > 0].mean()), 3),
            "albedoSrgbMean": [round(float(v), 3) for v in srgb(profile[coverage > COVERED, :3]).mean(axis=0)],
            "metalnessMean": round(float(profile[coverage > COVERED, 3].mean()), 3),
            "roughnessMean": round(float(profile[coverage > COVERED, 4].mean()), 3),
        }
    atlas = np.concatenate([halves["front"], halves["rear"]], axis=1)
    colour = np.concatenate([srgb(atlas[..., :3]), atlas[..., 5:6]], axis=2)
    save(os.path.join(out, "rim_blur_colour.png"), colour, "RGBA")
    save(os.path.join(out, "rim_blur_metalness.png"), atlas[..., 3], "L")
    save(os.path.join(out, "rim_blur_roughness.png"), atlas[..., 4], "L")
    save(os.path.join(out, "previews", "atlas_over_grey.png"), over_grey(atlas[..., :3], atlas[..., 5]), "RGB")

    for corner in ("FL", "FR", "RL", "RR"):
        sharp = np.load(os.path.join(build, f"front_{corner}.npy")).astype(np.float64)
        coverage = np.clip(sharp[..., 5], 0, 1)
        albedo = sharp[..., :3] / np.maximum(coverage, 1e-6)[..., None]
        left = over_grey(albedo, coverage)
        profile = straight(data[corner].astype(np.float64))
        blurred = half(profile, step, float(data[f"radius_{corner}"]))
        size = left.shape[0]
        pick = (np.arange(size) * HALF // size)[:, None], (np.arange(size) * HALF // size)[None, :]
        right = over_grey(blurred[..., :3][pick], blurred[..., 5][pick])
        save(os.path.join(out, "previews", f"front_{corner}_sharp_vs_blurred.png"), np.concatenate([left, right], axis=1), "RGB")
    with open(os.path.join(out, "maps.json"), "w") as handle:
        json.dump(report, handle, indent=1)
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main(*sys.argv[1:3])
