"""
Writes an exit table's caged span from the entry's solved table played backwards. The keys module's
MIRROR lists (exit frame, entry frame) at each beat the two share; every exit frame after the first
pair, up to the last, takes the entry's pose (pelvis, torso, neck, limb angles and points) at the
matching entry frame, a fractional entry frame being the linear blend of its two neighbours. A
limb the entry table leaves out on either neighbour (held, aimed by the bake) is left out.

  python car_entry_mirror.py <keys module> <entry_table.json> <exit_table.json> <out.json>
"""
import importlib
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def blend(a, b, w):
    def mix(u, v):
        return [round(float(x) * (1 - w) + float(y) * w, 4) for x, y in zip(u, v)]

    row = {k: mix(a[k], b[k]) for k in ("pelvis", "torso", "neck")}
    for key in ("angles", "targets"):
        row[key] = {limb: mix(v, b[key][limb]) for limb, v in a.get(key, {}).items() if limb in b.get(key, {})}
    return row


def main(argv):
    mod = importlib.import_module(argv[0])
    entry = json.load(open(argv[1], encoding="utf-8"))
    table = json.load(open(argv[2], encoding="utf-8"))
    ex, en = (np.array(v, float) for v in zip(*mod.MIRROR))
    for e in range(int(ex[0]) + 1, int(ex[-1]) + 1):
        n = float(np.interp(e, ex, en))
        n0 = int(np.floor(n + 1e-9))
        w = n - n0
        row = entry[str(n0)] if w < 1e-6 else blend(entry[str(n0)], entry[str(n0 + 1)], w)
        table[str(e)] = {k: row[k] for k in ("pelvis", "torso", "neck", "angles", "targets")}
    json.dump(dict(sorted(table.items(), key=lambda kv: int(kv[0]))), open(argv[3], "w", encoding="utf-8", newline="\n"), indent=0)
    print(f"exit f{int(ex[0]) + 1}-f{int(ex[-1])} from entry f{np.interp(ex[0] + 1, ex, en):.2f}-f{en[-1]:.0f}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
