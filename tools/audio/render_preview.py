"""
Renders a listening file from games/drive-lab/tools/audio_timeline.luau's output: the engine
loops played at the speeds and volumes the car's audio controller would set, frame by frame,
plus the start-up, gear clunks and pops at their times. A preview of what the game mixes, made
without Studio; Roblox's own resampling and 3D panning are not reproduced.

    python -I tools/audio/render_preview.py <timeline.json> <loops dir> <out.mp3>

<loops dir> holds the uploaded set (eng_idle.ogg, eng_on.ogg, eng_off.ogg, eng_limiter.ogg,
events.ogg; tools/audio/cut_loops.py). Layers are taken in Config/CarAudio's order: idle, on,
off. Decoding and the MP3 go through ffmpeg.
"""

import json
import os
import subprocess
import sys

import numpy as np

RATE = 48000
LAYER_FILES = ("eng_idle.ogg", "eng_on.ogg", "eng_off.ogg")


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


def main(timeline_path, loops, out):
    timeline = json.load(open(timeline_path))
    frames = timeline["frames"]
    times = np.array([f["t"] for f in frames])
    total = int((times[-1] + timeline["dt"]) * RATE)
    clock = np.arange(total) / RATE

    def track(values):
        return np.interp(clock, times, np.array(values, dtype=float))

    mix = np.zeros((total, 2))
    for index, name in enumerate(LAYER_FILES):
        audio = decode(os.path.join(loops, name))
        mix += loop_play(audio, track([f["speeds"][index] for f in frames]), track([f["volumes"][index] for f in frames]))
    limiter = decode(os.path.join(loops, "eng_limiter.ogg"))
    mix += loop_play(limiter, track([f["limiterSpeed"] for f in frames]), track([f["limiter"] for f in frames]))

    events = decode(os.path.join(loops, "events.ogg"))
    for shot in timeline["shots"]:
        piece = one_shot(events, shot["from"], shot["to"], shot["speed"]) * shot["volume"]
        at = int(shot["t"] * RATE)
        end = min(total, at + len(piece))
        mix[at:end] += piece[: end - at]

    peak = np.abs(mix).max()
    mix *= 10 ** (-1 / 20) / peak
    raw = mix.astype(np.float32).tobytes()
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "2", "-i", "-", "-b:a", "192k", out],
        input=raw,
        check=True,
    )
    print(f"{out}: {total / RATE:.1f} s, peak normalised to -1 dBFS (gain {20 * np.log10(10 ** (-1 / 20) / peak):+.1f} dB)")


if __name__ == "__main__":
    main(*sys.argv[1:4])
