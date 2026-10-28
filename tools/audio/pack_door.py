"""
Packs a car's two door sounds, the latch as the door starts to open and the shut as it closes,
into one file, so the pair costs one audio upload (Roblox allows 100 a month). Controllers/
CarDoor plays each through Sound.PlaybackRegion; the regions are in manifest.json.

    python -I tools/audio/pack_door.py <latch.wav> <shut.wav> <out dir>

For the SVJ the sources are the Assetto Corsa mod's own, drive-lab-assets/svj_sound_mod/wav/
26_door_open.wav (0.59 s) and 36_door_close.wav (0.55 s). Each sound starts its region at its
own onset (the first sample within ONSET_DB of its peak), so a region played the moment the
door moves lands its click on that moment; GUARD_SECONDS of silence keep the regions apart.
Writes door.wav, door.ogg (through ffmpeg) and manifest.json.
"""

import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from scipy.io import wavfile

RATE = 44100
GUARD_SECONDS = 0.25
ONSET_DB = -20.0


def mono(path: Path) -> np.ndarray:
    rate, data = wavfile.read(path)
    assert rate == RATE, f"{path} is {rate} Hz, expected {RATE}"
    samples = data.astype(np.float64)
    if data.dtype == np.int16:
        samples /= 32768.0
    return samples.mean(axis=1) if samples.ndim == 2 else samples


def onset(samples: np.ndarray) -> int:
    threshold = np.abs(samples).max() * 10 ** (ONSET_DB / 20)
    return int(np.argmax(np.abs(samples) >= threshold))


latch_path, shut_path, out = (Path(arg) for arg in sys.argv[1:4])
out.mkdir(parents=True, exist_ok=True)
guard = np.zeros(int(GUARD_SECONDS * RATE))
pieces, regions, cursor = [guard], {}, len(guard)
for name, path in (("latch", latch_path), ("shut", shut_path)):
    sound = mono(path)
    start = cursor + onset(sound)
    regions[name] = {"from": round(start / RATE, 4), "to": round((cursor + len(sound)) / RATE, 4)}
    pieces += [sound, guard]
    cursor += len(sound) + len(guard)
pack = np.concatenate(pieces)
wavfile.write(out / "door.wav", RATE, (np.clip(pack, -1, 1) * 32767).astype(np.int16))
subprocess.run(
    ["ffmpeg", "-y", "-loglevel", "error", "-i", str(out / "door.wav"), "-c:a", "libvorbis", "-q:a", "6", str(out / "door.ogg")],
    check=True,
)
manifest = {"seconds": round(len(pack) / RATE, 4), "regions": regions, "sources": [str(latch_path), str(shut_path)]}
(out / "manifest.json").write_text(json.dumps(manifest, indent=1))
print(json.dumps(manifest))
