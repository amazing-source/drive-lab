"""
Extracts the samples of an FMOD Studio sound bank (.bank, an FSB5 sample bank inside a RIFF) to
WAV files, for banks stored as plain PCM. Assetto Corsa car mods ship their sounds this way.
Prints each sample's name, rate, channels and length; writes <out dir>/<index>_<name>.wav.

    python -I tools/assets/fsb5_extract.py <file.bank> <out dir>

Encrypted banks and compressed codecs (Vorbis, FADPCM) are reported and skipped: those need
vgmstream. Format reference: the FSB5 header and sample-header bit layout as documented by the
vgmstream and python-fsb5 projects.
"""
import os
import struct
import sys
import wave

FREQUENCIES = {1: 8000, 2: 11000, 3: 11025, 4: 16000, 5: 22050, 6: 24000, 7: 32000, 8: 44100, 9: 48000, 10: 96000}
CODECS = {1: "PCM8", 2: "PCM16", 3: "PCM24", 4: "PCM32", 6: "IMAADPCM", 13: "Vorbis", 15: "FADPCM", 16: "Opus"}


def read_samples(data, base):
    version, count, headers_size, names_size, data_size, mode = struct.unpack_from("<IIIIII", data, base + 4)
    header_size = 0x3C if version == 1 else 0x40
    cursor = base + header_size
    samples = []
    for _ in range(count):
        (raw,) = struct.unpack_from("<Q", data, cursor)
        cursor += 8
        sample = {
            "rate": FREQUENCIES.get((raw >> 1) & 0xF, 44100),
            "channels": {0: 1, 1: 2, 2: 6, 3: 8}[(raw >> 5) & 0x3],
            "offset": ((raw >> 7) & 0x7FFFFFF) << 5,
            "frames": (raw >> 34) & 0x3FFFFFFF,
        }
        more = raw & 1
        while more:
            (chunk,) = struct.unpack_from("<I", data, cursor)
            cursor += 4
            more = chunk & 1
            size = (chunk >> 1) & 0xFFFFFF
            kind = (chunk >> 25) & 0x7F
            if kind == 1:
                sample["channels"] = data[cursor]
            elif kind == 2:
                (sample["rate"],) = struct.unpack_from("<I", data, cursor)
            elif kind == 3:
                sample["loop"] = struct.unpack_from("<II", data, cursor)
            cursor += size
        samples.append(sample)
    names_start = base + header_size + headers_size
    for index, sample in enumerate(samples):
        if names_size:
            (offset,) = struct.unpack_from("<I", data, names_start + 4 * index)
            end = data.index(b"\0", names_start + offset)
            sample["name"] = data[names_start + offset : end].decode("utf-8", "replace")
        else:
            sample["name"] = f"sample{index}"
    data_start = names_start + names_size
    for index, sample in enumerate(samples):
        stop = samples[index + 1]["offset"] if index + 1 < len(samples) else data_size
        sample["bytes"] = data[data_start + sample["offset"] : data_start + stop]
    return CODECS.get(mode, str(mode)), samples


def main(bank_path, out_dir):
    data = open(bank_path, "rb").read()
    base = data.find(b"FSB5")
    if base < 0:
        raise SystemExit("no FSB5 sample bank found: the bank is probably encrypted (use vgmstream)")
    codec, samples = read_samples(data, base)
    if codec != "PCM16":
        raise SystemExit(f"codec {codec}: not plain PCM16, use vgmstream")
    os.makedirs(out_dir, exist_ok=True)
    for index, sample in enumerate(samples):
        frame_bytes = 2 * sample["channels"]
        audio = sample["bytes"][: sample["frames"] * frame_bytes]
        safe = "".join(c if c.isalnum() or c in "-_." else "_" for c in sample["name"])
        path = os.path.join(out_dir, f"{index:02d}_{safe}.wav")
        with wave.open(path, "wb") as out:
            out.setnchannels(sample["channels"])
            out.setsampwidth(2)
            out.setframerate(sample["rate"])
            out.writeframes(audio)
        loop = f" loop {sample['loop']}" if "loop" in sample else ""
        print(f"{index:02d} {sample['name']:40s} {sample['rate']} Hz x{sample['channels']} {sample['frames'] / sample['rate']:6.2f} s{loop}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
