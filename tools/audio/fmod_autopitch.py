"""
Reads how an Assetto Corsa FMOD Studio bank (.bank) plays its samples: for every waveform
instrument, the sample it plays, its pitch (semitones) and volume (dB), its auto-pitch (the
game parameter that drives it, the parameter value at which the sample plays at its own
pitch, and the pitch at the parameter's minimum), and the automation curves bound to it.

This is what answers "at what rpm was this loop recorded" for a bank whose engine loops are
long single-rpm takes: the mod author's auto-pitch reference is the rpm at which the game plays
the sample unchanged. The FEV layout below was read off the bank itself (no public spec): a
RIFF tree whose WAIT lists hold a WAIB body (instrument GUID, waveform GUID) and an INST body;
WAV chunks map a waveform GUID to its FSB5 subsound; CTRL chunks bind a CURV (points of x, y,
shape) to an owner and a parameter (PRMB, which carries the parameter's name).

    python -I tools/audio/fmod_autopitch.py <file.bank>
"""

import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets"))
import fsb5_extract  # noqa: E402

# Offsets inside an INST body, measured on the gbe_lamborghini_aventador_svj_f1 bank.
PITCH_AT = 16
VOLUME_AT = 20
AUTOPITCH_PARAMETER_AT = 53
AUTOPITCH_REFERENCE_AT = 69
AUTOPITCH_MINIMUM_AT = 73


def chunks(data: bytes, start: int, end: int, out: list):
    while start + 8 <= end:
        kind = data[start : start + 4]
        (size,) = struct.unpack_from("<I", data, start + 4)
        body = start + 8
        if kind in (b"RIFF", b"LIST"):
            node = {"kind": "LIST:" + data[body : body + 4].decode("latin1"), "children": []}
            out.append(node)
            chunks(data, body + 4, body + size, node["children"])
        else:
            out.append({"kind": kind.decode("latin1"), "raw": data[body : body + size]})
        start = body + size + (size & 1)


def flatten(nodes: list, out: list) -> list:
    for node in nodes:
        out.append(node)
        flatten(node.get("children", []), out)
    return out


def curve_points(raw: bytes) -> list:
    # Two GUIDs and a 4-byte header, then (x, y, shape, flags) per point.
    return [struct.unpack_from("<ff", raw, at) for at in range(36, len(raw) - 15, 16)]


def main(path: str):
    data = open(path, "rb").read()
    sample_bank = data.find(b"FSB5")
    _, samples = fsb5_extract.read_samples(data, sample_bank)
    tree: list = []
    chunks(data, 0, sample_bank, tree)
    nodes = flatten(tree, [])

    waveforms = {n["raw"][:16]: struct.unpack_from("<H", n["raw"], 22)[0] for n in nodes if n["kind"] == "WAV "}
    parameters = {}
    for node in nodes:
        if node["kind"] == "PRMB":
            raw = node["raw"]
            (length,) = struct.unpack_from("<H", raw, 21)
            parameters[raw[:16]] = raw[23 : 23 + length].split(b"\0")[0].decode()
    curves = {n["raw"][:16]: curve_points(n["raw"]) for n in nodes if n["kind"] == "CURV"}
    bindings: dict = {}
    for node in nodes:
        if node["kind"] == "CTRL":
            raw = node["raw"]
            bindings.setdefault(raw[16:32], []).append((parameters.get(raw[32:48], "?"), curves.get(raw[:16], [])))

    for node in nodes:
        if node["kind"] != "LIST:WAIT":
            continue
        parts = {child["kind"]: child["raw"] for child in node["children"] if "raw" in child}
        body, inst = parts["WAIB"], parts.get("INST", b"")
        name = samples[waveforms[body[16:32]]]["name"]
        pitch, volume = struct.unpack_from("<ff", inst, PITCH_AT)
        line = f"{name:40s} pitch {pitch:+6.2f} st  volume {volume:+6.2f} dB"
        parameter = inst[AUTOPITCH_PARAMETER_AT : AUTOPITCH_PARAMETER_AT + 16]
        if parameter in parameters:
            reference, minimum = struct.unpack_from("<ff", inst, AUTOPITCH_REFERENCE_AT)
            line += f"  auto-pitch on '{parameters[parameter]}': x1 at {reference:g}, x{minimum:g} at its minimum"
        for parameter_name, points in bindings.get(body[:16], []):
            shown = " ".join(f"({x:g}, {y:g})" for x, y in points)
            line += f"\n{'':42s}curve on '{parameter_name}': {shown}"
        print(line)


if __name__ == "__main__":
    main(sys.argv[1])
