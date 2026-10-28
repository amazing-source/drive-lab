"""
Draws Drive Lab's road-surface marks, the gantry's sign faces and the two lamp-glint
textures, ready to upload.

    python -I tools/assets/roadside_textures.py <out dir> <vfx extras dir> [--patch <dir>] [--font <ttf>]

Road marks (RGBA, dark on clear, laid as Decals over the road; alpha stays well under 1 so the
wet road's gloss still shows through them):
- road_patch.png: a worn repair patch, its surface from ambientCG's AsphaltDamage001 (CC0;
  colour and torn-edge opacity, pass its folder as --patch) under a darker tar
  seal along the edge; without it, a procedural grain stands in.
- road_crack.png: a tar-sealed crack ("tar snake"), 0.6 x 4 m: a wandering, branching black
  band 5-7 cm wide (sealant is laid over the crack, wider than it).
- road_skid.png: one car's two tyre marks, 1.9 x 24 m: rubber streaks with tread striations,
  fading in over the first tenth and out over the last third, wandering a little together.
- road_stain.png: an oil stain, soft-edged, darker spots in it.
- road_drips.png: the dark band of drips down a lane's middle, 0.7 x 12 m, sparse and uneven.

Signs (RGB, 1100 x 600 for a 4.4 x 2.4 m panel): sign_right.png and sign_left.png, Italian
extra-urban direction signs (white on blue, DPR 495/1992 art. 78), a lane arrow and three
destinations with their distances. --font names a bold sans-serif TrueType font (default
Windows' Arial Bold): Italy's own alphabet is not free.

Glints (RGB on black, for additive beams: black adds nothing), from the owner's ChatGPT pack:
- lamp_flare.png: Horizontal_Lens_Flare_1024's central band, 1024 x 64, its 6-pixel core line
  thickened so it stays a line, not dashes, when the flare is a few pixels tall on screen, and
  windowed to black at all four edges (cropped, the haze reached the band's edge and the beam
  drew as a grey box).
- lamp_reflection.png: Wet_Asphalt_Reflection_1024 cropped round its streak and turned so the
  streak runs along the image's width, bright end on the right, faded to black over its last
  sixth there (the source's brightest rows touch its edge and drew a hard cut). A Beam draws
  the image's right edge at Attachment0 (seen in Studio).

Every mark is seeded, so a rebuild draws the same pixels. Prints each file's size and mean
alpha (or brightness) so a blank or saturated texture shows before anyone uploads it.
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

TAR = (16, 16, 17)
RUBBER = (12, 12, 13)
OIL = (14, 13, 12)


def smooth_noise(rng, height, width, scale):
    """Value noise: random cells of `scale` pixels, bicubic-smoothed to the image size, 0..1."""
    cells = rng.random((max(2, height // scale + 2), max(2, width // scale + 2)))
    image = Image.fromarray((cells * 255).astype(np.uint8), "L").resize((width, height), Image.BICUBIC)
    return np.asarray(image, dtype=np.float64) / 255


def rgba(colour, alpha):
    height, width = alpha.shape
    out = np.zeros((height, width, 4), np.uint8)
    out[..., 0], out[..., 1], out[..., 2] = colour
    out[..., 3] = np.round(np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def patch(rng, source):
    size = 512
    if source:
        colour = Image.open(source / "AsphaltDamage001_2K-PNG_Color.png").convert("L").resize((size, size), Image.BOX)
        opacity = Image.open(source / "AsphaltDamage001_2K-PNG_Opacity.png").convert("L").resize((size, size), Image.BOX)
        grey = np.asarray(colour, dtype=np.float64) / 255
        mask = np.asarray(opacity, dtype=np.float64) / 255
    else:
        grey = 0.45 + 0.2 * (smooth_noise(rng, size, size, 6) - 0.5) + 0.1 * (rng.random((size, size)) - 0.5)
        mask = np.zeros((size, size))
        mask[24:-24, 24:-24] = 1
    # The seal: a band just inside the edge, its width wandering.
    inner = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(9)), dtype=np.float64) / 255
    seal = np.clip(mask - inner, 0, 1) * (0.6 + 0.4 * smooth_noise(rng, size, size, 24))
    # Inside, the photo's light and dark read as alpha over a dark tone: the darker parts of the
    # worn surface darken the road more.
    surface = 0.34 + (0.62 - grey) * 0.5 + 0.1 * smooth_noise(rng, size, size, 48)
    alpha = np.maximum(np.clip(surface + 0.12, 0.3, 0.72) * inner, seal * 0.9) * mask
    shade = np.clip(grey * 60 + 14, 0, 255)
    out = np.zeros((size, size, 4), np.uint8)
    for channel in range(3):
        out[..., channel] = np.where(seal > 0.05, TAR[channel], shade).astype(np.uint8)
    out[..., 3] = np.round(np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def wander(rng, length, amplitude, scale):
    """A smooth lateral offset along a length, in pixels."""
    knots = rng.normal(0, 1, length // scale + 3)
    x = np.linspace(0, len(knots) - 3, length)
    base = np.minimum(np.floor(x).astype(int), len(knots) - 4)
    t = x - base
    # Catmull-Rom through the knots.
    p0, p1, p2, p3 = knots[base], knots[base + 1], knots[base + 2], knots[base + 3]
    curve = 0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (3 * p1 - p0 - 3 * p2 + p3) * t ** 3)
    return curve * amplitude


def stroke(alpha, xs, ys, widths, strength):
    """Draws round dabs along a path into an alpha array (max blend)."""
    height, width = alpha.shape
    for x, y, w in zip(xs, ys, widths):
        r = int(np.ceil(w)) + 1
        x0, x1 = max(0, int(x) - r), min(width, int(x) + r + 1)
        y0, y1 = max(0, int(y) - r), min(height, int(y) + r + 1)
        if x0 >= x1 or y0 >= y1:
            continue
        gy, gx = np.mgrid[y0:y1, x0:x1]
        d = np.hypot(gx - x, gy - y)
        dab = np.clip(w - d + 0.5, 0, 1) * strength
        alpha[y0:y1, x0:x1] = np.maximum(alpha[y0:y1, x0:x1], dab)


def crack(rng):
    # Drawn at twice the size and halved, so the band's edges are antialiased.
    width, height = 512, 2048
    alpha = np.zeros((height, width))
    ys = np.arange(0, height, 2.0)
    xs = width / 2 + wander(rng, len(ys), 40, 260) + wander(rng, len(ys), 4, 10)
    widths = 20 + 9 * smooth_noise(rng, 1, len(ys), 30)[0]
    fade = np.clip(np.minimum(ys, height - ys) / 160, 0, 1)
    stroke(alpha, xs, ys, widths * fade + 1, 0.92)
    for _ in range(3):
        start = int(rng.integers(200, len(ys) - 400))
        run = int(rng.integers(120, 320))
        side = rng.choice([-1, 1])
        by = ys[start : start + run]
        bx = xs[start] + side * np.linspace(0, rng.uniform(60, 150), run) + wander(rng, run, 8, 20)
        bw = np.linspace(13, 4, run)
        stroke(alpha, bx, by, bw, 0.88)
    return rgba(TAR, alpha).resize((width // 2, height // 2), Image.BOX)


def skid(rng):
    width, height = 256, 2048
    metres = 1.9
    px = width / metres
    y = np.arange(height)
    along = y / height
    fade = np.clip(along / 0.1, 0, 1) * np.clip((1 - along) / 0.35, 0, 1) ** 1.3
    drift = wander(rng, height, 10, 300)
    gx = np.arange(width)[None, :]
    alpha = np.zeros((height, width))
    for centre in (-0.8, 0.8):
        x = width / 2 + centre * px + drift[:, None] + wander(rng, height, 2, 60)[:, None]
        half = 0.15 * px
        d = np.abs(gx - x)
        band = np.clip((half - d) / 3 + 0.5, 0, 1)
        # Tread: grooves along the length, lighter lines a few pixels apart.
        grooves = 0.88 + 0.12 * np.cos((gx - x) / half * np.pi * 3.5)
        streaks = 0.75 + 0.25 * smooth_noise(rng, height, width, 18)
        alpha = np.maximum(alpha, band * grooves * streaks * 0.85)
    alpha *= fade[:, None]
    return rgba(RUBBER, alpha)


def stain(rng):
    size = 512
    gy, gx = np.mgrid[0:size, 0:size] / size - 0.5
    radius = np.hypot(gx * 1.15, gy)
    shape = smooth_noise(rng, size, size, 140) * 0.16 + (0.36 - radius)
    body = np.clip((shape - 0.04) / 0.16, 0, 1)
    spots = np.clip((smooth_noise(rng, size, size, 20) - 0.72) * 4, 0, 1)
    alpha = body * (0.5 + 0.22 * spots) + 0.06 * np.clip((shape + 0.05) / 0.1, 0, 1)
    soft = Image.fromarray((np.clip(alpha, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))
    return rgba(OIL, np.asarray(soft, dtype=np.float64) / 255)


def drips(rng):
    width, height = 128, 1024
    alpha = np.zeros((height, width))
    density = smooth_noise(rng, 1, height, 120)[0]
    for _ in range(420):
        y = rng.uniform(0, height)
        if rng.random() > density[int(y)] * 1.3:
            continue
        x = width / 2 + rng.normal(0, width * 0.16)
        r = rng.uniform(1.2, 4.5)
        stroke(alpha, [x], [y], [r], rng.uniform(0.45, 0.8))
    haze = smooth_noise(rng, height, width, 40) * np.exp(-(((np.arange(width) - width / 2) / (width * 0.28)) ** 2))[None, :]
    alpha = np.maximum(alpha, haze * 0.3)
    soft = Image.fromarray((np.clip(alpha, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
    return rgba(OIL, np.asarray(soft, dtype=np.float64) / 255)


SIGN_BLUE = (0, 76, 140)
SIGN_SIZE = (1100, 600)
SIGNS = {
    "sign_right": [("Milano", "48"), ("Bergamo", "21"), ("Lecco", "35")],
    "sign_left": [("Brescia", "33"), ("Verona", "92"), ("Venezia", "205")],
}


def sign(lines, font_path):
    """A blue panel with a white border, a down arrow for the lane below and three destinations."""
    width, height = SIGN_SIZE
    image = Image.new("RGB", SIGN_SIZE, SIGN_BLUE)
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((14, 14, width - 15, height - 15), radius=26, outline="white", width=12)
    font = ImageFont.truetype(font_path, 104)
    # The lane arrow: a shaft and a head pointing down, on the left.
    cx = 120
    draw.rectangle((cx - 20, 130, cx + 20, 380), fill="white")
    draw.polygon([(cx - 70, 360), (cx + 70, 360), (cx, 470)], fill="white")
    top = 85
    for name, distance in lines:
        draw.text((230, top), name, font=font, fill="white")
        right = width - 70 - draw.textlength(distance, font=font)
        draw.text((right, top), distance, font=font, fill="white")
        top += 150
    return image


def flare(extras):
    image = Image.open(extras / "Horizontal_Lens_Flare_1024.png").convert("L").crop((0, 448, 1024, 576))
    band = np.asarray(image, dtype=np.float64) / 255
    # Spread the core line over about 10 rows, keeping its brightness, then halve the height.
    spread = np.asarray(image.filter(ImageFilter.MaxFilter(9)), dtype=np.float64) / 255
    band = np.maximum(band, spread * 0.8)
    # Window the band to black at its edges, so the beam's rectangle never shows.
    rows = np.linspace(-1, 1, band.shape[0])
    columns = np.linspace(-1, 1, band.shape[1])
    vertical = np.clip(1 - np.abs(rows), 0, 1) ** 1.5
    horizontal = np.clip((1 - np.abs(columns)) / 0.12, 0, 1)
    band = band * vertical[:, None] * horizontal[None, :]
    out = Image.fromarray(np.round(np.clip(band, 0, 1) * 255).astype(np.uint8), "L").resize((1024, 64), Image.BOX)
    return out.convert("RGB")


def reflection(extras):
    image = Image.open(extras / "Wet_Asphalt_Reflection_1024.png").convert("RGB")
    # Columns round the streak; transposed, the original top (the streak's faded far end) is the
    # left edge and its bright near end the right.
    turned = np.asarray(image.crop((256, 0, 768, 1024)).transpose(Image.Transpose.TRANSPOSE), dtype=np.float64)
    width = turned.shape[1]
    x = np.arange(width) / (width - 1)
    t = np.clip((1 - x) / (1 / 6), 0, 1)
    fade = t * t * (3 - 2 * t)
    return Image.fromarray(np.round(turned * fade[None, :, None]).astype(np.uint8), "RGB")


def describe(image):
    data = np.asarray(image, dtype=np.float64) / 255
    if data.shape[2] == 4:
        return {"size": image.size, "meanAlpha": round(float(data[..., 3].mean()), 4), "maxAlpha": round(float(data[..., 3].max()), 4)}
    return {"size": image.size, "meanBrightness": round(float(data.mean()), 4), "max": round(float(data.max()), 4)}


def option(args, name, default):
    return args[args.index(name) + 1] if name in args else default


def main(args):
    out = Path(args[0])
    extras = Path(args[1])
    patch_dir = option(args, "--patch", None)
    source = Path(patch_dir) if patch_dir else None
    font = option(args, "--font", "C:/Windows/Fonts/arialbd.ttf")
    out.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(2026)
    images = {
        "road_patch": patch(rng, source),
        "road_crack": crack(rng),
        "road_skid": skid(rng),
        "road_stain": stain(rng),
        "road_drips": drips(rng),
        "lamp_flare": flare(extras),
        "lamp_reflection": reflection(extras),
    }
    for name, lines in SIGNS.items():
        images[name] = sign(lines, font)
    report = {}
    for name, image in images.items():
        image.save(out / f"{name}.png")
        report[name] = describe(image)
        alpha = report[name].get("maxAlpha", report[name].get("max"))
        if alpha is None or alpha < 0.05:
            raise SystemExit(f"{name} came out blank")
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main(sys.argv[1:])
