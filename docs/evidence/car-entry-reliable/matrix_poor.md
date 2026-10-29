# Play matrix, poor network profile

Branch head 1624e96, solo Play, 2026-10-29. The client on Studio's "poor" profile: 150 ms delay,
100 ms jitter and 0.5% loss each way (ping 0.35 s). Columns and starts as in `matrix_none.md`; the
Torso column is the torso's largest move in one frame of any speed. A jump fails a scenario when it
is over 0.5 studs and faster than 30 studs/s (sprinting is 26): on this profile a 50 ms Studio frame
carried the walk 0.71 studs in one frame at 14 studs/s, which the plain 0.5 limit counted as a
jump. The no-simulation run passed the plain limit.

37 of 37 pass.

| # | Case | Start | Abuse | Result | First clip | On mark | Torso | Hand-over | Notes |
|---|---|---|---|---|---|---|---|---|---|
| 1 | EnterShut | straight-out-4 | - | PASS | 0.91 | 0.38 | 0.22 | 0.05 |  |
| 2 | EnterShut | straight-out-4-away | - | PASS | 1.04 | 0.51 | 0.22 | 0.02 |  |
| 3 | EnterShut | close-0.9 | - | PASS | 1.00 | 0.42 | 0.21 | 0.03 |  |
| 4 | EnterShut | close-away-0.6 | - | PASS | 0.96 | 0.43 | 0.22 | 0.05 |  |
| 5 | EnterShut | angle-45 | - | PASS | 1.32 | 0.83 | 0.25 | 0.04 |  |
| 6 | EnterShut | beside-front-4 | - | PASS | 1.09 | 0.48 | 0.32 | 0.01 |  |
| 7 | EnterShut | beside-rear-4 | - | PASS | 1.01 | 0.38 | 0.25 | 0.06 |  |
| 8 | EnterShut | far-5.5 | - | PASS | 0.98 | 0.47 | 0.22 | 0.02 |  |
| 9 | EnterShut | front-corner | - | PASS | - | - | - | - | prompt not shown at 7.3 studs: nothing happened |
| 10 | EnterShut | rear-corner | - | PASS | - | - | - | - | prompt not shown at 7.3 studs: nothing happened |
| 11 | EnterShut | far-side | - | PASS | - | - | - | - | prompt not shown at 14.7 studs: nothing happened |
| 12 | EnterOpen | straight-out-4 | - | PASS | 0.94 | 0.39 | 0.22 | 0.07 |  |
| 13 | EnterOpen | straight-out-4-away | - | PASS | 1.08 | 0.42 | 0.22 | 0.01 |  |
| 14 | EnterOpen | close-away-0.6 | - | PASS | 0.84 | 0.34 | 0.22 | 0.00 |  |
| 15 | EnterOpen | beside-front-4 | - | PASS | 1.03 | 0.40 | 0.25 | 0.00 |  |
| 16 | EnterOpen | beside-rear-4 | - | PASS | 1.03 | 0.42 | 0.25 | 0.01 |  |
| 17 | OpenOutside | straight-out-4 | - | PASS | 1.41 | 0.43 | 0.22 | 0.00 |  |
| 18 | OpenOutside | straight-out-4-away | - | PASS | 0.97 | 0.36 | 0.22 | 0.00 |  |
| 19 | OpenOutside | close-away-0.6 | - | PASS | 1.36 | 0.41 | 0.22 | 0.00 |  |
| 20 | OpenOutside | beside-front-4 | - | PASS | 1.20 | 0.59 | 0.26 | 0.00 |  |
| 21 | OpenOutside | beside-rear-4 | - | PASS | 1.03 | 0.36 | 0.25 | 0.00 |  |
| 22 | CloseOutside | straight-out-4 | - | PASS | 0.91 | 0.43 | 0.22 | 0.00 |  |
| 23 | CloseOutside | straight-out-4-away | - | PASS | 0.99 | 0.47 | 0.22 | 0.00 |  |
| 24 | CloseOutside | close-away-0.6 | - | PASS | 1.03 | 0.30 | 0.22 | 0.00 |  |
| 25 | CloseOutside | beside-front-4 | - | PASS | 0.99 | 0.35 | 0.29 | 0.00 |  |
| 26 | CloseOutside | beside-rear-4 | - | PASS | 0.94 | 0.33 | 0.32 | 0.00 |  |
| 27 | CloseInside | seated | - | PASS | 0.42 | - | 0.01 | 0.00 |  |
| 28 | OpenInside | seated | - | PASS | 0.47 | - | 0.02 | 0.00 |  |
| 29 | ExitShut | seated | - | PASS | 0.44 | - | 0.07 | 0.00 | drift 0.00, car after 0.00 |
| 30 | ExitOpen | seated | - | PASS | 0.77 | - | 0.07 | 0.00 | drift 0.00, car after 0.00 |
| 31 | EnterShut | straight-out-4 | DoubleE | PASS | 0.90 | 0.35 | 0.24 | 0.03 |  |
| 32 | EnterShut | beside-front-4 | DoubleE | PASS | 0.99 | 0.37 | 0.28 | 0.02 |  |
| 33 | EnterShut | straight-out-4 | ResetWalk | PASS | - | - | 0.22 | 0.00 |  |
| 34 | EnterShut | straight-out-4 | ResetSequence | PASS | 0.97 | 0.42 | 0.22 | 0.03 |  |
| 35 | ExitShut | seated | ResetSequence | PASS | 0.49 | - | 0.07 | 0.00 | the drift is the respawn; car after 0.00 |
| 36 | EnterShut | straight-out-4 | KeysDuring | PASS | 0.96 | 0.39 | 0.24 | 0.05 |  |
| 37 | ExitShut | seated | KeysDuring | PASS | 0.49 | - | 0.07 | 0.00 | drift 0.00, car after 0.00 |

The car itself moved at most 0.02 studs in any scenario.

Earlier poor runs on this branch failed, each fixed and re-run in full: a door clip from outside
starting 0.52 to 0.8 studs under way (the start did not allow enough for the network), a 0.42 to
1.29-stud hand-over into the seat (the weld after the start), a 0.71 frame-hitch move counted
as a jump (the harness), and a 4.79-stud jump when a movement key walked the body off the mark
while the server confirmed (6aefdb0 passed this matrix 37 of 37; the walk-away key test then
found it, and 1624e96 holds the body on the mark). See the PR.
