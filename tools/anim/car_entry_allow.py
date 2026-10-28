"""Writes the car-entry allow lists (car_entry_check.py --allow): base hand allowances, decided contacts at their measured depth, and touch
requirements on every frame a hand contact can physically touch (the keys' reach report) or is held
exactly (door edge, strap, bar, release, corner).

  python tools/anim/car_entry_allow.py <car_entry_dir> <keys.log> [--measure check_entry.json,check_exit.json]

Without --measure, the decided contacts get a placeholder depth of 0 (so the check reports their
real depth as failures); with it, each decided contact's depth is the maximum the check measured
for those parts, groups and frames.
"""
import json
import math
import re
import sys

D = sys.argv[1]
log = open(sys.argv[2], encoding="utf-8").read()
measure = {}
if "--measure" in sys.argv:
    for path in sys.argv[sys.argv.index("--measure") + 1].split(","):
        measure[path] = json.load(open(f"{D}/{path}", encoding="utf-8"))["failures"]

ARMS = ["Right Arm", "Left Arm"]
LEGS = ["Right Leg", "Left Leg"]
SURF = ["sill", "paint", "interior", "carbon", "trim"]
DOOR = ["door", "interior", "carbon", "trim"]


def reach_spans(label):
    m = re.search(re.escape(label) + r" f\d+-f\d+: within reach (.*)", log)
    if not m or m.group(1).strip() == "never":
        return []
    return [tuple(int(v) for v in pair) for pair in re.findall(r"\((\d+), (\d+)\)", m.group(1))]


def measured(check, parts, groups, start, end):
    worst = 0.0
    for f, part, group, depth in measure.get(check, []):
        if start <= f <= end and part in parts and group in groups:
            worst = max(worst, depth)
    return math.ceil(worst * 1000 + 1) / 1000 if worst else 0.0  # rounded up, never below what was measured


THIGHS_ON_SILL = max(
    measured("check_entry.json", LEGS, ["sill", "paint"], 160, 184), measured("check_exit.json", LEGS, ["sill", "paint"], 88, 118)
)


def touch(label, part, groups, gap=0.1):
    return [
        {"why": f"{label}: must touch (within reach)", "from": a, "to": b, "parts": [part], "groups": groups, "touch": gap}
        for a, b in reach_spans(label)
    ]


entry = [
    {"why": "right hand on the release, pressing and lifting", "from": 22, "to": 42, "parts": ["Right Arm"], "groups": ["door", "paint", "carbon", "trim", "glass"], "depth": 0.15},
    {"why": "hands on the sill behind the perch", "from": 142, "to": 168, "parts": ARMS, "groups": SURF, "depth": 0.15},
    {"why": "bottom on the lip", "from": 148, "to": 166, "parts": ["Torso"], "groups": ["sill", "paint"], "depth": 0.1},
    {"why": "right hand on the cabin wall, left on the lip, through the hoist", "from": 166, "to": 196, "parts": ARMS, "groups": SURF, "depth": 0.15},
    {"why": "left hand on the door's lower inner edge, riding it from 45 to 30 degrees (#9)", "from": 184, "to": 200, "parts": ["Left Arm"], "groups": DOOR, "depth": 0.12},
    {"why": "left hand on the strap pulling the door shut (#31)", "from": 196, "to": 214, "parts": ["Left Arm"], "groups": DOOR, "depth": 0.12},
    {"why": "DECIDED (#9 thread): thighs resting on the cabin wall's top while sliding over it (a rigid R6 thigh hinged at its top edge)", "from": 186, "to": 202, "parts": LEGS, "groups": ["interior", "trim", "carbon", "sill"],
     "depth": measured("check_entry.json", LEGS, ["interior", "trim", "carbon", "sill"], 186, 202)},
    {"why": "DECIDED (lead, rigid-thigh class): thighs over the sill's lip while the legs swing in; one allowance with the exit's thighs-on-sill, at their measured maximum", "from": 160, "to": 184, "parts": LEGS, "groups": ["sill", "paint"],
     "depth": THIGHS_ON_SILL},
    {"why": "right hand on the release: must touch", "from": 26, "to": 38, "parts": ["Right Arm"], "groups": ["door", "paint", "carbon", "trim", "glass"], "touch": 0.1},
    {"why": "left hand on the door's lower inner edge: must touch", "from": 186, "to": 198, "parts": ["Left Arm"], "groups": DOOR, "touch": 0.1},
]
entry += touch("GetIn right hand on the sill", "Right Arm", SURF)
entry += touch("GetIn left hand on the sill", "Left Arm", SURF)
entry += touch("GetIn right hand on the cabin wall", "Right Arm", SURF)
entry += touch("GetIn left hand on the lip", "Left Arm", SURF)

exit_ = [
    {"why": "left hand on the release bar, pulling it and pushing the door up", "from": 12, "to": 26, "parts": ["Left Arm"], "groups": DOOR, "depth": 0.12},
    {"why": "DECIDED (lead): upper arm resting on the door card while reaching the release, at its measured depth", "from": 6, "to": 11, "parts": ["Left Arm"], "groups": DOOR,
     "depth": measured("check_exit.json", ["Left Arm"], DOOR, 6, 11)},
    {"why": "hands on the cabin wall and the lip through the hoist out", "from": 58, "to": 116, "parts": ARMS, "groups": SURF, "depth": 0.15},
    {"why": "DECIDED (#9 thread): thighs resting on the cabin wall's top while sliding over it (a rigid R6 thigh hinged at its top edge)", "from": 66, "to": 92, "parts": LEGS, "groups": ["interior", "trim", "carbon", "sill"],
     "depth": measured("check_exit.json", LEGS, ["interior", "trim", "carbon", "sill"], 66, 92)},
    {"why": "INHERITED, TIGHTENED (rigid-thigh class): thighs over the sill's edge while swinging out and perched; one allowance with the entry's thighs over the lip, at their measured maximum", "from": 88, "to": 118, "parts": LEGS, "groups": ["sill", "paint"],
     "depth": THIGHS_ON_SILL},
    {"why": "bottom on the lip", "from": 102, "to": 120, "parts": ["Torso"], "groups": ["sill", "paint"], "depth": 0.1},
    {"why": "right hand on the door's lower front corner pulling it down", "from": 228, "to": 250, "parts": ["Right Arm"], "groups": ["door", "paint", "carbon", "trim"], "depth": 0.15},
    {"why": "left hand on the release bar: must touch", "from": 14, "to": 24, "parts": ["Left Arm"], "groups": DOOR, "touch": 0.1},
]
exit_ += touch("GetOut right hand on the cabin wall", "Right Arm", SURF)
exit_ += touch("GetOut left hand on the lip", "Left Arm", SURF)
exit_ += touch("GetOut right hand on the sill", "Right Arm", SURF)
exit_ += touch("GetOut left hand on the sill", "Left Arm", SURF)

close = [
    {"why": "left hand on the strap pulling the door shut (#31)", "from": 24, "to": 42, "parts": ["Left Arm"], "groups": DOOR, "depth": 0.12},
]
for name, data in (("entry", entry), ("exit", exit_), ("close", close)):
    json.dump(data, open(f"{D}/allow_{name}.json", "w", encoding="utf-8", newline="\n"), indent=1)
    print(name, len(data), "entries;", [(a["why"][:50], a.get("depth"), a["from"], a["to"]) for a in data if a["why"].startswith(("DECIDED", "PROPOSED", "INHERITED"))])
