import pathlib, subprocess, sys
# python -I docs/evidence/gearbox-hunt/mutate.py [numbers]: each break is applied to the source,
# the full suite runs, the source is restored. Break 1 is the code before the fix.
ROOT = pathlib.Path(__file__).resolve().parents[3]
SRC = ROOT / "games/drive-lab/src/shared"
MUTANTS = [
    ("1 no hold (the code before the fix)", "Vehicle/Gearbox.luau", "\t\tand state.sinceUpshift >= config.upshiftHoldTime\n", ""),
    ("2 a hold shorter than the dip", "Config/Cars/SVJ.luau", "upshiftHoldTime = 1.0,", "upshiftHoldTime = 0.1,"),
    ("3 every shift starts the hold", "Vehicle/Gearbox.luau", "\tif state.upshift then\n\t\tstate.sinceUpshift = 0\n\tend\n", "\tstate.sinceUpshift = 0\n"),
    ("4 the hold never runs out", "Vehicle/Gearbox.luau", "\tstate.sinceUpshift += dt\n", ""),
    ("5 the hold blocks braking too", "Vehicle/Gearbox.luau", "\t\t\tand rpm * ratios[gear - 1] / ratios[gear] < ceiling * DOWNSHIFT_MARGIN\n\t\tthen", "\t\t\tand rpm * ratios[gear - 1] / ratios[gear] < ceiling * DOWNSHIFT_MARGIN\n\t\t\tand state.sinceUpshift >= config.upshiftHoldTime\n\t\tthen"),
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
        out = subprocess.run(["lune", "run", "tools/test/run"], cwd=ROOT, capture_output=True, text=True, timeout=300).stdout
    finally:
        path.write_bytes(original)
    summary = out.strip().splitlines()[-1] if out.strip() else "no output"
    print(f"[{name}] {summary}")
    for line in out.splitlines():
        if line.startswith("FAIL"):
            print("    " + (line.split("tests")[-1] if "tests" in line else line))
