"""
Tracks an engine recording's rpm over time from one harmonic line, and plots it.

A four-stroke V12 fires 6 times per crank revolution, so its firing order sits at rpm / 10 Hz.
Pass the line to follow (--line, Hz, read off a spectrum first) and its engine order (--order,
6 for the firing order). Each 8192-sample frame takes the strongest peak within --band of the
line, refined by parabolic interpolation, and converts it to rpm = line * 60 / order. Which
order a line is cannot be read from one steady recording alone: the line spacing only bounds
it. For the Drive Lab SVJ bank the order comes from the mod's own FMOD auto-pitch reference
(tools/audio/fmod_autopitch.py).

Writes <out>/<name>_rpm.csv (time, line Hz, rpm, peak strength) and <out>/<name>_rpm.png
(spectrogram with the tracked line, and rpm against time). Prints the median rpm, the spread
and the period of any slow wobble.

    python -I tools/audio/engine_rpm_track.py <file.wav> <out dir> --line 757.7 --order 6
        [--band 0.12] [--name int_on] [--fmax 2000]
"""

import argparse
import csv
import os

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from scipy.io import wavfile

WINDOW = 8192
HOP = 1024


def load_mono(path: str) -> tuple[int, np.ndarray]:
    rate, data = wavfile.read(path, mmap=True)
    samples = data.astype(np.float32) / 32768.0
    return rate, samples.mean(axis=1) if samples.ndim == 2 else samples


def track(rate: int, mono: np.ndarray, line: float, band: float, fmax: float):
    window = np.hanning(WINDOW).astype(np.float32)
    freqs = np.fft.rfftfreq(WINDOW, 1 / rate)
    search = np.nonzero((freqs >= line * (1 - band)) & (freqs <= line * (1 + band)))[0]
    shown = freqs <= fmax
    frames = (len(mono) - WINDOW) // HOP
    times = np.empty(frames)
    peaks = np.empty(frames)
    strength = np.empty(frames)
    picture = np.empty((frames, int(shown.sum())), np.float32)
    for index in range(frames):
        start = index * HOP
        spectrum = np.abs(np.fft.rfft(mono[start : start + WINDOW] * window))
        picture[index] = spectrum[shown]
        local = spectrum[search]
        k = int(np.argmax(local))
        i = search[k]
        a, b, c = np.log(spectrum[i - 1 : i + 2] + 1e-12)
        curve = a - 2 * b + c
        offset = 0.5 * (a - c) / curve if curve != 0 else 0.0
        times[index] = (start + WINDOW / 2) / rate
        peaks[index] = (i + offset) * rate / WINDOW
        strength[index] = local[k] / (np.median(local) + 1e-12)
    return times, peaks, strength, freqs[shown], picture


def wobble_period(times: np.ndarray, rpm: np.ndarray) -> float:
    """Period of the strongest slow oscillation of the rpm track, 2 to 20 s, or 0."""
    centred = rpm - np.mean(rpm)
    correlation = np.correlate(centred, centred, mode="full")[len(centred) - 1 :]
    if correlation[0] <= 0:
        return 0.0
    correlation /= correlation[0]
    step = times[1] - times[0]
    lags = np.arange(len(correlation)) * step
    usable = (lags >= 2.0) & (lags <= 20.0)
    if not usable.any():
        return 0.0
    best = int(np.argmax(np.where(usable, correlation, -np.inf)))
    return float(lags[best]) if correlation[best] > 0.3 else 0.0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("wav")
    parser.add_argument("out")
    parser.add_argument("--line", type=float, required=True)
    parser.add_argument("--order", type=float, default=6.0)
    parser.add_argument("--band", type=float, default=0.12)
    parser.add_argument("--name", default=None)
    parser.add_argument("--fmax", type=float, default=2000.0)
    args = parser.parse_args()
    name = args.name or os.path.splitext(os.path.basename(args.wav))[0]
    os.makedirs(args.out, exist_ok=True)

    rate, mono = load_mono(args.wav)
    times, peaks, strength, freqs, picture = track(rate, mono, args.line, args.band, args.fmax)
    rpm = peaks * 60.0 / args.order
    confident = strength > 4.0

    with open(os.path.join(args.out, f"{name}_rpm.csv"), "w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["time_s", "line_hz", "rpm", "peak_strength"])
        for row in zip(times, peaks, rpm, strength):
            writer.writerow([round(row[0], 3), round(row[1], 2), round(row[2]), round(row[3], 1)])

    held = rpm[confident] if confident.any() else rpm
    median = float(np.median(held))
    period = wobble_period(times[confident], held) if confident.sum() > 100 else 0.0
    fig, axes = plt.subplots(2, 1, figsize=(18, 9), sharex=True, gridspec_kw={"height_ratios": [3, 2]})
    axes[0].pcolormesh(times, freqs, 20 * np.log10(picture.T + 1e-6), shading="auto", cmap="magma", vmin=-20, vmax=60)
    axes[0].plot(times[confident], peaks[confident], ",", color="#00e5ff")
    axes[0].set_ylabel("Hz")
    axes[0].set_title(f"{name}: spectrogram, tracked line in cyan (order {args.order:g})")
    axes[1].plot(times[confident], rpm[confident], ".", markersize=1.5, color="#c0392b")
    axes[1].axhline(median, color="#2c3e50", lw=0.8)
    axes[1].axhspan(median * 0.99, median * 1.01, color="#2c3e50", alpha=0.08)
    low, high = np.percentile(held, [1, 99])
    axes[1].set_ylim(low * 0.98, high * 1.02)
    axes[1].set_ylabel(f"rpm (line x 60 / {args.order:g})")
    axes[1].set_xlabel("time in the recording (s)")
    axes[1].set_title(f"median {median:.0f} rpm, band shows +-1 %")
    axes[1].grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(os.path.join(args.out, f"{name}_rpm.png"), dpi=80)

    p5, p95 = np.percentile(held, [5, 95])
    print(
        f"{name}: {len(mono) / rate:.1f} s, confident frames {int(confident.sum())}/{len(times)}, "
        f"median {median:.0f} rpm, 5-95 % {p5:.0f}-{p95:.0f} ({(p95 - p5) / median * 100:.2f} % wide), "
        f"wobble period {period:.2f} s"
    )


if __name__ == "__main__":
    main()
