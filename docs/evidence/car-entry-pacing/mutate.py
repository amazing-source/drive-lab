"""Deliberate breaks of the changed rules, one at a time: each must turn its spec red, and the
file is restored byte for byte afterwards (checked by hash)."""
import hashlib
import os
import subprocess
import sys

ROOT = os.path.expanduser("~/Downloads/drive-lab/.worktrees/car-entry-pacing")
RULES = f"{ROOT}/games/drive-lab/src/shared/Rules/CarEntry.luau"
CONFIG = f"{ROOT}/games/drive-lab/src/shared/Config/CarEntry.luau"

BREAKS = [
    ("steps: getting out plays OutsideClose to its end (no EXIT_END)", RULES,
     "return chain(if doorOpen then EXIT_OPEN else EXIT_SHUT, Config.EXIT_END.at)",
     "return chain(if doorOpen then EXIT_OPEN else EXIT_SHUT)"),
    ("EXIT_END.at before the door has shut", CONFIG,
     "EXIT_END = table.freeze({ at = 3.433,", "EXIT_END = table.freeze({ at = 2.5,"),
    ("EXIT_END back on the mark", CONFIG,
     "right = -1.0913, forward = 0.5492", "right = -0.88, forward = 0"),
    ("exit hold back to 0.6 s", CONFIG,
     "EXIT_HOLD_SECONDS = 0.35,", "EXIT_HOLD_SECONDS = 0.6,"),
    ("linesUpFirst ignores the corridor", RULES,
     "return outward <= 0 or math.abs(lateral) > outward * math.tan(Config.APPROACH.lineUpAngle)",
     "return outward <= 0"),
    ("settleSeconds without the cap", RULES,
     "return math.min(seconds, approach.settleSeconds)", "return seconds"),
    ("settleSeconds ignores a turn the other way", RULES,
     "math.abs(turn) / approach.turnSpeed", "turn / approach.turnSpeed"),
    ("settleShare linear, not eased", RULES,
     "return share * share * (3 - 2 * share)\nend\n\n-- A held exit key",
     "return share\nend\n\n-- A held exit key"),
    ("entryStart accepts a time in the past", RULES,
     "return math.clamp(asked, now, now + Config.ENTRY_LEAD)",
     "return math.min(asked, now + Config.ENTRY_LEAD)"),
    ("entryStart lets NaN and infinity through", RULES,
     'if typeof(asked) ~= "number" or asked ~= asked or math.abs(asked) == math.huge then',
     'if typeof(asked) ~= "number" then'),
]


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def run():
    out = subprocess.run(["lune", "run", "tools/test/run"], cwd=ROOT, capture_output=True, text=True)
    lines = (out.stdout + out.stderr).splitlines()
    return out.returncode, [l for l in lines if l.startswith("FAIL")], lines[-1] if lines else ""


code, fails, last = run()
print(f"clean: exit {code}, {last}")
for name, path, old, new in BREAKS:
    original = open(path, "rb").read()
    before = sha(path)
    text = original.decode("utf-8")
    if text.count(old) != 1:
        print(f"!! {name}: search text found {text.count(old)} times, break NOT applied")
        continue
    open(path, "wb").write(text.replace(old, new).encode("utf-8"))
    try:
        code, fails, last = run()
    finally:
        open(path, "wb").write(original)
    restored = sha(path) == before
    print(f"\n## {name}\n   exit {code}, {last}, restored byte for byte: {restored}")
    for line in fails:
        print("   " + line[:220])
code, fails, last = run()
print(f"\nclean again: exit {code}, {last}")
