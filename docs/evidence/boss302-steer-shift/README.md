# Boss 302: steering release and quick automatic upshifts (evidence)

Systems agent, 2026-11-01. DriveSim, keyboard input help; no Studio.

## Slowing that kept going after the steering was released

The test: 160 km/h in 5th, full throttle, the steer key held 1 s then released.

| | Yaw settles after release (ESC on) | ESC acting after release | Lowest throttle after release | Yaw settles, ESC off | Coasting, ESC off |
|---|---|---|---|---|---|
| Boss before (front roll share 0.58) | 0.75 s | 0.60 s | 0.67 | never (the car spins) | never |
| Boss after (0.70) | 0.43 s | 0.28 s | 0.78 | 0.45 s | 0.75 s |
| SVJ (unchanged) | 0.35 s | 0.20 s | 0.80 | 0.37 s | |
| DR458 (unchanged) | 0.30 s | 0.05 s | 0.93 | 0.30 s | |

The steering returned to centre, the gearbox held 5th and the clutch stayed closed throughout. The keys are read with
IsKeyDown every frame; AZERTY Q is KeyCode.A, the left key. The cause was the car's balance: it oversteered after a
turn, and ESC braked it and cut the throttle while it caught the yaw.

## Automatic upshifts (drive broken: clutch under 0.9 or throttle cut, flat out from rest in Normal)

| | 1-2 | 2-3 | 3-4 |
|---|---|---|---|
| Before (the human pace) | 0.371 s | 0.471 s | 0.367 s |
| After (`autoTiming`) | 0.142 s | 0.179 s | 0.142 s |
| DR458, for reference | 0.063 s | 0.063 s | 0.062 s |

## Road tests (tools/boss302_calibrate, TracKey launch)

| | Before | After | Published |
|---|---|---|---|
| 0-60 mph, rollout / rest | 4.13 / 4.56 s | 4.06 / 4.50 s | 4.0-4.3 / 4.6 |
| Quarter mile, rollout / rest | 12.72 / 13.15 s | 12.45 / 12.88 s at 114.3 mph | 12.3-12.7 at 112.9-115.8 |
| Skidpad | 1.004 g | 0.981 g | 0.98 |
| 60-0 / 100-0 | 30.9 / 33.0 m | 31.3 / 33.5 m | 32.0 / 33.3 |

| File | What it is |
|---|---|
| `breaks.txt` | The three rules broken; each fails a spec |
| `tools_compare.txt` | Every tool on main and on this branch |
