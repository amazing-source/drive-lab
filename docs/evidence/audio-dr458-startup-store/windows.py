"""Scores hand-over windows for the store start-up on its measured envelope (store_envelope.txt).

The store sound fades out by cos and the idle mix fades in by sin over [handOver, to]; the sum's
power is compared with the idle's alone, in 100 ms windows from 0.3 s before the hand-over to its
end. The store's gain is the Sound volume it plays at (idle Sound volume x pack volume).
"""
import sys

import numpy as np

rows = np.loadtxt(sys.argv[1], comments="#")
t, rms = rows[:, 0], rows[:, 1]
keep = np.r_[True, np.diff(t) > 1e-6]
t, rms = t[keep], rms[keep]
IDLE_RMS = 10 ** (-38.2267 / 20)
gain = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
print(f"store Sound volume {gain:.4f}")
for hand, end in [(2.95, 3.45), (3.0, 3.4), (3.0, 3.45), (3.0, 3.5), (3.05, 3.45), (3.1, 3.5), (3.1, 3.9), (2.9, 3.5)]:
    worst, profile = 0.0, []
    for a in np.arange(hand - 0.3, end, 0.1):
        m = (t >= a) & (t < a + 0.1)
        if not m.any():
            continue
        mid = a + 0.05
        p = np.clip((mid - hand) / (end - hand), 0, 1)
        store = np.mean((gain * rms[m]) ** 2)
        total = np.cos(p * np.pi / 2) ** 2 * store + np.sin(p * np.pi / 2) ** 2 * IDLE_RMS**2
        db = 10 * np.log10(total / IDLE_RMS**2)
        profile.append(f"{db:+.1f}")
        if a >= hand - 1e-9:
            worst = max(worst, abs(db))
    print(f"hand-over {hand:.2f}-{end:.2f}: worst 100 ms window inside the fade {worst:.2f} dB from the idle; profile from -0.3 s: {' '.join(profile)}")
