import pathlib, subprocess, sys
# python -I docs/evidence/road-end/mutate.py [numbers]: each break applied, the full suite run,
# the source restored.
ROOT = pathlib.Path(__file__).resolve().parents[3]
SRC = ROOT / "games/drive-lab/src/shared"
MUTANTS = [
    ("1 one section short", "Rules/Roadside.luau", "local count = math.ceil(width / section - 1e-9)", "local count = math.floor(width / section)"),
    ("2 not centred", "Rules/Roadside.luau", "local first = -count * section / 2", "local first = -width / 2"),
    ("3 gaps between sections", "Rules/Roadside.luau", "lefts[index] = first + (index - 1) * section", "lefts[index] = first + (index - 1) * section * 1.1"),
    ("4 no setback", "Config/Roadside.luau", "ROAD_END_SETBACK = 1,", "ROAD_END_SETBACK = 0,"),
]
only = sys.argv[1:]
for name, rel, old, new in MUTANTS:
    if only and name.split()[0] not in only:
        continue
    path = SRC / rel
    original = path.read_bytes()
    text = original.decode("utf-8")
    if text.count(old) != 1:
        print(f"[{name}] PATTERN NOT FOUND ({text.count(old)})")
        continue
    path.write_bytes(text.replace(old, new).encode("utf-8"))
    try:
        out = subprocess.run(["lune", "run", "tools/test/run"], cwd=ROOT, capture_output=True, text=True, timeout=120).stdout
    finally:
        path.write_bytes(original)
    summary = out.strip().splitlines()[-1] if out.strip() else "no output"
    print(f"[{name}] {summary}")
    for line in out.splitlines():
        if line.startswith("FAIL"):
            print("    " + (line.split("tests")[-1] if "tests" in line else line))
