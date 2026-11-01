# Boss 302 pops and flames: evidence (#258)

Systems agent, 2026-11-01. Offline, no Studio: everything here was run in Lune.

| File | What it is |
|---|---|
| `breaks.txt` | The nine deliberate breaks, applied one at a time; each one fails a spec, and all pass once restored |
| `identical.txt` | SHA-256 of every SVJ and DR458 audio tool output (audio_timeline in every mode and the fallback start-up, downshift_pops, control_sounds), base against branch |

## Why the Boss showed no flame (code read)

No car has a `flames` entry. The DR458's own was retired in #159, so `Rules/ExhaustFlames.share(nil, ...)` gives every pop a flame,
in every mode, and never looks up a mode name. The Boss's two `exhaustOutlets` reach `Effects/ExhaustFlames.fromOutlets`,
which mounts them on `model.PrimaryPart`, the chassis that `CarRig.build` sets. That is the same path the DR458 takes. Flames come one
per pop, so the Boss threw as few as it popped. `ExhaustFlamesBurst.spec` now runs that effect in Lune on a stand-in Boss (below).

## Pops per downshift, measured

The method is `games/drive-lab/tools/downshift_pops.luau` with its car list set to the Boss (a scratch copy that is not committed). It
brakes from 250 km/h in sixth, asks for a manual downshift every 0.6 s, and takes the mean of 5 seeds. It counts downshift pops
only, so the lift and upshift chances it does not see also rose: Normal's lift chance goes from 0.35 to 1 and its upshift chance from 0 to 0.6.

| Gearbox, mode | Base (Normal as Strada, floor 3,000) | Chances one mode up, floor 3,000 | Branch (floor 2,400) |
|---|---|---|---|
| auto, Normal | 1.0 | 2.36 | 2.96 |
| auto, Sport | 3.88 | 3.88 | 3.92 |
| auto, TracKey | 4.04 | 4.04 | 4.04 |
| manual, Normal | 0.72 | 1.0 | 2.8 |
| manual, Sport | 1.0 | 1.0 | 2.8 |
| manual, TracKey | 1.0 | 1.0 | 2.8 |

The H box's clutch-in lets the revs sag before the gear engages. The manual downshifts engaged at 2,467, 3,206, 4,035, 2,724 and
2,495 rpm. `Rules/ExhaustPops` drops a downshift that engages under the floor, so 3 of those 5 could never pop, whatever
the chance. The automatic downshifts engaged at 3,383 to 3,825 rpm in Normal, 4,772 to 5,582 in Sport and 5,338 to 6,188 in TracKey.
Floor sweep on the manual box, with the new chances: 2,600 gives 1.8, 2,400 gives 2.8, 2,200 gives 4.24 pops per downshift. The coordinator approved 2,400,
just under the lowest engage seen.

## The flames effect in Lune

`games/drive-lab/tests/ExhaustFlamesBurst.spec.luau` runs `client/Effects/ExhaustFlames.luau` from its file with Lune's
instances and datatypes on a stand-in Boss: a Model whose PrimaryPart is a Part named Chassis, posed off the origin and
turned 30 degrees. What it shows: two `ExhaustOutlet` attachments on the chassis at the binding's centres; each carries a jet, a
fireball and a flash, emits along its front, and faces back out of the car and a little up. A full-strength pop emits three jets and
two fireballs at both outlets in Normal, Sport and TracKey, and the flash goes out after its delay. The same outlets are kept for later pops.

What is a stand-in, and why:

- `ParticleEmitter:Emit` is an engine method that Lune does not implement. The spec implements it as a counter, so the spec
  shows that the effect asks both outlets to emit, not that the engine draws the particles.
- `Lighting` and `task.delay` are plain tables. Lighting is read only for a car with flames of its own, and the Boss has none.
- `CFrame.lookAt` in Lune 0.10.5 mirrors the look direction's z: toward +Z it returns the identity, which looks toward -Z. With
  Lune's own lookAt, both outlets faced into the car. The effect is given the engine's lookAt, built from `fromMatrix`,
  and a spec checks it against the definition and records Lune's fault.
- `CarRig.build` (it needs the car's meshes) and `Controllers/CarAudio`'s `pop` (it needs SoundService and RunService) are not run.
  The stand-in is the state the rig leaves, and the pop's call into the effect is the two lines the spec repeats.
