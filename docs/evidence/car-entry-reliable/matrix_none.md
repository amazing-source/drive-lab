# Play matrix, no network simulation

Branch head e874f92, solo Play, 2026-10-29. All six NetworkSettings at 0 in edit and on the client
(ping 0.002 s). Harness: `harness/` (the scenarios themselves did not change since; a RealKey mode
was added afterwards for the key tests). Times in seconds from the press; moves in studs across the
ground.

- First clip: from the press to the first frame a clip plays.
- On mark: the body standing still on the mark before its sequence starts. "-" where no recorded
  frame had the body within 0.05 studs of the mark, or for door clips, which show their first frame
  while the last of the placing runs.
- Torso: the torso's largest move in one frame over the whole scenario (the clips move it up to
  0.18 a frame, a walk 0.21). Limit 0.5.
- Hand-over: its move across the frame the seat's weld took or let go of the body. Limit 0.4 in,
  0.35 out.
- Exits also pass on: stood up within 0.35 of where getting out ends (where the car was then),
  moved at most 0.1 after standing, no overlap with the car's box, car at rest, door shut, full size.
- Car moved: how far the car itself moved during the scenario, shown from 0.05 (the harness parks
  it before each one).
- Out of reach (prompt distance 6): a player cannot press a prompt that is not shown; the harness
  presses anyway and checks nothing happened.

37 of 37 pass.

| # | Case | Start | Abuse | Result | First clip | On mark | Torso | Hand-over | Notes |
|---|---|---|---|---|---|---|---|---|---|
| 1 | EnterShut | straight-out-4 | - | PASS | 0.60 | 0.28 | 0.22 | 0.03 |  |
| 2 | EnterShut | straight-out-4-away | - | PASS | 0.72 | 0.20 | 0.22 | 0.04 |  |
| 3 | EnterShut | close-0.9 | - | PASS | 0.19 | 0.09 | 0.25 | 0.02 |  |
| 4 | EnterShut | close-away-0.6 | - | PASS | 0.43 | 0.08 | 0.22 | 0.02 |  |
| 5 | EnterShut | angle-45 | - | PASS | 0.58 | 0.10 | 0.25 | 0.06 |  |
| 6 | EnterShut | beside-front-4 | - | PASS | 0.76 | 0.14 | 0.24 | 0.03 |  |
| 7 | EnterShut | beside-rear-4 | - | PASS | 0.71 | - | 0.25 | 0.07 | car moved 0.07 |
| 8 | EnterShut | far-5.5 | - | PASS | 0.60 | 0.17 | 0.22 | 0.04 |  |
| 9 | EnterShut | front-corner | - | PASS | - | - | - | - | prompt not shown at 7.3 studs: nothing happened |
| 10 | EnterShut | rear-corner | - | PASS | - | - | - | - | prompt not shown at 7.3 studs: nothing happened |
| 11 | EnterShut | far-side | - | PASS | - | - | - | - | prompt not shown at 14.7 studs: nothing happened |
| 12 | EnterOpen | straight-out-4 | - | PASS | 0.52 | 0.22 | 0.22 | 0.02 |  |
| 13 | EnterOpen | straight-out-4-away | - | PASS | 0.69 | 0.17 | 0.22 | 0.03 |  |
| 14 | EnterOpen | close-away-0.6 | - | PASS | 0.48 | 0.11 | 0.22 | 0.01 |  |
| 15 | EnterOpen | beside-front-4 | - | PASS | 0.73 | 0.11 | 0.32 | 0.04 |  |
| 16 | EnterOpen | beside-rear-4 | - | PASS | 0.72 | 0.11 | 0.26 | 0.05 |  |
| 17 | OpenOutside | straight-out-4 | - | PASS | 0.44 | 0.13 | 0.31 | 0.00 |  |
| 18 | OpenOutside | straight-out-4-away | - | PASS | 0.58 | 0.06 | 0.31 | 0.00 |  |
| 19 | OpenOutside | close-away-0.6 | - | PASS | 0.30 | - | 0.36 | 0.00 |  |
| 20 | OpenOutside | beside-front-4 | - | PASS | 0.56 | - | 0.38 | 0.00 |  |
| 21 | OpenOutside | beside-rear-4 | - | PASS | 0.57 | - | 0.32 | 0.00 |  |
| 22 | CloseOutside | straight-out-4 | - | PASS | 0.46 | 0.16 | 0.22 | 0.00 |  |
| 23 | CloseOutside | straight-out-4-away | - | PASS | 0.59 | 0.04 | 0.32 | 0.00 |  |
| 24 | CloseOutside | close-away-0.6 | - | PASS | 0.31 | - | 0.22 | 0.00 |  |
| 25 | CloseOutside | beside-front-4 | - | PASS | 0.57 | - | 0.29 | 0.00 |  |
| 26 | CloseOutside | beside-rear-4 | - | PASS | 0.56 | - | 0.26 | 0.00 |  |
| 27 | CloseInside | seated | - | PASS | 0.04 | - | 0.02 | 0.00 |  |
| 28 | OpenInside | seated | - | PASS | 0.04 | - | 0.03 | 0.00 |  |
| 29 | ExitShut | seated | - | PASS | 0.04 | - | 0.07 | 0.00 | drift 0.00, car after 0.01 |
| 30 | ExitOpen | seated | - | PASS | 0.04 | - | 0.08 | 0.00 | drift 0.00, car after 0.00 |
| 31 | EnterShut | straight-out-4 | DoubleE | PASS | 0.51 | 0.21 | 0.24 | 0.04 |  |
| 32 | EnterShut | beside-front-4 | DoubleE | PASS | 0.75 | 0.13 | 0.25 | 0.03 |  |
| 33 | EnterShut | straight-out-4 | ResetWalk | PASS | - | - | 0.23 | 0.00 |  |
| 34 | EnterShut | straight-out-4 | ResetSequence | PASS | 0.54 | 0.22 | 0.22 | 0.04 |  |
| 35 | ExitShut | seated | ResetSequence | PASS | 0.06 | - | 0.02 | 0.00 | the drift is the respawn; car after 0.00 |
| 36 | EnterShut | straight-out-4 | KeysDuring | PASS | 0.53 | 0.23 | 0.23 | 0.04 |  |
| 37 | ExitShut | seated | KeysDuring | PASS | 0.04 | - | 0.07 | 0.00 | drift 0.00, car after 0.01 |

Starts are in the door mark's frame (studs sideways, studs out from the car, turn from facing it):
straight-out-4 (0, 4, 0), straight-out-4-away (0, 4, 180), close-0.9 (0, 0.9, 0), close-away-0.6
(0, 0.6, 180; a turned head cannot stand nearer the car), angle-45 (2.8, 2.8, 90), beside-front-4
(-4, 1, 90) and beside-rear-4 (4, 1, -90), both inside the walk's margin round the car, far-5.5
(0, 5.5, 0), front-corner (-7, 2, 90), rear-corner (7, 2, -90), far-side (0, -14.6, 0).
Abuses: DoubleE presses twice 0.15 s apart; ResetWalk resets the character 0.35 s into the walk;
ResetSequence 1 s into the sequence; KeysDuring sends Door, Start, Exit, Enter, Door, Cancel 0.4 s
apart during the sequence.
