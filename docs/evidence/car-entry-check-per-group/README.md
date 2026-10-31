# Car-entry check per group: the proof, and what it finds in the SVJ's shipped clips (#153)

## The blind spot

`car_entry_check.py` kept, for each part on each frame, only its deepest point and tested only that
point's group against the allow list. A shallower contact with another group was never tested: a
part allowed 0.22 into the seat and also 0.20 into the cage passed. `--per-group` tests every group a
part cuts into (each car group, the door, the ground) against that group's own allowance.

## Proof on synthetic scenes

`tools/anim/car_entry_check_spec.py`: one Right Leg box with flat patches cut into it at known
depths, the allow list letting it 0.25 into `seat` only.

| Case | Contacts | Deepest-only | Per group |
|---|---|---|---|
| masked_cage | seat 0.22 (allowed), cage 0.20 | passes | fails: cage 0.20 |
| masked_door | seat 0.22 (allowed), door 0.20 | passes | fails: door 0.20 |
| masked_ground | seat 0.22 (allowed), ground 0.10 | passes | fails: ground 0.10 |
| both_allowed | seat 0.22, cage 0.20 (cage allowed 0.21) | | passes |
| cage_under_tol | seat 0.22 (allowed), cage 0.03 | | passes |
| deepest_over | seat 0.22, cage 0.20, nothing allowed | fails: seat | fails: seat and cage |

Plus the default: an unlisted scene runs per group, a scene listed in `DEEPEST_ONLY_SCENES` runs
deepest-only. 12 expectations, all hold.

- `synthetic_old_vs_new.txt`: the masked cases through the checker before this change
  (`origin/main`, unmodified): exit 0, no failure; through the new one: exit 1 on the hidden group.
- `spec_and_breaks.txt`: the spec green, then red on four deliberate breaks of the new rule, each
  applied to a copy of the checker: per group testing only the deepest group (5 expectations fail),
  the default flipped (2), every group held to the deepest group's allowance (4), allowances
  ignored (10, the controls among them).

## The SVJ's shipped clips, per group

Bake 4, the clips in `Config/Cars/SVJ/Door.luau` (bake SHA-256s match `car-entry-anim/uploaded_ids.json`),
against the SVJ scene (`7710cfda47eb`) and each timeline's own allow list
(`car-entry-anim/allow_*.json`, unchanged). Studs at scale 1, tolerance 0.04.

| Bake | Frames | Failures, deepest-only | Failures, per group | Added by per group |
|---|---|---|---|---|
| entry (OutsideOpen, GetIn), `c87d988c6d6c` | 229 | 2 | 2 | **0** |
| exit (InsideOpen, GetOut, OutsideClose), `b49f73d623fd` | 307 | 16 | 16 | **0** |
| close (InsideClose), `a0a07820ae09` | 55 | 0 | 0 | **0** |
| seated (SeatedPose, extra; no allow list), `6ff702707f1e` | 31 | 0 | 0 | **0** |

The failures in both rules are the same foot slides already recorded in
`car-entry-anim/check_results_bake4.json` and uploaded under the coordinator's override on
2026-10-28 (entry f161; exit 16 frames between f107 and f304). No penetration failure appears.

Per group, the check tested 16 secondary contacts past the tolerance (a group that was not the
part's deepest on that frame), all within their own group's allowance:

| Bake | Part | Group | Frames | Max depth | Limit (allowance) | Margin | Deepest group there |
|---|---|---|---|---|---|---|---|
| entry | Left Arm | paint | 151 | 0.0453 | 0.150 (hands on the sill) | +0.105 | sill 0.0528 |
| entry | Right Arm | sill | 153, 154, 161 | 0.0656 | 0.150 (hands on the sill) | +0.084 | paint 0.0775 |
| entry | Torso | sill | 155-160 | 0.0723 | 0.100 (bottom on the lip) | **+0.028** | paint 0.0740 |
| entry | Right Leg | sill | 163, 166, 167 | 0.0732 | 0.1421 (thighs over the lip) | +0.069 | paint 0.1290 |
| entry | Left Leg | sill | 182 | 0.0486 | 0.1421 (thighs over the lip) | +0.094 | paint 0.0717 |
| exit | Right Arm | interior | 85, 86 | 0.0735 | 0.150 (hands on the wall and lip) | +0.077 | trim 0.0797 |

Why nothing new fails on the SVJ: each of the 16 falls under the same allow entry, at the same
limit, as that frame's deepest group (its entries list several surfaces together, such as sill,
paint, interior, carbon and trim for the hands), so the old rule held them to the same number
through the deeper contact. The closest to its limit is the bottom on the sill at entry f160.

- Deepest-only on the new checker reproduces the old checker exactly on all four bakes: the same
  failures and every row identical (`svj_compare.txt`).
- `svj_checks.txt`: the checker's own output for each bake under both rules.

## Reproduce

    python -I tools/anim/car_entry_check_spec.py
    python -I tools/anim/car_entry_check.py <v4>/entry.baked.json <scene.npz> --allow <v4>/allow_entry.json --per-group --json <pg>/check_entry.json
    (the same for exit and close with their allow lists, seated without one; then without the flag into <deep>,
    and with origin/main's checker into <old>)
    python -I docs/evidence/car-entry-check-per-group/compare_modes.py <old> <deep> <pg> entry exit close seated

The bakes and the scene are in `drive-lab-assets/anim/car_entry/v4/` and `drive-lab-assets/anim/car_entry/`
(outside the repo).
