"""Write debadged copies of texture atlases: each listed box is refilled, the source is never touched.

    python -I tools/assets/debadge_atlas.py <spec.json> <out dir> [--sheet <preview.jpg>]

spec.json: {"source_dir": "...", "images": {"<file>": {"boxes": [[x0, y0, x1, y1, "fill"], ...]}}}
in the source's own pixels. Fills: "ring" (median colour of a 6 px ring just outside the box; the
background a mark sits on), "flat_normal" (128, 128, 255: RGB tangent maps only; a two-channel source
stores flat as olive, so use "ring" there), or "#rrggbb". Alpha is kept. Each copy is
written as <stem>_debadged<ext>. The check after writing: inside every box the colour spread is that
of a flat fill (max channel std <= 1), and outside the boxes every pixel equals the source.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

spec = json.loads(Path(sys.argv[1]).read_text())
out = Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
src_dir = Path(spec["source_dir"])
sheet_path = sys.argv[sys.argv.index("--sheet") + 1] if "--sheet" in sys.argv else None
fail, thumbs = [], []
for name, entry in spec["images"].items():
    src = Image.open(src_dir / name)
    mode = src.mode
    a = np.asarray(src.convert("RGBA")).copy()
    h, w = a.shape[:2]
    mask = np.zeros((h, w), bool)
    for x0, y0, x1, y1, fill in entry["boxes"]:
        x0, y0, x1, y1 = max(0, x0), max(0, y0), min(w, x1), min(h, y1)
        if fill == "ring":
            r = 6
            ring = np.zeros((h, w), bool)
            ring[max(0, y0 - r):min(h, y1 + r), max(0, x0 - r):min(w, x1 + r)] = True
            ring[y0:y1, x0:x1] = False
            colour = np.median(a[ring][:, :3], axis=0)
        elif fill == "flat_normal":
            colour = np.array([128, 128, 255])
        else:
            colour = np.array([int(fill[i:i + 2], 16) for i in (1, 3, 5)])
        a[y0:y1, x0:x1, :3] = np.round(colour).astype(np.uint8)
        mask[y0:y1, x0:x1] = True
        if a[y0:y1, x0:x1, :3].reshape(-1, 3).std(0).max() > 1:
            fail.append(f"{name} box {x0},{y0},{x1},{y1}: not a flat fill")
    dst = out / f"{Path(name).stem}_debadged{Path(name).suffix}"
    img = Image.fromarray(a, "RGBA")
    img = img if mode in ("RGBA", "LA", "P") else img.convert("RGB")
    img.save(dst)
    back = np.asarray(Image.open(dst).convert("RGBA"))
    ref = np.asarray(src.convert("RGBA"))
    if (back[~mask] != ref[~mask]).any():
        fail.append(f"{name}: pixels changed outside the boxes")
    print("DEBADGE", name, "->", dst.name, len(entry["boxes"]), "boxes")
    if sheet_path:
        before = src.convert("RGB")
        d = ImageDraw.Draw(before)
        for x0, y0, x1, y1, _f in entry["boxes"]:
            d.rectangle((x0, y0, x1, y1), outline=(0, 255, 255), width=max(2, w // 256))
        for im in (before, img.convert("RGB")):
            t = im.copy()
            t.thumbnail((480, 480))
            thumbs.append((name, t))
if sheet_path and thumbs:
    rows = len(thumbs) // 2
    sheet = Image.new("RGB", (2 * 490, rows * 500), (20, 20, 20))
    d = ImageDraw.Draw(sheet)
    for i, (name, t) in enumerate(thumbs):
        x, y = (i % 2) * 490, (i // 2) * 500
        sheet.paste(t, (x + 5, y + 18))
        d.text((x + 6, y + 3), ("source (boxes)  " if i % 2 == 0 else "debadged  ") + name, fill=(255, 255, 0))
    sheet.save(sheet_path, quality=88)
    print("DEBADGE sheet", sheet_path)
for f in fail:
    print("DEBADGE FAIL", f)
sys.exit(1 if fail else 0)
