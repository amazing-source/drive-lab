# Boss 302 driver's door: evidence (#217)

Every check below ran on the Blender bake of its timeline (`tools/blender/car_entry_scene.py bake`),
not on the solver's preview, in the authoring frame at driver scale 1.15 against the Boss scene
(`car_entry_prep_manifest.py` on the 3D agent's cockpit dump, mark right -1.00 / forward -0.80, the
sill split into its own group).

| File | What |
|---|---|
| `allow_<timeline>.json` | The named contacts the check allowed, each at its measured depth (rounded up at the fourth decimal) with its decision |
| `check_<timeline>_blender_house.json` | `car_entry_check.py --json` on the bake, every group a part touches |
| `check_<timeline>.txt` | The same run's summary, then the same bake with a deliberate break (`--mutate pelvis_y=-0.6@F0-F1`), which must fail |
| `palm_check_<timeline>.txt` | `boss_palm_check.py`: every held palm against its own target point, limit 0.1 stud; on the bake, then on table v5, where it must fail (see below) |
| `<timeline>_table.json` | The solved table (tracker, limb planner, polish) the bake was built from |
| `*_quarter_speed*.mp4` | Quarter-speed renders (`render --stretch 4`), third person and the cockpit eye |

## The palm check, and why it exists

`car_entry_check.py`'s `touch` rule asks only that an arm's end come within the gap of a contact's
GROUP. An arm lying along the door card meets that with the palm nowhere near the pull. During this
work a name clash in the keys module (the entry's door-pull point and the DR458 exit's OutsideClose
frame were both `CLOSE_PULL`) put GetIn's ride target 2,400 studs away while the limb plans ran; the
table they produced (v5) held the left palm 1.7-2.2 studs off the door's pull for the whole ride, and
the house check passed it. `boss_palm_check.py` (in the asset folder's `boss302/anim/scripts/`)
measures each held palm (`r6_fk.HAND` on the posed arm) against the very point the keys module holds
it on, and fails on table v5 (`palm_check_entry.txt`, second run, exit 1) and passes on the bake.

## Results

| Timeline | Clips | Per-group check on the bake | Break | Palm check |
|---|---|---|---|---|
| entry | OutsideOpen 2.8 s, GetIn 5.633 s | 0 failures | 360 failures | 4/4 PASS |
| close | InsideClose 1.6 s | 0 failures | 217 failures | (no hold) |
| seated | SeatedPose 1.0 s | 0 failures | 279 failures | (no hold) |
| exit | InsideOpen 2.067 s, GetOut 5.433 s, OutsideClose 10.267 s (exitEnd at 8.7 s) | 0 failures | 433 failures | 2/4 PASS; the two bolster holds FAIL (known issue below) |

Known issue, accepted by the coordinator and left failing in `palm_check_exit.txt`: getting out, the
palms reach the bolsters three frames after the feet land (gap 0.152 / 0.178 stud on f123, about 0.09 on
f125, 0.02-0.06 on f127). The limb planner quantizes a held aim to its 6-degree cells, and the bake's own
aim converges over three frames from the drop's pose.

## Not in this folder

The scene, the bakes, the exports and the scratch solvers live in the asset folder (`boss302/anim/`),
not in the repo, as for the DR458.
