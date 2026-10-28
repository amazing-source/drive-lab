"""
Prepares the hero car's texture maps for Roblox SurfaceAppearances, from the debadged
source textures:

    python -I tools/assets/hero_car_maps.py <clean texture dir> <out dir>

The source game names its maps by purpose. Its DiffuseAOSO maps carry colour with ambient
occlusion baked in, and something other than opacity in alpha, so colour maps are written
opaque (SurfaceAppearance's default Overlay mode would otherwise show the part's Color through
them). Emissive maps are coloured, while Roblox lights a SurfaceAppearance from its ColorMap
through a grayscale mask, so where a surface glows its colour is merged into the ColorMap and
its brightness becomes the EmissiveMask. Roblox has no numeric roughness or metalness on a
SurfaceAppearance, so small uniform maps stand in for those values.
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image

PREFIX = "Lamborghini_AventadorSVJ_2019_"
UNIFORM_SIZE = 16
ROUGHNESS = {"rough_glossy": 0.12, "rough_satin": 0.38, "rough_matte": 0.7, "rough_rubber": 0.92}
METALNESS = {"metal_none": 0.0, "metal_full": 1.0}
# Maps with colour (and a normal map where the source has one).
COLOUR_SETS = {
    "interior": ("InteriorA_DiffuseAOSO", "InteriorA_Normal", "InteriorA_Emissive"),
    "engine": ("EngineA_DiffuseAOSO", "EngineA_Normal", None),
    "grille1": ("Grille1A_DiffuseAOSO", "Grille1A_Normal", None),
    "grille2": ("Grille2A_DiffuseAOSO", "Grille2A_Normal", None),
    "grille3": ("Grille3A_DiffuseAOSO", "Grille3A_Normal", None),
    "wheel": ("Wheel2A_DiffuseAOSO", "Wheel2A_Normal", None),
    "light": ("LightA_Diffuse", None, "LightA_Emissive"),
}
CARBON = ("common_carbon05_black_diff.png", "common_carbon05_norm.png")
# The source game's material masks: red is metalness, green is gloss (so roughness is its
# inverse); MaterialOpacity maps also carry opacity in blue, unused here. Read off a channel
# split of the interior map (model_candidates/svj_ddiaz_renders/interior_channels.jpg): metal
# vents, speaker grilles and the glossy screen are bright in red and green, leather is not.
MATERIAL_MASKS = {
    "interior": "InteriorA_MaterialOpacity",
    "engine": "EngineA_MaterialOpacity",
    "light": "LightA_Material",
    "wheel": "Wheel2A_Material",
    "grille2": "Grille2A_Material",
    "grille3": "Grille3A_Material",
}
# Brand shapes still present in the material masks, painted over like the colour maps.
MASK_BOXES = {"interior": (274, 94, 396, 212)}
# Gloss maps from this game run dim; roughness = 1 - gloss ** GLOSS_CURVE keeps leather satin
# and lets screens and metal read as polished.
GLOSS_CURVE = 0.8


def load(path: Path) -> np.ndarray:
    return np.array(Image.open(path).convert("RGBA"))


def save(pixels: np.ndarray, path: Path):
    Image.fromarray(pixels.astype(np.uint8), "RGBA").save(path)


def uniform(value: float) -> np.ndarray:
    level = round(value * 255)
    return np.full((UNIFORM_SIZE, UNIFORM_SIZE, 4), (level, level, level, 255), dtype=np.uint8)


def main():
    source, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)

    for name, value in {**ROUGHNESS, **METALNESS}.items():
        save(uniform(value), out / f"{name}.png")

    for label, (colour_name, normal_name, emissive_name) in COLOUR_SETS.items():
        colour = load(source / f"{PREFIX}{colour_name}.png")
        colour[..., 3] = 255
        if emissive_name:
            emissive = Image.open(source / f"{PREFIX}{emissive_name}.png").convert("RGB")
            emissive = np.array(emissive.resize(colour.shape[1::-1], Image.BILINEAR)).astype(np.float32)
            brightness = emissive.max(axis=2)
            glowing = brightness > 24
            colour[glowing, :3] = np.maximum(colour[glowing, :3], emissive[glowing])
            mask = np.zeros_like(colour)
            mask[..., 0] = mask[..., 1] = mask[..., 2] = np.clip(brightness, 0, 255)
            mask[..., 3] = 255
            save(mask, out / f"{label}_emissive.png")
        save(colour, out / f"{label}_color.png")
        if normal_name:
            normal = load(source / f"{PREFIX}{normal_name}.png")
            normal[..., 3] = 255
            save(normal, out / f"{label}_normal.png")

    for label, mask_name in MATERIAL_MASKS.items():
        mask = load(source / f"{PREFIX}{mask_name}.png").astype(np.float32)
        if label in MASK_BOXES:
            x0, y0, x1, y1 = MASK_BOXES[label]
            ring = np.concatenate([mask[y0 - 3:y0, x0:x1].reshape(-1, 4), mask[y1:y1 + 3, x0:x1].reshape(-1, 4)])
            mask[y0:y1, x0:x1] = np.median(ring, axis=0)
        gloss = mask[..., 1] / 255.0
        roughness = (1.0 - gloss ** GLOSS_CURVE) * 255.0
        metalness = mask[..., 0]
        for kind, channel in (("roughness", roughness), ("metalness", metalness)):
            pixels = np.zeros(mask.shape, dtype=np.uint8)
            pixels[..., 0] = pixels[..., 1] = pixels[..., 2] = np.clip(channel, 0, 255)
            pixels[..., 3] = 255
            save(pixels, out / f"{label}_{kind}.png")

    carbon = load(source / CARBON[0])
    carbon[..., 3] = 255
    save(carbon, out / "carbon_color.png")
    carbon_normal = load(source / CARBON[1])
    carbon_normal[..., 3] = 255
    save(carbon_normal, out / "carbon_normal.png")

    for path in sorted(out.glob("*.png")):
        print(path.name, Image.open(path).size)


if __name__ == "__main__":
    main()
