"""
Renders listening files from games/drive-lab/tools/road_timeline.luau's output: the wind and the
roar played from the pack at the volumes and speeds the road audio controller would set, frame
by frame, the wind through its moving low-pass, each through its equaliser; and a second file
with the engine under them, its loops played as the car's audio controller would play them.
Previews of what the game mixes, made without Studio, and a measurement of the balance.

    python -I tools/audio/render_road_preview.py <timeline.json> <road.ogg> <engine loops dir> <out dir>

<road.ogg> is the pack made by tools/audio/cut_road.py; <engine loops dir> holds the engine set
(eng_idle.ogg, eng_on.ogg, eng_off.ogg, eng_limiter.ogg; tools/audio/cut_loops.py). Writes
road_preview.mp3 (speed sounds alone, peak-normalised: the balance between them, not their
level) and road_preview_with_engine.mp3 (one gain for the whole mix, so the balance against the
engine is the game's), and prints the measured levels.

Approximations: Roblox's AudioFilter is modelled as a second-order Butterworth low-pass whose
coefficients follow the cutoff every 10 ms; its EqualizerSoundEffect and AudioEqualizer as three
bands split at 400 Hz and 4 kHz (Linkwitz-Riley, so they sum flat at 0 dB). Roblox's resampling,
the engine's 3D position (about 1 dB down in the chase view) and the start-up, gear clunks and
pops are not reproduced. Loudness is BS.1770 K-weighted over 3 s, ungated.
"""

import json
import os
import subprocess
import sys

import numpy as np
from scipy.signal import butter, lfilter, sosfilt

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cut_weather import k_weighted  # noqa: E402

RATE = 48000
BANDS_HZ = (400.0, 4000.0)
BLOCK = int(0.01 * RATE)
ENGINE_FILES = ("eng_idle.ogg", "eng_on.ogg", "eng_off.ogg")


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


def moving_low_pass(x, cutoff, q):
    """A second-order low-pass whose cutoff follows `cutoff` (Hz per sample), updated per block."""
    y = np.empty_like(x)
    state = np.zeros((2, x.shape[1]))
    for start in range(0, len(x), BLOCK):
        end = min(len(x), start + BLOCK)
        w0 = 2 * np.pi * min(cutoff[start], RATE * 0.45) / RATE
        alpha = np.sin(w0) / (2 * q)
        cos = np.cos(w0)
        b = np.array([(1 - cos) / 2, 1 - cos, (1 - cos) / 2]) / (1 + alpha)
        a = np.array([1, -2 * cos / (1 + alpha), (1 - alpha) / (1 + alpha)])
        y[start:end], state = lfilter(b, a, x[start:end], axis=0, zi=state)
    return y


def bands(x):
    """Low, mid and high bands of x that sum back to x's magnitude (fourth-order Linkwitz-Riley)."""

    def lr4(kind, hz, signal):
        sos = butter(2, hz, kind, fs=RATE, output="sos")
        return sosfilt(sos, sosfilt(sos, signal, axis=0), axis=0)

    low = lr4("lowpass", BANDS_HZ[0], x)
    rest = lr4("highpass", BANDS_HZ[0], x)
    low = lr4("lowpass", BANDS_HZ[1], low) + lr4("highpass", BANDS_HZ[1], low)
    return low, lr4("lowpass", BANDS_HZ[1], rest), lr4("highpass", BANDS_HZ[1], rest)


def equalise(x, low_db, mid_db, high_db):
    low, mid, high = bands(x)

    def gain(db):
        return (10 ** (np.asarray(db, dtype=float) / 20)).reshape(-1, 1)

    return low * gain(low_db) + mid * gain(mid_db) + high * gain(high_db)


def lufs_track(x, seconds=3.0):
    """Short-term K-weighted loudness every 0.5 s, centred windows."""
    filtered = k_weighted(x)
    block, hop = int(seconds * RATE), int(0.5 * RATE)
    times, values = [], []
    for start in range(0, len(x) - block, hop):
        power = np.sum(np.mean(filtered[start : start + block] ** 2, axis=0))
        times.append((start + block / 2) / RATE)
        values.append(-0.691 + 10 * np.log10(power + 1e-20))
    return np.array(times), np.array(values)


def write_mp3(mix, out):
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "2", "-i", "-", "-b:a", "192k", out],
        input=mix.astype(np.float32).tobytes(),
        check=True,
    )


def main(timeline_path, pack_path, engine_dir, out_dir):
    timeline = json.load(open(timeline_path))
    frames = timeline["frames"]
    times = np.array([f["t"] for f in frames])
    total = int((times[-1] + timeline["dt"]) * RATE)
    clock = np.arange(total) / RATE

    def track(get):
        return np.interp(clock, times, np.array([get(f) for f in frames], dtype=float))

    pack = decode(pack_path)
    loops = timeline["loops"]
    wind_audio = pack[int(round(loops["wind"]["from"] * RATE)) : int(round(loops["wind"]["to"] * RATE))]
    road_audio = pack[int(round(loops["road"]["from"] * RATE)) : int(round(loops["road"]["to"] * RATE))]

    wind = loop_play(wind_audio, track(lambda f: f["windSpeed"]), track(lambda f: f["wind"]))
    wind = moving_low_pass(wind, track(lambda f: f["windCutoff"]), timeline["cutoffQ"])
    wind = equalise(wind, *(track(lambda f, k=k: f["windEq"][k]) for k in ("low", "mid", "high")))
    road = loop_play(road_audio, track(lambda f: f["roadSpeed"]), track(lambda f: f["road"]))
    road = equalise(road, *(track(lambda f, k=k: f["roadEq"][k]) for k in ("low", "mid", "high")))
    noise = wind + road

    engine = np.zeros((total, 2))
    for index, name in enumerate(ENGINE_FILES):
        audio = decode(os.path.join(engine_dir, name))
        engine += loop_play(audio, track(lambda f, i=index: f["engineSpeeds"][i]), track(lambda f, i=index: f["engineVolumes"][i]))
    limiter = decode(os.path.join(engine_dir, "eng_limiter.ogg"))
    engine += loop_play(limiter, track(lambda f: f["limiterSpeed"]), track(lambda f: f["limiter"]))
    shaping = timeline["engineEqualiser"]
    share = track(lambda f: f["engineOutside"])
    engine = equalise(
        engine,
        *(shaping["cockpit"][k] + (shaping["outside"][k] - shaping["cockpit"][k]) * share for k in ("low", "mid", "high")),
    )

    os.makedirs(out_dir, exist_ok=True)
    peak = np.abs(noise).max()
    write_mp3(noise * 10 ** (-1 / 20) / peak, os.path.join(out_dir, "road_preview.mp3"))
    full = engine + noise
    full_gain = 10 ** (-1 / 20) / np.abs(full).max()
    write_mp3(full * full_gain, os.path.join(out_dir, "road_preview_with_engine.mp3"))

    at, wind_l = lufs_track(wind)
    _, road_l = lufs_track(road)
    _, noise_l = lufs_track(noise)
    _, engine_l = lufs_track(engine)
    kmh = np.interp(at, times, [f["kmh"] for f in frames])
    cockpit = np.interp(at, times, [1.0 if f["cockpit"] else 0.0 for f in frames]) > 0.5
    print(f"{total / RATE:.1f} s; speed sounds alone peak-normalised ({20 * np.log10(10 ** (-1 / 20) / peak):+.1f} dB); with engine {20 * np.log10(full_gain):+.1f} dB")
    print("  t s   km/h  view     wind  roar  both  engine  engine lead  (LUFS, 3 s windows)")
    for i in range(0, len(at), 4):
        view = "cockpit" if cockpit[i] else "chase"
        print(f"  {at[i]:5.1f} {kmh[i]:5.0f}  {view:7s} {wind_l[i]:5.1f} {road_l[i]:5.1f} {noise_l[i]:5.1f} {engine_l[i]:6.1f}  {engine_l[i] - noise_l[i]:+6.1f}")
    moving = kmh > 30
    lead = engine_l - noise_l
    print(f"  smallest engine lead while moving: {lead[moving].min():+.1f} dB at {kmh[moving][np.argmin(lead[moving])]:.0f} km/h")
    accelerating = (np.diff(np.concatenate([[0], kmh])) > 0) & ~cockpit & moving
    crossing = np.where(accelerating & (wind_l > road_l))[0]
    if len(crossing):
        print(f"  outside, the wind first leads the roar at {kmh[crossing[0]]:.0f} km/h")


if __name__ == "__main__":
    main(*sys.argv[1:5])
