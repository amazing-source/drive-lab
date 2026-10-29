# The barrier at the road's start: functional Play check (#69)

Solo Play in the owner's place, 2026-10-29 12:12-12:15, Studio lock held by the systems agent, no
network simulation. Synced from a local check branch merging this branch with `agent/car-reverse`
(#72, the reverse and its 40 km/h cap) on main 7854a3b, so the car could reach the barrier at the
cap as a player will (first sync 12 written, second 0). The check branch is not pushed. Keys from
Studio's simulated keyboard.

## The place, in edit mode, before Play

- `ReplicatedStorage.DriveLabAssets.GuardrailA` and `GuardrailB`: pivot at the beam's left end,
  12 m along +X; an invisible `Collider` from the ground to 0.75 m, 0.28 m thick, its face on the
  model's -Z side. `GuardrailStart` and `GuardrailEnd`: 4 m terminals flaring out of the line, no
  collider.
- The car: pivot (46, 1.9, 12.5), facing -Z. The spawn: (25, 0.5, -26), ahead of the car, so on the
  road side of the barrier. The start pad's centre is between them; its x range (-286 to 357 studs)
  lies inside the barrier's (-307.6 to 399.6).

## Results

| Check | Result | Numbers |
|---|---|---|
| Laid by the server at start | PASS | `Workspace.RoadEnd`: 11 sections (A and B alternating) and the two terminals, all at z = 178.6, from x = -307.6 to 399.6 (132 m over a 131 m road and verges); 30.9 m behind the car's pivot |
| A car reversing at the cap stops on the road | PASS | Reversing on S at a steady 39.2 km/h, the car met the barrier, bounced forward to 3.9 m/s, and (S still held) pushed back into it a few times before resting 2.17 m from the beam (pivot to beam), on the road |
| Not flung | PASS | From 12 m before the barrier to rest: up vector's Y never under 0.999 (under 3 degrees of tilt), upward speed at most 0.14 m/s, height 4.29 to 4.43 studs (4.38 before); heading after -0.01 degrees. One logged frame of 6.7 rad/s angular speed at the impact, with no rotation that followed |

Capture: `play_car_stopped_against_barrier_R.jpg`. It was taken from the chase camera, which stands
behind the barrier once the car rests against it: the W-beam and its posts in the foreground, the
car in R with its reversing lamps lit.

## Not checked

- Hitting the barrier above 40 km/h: reverse cannot go faster once #72 is in. Forward into it is
  not possible from the road side.
- Driving round its ends: the line is centred on the road and reaches 66 m to each side, 0.5 m past
  the verge's 65.5 m edge (a terminal adds 4 m more), so beside its ends there is no ground to drive
  onto. Measured from the positions above, not driven.
- The chase camera looking through the beam while the car rests against it (the camera's owner to
  judge).
