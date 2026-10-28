"""
Builds the wet road's material states from one CC0 photoscanned asphalt set, so every state
shares the same tile, aggregate and masks and a swap between them never shifts the pattern.

    python -I wet_asphalt_maps.py <source dir> <out dir> [--bake-darkening]

The source dir holds a Poly Haven set at 2K (*_diff_2k.png, *_nor_gl_2k.png, *_rough_2k.png,
*_disp_2k.png). Output: <Stage>_color.png, <Stage>_normal.png, <Stage>_roughness.png at 1024,
seamless, plus stages.json with what each state is.

The wet look, per the Drive Lab handoff and Lagarde's "physically based wet surfaces":
- roughness drops from about 0.83 to 0.18-0.38 under a water film, lower in the binder than on
  the aggregate tops, and to 0.08 where water pools between the stones;
- the film is uneven: a tileable mid-scale noise wets some patches before others, so the
  highlights break up instead of forming one sheet;
- water collects first in the lowest parts of the displacement map, so the stones stay visible
  and only the gaps between them flatten (their normals ease toward the water surface);
- albedo darkens with the film (to about 0.8) and more under pooled water. With
  --bake-darkening the full darkening is in the colour maps; without it the maps keep only the
  pooled-water darkening and the uniform part is left to Terrain:SetMaterialColor at runtime.
Asphalt and water stay non-metallic: no metalness map is written.
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

SIZE = 1024
# name, nominal wetness, share of the surface under pooled water
STAGES = [
    ("Dry", 0.0, 0.0),
    ("Damp", 0.25, 0.0),
    ("Wet", 0.5, 0.05),
    ("Wetter", 0.75, 0.12),
    ("Soaked", 1.0, 0.22),
]
DESATURATE = 0.6
FILM_ROUGHNESS = (0.18, 0.38)
POOL_ROUGHNESS = 0.08
FILM_ALBEDO = 0.8
POOL_ALBEDO = 0.82
POOL_EDGE = 0.03


def load(path: Path) -> np.ndarray:
    image = Image.open(path)
    array = np.asarray(image)
    scale = 65535.0 if array.dtype == np.uint16 or image.mode.startswith("I") else 255.0
    return array.astype(np.float64) / scale


def halve(array: np.ndarray) -> np.ndarray:
    # Box filter: exact and seamless for a tile, unlike a resampler that clamps at the edges.
    h, w = array.shape[:2]
    shape = (h // 2, 2, w // 2, 2) + array.shape[2:]
    return array.reshape(shape).mean(axis=(1, 3))


def to_size(array: np.ndarray) -> np.ndarray:
    while array.shape[0] > SIZE:
        array = halve(array)
    return array


def periodic_noise(scale_px: float, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    white = rng.standard_normal((SIZE, SIZE))
    fx = np.fft.fftfreq(SIZE)[:, None]
    fy = np.fft.fftfreq(SIZE)[None, :]
    radius = np.sqrt(fx * fx + fy * fy)
    filtered = np.real(np.fft.ifft2(np.fft.fft2(white) * np.exp(-0.5 * (radius * scale_px) ** 2)))
    return (filtered - filtered.mean()) / filtered.std()


def periodic_blur(array: np.ndarray, sigma_px: float) -> np.ndarray:
    fx = np.fft.fftfreq(SIZE)[:, None]
    fy = np.fft.fftfreq(SIZE)[None, :]
    kernel = np.exp(-2 * (np.pi * sigma_px) ** 2 * (fx * fx + fy * fy))
    return np.real(np.fft.ifft2(np.fft.fft2(array) * kernel))


def normalise(array: np.ndarray) -> np.ndarray:
    low, high = np.percentile(array, 1), np.percentile(array, 99)
    return np.clip((array - low) / (high - low), 0, 1)


def save_gray(array: np.ndarray, path: Path):
    Image.fromarray(np.round(np.clip(array, 0, 1) * 255).astype(np.uint8), "L").save(path)


def save_rgb(array: np.ndarray, path: Path):
    Image.fromarray(np.round(np.clip(array, 0, 1) * 255).astype(np.uint8), "RGB").save(path)


def find(source: Path, key: str) -> Path:
    matches = sorted(source.glob(f"*_{key}_2k.png"))
    if not matches:
        raise SystemExit(f"no *_{key}_2k.png in {source}")
    return matches[0]


def main():
    source, out = Path(sys.argv[1]), Path(sys.argv[2])
    bake = "--bake-darkening" in sys.argv[3:]
    out.mkdir(parents=True, exist_ok=True)

    color = to_size(load(find(source, "diff"))[..., :3])
    luminance = color @ np.array([0.2126, 0.7152, 0.0722])
    color = luminance[..., None] + (color - luminance[..., None]) * (1 - DESATURATE)
    normal = to_size(load(find(source, "nor_gl"))[..., :3] * 2 - 1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    rough = to_size(load(find(source, "rough")))
    rough = rough if rough.ndim == 2 else rough[..., 0]
    height = normalise(to_size(load(find(source, "disp"))))
    height = height if height.ndim == 2 else height[..., 0]

    patches = 0.7 * periodic_noise(150, 7) + 0.5 * periodic_noise(45, 3)
    patches /= patches.std()
    level = periodic_noise(300, 11)
    # Water settles on a smoothed height, raised in some areas so pools are not uniform.
    water_height = normalise(periodic_blur(height, 2) + 0.12 * level)
    tops = np.clip((height - 0.6) / 0.4, 0, 1)
    film_target = FILM_ROUGHNESS[0] + (FILM_ROUGHNESS[1] - FILM_ROUGHNESS[0]) * height

    report = []
    for name, wetness, pooled in STAGES:
        # Unevenness peaks half way: a damp road is patchy, a soaked one is wet all over.
        film = np.clip(wetness + 0.8 * wetness * (1 - wetness) * patches, 0, 1)
        film *= 1 - 0.35 * tops * (1 - wetness)
        if pooled > 0:
            threshold = np.quantile(water_height, pooled)
            depth = np.clip((threshold - water_height) / POOL_EDGE + 0.5, 0, 1)
        else:
            depth = np.zeros_like(height)
        stage_rough = rough + (film_target - rough) * film
        stage_rough += (POOL_ROUGHNESS - stage_rough) * depth
        darkening = 1 + (FILM_ALBEDO - 1) * film if bake else np.ones_like(film)
        darkening *= 1 + (POOL_ALBEDO - 1) * depth
        stage_color = color * darkening[..., None]
        flat = np.zeros_like(normal)
        flat[..., 2] = 1
        stage_normal = normal + (flat - normal) * depth[..., None]
        stage_normal /= np.linalg.norm(stage_normal, axis=-1, keepdims=True)

        save_rgb(stage_color, out / f"{name}_color.png")
        save_rgb(stage_normal * 0.5 + 0.5, out / f"{name}_normal.png")
        save_gray(stage_rough, out / f"{name}_roughness.png")
        report.append(
            {
                "stage": name,
                "wetness": wetness,
                "pooled_share": float((depth > 0.5).mean()),
                "roughness_mean": float(stage_rough.mean()),
                "roughness_p5_p95": [float(np.percentile(stage_rough, 5)), float(np.percentile(stage_rough, 95))],
                "albedo_mean_srgb": float(stage_color.mean()),
            }
        )
    (out / "stages.json").write_text(json.dumps({"bake_darkening": bake, "stages": report}, indent=1))
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
