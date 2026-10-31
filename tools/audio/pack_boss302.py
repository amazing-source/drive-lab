"""
Packs the Boss 302's sound set into one engine bank and one events file, as the DR458's is packed:
every loop in its own region of the bank, every one-shot in its own region of the events file, with
silence between them and after the last, so an encoder that trims a file's end only trims silence
(on its own, the iRacer5 cut's on_1636.ogg decoded 128 samples short and clicked at its seam).

  engine   the iRacer5 HPE 650 bank as cut by tools/audio/cut_boss302.py (iracer5): the idle, eight
           on-throttle loops, three off-throttle loops and the limiter. Not its supercharger whine nor
           its turbo sounds: the Laguna Seca is not supercharged.
  far      its exterior on-throttle loops from 4,050 to 7,113 rpm brought to one length, summed and
           low-passed, as tools/audio/cut_dr458.py makes a far loop.
  TracKey  a lumpy cold idle, a 1971 Camaro Z28's (Pole Position, Sonniss GDC 2016), cut as a loop for
           the TracKey mode's idle, unused unless the owner takes it, so taking it needs no upload.
  events   the start-up, "Starting of Ford V8 5 Liter engine" (Freesound 455925 by noiseloop, CC BY
           3.0, from its preview), as recorded, its settled end matched to the loops' level and faded
           out over the hand-over; the A3DR mod's gear sounds, pops and backfires as cut by
           cut_boss302.py (a3dr).

Each region is written to the microsecond, its start rounded up and its end down, and checked on the
decoded OGG: the decode reaches past its end, lines up with the WAV with no lag, and each loop's seam
jump stays under SEAM_LIMIT times the loop's own 99.9th-percentile step. A failed check stops the
pack. Writes <out>/bank.ogg, <out>/events.ogg, their WAVs, manifest.json, and candidate.json (the
engine set with its regions, for games/drive-lab/tools/audio_sweep.luau and render_strip.py).

    python -I tools/audio/pack_boss302.py <iracer5 cut dir> <a3dr cut dir> <startup source> <z28 take> <out dir>
    python -I tools/audio/pack_boss302.py --check <loop.wav> <loop.ogg>
"""

import json
import math
import os
import subprocess
import sys

import numpy as np
from scipy.signal import butter, resample

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cut_boss302 as B  # noqa: E402
import cut_dr458 as D  # noqa: E402
import cut_loops as C  # noqa: E402

RATE = C.RATE
LOOP_LUFS = -18.0
BANK_GAP = 0.25
EVENTS_GAP = 0.5
SEAM_LIMIT = 1.5
OFF_VOLUME = 0.6
IDLE_CROSSOVER_RPM = 1250
STARTUP_SPAN = (0.3, 5.6)
# The Z28 take's cold idle after its start, before the first blip.
TRACKEY_SPAN = (15.0, 18.0)
TRACKEY_GUESS_RPM = 1190
FAR_SOURCES = ["on_4418", "on_5520", "on_6623", "on_7734"]
FAR_CUTOFF_HZ = 2500.0
GEARS = {"gearUp": "gearup", "gearDown": "geardnEXT", "grind": "missgear"}
POPS = ["C7_pop", "C7_pop23", "C7_back_1", "C7_back_2", "C7_back_3", "backfireEXT_8", "backfireEXT_2", "backfireEXT_9"]
LAG_SEARCH = 64


def region(a: int, b: int) -> dict:
    return {"from": math.ceil(a / RATE * 1e6) / 1e6, "to": math.floor(b / RATE * 1e6) / 1e6}


def decode_span(path: str, start: float, end: float) -> np.ndarray:
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-ss", str(start), "-t", str(end - start), "-i", path, "-f", "f64le", "-ac", "2", "-ar", str(RATE), "-"],
        check=True,
        capture_output=True,
    ).stdout
    return np.frombuffer(raw, np.float64).reshape(-1, 2).copy()


def check(wav: np.ndarray, decoded: np.ndarray, a: int, b: int, loop: bool) -> dict:
    """How the decoded OGG holds the WAV's samples a..b."""
    report = {"decoded_reaches_samples": int(len(decoded) - b)}
    if len(decoded) < b:
        return report
    w, d = C.mono(wav[a:b]), C.mono(decoded[a:b])
    core = slice(LAG_SEARCH, len(w) - LAG_SEARCH)
    lags = list(range(-LAG_SEARCH, LAG_SEARCH + 1))
    scores = [float(np.dot(w[core], d[LAG_SEARCH + k : len(d) - LAG_SEARCH + k])) for k in lags]
    report["lag_samples"] = lags[int(np.argmax(scores))]
    report["snr_db"] = round(float(10 * np.log10(np.sum(w**2) / (np.sum((w - d) ** 2) + 1e-20))), 1)
    if loop:
        report["seam_after_ogg"] = C.seam_report(decoded[a:b], None)
    return report


def failures(name: str, report: dict) -> list:
    out = []
    if report["decoded_reaches_samples"] < 0:
        out.append(f"{name}: the decode ends {-report['decoded_reaches_samples']} samples before the region does")
    elif report["lag_samples"] != 0:
        out.append(f"{name}: the decode lags the WAV by {report['lag_samples']} samples")
    elif "seam_after_ogg" in report and report["seam_after_ogg"]["jump_vs_p999"] > SEAM_LIMIT:
        out.append(f"{name}: seam jump {report['seam_after_ogg']['jump_vs_p999']} x its p99.9 step after the OGG")
    return out


def write(out: str, name: str, x: np.ndarray) -> tuple[np.ndarray, np.ndarray, int]:
    """The WAV as written (16-bit, dithered), its OGG decoded, and the OGG's size."""
    wav = os.path.join(out, "wav", f"{name}.wav")
    C.write_wav(wav, x)
    decoded = C.encode(wav, os.path.join(out, f"{name}.ogg"))
    return C.read(wav), decoded, os.path.getsize(os.path.join(out, f"{name}.ogg"))


def pack(items: list, gap_seconds: float) -> tuple[np.ndarray, list]:
    gap = np.zeros((int(gap_seconds * RATE), 2))
    parts, spans, at = [], [], 0
    for x in items:
        parts += [x, gap]
        spans.append((at, at + len(x)))
        at += len(x) + len(gap)
    return np.concatenate(parts), spans


def far_loop(iracer: str) -> tuple[np.ndarray, str]:
    parts = [C.mono(C.read(os.path.join(iracer, "wav", f"{name}.wav")))[:, None] for name in FAR_SOURCES]
    length = min(len(p) for p in parts)
    parts = [resample(p, length, axis=0) if len(p) != length else p for p in parts]
    summed = sum(p / np.sqrt(np.mean(p**2)) for p in parts)
    low = D.circular(butter(4, FAR_CUTOFF_HZ, "lowpass", fs=RATE, output="sos"), summed)
    y, _, _ = C.normalise(D.stereo(low - low.mean()), LOOP_LUFS, periodic=True)
    return y, f"{', '.join(FAR_SOURCES)} brought to one length, summed, low-passed at {FAR_CUTOFF_HZ:g} Hz"


def trackey_idle(path: str) -> tuple[np.ndarray, dict]:
    x = decode_span(path, *TRACKEY_SPAN)
    loop, cut = D.seamless(x, len(x))
    rpm = D.line_rpm(loop, TRACKEY_GUESS_RPM, orders=(4.0,), band=0.15)
    y, lufs, peak = C.normalise(loop, LOOP_LUFS, periodic=True)
    return y, {"source": f"{os.path.basename(path)} {TRACKEY_SPAN[0]:g}-{TRACKEY_SPAN[1]:g} s", "rpm": round(rpm), "cut": cut,
               "lope": B.lope(y, rpm), "loudness_lufs": round(lufs, 2), "peak_dbfs": round(peak, 2)}


def main(iracer: str, a3dr: str, startup_path: str, z28_path: str, out: str):
    os.makedirs(os.path.join(out, "wav"), exist_ok=True)
    cut = {f["name"]: f for f in json.load(open(os.path.join(iracer, "manifest.json")))["files"]}
    loops = []
    for f in cut.values():
        if f["kind"] == "engine_loop":
            loops.append(f)
    loops.sort(key=lambda f: ({"Both": 0, "On": 1, "Off": 2}[f["load"]], f["rpm"]))
    entries, items = [], []
    for f in loops:
        name = {"Both": "Idle", "On": f"On{f['rpm']}", "Off": f"Off{f['rpm']}"}[f["load"]]
        volume = OFF_VOLUME if f["load"] == "Off" else 1.0
        entries.append({"name": name, "kind": "engine_loop", "rpm": f["rpm"], "load": f["load"], "volume": volume, "source": f["source"]})
        items.append(C.read(os.path.join(iracer, "wav", f"{f['name']}.wav")))
    entries.append({"name": "Limiter", "kind": "limiter", "rpm": cut["limiter"]["rpm"], "volume": 1.0, "source": cut["limiter"]["source"]})
    items.append(C.read(os.path.join(iracer, "wav", "limiter.wav")))
    far, far_source = far_loop(iracer)
    entries.append({"name": "Far", "kind": "far_loop", "volume": 1.0, "source": far_source})
    items.append(far)
    trackey, trackey_info = trackey_idle(z28_path)
    entries.append(dict({"name": "TracKeyIdle", "kind": "engine_loop", "load": "Both", "volume": 1.0, "unused_until_chosen": True}, **trackey_info))
    items.append(trackey)

    bank, spans = pack(items, BANK_GAP)
    wav, decoded, bank_bytes = write(out, "bank", bank)
    problems = []
    for e, (a, b) in zip(entries, spans):
        e["region"] = region(a, b)
        e["check"] = check(wav, decoded, a, b, loop=True)
        problems += failures(e["name"], e["check"])

    a3dr_files = {f["name"]: f for f in json.load(open(os.path.join(a3dr, "manifest.json")))["files"]}
    a3dr_events = C.read(os.path.join(a3dr, "wav", "events.wav"))
    a3dr_regions = a3dr_files["events"]["regions"]

    def a3dr_piece(sample: str) -> np.ndarray:
        r = a3dr_regions[sample]["region"]
        return a3dr_events[int(round(r["from"] * RATE)) : int(round(r["to"] * RATE))]

    start, start_info = D.startup(startup_path, *STARTUP_SPAN)
    names = ["startup"] + list(GEARS) + [f"pop{n}" for n in range(1, len(POPS) + 1)]
    sources = [os.path.basename(startup_path)] + list(GEARS.values()) + POPS
    events, event_spans = pack([start] + [a3dr_piece(s) for s in list(GEARS.values()) + POPS], EVENTS_GAP)
    events_wav, events_decoded, events_bytes = write(out, "events", events)
    event_regions = {}
    for name, source, (a, b) in zip(names, sources, event_spans):
        report = check(events_wav, events_decoded, a, b, loop=False)
        problems += failures(name, report)
        event_regions[name] = {"source": source, "region": region(a, b), "check": report}
    flare = int(np.argmax(np.abs(C.mono(start))))
    start_info.update({"hand_over_s": round((len(start) - D.STARTUP_FADE_SECONDS * RATE) / RATE, 4), "loudest_sample_s": round(flare / RATE, 4)})

    manifest = {
        "bank": {"file": "bank.ogg", "seconds": round(len(bank) / RATE, 3), "bytes": bank_bytes,
                 "peak_dbfs": round(float(20 * np.log10(np.abs(bank).max())), 2), "regions": entries},
        "events": {"file": "events.ogg", "seconds": round(len(events) / RATE, 3), "bytes": events_bytes,
                   "regions": event_regions, "startup": start_info},
        "sources": {"engine": "iRacer5 HPE 650 bank (a3dr_boss302_laguna_seca_650.bank, 2017) via cut_boss302.py iracer5",
                    "one_shots": "A3DR Boss 302 Laguna Seca bank via cut_boss302.py a3dr",
                    "startup": "Freesound 455925, noiseloop, CC BY 3.0, preview", "trackey_idle": os.path.basename(z28_path)},
        "checks": {"seam_limit": SEAM_LIMIT, "problems": problems},
    }
    json.dump(manifest, open(os.path.join(out, "manifest.json"), "w"), indent=1)

    layers = [e for e in entries if e["kind"] == "engine_loop" and not e.get("unused_until_chosen")]
    limiter = next(e for e in entries if e["kind"] == "limiter")
    candidate = {
        "pack": {
            "engineLayers": [dict({"rpm": e["rpm"], "load": e["load"], "volume": e["volume"]},
                                  **({"crossoverRpm": IDLE_CROSSOVER_RPM} if e["load"] == "Both" else {})) for e in layers],
            "limiter": {"rpm": limiter["rpm"], "volume": 1, "onDuck": 0.3, "halfLife": 0.03},
        },
        "files": {"layers": ["bank.ogg"] * len(layers), "limiter": "bank.ogg", "events": "events.ogg"},
        "regions": {"layers": [e["region"] for e in layers], "limiter": limiter["region"]},
    }
    json.dump(candidate, open(os.path.join(out, "candidate.json"), "w"), indent=1)

    for e in entries:
        c = e["check"]
        print("%-12s %-6s region %9.6f-%9.6f  decode +%d samples, lag %d, SNR %.1f dB, seam %.3f" % (
            e["name"], e.get("load", e["kind"])[:6], e["region"]["from"], e["region"]["to"], c["decoded_reaches_samples"],
            c["lag_samples"], c["snr_db"], c["seam_after_ogg"]["jump_vs_p999"]))
    for name, r in event_regions.items():
        print("%-12s %-14s region %9.6f-%9.6f  lag %d, SNR %.1f dB" % (name, r["source"][:14], r["region"]["from"], r["region"]["to"],
                                                                      r["check"]["lag_samples"], r["check"]["snr_db"]))
    print("bank %.3f s %d bytes; events %.3f s %d bytes; start-up %s" % (len(bank) / RATE, bank_bytes, len(events) / RATE, events_bytes,
                                                                          json.dumps(start_info)))
    print("TracKey idle:", json.dumps({k: trackey_info[k] for k in ("rpm", "lope")}))
    if problems:
        sys.exit("pack checks failed:\n  " + "\n  ".join(problems))


def check_file(wav_path: str, ogg_path: str):
    """The same check on one looping file and its OGG."""
    wav = C.read(wav_path)
    report = check(wav, D.stereo(D.decode(ogg_path)) if wav.shape[1] == 2 else D.decode(ogg_path)[:, :1], 0, len(wav), loop=True)
    print(json.dumps(report))
    problems = failures(os.path.basename(ogg_path), report)
    if problems:
        sys.exit("check failed:\n  " + "\n  ".join(problems))


if __name__ == "__main__":
    if sys.argv[1] == "--check":
        check_file(sys.argv[2], sys.argv[3])
    else:
        main(*sys.argv[1:6])
