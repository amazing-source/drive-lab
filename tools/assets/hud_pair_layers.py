"""
Cuts a HUD design delivered as two pixel-aligned exports (a static frame with every live part left
out, and the same frame with example values drawn) plus their cut-out regions, into what the game
animates:

- hud_frame.png: the static export, cropped to what is drawn and brought to 1024 pixels wide,
  Roblox's limit;
- hud_parts.png: white masks the game tints: one rev segment (every segment is the same shape),
  each region named as a part (pictograms, indicator arrows), cut from the full export with 2 px
  of transparent padding; and, with --font, the gear's and the speed's glyphs (0-9, N, R) set in
  that face, narrowed, their bars thickened and slanted as the drawn digits are;
- hud_layout.json: every box in the cropped frame's pixels, before it is brought to 1024: the
  segments and parts as they are placed (padded, so a mask lands on its own pixels), each live
  text's glyph outline (what the full export draws there), each part's and glyph's rectangle in
  the atlas, and the glyphs' metrics;
- frame_on_grey.png, recomposed.png and glyphs_preview.png: previews to check before uploading.

    python -I tools/assets/hud_pair_layers.py <static.png> <full.png> <regions.json> <out dir>
        [--font <face.ttf> --height <px> --width <share> --bars <share> --gap <share>]

It refuses a pair that does not line up: the two exports must share their size and alpha, differ
only inside the regions, and every lit segment must be pixel-identical. Parts recomposed over the
frame in their drawn colours must match the full export.

The glyphs' slant is measured, not given: the mean of the drawn gear's and speed's straight edges.
--height is their capitals in atlas pixels; --width narrows them (a share of the face's own width)
so three digits fit beside the gear; --bars thickens their horizontal strokes by that share of the
height, toward the drawn digits' weight; --gap is the space between two digits, a share of the
narrowed height. Digits share one cell, the widest digit's, so the speed does not shift as it
changes.
"""

import argparse
import json
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

PAD = 2
GAP = 4
# Levels of difference between the exports that count as drawn ink.
INK = 8
LIMIT = 1024
# Regions drawn as live text in game, and the parts cut as masks.
TEXTS = ("mode_value", "gear_auto", "gear_value", "speed_value", "TC", "ABS")
PARTS = ("mode_icon", "headlight", "indicator_left", "indicator_right")
GLYPHS = "0123456789NR"
DIGITS = "0123456789"
# Glyphs are drawn this many times larger, then brought down: smooth slanted edges.
SUPER = 4


def box_of(region):
    x, y, w, h = region
    return (x, y, x + w, y + h)


def ink_box(ink, box):
    x0, y0, x1, y1 = box
    ys, xs = np.nonzero(ink[y0:y1, x0:x1])
    if len(xs) == 0:
        return None
    return (x0 + int(xs.min()), y0 + int(ys.min()), x0 + int(xs.max()) + 1, y0 + int(ys.max()) + 1)


def split_rows(ink, box):
    """A text with a line under it: the glyph rows and the line rows, split at the widest empty run."""
    x0, y0, x1, y1 = ink_box(ink, box)
    rows = ink[y0:y1, x0:x1].any(axis=1)
    best, start = (0, 0), None
    for index, filled in enumerate(list(rows) + [True]):
        if not filled and start is None:
            start = index
        elif filled and start is not None:
            if index - start > best[1] - best[0]:
                best = (start, index)
            start = None
    if best == (0, 0):
        raise SystemExit(f"no gap between the text and its line in {box}")
    text = ink_box(ink, (x0, y0, x1, y0 + best[0]))
    line = ink_box(ink, (x0, y0 + best[1], x1, y1))
    return text, line


def mask(full, box, background, ink):
    """A white copy of the shape drawn in `box`: alpha is how far each pixel went from the panel's
    colour toward the shape's own, so an antialiased edge keeps its coverage."""
    x0, y0, x1, y1 = box
    piece = full[y0:y1, x0:x1, :3].astype(float)
    distance = np.abs(piece - background).max(axis=2)
    colour = piece.reshape(-1, 3)[distance.argmax()]
    span = np.abs(colour - background).max()
    alpha = np.clip(distance / span, 0, 1) * ink[y0:y1, x0:x1]
    out = np.zeros((y1 - y0, x1 - x0, 4), np.uint8)
    out[..., :3] = 255
    out[..., 3] = (alpha * 255).round().astype(np.uint8)
    return out, colour


def grow(ink, steps):
    for _ in range(steps):
        grown = ink.copy()
        grown[1:] |= ink[:-1]
        grown[:-1] |= ink[1:]
        grown[:, 1:] |= ink[:, :-1]
        grown[:, :-1] |= ink[:, 1:]
        ink = grown
    return ink


def check_pair(static, full, boxes):
    if static.shape != full.shape:
        raise SystemExit(f"the exports differ in size: {static.shape} and {full.shape}")
    if not (static[..., 3] == full[..., 3]).all():
        raise SystemExit("the exports differ in alpha: they are not the same frame")
    ink = np.abs(full[..., :3].astype(int) - static[..., :3]).max(axis=2) > INK
    inside = np.zeros(ink.shape, bool)
    for box in boxes:
        x0, y0, x1, y1 = box
        inside[y0:y1, x0:x1] = True
    stray = ink & ~inside
    if stray.any():
        ys, xs = np.nonzero(stray)
        raise SystemExit(f"{len(xs)} drawn pixels lie outside every region, e.g. at ({xs[0]}, {ys[0]})")
    return ink


def edge_shear(full, background, box, side, rows):
    """The slant of a drawn glyph's straight edge: x of the half-coverage crossing on each row,
    fitted by a line. Returns the shear (x moved right per pixel up) and the worst residual."""
    x0, _, x1, _ = box
    span = np.abs(full[..., :3].astype(float) - background).max()
    points = []
    for y in rows:
        cover = np.clip(np.abs(full[y, x0:x1, :3].astype(float) - background).max(axis=1) / span, 0, 1)
        index = np.nonzero(cover >= 0.5)[0]
        if len(index) == 0:
            continue
        if side == "left":
            i = index[0]
            before = cover[i - 1] if i > 0 else 0.0
            x = x0 + i - 0.5 + (0.5 - before) / max(cover[i] - before, 1e-6)
        else:
            i = index[-1]
            after = cover[i + 1] if i + 1 < len(cover) else 0.0
            x = x0 + i + 0.5 + (cover[i] - 0.5) / max(cover[i] - after, 1e-6)
        points.append((y, x))
    points = np.array(points)
    slope, offset = np.polyfit(points[:, 0], points[:, 1], 1)
    residual = np.abs(points[:, 1] - (slope * points[:, 0] + offset)).max()
    return -slope, residual


def measure_shear(full, background, ink, named):
    """The drawn digits' slant: both straight sides of the speed's glyph and of the gear's, from 45%
    to 80% of their height, clear of a squared digit's rounded corners and of a 1's flag."""
    shears = []
    for name in ("speed_value", "gear_value"):
        x0, y0, x1, y1 = ink_box(ink, named[name])
        rows = range(y0 + (y1 - y0) * 45 // 100, y0 + (y1 - y0) * 80 // 100)
        for side in ("left", "right"):
            shear, residual = edge_shear(full, background, (x0 - PAD, y0, x1 + PAD, y1), side, rows)
            print(f"{name} {side} edge: shear {shear:.4f} ({np.degrees(np.arctan(shear)):.2f} deg), worst residual {residual:.2f} px")
            if residual > 1:
                raise SystemExit(f"the {name}'s {side} edge is not straight enough to measure a slant")
            shears.append(shear)
    return float(np.mean(shears))


class Face:
    def __init__(self, path):
        self.font = ImageFont.truetype(path, 400 * SUPER)
        _, box = self.raw("0")
        self.top, self.bottom = box[1], box[3]

    def raw(self, char):
        image = Image.new("L", (1200 * SUPER, 1000 * SUPER), 0)
        ImageDraw.Draw(image).text((100 * SUPER, 100 * SUPER), char, font=self.font, fill=255)
        alpha = np.asarray(image).astype(np.float32) / 255
        ys, xs = np.nonzero(alpha > 0.02)
        return alpha, (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)

    def upright(self, char):
        """The glyph's ink, cropped to its width and to the digits' height, alpha 0 to 1."""
        alpha, box = self.raw(char)
        if box[1] < self.top - SUPER or box[3] > self.bottom + SUPER:
            raise SystemExit(f"{char} reaches outside the digits' height")
        return alpha[self.top : self.bottom, box[0] : box[2]]

    def aspect(self, char):
        piece = self.upright(char)
        return piece.shape[1] / piece.shape[0]


def resize(alpha, width, height):
    image = Image.fromarray(alpha, "F").resize((max(1, round(width)), max(1, round(height))), Image.LANCZOS)
    return np.asarray(image).clip(0, 1)


def thicken_bars(alpha, steps):
    """Horizontal strokes thickened by `steps` px without changing the glyph's height: dilated
    along y, then brought back to the height."""
    if steps <= 0:
        return alpha
    padded = np.pad(alpha, ((steps, steps), (0, 0)))
    dilated = ndimage.maximum_filter1d(padded, size=2 * steps + 1, axis=0)
    return resize(dilated, alpha.shape[1], alpha.shape[0])


def glyph(face, char, height, width, bars, shear, cell):
    """A white glyph on transparent: `height` px capitals, `width` of the face's own width, bars
    thickened by `bars` of the height, slanted by `shear`, centred in a `cell` px wide box
    (its own width when None), PAD px of transparent margin all round."""
    upright = face.upright(char)
    tall = height * SUPER
    alpha = resize(upright, upright.shape[1] * tall / upright.shape[0] * width, tall)
    alpha = thicken_bars(alpha, round(bars * tall))
    ink_width = alpha.shape[1]
    cell_width = cell * SUPER if cell else ink_width
    margin = PAD * SUPER
    canvas = np.zeros((tall + 2 * margin, int(np.ceil(cell_width + shear * tall)) + 2 * margin), np.float32)
    left = round(margin + (cell_width - ink_width) / 2)
    canvas[margin : margin + tall, left : left + ink_width] = alpha
    base = margin + tall
    slanted = Image.fromarray(canvas, "F").transform(
        canvas.shape[::-1], Image.AFFINE, (1, shear, -shear * base, 0, 1, 0), resample=Image.BICUBIC
    )
    out = np.asarray(slanted).clip(0, 1)
    columns = int(np.ceil(out.shape[1] / SUPER))
    out = np.pad(out, ((0, 0), (0, columns * SUPER - out.shape[1])))
    small = out.reshape(out.shape[0] // SUPER, SUPER, columns, SUPER).mean(axis=(1, 3))
    rgba = np.zeros(small.shape + (4,), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (small * 255).round().astype(np.uint8)
    return rgba


def glyph_set(args, shear):
    face = Face(args.font)
    cell = max(face.aspect(c) for c in DIGITS) * args.height * args.width
    pieces = {}
    for char in GLYPHS:
        pieces[char] = glyph(face, char, args.height, args.width, args.bars, shear, cell if char in DIGITS else None)
    widths = {pieces[c].shape[1] for c in DIGITS}
    if len(widths) != 1:
        raise SystemExit(f"the digits came out at different widths {widths}: they must share a cell")
    advance = cell + args.gap * args.height * args.width
    metrics = {"height": args.height, "pad": PAD, "advance": round(advance, 2), "shear": round(shear, 4), "cell": round(cell, 2)}
    return pieces, metrics


def pack(pieces):
    """Shelves, tallest first, no wider than Roblox's limit; GAP px of transparency between."""
    order = sorted(pieces, key=lambda name: -pieces[name].shape[0])
    rects, x, y, shelf, width = {}, 0, 0, 0, 0
    for name in order:
        h, w = pieces[name].shape[:2]
        if x and x + w > LIMIT:
            x, y, shelf = 0, y + shelf + GAP, 0
        rects[name] = [x, y, w, h]
        x += w + GAP
        shelf = max(shelf, h)
        width = max(width, x - GAP)
    height = y + shelf
    if width > LIMIT or height > LIMIT:
        raise SystemExit(f"the parts atlas is {width} x {height}, over Roblox's {LIMIT}")
    atlas = np.zeros((height, width, 4), np.uint8)
    for name, (x, y, w, h) in rects.items():
        atlas[y : y + h, x : x + w] = pieces[name]
    return atlas, rects


def main(args):
    os.makedirs(args.out, exist_ok=True)
    static = np.asarray(Image.open(args.static).convert("RGBA")).copy()
    full = np.asarray(Image.open(args.full).convert("RGBA")).copy()
    regions = json.load(open(args.regions))["regions"]
    segments = [box_of(r) for r in regions["rev_segments"]]
    named = {name: box_of(regions[name]) for name in TEXTS + PARTS}
    ink = check_pair(static, full, segments + list(named.values()))

    lit = [i for i, box in enumerate(segments) if ink_box(ink, box)]
    if not lit:
        raise SystemExit("no segment is lit in the full export: no shape to cut")
    shapes = [full[b[1] : b[3], b[0] : b[2]] for b in (segments[i] for i in lit)]
    if any(shape.shape != shapes[0].shape or (shape != shapes[0]).any() for shape in shapes):
        raise SystemExit("the lit segments are not the same shape: one mask cannot serve them all")
    height, width = static.shape[:2]
    colours, counts = np.unique(static[..., :3][static[..., 3] == 255], axis=0, return_counts=True)
    background = colours[counts.argmax()].astype(float)

    def padded(box):
        x0, y0, x1, y1 = box
        return (max(x0 - PAD, 0), max(y0 - PAD, 0), min(x1 + PAD, width), min(y1 + PAD, height))

    near = grow(ink, PAD)
    pieces, drawn = {}, {}
    pieces["segment"], drawn["segment"] = mask(full, padded(segments[lit[0]]), background, near)
    for name in PARTS:
        pieces[name], drawn[name] = mask(full, padded(named[name]), background, near)

    # Recomposed: the frame with every part (and the lit segments) laid over it in its drawn colour,
    # against the full export. Live text is not recomposed, so its regions are left out.
    recomposed = static[..., :3].astype(float)
    placed = [("segment", padded(segments[i])) for i in lit] + [(n, padded(named[n])) for n in PARTS]
    for name, (x0, y0, x1, y1) in placed:
        alpha = pieces[name][..., 3:4] / 255
        recomposed[y0:y1, x0:x1] = recomposed[y0:y1, x0:x1] * (1 - alpha) + drawn[name] * alpha
    compare = np.ones((height, width), bool)
    for name in TEXTS:
        x0, y0, x1, y1 = padded(named[name])
        compare[y0:y1, x0:x1] = False
    error = np.abs(recomposed - full[..., :3])[compare].max()
    Image.fromarray(recomposed.round().astype(np.uint8), "RGB").save(os.path.join(args.out, "recomposed.png"))
    # The unlit segment under a lit one bleeds through its antialiased edge by a few levels.
    if error > 40:
        raise SystemExit(f"parts recomposed over the frame are {error:.0f} levels off the full export")

    glyphs = None
    if args.font:
        shear = measure_shear(full, background, ink, named)
        glyph_pieces, glyphs = glyph_set(args, shear)
        pieces.update({f"glyph_{c}": piece for c, piece in glyph_pieces.items()})
        preview = Image.new("RGBA", (sum(p.shape[1] for p in glyph_pieces.values()) + 20, args.height + 40), (9, 12, 16, 255))
        x = 10
        for piece in glyph_pieces.values():
            preview.alpha_composite(Image.fromarray(piece, "RGBA"), (x, 20 - PAD))
            x += piece.shape[1]
        preview.save(os.path.join(args.out, "glyphs_preview.png"))
    atlas, rects = pack(pieces)
    Image.fromarray(atlas, "RGBA").save(os.path.join(args.out, "hud_parts.png"))

    ys, xs = np.nonzero(static[..., 3] > INK)
    left, top = max(int(xs.min()) - PAD, 0), max(int(ys.min()) - PAD, 0)
    right, bottom = min(int(xs.max()) + 1 + PAD, width), min(int(ys.max()) + 1 + PAD, height)
    frame = Image.fromarray(static[top:bottom, left:right], "RGBA")
    frame_w, frame_h = frame.size
    if frame_w > LIMIT:
        size = (LIMIT, round(LIMIT * frame_h / frame_w))
        frame = frame.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")
    frame.save(os.path.join(args.out, "hud_frame.png"))
    grey = Image.new("RGBA", frame.size, (128, 140, 155, 255))
    Image.alpha_composite(grey, frame).save(os.path.join(args.out, "frame_on_grey.png"))

    def shift(box):
        return [int(box[0] - left), int(box[1] - top), int(box[2] - left), int(box[3] - top)]

    texts = {}
    for name in TEXTS:
        if name in ("TC", "ABS"):
            text, line = split_rows(ink, named[name])
            texts[name] = shift(text)
            texts[name + "_line"] = shift(line)
        else:
            texts[name] = shift(ink_box(ink, named[name]))
    layout = {
        "size": [frame_w, frame_h],
        "image": list(frame.size),
        "segments": [shift(padded(box)) for box in segments],
        "lit": [i + 1 for i in lit],
        "parts": {name: shift(padded(named[name])) for name in PARTS},
        "texts": texts,
        "atlas": [int(atlas.shape[1]), int(atlas.shape[0])],
        "rects": rects,
        "glyphs": glyphs,
        "colours": {name: [int(v) for v in colour] for name, colour in drawn.items()},
        "background": [int(v) for v in background],
        "recomposed_error": round(float(error), 1),
    }
    json.dump(layout, open(os.path.join(args.out, "hud_layout.json"), "w"), indent=1)
    print(json.dumps(layout))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("static")
    parser.add_argument("full")
    parser.add_argument("regions")
    parser.add_argument("out")
    parser.add_argument("--font")
    parser.add_argument("--height", type=int, default=0)
    parser.add_argument("--width", type=float, default=1.0)
    parser.add_argument("--bars", type=float, default=0.0)
    parser.add_argument("--gap", type=float, default=0.06)
    arguments = parser.parse_args()
    if arguments.font and arguments.height <= 0:
        parser.error("--font needs --height")
    main(arguments)
