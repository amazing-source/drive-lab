"""
Compares car_entry_check.py records of the same bakes in three runs: the checker before the
per-group rule (OLD), the new checker deepest-only (DEEP), and the new checker per group (PG).

  python -I compare_modes.py <OLD dir> <DEEP dir> <PG dir> entry exit close [...]

Each dir holds check_<name>.json. Prints, per bake: whether DEEP reproduces OLD exactly, the
failures PG adds over DEEP, and every secondary contact PG tested (a group past the tolerance that
was not the part's deepest on that frame) against its own allowance.
"""
import json
import sys


def load(folder, name):
    with open(f"{folder}/check_{name}.json", encoding="utf-8") as handle:
        return json.load(handle)


def allowance(allow, frame, part, group, tol):
    depths = [a.get("depth", 0.0) for a in allow if a["from"] <= frame <= a["to"] and part in a["parts"] and group in a["groups"]]
    return max(depths + [tol])


def main(argv):
    old_dir, deep_dir, pg_dir, names = argv[0], argv[1], argv[2], argv[3:]
    for name in names:
        old, deep, pg = load(old_dir, name), load(deep_dir, name), load(pg_dir, name)
        same = old["failures"] == deep["failures"] and old["rows"] == deep["rows"]
        others = [k for k in old if k not in ("rows", "failures", "baked") and old[k] != deep.get(k)]
        print(f"== {name}: bake {pg['baked_sha256'][:12]}, scene {pg['scene_sha256'][:12]}, allow {(pg['allow_sha256'] or 'none')[:12]}, {pg['frames']} frames")
        print(f"  DEEP reproduces OLD: failures and rows {'identical' if same else 'DIFFER'}; other fields differing: {others or 'none'}")
        print(f"  modes recorded: DEEP per_group={deep['per_group']}, PG per_group={pg['per_group']}")
        deep_set = {tuple(f) for f in deep["failures"]}
        pg_set = {tuple(f) for f in pg["failures"]}
        print(f"  failures: DEEP {len(deep_set)}, PG {len(pg_set)}; only in PG {len(pg_set - deep_set)}; only in DEEP {len(deep_set - pg_set)}")
        for f in sorted(pg_set - deep_set):
            print(f"    new: f{f[0]:g} {f[1]} {f[2]} {f[3]}")
        tol, runs = pg["tol"], {}
        for row in pg["rows"]:
            for part, v in row["parts"].items():
                for group, depth in v["groups"].items():
                    if depth > tol and group != v["group"]:
                        limit = allowance(pg["allow"], row["frame"], part, group, tol)
                        runs.setdefault((part, group, limit), []).append((row["frame"], depth, v["group"], v["depth"]))
        count = sum(len(v) for v in runs.values())
        print(f"  secondary contacts past tol {tol} (part-frames): {count}")
        for (part, group, limit), xs in sorted(runs.items(), key=lambda kv: kv[1][0][0]):
            frame, depth, top, top_depth = max(xs, key=lambda x: x[1])
            print(
                f"    {part:10s} {group:9s} max {depth:.4f} at f{frame:g}  limit {limit:.4f}  margin {limit - depth:+.4f}"
                f"  (deepest there: {top} {top_depth:.4f}); frames {' '.join(f'{x[0]:g}' for x in xs)}"
            )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
