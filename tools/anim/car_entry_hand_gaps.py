"""The hand-to-surface gap over each authored hand-push span (analysis only, never the gate: the gate is car_entry_check.py with the allow lists):
how far each hand is from its surface on the frames it cannot reach.

  python tools/anim/car_entry_hand_gaps.py <car_entry_dir>
"""
import json
import subprocess
import sys

D = sys.argv[1]
import os
TOOLS = os.path.dirname(os.path.abspath(__file__))
SURF = ["sill", "paint", "interior", "carbon", "trim"]
spans = {
    "entry": [
        ("GetIn right hand on the sill", "Right Arm", 154, 164),
        ("GetIn left hand on the sill", "Left Arm", 154, 162),
        ("GetIn right hand on the cabin wall", "Right Arm", 170, 190),
        ("GetIn left hand on the lip", "Left Arm", 170, 173),
    ],
    "exit": [
        ("GetOut right hand on the cabin wall", "Right Arm", 60, 98),
        ("GetOut left hand on the lip", "Left Arm", 61, 98),
        ("GetOut right hand on the sill", "Right Arm", 105, 114),
        ("GetOut left hand on the sill", "Left Arm", 105, 114),
    ],
}
out = {}
for t, rows in spans.items():
    allow = [{"why": label, "from": a, "to": b, "parts": [p], "groups": SURF, "touch": 0.1} for label, p, a, b in rows]
    path = f"{D}/gaps_allow_{t}.json"
    json.dump(allow, open(path, "w"))
    subprocess.run([sys.executable, "-I", f"{TOOLS}/car_entry_check.py", f"{D}/{t}.baked.json", f"{D}/scene.npz", "--allow", path, "--json", f"{D}/gaps_{t}.json", "--tol", "9"], capture_output=True)
    rows_out = json.load(open(f"{D}/gaps_{t}.json"))["rows"]
    gap = {(r["frame"], p): v.get("gap") for r in rows_out for p, v in r["parts"].items() if v.get("gap") is not None}
    for label, part, a, b in rows:
        g = [(f, gap.get((float(f), part), gap.get((f, part)))) for f in range(a, b + 1)]
        g = [(f, v) for f, v in g if v is not None]
        far = [(f, v) for f, v in g if v > 0.1]
        out[label] = {"frames": f"{a}-{b}", "touching": len(g) - len(far), "of": len(g), "max_gap": max((v for _, v in g), default=None), "gap_by_frame": {f: v for f, v in g}}
        print(f"{label}: touching {len(g) - len(far)} of {len(g)} frames; max gap {out[label]['max_gap']} studs (scale 1)")
json.dump(out, open(f"{D}/hand_gaps.json", "w"), indent=1)
