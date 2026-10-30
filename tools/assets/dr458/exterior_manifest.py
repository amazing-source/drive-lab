"""Write manifest/exterior.json (the 3D lead's area) from the assembly reports and a master inventory.

    DR458_WORK=<drive-lab-assets/dr458/work> python -I exterior_manifest.py <inventory.json> <out.json>

inventory.json is assembly/inventory.py's output for the master being described (triangles and
collections per object). Wheel centres come from assembly/wheels_report.json, the Door_L hinge from
assembly/hinge_report.json; Blender (x, y, z) becomes {forward = -y, right = -x, up = z}.
"""
import json
import os
import math
import sys
from pathlib import Path

WORK = Path(os.environ["DR458_WORK"])  # drive-lab-assets/dr458/work: the files live outside the repo
inv = {o["name"]: o for o in json.load(open(sys.argv[1]))["objects"]}
wheels = json.load(open(WORK / "assembly" / "wheels_report.json"))
hinge = json.load(open(WORK / "assembly" / "hinge_report.json"))["door_L_hinge"]
FILE = "work/assembly/dr458_master_v11_final.blend"


def m(v):
    return {"forward": round(-v[1], 4), "right": round(-v[0], 4), "up": round(v[2], 4)}


def tris(*names):
    return sum(inv[n]["tris"] for n in names if n in inv)


def like(*subs, col=None):
    return [n for n, o in inv.items() if any(s in n for s in subs) and (col is None or o["col"] == col)]


parts = []
for corner, src in (("FL", "FL"), ("FR", "FL"), ("RL", "RL"), ("RR", "RL")):
    c = list(wheels["corners"][src]["wheel_centre_m"])
    if corner.endswith("R"):
        c[0] = -c[0]
    w = f"Wheel_{corner}"
    parts.append({"name": w, "group": w, "motion": "spin", "pivot": m(c), "axis": {"forward": 0.0, "right": -1.0, "up": 0.0},
                  "positive": "rolls forward (top of the wheel moves toward the nose)",
                  "materials": ["aluminium_anodised_black"], "triangles": tris(w),
                  "measured_from": "wheel centre: track and axle from assembly/wheels_report.json (research 1.5 tyre sizes, rule ride heights)",
                  "source": "codex_wheels_src (Codex DR458 rim, fitted)", "file": FILE})
    for piece, mat in (("Tyre", "rubber"), ("Disc", "stainless_brushed"), ("DiscBell", "aluminium_brushed"), ("Nut", "aluminium_anodised_black")):
        parts.append({"name": f"{w}_{piece}", "group": w, "motion": "static", "materials": [mat], "triangles": tris(f"{w}_{piece}"),
                      "measured_from": "assembly/wheels_report.json built dimensions", "source": "tyres296_src / codex_wheels_src", "file": FILE})
    parts.append({"name": f"Caliper_{corner}", "group": f"Caliper_{corner}", "motion": "static", "materials": ["aluminium_brushed"],
                  "triangles": tris(f"Caliper_{corner}"), "note": "follows the upright (steers at the front), never spins",
                  "measured_from": "assembly/wheels_report.json", "source": "Forza 458 Italia brake, fitted", "file": FILE})
door_L = like("doorLF_")
parts.append({"name": "Door_L_Skin", "group": "Door_L", "motion": "hinge", "pivot": hinge["pivot_manifest"], "axis": hinge["axis_manifest"],
              "range": round(math.radians(hinge["clash_free_open_deg"]), 4),
              "positive": "opens: the door's rear edge swings out to the car's left",
              "materials": ["paint_red_clearcoat", "rubber", "plastic_black"], "triangles": tris(*door_L),
              "measured_from": "hinge fitted to the door's front shut line (assembly/hinge_report.json); 75 deg clash-free against the body, and against the cage (cockpit modeller's check: at least 18.1 mm)",
              "source": "Forza 458 Italia door, own hinge fit", "file": FILE, "objects": door_L})
for side, sub in (("L", "L"), ("R", "R")):
    if side == "R":
        dr = like("doorRF_")
        parts.append({"name": "Door_R_Skin", "group": "Door_R", "motion": "static", "materials": ["paint_red_clearcoat", "rubber", "plastic_black"],
                      "triangles": tris(*dr), "measured_from": "Forza 458 Italia door at the body's shut lines", "source": "Forza 458 Italia",
                      "file": FILE, "objects": dr})
    g = like(f"glass{sub}F_window")
    parts.append({"name": f"Door_{side}_Glass", "group": f"Door_{side}", "motion": "static", "materials": ["glass_clear"], "triangles": tris(*g),
                  "measured_from": "Forza 458 Italia side glass", "source": "Forza 458 Italia", "file": FILE, "objects": g})
    mi = like(f"mirror{sub}_")
    parts.append({"name": f"Door_{side}_Mirror", "group": f"Door_{side}", "motion": "static", "materials": ["plastic_black", "chrome"],
                  "triangles": tris(*mi), "measured_from": "Forza 458 Italia mirror; black caps per exterior/001, 002", "source": "Forza 458 Italia",
                  "file": FILE, "objects": mi})
GLASS = (("Glass_Windscreen", ("glassF_window_", "glassF_black_glass_"), "windscreen with its black frit band"),
         ("Glass_RearScreen", ("glassR_window_",), "screen over the engine"),
         ("Glass_CabinRear", ("body_window_",), "small window behind the cabin"),
         ("Glass_Quarter_L", ("glassLR_window_", "glassLR_black_glass_"), "rear quarter window, left"),
         ("Glass_Quarter_R", ("glassRR_window_", "glassRR_black_glass_"), "rear quarter window, right"))
for name, subs, what in GLASS:
    objs = like(*subs)
    if objs:
        parts.append({"name": name, "group": "Chassis", "motion": "static", "materials": ["glass_clear", "plastic_black"],
                      "triangles": tris(*objs), "note": what, "measured_from": "Forza 458 Italia glass at the body's openings",
                      "source": "Forza 458 Italia", "file": FILE, "objects": objs})
for side, obj in (("L", "Rolled titanium exhaust barrel.001"), ("R", "Rolled titanium exhaust barrel")):
    o = inv.get(obj)
    if not o:
        continue
    lo, hi = o["min"], o["max"]
    centre = [(lo[0] + hi[0]) / 2, hi[1], (lo[2] + hi[2]) / 2]
    parts.append({"name": f"Exhaust_Outlet_{side}", "group": "Chassis", "motion": "static", "materials": ["stainless_brushed"],
                  "triangles": o["tris"], "outlet": {"centre": m(centre), "axis": {"forward": -1.0, "right": 0.0, "up": 0.0},
                                                   "diameter_m": round(min(hi[0] - lo[0], hi[2] - lo[2]), 4)},
                  "note": "outlet centre on the barrel's rear face; axis points out of the pipe (rearward)",
                  "measured_from": "the fitted Evo exhaust barrel's bounds", "source": "codex_evo_src (Evo exhaust, fitted)",
                  "file": FILE, "objects": [obj]})
for e in parts:
    if e["triangles"] > 10000:
        e["note_export"] = "split into several MeshParts at export (over 10,000 triangles)"
json.dump({"file": FILE, "frame": "manifest_schema.json frame", "parts": parts}, open(sys.argv[2], "w"), indent=1)
print("EXTERIOR", len(parts), "parts,", sum(e["triangles"] for e in parts), "triangles")
