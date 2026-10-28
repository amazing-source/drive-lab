"""
Cuts a HUD design image (the owner's ChatGPT design of 2026-10-28: a Lamborghini-style frame
with a 10-segment rev bar, mode, TC/ABS, gear and speed) into what the game animates:

- hud_frame.png: the frame with every rev segment unlit and the live readouts erased (mode name,
  TC, ABS and their underlines, M, gear, speed, the headlight icon); the static marks stay (rev
  numbers, RPM x1000, km/h, the Y, the flags);
- hud_parts.png: white masks the game tints and places: the first, a middle and the last rev
  segment, and the headlight icon, side by side;
- hud_layout.json: where everything goes, as pixel boxes in the cropped frame (each readout's
  box is its glyphs' outline, so live text can be sized to it), and each part's rectangle in the
  parts atlas.

The frame is cropped to what is drawn and brought to 1024 pixels wide, Roblox's limit.

    python -I tools/assets/hud_layers.py <design.png> <out dir>

Segments are found as the bright shapes in the bar's band, separated by the design's dark
slanted gaps; segments 8 and 9 are unlit in the design, so they take the middle shape moved
along by the bar's own spacing.
"""

import json
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

BAND = (190, 250)
# Readouts drawn live in game, erased from the frame: (x0, y0, x1, y1) in design pixels.
ERASE = {
    "mode": (305, 378, 548, 434),
    "tcText": (338, 474, 412, 514),
    "tcLine": (325, 525, 427, 541),
    "absText": (552, 474, 656, 514),
    "absLine": (550, 525, 661, 541),
    "box": (1052, 330, 1112, 366),
    "gear": (945, 366, 1172, 590),
    "speed": (1385, 345, 1828, 497),
    # The top of the last digit runs past the speed's box, above "km/h".
    "speedEdge": (1826, 345, 1850, 436),
    "light": (1800, 512, 1880, 574),
}
# Not in the design: the indicators, drawn only while they blink, either side of the light icon.
INDICATORS = {"indicatorLeft": (1755, 517, 1790, 569), "indicatorRight": (1890, 517, 1925, 569)}
UNLIT = np.array([58.0, 57.0, 56.0])


def segments(rgba):
    rgb, alpha = rgba[..., :3].astype(float), rgba[..., 3]
    lum = rgb.mean(axis=2)
    y0, y1 = BAND
    bright = np.zeros(lum.shape, bool)
    bright[y0:y1, 300:1850] = (alpha[y0:y1, 300:1850] > 200) & (
        (lum[y0:y1, 300:1850] > 55) | ((rgb[y0:y1, 300:1850, 0] > 150) & (rgb[y0:y1, 300:1850, 1] < 90))
    )
    label = np.zeros(lum.shape, int)
    found = []
    for y in range(y0, y1):
        for x in range(300, 1850):
            if not bright[y, x] or label[y, x]:
                continue
            index = len(found) + 1
            queue, cells = deque([(y, x)]), []
            label[y, x] = index
            while queue:
                cy, cx = queue.popleft()
                cells.append((cy, cx))
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = cy + dy, cx + dx
                    if y0 <= ny < y1 and 300 <= nx < 1850 and bright[ny, nx] and not label[ny, nx]:
                        label[ny, nx] = index
                        queue.append((ny, nx))
            ys, xs = zip(*cells)
            found.append({"box": (min(xs), min(ys), max(xs) + 1, max(ys) + 1), "size": len(cells)})
    kept = sorted([(f["box"][0], i + 1, f) for i, f in enumerate(found) if f["size"] > 800])
    for _, index, f in kept:
        f["label"] = index
    return [f for _, _, f in kept], label


def saturation(rgb):
    high, low = rgb.max(axis=2), rgb.min(axis=2)
    return np.where(high > 0, (high - low) / np.maximum(high, 1), 0)


# Readouts inside the black hexagon: white text keyed out by colour, so the yellow edge that
# crosses their box is kept (a row blend there smeared it into a vertical streak).
KEYED = ("gear", "box")


def erase_keyed(rgba, box):
    x0, y0, x1, y1 = box
    piece = rgba[y0:y1, x0:x1]
    rgb = piece[..., :3].astype(float)
    lum, neutral = rgb.mean(axis=2), saturation(rgb) < 0.35
    text = (lum > 40) & neutral
    # The digits carry a near-black outline a shade off the black around them, and an
    # antialiased rim: both go with the text, or the erased digit still shows as a ghost.
    for _ in range(2):
        grown = text.copy()
        grown[1:] |= text[:-1]
        grown[:-1] |= text[1:]
        grown[:, 1:] |= text[:, :-1]
        grown[:, :-1] |= text[:, 1:]
        text = grown
    text = (text | (lum < 12)) & neutral
    dark = rgb[~text & (lum < 40)] if (~text & (lum < 40)).any() else rgb[lum < 12]
    fill = np.median(dark, axis=0) if len(dark) else np.zeros(3)
    piece[..., :3][text] = fill.round().astype(np.uint8)


def erase(rgba, box):
    # Each column refilled by a straight blend between the rows just above and below.
    x0, y0, x1, y1 = box
    above, below = rgba[y0 - 1, x0:x1].astype(float), rgba[y1, x0:x1].astype(float)
    for row in range(y0, y1):
        share = (row - y0 + 1) / (y1 - y0 + 1)
        rgba[row, x0:x1] = (above * (1 - share) + below * share).round()


def mask(rgba, box, only=None):
    """A white copy of the coloured shape in `box`: alpha from its colour against the dark frame,
    kept to `only` (a boolean mask, grown by two pixels for the antialiased edge) when given, so
    a slanted segment's box does not carry a sliver of its neighbour."""
    x0, y0, x1, y1 = box
    piece = rgba[y0:y1, x0:x1].astype(float)
    sat = saturation(piece[..., :3])
    value = piece[..., :3].max(axis=2) / 255
    # Dark pixels of the frame can be saturated too; only bright colour belongs to the shape.
    shape = np.clip((sat - 0.25) / 0.45, 0, 1) * np.clip((value - 0.2) / 0.25, 0, 1) * (piece[..., 3] / 255)
    if only is not None:
        keep = only[y0:y1, x0:x1].copy()
        for _ in range(2):
            grown = keep.copy()
            grown[1:] |= keep[:-1]
            grown[:-1] |= keep[1:]
            grown[:, 1:] |= keep[:, :-1]
            grown[:, :-1] |= keep[:, 1:]
            keep = grown
        shape = shape * keep
    out = np.zeros(piece.shape)
    out[..., :3] = 255 * np.clip(value / max(value[shape > 0.5].mean(), 1e-6), 0, 1)[..., None]
    out[..., 3] = 255 * shape
    return out.round().astype(np.uint8)


def main(design, out):
    os.makedirs(out, exist_ok=True)
    rgba = np.asarray(Image.open(design).convert("RGBA")).copy()
    height, width = rgba.shape[:2]
    found, label = segments(rgba)
    if len(found) != 10:
        raise SystemExit(f"found {len(found)} rev segments, expected 10")
    boxes = [f["box"] for f in found]
    # Segments 8 and 9 have no lit shape in the design: the middle shape, moved along.
    spacing = (boxes[6][0] - boxes[1][0]) / 5
    middle = boxes[1]
    for index in (7, 8):
        shift = round(boxes[1][0] + spacing * (index - 1)) - middle[0]
        boxes[index] = (middle[0] + shift, middle[1], middle[2] + shift, middle[3])

    own = {"first": found[0]["label"], "middle": found[1]["label"], "last": found[9]["label"]}
    parts_src = {"first": boxes[0], "middle": boxes[1], "last": boxes[9], "light": ERASE["light"]}
    masks = {
        name: mask(rgba, box, (label == own[name]) if name in own else None) for name, box in parts_src.items()
    }
    atlas_w = sum(m.shape[1] for m in masks.values()) + 4 * len(masks)
    atlas_h = max(m.shape[0] for m in masks.values())
    atlas = np.zeros((atlas_h, atlas_w, 4), np.uint8)
    cursor, rects = 0, {}
    for name, piece in masks.items():
        h, w = piece.shape[:2]
        atlas[:h, cursor : cursor + w] = piece
        rects[name] = [cursor, 0, w, h]
        cursor += w + 4
    Image.fromarray(atlas, "RGBA").save(os.path.join(out, "hud_parts.png"))

    # The frame: every segment unlit, then the live readouts erased.
    y0, y1 = BAND
    rgb = rgba[..., :3].astype(float)
    sat = saturation(rgb)
    weight = np.zeros(sat.shape)
    weight[y0:y1, 340:1820] = np.clip((sat[y0:y1, 340:1820] - 0.25) / 0.45, 0, 1)
    rgba[..., :3] = (rgb * (1 - weight[..., None]) + UNLIT * weight[..., None]).round().astype(np.uint8)
    before = rgba.copy()
    for name, box in ERASE.items():
        (erase_keyed if name in KEYED else erase)(rgba, box)
    # Each readout's own outline: the pixels its erasing changed. Text set live is sized to its
    # capitals, so it needs the glyphs' box, not the padded box that was cleared.
    glyphs = {}
    for name, (x0, y0, x1, y1) in ERASE.items():
        changed = np.abs(before[y0:y1, x0:x1, :3].astype(int) - rgba[y0:y1, x0:x1, :3]).max(axis=2) > 40
        ys, xs = np.nonzero(changed)
        glyphs[name] = (x0 + xs.min(), y0 + ys.min(), x0 + xs.max() + 1, y0 + ys.max() + 1)
    edge = glyphs.pop("speedEdge")
    speed = glyphs["speed"]
    glyphs["speed"] = (speed[0], min(speed[1], edge[1]), max(speed[2], edge[2]), max(speed[3], edge[3]))
    glyphs.update(INDICATORS)

    # Cropped to the drawn frame, so the transparent margin costs no resolution, then brought
    # to Roblox's 1024-pixel limit here rather than by the upload (premultiplied, so the
    # transparent edge does not bleed dark).
    ys, xs = np.nonzero(rgba[..., 3] > 8)
    left, top = max(xs.min() - 2, 0), max(ys.min() - 2, 0)
    right, bottom = min(xs.max() + 3, width), min(ys.max() + 3, height)
    frame = Image.fromarray(rgba[top:bottom, left:right], "RGBA")
    width, height = frame.size
    if width > 1024:
        frame = frame.convert("RGBa").resize((1024, round(1024 * height / width)), Image.LANCZOS).convert("RGBA")
    frame.save(os.path.join(out, "hud_frame.png"))
    boxes = [(x0 - left, y0 - top, x1 - left, y1 - top) for x0, y0, x1, y1 in boxes]
    readouts = {name: [int(v) for v in (x0 - left, y0 - top, x1 - left, y1 - top)] for name, (x0, y0, x1, y1) in glyphs.items()}

    # Boxes are { x0, y0, x1, y1 } in the cropped frame's pixels, before it is brought to 1024.
    layout = {
        "size": [width, height],
        "segments": [[int(v) for v in box] for box in boxes],
        "readouts": readouts,
        "parts": rects,
        "atlas": [atlas_w, atlas_h],
    }
    json.dump(layout, open(os.path.join(out, "hud_layout.json"), "w"), indent=1)
    print(json.dumps(layout))


if __name__ == "__main__":
    main(*sys.argv[1:3])
