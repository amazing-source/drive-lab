"""
Measures and cuts the DR458 binnacle design pack (three 2048 x 853 pages and a strip of eight
shift lamps, the owner's ChatGPT pack) into what the game draws:

- binnacle_driving.png, a sheet: the driving page, one white cell per rpm segment (each cut from
  the page's own unlit segment, so a lit segment has the design's exact shape), the TCS and POS
  pills as white masks, and the eight lamps unlit and lit (the lit lens made grey, for the
  game to tint with the rules' colour);
- binnacle_pages.png, a sheet: the CHASSIS - BODY and MECHANIC pages;
- binnacle_layout.json and BinnacleLayout.luau: every box, normalised to its page (0 to 1),
  and every sprite's rectangle in its sheet;
- previews of what was found, to check before uploading.

    python -I tools/assets/binnacle_layers.py <pack dir> <out dir> [driving=<image id> pages=<image id>]

How it finds things:
- Segments are the dark shapes inside the red band, the tick numbers the dark digits above them.
  Each segment's rpm is read off the tick numbers: every number is projected onto the band (the
  nearest point on the line through the segments' top edges) and the segments between two numbers
  are spread evenly between their values, so the band's own uneven spacing is kept. Below the
  first number the pack says nothing, so the segments there follow the real screen instead: the
  ones it lights at idle (IDLE_LIT) light up to IDLE_LIT_RPM.
- Labels are the light text of the empty pages, grouped into words and matched to the page's
  label list by their rough place. Each value's slot is centred on its label, and its height and
  top are the capitals of the example value in the matching filled page.
- Lamps are the opaque discs of the two strip images, each cut square on its own rim, since the
  lit strip was generated apart from the unlit one and its lamps are not where the unlit ones are.
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

PAGE_SIZE = (2048, 853)
# Pages are stored 1020 wide, so a 2-pixel border of their own edge fits a 1024 sheet: a sprite
# sampled at its edge then reads its own colour, not the next sprite's.
PAGE_WIDTH = 1020
SHEET_WIDTH = 1024
EXTRUDE = 2
GAP = 2
SEGMENT_SCALE = 0.5
LAMP_CELL = 64
MARKS = [2, 3, 4, 5, 6, 7, 8, 9]
# The real screen lights its first two segments at idle (photo 011), below the first tick
# number. They light evenly up to IDLE_LIT_RPM, kept under the DR458's lowest idle so they do
# not flicker there.
IDLE_LIT = 2
IDLE_LIT_RPM = 900

# Each page's labels in the order of Config/Cars/DR458/Binnacle.luau, with a rough centre in
# design pixels used only to tell which detected word is which.
LABELS = {
    "driving": {
        "GEAR": (938, 294),
        "SPEED": (488, 614),
        "TCS": (367, 341),
        "POS": (367, 474),
        "OIL P": (1361, 322),
        "P FUEL": (1803, 322),
        "WATER T": (1360, 611),
        "OIL T": (1816, 611),
    },
    "chassis": {
        "ABS FAIL": (258, 190),
        "TCS FAIL": (773, 190),
        "EDIFF FAIL": (1285, 190),
        "BRAKE FAIL": (1795, 190),
        "FRONT DISK": (257, 426),
        "REAR DISK": (770, 426),
        "BRAKE OIL": (1287, 426),
        "PAD WEAR": (1794, 426),
        "ODOMETER": (259, 658),
        "MANETTINO": (774, 658),
        "DDU FIRMWARE": (1548, 658),
    },
    "mechanic": {
        "RPM": (256, 190),
        "FUEL %": (767, 190),
        "CHECK": (1280, 190),
        "V_BATT": (1792, 190),
        "T_WATER": (256, 433),
        "ANGLE": (769, 431),
        "TOIL ENGINE": (1279, 431),
        "P_OIL": (1794, 433),
        "P CARTER": (365, 668),
        "TOIL GEAR": (1025, 668),
        "P_FUEL": (1681, 670),
    },
}
PILLS = ("TCS", "POS")
SNAP = 60


def load(directory, name):
    image = Image.open(directory / f"{name}.png").convert("RGBA")
    return np.asarray(image).astype(float)


def is_red(rgb):
    return (rgb[..., 0] > 120) & (rgb[..., 0] - rgb[..., 1] > 50)


def is_light(rgb):
    return (rgb.mean(axis=2) > 150) & (np.abs(rgb[..., 0] - rgb[..., 2]) < 60)


def boxes(mask):
    labels, count = ndimage.label(mask)
    found = []
    for index, area in enumerate(ndimage.find_objects(labels)):
        own = labels[area] == index + 1
        found.append(
            {
                "box": (area[1].start, area[0].start, area[1].stop, area[0].stop),
                "size": int(own.sum()),
                "label": index + 1,
            }
        )
    return labels, found


def words(mask, gap):
    joined, _ = ndimage.label(ndimage.binary_dilation(mask, structure=np.ones((3, gap))))
    found = []
    for index, area in enumerate(ndimage.find_objects(joined)):
        own = (joined[area] == index + 1) & mask[area]
        if own.sum() < 30:
            continue
        ys, xs = np.nonzero(own)
        x0, y0 = area[1].start, area[0].start
        found.append((x0 + xs.min(), y0 + ys.min(), x0 + xs.max() + 1, y0 + ys.max() + 1))
    return found


def centre(box):
    return ((box[0] + box[2]) / 2, (box[1] + box[3]) / 2)


def norm_rect(box):
    w, h = PAGE_SIZE
    return {
        "x": round(box[0] / w, 5),
        "y": round(box[1] / h, 5),
        "width": round((box[2] - box[0]) / w, 5),
        "height": round((box[3] - box[1]) / h, 5),
    }


def capitals(mask, near):
    """The capitals' top and bottom of the value glyphs in `mask` closest under `near`."""
    candidates = [
        b for b in words(mask, 40) if b[1] >= near[3] - 5 and (b[2] - b[0]) * (b[3] - b[1]) > 400
    ]
    if not candidates:
        raise SystemExit(f"no example value under {near}")
    nx = (near[0] + near[2]) / 2
    best = min(candidates, key=lambda b: (b[1] - near[3]) + abs(centre(b)[0] - nx))
    _, found = boxes(mask[best[1] : best[3], best[0] : best[2]])
    tall = [f["box"] for f in found if f["size"] > 20]
    peak = max(b[3] - b[1] for b in tall)
    caps = [b for b in tall if b[3] - b[1] >= 0.8 * peak]
    top = best[1] + min(b[1] for b in caps)
    bottom = best[1] + max(b[3] for b in caps)
    return best, top, bottom


def band(page):
    """The rpm band: each segment's mask, quad and rpm, and the tick numbers' places."""
    rgb = page[..., :3]
    dark = ~is_red(rgb)
    labels, found = boxes(dark)
    segments, digits = [], []
    for f in found:
        x0, y0, x1, y1 = f["box"]
        if y0 > 480:
            continue
        if y1 - y0 >= 70 and f["size"] > 1500 and x1 - x0 < 60:
            segments.append(f)
        elif 35 <= y1 - y0 <= 55 and 20 <= x1 - x0 <= 40 and 400 <= f["size"] <= 1200:
            digits.append(f)
    segments.sort(key=lambda f: f["box"][0])
    digits.sort(key=lambda f: f["box"][0])
    if len(digits) != len(MARKS):
        raise SystemExit(f"found {len(digits)} tick numbers, expected {len(MARKS)}")
    for a, b in zip(segments, segments[1:]):
        if a["box"][2] > b["box"][0]:
            raise SystemExit(f"segments overlap across columns: {a['box']} {b['box']}")

    worst = 0.0
    for f in segments:
        own = labels == f["label"]
        x0, _, x1, _ = f["box"]
        xs = np.arange(x0, x1)
        tops = np.array([np.nonzero(own[:, x])[0].min() for x in xs], float)
        bottoms = np.array([np.nonzero(own[:, x])[0].max() + 1 for x in xs], float)
        inner = slice(2, len(xs) - 2)
        top_fit = np.polyfit(xs[inner], tops[inner], 1)
        bottom_fit = np.polyfit(xs[inner], bottoms[inner], 1)
        worst = max(
            worst,
            np.abs(np.polyval(top_fit, xs[inner]) - tops[inner]).max(),
            np.abs(np.polyval(bottom_fit, xs[inner]) - bottoms[inner]).max(),
        )
        f["quad"] = [
            (x0, np.polyval(top_fit, x0)),
            (x1, np.polyval(top_fit, x1)),
            (x1, np.polyval(bottom_fit, x1)),
            (x0, np.polyval(bottom_fit, x0)),
        ]
        f["top"] = ((x0 + x1) / 2, np.polyval(top_fit, (x0 + x1) / 2))

    path = np.array([f["top"] for f in segments])
    marks = []
    for value, digit in zip(MARKS, digits):
        point = np.array(centre(digit["box"]))
        best = (float("inf"), 0.0)
        for k in range(len(path) - 1):
            a, b = path[k], path[k + 1]
            t = np.clip(np.dot(point - a, b - a) / np.dot(b - a, b - a), 0, 1)
            distance = np.linalg.norm(a + t * (b - a) - point)
            if distance < best[0]:
                best = (distance, k + t)
        marks.append({"rpm": value * 1000, "at": best[1], "box": digit["box"], "distance": best[0]})
    ats = [m["at"] for m in marks]
    if any(b <= a for a, b in zip(ats, ats[1:])):
        raise SystemExit(f"tick numbers do not rise along the band: {ats}")
    rpms = [m["rpm"] for m in marks]
    for k, f in enumerate(segments):
        if k <= ats[0]:
            i = 0
        elif k >= ats[-1]:
            i = len(ats) - 2
        else:
            i = max(j for j in range(len(ats) - 1) if ats[j] <= k)
        slope = (rpms[i + 1] - rpms[i]) / (ats[i + 1] - ats[i])
        f["rpm"] = int(round(rpms[i] + (k - ats[i]) * slope))
    if IDLE_LIT >= ats[0] + 1:
        raise SystemExit(f"the first tick number falls on a segment lit at idle (at {ats[0]:.2f})")
    for k in range(IDLE_LIT):
        segments[k]["rpm"] = int(round(IDLE_LIT_RPM * (k + 1) / IDLE_LIT))
    thresholds = [f["rpm"] for f in segments]
    if any(b <= a for a, b in zip(thresholds, thresholds[1:])):
        raise SystemExit(f"segment thresholds do not rise along the band: {thresholds[:6]}")
    return labels, segments, marks, worst


def lit_cells(page, labels, segments):
    """A white cell per segment: alpha from how far each pixel is from the band's red toward
    the segment's black, inside the segment's own shape grown by 2 pixels."""
    rgb = page[..., :3]
    red = np.median(rgb[is_red(rgb)][:, 0])
    black = np.median(np.concatenate([rgb[labels == f["label"]][:, 0] for f in segments]))
    alpha = np.clip((red - rgb[..., 0]) / (red - black), 0, 1)
    cells = []
    for f in segments:
        own = labels == f["label"]
        grown = ndimage.binary_dilation(own, iterations=2) & ((labels == f["label"]) | is_red(rgb))
        x0, y0, x1, y1 = f["box"]
        cx0, cy0 = (x0 - 4) // 2 * 2, (y0 - 4) // 2 * 2
        cx1, cy1 = -(-(x1 + 4) // 2) * 2, -(-(y1 + 4) // 2) * 2
        a = np.where(grown, alpha, 0)[cy0:cy1, cx0:cx1]
        cell = np.zeros((cy1 - cy0, cx1 - cx0, 4), np.uint8)
        cell[..., :3] = 255
        cell[..., 3] = np.round(a * 255)
        image = Image.fromarray(cell, "RGBA")
        small = image.resize(
            (round(image.width * SEGMENT_SCALE), round(image.height * SEGMENT_SCALE)), Image.BOX
        )
        cells.append({"image": small, "box": (cx0, cy0, cx1, cy1)})
    return cells


def lit_colour(filled, labels, segments):
    rgb = filled[..., :3]
    lit = [rgb[labels == f["label"]] for f in segments]
    lit = [p for p in lit if p.mean() > 150]
    if not lit:
        raise SystemExit("no lit segment in the filled driving page")
    pixels = np.concatenate(lit)
    pixels = pixels[pixels.mean(axis=1) > 180]
    return [int(round(v)) for v in np.median(pixels, axis=0)]


def ink_colours(pages):
    """The values' colour and the pills' text colour, as the filled examples print them."""
    bright, dark = [], []
    for name, (empty, filled) in pages.items():
        rgb, frgb = empty[..., :3], filled[..., :3]
        difference = np.abs(frgb - rgb).max(axis=2)
        bright.append(frgb[(difference > 90) & (frgb.mean(axis=2) > 200)])
        if name == "driving":
            dark.append(frgb[(difference > 90) & (frgb.mean(axis=2) < 40) & (rgb.mean(axis=2) > 150)])
    value = [int(round(v)) for v in np.median(np.concatenate(bright), axis=0)]
    text = [int(round(v)) for v in np.median(np.concatenate(dark), axis=0)]
    return value, text


def page_layout(name, empty, filled):
    rgb, frgb = empty[..., :3], filled[..., :3]
    light = is_light(rgb)
    labels, found = boxes(light)
    gear_ring, pills = None, {}
    for f in found:
        x0, y0, x1, y1 = f["box"]
        if name == "driving" and x1 - x0 > 300 and y1 - y0 > 300:
            gear_ring = f["box"]
            light &= labels != f["label"]
        elif name == "driving" and x1 - x0 > 150 and 50 < y1 - y0 < 100:
            pills["POS"] = f["box"]
            light &= labels != f["label"]
    if name == "driving":
        reds, found_red = boxes(is_red(rgb))
        for f in found_red:
            x0, y0, x1, y1 = f["box"]
            if x1 - x0 > 150 and 50 < y1 - y0 < 100 and y0 > 250:
                pills["TCS"] = f["box"]
        if gear_ring is None or set(pills) != set(PILLS):
            raise SystemExit(f"driving page: gear frame {gear_ring}, pills {sorted(pills)}")

    detected = [w for w in words(light, 80) if (w[2] - w[0]) * (w[3] - w[1]) > 400]
    matched = {}
    for label, rough in LABELS[name].items():
        best = min(detected, key=lambda w: np.hypot(*(np.array(centre(w)) - rough)))
        distance = float(np.hypot(*(np.array(centre(best)) - rough)))
        if distance > SNAP or best in matched.values():
            raise SystemExit(f"{name}: no clear word for {label} (nearest {best}, {distance:.0f} px)")
        matched[label] = best

    difference = np.abs(frgb - rgb).max(axis=2)
    values = (difference > 90) & (frgb.mean(axis=2) > 150)
    inked = (difference > 90) & (frgb.mean(axis=2) < 60)

    slots = {}
    for label, box in matched.items():
        cx = centre(box)[0]
        if label in pills:
            pill = pills[label]
            _, top, bottom = capitals(inked, (pill[0], pill[1] - 6, pill[2], pill[1] + 5))
            slots[label] = (pill[0], top, pill[2], bottom)
            continue
        if label == "GEAR":
            _, top, bottom = capitals(values, box)
            inset = 14
            slots[label] = (gear_ring[0] + inset, top, gear_ring[2] - inset, bottom)
            continue
        _, top, bottom = capitals(values, box)
        neighbours = [centre(matched[o])[0] for o in matched if o != label and abs(centre(matched[o])[1] - centre(box)[1]) < 40]
        if gear_ring is not None and gear_ring[1] < centre(box)[1] < gear_ring[3]:
            neighbours.append(centre(gear_ring)[0])
        room = min([abs(n - cx) for n in neighbours] + [2 * cx, 2 * (PAGE_SIZE[0] - cx)])
        half = 0.46 * room
        slots[label] = (cx - half, top, cx + half, bottom)
    return matched, slots, pills, gear_ring


def edges(page):
    rgb = page[..., :3]
    columns = np.concatenate([rgb[:, :4], rgb[:, -4:]], axis=1)
    red_rows = is_red(columns).all(axis=1)
    title = 0
    while title < len(red_rows) and red_rows[title]:
        title += 1
    below = columns[title:].reshape(-1, 3)
    edge = [int(round(v)) for v in np.median(below, axis=0)]
    if title == 0:
        return edge, None
    tint = [int(round(v)) for v in np.median(columns[:title].reshape(-1, 3), axis=0)]
    return edge, {"height": round(title / PAGE_SIZE[1], 5), "rgb": tint}


def lamps(strip):
    alpha = strip[..., 3]
    _, found = boxes(alpha > 128)
    discs = sorted([f for f in found if f["size"] > 5000], key=lambda f: f["box"][0])
    if len(discs) != 8:
        raise SystemExit(f"found {len(discs)} lamps, expected 8")
    return [f["box"] for f in discs]


def lamp_cells(off, on):
    off_boxes, on_boxes = lamps(off), lamps(on)
    side = max(max(b[2] - b[0], b[3] - b[1]) for b in off_boxes + on_boxes) + 4
    cells = {"off": [], "on": []}
    for kind, strip, found in (("off", off, off_boxes), ("on", on, on_boxes)):
        for box in found:
            cx, cy = centre(box)
            x0, y0 = int(round(cx - side / 2)), int(round(cy - side / 2))
            crop = strip[y0 : y0 + side, x0 : x0 + side].copy()
            if kind == "on":
                grey = crop[..., :3].max(axis=2)
                crop[..., 0] = crop[..., 1] = crop[..., 2] = grey
            image = Image.fromarray(np.round(crop).astype(np.uint8), "RGBA")
            cells[kind].append(image.resize((LAMP_CELL, LAMP_CELL), Image.LANCZOS))
    return cells, off_boxes, on_boxes, side


def page_cell(page):
    height = round(PAGE_SIZE[1] * PAGE_WIDTH / PAGE_SIZE[0])
    image = Image.fromarray(page.astype(np.uint8), "RGBA").resize((PAGE_WIDTH, height), Image.LANCZOS)
    padded = np.pad(np.asarray(image), ((EXTRUDE, EXTRUDE), (EXTRUDE, EXTRUDE), (0, 0)), mode="edge")
    return Image.fromarray(padded, "RGBA"), EXTRUDE


class Sheet:
    def __init__(self, name):
        self.name = name
        self.items = []
        self.x = self.y = self.row = 0

    def add(self, image, inset=0):
        if self.x + image.width > SHEET_WIDTH:
            self.x, self.y, self.row = 0, self.y + self.row + GAP, 0
        at = (self.x, self.y)
        self.items.append((image, at))
        self.x += image.width + GAP
        self.row = max(self.row, image.height)
        return {
            "sheet": self.name,
            "x": at[0] + inset,
            "y": at[1] + inset,
            "width": image.width - 2 * inset,
            "height": image.height - 2 * inset,
        }

    def newline(self):
        if self.x:
            self.x, self.y, self.row = 0, self.y + self.row + GAP, 0

    def save(self, path):
        height = self.y + self.row
        if height > 1024:
            raise SystemExit(f"{self.name} sheet is {height} tall, over Roblox's 1024")
        canvas = Image.new("RGBA", (SHEET_WIDTH, height), (0, 0, 0, 0))
        for image, at in self.items:
            canvas.paste(image, at)
        canvas.save(path)
        return (SHEET_WIDTH, height)


def luau_value(value, indent):
    pad = "\t" * indent
    flat = isinstance(value, (dict, list)) and not any(
        isinstance(v, (dict, list)) for v in (value.values() if isinstance(value, dict) else value)
    )
    if flat and isinstance(value, dict):
        return "{ " + ", ".join(f"{luau_key(k)} = {luau_value(v, 0)}" for k, v in value.items()) + " }"
    if flat:
        return "{ " + ", ".join(luau_value(v, 0) for v in value) + " }"
    if isinstance(value, dict):
        inner = "".join(f"{pad}\t{luau_key(k)} = {luau_value(v, indent + 1)},\n" for k, v in value.items())
        return "{\n" + inner + pad + "}"
    if isinstance(value, list):
        inner = "".join(f"{pad}\t{luau_value(v, indent + 1)},\n" for v in value)
        return "{\n" + inner + pad + "}"
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, (float, np.floating)):
        return repr(round(float(value), 5))
    if isinstance(value, (int, np.integer)):
        return str(int(value))
    raise TypeError(f"cannot write {type(value)} as Luau")


def luau_key(key):
    return key if key.isidentifier() else f"[{json.dumps(key)}]"


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    pack, out = Path(sys.argv[1]), Path(sys.argv[2])
    ids = dict(arg.split("=", 1) for arg in sys.argv[3:])
    out.mkdir(parents=True, exist_ok=True)

    pages = {name: (load(pack, f"{name}_empty"), load(pack, f"{name}_filled")) for name in LABELS}
    driving, driving_filled = pages["driving"]
    labels, segments, marks, worst = band(driving)
    cells = lit_cells(driving, labels, segments)
    segment_rgb = lit_colour(driving_filled, labels, segments)

    sheets = {"driving": Sheet("driving"), "pages": Sheet("pages")}
    layout = {"pages": {}, "segments": [], "marks": [], "pills": {}, "lamps": {"off": [], "on": []}}
    for name, (empty, filled) in pages.items():
        sheet = sheets["driving" if name == "driving" else "pages"]
        image, inset = page_cell(empty)
        sprite = sheet.add(image, inset)
        sheet.newline()
        matched, slots, pills, ring = page_layout(name, empty, filled)
        edge, title = edges(empty)
        layout["pages"][name] = {
            "art": sprite,
            "edge": edge,
            "title": title,
            "labels": {label: norm_rect(box) for label, box in matched.items()},
            "slots": {label: norm_rect(box) for label, box in slots.items()},
        }
        if name == "driving":
            for label, box in pills.items():
                rgb = empty[..., :3]
                x0, y0, x1, y1 = box[0] - 2, box[1] - 2, box[2] + 2, box[3] + 2
                crop = rgb[y0:y1, x0:x1]
                ink = crop[..., 0] if label == "TCS" else crop.mean(axis=2)
                lo, hi = np.percentile(ink, 2), np.percentile(ink, 98)
                cell = np.zeros(crop.shape[:2] + (4,), np.uint8)
                cell[..., :3] = 255
                cell[..., 3] = np.round(np.clip((ink - lo) / (hi - lo), 0, 1) * 255)
                pill = Image.fromarray(cell, "RGBA").resize(
                    (round(cell.shape[1] * SEGMENT_SCALE), round(cell.shape[0] * SEGMENT_SCALE)), Image.BOX
                )
                inside = rgb[box[1] + 8 : box[3] - 8, box[0] + 12 : box[2] - 12].reshape(-1, 3)
                layout["pills"][label] = {
                    "rect": norm_rect((x0, y0, x1, y1)),
                    "rgb": [int(round(v)) for v in np.median(inside, axis=0)],
                    "sprite": sheets["driving"].add(pill),
                }

    for f, cell in zip(segments, cells):
        layout["segments"].append(
            {
                "rpm": f["rpm"],
                "corners": [round(v, 5) for x, y in f["quad"] for v in (x / PAGE_SIZE[0], y / PAGE_SIZE[1])],
                "rect": norm_rect(cell["box"]),
                "sprite": sheets["driving"].add(cell["image"]),
            }
        )
    for m in marks:
        x, y = centre(m["box"])
        layout["marks"].append({"rpm": m["rpm"], "x": round(x / PAGE_SIZE[0], 5), "y": round(y / PAGE_SIZE[1], 5)})

    off = load(pack, "shift_lights_off")
    on = load(pack, "shift_lights_on")
    lamp_images, off_boxes, on_boxes, side = lamp_cells(off, on)
    sheets["driving"].newline()
    for kind in ("off", "on"):
        for image in lamp_images[kind]:
            layout["lamps"][kind].append(sheets["driving"].add(image))

    sizes = {name: sheet.save(out / f"binnacle_{name}.png") for name, sheet in sheets.items()}
    layout["sheets"] = {name: {"width": w, "height": h, "image": ids.get(name, "")} for name, (w, h) in sizes.items()}
    layout["segmentRgb"] = segment_rgb
    layout["valueRgb"], layout["pillTextRgb"] = ink_colours(pages)
    (out / "binnacle_layout.json").write_text(json.dumps(layout, indent=1), newline="\n")
    write_luau(out / "BinnacleLayout.luau", layout, ids)
    previews(out, pages, segments, marks, layout, off, on, off_boxes, on_boxes)

    print(f"segments: {len(segments)} (quad fit worst {worst:.2f} px)")
    print("tick numbers on the band (segment index, distance px):")
    for m in marks:
        print(f"  {m['rpm']:>5} rpm at {m['at']:.2f}, {m['distance']:.0f} px from the band")
    print("segment rpm:", [f["rpm"] for f in segments])
    print(f"lit segment colour {segment_rgb}")
    for name, page in layout["pages"].items():
        print(f"{name}: {len(page['labels'])} labels, {len(page['slots'])} slots, edge {page['edge']}, title {page['title']}")
    print(f"pills: {[(k, v['rgb']) for k, v in sorted(layout['pills'].items())]}")
    print(f"lamps: {len(off_boxes)} unlit, {len(on_boxes)} lit, cut {side} px square to {LAMP_CELL}")
    print(f"  unlit centres x: {[round(centre(b)[0]) for b in off_boxes]}")
    print(f"  lit centres x:   {[round(centre(b)[0]) for b in on_boxes]}")
    print(f"sheets: {sizes}")


def write_luau(path, layout, ids):
    def sprite(s):
        return {"image": ids.get(s["sheet"], ""), "x": s["x"], "y": s["y"], "width": s["width"], "height": s["height"]}

    def rgb(c):
        return {"r": c[0], "g": c[1], "b": c[2]}

    pages = {}
    for name, page in layout["pages"].items():
        pages[name] = {
            "art": sprite(page["art"]),
            "edge": rgb(page["edge"]),
            "labels": page["labels"],
            "slots": page["slots"],
        }
        if page["title"]:
            pages[name]["title"] = {"height": page["title"]["height"], "rgb": rgb(page["title"]["rgb"])}
    pages["driving"]["pills"] = {
        k: {"rect": v["rect"], "rgb": rgb(v["rgb"]), "sprite": sprite(v["sprite"])} for k, v in layout["pills"].items()
    }
    pages["driving"]["band"] = {
        "segments": [
            {"rpm": s["rpm"], "corners": s["corners"], "rect": s["rect"], "sprite": sprite(s["sprite"])}
            for s in layout["segments"]
        ],
        "rgb": rgb(layout["segmentRgb"]),
        "marks": layout["marks"],
    }
    data = {
        "pages": pages,
        "valueRgb": rgb(layout["valueRgb"]),
        "pillTextRgb": rgb(layout["pillTextRgb"]),
        "lamps": {k: [sprite(s) for s in v] for k, v in layout["lamps"].items()},
    }
    text = (
        "--!strict\n"
        "-- Generated by tools/assets/binnacle_layers.py from the design pack: rerun it, do not edit.\n"
        'local Binnacle = require("../../Binnacle")\n\n'
        f"local Layout: Binnacle.Layout = {luau_value(data, 0)}\n\nreturn Layout\n"
    )
    path.write_text(text, newline="\n")


def previews(out, pages, segments, marks, layout, off, on, off_boxes, on_boxes):
    driving = Image.fromarray(pages["driving"][0].astype(np.uint8), "RGBA").convert("RGB")
    draw = ImageDraw.Draw(driving)
    for index, f in enumerate(segments):
        quad = [tuple(p) for p in f["quad"]]
        draw.polygon(quad, outline=(0, 255, 255))
        if index % 3 == 0 or index == len(segments) - 1:
            x, y = f["quad"][3]
            draw.text((x, y + 4), f"{index + 1}\n{f['rpm']}", fill=(255, 255, 0))
    for m in marks:
        draw.rectangle(m["box"], outline=(255, 0, 255))
    for name, page in layout["pages"].items():
        image = driving if name == "driving" else Image.fromarray(pages[name][0].astype(np.uint8), "RGBA").convert("RGB")
        d = draw if name == "driving" else ImageDraw.Draw(image)
        w, h = PAGE_SIZE
        for label in page["labels"]:
            for key, colour in (("labels", (0, 255, 0)), ("slots", (255, 128, 0))):
                r = page[key][label]
                d.rectangle((r["x"] * w, r["y"] * h, (r["x"] + r["width"]) * w, (r["y"] + r["height"]) * h), outline=colour, width=2)
        image.save(out / f"preview_{name}_boxes.png")

    lit = Image.fromarray(pages["driving"][0].astype(np.uint8), "RGBA")
    for s in layout["segments"]:
        r = s["rect"]
        cell = Image.open(out / "binnacle_driving.png").crop(
            (s["sprite"]["x"], s["sprite"]["y"], s["sprite"]["x"] + s["sprite"]["width"], s["sprite"]["y"] + s["sprite"]["height"])
        )
        size = (round(r["width"] * PAGE_SIZE[0]), round(r["height"] * PAGE_SIZE[1]))
        lit.alpha_composite(cell.resize(size, Image.LANCZOS), (round(r["x"] * PAGE_SIZE[0]), round(r["y"] * PAGE_SIZE[1])))
    lit.convert("RGB").save(out / "preview_driving_all_lit.png")

    strip = Image.new("RGB", (off.shape[1], off.shape[0] * 2), (128, 128, 128))
    strip.paste(Image.fromarray(off.astype(np.uint8), "RGBA"), (0, 0), Image.fromarray(off.astype(np.uint8), "RGBA"))
    strip.paste(Image.fromarray(on.astype(np.uint8), "RGBA"), (0, off.shape[0]), Image.fromarray(on.astype(np.uint8), "RGBA"))
    d = ImageDraw.Draw(strip)
    for b in off_boxes:
        d.rectangle(b, outline=(255, 0, 255), width=3)
    for b in on_boxes:
        d.rectangle((b[0], b[1] + off.shape[0], b[2], b[3] + off.shape[0]), outline=(255, 0, 255), width=3)
    strip.save(out / "preview_lamps.png")


if __name__ == "__main__":
    main()
