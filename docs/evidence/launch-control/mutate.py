import pathlib, subprocess, sys
# python -I docs/evidence/launch-control/mutate.py [numbers]: each break is applied to the source,
# the full suite runs, the source is restored.
ROOT = pathlib.Path(__file__).resolve().parents[3]
SRC = ROOT / "games/drive-lab/src/shared"
MUTANTS = [
    ("1 arms on a part throttle", "Vehicle/Launch.luau", "if available and brake >= HELD and throttle >= FULL then", "if available and brake >= HELD and throttle >= 0.5 then"),
    ("2 arms without the brake", "Vehicle/Launch.luau", "if available and brake >= HELD and throttle >= FULL then", "if available and throttle >= FULL then"),
    ("3 a lift does not cancel", "Vehicle/Launch.luau", "\t\tif not available or throttle < FULL then\n", "\t\tif not available then\n"),
    ("4 launches before the release", "Vehicle/Launch.luau", "\t\telseif brake < RELEASED then\n", "\t\telseif brake < HELD then\n"),
    ("5 a lift does not end it", "Vehicle/Launch.luau", "return not selected or throttle < FULL or brake >= RELEASED", "return not selected or brake >= RELEASED"),
    ("6 no end speed", "Vehicle/Launch.luau", " or gear < 1 or groundSpeed >= config.endSpeed", " or gear < 1"),
    ("7 arms with ESC on", "Vehicle/Launch.luau", "return input.drivingMode == config.mode and not input.assists.esc", "return input.drivingMode == config.mode"),
    ("8 arms in any mode", "Vehicle/Launch.luau", "return input.drivingMode == config.mode and not input.assists.esc", "return not input.assists.esc"),
    ("9 no traction control with TC off", "Vehicle/Model.luau", "\t\tinput.assists.tc or launching,\n", "\t\tinput.assists.tc,\n"),
    ("10 the mode's slip, not the launch's", "Vehicle/Model.luau", "if launching then car.launch.slipRatio else mode.tcSlipRatio", "mode.tcSlipRatio"),
    ("11 the automatic never holds its gear", "Vehicle/Gearbox.luau", "if gear < 1 or context.holdGear then", "if gear < 1 then"),
    ("12 the flag is ignored", "Vehicle/Model.luau", "context.holdGear = state.launch.phase == \"Launching\" and not state.car.launch.autoUpshift", "context.holdGear = false"),
    ("13 the brake selects R while a launch can arm", "Vehicle/Selector.luau", "\t\t\tand not launchReady\n", "\t\t\tand true\n"),
    ("14 the model never runs the launch", "Vehicle/Model.luau", "\tLaunch.update(\n\t\tcar.launch,\n", "\tlocal _ = (function(...) end)(\n\t\tcar.launch,\n"),
    ("15 HUD ignores the launch", "Rules/Hud.luau", "\tif launching then\n\t\treturn launchText\n\tend\n", ""),
    ("16 cluster ignores the launch", "Rules/Cluster.luau", "\tif launching then\n\t\treturn Cluster.LAUNCH_TEXT\n\telseif lamp == \"EscOff\" then", "\tif lamp == \"EscOff\" then"),
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
