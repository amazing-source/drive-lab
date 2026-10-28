"""
Turns a painted hand texture set into SurfaceAppearance maps that take any player's skin tone:
the colour map becomes the skin's detail around white (creases, knuckles, nails, baked
occlusion), which the game tints with SurfaceAppearance.Color set to the avatar's arm colour.

    python -I tools/assets/hand_maps.py <baseColor.png> <normal.png> <occlusionRoughnessMetallic.png> <out dir>

Writes hand_color.png (detail, about 0.9 on average skin, so the tint lands close to the
avatar's colour and highlights keep headroom), hand_normal.png (copied: glTF normal maps use the
same +Y convention as Roblox) and hand_roughness.png (the ORM green channel). Metalness is zero
everywhere in a skin set, so no metalness map is written.
"""

import os
import sys

import numpy as np
from PIL import Image

MEAN_DETAIL = 0.9


def main(base_path, normal_path, orm_path, out):
    os.makedirs(out, exist_ok=True)
    base = np.asarray(Image.open(base_path).convert("RGB")).astype(float) / 255
    orm = np.asarray(Image.open(orm_path).convert("RGB")).astype(float) / 255
    # The skin's own colour: the median over every texel, which the painted skin dominates.
    skin = np.median(base.reshape(-1, 3), axis=0)
    detail = base / skin * orm[..., :1] * MEAN_DETAIL
    Image.fromarray((np.clip(detail, 0, 1) * 255).round().astype(np.uint8)).save(os.path.join(out, "hand_color.png"))
    Image.open(normal_path).convert("RGB").save(os.path.join(out, "hand_normal.png"))
    Image.fromarray((orm[..., 1] * 255).round().astype(np.uint8)).save(os.path.join(out, "hand_roughness.png"))
    print("skin median", (skin * 255).round(), "detail mean", detail.reshape(-1, 3).mean(axis=0).round(3))


if __name__ == "__main__":
    main(*sys.argv[1:5])
