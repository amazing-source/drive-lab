# Test circuit: Studio checks (#162)

Owner's place, 2026-10-31 14:12-14:30, Studio lock held by the systems agent. Before every Studio
action: `get_studio_mode` "stop" and `get_connected_instances` with the edit peer only. Synced from
this branch merged with origin/main 1dbf269 (15 written, 219 unchanged, 1 removed). Afterwards the
place was synced back to the main clone (5a8853e): 12 written, 4 removed (this branch's four new
modules), then a second sync writing 0. Nothing was saved.

No DataStore or MemoryStore call exists in `games/drive-lab/src` or `kit/src` (searched before
Play), so the playtest could write none.

## Edit mode: the circuit laid by the synced Track service

`ServerScriptService.Server.Services.Track.start()` called from the command context
(`studio_lay` in the PR), the baseplate renamed so the service kept it and hidden so the river
showed. Restored afterwards: the 6 laid folders destroyed, `Terrain:Clear()` (the place had no
terrain before: `CountCells` 0, checked first), the baseplate's name, transparency, CanQuery and
CanCollide, the camera's CFrame.

- `start()` returned after 1.15 s (field and pad); 10,295,906 terrain cells; the log: "circuit
  2859 m in 5 chunks, 2 bridges, start line at 153.14, 0, 173.24; field and pad in 1.15 s",
  then "circuit laid 4.68 s after start".
- Edit mode runs no physics step after a fill, so the pad's surface raycast found nothing
  ("could not find the pad's surface"): lane lines and parapet tops were placed with a lift of
  0 there, under the surface. In Play the lift was measured (below).

### The deck raycast grid (`studio_deck_grid.luau`)

Rays straight down onto terrain (water ignored), from 12 m before each deck to 12 m after it:

| | Bridge 1 (deck s 1045.8-1089.8 m) | Bridge 2 (deck s 2327.0-2371.0 m) |
|---|---|---|
| Road's full width, ±5.5 m, every 0.5 m | 3,151 rays, 0 holes | 3,151 rays, 0 holes |
| Inside the edge lines, ±5.0 m, every 0.25 m | 11,193 rays, 0 holes, all at y 2.000 studs, largest step between neighbours 0.0 mm | the same |
| Wheel paths (±0.85, ±1.75, ±2.65 m) | 2.000 to 2.000 studs | 2.000 to 2.000 studs |
| At the very edge, ±5.5 m | down to 1.587 studs (77 mm low), steps up to 39 mm: the terrain's 0.75 m voxels rounding the edge | the same, 1.571 |
| Under the deck at the crossing | water at y -16.08, mud bed at -24.78 | the same |
| 30 m along the river | water at -16.08 | the same |

Road elsewhere on the lap (s 100, 300, 640, 1200, 1700, 2600): asphalt at y 2.000 studs.

### Captures (edit mode, lift 0, so no lane lines and low parapets)

- `edit_bridge1_from_upstream.jpg`: the river under bridge 1, the deck's shadow, lamps beyond.
- `edit_bridge1_deck_parapet.jpg`: the deck over the channel with its concrete parapet from bank
  to bank.
- `edit_bridge2_driver_approach.jpg`: the road running level into bridge 2 at eye height, an
  approach guardrail on the left verge.
- `edit_hairpin_above.jpg`: the R25 hairpin, its lamps and outer guardrail, the field's edge
  100 m beyond, the river top right.
- `edit_paddock_cars_beside_main_straight.jpg`: both cars on the concrete pad, the main straight
  to their right.

An overview from 620 m up was washed out by the place's Atmosphere haze; the lighting was left
alone.

## Play (solo, muted)

Muting, session only, in the client: every SoundGroup held at volume 0 at RenderPriority.Last,
every Sound without a group put in a muted group, the AudioDeviceOutputs detached. The PC's volume
was not touched.

Server log: "field and pad in 0.43 s" (synchronous, before Cars rigs the cars), "circuit laid
5.02 s after start". No pad warning: the lift was measured. Then: 5 TrackLines folders (1,699
children), 4 parapets with their tops at y 6.82 studs = the 2.000 surface + 0.9 m, a lane line's
top at 2.075, no Baseplate, no RoadEnd, 10,325,758 terrain cells. The SVJ parked 20.0 m left of
the centre line at s 30 m, on the pad's concrete.

### The whole lap's surface (server, Play)

Every 1 m of the lap, lateral -4.5 to 4.5 m every 0.75 m: 37,167 rays, 0 holes (straights
25,051, arcs 12,116). 25 rays lay more than 0.01 studs off the 2.000 surface (lowest 1.865, 2.5 cm
low) and 70 hit Grass: all at ±4.5 m (the outer half-metre of a lane, inside the edge lines),
on the arcs (the voxels rounding each step's block) and on the straights exactly every 200 m.

**The 200 m ones were a defect of this branch, fixed in 0bc40f8.** They were the field's tile
seams: tiles that only met left a groove along each seam, up to 0.9 studs (17 cm) deep in the
grass (lowest y 1.102 against 2.000) and a dip of up to 0.86 studs in the river's surface. A fill
only raises a voxel's occupancy: an off-grid 10 m grass fill inside solid field left no mark
(lowest 2.000), and a 20 m fill straddling the seam at along 200 m healed it (1.102 to 2.000). The
tiles now overlap by 2 m. Re-measured after the fix: see the end of this file.

### Driving (keys from Studio's simulated keyboard)

The SVJ was seated with `Seat:Sit` on the server and given the state a finished entry leaves
(`Entry` "Enter", `EntryAt` 60 s back); R started it through the normal start (`Engine` On). A
client probe logged the car every 0.1 s: arc length and lateral offset from the centre line, the
chassis height and vertical speed, its up vector, `SpeedKmh`, `Gear`, `Throttle`, `Brake`,
`Steer`, and what a ray under the car hit. The car was placed on the road by `PivotTo` on the
client, which owns it.

| Run | Result | From the log |
|---|---|---|
| SVJ over bridge 1 (W 6 s from rest at s 960, then S) | PASS: on the deck at 128 to 146 km/h, asphalt terrain under it throughout, lateral 1.75 m all the way | `t=95.3 s=1048.0 y=4.428 v=128.4`, `t=96.4 s=1090.0 y=4.467 v=146.5` |
| Deck ends felt by the car | No feature told apart from the car's own motion: the chassis bobbed ±0.17 studs (about 3 cm) at about 3 Hz from s 987, 60 m before the deck on plain road, under full throttle with the throttle pulsing in 2nd, and kept the same amplitude across both deck ends | `s=1000 y=4.216`, `s=1006 y=4.570` (before); `s=1044 y=4.315`, `s=1048 y=4.428` (deck start); `s=1085 y=4.515`, `s=1090 y=4.467` (deck end) |
| SVJ into the R120 | FAIL of the check, not of the road: my next key call came about 5 s late, the car ran straight on at 76 km/h onto the grass outside the bend | `t=151.4 s=1383.0 lat=-14.54 v=56.1 under=Grass` |
| SVJ through the R25 hairpin, attempt 1 | Turned in 20 m early and too hard (Steer 0.2-0.6), left the road on the inside before the apex at 32 km/h | `t=318.5 s=594 lat=4.64 under=Grass` |
| SVJ through the R25 hairpin, attempt 2 | On the arc on asphalt from its start to s 617 at 38-28 km/h (lateral -1.9 to -3.9 m), then a glancing hit on the outer guardrail (two section colliders found there) that stopped it on the road | `t=343.0 s=601 lat=-1.94 v=38.2`, `t=345.0 s=617 lat=-3.86 v=28.3`, `t=345.3 v=6.6` |
| DR458 over bridge 2 | NOT DONE. Seated the same way, its engine started (`Engine` On, start-up "Running", door closed, `drivable` true), but it never moved: it read `Throttle` 1.00 at rest with no key held from the first sample after it was seated (s 30 m, lateral +40 m: not where its spawn stands, -16 m, and why was not established), and W did nothing; S selected R and it read -1222 rpm at 0 km/h. Not anchored, owned by the player. E beside its driver door did not start an entry either. Cause not found; the shortcut seating is the first suspect | `t=400.6 s=30 v=0.0 g=1 thr=1.00`; `t=423.2 g=-1 thr=1.00` |

Driving through the bends with simulated keys proved coarse: each key call is a separate tool
call, so steering is pre-planned rather than closed-loop. The bends' surface is covered by the
whole-lap grid above; how the cars drive them is for the owner's Play.

No script error from the game appeared in the session's log (only a third-party plugin's
warnings).

## Seams after the fix (0bc40f8)

Pending: re-measured in a second short Studio session.
