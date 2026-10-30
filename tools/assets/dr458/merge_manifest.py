"""Merge the per-area manifests into dr458_manifest.json and validate every entry.

    DR458_WORK=<drive-lab-assets/dr458/work> python -I merge_manifest.py <out.json> <area.json> [<area.json> ...]

Each area file is {"file", "frame", "parts": [...]} as manifest_schema.json describes. Validation
(any failure lists every problem and exits 1, writing nothing):
- required fields present; motion one of the schema's types;
- pivot and axis present unless static (or emissive), with numeric forward/right/up;
- axes unit length (to 1e-3); hinge range a positive angle up to pi; press range a travel of
  0-50 mm; toggle/rotary/removable ranges a list of angles;
- names unique across all areas; every moving or emissive part carries an agreed contract name
  (plan/dr458_parts_draft.json, since the binding looks it up by name); a static part, which the
  binding never looks up, is <Area>_<Piece>[_...] with a known area (e.g. Cabin_Battery_Case);
- materials known to materials/library/library.json; triangles a positive integer, at most 10,000;
- a pivot with no mesh of its own (an assembly's hub, such as the steering wheel's) says
  "mesh": false and may have 0 triangles and no materials; a hinge whose angle another system
  drives says "driven_by" instead of a range;
- every group resolves: a part's group is another part (the thing it rides on), an assembly in the
  parts draft, or Chassis; following groups from part to part never loops. A static part riding a
  moving one may be named <its group>_<Piece>.
- optional "points" per area file, {name: {forward, right, up, how}}: named reference points in the
  same frame (such as the driver's H-point), merged into a top-level "points"; names unique across
  files, numeric forward/right/up in metres, "how" a non-empty provenance string.
Rotation sense: axes are the Blender axis converted component-wise and a positive turn is the
right-hand rule in Blender's frame. The {forward, right, up} frame itself is left-handed, but mapped
to Roblox as (x = right, y = up, z = -forward) the whole chain is Blender (x, y, z) -> Roblox
(-x, z, y), a proper rotation, so the sense carries over unchanged. Each moving part should still
carry "positive" saying physically what a positive turn or travel does.
"""
import json
import os
import math
import re
import sys
from pathlib import Path

WORK = Path(os.environ["DR458_WORK"])  # drive-lab-assets/dr458/work: the files live outside the repo
HERE = WORK / "manifest"
out, areas = sys.argv[1], sys.argv[2:]
schema = json.load(open(HERE / "manifest_schema.json"))
lib = {m["name"] for m in json.load(open(WORK / "materials" / "library" / "library.json"))["materials"]}
draft = json.load(open(WORK / "plan" / "dr458_parts_draft.json"))
known, groups = set(), set()


def walk(x):
    if isinstance(x, dict):
        if "name" in x:
            known.add(x["name"])
            groups.add(x["name"])
        for p in x.get("parts", []) if isinstance(x.get("parts"), list) else []:
            if isinstance(p, str):
                known.add(p)
        for v in x.values():
            if isinstance(v, (list, dict)):
                walk(v)
    elif isinstance(x, list):
        for y in x:
            walk(y)


walk(draft["assemblies"])
STATIC = r"(Body|Cabin|Cage|Door_[LR]|Tunnel|Engine|Glass|Evo|Aero|Floor|Seat|Harness|Dash|Binnacle|SwitchPanel|SteeringWheel|SteeringColumn|WindowNet|Pedal|Cooler|Duct|Exhaust)_[A-Za-z0-9]+(_[A-Za-z0-9]+)*"
MOTIONS = {"static", "spin", "hinge", "press", "toggle", "rotary", "removable", "emissive"}
problems, parts, seen = [], [], {}


def vec(e, k):
    v = e.get(k)
    if not isinstance(v, dict) or not all(isinstance(v.get(c), (int, float)) for c in ("forward", "right", "up")):
        return None
    return [v["forward"], v["right"], v["up"]]


points, point_from = {}, {}
for path in areas:
    doc = json.load(open(path))
    for pn, pv in (doc.get("points") or {}).items():
        where = f"{Path(path).name}:points.{pn}"
        if pn in point_from:
            problems.append(f"{where}: point name also in {point_from[pn]}")
        point_from[pn] = Path(path).name
        if vec({"p": pv}, "p") is None:
            problems.append(f"{where}: needs numeric forward, right, up in metres")
        if not (isinstance(pv, dict) and isinstance(pv.get("how"), str) and pv["how"].strip()):
            problems.append(f"{where}: needs a 'how' provenance string")
        points[pn] = pv
    for e in doc["parts"]:
        n = e.get("name", "?")
        where = f"{Path(path).name}:{n}"
        for k in ("name", "group", "motion", "materials", "triangles", "measured_from", "source", "file"):
            if k not in e:
                problems.append(f"{where}: missing {k}")
        m = e.get("motion")
        if m not in MOTIONS:
            problems.append(f"{where}: motion {m!r} not in {sorted(MOTIONS)}")
        if m not in ("static", "emissive"):
            p, a = vec(e, "pivot"), vec(e, "axis")
            if p is None or a is None:
                problems.append(f"{where}: {m} needs pivot and axis as {{forward, right, up}}")
            elif abs(math.sqrt(sum(c * c for c in a)) - 1) > 1e-3:
                problems.append(f"{where}: axis not unit length ({math.sqrt(sum(c * c for c in a)):.4f})")
            r = e.get("range")
            if m == "hinge" and not e.get("driven_by") and not (isinstance(r, (int, float)) and 0 < r <= math.pi):
                problems.append(f"{where}: hinge range must be an angle in (0, pi] rad, got {r!r}")
            if m == "press" and not (isinstance(r, (int, float)) and 0 < r <= 0.05):
                problems.append(f"{where}: press range must be a travel in (0, 0.05] m, got {r!r}")
            if m in ("toggle", "rotary", "removable") and not (isinstance(r, list) and r and all(isinstance(x, (int, float)) for x in r)):
                problems.append(f"{where}: {m} range must be a list of detent angles, got {r!r}")
        if n in seen:
            problems.append(f"{where}: name also in {seen[n]}")
        seen[n] = Path(path).name
        bound = (n in known or re.fullmatch(r"(Wheel|Caliper)_(FL|FR|RL|RR)(_[A-Za-z]+)?", n)
                 or re.fullmatch(r"ShiftLight_[1-8]", n) or re.fullmatch(r"Light_[A-Za-z]+_[A-Za-z]+", n))
        if m not in ("static", None) and not bound:
            problems.append(f"{where}: a {m} part must carry an agreed contract name (the binding looks it up)")
        rider = isinstance(e.get("group"), str) and n.startswith(e["group"] + "_") and e["group"] != "Chassis"
        if m == "static" and not (bound or rider or re.fullmatch(STATIC, n)):
            problems.append(f"{where}: static name must be <Area>_<Piece>[_...] with a known area")
        for mat in e.get("materials", []):
            if mat not in lib:
                problems.append(f"{where}: material {mat!r} not in library.json")
        t = e.get("triangles")
        if e.get("mesh") is False:
            if t not in (0, None):
                problems.append(f"{where}: a part with no mesh carries no triangles, got {t!r}")
        elif not (isinstance(t, int) and 0 < t <= 10000):
            problems.append(f"{where}: triangles must be an integer in 1..10000, got {t!r}")
        e["_where"] = where
        parts.append(e)
by_name = {e["name"]: e for e in parts if "name" in e}
for e in parts:
    n, g, where = e.get("name"), e.get("group"), e.pop("_where")
    if g not in by_name and g not in groups and g != "Chassis":
        problems.append(f"{where}: group {g!r} is neither a part, an assembly of the parts draft, nor Chassis")
    chain = [n]
    while g in by_name and g != chain[-1]:
        if g in chain:
            problems.append(f"{where}: group chain loops: {' -> '.join(chain + [g])}")
            break
        chain.append(g)
        g = by_name[g].get("group")
if problems:
    print(f"MANIFEST FAIL: {len(problems)} problems")
    for p in problems:
        print("  " + p)
    sys.exit(1)
merged = {"about": "DR458 merged manifest, written by merge_manifest.py; do not edit by hand.",
          "frame": schema["frame"],
          "rotation_sense": "axes are Blender axes converted component-wise; a positive turn is the right-hand rule in Blender's frame, and stays so in Roblox when mapped as x = right, y = up, z = -forward (Blender (x, y, z) -> Roblox (-x, z, y) is a proper rotation); never compute a rotation in the {forward, right, up} components themselves, a left-handed frame; each moving part's 'positive' says physically what it does",
          "sources": [Path(p).name for p in areas], "parts": parts}
if points:
    merged["points"] = points
json.dump(merged, open(out, "w"), indent=1)
print(f"MANIFEST OK: {len(parts)} parts, {len(points)} points from {len(areas)} files -> {out}")
