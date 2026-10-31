"""
Measures the loudness of each cockpit control sound the DR458 plays (games/drive-lab/tools/
control_sounds.luau's JSON) and writes the fixture tests/CarAudio.spec checks them against: a
one-shot by its loudest 100 ms, a loop over its whole region, both K-weighted and ungated
(render_preview's loudness), in LUFS, a mono file counted on both channels at full level. Store sounds are read from <sounds dir>/<asset id>.ogg (Roblox's
licensed Pro Sound Effects play without a session: assetdelivery.roblox.com/v2/assetId/<id>); the
DR458's events file is passed as its baked WAV.

    lune run games/drive-lab/tools/control_sounds.luau > control_sounds.json
    python -I tools/audio/measure_control_sounds.py control_sounds.json <sounds dir> <events id> <events.wav> <fixture.json>
"""

import json
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_preview as R  # noqa: E402

ONE_SHOT_WINDOW = 0.1
HOP = 0.01


def decode(path):
    """Both channels of a stereo file; a mono file on both at full level, as the engine loops are
    measured (render_preview.decode's ffmpeg upmix would put it 3 dB lower)."""
    channels = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "stream=channels", "-of", "csv=p=0", path],
        capture_output=True, check=True, text=True,
    ).stdout.split()[0]
    if channels != "1":
        return R.decode(path)
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(R.RATE), "-"], check=True, capture_output=True
    ).stdout
    mono = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    return np.stack([mono, mono], axis=1)


def loudest(x, seconds):
    window = int(seconds * R.RATE)
    if len(x) <= window:
        return R.loudness(x)
    return max(R.loudness(x[k : k + window]) for k in range(0, len(x) - window + 1, int(HOP * R.RATE)))


def main(entries_path, sounds_dir, events_id, events_path, out_path):
    entries = json.load(open(entries_path, encoding="utf-8-sig"))
    decoded = {}
    fixture = {}
    for entry in entries:
        sound_id = entry["soundId"]
        path = events_path if sound_id == events_id else os.path.join(sounds_dir, sound_id.split("//")[-1] + ".ogg")
        if path not in decoded:
            decoded[path] = decode(path)
        region = decoded[path][int(round(entry["from"] * R.RATE)) : int(round(entry["to"] * R.RATE))]
        level = loudest(region, ONE_SHOT_WINDOW) if entry["kind"] == "OneShot" else R.loudness(region)
        key = "%s@%g-%g" % (sound_id, entry["from"], entry["to"])
        fixture[key] = round(level, 2)
        print("%-22s %-28s %6.2f LUFS" % (entry["name"], key, level))
    json.dump(dict(sorted(fixture.items())), open(out_path, "w", encoding="utf-8", newline="\n"), indent="\t")


if __name__ == "__main__":
    main(*sys.argv[1:6])
