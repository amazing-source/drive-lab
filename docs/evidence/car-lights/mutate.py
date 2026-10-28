import hashlib, subprocess, sys
from pathlib import Path
R = Path("games/drive-lab/src/shared/Rules/CarLights.luau")
C = Path("games/drive-lab/src/shared/Config/CarLights.luau")
M = [
 ("blink starts dark", R, "return (math.max(elapsed, 0) * hz) % 1 < onShare", "return (math.max(elapsed, 0) * hz + 0.5) % 1 < onShare"),
 ("headlights without ignition", R, "local headlights = running and (state.mode", "local headlights = (state.mode"),
 ("cabin needs ignition", R, "cabin = state.cabin,", "cabin = running and state.cabin,"),
 ("DRL ignores indicator", R, "\tif state.indicator == side then\n\t\treturn tuning.drlWhileIndicating\n\tend\n", ""),
 ("DRL not dimmed by headlights", R, "return if headlights then tuning.drlWithHeadlights else 1", "return 1"),
 ("tail with running lights", R, "tail = headlights,", "tail = running,"),
 ("tail share wins over brake", R, "tail = if lit.brake then 1 elseif lit.tail then tailShare else 0,", "tail = if lit.tail then tailShare elseif lit.brake then 1 else 0,"),
 ("strength blend reversed", R, "return level * (night + (day - night) * daylight)", "return level * (night + (day - night) * (1 - daylight))"),
 ("daylight unclamped", R, "return math.clamp((brightness - night) / (day - night), 0, 1)", "return (brightness - night) / (day - night)"),
 ("tap after hold", R, "if wasDown and not press.spent then", "if wasDown then"),
 ("hold repeats", R, "\t\t\tpress.spent = true\n\t\t\treturn \"Hold\"", "\t\t\treturn \"Hold\""),
 ("indicator 150 a minute", C, "blinkHz = 1.5,", "blinkHz = 2.5,"),
 ("tail a third of brake", C, "TAIL_SHARE = 0.2,", "TAIL_SHARE = 0.3,"),
]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
for name, path, old, new in M:
    original = path.read_bytes(); before = sha(path)
    text = original.decode()
    assert text.count(old) == 1, f"{name}: pattern found {text.count(old)} times"
    path.write_bytes(text.replace(old, new).encode())
    out = subprocess.run(["lune", "run", "tools/test/run"], capture_output=True, text=True).stdout
    path.write_bytes(original)
    assert sha(path) == before
    fails = [l for l in out.splitlines() if l.startswith("FAIL")]
    summary = out.strip().splitlines()[-1] if out.strip() else "no output"
    print(f"## {name}: {summary}")
    for f in fails: print("   ", f[:220])
out = subprocess.run(["lune", "run", "tools/test/run"], capture_output=True, text=True).stdout
print("restored:", out.strip().splitlines()[-1])
