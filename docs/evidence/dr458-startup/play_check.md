# DR458 start-up hands: functional Play check (#118, PR #146)

Solo Play in the owner's place, 2026-10-31, 03:23-03:31, Studio lock held by the start-up
animator. The place was synced from this branch merged with main 7f51219 (4 written, 218
unchanged). Keys came from Studio's simulated keyboard (MCP `simulate_keyboard_input`): E at the
DR458's door mark, V to the cockpit view, then R. Afterwards it was synced back to main 7f51219
from a clean detached worktree: the first sync wrote 3 and removed 1, the second wrote 0 of 221.
Nothing was saved. Every probe lived in the Play session only.

## Method

A client probe, run in the session only, read what was drawn each frame. It took the visible
right hand in `workspace.DriverArms`, recovered its wrist frame from the part and the paths'
mesh offset, and put the touch's contact point (`StartupPaths.TOUCHES`: the pinch point or the
index tip) in the world. It compared that with the touched point of the control part as the car
turns it: that point was taken in the control's own frame with the engine off, then followed on
the live part. It also measured the index tip's height over ENGINE START's face along its normal.

Three runs of the start-up (the engine set back to Off on the server between runs):
1. Sampled every 30 ms. A 0.48 s client stall (a screenshot taken during the run) skipped the
   toggle's window.
2. Every rendered frame, on `RenderStepped`.
3. Every rendered frame, at `RenderPriority.Last` (after every bound step): what is drawn.

## Results

| Check | Result | Numbers |
|---|---|---|
| Hand shapes on time | PASS | Rest; Point from 0.40 s (standing in for Pinch, not uploaded); Rest from 3.45 s; the grip from 3.88 s; on the wheel at 3.9 s (`wheelAt` 3.9) |
| The hand rides the master key while it turns (0.65-1.00 s) | PASS | at most 0.5 mm (runs 2 and 3, 25-28 frames) |
| The hand rides the ignition guard's edge (1.45-1.70 s) | PASS, with a one-frame offset (below) | 0.4 mm (run 1, 7 samples); 3.7 mm (run 2); 4.6 mm at 1.58 s, mid-lift (run 3, 19 frames) |
| The hand rides the toggle (1.85-1.95 s) | PASS, the same offset | at most 1.8 mm (runs 2 and 3, 7-8 frames) |
| ENGINE START pressed at 2.40 s and held | PASS | index tip on the face (0.0 mm) from 2.37 to 2.87 s, 3.5 cm off by 3.05 s |
| No script errors | PASS | only the asset-type warnings that predate the session |

**The one-frame offset.** The worst gap on each control is about one frame of its own motion:
- guard: 1.75 rad in 0.25 s, at 44 mm from its hinge, is 5.1 mm per frame (measured 4.6);
- toggle: 0.7 rad in 0.1 s, at 15 mm, is 1.75 mm (measured 1.8);
- key: the pinch point is close to the key's axis (measured 0.5).

My reading, from the source and not verified: `Controllers/CarDoor` turns a control by setting
its weld's `C0` in `PreRender`, and the part moves at the next step, while `Controllers/
DriverArms` places the hands with `BulkMoveTo` in the same frame. So a control is drawn one frame
behind the hand. The SVJ's flap goes through the same path.

## Not checked

- The arms. On main the DR458's driver uses the global scale and arm lengths, because PR #120's
  per-car fields are not merged. The paths were keyed for scale 1.15 and arms 1.25 + 1.13 studs.
  The arm controller therefore reaches with different shoulders and lengths than the bake
  assumed, and the arms are hidden in the cockpit view anyway.
- Captures from beside the panel. The car's camera controller overrides a scripted camera, so the
  only capture is from the cockpit view, where the panel and the key are below the frame.
- The Pinch hand (not uploaded) and the hand-over blend from getting in (PR #120's).
