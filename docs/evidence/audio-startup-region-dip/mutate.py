"""Breaks each new rule on purpose, runs the unit tests, records which spec failed, restores the file.

    python -I mutate.py <worktree> <out.txt>

Every file is restored from the bytes read before its break, and the tree is checked clean after.
"""
import subprocess
import sys

ROOT = sys.argv[1]
OUT = sys.argv[2]
RULE = "games/drive-lab/src/shared/Rules/StartupHandOver.luau"

MUTATIONS = [
    (
        "M1",
        "the fix reverted: the ended check before the load timeout for the car's own sound only",
        "\tif state.handedOver == nil and not playback.playing then",
        "\tif state.own and state.handedOver == nil and not playback.playing then",
    ),
    (
        "M2",
        "the ended check removed, for both start-ups",
        "\tif state.handedOver == nil and not playback.playing then",
        "\tif false then",
    ),
    (
        "M3",
        "the load timeout never fires",
        "(not playback.loaded and now - state.startedAt > LOAD_TIMEOUT)",
        "false",
    ),
    ("M4", "revving past abortRpm ignored", "rpm > settings.abortRpm or ", ""),
    ("M5", "the early hand-over does not fade the start-up", "\t\tstate.gain *= 1 - step\n", ""),
    ("M6", "the early hand-over never completes", "state.done = share > DONE_SHARE", "state.done = false"),
    (
        "M7",
        "the car's own sound not caught up with the press",
        "\t\t\tposition = own.from + now - state.pressedAt\n\t\t\tseek = position\n",
        "",
    ),
    (
        "M8",
        "the region's hand-over made linear",
        "return math.sin(progress * math.pi / 2), nil, nil",
        "return progress, nil, nil",
    ),
]


def run_tests() -> tuple[int, list[str], str]:
    result = subprocess.run(
        ["lune", "run", "tools/test/run"], cwd=ROOT, capture_output=True, text=True, encoding="utf-8"
    )
    lines = (result.stdout + result.stderr).splitlines()
    fails = [line for line in lines if line.startswith("FAIL")]
    summary = next((line for line in reversed(lines) if "spec files" in line), "no summary")
    return result.returncode, fails, summary


def relative(line: str) -> str:
    """Repo-relative, forward-slash paths in a test runner line."""
    backslash = chr(92)
    marker = backslash + ".worktrees" + backslash
    while marker in line:
        at = line.index(marker)
        start = line.rfind(" ", 0, at) + 1
        rest = line.index(backslash, at + len(marker)) + 1
        end = line.find(":", rest)
        line = line[:start] + line[rest:end].replace(backslash, "/") + line[end:]
    return line


out = []
code, fails, summary = run_tests()
out.append(f"Baseline: exit {code}; {summary}")
assert code == 0, "the baseline must pass before mutating"
for name, what, old, new in MUTATIONS:
    path = f"{ROOT}/{RULE}"
    original = open(path, "rb").read()
    text = original.decode("utf-8")
    assert text.count(old) == 1, f"{name}: the text to break must appear once"
    open(path, "wb").write(text.replace(old, new).encode("utf-8"))
    try:
        code, fails, summary = run_tests()
    finally:
        open(path, "wb").write(original)
    out.append(f"{name} ({what}) in {RULE}")
    out.append(f"  exit {code}; {summary}")
    for line in fails:
        out.append(f"  {relative(line)}")
    if code == 0:
        out.append("  NOT CAUGHT")
code, fails, summary = run_tests()
out.append(f"Restored: exit {code}; {summary}")
diff = subprocess.run(["git", "diff", "--stat", "HEAD", "--", RULE], cwd=ROOT, capture_output=True, text=True).stdout
out.append("Rule file identical to HEAD after restore: " + ("yes" if diff.strip() == "" else diff))
open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
print("\n".join(out))
