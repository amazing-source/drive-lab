"""
Renders a listening file from games/drive-lab/tools/audio_timeline.luau's output: the engine
loops played at the speeds and volumes the car's audio controller would set, frame by frame,
plus the start-up, gear clunks and pops at their times. A preview of what the game mixes, made
without Studio; Roblox's own resampling and 3D panning are not reproduced.

    python -I tools/audio/render_preview.py <timeline.json> <loops dir> <out.mp3> [from s] [to s]

<loops dir> holds the car's set (tools/audio/cut_loops.py for the SVJ, cut_dr458.py for the
DR458); the timeline names each layer's file in the pack's order, and the limiter and events
files, and a one-shot's own file when it is cut from another (the DR458's pops come from the
SVJ's events.ogg, copied in as svj_events.ogg). A loop with a region (a pack whose loops share a
file) plays only that stretch of its file. [from s] [to s] keep a stretch of the run. Every file is matched to -16 LUFS (K-weighted,
ungated), lower only if a peak would pass -1 dBFS, so two renders compare at the same loudness.
Decoding and the MP3 go through ffmpeg.
"""

import json
import os
import subprocess
import sys

import numpy as np
from scipy.signal import lfilter

RATE = 48000
TARGET_LUFS = -16.0
PEAK_CEILING_DB = -1.0


def decode(path):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(RATE), "-"],
        check=True,
        capture_output=True,
    ).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).astype(np.float64)


def loop_play(audio, speed, volume):
    """A loop read at a varying speed (1 = as recorded), wrapping, linearly interpolated."""
    position = np.cumsum(speed) % len(audio)
    index = np.floor(position).astype(np.int64)
    share = (position - index)[:, None]
    after = (index + 1) % len(audio)
    return (audio[index] * (1 - share) + audio[after] * share) * volume[:, None]


def one_shot(audio, start, end, speed):
    piece = audio[int(start * RATE) : int(end * RATE)]
    length = max(1, int(len(piece) / speed))
    source = np.linspace(0, len(piece) - 1, length)
    return np.stack([np.interp(source, np.arange(len(piece)), piece[:, c]) for c in range(2)], axis=1)


def loudness(x):
    """BS.1770 K-weighting (its 48 kHz coefficients), ungated."""
    shelf = lfilter([1.53512485958697, -2.69169618940638, 1.19839281085285], [1.0, -1.69065929318241, 0.73248077421585], x, axis=0)
    weighted = lfilter([1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621], shelf, axis=0)
    return -0.691 + 10 * np.log10(np.sum(np.mean(weighted**2, axis=0)) + 1e-20)


def main(timeline_path, loops, out, start=None, stop=None):
    timeline = json.load(open(timeline_path))
    own = timeline.get("startupSound")
    if own:
        print(f"start-up: {own['id']} cannot be downloaded, so the render starts silent until its hand-over")
    files = timeline["files"]
    frames = timeline["frames"]
    times = np.array([f["t"] for f in frames])
    total = int((times[-1] + timeline["dt"]) * RATE)
    clock = np.arange(total) / RATE

    def track(values):
        return np.interp(clock, times, np.array(values, dtype=float))

    regions = timeline.get("regions") or {}
    decoded = {}

    def loop_audio(name, region):
        if name not in decoded:
            decoded[name] = decode(os.path.join(loops, name))
        audio = decoded[name]
        return audio[int(round(region["from"] * RATE)) : int(round(region["to"] * RATE))] if region else audio

    mix = np.zeros((total, 2))
    layer_regions = regions.get("layers") or [False] * len(files["layers"])
    for index, name in enumerate(files["layers"]):
        audio = loop_audio(name, layer_regions[index])
        mix += loop_play(audio, track([f["speeds"][index] for f in frames]), track([f["volumes"][index] for f in frames]))
    limiter = loop_audio(files["limiter"], regions.get("limiter"))
    mix += loop_play(limiter, track([f["limiterSpeed"] for f in frames]), track([f["limiter"] for f in frames]))

    sources = {files["events"]: decode(os.path.join(loops, files["events"]))}
    for shot in timeline["shots"]:
        name = shot.get("file", files["events"])
        if name not in sources:
            sources[name] = decode(os.path.join(loops, name))
        piece = one_shot(sources[name], shot["from"], shot["to"], shot["speed"]) * shot["volume"]
        at = int(shot["t"] * RATE)
        end = min(total, at + len(piece))
        mix[at:end] += piece[: end - at]

    if start is not None:
        mix = mix[int(float(start) * RATE) : int(float(stop) * RATE)]
        total = len(mix)
    gain_db = TARGET_LUFS - loudness(mix)
    peak_db = 20 * np.log10(np.abs(mix).max() + 1e-12)
    gain_db = min(gain_db, PEAK_CEILING_DB - peak_db)
    mix *= 10 ** (gain_db / 20)
    raw = mix.astype(np.float32).tobytes()
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "2", "-i", "-", "-b:a", "192k", out],
        input=raw,
        check=True,
    )
    print(f"{out}: {total / RATE:.1f} s, {loudness(mix):.1f} LUFS, peak {20 * np.log10(np.abs(mix).max() + 1e-12):.1f} dBFS (gain {gain_db:+.1f} dB)")


if __name__ == "__main__":
    main(*sys.argv[1:6])
