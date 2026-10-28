"""
Renders a listening file from games/drive-lab/tools/weather_timeline.luau's output: the weather
loops played from the pack at the volumes the weather's audio controller would set, frame by
frame, the spray at its speed, the thunders at their times, and the two groups as the game
builds them: everything outside through the cockpit's equaliser and gain, the roof on its own.
A preview of what the game mixes, made without Studio. Approximations: Roblox's
EqualizerSoundEffect is modelled as three bands split at 400 Hz and 4 kHz (Linkwitz-Riley, so
the bands sum flat at 0 dB); its own filter shapes, its resampling and the spray's 3D panning
are not reproduced. The mix is peak-normalised, so it shows the balance, not the level against
the engine.

    python -I tools/audio/render_weather_preview.py <timeline.json> <weather.ogg> <out.mp3>

<weather.ogg> is the pack made by tools/audio/cut_weather.py; the regions come from the
timeline, which takes them from Config/WeatherAudio. Decoding and the MP3 go through ffmpeg.
"""

import json
import subprocess
import sys

import numpy as np
from scipy.signal import butter, sosfilt

RATE = 48000
BANDS_HZ = (400.0, 4000.0)
LOOPS = ("rainLight", "rainHeavy", "roofLight", "roofHeavy", "spray")


def decode(path):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ar", str(RATE), "-"],
        check=True,
        capture_output=True,
    ).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2)


def region(pack, span):
    return pack[int(round(span["from"] * RATE)) : int(round(span["to"] * RATE))].astype(np.float64)


def loop_play(audio, speed, volume):
    """A loop read at a varying speed (1 = as recorded), wrapping, linearly interpolated."""
    position = np.cumsum(speed) % len(audio)
    index = np.floor(position).astype(np.int64)
    share = (position - index)[:, None]
    after = (index + 1) % len(audio)
    return (audio[index] * (1 - share) + audio[after] * share) * volume[:, None]


def one_shot(audio, speed):
    length = max(1, int(len(audio) / speed))
    source = np.linspace(0, len(audio) - 1, length)
    return np.stack([np.interp(source, np.arange(len(audio)), audio[:, c]) for c in range(2)], axis=1)


def bands(x):
    """Low, mid and high bands of x that sum back to x's magnitude (fourth-order Linkwitz-Riley)."""

    def lr4(kind, hz, signal):
        sos = butter(2, hz, kind, fs=RATE, output="sos")
        return sosfilt(sos, sosfilt(sos, signal, axis=0), axis=0)

    low = lr4("lowpass", BANDS_HZ[0], x)
    rest = lr4("highpass", BANDS_HZ[0], x)
    # The low band is phase-matched to the others through the upper crossover's all-pass.
    low = lr4("lowpass", BANDS_HZ[1], low) + lr4("highpass", BANDS_HZ[1], low)
    return low, lr4("lowpass", BANDS_HZ[1], rest), lr4("highpass", BANDS_HZ[1], rest)


def equalise(x, low_db, mid_db, high_db):
    low, mid, high = bands(x)

    def gain(db):
        return (10 ** (np.asarray(db, dtype=float) / 20)).reshape(-1, 1) if np.ndim(db) else 10 ** (db / 20)

    return low * gain(low_db) + mid * gain(mid_db) + high * gain(high_db)


def main(timeline_path, pack_path, out):
    timeline = json.load(open(timeline_path))
    frames = timeline["frames"]
    times = np.array([f["t"] for f in frames])
    total = int((times[-1] + timeline["dt"]) * RATE)
    clock = np.arange(total) / RATE

    def track(key):
        return np.interp(clock, times, np.array([f[key] for f in frames], dtype=float))

    pack = decode(pack_path)
    loops = {name: region(pack, timeline["loops"][name]) for name in LOOPS}
    ones = np.ones(total)
    outside = loop_play(loops["rainLight"], ones, track("rainLight"))
    outside += loop_play(loops["rainHeavy"], ones, track("rainHeavy"))
    outside += loop_play(loops["spray"], track("spraySpeed"), track("spray"))
    shaping = timeline["thunderEqualiser"]
    for thunder in timeline["thunders"]:
        piece = one_shot(region(pack, thunder), thunder["speed"]) * thunder["volume"]
        piece = equalise(piece, shaping["low"], shaping["mid"], shaping["high"])
        at = int(thunder["t"] * RATE)
        end = min(total, at + len(piece))
        outside[at:end] += piece[: end - at]
    outside = equalise(outside, 0.0, track("midGain"), track("highGain")) * track("outside")[:, None]
    roof = loop_play(loops["roofLight"], ones, track("roofLight")) + loop_play(loops["roofHeavy"], ones, track("roofHeavy"))
    mix = outside + roof * track("roof")[:, None]

    peak = np.abs(mix).max()
    mix *= 10 ** (-1 / 20) / peak
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "2", "-i", "-", "-b:a", "192k", out],
        input=mix.astype(np.float32).tobytes(),
        check=True,
    )
    print(f"{out}: {total / RATE:.1f} s, {len(timeline['thunders'])} thunders, peak normalised to -1 dBFS (gain {20 * np.log10(10 ** (-1 / 20) / peak):+.1f} dB)")


if __name__ == "__main__":
    main(*sys.argv[1:4])
