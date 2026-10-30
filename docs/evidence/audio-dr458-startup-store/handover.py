import sys
import numpy as np

rows = np.loadtxt(sys.argv[1], comments="#")
t, rms, peak, pu, pk = rows.T
# The probe reads some buffers twice: keep each time position once.
keep = np.r_[True, (np.diff(t) > 1e-6)]
t, rms, peak, pu, pk = t[keep], rms[keep], peak[keep], pu[keep], pk[keep]
IDLE_RMS_DB, IDLE_K_DB = -38.2267, -37.0129


def db(p):
    return 10 * np.log10(p + 1e-30)


print("idle (game mix at 1,000 rpm, throttle 0): RMS %.2f dBFS, K %.2f dB (spectrum scale)" % (IDLE_RMS_DB, IDLE_K_DB))


def window(a, b, lag=0.0):
    m = (t >= a) & (t < b)
    mk = (t >= a + lag) & (t < b + lag)
    return db(np.mean(rms[m] ** 2)), db(np.mean(pk[mk]))


for a, b in [(2.9, 3.9), (3.0, 3.9), (3.1, 3.9), (3.2, 3.9), (2.5, 3.1), (3.0, 3.6), (3.1, 3.5), (3.5, 3.9), (3.3, 3.9), (2.5, 3.1)]:
    r, k = window(a, b, lag=0.04)
    print(f"store {a:.1f}-{b:.1f} s: RMS {r:6.2f} dBFS ({r - IDLE_RMS_DB:+.2f} vs idle), K {k:6.2f} ({k - IDLE_K_DB:+.2f} vs idle)")

print("\n100 ms RMS envelope (dBFS):")
for a in np.arange(0.4, 3.95, 0.1):
    m = (t >= a) & (t < a + 0.1)
    if m.any():
        print(f"  {a:.1f}-{a + 0.1:.1f}  {db(np.mean(rms[m] ** 2)):6.1f}  peak {20 * np.log10(peak[m].max() + 1e-12):6.1f}")
i = np.argmax(rms)
print("loudest buffer at %.3f s: RMS %.1f dBFS; loudest peak %.1f dBFS" % (t[i], 20 * np.log10(rms[i]), 20 * np.log10(peak.max())))
