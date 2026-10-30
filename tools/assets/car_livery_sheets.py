"""Draw a car's side livery as two decal sheets in the car's own side-view frame.

    python -I tools/assets/car_livery_sheets.py <livery.json> <out dir> [--overlay <ortho_left.png> <ortho_right.png>]

Each sheet is RGBA over y (car metres, Blender axes, nose toward -y) and z, `res_m` metres per pixel:
pixel x = (y - y0) / res, pixel y = (z1 - z) / res, so both sides share one frame and the bake samples
them by position. Text and numerals on the right sheet are mirrored in that frame, so they read
correctly from the right; shapes are the same on both sides. No brand, logo or sponsor name: the
stickers are plain shapes. Each element's `roughness` is drawn under its alpha into
livery_<side>_roughness.png. --overlay writes each sheet over an orthographic side render in the
same frame, to check where elements land. `top_elements` (centre x, y;
text on a plate) are drawn on livery_top.png in `top_frame`, image top toward the rear, so they read
from the front.
"""
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

spec = json.loads(Path(sys.argv[1]).read_text())
out = Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
F = spec["frame"]
Y0, Y1, Z0, Z1, RES = F["y0"], F["y1"], F["z0"], F["z1"], F["res_m"]
W, H = round((Y1 - Y0) / RES), round((Z1 - Z0) / RES)
FONT = spec["font"]


def px(y, z):
    return ((y - Y0) / RES, (Z1 - z) / RES)


def poly(d, pts, fill):
    d.polygon([px(y, z) for y, z in pts], fill=fill)


def text_patch(text, height_m, fill, plate=None, shear=0.18):
    """A text (or numeral) patch, italic by shear, optionally on a rounded plate; returns RGBA."""
    hpx = max(8, round(height_m / RES))
    font = ImageFont.truetype(FONT, hpx)
    bbox = font.getbbox(text)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    pad = round(hpx * 0.1)
    img = Image.new("RGBA", (tw + 2 * pad + round(th * shear), th + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((pad - bbox[0] + round(th * shear), pad - bbox[1]), text, font=font, fill=fill)
    img = img.transform(img.size, Image.AFFINE, (1, shear, 0, 0, 1, 0), Image.BICUBIC)
    if plate:
        w_m, h_m, colour, radius_m = plate
        pw, ph = round(w_m / RES), round(h_m / RES)
        base = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
        ImageDraw.Draw(base).rounded_rectangle((0, 0, pw - 1, ph - 1), radius=round(radius_m / RES), fill=colour)
        img.thumbnail((round(pw * 0.86), round(ph * 0.86)), Image.LANCZOS)
        base.alpha_composite(img, ((pw - img.width) // 2, (ph - img.height) // 2))
        img = base
    return img


def us_flag(w_px, h_px):
    img = Image.new("RGBA", (w_px, h_px), (255, 255, 255, 255))
    d = ImageDraw.Draw(img)
    red, blue, white = (178, 34, 52, 255), (60, 59, 110, 255), (255, 255, 255, 255)
    for k in range(13):
        if k % 2 == 0:
            d.rectangle((0, round(k * h_px / 13), w_px, round((k + 1) * h_px / 13) - 1), fill=red)
    cw, ch = round(w_px * 0.4), round(h_px * 7 / 13)
    d.rectangle((0, 0, cw - 1, ch - 1), fill=blue)
    r = ch * 0.0616 * 0.8 / 1.0
    for row in range(9):
        for col in range(6 if row % 2 == 0 else 5):
            cx = cw * ((col * 2 + (1 if row % 2 == 0 else 2)) / 12)
            cy = ch * ((row + 1) / 10)
            pts = []
            for i in range(10):
                a = -math.pi / 2 + i * math.pi / 5
                rr = r if i % 2 == 0 else r * 0.382
                pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
            d.polygon(pts, fill=white)
    return img


def sheet(side):
    """The colour sheet (RGBA) and its roughness sheet (L, each element's `roughness` under its alpha)."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    rough = Image.new("L", (W, H), 0)
    for el in spec["elements"]:
        k = el["kind"]
        lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(lay)
        if k == "polygon":
            poly(d, el["points"], tuple(el["rgba"]))
        elif k == "checker":
            y0, y1, z0, z1, n_rows = el["y0"], el["y1"], el["z0"], el["z1"], el["rows"]
            sq = (z1 - z0) / n_rows
            cols = round((y1 - y0) / sq)
            for r in range(n_rows):
                for c in range(cols):
                    if (r + c) % 2 == 0:
                        ya, za = y0 + c * sq, z1 - (r + 1) * sq
                        poly(d, [(ya, za), (ya + sq, za), (ya + sq, za + sq), (ya, za + sq)], tuple(el["rgba"]))
        elif k == "stripes":
            # A rectangle with diagonal stripes (a hazard-style sticker), stripes 45 degrees.
            y0, z0, w, h = el["y"], el["z"], el["w"], el["h"]
            poly(d, [(y0, z0), (y0 + w, z0), (y0 + w, z0 + h), (y0, z0 + h)], tuple(el["base"]))
            step = el["pitch"]
            patch = Image.new("RGBA", (round(w / RES), round(h / RES)), (0, 0, 0, 0))
            pd = ImageDraw.Draw(patch)
            pw, ph = patch.size
            sp = round(step / RES)
            for x in range(-ph, pw + ph, sp * 2):
                pd.polygon([(x, ph), (x + sp, ph), (x + sp + ph, 0), (x + ph, 0)], fill=tuple(el["rgba"]))
            lay.alpha_composite(patch, tuple(round(v) for v in px(y0, z0 + h)))
        elif k == "chevrons":
            y0, z0, w, h, n = el["y"], el["z"], el["w"], el["h"], el["count"]
            poly(d, [(y0, z0), (y0 + w, z0), (y0 + w, z0 + h), (y0, z0 + h)], tuple(el["base"]))
            cw = w / (n + 1)
            for i in range(n):
                ya = y0 + cw * (i + 0.6)
                # Chevrons point toward the front (-y) on both sides.
                poly(d, [(ya + cw * 0.55, z0 + h * 0.15), (ya, z0 + h * 0.5), (ya + cw * 0.55, z0 + h * 0.85),
                         (ya + cw * 0.85, z0 + h * 0.85), (ya + cw * 0.3, z0 + h * 0.5),
                         (ya + cw * 0.85, z0 + h * 0.15)], tuple(el["rgba"]))
        elif k == "disc":
            cy, cz, r = el["y"], el["z"], el["r"]
            (x0, yy0), (x1, yy1) = px(cy - r, cz + r), px(cy + r, cz - r)
            d.ellipse((x0, yy0, x1, yy1), fill=tuple(el["rgba"]))
            if "ring" in el:
                rr = r * el["ring"][0]
                (x0, yy0), (x1, yy1) = px(cy - rr, cz + rr), px(cy + rr, cz - rr)
                d.ellipse((x0, yy0, x1, yy1), fill=tuple(el["ring"][1]))
        elif k == "text":
            patch = text_patch(el["text"], el["height"], tuple(el["rgba"]),
                               plate=(el["plate"]["w"], el["plate"]["h"], tuple(el["plate"]["rgba"]),
                                      el["plate"]["radius"]) if "plate" in el else None,
                               shear=el.get("shear", 0.18))
            if side == "right":
                patch = patch.transpose(Image.FLIP_LEFT_RIGHT)
            x, y = px(el["y"], el["z"])
            lay.alpha_composite(patch, (round(x - patch.width / 2), round(y - patch.height / 2)))
        elif k == "flag":
            y0, z0, w, h = el["y"], el["z"], el["w"], el["h"]
            flag = us_flag(round(w / RES), round(h / RES))
            lay.alpha_composite(flag, tuple(round(v) for v in px(y0, z0 + h)))
        img.alpha_composite(lay)
        rough.paste(round(el.get("roughness", 0.3) * 255), mask=lay.getchannel("A"))
    return img, rough


def top_sheet():
    """Top-view sheet for `top_elements` (keys x, y): image right is +x, image top is +y (the rear),
    so text reads upright for someone standing in front of the car."""
    T = spec["top_frame"]
    assert abs(T["res_m"] - RES) < 1e-12, "top_frame res_m must equal frame res_m"
    tw, th = round((T["x1"] - T["x0"]) / RES), round((T["y1"] - T["y0"]) / RES)
    img = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    rough = Image.new("L", (tw, th), 0)
    for el in spec["top_elements"]:
        lay = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
        if el["kind"] != "text":
            raise ValueError(f"top element kind {el['kind']!r} not supported")
        patch = text_patch(el["text"], el["height"], tuple(el["rgba"]),
                           plate=(el["plate"]["w"], el["plate"]["h"], tuple(el["plate"]["rgba"]),
                                  el["plate"]["radius"]) if "plate" in el else None,
                           shear=el.get("shear", 0.18))
        x, y = (el["x"] - T["x0"]) / RES, (T["y1"] - el["y"]) / RES
        lay.alpha_composite(patch, (round(x - patch.width / 2), round(y - patch.height / 2)))
        img.alpha_composite(lay)
        rough.paste(round(el.get("roughness", 0.3) * 255), mask=lay.getchannel("A"))
    return img, rough


if spec.get("top_elements"):
    t, tr = top_sheet()
    t.save(out / "livery_top.png")
    tr.save(out / "livery_top_roughness.png")
    print("SHEET top", t.size, "->", out / "livery_top.png")
for side in ("left", "right"):
    s, r = sheet(side)
    s.save(out / f"livery_{side}.png")
    r.save(out / f"livery_{side}_roughness.png")
    print("SHEET", side, s.size, "->", out / f"livery_{side}.png")
if "--overlay" in sys.argv:
    i = sys.argv.index("--overlay")
    for side, path in (("left", sys.argv[i + 1]), ("right", sys.argv[i + 2])):
        ortho = Image.open(path).convert("RGBA").resize((W, H))
        sh = Image.open(out / f"livery_{side}.png")
        if side == "right":
            ortho = ortho.transpose(Image.FLIP_LEFT_RIGHT)  # the right render looks from -x: put it in the y frame
        ortho.alpha_composite(sh)
        view = ortho.transpose(Image.FLIP_LEFT_RIGHT) if side == "right" else ortho
        view.convert("RGB").save(out / f"overlay_{side}.jpg", quality=88)
        print("OVERLAY", out / f"overlay_{side}.jpg")
