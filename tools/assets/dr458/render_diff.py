"""Compare two render_ids.py runs (same seed) and fail when visible geometry changed.

    python -I render_diff.py <before dir> <after dir> <out dir> [max changed share] [allowed.json]

A pixel changed when its object colour differs. allowed.json ({"deleted": [names], "pairs": [[a, b]],
"revealed": [names]}) excuses pixels of objects deleted on purpose, swaps between the two members of
a depth-fight pair that was resolved (either may win there), and pixels of a "revealed" object
(one trimmed on purpose where it covered real parts) that now show another object, never the
background; every other changed pixel counts as visible geometry lost
or moved, and is attributed to the object that was there before. Per view: the share of car pixels (non-black in
either image) that changed. FAIL (exit 1) when any view exceeds the limit (default 0.002, 0.2 %).
Writes a diff image per view (changed pixels in magenta over the after image) and diff.json.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.spatial import cKDTree

a, b, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
limit = float(sys.argv[4]) if len(sys.argv) > 4 else 0.002
allowed = json.load(open(sys.argv[5])) if len(sys.argv) > 5 else {"deleted": [], "pairs": []}
deleted = set(allowed.get("deleted", []))
pairs = {frozenset(p) for p in allowed.get("pairs", [])}
revealed = set(allowed.get("revealed", []))


def palette(d):
    cols = json.load(open(d / "colours.json"))
    names = list(cols)
    lin = np.array([cols[n] for n in names])
    srgb = np.where(lin <= 0.0031308, 12.92 * lin, 1.055 * np.power(lin, 1 / 2.4) - 0.055) * 255
    return names, srgb


def ident(img, names, srgb):
    """Object index per pixel: the nearest palette colour within 4 levels (render dither), else -1."""
    flat = img.reshape(-1, 3).astype(float)
    dist, idx = cKDTree(srgb).query(flat, distance_upper_bound=4.0)
    out = np.where(np.isfinite(dist), idx, -1)
    out[flat.sum(1) == 0] = -1
    return out


na, pa = palette(a)
nb, pb = palette(b)
losses = {}
out.mkdir(parents=True, exist_ok=True)
rows, worst = {}, 0.0
for fa in sorted(f for f in a.glob("*.png") if not f.stem.endswith("_holes")):
    A = np.asarray(Image.open(fa).convert("RGB")).astype(int)
    B = np.asarray(Image.open(b / fa.name).convert("RGB")).astype(int)
    car = (A.sum(2) > 0) | (B.sum(2) > 0)
    ch = np.abs(A - B).sum(2) > 6
    ia, ib = ident(A, na, pa), ident(B, nb, pb)
    lost = np.zeros(ch.size, bool)
    for k in np.flatnonzero(ch.ravel()):
        was = na[ia[k]] if ia[k] >= 0 else None
        now = nb[ib[k]] if ib[k] >= 0 else None
        if was in deleted or (was and now and frozenset((was, now)) in pairs) or (was in revealed and now):
            continue
        lost[k] = True
        losses[was] = losses.get(was, 0) + 1
    ch = lost.reshape(ch.shape)
    share = float(ch.sum() / max(1, car.sum()))
    rows[fa.stem] = {"changed_px": int(ch.sum()), "car_px": int(car.sum()), "share": round(share, 5)}
    worst = max(worst, share)
    vis = B.astype(np.uint8).copy()
    vis[ch] = (255, 0, 255)
    Image.fromarray(vis).save(out / f"diff_{fa.stem}.png")
verdict = "PASS" if worst <= limit else "FAIL"
json.dump({"verdict": verdict, "limit": limit, "worst": round(worst, 5), "views": rows,
           "lost_px_by_object": dict(sorted(losses.items(), key=lambda kv: -kv[1]))}, open(out / "diff.json", "w"), indent=1)
print(verdict, f"worst view {worst:.4%} changed (limit {limit:.2%})")
for k, v in rows.items():
    print(f"  {k:10s} {v['share']:.4%} ({v['changed_px']} of {v['car_px']} px)")
for n, c in sorted(losses.items(), key=lambda kv: -kv[1])[:15]:
    print(f"  lost {c:7d} px  {n}")
sys.exit(0 if verdict == "PASS" else 1)
