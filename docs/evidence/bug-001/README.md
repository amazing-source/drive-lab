# BUG-001: evidence (#266)

Systems agent, 2026-11-01. DriveSim on the keyboard's input help; no Studio, and no runtime log of the stuck state
exists (the coordinator checked: no script errors in today's Studio log, and the newest Player log on this PC predates
the report).

## Reproduction attempt

`fuzz.luau.txt` (the scratch script, kept for the record) drove 900 random sequences: 300 each on the DR458, SVJ and
Boss 302. Each one held Space, S, W and the steering for 0.1 to 1.5 s in every order, pressed a paddle mid-segment,
and ran in auto or manual. Then nothing was held for 6 s. **None stuck.** The drift ended, the smoke read 0, the
steering centred, and nothing was NaN; every frame ran inside a pcall and none raised an error.

The model's drift is bounded by design: engagement falls to 0 over 0.5 s once Space is let go, and the exit lasts at
most 1.5 s. So the stuck state is most likely outside the model, in the Play glue. If a frame's drive stops running
(an error every frame, for example), the car keeps its last forces, which feels like still steering, and its last slip
readouts, so the smoke never stops. That matches both symptoms. It is not proven.

`hold_space_s.luau.txt` found one real Space+S defect on all three cars. Held at a stop, S selected reverse after 0.3 s
and then, swapped to the accelerator, drove the car backwards with the handbrake held: the DR458 reached -38 km/h,
the SVJ -14, the Boss -12. Fixed here.

## What changed for the SVJ and DR458

Only this input: the handbrake (Space) held at a standstill in automatic, on the keyboard's or pad's preset, with
- the brake alone held for the reverse hold: it no longer selects reverse; or
- in reverse, the accelerator alone held for the hold: it no longer selects first.

Every game tool's output is otherwise identical (`tools_compare.txt`), and the 4,862-frame trace keeps its hash
(`7f2eee0a…`).

| File | What it is |
|---|---|
| `breaks.txt` | The four guarded rules broken one at a time; each fails a spec |
| `tools_compare.txt` | Every tool on main and on this branch |
| `fuzz.luau.txt`, `hold_space_s.luau.txt` | The reproduction scripts |
