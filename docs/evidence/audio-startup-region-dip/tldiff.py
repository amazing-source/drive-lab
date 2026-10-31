"""Compares two audio_timeline.luau outputs field by field.

    python -I tldiff.py <a.json> <b.json>

Prints every frame that differs (time, field, a, b), grouped into contiguous time spans, and
whether the one-shots and the header fields are identical."""
import json
import sys

a, b = (json.load(open(path)) for path in sys.argv[1:3])
for key in ("dt", "car", "mode", "files", "startupSound"):
    print(f"{key}: {'same' if a.get(key) == b.get(key) else 'DIFFERENT'}")
print(f"shots: {'same' if a['shots'] == b['shots'] else 'DIFFERENT'} ({len(a['shots'])} vs {len(b['shots'])})")
print(f"frames: {len(a['frames'])} vs {len(b['frames'])}")


def flat(frame):
    out = {}
    for key, value in frame.items():
        if isinstance(value, list):
            for index, item in enumerate(value):
                out[f"{key}[{index + 1}]"] = item
        else:
            out[key] = value
    return out


spans = []
largest = 0.0
for fa, fb in zip(a["frames"], b["frames"]):
    ka, kb = flat(fa), flat(fb)
    fields = [k for k in ka if ka[k] != kb.get(k)]
    if fields:
        for k in fields:
            largest = max(largest, abs(ka[k] - kb[k]))
        if spans and abs(fa["t"] - spans[-1][1] - a["dt"]) < 1e-9:
            spans[-1][1] = fa["t"]
            spans[-1][2].update(fields)
            spans[-1][3] += 1
        else:
            spans.append([fa["t"], fa["t"], set(fields), 1])
if not spans:
    print("no frame differs")
for start, end, fields, count in spans:
    print(f"differs t={start:.4f}..{end:.4f} s ({count} frames): {', '.join(sorted(fields))}")
print(f"largest absolute difference: {largest:.6g}")
