"""
Cuts the Drive Lab DR458's engine bank and events file (Config/Cars/DR458/Audio) from Pole Position
Production's Ferrari 458 recordings in the free Sonniss GDC bundles (archive.org mirrors
sonniss-gdc-<year>-game-audio-bundle-normalized, folder "Pole Position - Ferrari 458 2013"):

  exhaust  GDC 2024 "Ferrari 458 Straight Pipes - t5 - ONBRD - RAMPS - Drive Stop Off - EXHAUST - Left - DPA4062"
  intake   GDC 2020 "ferrari_458_t8_onbrd_drive_ramps_stop_off_intake_left_DPA4062"
  start-up GDC 2019 "Ferrari_F40_LM_t5_Onbrd_Start_Fast_Drive_Various_Stop_Off_Turbo_Wastegate_DPA4061"

Both 458 takes are one-gear ramps: full throttle from about 1,100 rpm to the 9,000 rpm limiter, then
a coast down. Each take's rpm is tracked off its firing line (the exhaust's 4th order, the intake's
2nd, which is the stronger there), scored with its harmonics and followed by a Viterbi path that
penalises jumps. Every loop is cut where each ramp of its load crosses its rpm (within SPAN): each
crossing is read at the speed target / rpm, which flattens its pitch to the target, the crossings
are joined with equal-power crossfades and the whole closed into a seamless loop. The drive and
stop stretches between ramps are left out. The idle is the exhaust take's idle just before the
engine is switched off, flattened to the car's 1,000 rpm.

The bank is the exhaust with the intake under it (INTAKE_DB), mixed per loop. Where the intake has
no crossing (below 2,000 rpm) the exhaust stands alone, as it did in the owner's preview. Each mixed
loop is matched to -18 LUFS and its level relative to the others kept as its layer's volume,
normalised so the on-throttle loops sit at 1, no off-throttle loop under MIN_OFF_VOLUME. The limiter is the top on-throttle loop raised to
9,000 rpm and gated at 15 Hz. Every loop goes into one packed file, each in its own region, with
silence between.

The events file holds the start-up, the gear click (the previous events file's, unchanged) and the
wiper motor loop (Freesound 425395, Soundholder, CC BY 4.0, from its public preview). The start-up
is played at the speed that puts its settled firing line on the car's 1,000 rpm idle, its settled
stretch matched to the idle loop's loudness and its last STARTUP_FADE_SECONDS faded out.

Writes <out>/bank.ogg, <out>/events.ogg (and the WAVs they were encoded from), and manifest.json
with every region, volume, level and check. Decoding and encoding go through ffmpeg.

    python -I tools/audio/cut_dr458_gdc.py <exhaust.flac> <intake.flac> <f40.wav> <old events.ogg> <wiper.mp3> <out dir>
"""

import json
import os
import subprocess
import sys

import numpy as np
from scipy.signal import resample, resample_poly, stft

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_preview as R  # noqa: E402

RATE = 48000
SOURCE_RATE = 96000
TRACK_RATE = 12000
LUFS = -18.0
PEAK_CEILING_DB = -1.0
VORBIS_QUALITY = "6"

SPAN = 1.07
ON_TARGETS = [1500, 2250, 3000, 3750, 4500, 5250, 6000, 6750, 7500, 8250, 8800]
OFF_TARGETS = [1500, 2500, 3500, 4500, 5500, 6500, 7500, 8500]
GRAIN_XFADE = 0.06
LOOP_XFADE = 0.10
MAX_GRAINS = 6
MIN_GRAIN = 0.25
ON_SLOPE, OFF_SLOPE = 250.0, -180.0
# Off loops play at their raw level against the on loops at the same rpm, within these bounds.
OFF_VOLUME = (0.25, 1.0)

# take: (firing order tracked, line search range Hz, jump penalty, stretches left out, seconds)
TAKES = {
    "exhaust": (4.0, (55.0, 650.0), 5.0, [(99, 120), (150, 178), (243, 300)]),
    "intake": (2.0, (26.0, 330.0), 5.0, [(60, 86), (120, 150), (185, 206), (328, 400)]),
}
IDLE_SPAN = (273.9, 276.4)
IDLE_RPM = 1000
# The intake under the exhaust: the preview mixed their renders 4 dB apart after each render's own
# loudness gain (exhaust -1.3 dB, intake -0.5 dB), so -3.2 dB at matched loop loudness.
INTAKE_DB = -3.2
# The quietest an off-throttle loop plays, as the previous bank's quietest: the mix's coast at
# 3,500-4,500 rpm left the engine 5.4 dB over the wind at 166 km/h, under tests/RoadAudio.spec's 6.
MIN_OFF_VOLUME = 0.47
LIMITER_RPM = 9000
GATE_HZ = 15
PACK_GAP = 0.25

STARTUP_SPAN = (1.9, 8.0)
STARTUP_ORDER = 4
STARTUP_FADE_SECONDS = 0.8
STARTUP_SETTLED_SECONDS = 0.6
GEAR_REGION = (5.35, 5.5705)
WIPER_SPAN = (1.0, 9.0)
EVENTS_GAP = 0.5


def decode(path, rate=RATE, start=None, length=None):
    cmd = ["ffmpeg", "-v", "error"]
    if start is not None:
        cmd += ["-ss", str(start), "-t", str(length)]
    cmd += ["-i", path, "-f", "f32le", "-ac", "1", "-ar", str(rate), "-"]
    return np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout, np.float32).astype(np.float64)


def loudness(x):
    return R.loudness(np.stack([x, x], axis=1))


def loop_loudness(x):
    return loudness(np.concatenate([x, x, x]))


def track(x12, order, band, jump):
    hop = TRACK_RATE // 100
    f, t, Z = stft(x12.astype(np.float32), fs=TRACK_RATE, nperseg=2048, noverlap=2048 - hop, boundary=None)
    mag = np.log(np.abs(Z).astype(np.float32) + 1e-6)
    del Z
    grid = np.exp(np.linspace(np.log(band[0]), np.log(band[1]), 480))

    def at(freqs):
        return np.stack([np.interp(freqs, f, mag[:, k]) for k in range(mag.shape[1])], axis=1)

    score = at(grid) + 0.6 * at(2 * grid) + 0.4 * at(3 * grid) - 0.5 * at(0.75 * grid)
    score -= score.mean(axis=0, keepdims=True)
    n_bins, n_frames = score.shape
    step = np.log(grid[1] / grid[0])
    cost = np.abs(np.arange(n_bins)[:, None] - np.arange(n_bins)[None, :]) * step * 100 * jump
    back = np.zeros((n_bins, n_frames), dtype=np.int32)
    acc = score[:, 0].copy()
    for k in range(1, n_frames):
        cand = acc[None, :] - cost
        back[:, k] = np.argmax(cand, axis=1)
        acc = cand[np.arange(n_bins), back[:, k]] + score[:, k]
    path = np.zeros(n_frames, dtype=np.int32)
    path[-1] = int(np.argmax(acc))
    for k in range(n_frames - 1, 0, -1):
        path[k - 1] = back[path[k], k]
    rpm = grid[path] * 60 / order
    k = 31
    smooth = np.convolve(np.pad(rpm, k // 2, mode="edge"), np.ones(k) / k, mode="valid")
    return t, smooth


def flatten(x96, t, rs, a, b, target):
    """The source from a to b seconds, read at speed target / rpm so its pitch holds the target."""
    pos, p = [], a
    while p < b:
        pos.append(p)
        p += (1 / 2000) * target / np.interp(p, t, rs)
    pos = np.array(pos)
    n = int(len(pos) * SOURCE_RATE / 2000)
    fine = np.interp(np.arange(n) / SOURCE_RATE, np.arange(len(pos)) / 2000, pos) * SOURCE_RATE
    i = np.clip(np.floor(fine).astype(np.int64), 0, len(x96) - 2)
    frac = fine - i
    return resample_poly(x96[i] * (1 - frac) + x96[i + 1] * frac, 1, 2)


def join(a, b, seconds):
    n = int(seconds * RATE)
    w = np.linspace(0, np.pi / 2, n)
    return np.concatenate([a[:-n], a[-n:] * np.cos(w) + b[:n] * np.sin(w), b[n:]])


def close(y, seconds):
    n = int(seconds * RATE)
    w = np.linspace(0, np.pi / 2, n)
    return np.concatenate([y[:n] * np.sin(w) + y[-n:] * np.cos(w), y[n:-n]])


def runs(mask):
    out, i = [], 0
    while i < len(mask):
        if mask[i]:
            j = i
            while j < len(mask) and mask[j]:
                j += 1
            out.append((i, j))
            i = j
        else:
            i += 1
    return out


def cut_take(path, name):
    order, band, jump, excluded = TAKES[name]
    x96 = decode(path, SOURCE_RATE)
    t, rs = track(decode(path, TRACK_RATE), order, band, jump)
    slope = np.gradient(rs, t)
    guard = np.zeros_like(t, dtype=bool)
    for i in np.where((slope[:-1] > 0) & (slope[1:] <= 0) & (rs[:-1] > 6000))[0]:
        guard |= (t > t[i] - 0.15) & (t < t[i] + 0.6)
    out_of = np.zeros_like(t, dtype=bool)
    for a, b in excluded:
        out_of |= (t >= a) & (t <= b)
    loads = {"on": (slope > ON_SLOPE) & ~guard & ~out_of, "off": (slope < OFF_SLOPE) & ~guard & ~out_of}
    loops = {}
    for load, targets in (("on", ON_TARGETS), ("off", OFF_TARGETS)):
        for target in targets:
            within = loads[load] & (rs >= target / SPAN) & (rs <= target * SPAN)
            spans = [(t[i0], t[i1 - 1]) for i0, i1 in runs(within) if t[i1 - 1] - t[i0] >= MIN_GRAIN][:MAX_GRAINS]
            if len(spans) < 2:
                continue
            pieces = [flatten(x96, t, rs, a, b, target) for a, b in spans]
            y = pieces[0]
            for p in pieces[1:]:
                y = join(y, p, GRAIN_XFADE)
            y = close(y, LOOP_XFADE)
            raw = loop_loudness(y)
            loops[(load, target)] = {"audio": y * 10 ** ((LUFS - raw) / 20), "raw_lu": raw, "spans": spans}
    idle = None
    if name == "exhaust":
        y = close(flatten(x96, t, rs, IDLE_SPAN[0], IDLE_SPAN[1], IDLE_RPM), 0.12)
        idle = {"audio": y * 10 ** ((LUFS - loop_loudness(y)) / 20), "raw_lu": loop_loudness(y), "spans": [IDLE_SPAN]}
    return loops, idle


def off_volumes(loops):
    on = sorted((rpm, v["raw_lu"]) for (load, rpm), v in loops.items() if load == "on")
    rpms, lus = np.array([r for r, _ in on], float), np.array([lu for _, lu in on], float)
    out = {}
    for (load, rpm), v in loops.items():
        ratio = 1.0 if load == "on" else 10 ** ((v["raw_lu"] - float(np.interp(rpm, rpms, lus))) / 20)
        out[(load, rpm)] = float(np.clip(ratio, *OFF_VOLUME)) if load == "off" else 1.0
    return out


def fit(y, n):
    """A seamless loop y laid over n samples, closed again at n."""
    m = int(LOOP_XFADE * RATE)
    tiled = np.tile(y, (n + m) // len(y) + 2)[: n + m]
    w = np.linspace(0, np.pi / 2, m)
    return np.concatenate([tiled[:m] * np.sin(w) + tiled[n : n + m] * np.cos(w), tiled[m:n]])


def line_rpm(y, guess, order=4):
    X = np.abs(np.fft.rfft(y * np.hanning(len(y))))
    f = np.fft.rfftfreq(len(y), 1 / RATE)
    m = (f > guess * order / 60 / 1.12) & (f < guess * order / 60 * 1.12)
    return float(f[m][np.argmax(X[m])] * 60 / order)


def seam(y):
    step = np.abs(np.diff(y))
    return round(float(abs(y[0] - y[-1]) / np.percentile(step, 99.9)), 3)


def write(out, name, y):
    wav = os.path.join(out, "wav", name + ".wav")
    ogg = os.path.join(out, name + ".ogg")
    os.makedirs(os.path.dirname(wav), exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f64le", "-ar", str(RATE), "-ac", "1", "-i", "-", "-c:a", "pcm_s24le", wav],
                   input=y.astype(np.float64).tobytes(), check=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", VORBIS_QUALITY, ogg], check=True)
    return decode(ogg), os.path.getsize(ogg)


def startup(path):
    x = decode(path, RATE, STARTUP_SPAN[0], STARTUP_SPAN[1] - STARTUP_SPAN[0])
    x -= x.mean()
    tail = x[-int(1.2 * RATE):]
    X = np.abs(np.fft.rfft(tail * np.hanning(len(tail))))
    f = np.fft.rfftfreq(len(tail), 1 / RATE)
    m = (f > 600 * STARTUP_ORDER / 60) & (f < 2200 * STARTUP_ORDER / 60)
    settled = float(f[m][np.argmax(X[m])] * 60 / STARTUP_ORDER)
    speed = IDLE_RPM / settled
    y = resample(x, int(len(x) / speed))
    fade_in, fade_out = int(0.005 * RATE), int(STARTUP_FADE_SECONDS * RATE)
    y[:fade_in] *= np.linspace(0, 1, fade_in)
    stretch = y[-fade_out - int(STARTUP_SETTLED_SECONDS * RATE): -fade_out]
    y[-fade_out:] *= np.cos(np.linspace(0, np.pi / 2, fade_out))
    level_db = LUFS - loudness(stretch)
    peak_db = 20 * np.log10(np.abs(y).max() + 1e-12)
    gain_db = min(level_db, PEAK_CEILING_DB - peak_db)
    return y * 10 ** (gain_db / 20), {"settled_rpm": round(settled), "speed": round(speed, 4), "gain_db": round(gain_db, 2),
                                      "boost_vs_idle_db": round(level_db - gain_db, 2)}


def wiper_loop(path):
    x = decode(path, RATE, WIPER_SPAN[0], WIPER_SPAN[1] - WIPER_SPAN[0])
    env = np.sqrt(np.convolve(x ** 2, np.ones(480) / 480, mode="same"))[::480]
    env -= env.mean()
    ac = np.correlate(env, env, mode="full")[len(env) - 1:]
    lo, hi = int(0.6 * 100), int(2.5 * 100)
    period = (lo + int(np.argmax(ac[lo:hi]))) / 100
    cycles = max(1, int((len(x) / RATE - LOOP_XFADE) // period))
    n = int(cycles * period * RATE)
    y = close(x[: n + int(LOOP_XFADE * RATE)], LOOP_XFADE)
    return y * 10 ** ((LUFS - loop_loudness(y)) / 20), {"period_s": period, "cycles": cycles}


def main(exhaust_path, intake_path, f40_path, old_events_path, wiper_path, out):
    os.makedirs(out, exist_ok=True)
    exhaust, idle = cut_take(exhaust_path, "exhaust")
    intake, _ = cut_take(intake_path, "intake")
    v_exhaust, v_intake = off_volumes(exhaust), off_volumes(intake)
    k = 10 ** (INTAKE_DB / 20)
    mixed, manifest_loops = {}, []
    for key in sorted(exhaust, key=lambda kk: (kk[0] != "on", kk[1])):
        e = exhaust[key]["audio"] * v_exhaust[key]
        if key in intake:
            i = intake[key]["audio"] * v_intake[key]
        else:
            i = exhaust[key]["audio"] * v_exhaust[key]
        y = e + k * fit(i, len(e))
        raw = loop_loudness(y)
        mixed[key] = (y * 10 ** ((LUFS - raw) / 20), raw)
    idle_y = idle["audio"] * (1 + k)
    idle_raw = loop_loudness(idle_y)
    reference = float(np.median([raw for (load, _), (_, raw) in mixed.items() if load == "on"]))

    def volume(raw, floor=0.0):
        return round(max(10 ** ((raw - reference) / 20), floor), 4)

    loops = [("idle", 1000, "Both", idle_y * 10 ** ((LUFS - idle_raw) / 20), volume(idle_raw))]
    for (load, rpm), (y, raw) in sorted(mixed.items(), key=lambda kv: (kv[0][0] != "on", kv[0][1])):
        floor = MIN_OFF_VOLUME if load == "off" else 0.0
        loops.append((f"{load}_{rpm}", rpm, "On" if load == "on" else "Off", y, volume(raw, floor)))
    top_key = max(rpm for (load, rpm) in mixed if load == "on")
    top, top_raw = mixed[("on", top_key)]
    lim = resample(top, int(len(top) * top_key / LIMITER_RPM))
    period = RATE // GATE_HZ
    lim = lim[: (len(lim) // period) * period]
    phase = (np.arange(len(lim)) % period) / period
    lim = lim * (np.clip(np.minimum(phase / 0.08, (0.62 - phase) / 0.08), 0, 1) * 0.85 + 0.15)
    loops.append(("limiter", LIMITER_RPM, "Limiter", lim, volume(top_raw)))

    gap = np.zeros(int(PACK_GAP * RATE))
    parts, at, entries = [], 0, []
    for name, rpm, load, y, vol in loops:
        entries.append({"name": name, "rpm": rpm, "load": load, "volume": vol, "from_sample": at, "to_sample": at + len(y),
                        "seam": seam(y), "line_rpm": round(line_rpm(y, rpm)) if load != "Limiter" else None})
        parts += [y, gap]
        at += len(y) + len(gap)
    packed = np.concatenate(parts)
    peak = 20 * np.log10(np.abs(packed).max())
    assert peak <= PEAK_CEILING_DB, f"the packed bank peaks at {peak:.2f} dBFS"
    decoded, bank_bytes = write(out, "bank", packed)
    for e in entries:
        a, b = e["from_sample"], e["to_sample"]
        e["region"] = {"from": round(a / RATE, 6), "to": round(b / RATE, 6)}
        e["seam_after_ogg"] = seam(decoded[a:b])

    start, start_info = startup(f40_path)
    old = decode(old_events_path)
    gear = old[int(round(GEAR_REGION[0] * RATE)): int(round(GEAR_REGION[1] * RATE))]
    wiper, wiper_info = wiper_loop(wiper_path)
    g = np.zeros(int(EVENTS_GAP * RATE))
    events = np.concatenate([start, g, gear, g, wiper, g])
    regions = {
        "startup": (0, len(start)),
        "gear": (len(start) + len(g), len(start) + len(g) + len(gear)),
        "wiper": (len(start) + 2 * len(g) + len(gear), len(start) + 2 * len(g) + len(gear) + len(wiper)),
    }
    decoded_events, events_bytes = write(out, "events", events)
    manifest = {
        "bank": {"file": "bank.ogg", "seconds": round(len(packed) / RATE, 3), "bytes": bank_bytes, "peak_dbfs": round(peak, 2),
                 "reference_raw_lu": round(reference, 2), "intake_db": INTAKE_DB, "loops": entries,
                 "spans": {f"{load}_{rpm}": [[round(a, 2), round(b, 2)] for a, b in exhaust[(load, rpm)]["spans"]] for (load, rpm) in exhaust}},
        "events": {"file": "events.ogg", "seconds": round(len(events) / RATE, 3), "bytes": events_bytes,
                   "regions": {name: {"from": round(a / RATE, 6), "to": round(b / RATE, 6)} for name, (a, b) in regions.items()},
                   "startup": start_info, "wiper": dict(wiper_info, seam_after_ogg=seam(decoded_events[regions["wiper"][0]: regions["wiper"][1]])),
                   "startup_hand_over_s": round((len(start) - STARTUP_FADE_SECONDS * RATE) / RATE, 4)},
        "sources": {"exhaust": os.path.basename(exhaust_path), "intake": os.path.basename(intake_path), "startup": os.path.basename(f40_path),
                    "gear": "the previous DR458 events file, %g-%g s" % GEAR_REGION, "wiper": os.path.basename(wiper_path)},
    }
    json.dump(manifest, open(os.path.join(out, "manifest.json"), "w"), indent=1)
    for e in entries:
        print(f"{e['name']:>9} rpm {e['rpm']:>5} vol {e['volume']:.3f} line {e['line_rpm']} region {e['region']['from']:.3f}-{e['region']['to']:.3f} seam {e['seam_after_ogg']}")
    print("bank", manifest["bank"]["seconds"], "s", bank_bytes, "bytes; events", manifest["events"]["seconds"], "s", events_bytes, "bytes")
    print("startup", start_info, "wiper", wiper_info)


if __name__ == "__main__":
    main(*sys.argv[1:7])
