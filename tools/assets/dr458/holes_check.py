"""Holes seen from the cockpit eye: compare the `<view>_holes.png` frames of two render_ids.py runs.

    python -I holes_check.py <before dir> <after dir> [max new share] [allowed.json]

Those frames are drawn single-sided with the glass shown, from inside the closed car, so every
pixel should be car or glass: a black (background) pixel is a hole a player would see through.
Per view: hole pixels before and after. FAIL (exit 1) when any view gains more than the limit
(default 0.0005 of the frame, 200 px at 800x500); holes already there before are reported, not failed.
allowed.json's "deleted" objects (deleted on purpose because another file replaces them, such as
the road door cards) are excused where they were: a hole there is closed by the replacement, which
only a check on the assembled car can see.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.spatial import cKDTree

a, b = Path(sys.argv[1]), Path(sys.argv[2])
limit = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0005
deleted = set(json.load(open(sys.argv[4])).get("deleted", [])) if len(sys.argv) > 4 else set()
cols = json.load(open(a / "colours.json"))
names = [n for n in cols if n in deleted]
tree = None
if names:
    lin = np.array([cols[n] for n in names])
    tree = cKDTree(np.where(lin <= 0.0031308, 12.92 * lin, 1.055 * np.power(lin, 1 / 2.4) - 0.055) * 255)
rows, worst = {}, 0.0
for fa in sorted(a.glob("*_holes.png")):
    A = np.asarray(Image.open(fa).convert("RGB")).sum(2) == 0
    B = np.asarray(Image.open(b / fa.name).convert("RGB")).sum(2) == 0
    if tree is not None:
        rgb = np.asarray(Image.open(fa).convert("RGB")).reshape(-1, 3).astype(float)
        dist, _i = tree.query(rgb, distance_upper_bound=4.0)
        B = B & ~np.isfinite(dist).reshape(B.shape)  # a deliberately deleted object was there
    new = float((B & ~A).sum() / B.size)
    rows[fa.stem] = {"holes_before_px": int(A.sum()), "holes_after_px": int(B.sum()), "new_px": int((B & ~A).sum()),
                     "new_share": round(new, 5)}
    worst = max(worst, new)
verdict = "PASS" if worst <= limit else "FAIL"
json.dump({"verdict": verdict, "limit": limit, "views": rows}, open(b / "holes.json", "w"), indent=1)
print(verdict, f"worst new holes {worst:.4%} of the frame (limit {limit:.3%})")
for k, v in rows.items():
    print(f"  {k:24s} before {v['holes_before_px']:6d} px  after {v['holes_after_px']:6d} px  new {v['new_px']:6d}")
sys.exit(0 if verdict == "PASS" else 1)
