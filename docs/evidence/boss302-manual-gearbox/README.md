# Boss 302 H box, PR A: evidence (#209)

Systems agent, 2026-10-31. Offline on `tools/DriveSim`; no Studio, by instruction. The Boss has no model yet
and is not in the catalog.

| File | What it is |
|---|---|
| `calibration.txt` | `tools/boss302_calibrate.luau` on this branch: the Boss against the published data, the step cost, and the launch and stop at 30, 60, 120 and 240 FPS |
| `breaks.txt` | Every new rule broken on purpose, one at a time, against `ShiftPlan.spec`, `HBox.spec`, `Boss302.spec` and `PitLimiter.spec`: what was broken and which spec line failed |
| `tools_identical.txt` | Every game tool run on the base (61f6d7a) and on this branch: all identical except calibrate's wall-clock timing line |
| `svj_dr458_trace.txt` | 4,862 frames of SVJ and DR458 telemetry, wheel forces and body pose, at 30 and 60 FPS, on the base and on this branch: byte-identical (scenario and hashes) |
| `performance.txt` | Model.step for the three cars interleaved (the Boss about 150 us against the SVJ's 145 at 60 FPS), and the SVJ on the base against this branch |

## What the traces showed on the way

These findings set the agent's choices recorded in the PR.

- **A start flared the engine and spun the tyres.** The automatic clutch closed at its full rate while the
  engine revved to 4,200 rpm. The tyres spun (slip 1.6), traction control cut the throttle, and the clutch
  opened again, in a cycle. Holding the revs at the top of the clutch's slip band while it slips fixed the
  cycle. 0-60 mph went from 5.68 s to 4.92 s.
- **The 2-3 shift fell just before 60 mph.** At a 7,300 rpm shift point with 4 % tyre slip, the 2-3 shift came
  at 96 km/h. The shift point is now 7,400 rpm, 100 under the limiter, as on the other cars.
- **The soft LS springs left the ground.** With 5.5 cm of droop, the front wheels lifted on a start with
  traction control off. The rear unloaded under hard braking, and at 30 FPS its load chattered between 0 and
  11 kN. The model has no anti-dive or anti-squat geometry. Travel and droop were raised and the dampers made
  firmer (all EST).
- **Braking downshifts locked the rear wheels.** Without a blip, each clutch release dragged the idling engine
  up to the lower gear's speed: rear slip -0.55 to -0.68 for about 0.6 s. The automatic now heel-and-toes its
  own downshifts. This is a deviation from "no blip unless rev-matching is on", stated in the PR.
- **A spec hung instead of failing.** `stalled = stalled or DriveSim.frame(...)` stopped stepping the car once
  `stalled` was true, so the loop never ended under one break. It was rewritten so every iteration steps
  the car, and that break now fails cleanly.
