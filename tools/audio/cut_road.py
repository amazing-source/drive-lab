"""
Cuts Drive Lab's speed sounds and packs them into one file, road_audio.ogg, so the set costs one
audio upload: a wind loop (the air rushing past the car) and a tyre roar loop (tyres on asphalt,
heard inside a car). Config/RoadAudio plays each through a LoopRegion; the regions are in
manifest.json.

    python -I tools/audio/cut_road.py <out dir> <sources dir> [<sources dir> ...]

The source folders hold the downloads under the names in LOOPS, both from
bigsoundbank.com/UPLOAD/flac/<n>.flac (CC0; the site wants a browser user agent and its own
Referer): bsb_1450.flac is BigSoundBank 1450, "Strong wind and trees #1" (storm Miguel, France,
June 2019), and bsb_3097.flac is 3097, "Car interior, 90 km/h" (a petrol Citroen C3 on a 90 km/h
road). Writes the pieces (OGG, and the WAV they were encoded from), road_audio.ogg and
manifest.json to <out dir>. Decoding and encoding go through ffmpeg.

The wind was first Freesound 82267 (ra_gun, heavy wind recorded from inside a car, CC0): Roblox's
audio moderation rejected the pack holding it on 2026-10-28 (asset 75621257296285), so the wind
is BigSoundBank's, the source whose recordings have all passed. 1450 is the flattest of the
storm recordings measured (no line over 3 dB, even from 300 Hz to 12 kHz); 1714 and 1716, wind
heard from indoors, stop near 2 kHz, and the wind has to reach 8 kHz at top speed.

The roar was chosen over BigSoundBank 3098 (the C3 at 80 km/h, its level swings 17 dB) and
Freesound 817389 (a 1.6 kHz tyre whine), 403667 (rattles), 520999 (a 5.5 kHz preview), 675209
(an engine line at 144 Hz) and 591079 (bumps); other winds over 0595 (a Foley wind machine,
nothing above 1.5 kHz), 439242 (window buffeting, lines at 264 and 296 Hz) and 438871/438881
(mains hum). Measured with Welch spectra: lines more than 6 dB over a sixth-octave median floor
between 30 Hz and 4 kHz, and the spread of 1 s levels.

The method is tools/audio/cut_weather.py's (loudness, seam folding, guards, the seam report
after OGG decoding), imported from it. Two steps are this pack's own: the wind's gusts are
ridden down with a slow gain (a car's own wind is steady; a storm's is not), and the roar's one
tonal line, the C3's engine firing at 69 Hz, is notched out, so the game's engine is the only
engine heard.
"""

import json
import os
import sys

import numpy as np
from scipy.ndimage import uniform_filter1d
from scipy.signal import butter, iirnotch, sosfilt, tf2sos

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cut_weather import (  # noqa: E402
    FOLD_SECONDS,
    GUARD_SECONDS,
    RATE,
    balance,
    find,
    flatten,
    fold,
    high_pass,
    normalise_loop,
    probe,
    read,
    save,
    seam_report,
)

# name, source, section start and end s, high-pass Hz, notches (Hz, Q), gust ride strength.
LOOPS = [
    # 1450: 29-65 s is its steadiest 36 s (4.4 dB of residual swing after the trend). Below 80 Hz
    # is wind buffeting the recorder, not air past a car.
    ("wind", "bsb_1450.flac", 29.0, 65.0, 80.0, [], 0.8),
    # 3097: 110-150 s is its steadiest 40 s (1.2 dB of residual swing).
    ("road", "bsb_3097.flac", 110.0, 150.0, 40.0, [(69.0, 6.0)], 0.0),
]
# The pack's name; the loops' names must differ from it, or a piece overwrites the pack.
PACK = "road_audio"
# Seconds of the power average the gust ride follows.
RIDE_SECONDS = 1.5


def notch(x: np.ndarray, hz: float, q: float) -> np.ndarray:
    b, a = iirnotch(hz, q, fs=RATE)
    return sosfilt(tf2sos(b, a), x, axis=0)


def ride(x: np.ndarray, strength: float) -> tuple[np.ndarray, float]:
    """Pulls the slow level toward its mean by `strength` (0 none, 1 flat); returns the swing removed, dB."""
    power = uniform_filter1d(np.mean(x**2, axis=1), size=int(RIDE_SECONDS * RATE), mode="nearest")
    level = 10 * np.log10(power + 1e-20)
    deviation = level - np.mean(level)
    y = x * 10 ** (-strength * deviation / 20)[:, None]
    return y, float(np.ptp(deviation))


def cut(sources: list[str], spec: tuple) -> tuple[np.ndarray, dict]:
    name, source, start, end, hp_hz, notches, strength = spec
    path = find(sources, source)
    section = read(path, start, end)
    entry = {"name": name, "kind": "loop", "source": f"{source} {start:g}-{start + len(section) / RATE:.3f} s"}
    section = section - section.mean(axis=0)
    section = high_pass(section, periodic=False)
    if hp_hz > 0:
        section = sosfilt(butter(2, hp_hz, "highpass", fs=RATE, output="sos"), section, axis=0)
        entry["high_pass_hz"] = hp_hz
    for hz, q in notches:
        section = notch(section, hz, q)
    if notches:
        entry["notches_hz_q"] = notches
    if strength > 0:
        section, swing = ride(section, strength)
        entry["gust_ride"] = {"strength": strength, "window_s": RIDE_SECONDS, "swing_before_db": round(swing, 2)}
    if probe(path)[1] == 2:
        section, difference = balance(section)
        entry["balanced_lr_db"] = round(difference, 2)
    section, drift = flatten(section)
    entry["drift_removed_db"] = round(drift, 2)
    loop = fold(section, FOLD_SECONDS)
    loop, levels = normalise_loop(loop)
    entry.update(levels)
    return loop, entry


def pack(out: str, loops: list) -> list:
    """road_audio.ogg: every loop between guards of its own audio."""
    guard = int(GUARD_SECONDS * RATE)
    parts, cursor = [], 0
    for entry, x in loops:
        parts += [x[-guard:], x, x[:guard]]
        entry["pack"] = {"file": PACK + ".ogg", "start_s": round((cursor + guard) / RATE, 6), "end_s": round((cursor + guard + len(x)) / RATE, 6)}
        cursor += len(x) + 2 * guard
    packed = np.concatenate(parts)
    decoded = save(out, PACK, packed)
    for entry, x in loops:
        region = decoded[int(round(entry["pack"]["start_s"] * RATE)) : int(round(entry["pack"]["end_s"] * RATE))]
        entry["seam_after_ogg"] = seam_report(region)
        probe_span = slice(guard, guard + int(0.5 * RATE))
        entry["pack_alignment"] = {
            str(lag): round(float(np.corrcoef(region[probe_span, 0], x[guard + lag : guard + lag + int(0.5 * RATE), 0])[0, 1]), 4) for lag in (-1, 0, 1)
        }
    summary = {
        "name": PACK,
        "kind": "pack",
        "file": PACK + ".ogg",
        "duration_s": round(len(packed) / RATE, 4),
        "decoded_length_diff": int(len(decoded)) - int(len(packed)),
        "bytes": os.path.getsize(os.path.join(out, PACK + ".ogg")),
        "guard_s": GUARD_SECONDS,
    }
    return [summary] + [entry for entry, _ in loops]


def main(out: str, sources: list[str]):
    assert PACK not in (spec[0] for spec in LOOPS), "a loop named like the pack would overwrite it"
    os.makedirs(os.path.join(out, "wav"), exist_ok=True)
    loops = []
    for spec in LOOPS:
        loop, entry = cut(sources, spec)
        entry["seam_before_ogg"] = seam_report(loop)
        entry["duration_s"] = round(len(loop) / RATE, 4)
        save(out, entry["name"], loop)
        loops.append((entry, loop))
    manifest = pack(out, loops)
    manifest[0]["asset_id"] = None
    with open(os.path.join(out, "manifest.json"), "w") as handle:
        json.dump(manifest, handle, indent=1)
    for entry in manifest:
        print(json.dumps(entry))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
