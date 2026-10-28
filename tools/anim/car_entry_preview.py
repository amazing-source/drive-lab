"""
Quick orthographic previews of a bake against the car, without Blender: the car's points within a
slab around the body (faint), the door at that frame (orange), the R6 boxes (blue outlines, the
torso filled), from the side (looking along +Z into the car), the top and the front. For iterating
on keys between Blender runs; the review renders come from tools/blender/car_entry_scene.py.

  python car_entry_preview.py <baked.json> <scene.npz> <out.png> --frames 66,80,100 [--views side,top,front]
"""
import argparse
import sys

import numpy as np
from PIL import Image, ImageDraw

from car_entry_check import HALF, frame_matrix, rotation_about, sample

VIEWS = {
    # (horizontal axis, sign), (vertical axis, sign), depth axis
    "side": ((0, 1), (1, 1), 2),
    "top": ((0, 1), (2, 1), 1),
    "front": ((2, -1), (1, 1), 0),
}
EDGES = [(0, 1), (0, 2), (0, 4), (1, 3), (1, 5), (2, 3), (2, 6), (3, 7), (4, 5), (4, 6), (5, 7), (6, 7)]


def box_corners(m, half):
    s = np.array([[x, y, z] for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)], dtype=float)
    return (s * np.asarray(half)) @ m[:3, :3].T + m[:3, 3]


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("baked")
    parser.add_argument("scene")
    parser.add_argument("out")
    parser.add_argument("--frames", required=True)
    parser.add_argument("--views", default="side,top,front")
    parser.add_argument("--scale", type=float, default=34)
    parser.add_argument("--slab", type=float, default=1.2, help="depth of car shown around the body")
    parser.add_argument("--box", default="-8,-1,-9,5,9,3", help="lo x,y,z,hi x,y,z shown")
    args = parser.parse_args(argv)
    import json

    baked = {f["frame"]: f for f in json.load(open(args.baked, encoding="utf-8"))["frames"]}
    scene = np.load(args.scene, allow_pickle=False)
    car = np.concatenate(
        [sample(scene[f"v_{g}"].astype(float), scene[f"f_{g}"], 0.12) for g in [str(g) for g in scene["groups"]]]
    )
    door = None
    if "v_door" in scene:
        door = sample(scene["v_door"].astype(float), scene["f_door"], 0.12) - scene["hinge_pivot"]
    frames = [int(v) for v in args.frames.split(",")]
    views = args.views.split(",")
    box = [float(v) for v in args.box.split(",")]
    lo, hi = np.array(box[:3]), np.array(box[3:])
    sc = args.scale
    tiles = []
    for fr in frames:
        f = baked[fr]
        door_pts = None
        if door is not None:
            door_pts = door @ rotation_about(scene["hinge_axis"], f.get("door", 0) * float(scene["open_angle"])).T
            door_pts = door_pts + scene["hinge_pivot"]
        parts = {p: frame_matrix(f["parts"][p]) for p in HALF}
        centre = parts["Torso"][:3, 3]
        row = []
        for view in views:
            (ha, hs), (va, vs), da = VIEWS[view]
            w = int((hi[ha] - lo[ha]) * sc)
            h = int((hi[va] - lo[va]) * sc)
            im = Image.new("RGB", (w, h), (250, 250, 250))
            d = ImageDraw.Draw(im)

            def xy(p):
                x = (p[ha] - lo[ha]) * sc if hs > 0 else (hi[ha] - p[ha]) * sc
                y = h - (p[va] - lo[va]) * sc
                return x, y

            near = car[np.abs(car[:, da] - centre[da]) < args.slab]
            for p in near[:: max(1, len(near) // 60000)]:
                x, y = xy(p)
                if 0 <= x < w and 0 <= y < h:
                    im.putpixel((int(x), int(y)), (150, 150, 160))
            if door_pts is not None:
                dn = door_pts[np.abs(door_pts[:, da] - centre[da]) < args.slab * 2]
                for p in dn[:: max(1, len(dn) // 20000)]:
                    x, y = xy(p)
                    if 0 <= x < w and 0 <= y < h:
                        im.putpixel((int(x), int(y)), (235, 140, 40))
            gy = h - (0 - lo[1]) * sc
            if va == 1:
                d.line([(0, gy), (w, gy)], fill=(90, 160, 90))
            for part, m in parts.items():
                c = box_corners(m, HALF[part])
                colour = (30, 60, 200) if part != "Torso" else (200, 40, 40)
                for i, j in EDGES:
                    d.line([xy(c[i]), xy(c[j])], fill=colour, width=1)
            d.text((4, 4), f"f{fr} {view} door {f.get('door', 0):.2f}", fill=(0, 0, 0))
            row.append(im)
        tiles.append(row)
    tw = sum(t.width for t in tiles[0])
    th = sum(r[0].height for r in tiles)
    sheet = Image.new("RGB", (tw, th), (255, 255, 255))
    y = 0
    for row in tiles:
        x = 0
        for t in row:
            sheet.paste(t, (x, y))
            x += t.width
        y += row[0].height
    sheet.save(args.out)


if __name__ == "__main__":
    main(sys.argv[1:])
