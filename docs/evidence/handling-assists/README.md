# Handling assists: evidence (#158)

Systems agent, 2026-10-31. Offline on `tools/DriveSim`; the method, the design and the research are
in `docs/research/14_game_handling.md`.

| File | What it is |
|---|---|
| `handling_30fps.txt`, `handling_60fps.txt`, `handling_120fps.txt` | `lune run games/drive-lab/tools/handling.luau <fps>` on this branch: each notch on both cars, events in a held corner, catches, step steer and lane change, with the assist's peak share |
| `prototype_30.txt`, `prototype_60.txt`, `prototype_120.txt` | The scratch prototype at the plan's values (Forgiving's yaw start still 0.25), for the plan's numbers. The harness reproduced the tool's Realistic numbers exactly. |
| `realistic_identical.txt` | Every game tool run on main 5a8853e and on this change with no level set: all outputs identical except calibrate's wall-clock timing line |
| `play_partial.md` | A partial Play session stopped by the owner's no-Studio rule. Key 2 and the HUD flash passed from the probe's log; the slide test was void (the car fell off the world's end, #99); no script error |
| `mutations.txt` | Thirteen deliberate breaks, each with the specs that failed and their lines; every file was restored from git after its run |

## Per-frame cost

`DriveSim.frame` (the model's step and the body's integration), 600 frames at 60 FPS, median of 7
runs, Realistic against Forgiving.

| Run | Car | Realistic | Forgiving |
|---|---|---|---|
| A 20° slide being caught (assist acting) | SVJ | 308 µs | 294 µs |
| | DR458 | 411 µs | 436 µs |
| A gentle steady turn (assist idle) | SVJ | 327 µs | 355 µs |
| | DR458 | 442 µs | 440 µs |

The differences go both ways and sit within run-to-run noise. The assist adds a few trigonometric
calls and one yaw reference per frame, beside the model's 240 Hz substeps.

Studio script time was not profiled.
