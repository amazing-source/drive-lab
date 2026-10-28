"""Tiles images into one labelled contact sheet.  python -I contact_sheet.py <out.png> <cell px> <img> [...]"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

out, cell, files = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
cols = min(5, len(files))
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * cell, rows * (cell + 18)), (30, 30, 30))
draw = ImageDraw.Draw(sheet)
for i, name in enumerate(files):
    img = Image.open(name).convert("RGB").resize((cell, cell))
    x, y = (i % cols) * cell, (i // cols) * (cell + 18)
    sheet.paste(img, (x, y + 18))
    draw.text((x + 4, y + 3), Path(name).stem, fill=(255, 255, 255))
sheet.save(out)
