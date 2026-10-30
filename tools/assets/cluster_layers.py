"""
Cuts a car's instrument-cluster texture into the layers the live cluster animates: the static
face with the drive-mode label erased (the game draws the live mode there), and the rev counter's
cells lit, in white (tinted per drive mode in game) and in red (the red zone). Prints the dial's
geometry, measured from the image, for the car's face (Config/Cars/<Car>/Cluster).

    python -I tools/assets/cluster_layers.py <display.png> <out dir> [--erase x0,y0,x1,y1 ...]

Built for the Aventador SVJ texture of the Assetto Corsa mod (512 x 256, read out of the .kn5):
a rev counter of 20 cells between an outer rim and an inner line, 0 to 10,000 rpm.
- The dial centre and radius come from a least-squares circle through the rim's top edge.
- Cell edges are the dark separators, found as minima of the band's brightness by angle.
- The lit layers are square and centred on the dial, so a gradient rotated about the image's
  centre wipes them round the dial (see Rules/Cluster.wipeRotation).
"""

import json
import os
import sys

import numpy as np
from PIL import Image

CELL_COUNT = 20
DIAL_MAX_RPM = 10000
RED_FROM_RPM = 8500
# Radial extent of the cells, inward from the rim, pixels.
CELL_OUTER, CELL_INNER = 3.5, 15.5


def rim_circle(rgb):
    r, b = rgb[..., 0], rgb[..., 2]
    warm = (r > 110) & (r - b > 60)
    points = []
    for x in range(rgb.shape[1]):
        rows = np.nonzero(warm[: rgb.shape[0] * 55 // 100, x])[0]
        if len(rows):
            points.append((x, rows[0]))
    pts = np.array(points, float)
    # Refit without the points far off the circle: warm pixels of the side gauges, not the rim.
    keep = np.ones(len(pts), bool)
    for _ in range(8):
        x, y = pts[keep, 0], pts[keep, 1]
        solution, *_ = np.linalg.lstsq(np.c_[2 * x, 2 * y, np.ones_like(x)], x**2 + y**2, rcond=None)
        cx, cy = solution[0], solution[1]
        radius = np.sqrt(solution[2] + cx**2 + cy**2)
        keep = np.abs(np.hypot(pts[:, 0] - cx, pts[:, 1] - cy) - radius) < 2
    residual = np.hypot(pts[keep, 0] - cx, pts[keep, 1] - cy) - radius
    return cx, cy, radius, residual.std()


def bilinear(img, x, y):
    x0 = np.clip(np.floor(x).astype(int), 0, img.shape[1] - 2)
    y0 = np.clip(np.floor(y).astype(int), 0, img.shape[0] - 2)
    fx, fy = (x - x0)[..., None], (y - y0)[..., None]
    if img.ndim == 2:
        fx, fy = fx[..., 0], fy[..., 0]
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy)
            + img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)


def separators(lum, cx, cy, radius):
    angles = np.arange(180, 360, 0.25)
    t = np.radians(angles)
    band = np.mean([bilinear(lum, cx + (radius - k) * np.cos(t), cy + (radius - k) * np.sin(t))
                    for k in range(5, 12)], axis=0)
    lit = angles[band > 12]
    start, end = lit.min(), lit.max()
    found = []
    for i in range(2, len(angles) - 2):
        window = band[max(0, i - 8): i + 9]
        if start < angles[i] < end and band[i] == band[i - 2: i + 3].min() and band[i] < 0.5 * window.max():
            found.append(float(angles[i]))
    # Shading near the band's ends makes shallow minima: a separator sits a cell's width apart.
    cell = (end - start) / CELL_COUNT
    edges, last = [], start
    for angle in found:
        if angle - last > 0.6 * cell and end - angle > 0.6 * cell:
            edges.append(angle)
            last = angle
    return float(start), float(end), edges


def erase(rgb, box):
    # Each column is refilled by a straight blend between the pixels just above and below.
    x0, y0, x1, y1 = box
    above, below = rgb[y0 - 1, x0:x1], rgb[y1, x0:x1]
    for row in range(y0, y1):
        share = (row - y0 + 1) / (y1 - y0 + 1)
        rgb[row, x0:x1] = above * (1 - share) + below * share


def lit_layers(lum, cx, cy, radius, start, sweep, size):
    half = size / 2
    v, u = np.mgrid[0:size, 0:size].astype(float)
    x, y = cx - half + u + 0.5, cy - half + v + 0.5
    distance = np.hypot(x - cx, y - cy)
    angle = np.degrees(np.arctan2(y - cy, x - cx)) % 360
    inside = (x >= 0) & (x < lum.shape[1] - 1) & (y >= 0) & (y < lum.shape[0] - 1)
    source = np.where(inside, bilinear(lum, np.clip(x, 0, lum.shape[1] - 1.01), np.clip(y, 0, lum.shape[0] - 1.01)), 0)
    # Soft radial edges, then the art's own separators: dark pixels stay unlit.
    radial = np.clip(distance - (radius - CELL_INNER), 0, 1) * np.clip((radius - CELL_OUTER) - distance, 0, 1)
    along = (angle - start) % 360
    within = along <= sweep
    alpha = radial * within * np.clip((source - 8) / 12, 0, 1)
    # Brightest at the rim, as the unlit cells' own shading runs.
    shade = np.clip(0.55 + 0.45 * (distance - (radius - CELL_INNER)) / (CELL_INNER - CELL_OUTER), 0.55, 1)
    red = along >= sweep * RED_FROM_RPM / DIAL_MAX_RPM
    white = np.dstack([shade * 255] * 3 + [alpha * (~red) * 255])
    reds = np.dstack([shade * 235, shade * 38, shade * 30, alpha * red * 255])
    return white.astype(np.uint8), reds.astype(np.uint8)


def main(args):
    source, out = args[0], args[1]
    boxes = [tuple(int(v) for v in a.split(",")) for a in args[2:] if a != "--erase"]
    rgb = np.asarray(Image.open(source).convert("RGB")).astype(float)
    lum = rgb.mean(axis=2)
    cx, cy, radius, spread = rim_circle(rgb)
    start, end, edges = separators(lum, cx, cy, radius)
    sweep = end - start
    if len(edges) != CELL_COUNT - 1:
        raise SystemExit(f"found {len(edges)} separators, expected {CELL_COUNT - 1}: {edges}")
    spacing = np.diff([start] + edges + [end])
    os.makedirs(out, exist_ok=True)
    base = rgb.copy()
    for box in boxes:
        erase(base, box)
    Image.fromarray(base.round().astype(np.uint8)).save(os.path.join(out, "cluster_base.png"))
    size = int(np.ceil(radius + 3)) * 2
    white, red = lit_layers(lum, cx, cy, radius, start, sweep, size)
    Image.fromarray(white, "RGBA").save(os.path.join(out, "cluster_lit.png"))
    Image.fromarray(red, "RGBA").save(os.path.join(out, "cluster_red.png"))
    print(json.dumps({
        "image": [rgb.shape[1], rgb.shape[0]],
        "centre": [round(cx, 2), round(cy, 2)],
        "radius": round(radius, 2),
        "rimFitSd": round(spread, 2),
        "startDeg": start,
        "sweepDeg": sweep,
        "cellDeg": [round(float(spacing.min()), 2), round(float(spacing.max()), 2)],
        "litSize": size,
    }, indent=1))


if __name__ == "__main__":
    main(sys.argv[1:])
