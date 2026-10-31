"""Breaks each new rule on purpose, runs the unit tests, records which spec failed, restores the file.

    python -I mutate.py <worktree> <out.txt>

Every file is restored from the bytes read before its break, and the tree is checked clean after.
"""
import subprocess
import sys

ROOT = sys.argv[1]
OUT = sys.argv[2]
SRC = "games/drive-lab/src/shared/"
CONTRACT = SRC + "Config/Cars/Contract.luau"
ENGINE = SRC + "Rules/EngineSound.luau"
DR_AUDIO = SRC + "Config/Cars/DR458/Audio.luau"
DR_STARTUP = SRC + "Config/Cars/DR458/Startup.luau"

MUTATIONS = [
    ("M1", "the id check accepts a bare number", CONTRACT, '"^rbxassetid://%d+$"', '"%d+$"'),
    ("M2", "the level check accepts volume 0", CONTRACT, "assert(sound.volume > 0,", "assert(sound.volume >= 0,"),
    ("M3", "order: a negative `from` allowed", CONTRACT, "\t\t0 <= sound.from\n\t\t\tand sound.from", "\t\tsound.from"),
    ("M4", "order: handOver may equal `to`", CONTRACT, "and sound.handOver < sound.to,", "and sound.handOver <= sound.to,"),
    ("M5", "order: the catch may equal handOver", CONTRACT, "and sound.catchAt < sound.handOver", "and sound.catchAt <= sound.handOver"),
    ("M6", "timing tolerance 0.02 -> 0.2 s", CONTRACT, "local TIMING_TOLERANCE = 0.02", "local TIMING_TOLERANCE = 0.2"),
    (
        "M7",
        "hold check: the lower bound (starter's end) removed",
        CONTRACT,
        "\t\tcranking >= sound.starterEnds - sound.from - TIMING_TOLERANCE\n\t\t\tand cranking",
        "\t\tcranking",
    ),
    (
        "M8",
        "hold check: the upper bound (the catch) removed",
        CONTRACT,
        "\n\t\t\tand cranking <= startup.catchAfter + TIMING_TOLERANCE,",
        ",",
    ),
    ("M9", "define no longer runs the check", CONTRACT, "\tContract.checkStartupSound(entry.startup, entry.audio)\n", ""),
    (
        "M10",
        "hand-over law made linear",
        ENGINE,
        "return math.sin(progress * math.pi / 2), math.cos(progress * math.pi / 2)",
        "return progress, 1 - progress",
    ),
    (
        "M11",
        "hand-over not clamped",
        ENGINE,
        "local progress = math.clamp((position - from) / (to - from), 0, 1)",
        "local progress = (position - from) / (to - from)",
    ),
    ("M12", "DR458 start-up catches 0.1 s late", DR_STARTUP, "catchAfter = 0.71,", "catchAfter = 0.81,"),
    ("M13", "DR458 hand-over runs past the recording's end", DR_AUDIO, "to = 3.45,", "to = 3.95,"),
    ("M14", "DR458 start-up revs settle at 950, not the idle", DR_STARTUP, "1160, 1000 }", "1160, 950 }"),
    (
        "M15",
        "DR458 pack without its own sound",
        DR_AUDIO,
        'sound = {\n\t\t\tid = "rbxassetid://126032464409866",',
        'soundOff = {\n\t\t\tid = "rbxassetid://126032464409866",',
    ),
]


def run_tests():
    result = subprocess.run(["lune", "run", "tools/test/run"], cwd=ROOT, capture_output=True, text=True)
    lines = (result.stdout + result.stderr).strip().splitlines()
    fails = [line for line in lines if line.startswith("FAIL")]
    summary = lines[-1] if lines else "(no output)"
    return result.returncode, fails, summary, lines


report = []
for key, what, path, old, new in MUTATIONS:
    full = f"{ROOT}/{path}"
    original = open(full, "rb").read()
    text = original.decode("utf-8")
    assert text.count(old) == 1, f"{key}: expected the text once in {path}, found {text.count(old)}"
    open(full, "wb").write(text.replace(old, new).encode("utf-8"))
    try:
        code, fails, summary, lines = run_tests()
    finally:
        open(full, "wb").write(original)
    report.append(f"{key} ({what}) in {path}\n  exit {code}; {summary}")
    if not fails:
        report.append("  NO SPEC FAILED")
        report.extend("  | " + line for line in lines[-5:])
    for line in fails:
        report.append("  " + line[:400])

dirty = subprocess.run(["git", "status", "--porcelain", "--untracked-files=no"], cwd=ROOT, capture_output=True, text=True).stdout
code, fails, summary, _ = run_tests()
report.append(f"\nRestored: tree clean = {dirty.strip() == ''}; exit {code}; {summary}")
open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(report) + "\n")
print("\n".join(report))
