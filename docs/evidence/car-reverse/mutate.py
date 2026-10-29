import pathlib, subprocess, sys
# Run from anywhere: python -I docs/evidence/car-reverse/mutate.py [numbers]. Each break is applied to the
# source, the full suite runs, the source is restored.
ROOT = pathlib.Path(__file__).resolve().parents[3]
SRC = ROOT / "games/drive-lab/src/shared"
MUTANTS = [
    ("1 no hold time", "Vehicle/Selector.luau", "if state.held >= hold and", "if state.held >= 0 and"),
    ("2 selector ignores speed", "Vehicle/Selector.luau", "\t\t\tand groundSpeed < config.selectorMaxSpeed\n", "\t\t\tand true\n"),
    ("3 gearbox.select ignores speed", "Vehicle/Gearbox.luau", "if Gearbox.isShifting(state) or groundSpeed >= config.selectorMaxSpeed then\n\t\treturn false", "if Gearbox.isShifting(state) then\n\t\treturn false"),
    ("4 gearbox.select ignores shift", "Vehicle/Gearbox.luau", "if Gearbox.isShifting(state) or groundSpeed >= config.selectorMaxSpeed then\n\t\treturn false", "if groundSpeed >= config.selectorMaxSpeed then\n\t\treturn false"),
    ("5 R with both pedals", "Vehicle/Selector.luau", "if gear > 0 and brake >= HELD and throttle < LIFTED then", "if gear > 0 and brake >= HELD then"),
    ("6 D with both pedals", "Vehicle/Selector.luau", "elseif gear < 0 and throttle >= HELD and brake < LIFTED then", "elseif gear < 0 and throttle >= HELD then"),
    ("7 hold never restarts", "Vehicle/Selector.luau", "\tif hold == nil or target == nil then\n\t\tstate.held = 0\n", "\tif hold == nil or target == nil then\n"),
    ("8 selects in manual", "Vehicle/Selector.luau", "\t\t\tand input.gearboxMode == \"auto\"\n", "\t\t\tand true\n"),
    ("9 swaps in manual", "Vehicle/Selector.luau", "return help.reverseHoldTime ~= nil and mode == \"auto\" and gearbox.gear < 0", "return help.reverseHoldTime ~= nil and gearbox.gear < 0"),
    ("10 swaps without the help", "Vehicle/Selector.luau", "return help.reverseHoldTime ~= nil and mode == \"auto\" and gearbox.gear < 0", "return mode == \"auto\" and gearbox.gear < 0"),
    ("11 never swaps", "Vehicle/Selector.luau", "out.throttle = if swap then input.brake else input.throttle", "out.throttle = input.throttle"),
    ("12 model skips the selector", "Vehicle/Model.luau", "\tSelector.update(state.help, car.gearbox, state.gearbox, state.selector, input, math.abs(forward), dt)\n", ""),
    ("13 model filters the raw pedals", "Vehicle/Model.luau", "InputFilter.update(state.help, car, state.controls, pedals,", "InputFilter.update(state.help, car, state.controls, input,"),
    ("14 rule drops borrowed keys", "Rules/ControlsHelp.luau", "for _, list in { row.controls, row.keysOf or NONE } do", "for _, list in { row.controls } do"),
    ("15 rule skips the borrowed-key check", "Rules/ControlsHelp.luau", "\t\tif bindings[control] == nil then\n\t\t\ttable.insert(found, `{name} shows the keys of", "\t\tif false then\n\t\t\ttable.insert(found, `{name} shows the keys of"),
    ("16 model skips the reverse cut", "Vehicle/Model.luau", "\t\t* electronics.escFactor\n\t\t* Gearbox.reverseCut(state.car.gearbox, state.gearbox.gear, prediction.forward)\n", "\t\t* electronics.escFactor\n"),
    ("17 hard cut, no band", "Vehicle/Gearbox.luau", "(config.reverseMaxSpeed + forwardSpeed) / config.reverseCutBand, 0, 1)", "(config.reverseMaxSpeed + forwardSpeed) / 1e-6, 0, 1)"),
    ("18 cut also in neutral", "Vehicle/Gearbox.luau", "\tif gear >= 0 then\n\t\treturn 1\n\tend\n\treturn math.clamp(", "\tif gear > 0 then\n\t\treturn 1\n\tend\n\treturn math.clamp("),
    ("19 cut set 10 km/h too high", "Vehicle/Gearbox.luau", "(config.reverseMaxSpeed + forwardSpeed)", "(config.reverseMaxSpeed + 10 / 3.6 + forwardSpeed)"),
    ("20 define accepts any cut", "Config/Cars/Types.luau", "\t\tcar.gearbox.reverseCutBand > 0 and car.gearbox.reverseCutBand < car.gearbox.reverseMaxSpeed,", "\t\ttrue,"),
]
only = sys.argv[1:]
for name, rel, old, new in MUTANTS:
    if only and name.split()[0] not in only:
        continue
    path = SRC / rel
    original = path.read_bytes()
    text = original.decode("utf-8")
    if text.count(old) != 1:
        print(f"[{name}] PATTERN NOT FOUND ({text.count(old)})"); continue
    path.write_bytes(text.replace(old, new).encode("utf-8"))
    try:
        out = subprocess.run(["lune", "run", "tools/test/run"], cwd=ROOT, capture_output=True, text=True, timeout=120).stdout
    finally:
        path.write_bytes(original)
    fails = [l for l in out.splitlines() if l.startswith("FAIL")]
    summary = out.strip().splitlines()[-1] if out.strip() else "no output"
    print(f"[{name}] {summary}")
    for l in fails:
        print('    ' + l.split('tests')[-1] if 'tests' in l else '    ' + l)
