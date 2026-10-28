"""
Cuts the Drive Lab weather sound set and packs it into one file, weather.ogg, so the set costs
one audio upload: two exterior rain loops (light, heavy), two rain-on-the-roof loops recorded
inside a car (light, heavy), a tyre-spray loop synthesised here, and four distant thunders.
Config/WeatherAudio plays each loop through Sound.LoopRegion and each thunder through
Sound.PlaybackRegion; the regions are in manifest.json.

    python -I tools/audio/cut_weather.py <out dir> <sources dir> [<sources dir> ...]

The source folders hold the downloads under the names in LOOPS, THUNDERS and SPRAY_SOURCE:
bsb_<n>.flac from bigsoundbank.com/UPLOAD/flac/<n>.flac (CC0; the site wants a browser user
agent and its own Referer), freesound_462862.ogg from Freesound's preview of sound 462862 (CC0).
Writes the pieces (OGG, and the WAV they were encoded from), weather.ogg and manifest.json to
<out dir>. Decoding and encoding go through ffmpeg.

The exterior rain was first Mixkit's (1253 light, 1246 heavy): Roblox's audio moderation
rejected it on 2026-10-28, alone and in the pack, while the BigSoundBank and synthesised pieces
passed, so the exterior rain is BigSoundBank's too.

Rain is noise, so a loop is not cut where the take repeats (it never does): a section is
chosen, its slow level drift flattened, and its first FOLD_SECONDS folded over its end with an
equal-power crossfade, so the wrap joins two samples that were neighbours in the recording and
the cut-off end fades out under them. In the pack every loop is written with GUARD_SECONDS
of its own wrapped audio on both sides, so a loop jump that lands a little early or late still
plays the loop.
The spray loop is noise shaped to the spectrum of a real wet pass-by and made periodic by
construction (one inverse FFT over the whole loop). Each loop's seam is measured after OGG
decoding against the loop's own moment-to-moment variation. Loudness is BS.1770 K-weighted,
ungated; loops are matched as loops, thunders on their loudest 3 s.
"""

import json
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy.interpolate import CubicSpline
from scipy.io import wavfile
from scipy.ndimage import maximum_filter1d, uniform_filter1d
from scipy.signal import butter, lfilter, resample_poly, sosfilt, welch

RATE = 48000
LOOP_LUFS = -20.0
THUNDER_LUFS = -20.0
PEAK_CEILING_DB = -1.0
VORBIS_QUALITY = "5"
FOLD_SECONDS = 1.5
GUARD_SECONDS = 0.25
PACK_GAP_SECONDS = 0.5
HIGH_PASS_HZ = 25.0

# name, source, section start and end s (None: to the end), whether the source clips.
LOOPS = [
    # 2719 is 35 minutes of a storm: between 635 and 700 s a soft, steady rain with no thunder.
    ("rain_light", "bsb_2719.flac", 635.0, 700.0, False),
    # 1019, a summer downpour on a terrace: dense big drops; it slowly eases after 80 s.
    ("rain_heavy", "bsb_1019.flac", 4.0, 56.0, False),
    # 1293 holds a steady light patter until about 95 s, then bigger drops.
    ("roof_light", "bsb_1293.flac", 15.0, 75.0, False),
    # 1294 builds for its first 40 s; its steady heavy part clips on the biggest drops.
    ("roof_heavy", "bsb_1294.flac", 40.0, 81.5, True),
]
THUNDERS = ["bsb_3181.flac", "bsb_3182.flac", "bsb_3184.flac", "bsb_2718.flac"]
# A thunder starts this far under its peak and ends this far under it, the last seconds faded.
THUNDER_START_DB = -40.0
THUNDER_END_DB = -42.0
THUNDER_FADE_SECONDS = 4.0
THUNDER_MAX_SECONDS = 26.0
SPRAY_SOURCE = "freesound_462862.ogg"
# The pass-by's closest second: the spray at its fullest.
SPRAY_SECTION = (1.9, 3.1)
SPRAY_SECONDS = 12.0
# Below this the pass-by is the car's engine and tyre rumble, which the engine sound already is.
SPRAY_HIGH_PASS_HZ = 300.0
SPRAY_LOW_PASS_HZ = 12000.0
# Slow swell of the spray (whole cycles per loop, so the loop stays seamless) and splashes.
SPRAY_SWELL_CYCLES = (5, 11, 23)
SPRAY_SWELL_DB = 1.5
SPRAY_SPLASHES = 16
SPRAY_SPLASH_GAIN = (0.5, 1.2)
SPRAY_SPLASH_SECONDS = (0.03, 0.09)
SEED = 1293


def probe(path: str) -> tuple[int, int]:
    """(sample rate, channels) of the first audio stream."""
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=sample_rate,channels", "-of", "csv=p=0", path],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    rate, channels = out.strip().split(",")[:2]
    return int(rate), int(channels)


def read(path: str, start: float = 0.0, end: float | None = None) -> np.ndarray:
    """Any file, or its section from `start` to `end` s, as float stereo at RATE. Decoded at its
    own rate and channel count: ffmpeg's own mono-to-stereo upmix is 3 dB down, which would hide
    clipping, so mono is doubled here, and resampling is polyphase here rather than ffmpeg's
    default resampler. Only the section is decoded, so a long file costs no memory."""
    rate, channels = probe(path)
    span = ["-ss", f"{start:.6f}"] + (["-t", f"{end - start:.6f}"] if end is not None else [])
    raw = subprocess.run(["ffmpeg", "-v", "error", *span, "-i", path, "-f", "f32le", "-"], check=True, capture_output=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).reshape(-1, channels).astype(np.float64)
    if channels == 1:
        x = np.repeat(x, 2, axis=1)
    if rate != RATE:
        common = np.gcd(rate, RATE)
        x = resample_poly(x, RATE // common, rate // common, axis=0)
    return x


def k_weighted(x: np.ndarray) -> np.ndarray:
    """BS.1770 pre-filter (high shelf) and RLB high-pass, designed for RATE."""

    def biquad(kind: str, gain_db: float, q: float, fc: float):
        a_gain = 10 ** (gain_db / 40)
        w0 = 2 * np.pi * fc / RATE
        alpha = np.sin(w0) / (2 * q)
        cos = np.cos(w0)
        if kind == "shelf":
            root = 2 * np.sqrt(a_gain) * alpha
            b = [
                a_gain * ((a_gain + 1) + (a_gain - 1) * cos + root),
                -2 * a_gain * ((a_gain - 1) + (a_gain + 1) * cos),
                a_gain * ((a_gain + 1) + (a_gain - 1) * cos - root),
            ]
            a = [(a_gain + 1) - (a_gain - 1) * cos + root, 2 * ((a_gain - 1) - (a_gain + 1) * cos), (a_gain + 1) - (a_gain - 1) * cos - root]
        else:
            b = [(1 + cos) / 2, -(1 + cos), (1 + cos) / 2]
            a = [1 + alpha, -2 * cos, 1 - alpha]
        return np.array(b) / a[0], np.array(a) / a[0]

    b1, a1 = biquad("shelf", 3.999843853973347, 0.7071752369554196, 1681.974450955533)
    b2, a2 = biquad("highpass", 0.0, 0.5003270373238773, 38.13547087602444)
    return lfilter(b2, a2, lfilter(b1, a1, x, axis=0), axis=0)


def loudness(x: np.ndarray, periodic: bool, block_seconds: float = 3.0) -> float:
    """Ungated loudness of a loop (filtered as a loop), or of the loudest block of a one-shot."""
    if periodic:
        filtered = k_weighted(np.concatenate([x, x, x]))[len(x) : 2 * len(x)]
        return -0.691 + 10 * np.log10(np.sum(np.mean(filtered**2, axis=0)) + 1e-20)
    filtered = k_weighted(x)
    block, hop = int(block_seconds * RATE), int(0.1 * RATE)
    powers = [np.sum(np.mean(filtered[s : s + block] ** 2, axis=0)) for s in range(0, max(1, len(filtered) - block), hop)]
    return -0.691 + 10 * np.log10(max(powers) + 1e-20)


def peak_db(x: np.ndarray) -> float:
    return float(20 * np.log10(np.max(np.abs(x)) + 1e-12))


def high_pass(x: np.ndarray, periodic: bool) -> np.ndarray:
    sos = butter(2, HIGH_PASS_HZ, "highpass", fs=RATE, output="sos")
    if periodic:
        return sosfilt(sos, np.concatenate([x, x, x]), axis=0)[2 * len(x) :]
    return sosfilt(sos, x, axis=0)


def declip(x: np.ndarray, level: float = 0.999, reach: int = 8) -> tuple[np.ndarray, int]:
    """Redraws each run of full-scale samples with a cubic through `reach` samples either side."""
    y = x.copy()
    restored = 0
    for c in range(y.shape[1]):
        clipped = np.abs(y[:, c]) >= level
        index = np.nonzero(clipped)[0]
        if len(index) == 0:
            continue
        for run in np.split(index, np.nonzero(np.diff(index) > 1)[0] + 1):
            first, last = run[0], run[-1]
            before = np.arange(max(0, first - reach), first)
            after = np.arange(last + 1, min(len(y), last + 1 + reach))
            known = np.concatenate([before, after])
            if len(before) < 2 or len(after) < 2:
                continue
            y[run, c] = CubicSpline(known, y[known, c])(run)
            restored += len(run)
    return y, restored


def balance(x: np.ndarray) -> tuple[np.ndarray, float]:
    """Equal power in both channels; returns the left-minus-right difference it removed, dB."""
    power = np.mean(x**2, axis=0)
    difference = 10 * np.log10(power[0] / power[1])
    mean = np.sqrt(power.mean())
    return x * (mean / np.sqrt(power))[None, :], float(difference)


def flatten(x: np.ndarray) -> tuple[np.ndarray, float]:
    """Removes the straight-line trend of the level in dB (so the seam joins equal levels)."""
    frame = int(2.0 * RATE)
    centres, levels = [], []
    for start in range(0, len(x) - frame + 1, frame // 2):
        centres.append((start + frame / 2) / RATE)
        levels.append(10 * np.log10(np.mean(x[start : start + frame] ** 2) + 1e-20))
    slope, _ = np.polyfit(centres, levels, 1)
    t = np.arange(len(x)) / RATE
    correction = -slope * (t - t.mean())
    return x * 10 ** (correction / 20)[:, None], float(slope * len(x) / RATE)


def fold(x: np.ndarray, seconds: float) -> np.ndarray:
    """Folds the first `seconds` over the end with an equal-power fade (for noise-like loops)."""
    n = int(seconds * RATE)
    body = x[n:].copy()
    fade = np.linspace(0.0, np.pi / 2, n)[:, None]
    body[-n:] = body[-n:] * np.cos(fade) + x[:n] * np.sin(fade)
    return body


def limit(x: np.ndarray, ceiling_db: float, periodic: bool) -> tuple[np.ndarray, float, float]:
    """A look-ahead peak limiter, linked across channels: the gain each peak needs is held 15 ms
    either side and smoothed over 2 ms, so a loud drop is turned down whole rather than clipped.

    Returns the limited signal, the deepest gain reduction in dB and the share of samples touched.
    """
    ceiling = 10 ** (ceiling_db / 20)
    source = np.concatenate([x, x, x]) if periodic else x
    peak = maximum_filter1d(np.abs(source).max(axis=1), size=2 * int(0.001 * RATE) + 1)
    gain = np.minimum(1.0, ceiling / (peak + 1e-12))
    held = -maximum_filter1d(-gain, size=int(0.03 * RATE))
    gain = np.minimum(gain, uniform_filter1d(held, size=int(0.002 * RATE)))
    if periodic:
        gain = gain[len(x) : 2 * len(x)]
    y = x * gain[:, None]
    return y, float(20 * np.log10(gain.min())), float(np.mean(gain < 0.9999))


def normalise_loop(x: np.ndarray) -> tuple[np.ndarray, dict]:
    raw = loudness(x, periodic=True)
    y = x * 10 ** ((LOOP_LUFS - raw) / 20)
    y, deepest, share = limit(y, PEAK_CEILING_DB, periodic=True)
    return y, {
        "loudness_lufs": round(loudness(y, periodic=True), 2),
        "gain_db": round(LOOP_LUFS - raw, 2),
        "peak_dbfs": round(peak_db(y), 2),
        "limiter_max_db": round(deepest, 2),
        "limiter_samples_pct": round(share * 100, 3),
    }


def band_levels(x: np.ndarray) -> np.ndarray:
    """Third-octave band levels, 100 Hz to 16 kHz, dB."""
    spectrum = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    freqs = np.fft.rfftfreq(len(x), 1 / RATE)
    centres = 100 * 2 ** (np.arange(0, 23) / 3)
    return np.array([10 * np.log10(spectrum[(freqs >= c / 2 ** (1 / 6)) & (freqs < c * 2 ** (1 / 6))].sum() + 1e-20) for c in centres])


def seam_report(loop: np.ndarray) -> dict:
    """How the end of the loop meets its start, against how any moment meets the next one.

    Rain has no waveform to line up, so a seam is judged by what the ear tracks in noise: the
    level step and the change of spectrum across it, each against the same measure taken
    between neighbouring windows everywhere else in the loop (p50 and p95).
    """
    m = loop.mean(axis=1)
    wrapped = np.concatenate([m, m[: int(0.5 * RATE)]])
    seam = len(m)

    def level(segment):
        return 10 * np.log10(np.mean(segment**2) + 1e-20)

    short, long = int(0.1 * RATE), int(0.25 * RATE)
    steps = [abs(level(wrapped[s - short : s]) - level(wrapped[s : s + short])) for s in range(short, len(m) - short, short)]
    changes = [
        float(np.sqrt(np.mean((band_levels(wrapped[s - long : s]) - band_levels(wrapped[s : s + long])) ** 2)))
        for s in range(long, len(m) - long, long)
    ]
    jumps = np.abs(np.diff(wrapped[: seam + 1]))
    step = abs(level(wrapped[seam - short : seam]) - level(wrapped[seam : seam + short]))
    change = float(np.sqrt(np.mean((band_levels(wrapped[seam - long : seam]) - band_levels(wrapped[seam : seam + long])) ** 2)))
    return {
        "level_step_db": round(step, 2),
        "level_step_elsewhere_p50_p95": [round(float(v), 2) for v in np.percentile(steps, [50, 95])],
        # Share of the loop's other moments that change less than the seam does.
        "level_step_rank_pct": round(float(np.mean(np.array(steps) < step) * 100), 1),
        "spectrum_change_db": round(change, 2),
        "spectrum_change_elsewhere_p50_p95": [round(float(v), 2) for v in np.percentile(changes, [50, 95])],
        "spectrum_change_rank_pct": round(float(np.mean(np.array(changes) < change) * 100), 1),
        "jump_vs_p999": round(float(jumps[-1] / (np.percentile(jumps[:-1], 99.9) + 1e-12)), 3),
    }


def find(sources: list[str], name: str) -> str:
    for folder in sources:
        path = os.path.join(folder, name)
        if os.path.isfile(path):
            return path
    raise SystemExit(f"{name} is in none of {sources}")


def rain_loop(sources: list[str], spec: tuple) -> tuple[np.ndarray, dict]:
    name, source, start, end, clips = spec
    path = find(sources, source)
    section = read(path, start, end)
    entry = {"name": name, "kind": "loop", "source": f"{source} {start:g}-{start + len(section) / RATE:.3f} s"}
    if clips:
        section, restored = declip(section)
        entry["declipped_samples"] = restored
    section = section - section.mean(axis=0)
    section = high_pass(section, periodic=False)
    if probe(path)[1] == 2:
        section, difference = balance(section)
        entry["balanced_lr_db"] = round(difference, 2)
    section, drift = flatten(section)
    entry["drift_removed_db"] = round(drift, 2)
    loop = fold(section, FOLD_SECONDS)
    loop, levels = normalise_loop(loop)
    entry.update(levels)
    return loop, entry


def thunder(sources: list[str], index: int, source: str) -> tuple[np.ndarray, dict]:
    x = read(find(sources, source))
    x = high_pass(x - x.mean(axis=0), periodic=False)
    frame = int(0.01 * RATE)
    envelope = 10 * np.log10(uniform_filter1d(np.mean(x**2, axis=1), size=int(0.1 * RATE)) + 1e-20)
    top = envelope.max()
    first = int(np.argmax(envelope > top + THUNDER_START_DB))
    last = len(envelope) - 1 - int(np.argmax(envelope[::-1] > top + THUNDER_END_DB))
    first = max(0, first - int(0.1 * RATE))
    last = min(last, first + int(THUNDER_MAX_SECONDS * RATE))
    y = x[first:last].copy()
    y[:frame] *= np.sin(np.linspace(0, np.pi / 2, frame))[:, None]
    fade = int(THUNDER_FADE_SECONDS * RATE)
    y[-fade:] *= np.cos(np.linspace(0, np.pi / 2, fade))[:, None] ** 2
    raw = loudness(y, periodic=False)
    gain_db = THUNDER_LUFS - raw
    gain_db -= max(0.0, peak_db(y) + gain_db - PEAK_CEILING_DB)
    y *= 10 ** (gain_db / 20)
    return y, {
        "name": f"thunder_{index}",
        "kind": "one_shot",
        "source": f"{source} {first / RATE:.2f}-{last / RATE:.2f} s, last {THUNDER_FADE_SECONDS:g} s faded",
        "loudness_lufs_3s_max": round(loudness(y, periodic=False), 2),
        "gain_db": round(gain_db, 2),
        "peak_dbfs": round(peak_db(y), 2),
    }


def spray(sources: list[str]) -> tuple[np.ndarray, dict]:
    """Noise with the spectrum of the pass-by's closest second, periodic over SPRAY_SECONDS."""
    rng = np.random.default_rng(SEED)
    x = read(find(sources, SPRAY_SOURCE)).mean(axis=1)
    near = x[int(SPRAY_SECTION[0] * RATE) : int(SPRAY_SECTION[1] * RATE)]
    freqs, psd = welch(near, fs=RATE, nperseg=4096)
    # Third-octave smoothing in log frequency, so no single partial of the source survives.
    smooth = np.array([psd[(freqs >= f / 2 ** (1 / 6)) & (freqs <= f * 2 ** (1 / 6))].mean() if f > 0 else psd[0] for f in freqs])
    shape = np.sqrt(smooth)
    shape /= 1 + (SPRAY_HIGH_PASS_HZ / np.maximum(freqs, 1)) ** 4
    shape /= 1 + (freqs / SPRAY_LOW_PASS_HZ) ** 8
    n = int(SPRAY_SECONDS * RATE)
    loop_freqs = np.fft.rfftfreq(n, 1 / RATE)
    magnitude = np.interp(loop_freqs, freqs, shape)
    channels = []
    for _ in range(2):
        phase = rng.uniform(0, 2 * np.pi, len(loop_freqs))
        channels.append(np.fft.irfft(magnitude * np.exp(1j * phase), n))
    y = np.stack(channels, axis=1)
    t = np.arange(n) / n
    swell = sum(np.sin(2 * np.pi * (cycles * t + rng.uniform())) for cycles in SPRAY_SWELL_CYCLES)
    swell_db = SPRAY_SWELL_DB * swell / len(SPRAY_SWELL_CYCLES)
    splash = np.zeros(n)
    for _ in range(SPRAY_SPLASHES):
        at = rng.integers(n)
        length = int(rng.uniform(*SPRAY_SPLASH_SECONDS) * RATE)
        bump = rng.uniform(*SPRAY_SPLASH_GAIN) * np.exp(-np.arange(4 * length) / length)
        bump[: int(0.003 * RATE)] *= np.linspace(0, 1, int(0.003 * RATE))
        splash[(at + np.arange(len(bump))) % n] += bump
    y *= (10 ** (swell_db / 20) * (1 + splash))[:, None]
    loop, levels = normalise_loop(y - y.mean(axis=0))
    # The synthesis level is arbitrary, so its gain says nothing.
    del levels["gain_db"]
    return loop, {
        "name": "spray",
        "kind": "loop",
        "source": f"synthesised: noise with the third-octave spectrum of {SPRAY_SOURCE} {SPRAY_SECTION[0]:g}-{SPRAY_SECTION[1]:g} s, "
        f"high-passed at {SPRAY_HIGH_PASS_HZ:g} Hz, a +-{SPRAY_SWELL_DB:g} dB swell and {SPRAY_SPLASHES} splashes, periodic by construction",
        **levels,
    }


def write_wav(path: str, x: np.ndarray):
    rng = np.random.default_rng(7)
    dither = (rng.random(x.shape) - rng.random(x.shape)) / 32768.0
    pcm = np.clip(np.round((x + dither) * 32767), -32768, 32767).astype(np.int16)
    wavfile.write(path, RATE, pcm)


def encode(wav_path: str, ogg_path: str) -> np.ndarray:
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", wav_path, "-c:a", "libvorbis", "-q:a", VORBIS_QUALITY, ogg_path],
        check=True,
    )
    with tempfile.TemporaryDirectory() as scratch:
        decoded = os.path.join(scratch, "decoded.wav")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", ogg_path, decoded], check=True)
        return read(decoded)


def save(out: str, name: str, x: np.ndarray) -> np.ndarray:
    wav_path = os.path.join(out, "wav", f"{name}.wav")
    write_wav(wav_path, x)
    return encode(wav_path, os.path.join(out, f"{name}.ogg"))


def pack(out: str, loops: list, shots: list) -> list:
    """weather.ogg: every loop between guards of its own audio, then the one-shots apart."""
    guard = int(GUARD_SECONDS * RATE)
    gap = np.zeros((int(PACK_GAP_SECONDS * RATE), 2))
    parts, cursor = [], 0
    for entry, x in loops:
        parts += [x[-guard:], x, x[:guard]]
        entry["pack"] = {"file": "weather.ogg", "start_s": round((cursor + guard) / RATE, 6), "end_s": round((cursor + guard + len(x)) / RATE, 6)}
        cursor += len(x) + 2 * guard
    for entry, x in shots:
        parts += [gap, x]
        cursor += len(gap)
        entry["pack"] = {"file": "weather.ogg", "start_s": round(cursor / RATE, 6), "end_s": round((cursor + len(x)) / RATE, 6)}
        cursor += len(x)
    parts.append(gap)
    packed = np.concatenate(parts)
    decoded = save(out, "weather", packed)
    for entry, x in loops:
        region = decoded[int(round(entry["pack"]["start_s"] * RATE)) : int(round(entry["pack"]["end_s"] * RATE))]
        entry["seam_after_ogg"] = seam_report(region)
        # The decoded region lines up with what was written: correlation at lag 0 and at +-1 sample.
        probe = slice(guard, guard + int(0.5 * RATE))
        entry["pack_alignment"] = {
            str(lag): round(float(np.corrcoef(region[probe, 0], x[guard + lag : guard + lag + int(0.5 * RATE), 0])[0, 1]), 4) for lag in (-1, 0, 1)
        }
    summary = {
        "name": "weather",
        "kind": "pack",
        "file": "weather.ogg",
        "duration_s": round(len(packed) / RATE, 4),
        "decoded_length_diff": int(len(decoded)) - int(len(packed)),
        "bytes": os.path.getsize(os.path.join(out, "weather.ogg")),
        "guard_s": GUARD_SECONDS,
        "peak_dbfs": round(peak_db(packed), 2),
    }
    return [summary] + [entry for entry, _ in loops] + [entry for entry, _ in shots]


def main(out: str, sources: list[str]):
    os.makedirs(os.path.join(out, "wav"), exist_ok=True)
    loops = []
    for spec in LOOPS:
        loop, entry = rain_loop(sources, spec)
        entry["seam_before_ogg"] = seam_report(loop)
        entry["duration_s"] = round(len(loop) / RATE, 4)
        save(out, entry["name"], loop)
        loops.append((entry, loop))
    loop, entry = spray(sources)
    entry["seam_before_ogg"] = seam_report(loop)
    entry["duration_s"] = round(len(loop) / RATE, 4)
    save(out, "spray", loop)
    loops.append((entry, loop))
    shots = []
    for index, source in enumerate(THUNDERS, 1):
        shot, entry = thunder(sources, index, source)
        entry["duration_s"] = round(len(shot) / RATE, 4)
        save(out, entry["name"], shot)
        shots.append((entry, shot))
    manifest = pack(out, loops, shots)
    manifest[0]["asset_id"] = None
    with open(os.path.join(out, "manifest.json"), "w") as handle:
        json.dump(manifest, handle, indent=1)
    for entry in manifest:
        print(json.dumps(entry))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
