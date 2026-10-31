"""
Cuts Drive Lab's tyre sounds and packs each set into one file, so a set costs one audio upload:
a squeal loop (a tyre at the edge of grip: tonal) and a skid loop (a full slide or a lock-up:
broad and rough). Config/TyreAudio plays each through a LoopRegion; the regions are in
manifest.json, one per pack.

    python -I tools/audio/cut_tyres.py <out dir> <sources dir> [<sources dir> ...]

Two packs, so the owner can choose by ear without another upload, and so one moderation decision
cannot silence both:

- tyres_ac: Assetto Corsa's own pair. Every AC car bank built on Kunos's SDK template holds
  skid_ext_mono (a squeal: lines near 980 Hz and 1.9 kHz) and Skid (a skid: a rough band from
  0.6 to 3 kHz), byte-identical in every mod bank checked. Extract them from any such bank with
  tools/assets/fsb5_extract.py and name them ac_skid_ext_mono.wav and ac_Skid.wav. Kunos cut both
  to loop: their level and spectrum change less at the seam than anywhere else, so they are used
  whole, declipped, resampled as loops and loudness-matched. The squeal's waveform kinks at the
  wrap (click_report), so its seam is repaired (repair_seam).
- tyres_real: real recordings, both CC0 Freesound HQ previews, saved as freesound_<id>.ogg.
  The squeal is 71739 (audible-edge, a 1996 Chrysler LHS circling the microphone), its
  steadiest 4.6 s; the skid is 628044 (monosfera, a drift with the tyres burning), its
  steadiest 4.1 s, high-passed at 800 Hz to remove the car's engine, so the game's engine is
  the only engine heard. Each section's start is folded over its end, as cut_weather.py does.

Every loop is matched to -20 LUFS, as the road pack's loops are, so the volumes in config are
the balance. Each pack is written with two identical channels, as every earlier upload is, so
the loudness measured here is the one measured on the engine and road files. Each loop's seam is
measured after OGG decoding, and the run fails if one is more click-like than CLICK_LIMIT.
Decoding and encoding go through ffmpeg.
"""

import json
import os
import subprocess
import sys

import numpy as np
from scipy.linalg import solve_toeplitz
from scipy.signal import butter, lfilter, resample, sosfilt

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cut_weather import (  # noqa: E402
    GUARD_SECONDS,
    RATE,
    declip,
    find,
    fold,
    high_pass,
    normalise_loop,
    probe,
    read,
    seam_report,
    write_wav,
)

FOLD_SECONDS = 0.5
# A LoopRegion wraps from the loop's encoded end to its separately encoded start. At the
# weather pack's quality 5 the two copies' coding errors differ enough to tick on the skids,
# whose high end is quiet; at 10 every seam passes CLICK_LIMIT.
VORBIS_QUALITY = "10"
REPAIR_OVERLAP_MS = 10.0
REPAIR_SEARCH_MS = 40.0
# A loop fails when its seam is more click-like than this share of its own loudest 0.1 % of
# moments (click_report's seam_vs_p999), measured after OGG decoding.
CLICK_LIMIT = 1.0

# A whole-file loop: (name, source, repair the seam). A section: (name, source, start s, end s,
# high-pass Hz).
PACKS = {
    "tyres_ac": [
        # Kunos's squeal kinks at its wrap (click_report); the skid does not.
        ("squeal", "ac_skid_ext_mono.wav", True),
        ("skid", "ac_Skid.wav", False),
    ],
    "tyres_real": [
        ("squeal", "freesound_71739.ogg", 5.6, 10.2, 500.0),
        ("skid", "freesound_628044.ogg", 6.1, 10.2, 800.0),
    ],
}


def save(out: str, name: str, x: np.ndarray) -> np.ndarray:
    """<out>/<name>.ogg (and wav/<name>.wav, its source); returns the OGG as decoded."""
    wav_path = os.path.join(out, "wav", f"{name}.wav")
    ogg_path = os.path.join(out, f"{name}.ogg")
    write_wav(wav_path, x)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav_path, "-c:a", "libvorbis", "-q:a", VORBIS_QUALITY, ogg_path], check=True)
    decoded_path = os.path.join(out, "wav", f"{name}.decoded.wav")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", ogg_path, decoded_path], check=True)
    decoded = read(decoded_path)
    os.remove(decoded_path)
    return decoded


def click_report(loop: np.ndarray, rate: int = RATE, order: int = 32, window_ms: float = 2.0) -> dict:
    """How click-like the wrap from the loop's end to its start is.

    seam_report's 100 and 250 ms windows cannot see a waveform break inside a squeal. A break is
    what a linear predictor cannot foresee, so this measures the predictor's residual in 2 ms
    windows: the seam's against every other moment's, wrapped.
    """
    m = loop.mean(axis=1)
    spectrum = np.fft.rfft(m, 2 * len(m))
    r = np.fft.irfft(np.abs(spectrum) ** 2)[: order + 1]
    a = solve_toeplitz(r[:order], r[1 : order + 1])
    half = len(m) // 2
    wrapped = np.roll(m, half)
    residual = lfilter(np.r_[1, -a], [1], np.concatenate([wrapped[-4 * order :], wrapped]))[4 * order :]
    w = int(window_ms / 1000 * rate)
    energy = np.convolve(residual**2, np.ones(w) / w, "same")
    at_seam = energy[half - w : half + w].max()
    elsewhere = np.ones(len(energy), bool)
    elsewhere[half - 3 * w : half + 3 * w] = False
    return {
        "seam_vs_p999": round(float(at_seam / np.percentile(energy[elsewhere], 99.9)), 2),
        "seam_rank_pct": round(float(np.mean(energy[elsewhere] < at_seam) * 100), 3),
    }


def read_native(path: str) -> np.ndarray:
    """A whole file at its own rate, as float stereo (mono doubled)."""
    rate, channels = probe(path)
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-"], check=True, capture_output=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).reshape(-1, channels).astype(np.float64)
    return np.repeat(x, 2, axis=1) if channels == 1 else x


def resample_loop(x: np.ndarray, rate: int) -> np.ndarray:
    """Resamples a loop as a loop: by FFT, which treats the signal as periodic, to a whole number
    of samples. Polyphase filtering would treat its ends as silence and click at the seam."""
    if rate == RATE:
        return x
    return resample(x, int(round(len(x) * RATE / rate)), axis=0)


def repair_seam(x: np.ndarray) -> tuple[np.ndarray, dict]:
    """Ends the loop where its audio best continues into its first REPAIR_OVERLAP_MS (normalised
    correlation, searched over its last REPAIR_SEARCH_MS), and crossfades that continuation into
    its start: the wrap then joins two neighbouring samples, and the fade mixes two takes that
    are in phase."""
    overlap = int(REPAIR_OVERLAP_MS / 1000 * RATE)
    span = int(REPAIR_SEARCH_MS / 1000 * RATE)
    m = x.mean(axis=1)
    head = m[:overlap]
    best, end = -2.0, len(m) - overlap
    for candidate in range(len(m) - overlap - span, len(m) - overlap + 1):
        tail = m[candidate : candidate + overlap]
        match = float(np.dot(tail, head) / (np.linalg.norm(tail) * np.linalg.norm(head) + 1e-12))
        if match > best:
            best, end = match, candidate
    fade = np.linspace(0.0, 1.0, overlap)[:, None]
    y = x[:end].copy()
    y[:overlap] = x[:overlap] * fade + x[end : end + overlap] * (1 - fade)
    return y, {"shortened_ms": round((len(x) - end) / RATE * 1000, 2), "match": round(best, 3)}


def whole(sources: list[str], name: str, source: str, repair: bool = False) -> tuple[np.ndarray, dict]:
    path = find(sources, source)
    rate, _ = probe(path)
    x = read_native(path)
    entry = {"name": name, "kind": "loop", "source": f"{source} whole ({len(x) / rate:.3f} s at {rate} Hz)"}
    entry["seam_source"] = seam_report(resample_loop(x, rate))
    entry["click_source"] = click_report(x, rate)
    x, restored = declip(x)
    entry["declipped_samples"] = restored
    x = resample_loop(x, rate)
    if repair:
        x, entry["seam_repair"] = repair_seam(x)
    x = x - x.mean(axis=0)
    x = high_pass(x, periodic=True)
    return x, entry


def section(sources: list[str], name: str, source: str, start: float, end: float, hp_hz: float) -> tuple[np.ndarray, dict]:
    path = find(sources, source)
    x = read(path, start, end)
    entry = {"name": name, "kind": "loop", "source": f"{source} {start:g}-{start + len(x) / RATE:.3f} s", "high_pass_hz": hp_hz}
    x = np.repeat(x.mean(axis=1, keepdims=True), 2, axis=1)
    x = x - x.mean(axis=0)
    x = sosfilt(butter(4, hp_hz, "highpass", fs=RATE, output="sos"), x, axis=0)
    return fold(x, FOLD_SECONDS), entry


def pack(out: str, name: str, loops: list) -> list:
    """<name>.ogg: every loop between guards of its own audio."""
    guard = int(GUARD_SECONDS * RATE)
    parts, cursor = [], 0
    for entry, x in loops:
        parts += [x[-guard:], x, x[:guard]]
        entry["pack"] = {"file": name + ".ogg", "start_s": round((cursor + guard) / RATE, 6), "end_s": round((cursor + guard + len(x)) / RATE, 6)}
        cursor += len(x) + 2 * guard
    packed = np.concatenate(parts)
    decoded = save(out, name, packed)
    for entry, x in loops:
        region = decoded[int(round(entry["pack"]["start_s"] * RATE)) : int(round(entry["pack"]["end_s"] * RATE))]
        entry["seam_after_ogg"] = seam_report(region)
        entry["click_after_ogg"] = click_report(region)
    summary = {
        "name": name,
        "kind": "pack",
        "file": name + ".ogg",
        "duration_s": round(len(packed) / RATE, 4),
        "decoded_length_diff": int(len(decoded)) - int(len(packed)),
        "bytes": os.path.getsize(os.path.join(out, name + ".ogg")),
        "guard_s": GUARD_SECONDS,
        "asset_id": None,
    }
    return [summary] + [entry for entry, _ in loops]


def main(out: str, sources: list[str]):
    os.makedirs(os.path.join(out, "wav"), exist_ok=True)
    manifest = {}
    for pack_name, specs in PACKS.items():
        loops = []
        for spec in specs:
            loop, entry = whole(sources, *spec) if len(spec) == 3 else section(sources, *spec)
            loop, levels = normalise_loop(loop)
            entry.update(levels)
            entry["seam_before_ogg"] = seam_report(loop)
            entry["click_before_ogg"] = click_report(loop)
            entry["duration_s"] = round(len(loop) / RATE, 4)
            assert entry["name"] != pack_name, "a loop named like its pack would overwrite it"
            save(out, f"{pack_name}_{entry['name']}", loop)
            loops.append((entry, loop))
        manifest[pack_name] = pack(out, pack_name, loops)
    with open(os.path.join(out, "manifest.json"), "w") as handle:
        json.dump(manifest, handle, indent=1)
    for entries in manifest.values():
        for entry in entries:
            print(json.dumps(entry))
    clicks = [
        f"{entries[0]['name']}/{entry['name']}: {entry['click_after_ogg']['seam_vs_p999']}"
        for entries in manifest.values()
        for entry in entries[1:]
        if entry["click_after_ogg"]["seam_vs_p999"] > CLICK_LIMIT
    ]
    if clicks:
        raise SystemExit(f"seams more click-like than {CLICK_LIMIT} x the loop's loudest 0.1 %: {', '.join(clicks)}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
