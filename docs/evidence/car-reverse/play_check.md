# Reverse in automatic: functional Play check (#67)

Solo Play in the owner's place, 2026-10-29 11:49-11:56, Studio lock held by the systems agent.
Code synced from `.worktrees/car-reverse` (first sync 7 written, second 0). No network
simulation (all zeros before and after). Keys from Studio's simulated keyboard (MCP
`simulate_keyboard_input`), not a physical keyboard. Getting in: E at the door prompt; R started
the engine; the checks began once `Rules/CarEntry.drivable` was true. Drive mode Strada (the
default).

A client probe (session only, not committed) logged the car's attributes every 0.1 s and at each
gear change: signed speed along the car (m/s, + forward), Throttle, Brake, Rpm, GearboxMode, the
HUD's gear text, the cluster's gear text, the left reversing lamp's EmissiveStrength (`revE`) and
its night spot light (`spot`, off by day by design, `Effects/CarLamps`).

## Results

| Check | Keys | Result | Line from the log |
|---|---|---|---|
| R engages at a standstill, automatic | S held 1 s | PASS: R about 0.3 s after S went down, at 0.00 m/s; HUD and cluster R; lamp lit | `GEAR 1->t=4.92 g=-1 v=0.00 brk=0.84 mode=auto`; `t=5.06 g=-1 hud=R cl=R revE=8.0` |
| In R the brake key drives backwards | S still held | PASS | `MARK A release S t=6.01 g=-1 v=-6.19 thr=1.00 brk=0.00 rpm=5000` |
| In R the accelerator key brakes, then D comes back at a standstill | W held 2.5 s from -3.9 m/s | PASS: braked to a stop, D at 0.07 m/s, then forward to 22 m/s; HUD and cluster 1; lamp off | `t=11.17 g=-1 v=0.15 brk=1.00`; `GEAR -1->t=11.35 g=1 v=0.07`; `MARK B release W t=13.73 g=1 v=21.92 revE=0.0` |
| No R while rolling forward | S held from 19.1 m/s | PASS: only braked, the automatic stepped 6 to 1; R at -0.03 m/s after the stop | `GEAR 2->t=19.45 g=1 v=5.75`; `GEAR 1->t=20.19 g=-1 v=-0.03` |
| Manual: S at a standstill only brakes | T, then S held 1.5 s in R and in 1 | PASS: brake 1.00, gear unchanged both times | `t=43.50 g=-1 brk=1.00 mode=manual`; `t=50.12 g=1 brk=1.00 mode=manual` |
| Manual: Q and E unchanged | E, E from R; Q, Q from 1 | PASS: R, N, 1 and 1, N, R; HUD and cluster N and R | `GEAR -1->...g=0`, `GEAR 0->...g=1`; `GEAR 1->...g=0`, `GEAR 0->...g=-1` |
| Manual R: W drives backwards, S brakes | W 0.6 s, S 1.2 s | PASS | `t=53.28 g=-1 v=-2.79 mode=manual`; `t=54.55 g=-1 v=0.05 brk=1.00` |

Screenshot in manual R at a standstill, by day: `play_manual_R_reversing_lamps_hud.jpg` (HUD
shows R and M; the two clear chevrons lit).

## Reverse's top speed (#70), second session

Solo Play, 2026-10-29 12:12-12:15, lock held, no network simulation. Synced from a local check
branch merging `agent/car-reverse` and `agent/world-road-end` (the barrier, #69) on main 7854a3b
(first sync 12 written, second 0); the check branch is not pushed. Same probe, plus position.

| Check | Keys | Result | Line from the log |
|---|---|---|---|
| No R while braking from speed | W 3.5 s (to 105 km/h), then S held | PASS: the box stepped 4 to 1 under braking; R at -0.04 m/s after the stop | `GEAR 1->t=9.64 g=-1 v=-0.04 m/s` |
| Reverse tops out under 40 km/h | S still held, 12 s | PASS: steady at 39.2 km/h from 1.7 s after R until the barrier, never above | `MAX BACKWARDS: v=-10.88 m/s (-39.2 km/h)`; `t=21.62 g=-1 v=-10.88 m/s` |

The car then met the barrier at the cap: see `docs/evidence/road-end/play_check.md` on the
barrier's PR.

## Seen on the way (follow-ups, not changed here)

- A first run held S for 3 s: the car reached 28 m/s backwards and, coasting on, left the road
  behind the spawn and fell out of the world (seat at y = -7425, upside down). Issue #69.
- Reverse has no speed cap besides the limiter (90 km/h backwards in 4 s in DriveSim). Issue #70.
