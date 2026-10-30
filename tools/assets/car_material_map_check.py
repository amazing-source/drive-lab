"""Check a material map covers every material slot the driver can see.

    python -I tools/assets/car_material_map_check.py <inventory_eye.json> <map.json> [--min-px N]

Every visible object (car_eye_inventory.py, any view group, at least N pixels, default 1) must have an
object rule, or each of its slots a material rule, a `keep` entry, or a material named after a
library set (taken as that set); a slot with no material needs an object rule. Every set named
must exist in the library (or the map's `derived`). Exit 1 on a gap.
"""
import json
import re
import sys
from pathlib import Path

inv = json.loads(Path(sys.argv[1]).read_text())
M = json.loads(Path(sys.argv[2]).read_text())
min_px = int(sys.argv[sys.argv.index("--min-px") + 1]) if "--min-px" in sys.argv else 1
lib = {m["name"] for m in json.loads((Path(M["library"]) / "library.json").read_text())["materials"]}
lib |= set(M.get("derived", {}))


def base(n):
    return re.sub(r"\.\d{3}$", "", n)


gaps, sets, n = [], set(), 0
for r in inv["objects"]:
    if r["px_ahead"] + r["px_around"] < min_px:
        continue
    n += 1
    rule = M["objects"].get(r["object"])
    if rule:
        sets |= {rule["set"]} if "set" in rule else {rule["split_by_normal"]["up"], rule["split_by_normal"]["other"]}
        continue
    if not r["materials"]:
        gaps.append(f"{r['object']}: no material slot and no object rule")
    for m in r["materials"]:
        name = m.get("name")
        if name is None:
            if len(r["materials"]) == 1:
                gaps.append(f"{r['object']}: empty slot and no object rule")
            continue
        if base(name) in M["materials"]:
            sets.add(M["materials"][base(name)]["set"])
        elif base(name) in M["keep"]:
            continue
        elif base(name) in lib:
            sets.add(base(name))
        else:
            gaps.append(f"{r['object']} ({r['px_ahead']}+{r['px_around']} px): material {name!r} neither mapped nor kept")
unknown = sorted(s for s in sets if s not in lib)
for s in unknown:
    gaps.append(f"set {s!r} is not in the library")
print(f"CHECK_MAP {n} visible objects, {len(sets)} sets used, {len(gaps)} gaps")
for g in gaps:
    print("  GAP", g)
sys.exit(1 if gaps else 0)
