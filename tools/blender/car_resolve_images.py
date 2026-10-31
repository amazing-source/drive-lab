"""Make every image in the open blend resolve from wherever the blend now lives.

As a module: resolve(roots) -> (fixed, missing). As a script, run before another one:

    blender -b <file.blend> -P tools/blender/car_resolve_images.py -P <render.py> -- <render args>

Roots then come from DL_IMAGE_ROOTS (separated by os.pathsep). Each image path is made absolute;
one that does not exist is looked up by file name under the roots (first root first). Packed and
library-linked images are left alone.
"""
import os
from pathlib import Path

import bpy

EXTS = {".png", ".jpg", ".jpeg", ".tga", ".tif", ".tiff", ".exr", ".bmp", ".dds", ".webp"}


def _index(roots):
    found = {}
    for root in roots:
        root = Path(root)
        if not root.is_dir():
            continue
        for p in root.rglob("*"):
            if p.suffix.lower() in EXTS:
                found.setdefault(p.name.lower(), p)
    return found


def resolve(roots):
    index = None
    fixed, missing = [], []
    for img in bpy.data.images:
        if img.source not in {"FILE", "SEQUENCE", "TILED"} or img.packed_file or img.library:
            continue
        p = Path(bpy.path.abspath(img.filepath))
        if p.is_file():
            if img.filepath != str(p):
                img.filepath = str(p)
            continue
        if index is None:
            index = _index(roots)
        hit = index.get(p.name.lower())
        if hit:
            img.filepath = str(hit)
            img.reload()
            fixed.append((img.name, str(hit)))
        else:
            missing.append((img.name, img.filepath))
    return fixed, missing


if __name__ == "__main__":
    roots = [r for r in os.environ.get("DL_IMAGE_ROOTS", "").split(os.pathsep) if r]
    f, m = resolve(roots)
    print(f"RESOLVE fixed {len(f)}, missing {len(m)}", m[:8])
