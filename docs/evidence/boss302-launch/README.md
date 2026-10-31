# Boss 302 standing start: evidence (#220)

Systems agent, 2026-10-31. Offline on `tools/DriveSim`; no Studio.

| File | What it is |
|---|---|
| `calibration_before.txt` | `tools/boss302_calibrate` on main 31b1839's config, timed from rest and with the one-foot rollout |
| `calibration_after.txt` | The same tool on this branch |
| `breaks.txt` | The four config rules broken one at a time; each fails a spec |

## Where the time went (TracKey launch, before)

| Phase | What the trace showed |
|---|---|
| 1st gear | Already at the tyres' limit: 0.70-0.74 g, traction control holding the slip at the 0.10 peak, rear μ about 1.25 under load |
| The launch | About 0.25 s lost in two dead spots. A traction-control cut drops the engine torque the automatic clutch follows, the clutch opens at once and re-closes only at 0.25 s. At that rate the start was chaotic: unrelated small changes moved 0-60 by up to 0.6 s |
| Each shift | 0.40-0.50 s without drive (clutch down to back up), against a quick human shift's 0.25-0.35 s; three shifts in a quarter mile |
| The first foot | 0.44 s. MT and Edmunds take it off their times (the rollout); the old tool did not |

## Tried and rejected (measured)

| Change | 0-60 mph from rest (TracKey) | Why rejected |
|---|---|---|
| Softer traction control (gain 2, or the outright cut at 4× the slip) | 4.93 / 4.99 s (base 4.88) | No gain |
| Traction control recovering in 0.1 s | 5.47 s | Worse |
| The clutch's opening rate-limited while pulling away | about 5.8 s | The tyres stay spinning |
| Launch rpm 2,200 or 3,000 | 5.09 / 4.99 s | No gain |
| Flywheel 0.15 kg·m² | 5.47 s | Chaotic, worse |
| μX 1.40 on both axles | 4.60 s | 60-0 falls to 29.1 m, out of the published range |
| The throttle fed back with the clutch's bite instead of the pedal | -0.02 s | Not worth a code change |
