# Boss 302 H box in Play: evidence (#222)

Systems agent, 2026-10-31. Offline; no Studio. The Boss is not in the catalog yet, so nothing here could be played.

| File | What it is |
|---|---|
| `breaks.txt` | The 16 rules broken one at a time; each fails a spec |
| `tools_identical.txt` | Every game tool identical on the base and on this branch, except the wall-clock step cost lines |
| `svj_dr458_trace.txt` | 4,862 frames of SVJ and DR458 byte-identical on the base and on this branch |

## The clutch key, measured (Boss on DriveSim with the keyboard's input help)

The key is held from before the start, then let go after 0.5 s; the pedal comes up over 0.8 s.

| Throttle held | Result |
|---|---|
| 0 and 0.3 | stalls |
| 0.5 | pulls away, lowest 684 rpm, 31 km/h after 4 s |
| 1.0 (the keyboard's W) | pulls away, lowest 784 rpm, 67 km/h after 4 s |

With the pedal let up at once (the `direct` help a test robot uses), 0.5 is still enough. The ramp is there so the
keyboard's binary key behaves as a foot.

## Spec gaps found by the breaks, and fixed

- The model reading the raw key passed every spec. DriveSim's default help is `direct`, where no pedal ramps.
  The ramp spec now drives on the keyboard's help.
- The clutch row of the controls screen was two sentences and passed every spec. Only catalog cars are checked, and
  none offers the clutch. A spec now checks the row on a car with the feature switched on.
