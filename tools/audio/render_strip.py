"""
Renders a packed engine set (tools/audio/pack_boss302.py's candidate.json and manifest.json) as a
listening strip, for a car with no physics yet: its start-up into its idle, a full-throttle pull
through four gears to the limiter, a lift, a coast with two blipped downshifts, idle. The engine is
games/drive-lab/tools/audio_sweep.luau (Drive Lab's own mix) rendered by tools/audio/render_preview.py
from the packed files' regions; gear sounds at each shift, pop trains after the lift and each
downshift. The start-up's settled end is matched to the run's first idle second and its faded tail
laid over the run's first 0.8 s. The strip is levelled to PULL_LUFS over the pull, so strips compare
by ear.

    python -I tools/audio/render_strip.py <pack dir> <out.mp3> [start rpm] [seed]
"""

import json
import os
import random
import re
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_preview as R  # noqa: E402

RATE = R.RATE
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
IDLE = 750
LIMIT = 7500
PULL_LUFS = -18.5
# Seconds into the run: the pull from first gear to the limiter.
PULL = (2.75, 15.0)
TUNING = {"crossfadeOctaves": 0.5, "minSpeed": 0.1, "maxSpeed": 2.5, "quietRpm": IDLE, "quietDb": -12, "loudRpm": 7000, "loudDb": 0,
          "liftHalfLife": 0.025, "pressHalfLife": 0.06, "volumeHalfLife": 0.03, "speedHalfLife": 0.012}
HAND_OVER_SECONDS = 0.8
GEAR_VOLUME = 0.5
POP_VOLUME = (1.0, 1.25)


def profile(start_rpm: float) -> list:
    """Segments: seconds, rpm from, rpm to, throttle, and a flag audio_sweep reads."""
    return [
        [1.5, start_rpm, IDLE, 0, ""], [1.0, IDLE, IDLE, 0, ""], [0.25, IDLE, 1500, 1, ""],
        [2.0, 1500, 7400, 1, ""], [0.12, 7400, 4913, 0, "shiftUp"],
        [2.6, 4913, 7400, 1, ""], [0.12, 7400, 5146, 0, "shiftUp"],
        [3.4, 5146, 7400, 1, ""], [0.12, 7400, 5780, 0, "shiftUp"],
        [3.0, 5780, LIMIT, 1, ""], [0.9, LIMIT, LIMIT, 1, "limiter"],
        [3.5, LIMIT, 4200, 0, ""], [0.25, 4200, 5400, 0.3, "shiftDown"],
        [2.2, 5400, 3600, 0, ""], [0.25, 3600, 5200, 0.3, "shiftDown"],
        [2.2, 5200, 2500, 0, ""], [0.6, 2500, IDLE, 0, ""], [2.0, IDLE, IDLE, 0, ""],
    ]



def shots(events: list, regions: dict, seed: str) -> list:
    pops = sorted((k for k in regions if k.startswith("pop")), key=lambda k: int(k[3:]))
    random.seed(seed)
    out = []

    def shot(t, key, volume):
        r = regions[key]["region"]
        out.append({"t": t, "kind": key, "from": r["from"], "to": r["to"], "volume": volume, "speed": random.uniform(0.95, 1.05)})

    for event in events:
        if event["kind"] == "shiftUp":
            shot(event["t"], "gearUp", GEAR_VOLUME)
        elif event["kind"] == "shiftDown":
            shot(event["t"], "gearDown", GEAR_VOLUME)
            t = event["t"] + 0.1
            for _ in range(3):
                shot(t, random.choice(pops), random.uniform(*POP_VOLUME))
                t += random.uniform(0.08, 0.2)
        elif event["kind"] == "lift":
            t = event["t"] + 0.05
            for _ in range(6):
                shot(t, random.choice(pops), random.uniform(*POP_VOLUME))
                t += random.uniform(0.08, 0.22)
    return out


def main(pack_dir: str, out: str, start_rpm: str = "1140", seed: str = "strip"):
    manifest = json.load(open(os.path.join(pack_dir, "manifest.json")))
    candidate = json.load(open(os.path.join(pack_dir, "candidate.json")))
    candidate["pack"]["engineTuning"] = TUNING
    candidate["profile"] = profile(float(start_rpm))
    sweep_input = os.path.join(pack_dir, "strip_sweep.json")
    json.dump(candidate, open(sweep_input, "w"))
    timeline = json.loads(subprocess.run(["lune", "run", "games/drive-lab/tools/audio_sweep.luau", os.path.abspath(sweep_input)], cwd=ROOT,
                                         capture_output=True, check=True, text=True).stdout)
    events = timeline["events"] if isinstance(timeline["events"], list) else []
    regions = manifest["events"]["regions"]
    timeline["shots"] = shots(events, regions, seed)
    timeline["regions"] = candidate["regions"]
    timeline_path = os.path.join(pack_dir, "strip_timeline.json")
    json.dump(timeline, open(timeline_path, "w"))
    run_path = os.path.join(pack_dir, "strip_run.wav")
    subprocess.run([sys.executable, "-I", os.path.join(os.path.dirname(os.path.abspath(__file__)), "render_preview.py"),
                    timeline_path, pack_dir, run_path], check=True, capture_output=True)
    run = R.decode(run_path)
    r = regions["startup"]["region"]
    start = R.decode(os.path.join(pack_dir, "events.ogg"))[int(round(r["from"] * RATE)) : int(round(r["to"] * RATE))].copy()
    n = int(HAND_OVER_SECONDS * RATE)
    settled = start[-n - int(0.6 * RATE) : -n]
    start *= 10 ** ((R.loudness(run[:RATE]) - R.loudness(settled)) / 20)
    fade_in = np.sin(np.linspace(0, np.pi / 2, n))[:, None]
    strip = np.vstack([np.zeros((int(0.3 * RATE), 2)), start[:-n], start[-n:] + run[:n] * fade_in, run[n:]])
    lead = 0.3 + len(start) / RATE - HAND_OVER_SECONDS
    pull = strip[int((lead + PULL[0]) * RATE) : int((lead + PULL[1]) * RATE)]
    strip *= 10 ** ((PULL_LUFS - R.loudness(pull)) / 20)
    peak = 20 * np.log10(np.abs(strip).max())
    assert peak <= -1.0, f"the strip peaks at {peak:.1f} dBFS"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "2", "-i", "-", "-b:a", "192k", out],
                   input=strip.astype(np.float32).tobytes(), check=True)
    print("%s: %.1f s, peak %.1f dBFS, start-up %.2f s, %d shots, events %s" % (
        out, len(strip) / RATE, peak, len(start) / RATE, len(timeline["shots"]), re.sub(r"\s+", " ", json.dumps(events))))


if __name__ == "__main__":
    main(*sys.argv[1:5])
