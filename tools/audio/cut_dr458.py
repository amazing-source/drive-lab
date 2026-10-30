"""
Cuts the Drive Lab DR458 sound set (Config/Cars/DR458/Audio) out of two Assetto Corsa banks, both
458 Italia: <bank A> (ferrari_458_s3.bank of "New Ferrari 458 Italia Sound Mod 2.1") gives the
cabin engine loops, the idle and the exterior loops the far loop is made of; <bank B>
(ksk_ferrari_458.bank) gives the stereo of its own loops, the pops ("pet") and the shift click.
Both are plain PCM banks, read with tools/assets/fsb5_extract.py. Writes OGG Vorbis files (and the
WAV they were encoded from) plus manifest.json to <out dir>.

A bank loop's last few milliseconds fade out, and its own loop end is not continuous with its
start. Each loop is therefore cut where the samples just before the bank's loop end best match
its first 50 ms (normalised cross-correlation), and those samples are crossfaded into its start.
Its rpm is the 4th engine order of a flat-plane V8 (rpm / 15 Hz), read off the whole loop's
spectrum near the rpm the bank's own auto-pitch gives.

The bank is a road 458 heard from the cabin: near-mono and dull. Unless --raw, every engine
sound is shaped toward the Challenge's straight-through exhaust, in this order, filtered as a
loop so every seam stays whole: a 30 Hz high-pass; -6 dB below 200 Hz (cabin boom); a parallel
exciter (300 Hz to 3 kHz driven into tanh, its harmonics above 1.2 kHz mixed back in); +9 dB
above 2 kHz; then stereo, whose side is bank B's nearest-rpm loop resampled to the same rpm and
high-passed at 800 Hz, its seam folded. --raw keeps the bank as recorded, for an A/B.

Neither bank has a start-up: it is synthesised. A starter cranks (pinion whine, brush noise and a
compression pulse at the cranking speed's 4th order), then the engine catches, flares and
settles, rendered from this set's own loops along an rpm path.

    python -I tools/audio/cut_dr458.py <bank A> <bank B> <out dir> [--raw]
"""

import json
import os
import sys

import numpy as np
from scipy.signal import butter, fftconvolve, resample, sosfilt

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets"))
import cut_loops as C  # noqa: E402
import fsb5_extract  # noqa: E402

RATE = C.RATE
ORDER = 4.0
LOOP_LUFS = -18.0
GEAR_LUFS = -14.0
POP_LUFS = -20.0

# name, bank A sample, the rpm its auto-pitch plays at x1, load.
LOOPS = [
    ("idle", "idle", 900, "Both"),
    ("on_2100", "2000_load", 2000, "On"),
    ("on_2900", "3000_load", 2800, "On"),
    ("on_4900", "5000_load", 4900, "On"),
    ("on_5900", "6000_load", 5800, "On"),
    ("on_6900", "7000_load", 6900, "On"),
    ("on_8100", "8000_load", 8000, "On"),
    ("off_2000", "2000", 2000, "Off"),
    ("off_3800", "4000", 3800, "Off"),
    ("off_5000", "5000", 5000, "Off"),
    ("off_7000", "7000", 6900, "Off"),
    ("off_9000", "9000", 8900, "Off"),
]
# The idle's strongest lines sit at 8 and 12 times its 4th order; the 4th order itself is weak.
IDLE_LINE_ORDERS = (8.0, 12.0)
FAR_SOURCES = ["4000_load_ext", "5000_load_ext", "6000_load_ext", "7000_load_ext"]
FAR_CUTOFF_HZ = 2500.0
LOW_SHELF_DB, LOW_SHELF_HZ = -6.0, 200.0
EXCITER_BAND_HZ = (300.0, 3000.0)
# tanh input level, in multiples of the band's peak-ish level (4 x its RMS).
EXCITER_DRIVE = 6.0
EXCITER_HIGHPASS_HZ = 1200.0
EXCITER_MIX = 2.5
HIGH_SHELF_DB, HIGH_SHELF_HZ = 9.0, 2000.0
SIDE_SET = "fs"
SIDE_HIGHPASS_HZ = 800.0
SIDE_SHARE = 0.35
SIDE_SEAM_SECONDS = 0.08
POPS = ["pet1", "pet2", "pet3", "pet4", "pet5", "pet6", "pet7", "pet8", "pet10"]
GEAR = "shift1"

LIMITER_RPM = 9000.0
# Hard-cut race limiters bounce at about 10 to 20 Hz; 15 Hz is our choice, no source gives it.
LIMITER_RHYTHM_HZ = 15.0
LIMITER_FIRE_SHARE = 0.55
LIMITER_CUT_DB = -20.0

# The start-up, seconds and rpm. The settled idle is the preview drive's assumption (no source).
CRANK_SECONDS = 0.85
CRANK_RPM = 230.0
STARTER_PINION_RATIO = 12.0
STARTER_PINION_TEETH = 10
FLARE_PATH = [(0.0, CRANK_RPM, 1.0), (0.3, 3200.0, 1.0), (0.42, 3100.0, 0.0), (1.0, 1700.0, 0.0), (1.8, 1300.0, 0.15), (4.0, 1150.0, 0.15), (8.5, 1000.0, 0.12), (9.65, 1000.0, 0.12)]
STARTUP_FADE_SECONDS = 2.0
# Mirrors the pack's engineTuning (Config/Cars/DR458/Audio) for the start-up's own mix.
QUIET_RPM, QUIET_DB, LOUD_RPM, LOUD_DB = 1000.0, -12.0, 8500.0, 0.0
CROSSFADE_OCTAVES = 0.5
SEAM_SECONDS = 0.05
SEAM_SEARCH_SECONDS = 0.25


def read_bank(path: str) -> dict:
    """Every sample of a PCM16 bank by name: (audio, loop end or None)."""
    data = open(path, "rb").read()
    codec, samples = fsb5_extract.read_samples(data, data.find(b"FSB5"))
    assert codec == "PCM16", f"{path}: {codec}"
    out = {}
    for sample in samples:
        pcm = np.frombuffer(sample["bytes"][: sample["frames"] * 2 * sample["channels"]], dtype="<i2")
        assert sample["rate"] == RATE, f"{sample['name']}: {sample['rate']} Hz"
        audio = pcm.reshape(-1, sample["channels"]).astype(np.float64) / 32768.0
        loop = sample.get("loop")
        out[sample["name"]] = (audio, loop[1] if loop else None)
    return out


def seamless(x: np.ndarray, loop_end: int) -> tuple[np.ndarray, dict]:
    """x[0:n], its first SEAM_SECONDS crossfaded from x[n:], n where x[n:] best matches the start."""
    fade = int(SEAM_SECONDS * RATE)
    m = C.mono(x)
    head = m[:fade]
    low = loop_end - int(SEAM_SEARCH_SECONDS * RATE) - fade
    region = m[low:loop_end]
    correlation = fftconvolve(region, head[::-1], mode="valid")
    energy = np.sqrt(fftconvolve(region**2, np.ones(fade), mode="valid") * np.sum(head**2))
    ncc = correlation / (energy + 1e-12)
    k = int(np.argmax(ncc))
    n = low + k
    ramp = np.linspace(0.0, 1.0, fade)[:, None]
    if ncc[k] < 0.6:
        ramp = np.sin(ramp * np.pi / 2)
        tail_gain = np.cos(np.linspace(0.0, 1.0, fade)[:, None] * np.pi / 2)
    else:
        tail_gain = 1 - ramp
    loop = x[:n].copy()
    loop[:fade] = x[:fade] * ramp + x[n : n + fade] * tail_gain
    return loop - loop.mean(axis=0), {"bank_loop_end": int(loop_end), "cut_at": int(n), "seam_ncc": round(float(ncc[k]), 4)}


def stereo(x: np.ndarray) -> np.ndarray:
    return np.repeat(x, 2, axis=1) if x.shape[1] == 1 else x


def circular(sos: np.ndarray, x: np.ndarray) -> np.ndarray:
    """Filters a loop as the loop it is: its end runs into its start."""
    n = len(x)
    return sosfilt(sos, np.concatenate([x, x, x]), axis=0)[n : 2 * n]


def shelf(x: np.ndarray, gain_db: float, cutoff: float, kind: str) -> np.ndarray:
    """The input plus `gain_db` on its part below or above `cutoff`."""
    sos = butter(2, cutoff, "lowpass" if kind == "low" else "highpass", fs=RATE, output="sos")
    return x + (10 ** (gain_db / 20) - 1) * circular(sos, x)


def line_rpm(x: np.ndarray, guess_rpm: float, orders: tuple = (ORDER,), band: float = 0.12) -> float:
    """Rpm from the strongest line within `band` of where each order should be, whole loop."""
    m = C.mono(x)
    spectrum = np.abs(np.fft.rfft(m * np.hanning(len(m)), n=4 * len(m)))
    freqs = np.fft.rfftfreq(4 * len(m), 1 / RATE)
    votes = []
    for order in orders:
        line = guess_rpm / 60 * order
        near = np.nonzero((freqs > line * (1 - band)) & (freqs < line * (1 + band)))[0]
        votes.append(freqs[near[int(np.argmax(spectrum[near]))]] * 60 / order)
    return float(np.median(votes))


def side_layer(bank_b: dict, rpm: float, length: int) -> tuple[np.ndarray, str]:
    """Bank B's nearest loop resampled to `rpm`, its side only, as a seamless loop of `length`."""
    prefix = f"ferrari_458_{SIDE_SET}"
    candidates = []
    for name in bank_b:
        if name.startswith(prefix) and name.endswith("loop"):
            recorded = float(name[len(prefix) : -len("loop")])
            candidates.append((abs(np.log(rpm / recorded)), recorded, name))
    _, recorded, path = min(candidates)
    audio, loop_end = bank_b[path]
    x = audio[: loop_end or len(audio)]
    measured = line_rpm(x, recorded)
    speed = rpm / measured
    fold = int(SIDE_SEAM_SECONDS * RATE)
    needed = int((length + fold) * speed) + 8
    assert needed <= len(x), f"{path} too short for {length} samples at x{speed:.3f}"
    raised = resample(x[:needed], int(needed / speed), axis=0)[: length + fold]
    side = (raised[:, 0] - raised[:, 1]) / 2
    side = C.crossfade_seam(side[:, None], SIDE_SEAM_SECONDS)[:, 0]
    sos = butter(4, SIDE_HIGHPASS_HZ, "highpass", fs=RATE, output="sos")
    return circular(sos, side[:, None])[:, 0], f"bank B {path} ({measured:.0f} rpm) x{speed:.4f}"


def race_shape(x: np.ndarray, rpm: float, bank_b: dict) -> tuple[np.ndarray, str]:
    m = C.mono(x)[:, None]
    m = circular(butter(2, 30, "highpass", fs=RATE, output="sos"), m)
    m = shelf(m, LOW_SHELF_DB, LOW_SHELF_HZ, "low")
    band = circular(butter(4, EXCITER_BAND_HZ, "bandpass", fs=RATE, output="sos"), m)
    drive = EXCITER_DRIVE / (np.sqrt(np.mean(band**2)) * 4 + 1e-12)
    harmonics = np.tanh(band * drive) / drive
    harmonics = circular(butter(4, EXCITER_HIGHPASS_HZ, "highpass", fs=RATE, output="sos"), harmonics)
    m = m + EXCITER_MIX * harmonics
    m = shelf(m, HIGH_SHELF_DB, HIGH_SHELF_HZ, "high")
    side, source = side_layer(bank_b, rpm, len(m))
    side *= SIDE_SHARE * np.sqrt(np.mean(m**2)) / (np.sqrt(np.mean(side**2)) + 1e-12)
    out = np.stack([m[:, 0] + side, m[:, 0] - side], axis=1)
    return out - out.mean(axis=0), source


def tilt(x: np.ndarray) -> dict:
    m = C.mono(x)
    power = np.abs(np.fft.rfft(m * np.hanning(len(m)))) ** 2
    freqs = np.fft.rfftfreq(len(m), 1 / RATE)
    total = power.sum() + 1e-20
    report = {
        "centroid_hz": round(float((freqs * power).sum() / total)),
        "above_2k_pct": round(float(power[freqs > 2000].sum() / total * 100), 2),
        "below_200_pct": round(float(power[freqs < 200].sum() / total * 100), 2),
    }
    if x.shape[1] == 2:
        report["lr_correlation"] = round(float(np.corrcoef(x[:, 0], x[:, 1])[0, 1]), 3)
    return report


def seam(x: np.ndarray) -> dict:
    return C.seam_report(x, None)


def save(out: str, name: str, x: np.ndarray, entry: dict) -> dict:
    C.write_wav(os.path.join(out, "wav", f"{name}.wav"), x)
    decoded = C.encode(os.path.join(out, "wav", f"{name}.wav"), os.path.join(out, f"{name}.ogg"))
    entry.update(
        {
            "file": f"{name}.ogg",
            "channels": int(x.shape[1]),
            "duration_s": round(len(x) / RATE, 4),
            "bytes": os.path.getsize(os.path.join(out, f"{name}.ogg")),
            "decoded_length_diff": int(len(decoded)) - int(len(x)),
        }
    )
    if entry.get("loop"):
        entry["seam_after_ogg"] = seam(decoded[: len(x)])
    return entry


def limiter_loop(on_loop: np.ndarray, on_rpm: float) -> tuple[np.ndarray, str]:
    """The top on loop raised to LIMITER_RPM and gated at the fuel cut's rhythm."""
    length = int(round(len(on_loop) * on_rpm / LIMITER_RPM))
    raised = resample(on_loop, length, axis=0)
    seconds = length / RATE
    rhythm = max(1, round(LIMITER_RHYTHM_HZ * seconds)) / seconds
    phase = (np.arange(length) / RATE * rhythm) % 1.0
    cut = 10 ** (LIMITER_CUT_DB / 20)
    ramp = 0.002 * rhythm
    gate = np.where(phase < LIMITER_FIRE_SHARE, 1.0, cut)
    rising = phase < ramp
    gate[rising] = cut + (1 - cut) * 0.5 * (1 - np.cos(np.pi * phase[rising] / ramp))
    falling = (phase >= LIMITER_FIRE_SHARE) & (phase < LIMITER_FIRE_SHARE + ramp)
    gate[falling] = cut + (1 - cut) * 0.5 * (1 + np.cos(np.pi * (phase[falling] - LIMITER_FIRE_SHARE) / ramp))
    return raised * gate[:, None], f"on loop raised to {LIMITER_RPM:g} rpm, gated at {rhythm:.2f} Hz ({LIMITER_FIRE_SHARE:.0%} firing, cut {LIMITER_CUT_DB:g} dB)"


def far_loop(bank_a: dict) -> tuple[np.ndarray, str]:
    """Bank A's exterior on-load loops made seamless, brought to one length, summed and low-passed."""
    parts = [C.mono(seamless(*bank_a[name])[0])[:, None] for name in FAR_SOURCES]
    length = min(len(p) for p in parts)
    parts = [resample(p, length, axis=0) if len(p) != length else p for p in parts]
    summed = sum(p / np.sqrt(np.mean(p**2)) for p in parts)
    low = circular(butter(4, FAR_CUTOFF_HZ, "lowpass", fs=RATE, output="sos"), summed)
    return stereo(low - low.mean()), f"{', '.join(FAR_SOURCES)} summed, low-passed at {FAR_CUTOFF_HZ:g} Hz"


def render_engine(loops: list, path: list, level_rpm: float) -> np.ndarray:
    """The set's loops along an rpm and throttle path (time s, rpm, throttle), crossfaded as
    Rules/EngineSound does, at unity gain at `level_rpm` and louder with rpm as the pack is."""
    end = path[-1][0]
    t = np.arange(int(end * RATE)) / RATE
    rpm = np.interp(t, [p[0] for p in path], [p[1] for p in path])
    throttle = np.interp(t, [p[0] for p in path], [p[2] for p in path])
    out = np.zeros((len(t), 2))
    half = 2 ** (CROSSFADE_OCTAVES / 2)
    for load, gain in (("On", np.sin(throttle * np.pi / 2)), ("Off", np.cos(throttle * np.pi / 2))):
        chain = sorted((loop for loop in loops if loop["load"] in (load, "Both")), key=lambda loop: loop["rpm"])
        weights = [np.zeros(len(t)) for _ in chain]
        weights[0][rpm <= chain[0]["rpm"]] = 1
        weights[-1][rpm >= chain[-1]["rpm"]] = 1
        for i in range(len(chain) - 1):
            low, high = chain[i]["rpm"], chain[i + 1]["rpm"]
            inside = (rpm > low) & (rpm < high)
            centre = np.sqrt(low * high)
            a, b = max(centre / half, low), min(centre * half, high)
            share = np.clip(np.log(rpm[inside] / a) / np.log(b / a), 0, 1)
            weights[i][inside] = np.cos(share * np.pi / 2)
            weights[i + 1][inside] = np.sin(share * np.pi / 2)
        for loop, weight in zip(chain, weights):
            if weight.max() == 0:
                continue
            audio = loop["audio"]
            position = np.cumsum(np.clip(rpm / loop["rpm"], 0.1, 2.5)) % len(audio)
            index = np.floor(position).astype(np.int64)
            frac = (position - index)[:, None]
            played = audio[index] * (1 - frac) + audio[(index + 1) % len(audio)] * frac
            out += played * (gain * weight * loop["volume"])[:, None]
    def loudness(at):
        share = np.clip(np.log(at / QUIET_RPM) / np.log(LOUD_RPM / QUIET_RPM), 0, 1)
        return QUIET_DB + (LOUD_DB - QUIET_DB) * share

    return out * (10 ** ((loudness(rpm) - loudness(level_rpm)) / 20))[:, None]


def crank(seconds: float) -> np.ndarray:
    """A starter turning the engine: pinion whine, brush noise and the compression pulse."""
    rng = np.random.default_rng(11)
    t = np.arange(int(seconds * RATE)) / RATE
    pulse_hz = CRANK_RPM / 60 * ORDER
    pulse = 0.5 * (1 + np.sin(2 * np.pi * pulse_hz * t))
    crank_rpm = CRANK_RPM * (1 - 0.12 * pulse)
    mesh_hz = crank_rpm * STARTER_PINION_RATIO / 60 * STARTER_PINION_TEETH
    phase = 2 * np.pi * np.cumsum(mesh_hz) / RATE
    whine = sum(np.sin(k * phase) / k for k in (1, 2, 3, 4))
    brush = sosfilt(butter(2, [2000, 6000], "bandpass", fs=RATE, output="sos"), rng.standard_normal(len(t)))
    chuff = sosfilt(butter(2, [60, 220], "bandpass", fs=RATE, output="sos"), rng.standard_normal(len(t))) * pulse**3
    engage = np.exp(-t / 0.01) * sosfilt(butter(2, 1500, "highpass", fs=RATE, output="sos"), rng.standard_normal(len(t)))
    x = 0.25 * whine * (0.6 + 0.4 * pulse) + 0.08 * brush + 0.9 * chuff + 0.6 * engage
    x *= np.minimum(1, t / 0.02) * np.minimum(1, (seconds - t) / 0.05)
    return stereo(x[:, None] * 0.3)


def startup(loops: list) -> tuple[np.ndarray, dict]:
    cranking = crank(CRANK_SECONDS)
    engine = render_engine(loops, FLARE_PATH, FLARE_PATH[-1][1])
    lead = int(0.03 * RATE)
    engine[:lead] *= np.linspace(0, 1, lead)[:, None]
    x = np.concatenate([cranking, np.zeros((len(engine), 2))])
    x[len(cranking) - lead : len(cranking) - lead + len(engine)] += engine
    fade = int(STARTUP_FADE_SECONDS * RATE)
    x[-fade:] *= np.cos(np.linspace(0, np.pi / 2, fade))[:, None]
    peak_db = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
    gain_db = min(0.0, C.PEAK_CEILING_DB - peak_db)
    x *= 10 ** (gain_db / 20)
    return x, {
        "source": f"synthesised: {CRANK_SECONDS:g} s of starter cranking at {CRANK_RPM:g} rpm, then this set's loops along {FLARE_PATH}; last {STARTUP_FADE_SECONDS:g} s faded out",
        "peak_dbfs": round(20 * np.log10(np.max(np.abs(x)) + 1e-12), 2),
        "boost_vs_idle_db": round(-gain_db, 2),
    }


def one_shot(bank: dict, name: str, target: float) -> tuple[np.ndarray, dict]:
    x = C.trim(bank[name][0])
    y, lufs, peak = C.normalise(x, target, periodic=False)
    return y, {"source": f"bank B {name}", "loudness_lufs_400ms_max": round(lufs, 2), "peak_dbfs": round(peak, 2)}


def main(bank_a_path: str, bank_b_path: str, out: str, raw: bool):
    os.makedirs(os.path.join(out, "wav"), exist_ok=True)
    bank_a, bank_b = read_bank(bank_a_path), read_bank(bank_b_path)
    manifest, loops = [], []
    raw_levels = {}
    for name, sample, autopitch, load in LOOPS:
        x, cut = seamless(*bank_a[sample])
        if name == "idle":
            rpm = line_rpm(x, autopitch, IDLE_LINE_ORDERS, band=0.2)
        else:
            rpm = line_rpm(x, autopitch)
        raw_levels[name] = C.loudness(x, periodic=True)
        before = tilt(x)
        entry = {"name": name, "kind": "engine_loop", "rpm": round(rpm), "load": load, "loop": True, "source": f"bank A {sample}", "cut": cut, "raw_lufs": round(raw_levels[name], 2), "tilt_before": before}
        if not raw:
            x, side = race_shape(x, rpm, bank_b)
            entry["side"] = side
        y, lufs, peak = C.normalise(x, LOOP_LUFS, periodic=True)
        entry.update({"loudness_lufs": round(lufs, 2), "peak_dbfs": round(peak, 2), "tilt": tilt(y), "seam": seam(y)})
        loops.append({"name": name, "rpm": rpm, "load": load, "audio": stereo(y), "volume": 1.0})
        manifest.append(save(out, name, stereo(y), entry))

    # The bank's own off-load level against its on-load level at the same rpm, so an off loop
    # keeps its natural share once every file is loudness-matched.
    on = sorted((loop["rpm"], raw_levels[loop["name"]]) for loop in loops if loop["load"] == "On")
    for loop, entry in zip(loops, manifest):
        if loop["load"] == "Off":
            reference = np.interp(np.log(loop["rpm"]), [np.log(r) for r, _ in on], [lvl for _, lvl in on])
            loop["volume"] = float(10 ** ((raw_levels[loop["name"]] - reference) / 20))
            entry["volume_vs_on"] = round(loop["volume"], 3)

    top = max((loop for loop in loops if loop["load"] == "On"), key=lambda loop: loop["rpm"])
    limited, source = limiter_loop(top["audio"], top["rpm"])
    limited, lufs, peak = C.normalise(limited, LOOP_LUFS, periodic=True)
    manifest.append(save(out, "limiter", limited, {"name": "limiter", "kind": "limiter_loop", "rpm": LIMITER_RPM, "loop": True, "source": source, "loudness_lufs": round(lufs, 2), "peak_dbfs": round(peak, 2), "seam": seam(limited)}))

    far, source = far_loop(bank_a)
    far, lufs, peak = C.normalise(far, LOOP_LUFS, periodic=True)
    manifest.append(save(out, "far", far, {"name": "far", "kind": "far_loop", "rpm": None, "loop": True, "source": source, "loudness_lufs": round(lufs, 2), "peak_dbfs": round(peak, 2), "seam": seam(far)}))

    shots = []
    start, info = startup(loops)
    shots.append(({"name": "startup", "kind": "startup", "loop": False, **info}, start))
    gear, info = one_shot(bank_b, f"ferrari_458_{GEAR}", GEAR_LUFS)
    shots.append(({"name": "gear", "kind": "gear", "loop": False, **info}, stereo(gear)))
    for index, pop in enumerate(POPS, 1):
        y, info = one_shot(bank_b, f"ferrari_458_{pop}", POP_LUFS)
        shots.append(({"name": f"pop_{index}", "kind": "pop", "loop": False, **info}, stereo(y)))

    gap = np.zeros((int(C.PACK_GAP_SECONDS * RATE), 2))
    parts, cursor = [gap], len(gap)
    for entry, x in shots:
        entry["pack"] = {"file": "events.ogg", "start_s": round(cursor / RATE, 4), "end_s": round((cursor + len(x)) / RATE, 4)}
        parts += [x, gap]
        cursor += len(x) + len(gap)
    packed = np.concatenate(parts)
    manifest.append(save(out, "events", packed, {"name": "events", "kind": "pack", "loop": False, "source": "every one-shot below, played through Sound.PlaybackRegion", "peak_dbfs": round(20 * np.log10(np.max(np.abs(packed)) + 1e-12), 2)}))
    manifest += [entry for entry, _ in shots]
    for entry in manifest:
        entry["asset_id"] = None
    with open(os.path.join(out, "manifest.json"), "w") as handle:
        json.dump({"variant": "raw" if raw else "race", "files": manifest}, handle, indent=1)
    for entry in manifest:
        print(json.dumps(entry))


if __name__ == "__main__":
    arguments = [a for a in sys.argv[1:] if a != "--raw"]
    main(arguments[0], arguments[1], arguments[2], "--raw" in sys.argv[1:])
