# Eased keyboard steering: Play check (2026-10-29)

Solo Play in Studio, branch `agent/car-steering-smooth` synced (2 written). The character was placed 3.5 studs out from the door, then got in with E through the real prompt and started the car with R. The car stood still (SpeedKmh 0) throughout. The car's `Steer` attribute (Driving publishes the filtered steer) was sampled every rendered frame for 6 s while Studio's simulated keyboard held D for 1.5 s.

| Measure | Value |
|---|---|
| Frames sampled | 496 |
| D held: from the first movement to 0.95 of lock | 0.78 s (full lock 1.000 at about 0.9 s) |
| Path, every 12th frame | 0.087, 0.275, 0.475, 0.697, 0.881, 0.997, 1.000 |
| Largest change in one frame | 0.031 of lock |
| D released at rest: back to 0.003 | about 0.8 s (0.971, 0.763, 0.509, 0.321, 0.132, 0.003) |
| Overshoot past full lock or past centre | none (peak 1.000, minimum 0.000) |

A 0.1 s tap of A was sent after D; it arrived while the wheel was still returning and only hurried the return (the steer never went negative). The tap's own behaviour is covered by `tests/InputFilter.spec.luau` ("moves the wheel only a little on a short tap").

Not run in Play: steering on the move, the gamepad, and the feel, which is the owner's.
