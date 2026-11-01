"""Put renders beside reference photos, one row per pair, labelled.

python -I tools/assets/dr458/side_by_side.py <out.jpg> <render.png>=<photo.jpg> [...]

Each photo is centre-cropped to the render's aspect and both are scaled to 540 px high.
"""
import sys

from PIL import Image, ImageDraw

out, pairs = sys.argv[1], [a.split("=", 1) for a in sys.argv[2:]]
H = 540
rows = []
for render, photo in pairs:
    r = Image.open(render).convert("RGB")
    p = Image.open(photo).convert("RGB")
    aspect = r.width / r.height
    if p.width / p.height > aspect:
        w = int(p.height * aspect)
        p = p.crop(((p.width - w) // 2, 0, (p.width + w) // 2, p.height))
    else:
        h = int(p.width / aspect)
        p = p.crop((0, (p.height - h) // 2, p.width, (p.height + h) // 2))
    r, p = r.resize((int(H * aspect), H)), p.resize((int(H * aspect), H))
    row = Image.new("RGB", (r.width + p.width + 8, H), "white")
    row.paste(r, (0, 0))
    row.paste(p, (r.width + 8, 0))
    d = ImageDraw.Draw(row)
    d.text((8, 8), render.replace("\\", "/").split("/")[-1], fill=(255, 255, 0))
    d.text((r.width + 16, 8), photo.replace("\\", "/").split("/")[-1], fill=(255, 255, 0))
    rows.append(row)
sheet = Image.new("RGB", (max(x.width for x in rows), sum(x.height + 8 for x in rows)), "white")
y = 0
for row in rows:
    sheet.paste(row, (0, y))
    y += row.height + 8
sheet.save(out, quality=88)
print("SHEET", out)
