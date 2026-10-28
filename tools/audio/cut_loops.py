"""
Cuts the Drive Lab SVJ engine sound set out of the decoded Assetto Corsa bank: seamless engine
loops, a start-up one-shot, a V12 limiter loop, the gear clunk and a pick of backfires. Writes
OGG Vorbis files (and the WAV they were encoded from) plus manifest.json to <out dir>.

The one-shots are also packed into events.ogg, each with its region in the manifest, so the
set costs six audio uploads (Open Cloud allows 10 a month to a creator who is not ID-verified).

What the material allows. The bank's on- and off-throttle engine takes are each ONE steady rpm
(about 7,560 and 7,265 rpm), built by repeating a few-second loop; the mod plays them pitched
by rpm / 7,600 and rpm / 7,400 (tools/audio/fmod_autopitch.py). So there is one on loop and
one off loop, not a loop per rpm step: a "set" resampled from one take would only be that
take at other speeds, and crossfading two speeds of one take combs.

A loop is cut where the take repeats itself: the lag with the highest normalised
cross-correlation, at a rising zero crossing, then a short linear crossfade from the loop's
tail into the samples just before its start. Each loop is measured at its seam (sample jump
and high-passed click energy against the rest of the loop, and the firing-order rpm on both
sides), again after OGG decoding. Loudness is BS.1770 K-weighted, ungated (the loops are
steady); one-shots are matched on their loudest 400 ms.

    python -I tools/audio/cut_loops.py <wav dir> <out dir>
"""

import json
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy.interpolate import CubicSpline
from scipy.io import wavfile
from scipy.signal import butter, fftconvolve, lfilter, resample, sosfilt

RATE = 44100
LOOP_LUFS = -18.0
GEAR_LUFS = -14.0
# Pops are all transient: matched low enough that none of them reaches the peak ceiling.
BACKFIRE_LUFS = -20.0
PEAK_CEILING_DB = -1.0
SEAM_FADE = 256
VORBIS_QUALITY = "6"
LIMITER_RPM = 8700.0
# A V12 fuel cut bounces at about 15 to 20 Hz; the S50 sample in the bank bounces at 9.5 Hz.
LIMITER_RHYTHM_HZ = 17.0
LIMITER_FIRE_SHARE = 0.55
LIMITER_CUT_DB = -20.0
LIMITER_PITCH_SWING = 0.012

ENGINE_LOOPS = [
    # name, source, firing-order line (Hz) at which rpm = line * 10, search start s, min and max length s
    ("eng_on", "24_lamborghini_aventador_int_on_new5b.wav", 755.9, 20.0, 3.0, 30.0),
    ("eng_off", "17_lamborghini_aventador_int_off_new4b.wav", 726.5, 20.0, 3.0, 30.0),
    ("eng_idle", "13_Avent_Startup_Race_Adaptive_Idle.wav", 154.4, 40.0, 3.0, 30.0),
]
NOTES = {
    "eng_on": "the mod's auto-pitch plays it x1 at 7,600 rpm",
    "eng_off": "the mod's auto-pitch plays it x1 at 7,400 rpm",
    "eng_idle": "rpm reads the 154 Hz line as the firing order; the line spacing also fits half that. "
    "The mod plays this sample unpitched at its 950 rpm idle.",
}
BACKFIRES = [
    "05_500_backfire3.wav",
    "15_500_backfire5.wav",
    "27_500_backfire6.wav",
    "14_backfireEXT_9.wav",
    "35_backfireEXT_2.wav",
    "31_backfireEXT_4.wav",
]
GEAR = "37_gearupEXT.wav"  # byte-identical to 32_geardnEXT.wav
FAR = "34_MCC_-_Exterior_Far_Car_Sound_Loop.wav"
STARTUP = "13_Avent_Startup_Race_Adaptive_Idle.wav"
# The cold idle after the flare settles to the warm idle the idle loop holds by about 10 s.
STARTUP_SECONDS = 10.5
STARTUP_FADE_SECONDS = 2.0
FAR_SEAM_SECONDS = 0.1
# Silence between one-shots in the packed file, so an imprecise region start cannot bleed.
PACK_GAP_SECONDS = 0.5


def read(path: str) -> np.ndarray:
    rate, data = wavfile.read(path)
    assert rate == RATE, f"{path}: {rate} Hz"
    samples = data.astype(np.float64) / 32768.0
    return samples[:, None] if samples.ndim == 1 else samples


def mono(x: np.ndarray) -> np.ndarray:
    return x.mean(axis=1)


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


def loudness(x: np.ndarray, periodic: bool) -> float:
    """Ungated loudness of a steady loop (filtered as a loop), or the loudest 400 ms block."""
    if periodic:
        filtered = k_weighted(np.concatenate([x, x, x]))[len(x) : 2 * len(x)]
        return -0.691 + 10 * np.log10(np.sum(np.mean(filtered**2, axis=0)) + 1e-20)
    filtered = k_weighted(x)
    block, hop = int(0.4 * RATE), int(0.1 * RATE)
    if len(filtered) <= block:
        return -0.691 + 10 * np.log10(np.sum(np.mean(filtered**2, axis=0)) + 1e-20)
    powers = [np.sum(np.mean(filtered[s : s + block] ** 2, axis=0)) for s in range(0, len(filtered) - block, hop)]
    return -0.691 + 10 * np.log10(max(powers) + 1e-20)


def normalise(x: np.ndarray, target: float, periodic: bool) -> tuple[np.ndarray, float, float]:
    gain_db = target - loudness(x, periodic)
    peak_db = 20 * np.log10(np.max(np.abs(x)) + 1e-12) + gain_db
    if peak_db > PEAK_CEILING_DB:
        gain_db -= peak_db - PEAK_CEILING_DB
    y = x * 10 ** (gain_db / 20)
    return y, loudness(y, periodic), 20 * np.log10(np.max(np.abs(y)) + 1e-12)


def ncc_search(signal: np.ndarray, start: int, window: int, low: int, high: int) -> tuple[np.ndarray, int]:
    reference = signal[start : start + window]
    region = signal[start + low : start + high + window]
    correlation = fftconvolve(region, reference[::-1], mode="valid")
    energy = np.sqrt(fftconvolve(region**2, np.ones(window), mode="valid") * np.sum(reference**2))
    return correlation / (energy + 1e-12), low


def repeat_match(signal: np.ndarray, start: int, length: int) -> float:
    """Normalised correlation of 2 s around the loop start with 2 s around its end."""
    span = int(2.0 * RATE)
    a = signal[start - span // 2 : start + span // 2]
    b = signal[start + length - span // 2 : start + length + span // 2]
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-12))


def find_repeat(signal: np.ndarray, search_start: float, min_len: float, max_len: float) -> tuple[int, int, float]:
    """(start, length, match) of the longest loop that repeats the take as well as the best one.

    A 0.5 s probe proposes lags; each is then judged on 2 s across its seam, so a lag that
    matches only locally loses to one where the take truly repeats. Among equal matches the
    longest wins: a longer loop hides its repetition better.
    """
    window = int(0.5 * RATE)
    candidates = []
    for offset in np.arange(0.0, 6.0, 0.75):
        start = int((search_start + offset) * RATE)
        ncc, low = ncc_search(signal, start, window, int(min_len * RATE), int(max_len * RATE))
        best = float(ncc.max())
        for lag in np.nonzero(ncc > best - 0.02)[0]:
            if ncc[lag] >= ncc[max(lag - 1, 0)] and ncc[lag] >= ncc[min(lag + 1, len(ncc) - 1)]:
                length = low + int(lag)
                candidates.append((repeat_match(signal, start, length), length, start))
    top = max(c[0] for c in candidates)
    match, length, start = max((c for c in candidates if c[0] > top - 0.0005), key=lambda c: c[1])
    return start, length, match


def rising_zero(signal: np.ndarray, near: int, reach: int) -> int:
    for distance in range(reach):
        for index in (near + distance, near - distance):
            if signal[index - 1] < 0 <= signal[index]:
                return index
    return near


def cut_loop(x: np.ndarray, start: int, length: int) -> np.ndarray:
    loop = x[start : start + length].copy()
    tail = loop[-SEAM_FADE:]
    lead_in = x[start - SEAM_FADE : start]
    ramp = np.linspace(0.0, 1.0, SEAM_FADE)[:, None]
    loop[-SEAM_FADE:] = tail * (1 - ramp) + lead_in * ramp
    return loop - loop.mean(axis=0)


def firing_rpm(signal: np.ndarray, line: float) -> np.ndarray:
    """Firing-order rpm per 4096-sample frame, from the strongest peak within 10 % of `line`."""
    size, hop = 4096, 1024
    window = np.hanning(size)
    freqs = np.fft.rfftfreq(size, 1 / RATE)
    band = np.nonzero((freqs > line * 0.9) & (freqs < line * 1.1))[0]
    out = []
    for s in range(0, len(signal) - size, hop):
        spectrum = np.abs(np.fft.rfft(signal[s : s + size] * window))
        i = band[int(np.argmax(spectrum[band]))]
        a, b, c = np.log(spectrum[i - 1 : i + 2] + 1e-12)
        curve = a - 2 * b + c
        out.append((i + (0.5 * (a - c) / curve if curve else 0.0)) * RATE / size * 10)
    return np.array(out)


def seam_report(loop: np.ndarray, line: float | None) -> dict:
    """How the loop's end meets its start, against the loop's own statistics."""
    m = mono(loop)
    jumps = np.abs(np.diff(np.concatenate([m, m[:1]])))
    seam_jump = jumps[-1]
    sos = butter(4, 4000, "highpass", fs=RATE, output="sos")
    tripled = np.concatenate([m, m, m])
    high = sosfilt(sos, tripled)[len(m) : 2 * len(m) + len(m)]
    frame = int(0.002 * RATE)
    energies = np.array([np.mean(high[s : s + frame] ** 2) for s in range(0, len(m), frame)])
    seam_energy = np.mean(high[len(m) - frame : len(m) + frame] ** 2)
    report = {
        "jump_vs_p999": round(float(seam_jump / (np.percentile(jumps[:-1], 99.9) + 1e-12)), 3),
        "click_db_vs_median": round(float(10 * np.log10(seam_energy / (np.median(energies) + 1e-20))), 2),
        "click_db_vs_p99": round(float(10 * np.log10(seam_energy / (np.percentile(energies, 99) + 1e-20))), 2),
    }
    if line is not None:
        twice = np.concatenate([m, m])
        rpm = firing_rpm(twice, line)
        steps_per_loop = len(m) // 1024
        inside = rpm[: steps_per_loop - 4]
        median = float(np.median(inside))
        across = rpm[steps_per_loop - 4 : steps_per_loop + 1]
        local = [np.ptp(inside[i : i + 5]) for i in range(0, len(inside) - 5)]
        report.update(
            {
                "rpm_median": round(median),
                "rpm_spread_pct_5_95": round(float((np.percentile(inside, 95) - np.percentile(inside, 5)) / median * 100), 2),
                "rpm_step_at_seam_pct": round(float((across.max() - across.min()) / median * 100), 2),
                "rpm_step_elsewhere_p95_pct": round(float(np.percentile(local, 95) / median * 100), 2),
            }
        )
    return report


def write_wav(path: str, x: np.ndarray):
    rng = np.random.default_rng(7)
    dither = (rng.random(x.shape) - rng.random(x.shape)) / 32768.0
    pcm = np.clip(np.round((x + dither) * 32767), -32768, 32767).astype(np.int16)
    wavfile.write(path, RATE, pcm[:, 0] if pcm.shape[1] == 1 else pcm)


def encode(wav_path: str, ogg_path: str) -> np.ndarray:
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", wav_path, "-c:a", "libvorbis", "-q:a", VORBIS_QUALITY, ogg_path],
        check=True,
    )
    with tempfile.TemporaryDirectory() as scratch:
        decoded = os.path.join(scratch, "decoded.wav")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", ogg_path, decoded], check=True)
        return read(decoded)


def save(out: str, name: str, x: np.ndarray, entry: dict, line: float | None) -> dict:
    wav_path = os.path.join(out, "wav", f"{name}.wav")
    ogg_path = os.path.join(out, f"{name}.ogg")
    write_wav(wav_path, x)
    decoded = encode(wav_path, ogg_path)
    entry.update(
        {
            "file": f"{name}.ogg",
            "channels": int(x.shape[1]),
            "duration_s": round(len(x) / RATE, 4),
            "bytes": os.path.getsize(ogg_path),
            "decoded_length_diff": int(len(decoded)) - int(len(x)),
        }
    )
    if entry["loop"]:
        entry["seam_after_ogg"] = seam_report(decoded[: len(x)], line)
    return entry


def engine_loop(wav_dir: str, out: str, spec: tuple) -> tuple[dict, np.ndarray]:
    name, source, line, search_start, min_len, max_len = spec
    x = read(os.path.join(wav_dir, source))
    m = mono(x)
    start, length, confirm = find_repeat(m, search_start, min_len, max_len)
    start = rising_zero(m, start, int(0.003 * RATE))
    loop = cut_loop(x, start, length)
    raw_lufs = loudness(loop, periodic=True)
    loop, lufs, peak = normalise(loop, LOOP_LUFS, periodic=True)
    entry = {
        "name": name,
        "kind": "engine_loop",
        "rpm": round(float(np.median(firing_rpm(mono(loop), line)))),
        "throttle": {"eng_on": "on", "eng_off": "off", "eng_idle": "any"}[name],
        "loop": True,
        "source": f"{source} {start / RATE:.4f}-{(start + length) / RATE:.4f} s",
        "repeat_ncc_2s": round(confirm, 5),
        "loudness_lufs": round(lufs, 2),
        "gain_db": round(lufs - raw_lufs, 2),
        "peak_dbfs": round(peak, 2),
        "seam": seam_report(loop, line),
    }
    if name in NOTES:
        entry["note"] = NOTES[name]
    return save(out, name, loop, entry, line), loop


def limiter_loop(out: str, on_loop: np.ndarray, on_rpm: float) -> dict:
    """The on loop raised to the limiter and gated at a V12 fuel-cut rhythm, pitch dipping in each cut."""
    length = int(round(len(on_loop) * on_rpm / LIMITER_RPM))
    raised = resample(on_loop, length, axis=0)
    seconds = length / RATE
    cycles = max(1, round(LIMITER_RHYTHM_HZ * seconds))
    rhythm = cycles / seconds
    t = np.arange(length) / RATE
    # Read position swings around real time with zero mean per cycle, so the loop stays whole.
    position = t + LIMITER_PITCH_SWING / (2 * np.pi * rhythm) * np.sin(2 * np.pi * rhythm * t)
    tiled_t = np.arange(-length, 2 * length) / RATE
    tiled = np.concatenate([raised, raised, raised])
    warped = CubicSpline(tiled_t, tiled, axis=0)(position)
    phase = (t * rhythm) % 1.0
    ramp = 0.002 * rhythm
    cut = 10 ** (LIMITER_CUT_DB / 20)
    gate = np.where(phase < LIMITER_FIRE_SHARE, 1.0, cut)
    rising = phase < ramp
    gate[rising] = cut + (1 - cut) * 0.5 * (1 - np.cos(np.pi * phase[rising] / ramp))
    falling = (phase >= LIMITER_FIRE_SHARE) & (phase < LIMITER_FIRE_SHARE + ramp)
    gate[falling] = cut + (1 - cut) * 0.5 * (1 + np.cos(np.pi * (phase[falling] - LIMITER_FIRE_SHARE) / ramp))
    shaped, lufs, peak = normalise(warped * gate[:, None], LOOP_LUFS, periodic=True)
    entry = {
        "name": "eng_limiter",
        "kind": "limiter_loop",
        "rpm": LIMITER_RPM,
        "throttle": "on",
        "loop": True,
        "source": f"eng_on raised to {LIMITER_RPM:g} rpm, gated at {rhythm:.2f} Hz ({LIMITER_FIRE_SHARE:.0%} firing, cut {LIMITER_CUT_DB:g} dB), pitch swing +-{LIMITER_PITCH_SWING:.1%}",
        "loudness_lufs": round(lufs, 2),
        "peak_dbfs": round(peak, 2),
        "seam": seam_report(shaped, None),
    }
    return save(out, "eng_limiter", shaped, entry, None)


def trim(x: np.ndarray, fade_in: float = 0.002, fade_out: float = 0.02) -> np.ndarray:
    envelope = np.convolve(np.abs(mono(x)), np.ones(64) / 64, mode="same")
    active = np.nonzero(envelope > envelope.max() * 0.01)[0]
    first = max(0, active[0] - int(0.002 * RATE))
    last = min(len(x), active[-1] + int(0.01 * RATE))
    y = x[first:last].copy()
    n_in, n_out = int(fade_in * RATE), int(fade_out * RATE)
    y[:n_in] *= np.linspace(0, 1, n_in)[:, None]
    y[-n_out:] *= np.linspace(1, 0, n_out)[:, None]
    return y


def one_shot(wav_dir: str, out: str, name: str, source: str, kind: str, target: float) -> dict:
    x = trim(read(os.path.join(wav_dir, source)))
    y, lufs, peak = normalise(x, target, periodic=False)
    entry = {
        "name": name,
        "kind": kind,
        "rpm": None,
        "throttle": None,
        "loop": False,
        "source": source,
        "loudness_lufs_400ms_max": round(lufs, 2),
        "peak_dbfs": round(peak, 2),
    }
    return save(out, name, y, entry, None), y


def crossfade_seam(x: np.ndarray, seconds: float) -> np.ndarray:
    """Folds the first `seconds` over the end with an equal-power fade (for noise-like loops)."""
    n = int(seconds * RATE)
    body = x[n:].copy()
    fade = np.linspace(0.0, np.pi / 2, n)[:, None]
    body[-n:] = body[-n:] * np.cos(fade) + x[:n] * np.sin(fade)
    return body


def far_loop(wav_dir: str, out: str) -> dict:
    x = read(os.path.join(wav_dir, FAR))
    x = x - x.mean(axis=0)
    native = seam_report(x, None)
    folded = crossfade_seam(x, FAR_SEAM_SECONDS)
    y, lufs, peak = normalise(folded, LOOP_LUFS, periodic=True)
    entry = {
        "name": "eng_far",
        "kind": "far_loop",
        "rpm": None,
        "throttle": "any",
        "loop": True,
        "source": f"{FAR}, whole file, its first {FAR_SEAM_SECONDS:g} s folded over the end",
        "loudness_lufs": round(lufs, 2),
        "peak_dbfs": round(peak, 2),
        "seam_native": native,
        "seam": seam_report(y, None),
    }
    return save(out, "eng_far", y, entry, None)


def startup(wav_dir: str, out: str, idle_gain_db: float, idle_lufs: float) -> dict:
    """The flare and the cold idle settling, at the idle loop's gain so the hand-over is level."""
    x = read(os.path.join(wav_dir, STARTUP))[: int(STARTUP_SECONDS * RATE)].copy()
    peak_db = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
    gain_db = min(idle_gain_db, PEAK_CEILING_DB - peak_db)
    x *= 10 ** (gain_db / 20)
    settled = slice(int((STARTUP_SECONDS - STARTUP_FADE_SECONDS - 1.5) * RATE), int((STARTUP_SECONDS - STARTUP_FADE_SECONDS) * RATE))
    tail = x[settled].copy()
    fade = int(STARTUP_FADE_SECONDS * RATE)
    x[-fade:] *= np.cos(np.linspace(0, np.pi / 2, fade))[:, None]
    x[:220] *= np.linspace(0, 1, 220)[:, None]
    boost = idle_gain_db - gain_db
    entry = {
        "name": "eng_startup",
        "kind": "startup",
        "rpm": None,
        "throttle": None,
        "loop": False,
        "source": f"{STARTUP} 0-{STARTUP_SECONDS:g} s, last {STARTUP_FADE_SECONDS:g} s faded out (the idle loop takes over)",
        "gain_db": round(gain_db, 2),
        "peak_dbfs": round(20 * np.log10(np.max(np.abs(x)) + 1e-12), 2),
        # Play the start-up this many dB louder than the idle loop for a level hand-over.
        "boost_vs_idle_db": round(boost, 2),
        "settled_tail_vs_idle_loop_db": round(loudness(tail, periodic=False) + boost - idle_lufs, 2),
    }
    return save(out, "eng_startup", x, entry, None), x


def pack(out: str, items: list) -> dict:
    """One stereo file holding every one-shot, PACK_GAP_SECONDS apart; each entry gets its region."""
    gap = np.zeros((int(PACK_GAP_SECONDS * RATE), 2))
    parts, cursor = [gap], len(gap)
    for entry, x in items:
        stereo = np.repeat(x, 2, axis=1) if x.shape[1] == 1 else x
        entry["pack"] = {"file": "events.ogg", "start_s": round(cursor / RATE, 4), "end_s": round((cursor + len(stereo)) / RATE, 4)}
        parts += [stereo, gap]
        cursor += len(stereo) + len(gap)
    packed = np.concatenate(parts)
    entry = {
        "name": "events",
        "kind": "pack",
        "rpm": None,
        "throttle": None,
        "loop": False,
        "source": "every one-shot below, played through Sound.PlaybackRegion",
        "peak_dbfs": round(20 * np.log10(np.max(np.abs(packed)) + 1e-12), 2),
    }
    return save(out, "events", packed, entry, None)


def main(wav_dir: str, out: str):
    os.makedirs(os.path.join(out, "wav"), exist_ok=True)
    manifest = []
    on_loop, on_rpm = None, None
    for spec in ENGINE_LOOPS:
        entry, loop = engine_loop(wav_dir, out, spec)
        manifest.append(entry)
        if entry["name"] == "eng_on":
            on_loop, on_rpm = loop, entry["rpm"]
    manifest.append(limiter_loop(out, on_loop, on_rpm))
    idle = next(entry for entry in manifest if entry["name"] == "eng_idle")
    manifest.append(far_loop(wav_dir, out))
    shots = [startup(wav_dir, out, idle["gain_db"], idle["loudness_lufs"])]
    shots.append(one_shot(wav_dir, out, "gear_clunk", GEAR, "gear", GEAR_LUFS))
    for index, source in enumerate(BACKFIRES, 1):
        shots.append(one_shot(wav_dir, out, f"backfire_{index}", source, "backfire", BACKFIRE_LUFS))
    manifest.append(pack(out, shots))
    manifest += [entry for entry, _ in shots]
    for entry in manifest:
        entry["asset_id"] = None
    with open(os.path.join(out, "manifest.json"), "w") as handle:
        json.dump(manifest, handle, indent=1)
    for entry in manifest:
        print(json.dumps(entry))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
