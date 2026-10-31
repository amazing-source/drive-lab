# Tyre squeal and skid: functional Play check (#136)

Ran in the same solo Play session as the drift's check, in the owner's place, 2026-10-31
02:45-02:56, with the Studio lock held. The place was synced from a local worktree merging #144
(the drift wiring), #139's drift law, main 5d207ad and this branch at 42509d2. Afterwards it was
synced back to main 9840f2e (second sync 0 written) and not saved. The full write-up is
`docs/evidence/drift-wiring/play_check.md` in #144. A client probe logged every 0.1 s the
`EngineLevel` attribute and the four tyre `AudioPlayer`s' volumes, in the order RearSqueal,
RearSkid, FrontSqueal, FrontSkid (`*` = playing).

| Check | Result | Lines from the log |
|---|---|---|
| `EngineLevel` is published by `CarAudio` | PASS: 0.251 at idle, up to 1.000 flat out | `eng=0.251`; `t=37.61 v=163.2 eng=1.000` |
| Silent under the limit | PASS: all four at 0.000 at a steady 80 km/h | `t=28.31 v=79.9 eng=0.818 tyres=0.000,0.000,0.000,0.000` |
| The squeal comes in at the limit, then the skid | PASS. The squeal is first, at rear slip 1.2 to 1.9; the skid follows past slip 2 | SVJ `t=28.72 rl=1.23/3.3 tyres=0.082*,0.000`; `t=28.92 rl=2.53/6.5 tyres=0.322*,0.028*` |
| Capped by the engine, car-wide | PASS, with one small excess. In the drift's steady part the four loops add up to the ceiling, `EngineLevel` × 10^(−4.9/20). The sample below is 0.278 against 0.276, 0.06 dB over; the log rounds to 3 decimals, and the controller may read `EngineLevel` a frame late. Neither was investigated | SVJ `t=29.36 eng=0.485 tyres=0.204*,0.189*,0.000,0.000` |
| A lock is mostly skid | PASS: the straight-line handbrake at 30 km/h, rear combined slip 12.4, plays skid 0.12 and squeal 0.07 | `t=81.44 rl=12.50/7.7 tyres=0.068*,0.125*` |
| Fades out when the slide ends | PASS: back to 0 within about 0.6 s after the slip falls | `t=31.19 rl=0.10/0.1 tyres=0.012*,0.000,0.022*,0.000`; `t=31.93 tyres=0.000,0.000,0.000,0.000` |

No script error in the runtime log during the session.

## Not checked in Play

- The sound itself: nothing was listened to. The mix, the cockpit shaping and the pitch are the
  owner's to judge by ear.
- The `Real` pack (only `Ac`, the default, was loaded).
- Performance of the controller per frame.
