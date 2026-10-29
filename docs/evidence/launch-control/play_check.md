# Launch control: functional Play check (#74)

Solo Play in the owner's place, 2026-10-29 12:33-12:36, Studio lock held by the systems agent, no
network simulation. Synced from `agent/car-launch-control` on main 0f68474 (first sync 19 written,
0 removed; second 0). Keys from Studio's simulated keyboard (MCP `simulate_keyboard_input`), not a
physical keyboard. Got in with E at the door, started with R; a client probe (session only) logged
the car's attributes every 0.1 s and every change of launch phase, gear, drive mode or ESC, with
the HUD's mode label and the cluster's label under the gear.

## Results

| Check | Keys | Result | Line from the log |
|---|---|---|---|
| Corsa and ESC off from the player's keys | M, M; G held 3.3 s | PASS | `t=13.95 mode=Corsa/auto`; `t=17.62 escOff=true hud=CORSA` |
| The brake alone selects no reverse while launch control can arm (automatic) | S held 1.5 s, stopped in first | PASS: gear stayed 1, launch Off | `MARK S held 1.5 s alone ... t=24.07 launch=Off g=1 brk=1.00` |
| Arms on the brake and full throttle | W added, S still held | PASS: Armed; the engine held 4,840 to 5,000 rpm; HUD LAUNCH, cluster LAUNCH | `CHANGE t=24.38 launch=Armed`; `t=25.78 launch=Armed rpm=4862 hud=LAUNCH cl=LAUNCH` |
| Lifting before the release cancels | W released, S held | PASS: Off; CORSA and ESC OFF back | `CHANGE t=35.14 launch=Off`; `t=36.94 launch=Off rpm=948 hud=CORSA cl=ESC OFF` |
| Re-arms | W again | PASS | `CHANGE t=37.22 launch=Armed` |
| Releasing the brake launches; traction control acts with TC switched off | S released, W held | PASS: Launching; TC active in 4 of the first 13 samples while ESC was off | `CHANGE t=39.09 launch=Launching`; `t=39.26 launch=Launching tc=true escOff=true` |
| The automatic shifts up during the launch (the coordinator's choice) | W held | PASS | `CHANGE t=41.48 launch=Launching g=2 v=21.83 m/s (79 km/h)` |
| The launch ends at 100 km/h; the displays go back | W held | PASS | `CHANGE t=42.26 launch=Off g=2 v=27.93 m/s (101 km/h)`; `t=42.35 hud=CORSA cl=ESC OFF` |

0 to 100 km/h in Play: about 3.2 s from the frame the launch began (39.09) to the sample at
100 km/h (42.25), at the probe's 0.1 s resolution. DriveSim gives 2.88 s for the same start
(`tests/Launch.spec.luau`); the gap is Roblox's physics against the offline integrator and was not
investigated. Feel and calibration are the owner's.

Capture, armed: `play_armed_launch_hud.jpg` (HUD: LAUNCH in the drive mode's place, gear 1, the
rev bar at 5,000 rpm, TC red because it is switched off; the brake lamps lit).

## Not checked in Play

- Manual: the launch with the driver's upshift (the automatic's own upshift rule does not run in
  manual, which existing specs cover).
- A gamepad's triggers (the launch needs the accelerator at 95 % or more).
- The cluster on screen: its label was read from the instance, not captured.
