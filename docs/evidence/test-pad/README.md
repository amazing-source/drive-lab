# Pad layout: offline evidence (#183)

No Studio: agents no longer use it (owner, 2026-10-31); the owner tests by playing.

## Other layouts unchanged

`compare_layouts.luau`, run from a copy of `games/drive-lab/src/shared` taken from origin/main
(561bb71) and one from this branch: 109,854 values byte-identical (sha256 prefix
269eadc47237d422e9b9 for both). It covers:

- the endless road, bends on and off, and the default curvature;
- guardrail pieces, delineators, gantries, road marks and lamps over 40 km;
- the circuit's points every metre, its bridge spans, keep-out zones and approach guardrails;
- its field tiles.

The server's Circuit, Straight and Bends paths are untouched: the Track service gains one branch
at the top of `start()` for "Pad". The comparison was shown failing on a deliberate break (the
circuit's tile overlap 2 -> 2.5 m: differs at line 109,834).

## Cost at server start (counted offline, time estimated)

- Paving: 16 terrain fills, 0.640 km2 (0.659 km2 counting the overlaps), about 6.9 M terrain
  cells at 6 voxel layers for the 4 m depth. Laid synchronously in `start()`, before Cars rigs
  the parked cars.
- Lines: 210 parts (189 circle chords, 2 straight pieces, 7 cross marks, 12 run-off edge
  pieces), laid a frame later.
- Time: **estimated, not measured.** #170 measured in Play 0.43 s for the circuit's field and
  start pad, 0.95 km2 in 30 fills. Scaled by area, this pad would take about 0.3 s. The server
  logs both times (`[Pad] paved in ... s` and `laid ... lines, ... s after start`), so the
  owner's first Play gives the real numbers.

## The paint and the car's physics

`VehicleRunner` casts each wheel's ray with `RaycastParams` set to exclude the car, in the
wheels' collision group, ignoring water; it does not set `RespectCanCollide`. Such a ray skips a
part only when the part's `CanQuery` is false, which Roblox allows only for a part with
`CanCollide` false. The lines carry both (and `CanTouch` false) from `Config/Pad.STRIPE`, which
the server applies as it is and `tests/Pad.spec.luau` checks. They sit 5 mm above the measured
surface, 10 mm thick: clear of z-fighting, and with no collision there is no bump to feel.

## Breaks

`mutations.txt`: each break applied to the committed branch, run through the specs, restored.
