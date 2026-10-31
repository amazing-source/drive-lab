# Drift on Space: functional Play check (#136)

Solo Play in the owner's place, 2026-10-31, 02:45-02:56, Studio lock held by the systems agent, no
network simulation. Synced from a local worktree that merges this branch (the drift law of #139,
the wiring of this PR), main 5d207ad and the tyre audio of #141. The first sync wrote 16 and
removed 0; the second wrote 0. Keys came from Studio's simulated keyboard (MCP
`simulate_keyboard_input`), not a physical keyboard: E at the door, then R to start, W, S, D and
Space.

A client probe (session only) logged the driven car every 0.1 s:
- the attributes `SpeedKmh`, `Gear`, `Drift`, `DriftTarget`, `Steer`, `TyreSlipRL`, `TyreSlideRL`,
  `Brake` and `EngineLevel`;
- the body slip, measured from the chassis's velocity against its heading;
- the four tyre `AudioPlayer`s' volumes (`*` = playing).

Afterwards the place was synced back to main 9840f2e from a clean worktree: the first sync wrote 9
and removed 3, the second wrote 0. Nothing was saved.

## Results

| Check | Keys | Result | Lines from the log |
|---|---|---|---|
| The SVJ drifts at 80 km/h | W 2.5 s, D held, Space 1.5 s, D released | PASS. Engaged in 0.2 s; held 24.9-28.2° against its 25° target, the assist countersteering; faded out in 0.5 s on release; back under 3° in about 1.3 s, with no slide the other way | `t=28.41 v=79.6 g=3 drift=0.23 tgt=25.0`; `t=29.47 v=61.0 drift=1.00 tgt=25.0 steer=-0.66 slip=-28.2`; `t=29.91 drift=0.89 tgt=0.0`; `t=31.19 drift=0.00 slip=-0.2` |
| The DR458 drifts at 76 km/h | the same | PASS. Engaged in 0.2 s; peak 30.0° against 28°, held about 27°; faded out in 0.5 s | `t=27.57 v=76.3 drift=0.40 tgt=28.0`; `t=28.42 drift=1.00 steer=-0.90 slip=-30.0`; `t=28.97 slip=-27.1`; `t=29.39 drift=0.17 tgt=0.0` |
| Space below 30 km/h with the wheel turned is the handbrake | D held, Space 1 s at about 6 km/h | PASS. No drift; the rear locks | `t=52.31 v=4.1 drift=0.00 steer=0.76 rl=7.33` (combined slip; a lock reads about 10) |
| Space with the wheel straight is the handbrake | Space 1 s at 37 km/h | PASS. No drift; the rear locks and the car slows | `t=81.23 v=30.7 drift=0.00 steer=0.00 rl=12.41/8.5`; `t=81.87 v=22.1 rl=12.44` |
| The tyre audio plays, capped by the engine (#141) | the drifts above | PASS, with one small excess. The squeal comes in first, the skid as the slip passes about 2. All four loops together sit at the ceiling, `EngineLevel` × 10^(−4.9/20). A lock plays mostly skid. In the sample quoted, the loops add up to 0.278 against a cap of 0.276, 0.06 dB over. Two possible causes, neither investigated: the log rounds to three decimals, and the tyre controller may read the `EngineLevel` that `CarAudio` wrote a frame earlier | SVJ `t=29.36 eng=0.485 tyres=0.204*,0.189*,0.000,0.000`; straight lock `t=81.44 tyres=0.068*,0.125*` |
| `EngineLevel` is published | engine on | PASS: 0.251 at idle, up to 1.000 flat out | `t=23.78 eng=0.251`; `t=37.61 eng=1.000` |

No script error appeared in the runtime log during the session (only asset-type warnings and
plugin messages that predate it).

## What went wrong in the session

- **The first run crashed the SVJ.** Each simulated key call takes seconds, so "W for 4 s" became
  190 km/h, and the drift was held with D on a straight road. The car curved right off the road at
  about 170 km/h and 26°, hit the terrain beyond and tumbled. From that point the wheels read slip
  and slide 0 (off the ground) and the speed jumped between samples (173 → 100 → 67 km/h). The
  character ended 155 studs right of the road's line, on terrain grass. Up to the crash, the drift
  engaged and held as in the runs above: `t=41.14 v=172.2 drift=1.00 steer=-0.87 slip=-25.5`.
  The later runs used exact key holds (`tap` with a duration) and braked at once.
- **In the second run the car coasted off the edge of the terrain** after the drift, while my calls
  ran, and fell. The session was restarted for the DR458.
- Holding S at a standstill selects reverse, as it should, so after the low-speed check the car
  backed away until W braked it.

## Observations for the owner (feel, not failures)

- Braking with S straight out of a drift kept the DR458 sliding at 17-26° until it stopped
  (`t=30.06 v=37.1 drift=0.00 slip=-17.6 brk=0.08`). The brakes take the lateral grip the exit
  needs, and the drift's assist has faded by then. It stopped straight, with no spin.
- Coasting through a drift without the throttle costs speed: 76 → 52 km/h over 1.5 s on the
  DR458, and 80 → 59 km/h on the SVJ.
- The visual steering follows the assist (`Steer` reads −0.6 to −0.9 while drifting right), so the
  steering wheel and the driver's arms countersteer by themselves.

## Not checked in Play

- A gamepad (ButtonX, the analogue stick and triggers).
- A left-hand drift, and the S-bend switch; both are covered offline in `tests/Drift.spec.luau`.
- Wet roads, other surfaces, and frame-rate effects in Roblox.
- The sound itself: volumes and playing states were read, nothing was listened to.
