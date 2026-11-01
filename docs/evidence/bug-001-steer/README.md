# BUG-001 (Space with D/Q): evidence

Systems agent, 2026-11-01. DriveSim, keyboard input help; no Studio.

## Reproduced

The test: Space held or tapped while steering with D or Q (60-140 km/h, half the runs coasting, a paddle shift
mid-drift), then the steer key let go with Space still held. Counted: runs still smoking, turning or re-drifting
2-3 s after the steer key was let go, above 30 km/h, 100 runs per car.

| | DR458 | SVJ | Boss 302 |
|---|---|---|---|
| main | 15 | 23 | 27 |
| this fix | 0 | 0 | 0 |

The cause: Space is both the drift and the handbrake. Once the steering was let go and the slide closed under the
drift's gate, the drift dropped and the still-held button became the handbrake again. The handbrake locked the rear
wheels, so the tyres smoked and the car slid and yawed. The slide re-opened the gate, the drift re-engaged and
released the handbrake, the slide closed, the handbrake came back, and so on for as long as Space was held, with
the automatic downshifting under the handbrake's braking. That is the permanent smoke, the car turning on its own
and the "around shifts".

## The fix

A hold of the button that has drifted stays the drift's until the button is let go or the car is slower than a drift
(30 km/h); then it is the handbrake again. Traced, DR458 at 100 km/h coasting: on main, smoke 1.0 and yaw 0.3-0.6
rad/s through 2-4 s with the drift re-engaging; fixed, smoke 0, yaw 0 and no new drift.

## SVJ and DR458

Only that input changes: Space still held, above 30 km/h, after a drift in the same hold. drift_turn, drift_baseline,
drift_candidate, assists and calibrate output are identical to main; the 4,862-frame trace keeps its hash
(`7f2eee0a…`).

| File | What it is |
|---|---|
| `breaks.txt` | Three breaks (main's rule first); each fails a spec |
