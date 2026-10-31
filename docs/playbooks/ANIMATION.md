# Animation playbook

For the animator who makes the next car's driver animations: getting in and out, the door clips,
the seated pose, the start-up hands and the wheel gestures. The two cars so far took tens of
agent-hours (about 20 on the DR458, see [Time](#time)). This page says what moves each body part,
how the motion is made smooth, the recipe for a new car, where the hours went, and the traps
already paid for.

It sits on top of the pipeline guides and does not repeat their detail:
[R6 animation](../pipelines/R6_ANIMATION.md) (the rig, signs, keys, export),
[car entry](../pipelines/CAR_ENTRY_ANIMATION.md) (scene, timelines, checks, upload guard),
[driver hands](../pipelines/DRIVER_HANDS.md) (grip, start-up, thumbs, gestures),
[driver legs](../pipelines/DRIVER_LEGS.md) (trousers, shoes, footwell).
What the 3D model must give and keep stable is in
[the modelling playbook](MODELLING.md#hand-off-to-animation).

## How to read this page

- Each fact ends with its source and its kind.
- Kinds: **M** measured (a tool run, a check record, a Play check, a timestamp); **S** source read
  (read in the code at main `2f81def`, not run); **D** decided (by the owner or the coordinator);
  **J** judgement (an estimate or an opinion).
- Code paths are short: `Rig/...` and `Controllers/...` are under `games/drive-lab/src/client/`;
  `Rules/...`, `Config/...` and `Car/...` are under `games/drive-lab/src/shared/`.
- Notes live in `drive-lab-assets/dr458/work/` (outside the repo):
  [anim] `NOTES_animation.md` (sections T0-T13 for the entry, X0-X4 for the exit),
  [startup] `NOTES_animation_startup.md`, [gestures] `NOTES_animation_thumbs.md`,
  [checker] `NOTES_checker.md`, [polish] `NOTES_polish.md`, [cockpit] `NOTES_cockpit.md`,
  [handoff] `HANDOFF_entry_2026-10-31.md`. [coord] is `drive-lab-assets/COORDINATOR_HANDOFF.md`.
- Times are Paris time (UTC+1) unless marked Z.

## The driver in one picture

Three systems draw the driver. Know which one owns a body part before you touch it.

1. **Clips.** The blocky R6 plays KeyframeSequences while getting in and out, then a looped
   SeatedPose (`Rig/ClipPlayer`, `Controllers/CarEntry`). **S**
2. **Drawn limbs.** Once seated, the blocky arms and legs are hidden (Transparency 1). Custom arms
   and legs are drawn every frame from the live torso: arms to the grip, the start-up path or a
   gesture; legs to the pedals (`Controllers/DriverArms`, `Controllers/DriverLegs`). **S**
3. **Procedural layers.** The neck (`Controllers/HeadLook`) and the root (`Controllers/BodyLean`)
   get a turn written on the joint's `Transform`, on top of the clip (`Rig/JointLayer`). **S**

What runs when, in one frame:

| When | What | Where |
|---|---|---|
| Animator step | the clip at Action priority, moved back if it drifts over 0.08 s from the server clock; held 1/60 s before its end | `Rig/ClipPlayer` **S** |
| PreSimulation | neck and root layers: `Transform = turn * animated` | `Rig/JointLayer` **S** |
| PreRender | door and cockpit controls' weld C0 | `Controllers/CarDoor` **S** |
| RenderStep, Camera + 3 | drawn arms and legs, one `BulkMoveTo` each, after physics | `DriverArms`, `DriverLegs` **S** |

Consecutive clips are cut from one timeline, so they meet on the same pose and chain with no fade
(`CHAIN_FADE = 0`); the seated pose and the standing clips fade in over 0.15 s
(`Controllers/CarEntry`). **S**

## Body parts

### What drives each part

| Part | Getting in and out | Seated | On foot |
|---|---|---|---|
| Root, hips | `RootJoint` in the clip; the root is welded to the DriverSeat (SeatWeld) | SeatWeld + SeatedPose clip | `BodyLean` on `RootJoint` |
| Torso | one rigid box moved by `RootJoint`; no spine joint | same | same |
| Neck, head | `Neck` in the clip; standing variants leave it at rest | the clip's neck; `HeadLook` holds the head straight ahead | `HeadLook` on `Neck` |
| Shoulders | `Right/Left Shoulder` in the clip | blocky arm hidden; the drawn arm starts 0.2 studs inside the shoulder joint | walk/run clips |
| Upper arm, elbow, forearm | one rigid 2-stud box; no elbow | drawn sleeves on a two-bone reach (`Rules/ArmIK`) | clips |
| Wrist, hand, fingers | none (the box's end) | posed hand meshes, placed by a wrist frame; no finger bones at run time | none |
| Thigh, knee, shin | `Right/Left Hip` in the clip; one rigid box; no knee | drawn trousers on a two-bone reach from the hip toward the car's `kneeToward` | clips |
| Feet | the box's end | shoes on the pedals and the footrest; the pedals turn under them | clips |
| Pelvis cloth | none | one `Pelvis` mesh from the torso's bottom to the cushion | none |

Sources: `Controllers/DriverArms`, `Controllers/DriverLegs`, `Controllers/HeadLook`,
`Controllers/BodyLean`, `Rig/JointLayer`, [ENTRY §2-3]. **S**

### Joint classes: Motor6D or AnimationConstraint

- `Rig/JointLayer` accepts both and writes only `Transform`: an AnimationConstraint's C0 is read-only.
  Its header records every spawned avatar on 2026-10-27 as having AnimationConstraints. **S**
- `DriverArms` reads the shoulder point from a **Motor6D** named `Right Shoulder` / `Left Shoulder`
  under `Torso` (C0 read, never written). With any other class it builds nothing, and the blocky
  arms stay, with no warning. **S**
- The Play checks of #146 and #156 logged the drawn hands on the R6 player, so there the shoulders
  were Motor6Ds. **M** An R6 with AnimationConstraint shoulders is not tested.
- `DriverLegs` reads no joint: it places the hips from the torso's CFrame and `Config/DriverLegs.HIP`. **S**
- Edit-mode probes step the clips with `Animator:StepAnimations` ([ENTRY §8]). **S**

### Axes and signs

Roblox frame: +X right, +Y up, -Z forward. A joint's rotation is XYZ Euler in body axes
(`anim = T(loc) * Rz * Ry * Rx`, `tools/anim/r6_fk.py`). [R6 §1] **M** (Blender matched Studio to
0.0002 studs.)

| Joint | rot X + | rot Y + | rot Z + |
|---|---|---|---|
| limbs | swing forward | twist | right limb out, left limb in |
| RootJoint | lean back (forward is -) | turn left | lean left |
| Neck | nod up | look left | tilt left |

- A limb's angle in the world is its joint angle minus the torso's lean. [R6 §1]
- Pivots at scale 1, in the torso's space (`r6_fk.py`): Neck (0, 1, 0); shoulders (±1, 0.5, 0), at
  the arm's **inner** top edge; hips (±1, -1, 0), at the leg's **outer** top edge. **S**
- Points used for aiming: the palm (0, -0.85, -0.05) in the arm, the sole (0, -1, 0) in the leg,
  the pelvis (0, -1, 0) in the torso (`r6_fk.py`). **S**
- Aim limits (swing X, spread Z): arm -200..230, -130..130; leg -130..165, -85..85
  (`r6_fk.LIMITS`). **S**
- Torso turns are written as lean, yaw, roll about the body's own axes (`r6_fk.body_turn`; lean
  negative is forward, roll positive leans left). It has no lock at a 90° yaw; in Blender the
  RootJoint is keyed as quaternions, since the torso turns 270° on the way in. [ENTRY §3] **S**
- Drawn arms and legs use the seat frame: x right, y up, z back (`Config/DriverLegs`,
  `Config/DriverStartup`). Grip and gesture keys use the wheel's frame: x right, y up the wheel's
  face, z toward the driver (`Config/DriverArms`, `Config/DriverGestures`). **S**
- Pedal travel signs: the throttle negative, the brake positive, the binding's axis along the car's
  right. `Contract.footwellMismatches` checks the hinge within 1 cm, the axis and the signed travel.
  [anim, runtime PR] **M** (spec shown failing at `CarContract.spec:175`).

### Ranges that read as natural

| Part | Range | Source |
|---|---|---|
| Root on foot | lean ≤ 10° forward, ≤ 6° back, ≤ 18° roll; half-life 0.1 s, no spring | `Config/Lean` **D** |
| Root seated, SVJ | Roblox's upright sit, 2.0 studs (0.37 m) above the cushion, kept because the cockpit eye is tuned to it; scale 0.857 | [ENTRY §2] **M**, **D** |
| Root seated, DR458 | in the bucket on the backrest, raised 6 cm on a cloth fill, scale 1.15 (the owner's option D) | [anim step 1] **D** |
| Root, walk | one sharp two-frame drop at contact, slow rise; a 6° then 2° sideways roll read as waddling | [R6 §4] **D** |
| Torso, SVJ release from the seat | about 32° forward, 6° yaw, 4° roll, pelvis in the seat | [ENTRY §3] **S** |
| Torso, into a cage | facing the car, a 30-50° lean clears the bars; the key poses lean 55° and roll 55° inboard | [anim T1, T4] **M** |
| Body, per frame (DR458 tracker bounds) | pelvis 0.08 stud, torso 5°, neck 8° then 12°, limbs 14° | [anim T12] **M** |
| Head on foot | yaw ±70°, up 55°, down 50°, inside a human neck's range | `Config/Look` **S** |
| Head seated | straight ahead whatever the camera does; only the arms move | `HeadLook` header (owner, 2026-10-27) **D** |
| Elbows (drawn) | about 130-135°; 100° showed the wrists' cut ends; 116° meant arms too long | `Config/DriverArms`, [anim step 1] **D** |
| Arm lengths, studs at scale 1 | SVJ 0.82 + 0.77; DR458 1.25 + 1.13 | `Config/DriverArms`, `Config/Cars/DR458/Driver` **D** |
| Grip | SVJ 25° above 3 o'clock; DR458 10° with the thumbs over the spokes; bar tilt 10 (28 rejected), wrist turn -10 | [HANDS §3], [anim step 1] **D** |
| Hands on a turning wheel | follow to ±110°, then the wheel slides through them | `DriverArms.FOLLOW_LIMIT` **D** |
| Keyed wrist paths | stop above 96 % of the arm's reach | [HANDS §8c], `gesture_paths.REACH_SHARE` **S** |
| Legs (drawn) | thigh 0.46 m, shin 0.45 m; floored throttle at 96 % of reach | `Config/DriverLegs` **M** |
| Knees, DR458 | 121-124° on the brake, 132-139° on the throttle | [anim step 1] **M** |
| Right foot | throttle to brake in 0.18 s, the ball lifts 3.5 cm, the heel slides; lifting the whole foot raised the knee into the dash | `Config/DriverLegs`, [LEGS §5] **S** |
| Pedal travel | SVJ throttle -16°, brake +12° (5.8 and 4.0 cm at the ball of the foot); DR458 -0.18 rad, +0.10 rad | `Config/Cars/*/Driver` **S** |
| Blocky feet | slide ≤ 0.6 studs/s while within 0.025 of the ground | `car_entry_check.py` **S** |
| Smoothness (jerk, studs/frame²) | the walk's steps 0.1-0.6; pops of 1.6-4.5 read as snaps; the shipped DR458 exit: largest 1.11, p95 0.23-0.43; the entry's planned pass before smoothing: largest 1.3, p95 0.4-0.6 (the shipped entry's figure is not recorded) | [anim T12, X3] **M** |

### What goes wrong, per part

| Part | Symptom | Cause, fix (pitfall) |
|---|---|---|
| Root | the torso pops at a clip boundary | the root jumps between the mark and the seat; hide it behind idle frames at the mark (P13) |
| Root | seated legs 0.44 into the cushion | the solved body drifted off the seated pose; pin it (P8) |
| Root | a planted foot slides on a step | a hip hike that starts in one frame; reuse the shared walk (P9) |
| Torso | locks or flips near 90° yaw | Euler XYZ; use `body_turn` and quaternion keys (P14) |
| Torso | sides in the bucket's bolsters | a 0.43 m box in a 0.37-0.40 m bucket at 1.15; a named contact, 0.261 (P11) |
| Head | through the cage rail | the head must roll inboard, not duck (the wheel is there) (P1) |
| Head | two checkers disagree on the headrest | two head boxes (0.62 vs 0.6 × 0.625 × 0.6); name it at the house checker's depth (P6) |
| Shoulders | drawn arms never appear (possible, not seen) | no Motor6D shoulder (P31) |
| Upper arm | the arm snaps between two frames | an R6 arm reaches a point two ways; bound and plan (P4) |
| Elbow (drawn) | wrists' cut ends show, forearms vertical | arms too long for the shoulder-to-wrist distance (the SVJ at real proportions: 100°); size them on the real grip for about 130° (P22) |
| Hand | thumb hovers 2.5 mm off the spoke | aimed with a bone point; aim the skin (P20) |
| Hand | open fingers dip into the rim as they close | a discrete Rest-to-Grip swap; a named contact (P26) |
| Thigh | thighs into the sill or the bars | a rigid thigh hinged at its top edge; a named rigid-limb contact (P11) |
| Knee (drawn) | knee inside the console | bent straight out, and measured by one ray; measure the nearest surface (P30) |
| Feet | slide at a stand-up | soles land while the pelvis still travels; mirror the entry's lift-off (P12) |
| Pelvis cloth | air or box sides under the trousers | one mesh shaped to the SVJ's bucket serves both cars (see open items; the box sides were the SVJ's first version, [LEGS §3]) |

## How motion is made smooth

The smoothness comes from five things, in this order. Each one fixed a failure that is in the
pitfalls.

### 1. Author beats, solve every frame, key densely

- **Beats, not joint angles** (`tools/anim/beat_tracks.py`). A body is a few tracks: the pelvis
  point, the torso's lean, yaw and roll, the neck, a target per limb, the door's openness. A
  monotone cubic runs between beats: no overshoot, continuous speed. [ENTRY §3] **S**
- **Every frame is solved** (`r6_fk.aim`): each rigid limb is aimed at its target, the palm to a
  hand target, the sole to a foot target; a box foot stands on its corner. **S**
- **Support legs:** while a foot is planted, the pelvis height is solved from the straight legs, so
  feet neither dig nor slide. **S**
- **Holds on a moving point are solved per frame** (`car_entry_hold.py`): a no-elbow arm holds a
  point only while the shoulder is exactly 1.44 studs from it. Interpolated holds put the arm
  0.127 studs into the door. [ENTRY §3] **M**
- **Pushes on the car** go to the nearest surface point the arm can reach (`Car.on_surface`);
  out-of-reach frames are reported, never claimed. **S**
- **Dense keys:** every 2 frames, every frame inside contact spans; the SVJ's final bake keys every
  frame. Bezier, auto-clamped handles. [ENTRY §3], #39 **M**
- A beat may be a function of the frame (a hand riding the door), so hand and door are one motion. **S**

### 2. For tight cabins: track, plan, smooth, polish

Used on the DR458's cage. The SVJ did not need it. [anim T11-T13, X2-X3] **M**

| Step | Tool | What it does |
|---|---|---|
| Key poses | `drive-lab-assets/dr458/anim/scripts/keygrid2.py` (scratch) | grids each key pose per group, 0.02 under the caps: the body first, then each limb on its own (limbs never collide with each other in the check) |
| Body per frame | `tools/anim/car_entry_track.py` | pattern search from two centres (the authored pose, the previous frame moved by the authored step), within hard per-frame bounds |
| Limbs over the span | `tools/anim/car_entry_limbs.py` | dynamic programming over 6° cells, at most 2 cells a frame, a 60° window; held frames are fixed points |
| Smooth | `tools/anim/car_entry_smooth.py --passes 8` | 1-2-1 averaging, kept only where no group goes deeper |
| Repair, polish | `--repair 40`, `--polish F0-F1 --margin 0.003` | random or pattern moves on frames still past an allowance |
| Check | `car_entry_check.py` (per group) and `jitter.py` (scratch) | contacts per group; second difference per part |

Why this order: a per-frame search ranks contacts first, so it flips a limb onto its other branch
to clear one (pops up to 4.5 studs/frame²). Bounded frames stop flips, but a boxed-in limb then
gets stuck, since a search only looks one frame ahead. A path planned over the whole span goes
round in time. [anim T12] **M**

### 3. Mirror the exit from the entry

GetOut is GetIn's solved path played backwards: the beats share nearly the same spacing both ways
(seated to D2 10 frames, D2 to D1 8, T2 to C 6, T1 to T2 5). `car_entry_mirror.py` writes the exit
table's caged span from the entry table through the keys module's `MIRROR` list; the exit's allow
list is the entry's at the mirrored frames (`exit_frame()`). It took the exit from 72 house
failures to 31, then 10 and 0 after local re-plans and polishes, in about 1.5 h.
[anim X1-X3], PR #157 **M**

### 4. Checks that can fail, run on every pass

- `car_entry_check.py`: every R6 box against a 0.05-stud point cloud of the car, the door at that
  frame's openness, and the ground. Fails above 0.04 studs except where `allow.json` names a
  contact. **Per group** for every scene except the SVJ's (`DEEPEST_ONLY_SCENES`). [ENTRY §5],
  [checker] **S**
- `"touch"` entries require the contact: a hand "on" a surface must come within the gap. #39 **M**
- Named contacts sit at their measured depth, rounded up at the fourth decimal; none is widened to
  pass. [ENTRY §5] **D**
- Shown failing on purpose: `--mutate pelvis_y=-0.6` turns the DR458 exit and SeatedPose red.
  [anim X4] **M**
- Hands: `startup_check.py` and `gesture_check.py` sample the keys as the game samples them;
  with `thumb_check.py` they use fixed per-triangle samples and ray parity on closed meshes, and
  `--break` shows each failing. [HANDS §10-12] **M**
- Renders at quarter speed (`--stretch 4`), read before anything is called done. [ENTRY §6]

### 5. Play it back the way it was authored

- **Clips follow the server's clock** (`Rig/ClipPlayer`), so the door stays under the hand. **S**
- **The seated root:** each seated clip is the authored motion re-expressed against the welded root
  (`car_entry_export.py`); translations are authored at scale 1 and the Animator scales them with
  the character (0.857 measured). [ENTRY §2] **M**
- **The hand-over to the drawn arms** (DR458, decision D): GetIn ends on a seated pose whose blocky
  palms are in `Driver.handOver`. The drawn hands start there and ease to the resting pose over
  0.6 s (`Rules/StartupArms.settle`: smoothstep plus slerp; `Rules/CarEntry.handOverShare`). As an
  exit begins, the share runs back to 0 with the drawn arms still shown. 0.25 s would move the left
  hand 2.3 cm a frame. [anim T8], `DriverHandOver.spec` **M**
- **Gestures wait for the hand-over:** a hand takes gestures only once its share reaches 1
  (`StartupArms.onWheel`). [anim T12] **S**
- **Start-up hands** (`Rig/StartupHands`): wrist frames sampled from the keys (positions on a cubic
  through every key, rotations slerped), bent toward the live grip over the last 0.5 s; shapes
  swap while the hand moves (Rest to Point leaving the thigh, Point to Grip half way). [HANDS §8d] **S**
- **Gestures** (`Rules/HandGestures`, `Rig/WheelGestures`): forward while the input is held, or for
  `HOLD_MIN` (0.12 s on the DR458) after a tap, then back along the same keys; a press on the same
  hand waits in a queue of 3. Wheel-frame keys follow the wheel; seat-frame tracks blend onto the
  live grip over `gripBlend` (0.2 s). [HANDS §12] **S**

### Commands

Run from the repo root. `python -I` drops the script's folder from the import path; that cost time
on the DR458 [anim step 2]. Most `tools/anim` scripts now put their own folder back on the path,
so `-I` works for them; `beat_tracks.py` and `car_entry_preview.py` do not, so run those with plain
`python`, and give any new keys module the same `sys.path.insert` line as `car_entry_dr458.py`. **S**

Seated pose, grip and legs:

    # the DR458's v9_a10 values; the SVJ used --grip-angle 25 without the two thumb flags
    blender -b --factory-startup -P tools/blender/hand_grip.py -- <Hand_Nails_R.gltf> <wheel.glb> <points.json> <out dir> \
        --grip-angle 10 --bar-tilt 10 --wrist-turn -10 [--wheel-contact --thumb-spoke] [--tube-radius R --tube-centre r,y]
    blender -b <car.blend> --factory-startup -P tools/blender/footwell.py -- <out dir> [--save <tagged.blend>]
    lune run tools/legs/poses <SEAT_WELD.json> <poses.json>
    blender -b <car.blend> --factory-startup -P tools/blender/leg_clearance.py -- <poses.json>
    python -I tools/blender/rest_pose.py --car <car_rest.json> <poses.json> <REST_POSE.json>

Entry and exit (a manifest-built car, as the DR458; the SVJ's Studio-measured path is
[ENTRY §7-9]):

    python -I tools/anim/car_entry_prep_manifest.py --dump cockpit.npz --manifest manifest.json \
        --pose seated_pose.json --mark <right,forward> [--open-deg 75] --out scene.npz
    K="car_entry_<car> scene.npz seated_pose.json REST_POSE.json"     # the keys module and its inputs
    python tools/anim/car_entry_<car>.py scene.npz seated_pose.json REST_POSE.json <out> --timeline entry [--clear table.json]
    python -u tools/anim/car_entry_track.py $K --from F --to F [--pin F] --out track.json
    python -u tools/anim/car_entry_limbs.py $K --table track.json --out plan_<limb>.json --from F --to F --spacing 0.1 --limbs <limb>
    python -u tools/anim/car_entry_smooth.py $K --table merged.json --out final.json --passes 8 [--repair 40] [--polish F0-F1 --margin 0.003]
    python tools/anim/car_entry_mirror.py car_entry_<car> entry_table.json exit_table.json exit_mirrored.json
    python tools/anim/car_entry_check.py <timeline.fk.json or .baked.json> scene.npz --allow allow.json --json check.json
    blender -b --factory-startup -P tools/blender/car_entry_scene.py -- build <keys.json> scene.npz <out.blend>
    blender -b <out.blend> -P tools/blender/car_entry_scene.py -- bake <out.baked.json>
    blender -b <out.blend> -P tools/blender/car_entry_scene.py -- render <abs out dir> --cams entry,eye,door,side --stretch 4 --res 480 --step 2
    python tools/anim/car_entry_export.py <baked.json> scene.npz <export dir per timeline>
    python tools/anim/car_entry_exit_end.py <exit.baked.json> --mark <right,forward> --scale <driver scale>
    python -I tools/anim/car_entry_upload.py <creator id> <export dir>=<check.json> --ids ids.json --dry-run

`merge_tables.py` and `merge_limbs.py` (scratch, `drive-lab-assets/dr458/anim/scripts/`) join the
track and the limb plans before the smoothing. `check_all.sh` there builds a timeline and runs both
checks in about 2 minutes. [handoff, anim X0] **M**

Start-up hands, thumbs and gestures ([HANDS §10-12]):

    lune run games/drive-lab/tools/startup_config <CAR> <startup_config.json>
    blender -b --factory-startup --python-exit-code 1 -P tools/blender/startup_paths.py -- \
        <inputs.json> games/drive-lab/src/shared/Config/Cars/<CAR>/StartupPaths.luau <out dir>
    python tools/anim/startup_check.py <out dir>/paths.json --allow <allow.json> --json <out dir>/check.json
    blender -b --factory-startup --python-exit-code 1 -P tools/blender/thumb_press.py -- <inputs.json> <out dir>
    python tools/anim/thumb_check.py <inputs.json> <out dir> --pick --json <out dir>/check.json
    lune run games/drive-lab/tools/gesture_config <CAR> <gesture_config.json>
    blender -b --factory-startup --python-exit-code 1 -P tools/blender/gesture_poses.py -- <inputs.json> <poses dir>
    python tools/anim/gesture_paths.py <inputs.json> <out dir> --write games/drive-lab/src/shared/Config/Cars/<CAR>/Gestures.luau
    python tools/anim/gesture_check.py <out dir>/paths.json --track <CONTROL/state> --allow <allow.json> --json <check.json>
    stylua games/drive-lab/src/shared/Config/Cars/<CAR>

## A new car, step by step

### Inputs the model must give

Ask for these before any key. Each one cost a rework on the DR458 when it moved later.

| Input | Used by | Source |
|---|---|---|
| Door hinge: pivot, axis, open angle | the scene, the door curves, `Rules/Hinge` | [anim step 0] |
| Door contact points on the skin: the outside handle, the inside release, the edge or strap a hand rides, the card face a palm pushes | the keys, the holds | [ENTRY §9], [anim T3] |
| The seat: the H-point (`Driver_HPoint` in the manifest), which places the DriverSeat | the scene, the seated pose, the eye | [startup step 0] |
| A cockpit dump: every triangle in car metres, objects grouped as cage, seat, harness (worn and stowed sets), wheel, sill, cabin, body, door | the per-group check, the solvers | [anim T0, T2] |
| The wheel: centre and axis (`points.json`); one glb with the wheel joined, in the car export's units | `hand_grip.py`, `rim_profile.py` | [anim step 1] |
| Each start-up control: pivot, axis, rest, travel (binding `controls`, manifest names); a button's face and press axis | `startup_config`, `startup_sequence.py` | [HANDS §10] |
| Wheel buttons, the knob, panel toggles: faces, press axes, the knob's hinge and positions, every toggle bound in the binding | `thumb_press.py`, `gesture_config` | [gestures step 0] |
| The footwell: pedals cut as parts with hinges, travel signs, the footrest | `footwell.py`, `DriverLegs`, the contract check | [LEGS §4-6] |
| The collision Hull's size | where the mark and `exitEnd` can stand | [ENTRY §2] |

Keeping pivots and names stable, the clearance checks against the seated avatar and the harness's
swept-volume hand-off are the modeller's side: [MODELLING.md](MODELLING.md#hand-off-to-animation).

### What to reuse

| Reuse as is | Change per car |
|---|---|
| The R6 rig, bake and export (`r6_rig.py`, `build_keyframes`) | the scene (`car_entry_prep*.py`) |
| The six clips and four timelines, the runtime flow (`Rules/CarEntry`, `SeatHandOver`, `ClipPlayer`) | the keys module: copy the closer car's (`car_entry_keys.py` for a scissor door over a wide sill, `car_entry_dr458.py` for a front-hinged door into a cage) |
| The tracker, planner, smoother, mirror and checkers | the named contacts and their depths |
| The hand meshes: Rest, Point, Pinch, the cuffs (`hand_poses.py`) | the grip and thumb meshes (posed on this rim) |
| The start-up and gesture runtime, the data formats | `Startup.luau` moves and times; `StartupPaths.luau`, `Gestures.luau` (re-baked) |
| The hand-over blend (`Driver.handOver`) | the hand-over pose and its 0.6 s, if the palms land elsewhere |
| The trousers, shoes and sleeves | the footwell and `kneeToward` points |

### The steps

Times are targets for car 3 (**J**); the measured DR458 hours are in [Time](#time).

0. **Read and split (20 min).** This page, then the pipeline guides. Split as the DR458 did: one
   animator on seated pose, grip and entry/exit; one on start-up hands and gestures. Keep notes
   with clock times in `drive-lab-assets/<car>/work/NOTES_animation*.md`.
1. **Scale and arms first (30 min).** Draw the R6 boxes on a section of the cabin with matplotlib;
   it settles a placement in seconds. Use Blender only for the owner's picture. The owner picks the
   driver's scale. Never send a reach or an elbow angle before the real grip exists. [anim step 1]
2. **Grip (30 min).** `hand_grip.py`; add `--wheel-contact --thumb-spoke` for a wheel with spokes at
   3 and 9. Check the exported skin in the wheel, not a bone point (`grip_check.py` in
   `drive-lab-assets/dr458/anim/scripts/`). Then size the drawn arms for elbows near 130°.
3. **Rest pose and footwell (30 min).** `rest_pose.py --car` writes the one `REST_POSE.json` that the
   entry's last frame and the start-up's first key share. `footwell.py`, then the knee clearance.
   The contract checks the pedal signs.
4. **Scene (20 min).** Dump the cockpit (both harness sets), `car_entry_prep_manifest.py`. Put the
   mark outside the door's sweep and the Hull, measured for the torso's corner, not the root.
   [anim T5]
5. **Probe the path before solving (30 min).** Measure the window the head and torso must pass
   with single poses. On the DR458 this showed in minutes that only a lean-in facing the car works.
   [anim T1]
6. **Entry (2.5 h).** Copy the closer keys module to `car_entry_<car>.py`. Author the beats, then
   track, plan, smooth, check per group. Agree the named contacts with the coordinator early
   (rigid-limb classes: thighs over the sill or bars, the bottom on the bars or lip, hands on bars).
7. **InsideClose and SeatedPose (15 min).** Both hold the hand-over pose while the door shuts.
8. **Exit (1.5 h).** Mirror GetOut from GetIn at once. Author only InsideOpen and OutsideClose.
   End on a still stance at least 1 game stud out (`car_entry_exit_end.py --scale`).
9. **Bake, check, render, export (1 h).** Blender bakes, both checks on the bakes, measured allow
   files, quarter-speed renders and strips, one export folder per timeline.
10. **Start-up hands (1 h).** `startup_config`, then `startup_paths.py` with a `sequence`, then
    `startup_check.py`. Re-bake whenever a time or a control moves: the spec fails otherwise.
11. **Thumbs and gestures (1.5 h).** `thumb_press.py`, `thumb_check.py --pick`, `gesture_poses.py`,
    `gesture_paths.py`, `gesture_check.py --track` one track at a time (memory).
12. **Upload (owner's go).** Dry-run the guarded upload. The coordinator uploads with the owner's
    explicit go, as it did for #157's clips: clips through `car_entry_upload.py`, meshes through
    `tools/assets/upload_images.py`. An approval relayed by an agent is not the owner's consent: the entry
    animator declined one, and the coordinator later told the owner it had stretched an overnight
    mandate to the gestures' hand-mesh uploads. [anim T13], [gestures step 4], [coord]
13. **Wire (30 min).** `Door.luau`: ids, durations, door curves, `mark`, `exitEnd`, `seatedPose`.
    `Driver.luau`: `scale`, `arms`, `grip`, `footwell`, `startupPaths`, `handOver`, `gestures`.
    `Startup.luau`: moves and times. Gates green; every new rule's spec shown failing.
14. **Feel is the owner's.** The owner plays both cars and every path; agents hand over once the
    gates pass, and the coordinator syncs. #157 shipped that way, by the owner's instruction.
    [anim X4], #157 **D**

## Time

### Measured hours per stage

Spans come from PR, issue and commit timestamps (exact) and the notes' clock times. The entry
animator's note headings drift from its commits by up to an hour (T10 says 05:15-06:20 for the
door and walk pass; commit `967efda` is at 04:20; T13 says 09:45, commit `0d77a08` is at 08:49),
so splits inside a span are ±1 h; the span ends hold. **M**

| Stage | SVJ | DR458 |
|---|---|---|
| Walk and run | commits 10-27 20:13-21:45, shared with the car's physics; hours not recorded | reused |
| Seated pose, scale, arms | not a separate stage (Roblox's sit) | study from 23:35, end not noted; then a wait for the owner's choice [anim step 1] |
| Grip | commits 10-27 23:31-00:02 with the sleeves; hours not recorded | 30 min, then 1 h 10 for the thumb over the spoke [anim step 1] |
| Start-up hands | #24's commits 10-28 15:50-16:52; work began before the import, start not recorded | 00:45-03:20, about 2 h 35 with memory waits; #146 merged 03:46 [startup] |
| Legs, pedals | #36's commits 10-28 17:12-17:45; start not recorded | inside the seated-pose span; not timed apart |
| Thumb presses | none | 01:35-01:50 and 03:00-04:05, about 1 h 20; re-measure 20 min [startup] |
| Gestures | none | 03:35-06:10, 2 h 35 by the clock (Paris: the note's Studio step gives both clocks, and #156 opened 06:02); the note's own task list adds to 4 h 25 and does not fit that span [gestures] |
| Entry clips | all six clips: issue #10 at 15:17 to #39 merged 21:11, 5 h 54, two agents in turn | 00:25-08:49 to pass on the solver's bake (8 h 25, two animators); Blender bakes pass 09:46 [anim], `0d77a08` |
| Exit clips | inside the 5 h 54 | first passes inside the entry span; the exit animator 10:05-12:04, about 2 h [anim X0-X4] |
| Checker | built in #39 | per-group check #155: issue 04:09 to merge 04:31 |
| Runtime flow | entry state #17; pacing #40 at 21:27 to #53 merged 03:29 next day, 6 h with a revert (#43, #45) | config only, plus the hand-over blend (decision D) inside the entry span |
| Upload, wiring | inside #39 | inside the exit span; uploads by the coordinator |

Totals:

- **DR458: about 20 agent-hours**: animator 1 23:00-01:15 (seated pose, option D, grip, entry
  v1/v2, the runtime PR), animator 2 00:56-10:05, the exit animator 10:05-12:05 (about 13.4 h with
  the seated pose), start-up and thumbs about 3.75 h, gestures about 2.6 h, the checker about 0.4 h.
  Issue #108 opened 23:06; #157 merged 12:08. **M**
- **SVJ:** not summable. The windows above are commit and PR times, and agents worked in parallel.
  **M** for the windows only.

### What ate the time

DR458, largest first (each **M** from its note):

1. **The cage.** An R6 at 1.15 is 0.70 m from bottom to head top, all rigid; the window over the
   door bars is 0.45 m. Three techniques died before the lean-in worked. [anim T1]
2. **The solver stack was built during the job.** Per-frame clear, tracker v1-v4, the limb
   planner, smoother bugs; a full tracker run took about 25 minutes. [anim T3-T12]
3. **Checks that hid or invented problems.** The house checker masked secondary contacts, so key
   poses were re-found per group; random samples made depths jitter. [anim T9], [startup]
4. **Wrong numbers sent, then corrected.** Reach before the real grip; the thumb measured on a bone
   point; a door probe that never checked reach. Each forced a decision to be re-made.
   [anim step 1, T8]
5. **Decisions in the critical path.** The driver's scale waited on the owner's choice; the arm
   lengths were set three times (1.17 + 1.05, then 1.34 + 1.21, then 1.25 + 1.13) because a reach
   was sent before the real grip existed; named contacts and deviations waited on the coordinator.
   [anim step 1, T6-T13]
6. **The exit authored on its own** before the mirror: 72 failures; mirrored, 0 within about 1.5 h.
   [anim X1-X3]
7. **Memory.** Blender refused to start under 2-2.5 GB free while Studio was open; several bakes
   waited 10 minutes and gave up. [startup], [anim T6]
8. **Three animators in a row** on entry and exit (context ran out twice), each re-reading. [anim]

SVJ: an upload over a failing check and a silent change of the decided door close (found by the
replacement agent and redone, #39); allowances widened silently, then restored; a check that caught
only penetration; one timeline taking 18 minutes to solve (#39); the pacing change that broke
getting in at run time and was reverted (#43, #45, #53).

### Target for car 3

| Stage | DR458 (measured) | Car 3 (**J**) | Shortcut |
|---|---|---|---|
| Seated pose, scale, grip | about 2 h (the notes' times overlap) | 1 h | step 1 before any key; the grip flags exist |
| Entry + exit + InsideClose + SeatedPose | about 11 h | 4.5 h | copy the closer keys module; mirror the exit at once; per group from the first run |
| Bake, renders, export, wiring | inside the spans above, not timed apart | 1 h | one export folder per timeline |
| Start-up hands (with thumbs) | about 3.75 h | 1 h | touches as data; the shared rest pose |
| Gestures | about 2.6 h | 1.5 h | the runtime and the four path kinds exist |
| **Total** | **about 20 agent-hours** | **about 9** | |

The target holds only if the door and cabin are like a car already done. A new door type (gullwing,
butterfly) adds an estimated 2-3 h to the entry. **J**

Two shortcuts not yet taken (**J**): move the DR458's scratch scripts (`check_all.sh`, `jitter.py`,
`allow_measured.py`, `check_groups.py`, `clear_map.py`, `body_drift.py`, `merge_tables.py`,
`merge_limbs.py`, `keygrid2.py`, `grip_check.py`) into `tools/anim/`; they carry hard-coded local
paths today. And give the next car's decisions (scale, door technique, named-contact classes) to the
owner before the first key.

## Pitfalls

Each: symptom → cause → fix (source).

### Getting in and out

- **P1.** The head cannot pass the window → a rigid 0.70 m body against a 0.45 m opening → probe the
  head's path first; lean in facing the car, head inside, roll inboard ([anim T1]).
- **P2.** A part cutting two surfaces passes → the old check tested only the deepest group →
  per-group check, the default for new scenes ([checker], #155).
- **P3.** Hands "on" a surface float up to 1 stud → a penetration-only check → `"touch"` entries
  (#39).
- **P4.** A limb snaps 2.7-4.5 studs/frame² → the search flips it onto its other branch (the pivot is
  off the limb's axis, so two angle pairs reach one point) → bound each frame and plan the limb over
  the span (`car_entry_limbs.py`) ([anim T12], [handoff]).
- **P5.** The Blender bake fails where the solver passed (92 against 3) → the bake re-aimed limbs onto
  the other branch → carry the searched angles (`Body.fixed`) ([anim T11]).
- **P6.** Two checkers disagree on the seated head → different head boxes → name the contact at the
  house checker's depth ([anim T4]).
- **P7.** The solver keeps the body outside, then jumps → small steps cannot cross a bar → make the
  key poses nearly feasible by grid first; track from two centres ([anim T4, T11]).
- **P8.** Seated legs 0.44 into the cushion → the tracked body sat 15° off the seated pose → check the
  body's drift (`body_drift.py`, scratch) before planning limbs; pin the body to the seated pose
  ([anim T12]).
- **P9.** A planted foot slides on a step → steps too fast (5 frames) or too long, a hike that starts
  in one frame, a frame with no supporting leg → the shared `side_step` walk, 8-9 frames a pivot
  step, both feet down between walks ([anim T0-T5], [handoff]).
- **P10.** The smoother made a contact deeper → it judged a frame by its worst point only → refuse any
  move that goes deeper in any group ([anim T12]).
- **P11.** No clean pose exists (a 0.43 m torso in a 0.37-0.40 m bucket; a rigid thigh over a sill;
  zero clear cells for an arm) → the R6's shape → a named contact at its measured depth, decided and
  written in the PR as a deviation with the planner's evidence; never widened ([ENTRY §5], #157).
- **P12.** Feet slide at the stand-up (3.55 studs/s) → soles land while the pelvis still travels →
  mirror the entry's lift-off ([anim X1]).
- **P13.** The root pops between clips → the root moves between the mark and the seat → first and last
  frames are the idle stance at the mark ([ENTRY §2]).
- **P14.** The torso locks near a 90° yaw → Euler XYZ → `body_turn` and quaternion keys ([ENTRY §3]).
- **P15.** The exit fails where the entry passes → authored separately → GetOut = GetIn reversed, with
  the entry's contacts at the mirrored frames ([anim X1-X2]).
- **P16.** Getting out ends against the car → the walk back to the mark is too close to turn → end on
  `exitEnd`; pass `--scale` (the tool once assumed the SVJ's 0.857) (#40, [anim X4]).
- **P17.** The opening arm 0.3-0.4 studs into the body → the handle point was 9 cm inside the door
  skin; bar holds aimed the palm, which sits 0.15 studs above the arm's end face → targets on the
  skin from outside; raise bar targets 3.2 cm ([anim T3]).
- **P18.** A decision built on a depth that was never reachable → the probe did not report the miss →
  every probe that aims a limb prints its miss ([anim T8]).
- **P19.** An upload over a failing check, a decided motion swapped silently → no guard, no report →
  `car_entry_upload.py` refuses; report deviations at once (#39, `AGENTIC_WORKFLOW.md`).

### Hands

- **P20.** The thumb hovers 2.5-2.7 mm while the check says it touches → it measured a point 35 %
  along the tip bone, which runs 2.5 cm past the skin → aim and measure the exported skin
  ([anim step 1 #4], [startup 2b]).
- **P21.** The index stops short of the flap → the bone's tail is past the fingertip → the skin vertex
  nearest the tail ([HANDS §8a]).
- **P22.** Elbows wrong after a decision → a reach computed from an estimated wrist → wait for the real
  grip ([anim step 1]).
- **P23.** Grip renders wrong while the numbers are right → the tool wants the car export's units and
  the first mesh named Steering; its glbs carry a half turn about y → join the wheel, use the units,
  read the glb as (-x, y, -z) ([anim step 1]).
- **P24.** Depths jitter 0.3 mm between bakes, a finger reads 19.5 mm inside a cover → random samples,
  a vote fooled in a cavity → fixed per-triangle samples, ray parity on closed meshes; fix sibling
  checks the same day ([startup checkpoint 1, re-measure]).
- **P25.** The hand overshoots and comes back at a track's end → a key after the last, and the game's
  cubic → no key after the last ([gestures step 3]).
- **P26.** Open fingers dip 1.5-3.6 mm into the rim → a discrete Rest-to-Grip swap → a named contact;
  there is no half-open mesh ([HANDS §10]).
- **P27.** The solver said a thumb pose was fine; the mesh was 3.3 mm in the rim → judge candidates on
  the exported meshes (`thumb_check.py --pick`) ([startup 2c]).
- **P28.** A hand goes back and forth between two controls → a lead-in started before the last
  back-out ended → fit both inside 45 % of the gap and assert the order ([startup 1b]). Also: one
  changed key moved Blender's auto-clamped handles on its neighbours → pin keys ([startup 1c]).
- **P29.** Thumb meshes faceted, the glove map gone → faces rebuilt from points dropped UVs and normals
  → copy the evaluated mesh; `--export-from` ([HANDS §11], [gestures step 2]).

### Legs and runtime

- **P30.** The right knee 5 cm inside the console → bent straight out, checked with one upward ray →
  measure the nearest surface (`leg_clearance.py`) ([LEGS §5]).
- **P31.** Drawn arms would never show (not seen yet) → `DriverArms` needs a Motor6D shoulder and
  builds nothing otherwise, silently → check the joint class first (`Controllers/DriverArms`). **S**
- **P32.** Cockpit controls lag the hands by a frame → `CarDoor` writes weld C0 in PreRender while
  the hands use `BulkMoveTo` (a reading, not verified) → open as #147 ([startup Play check]).

### Tools and machine

- **P33.** A merge silently reverts tools → main moved files the branch had not touched since → diff
  `tools/anim` against HEAD before committing a merge ([anim T10]).
- **P34.** Uncommitted edits lost while undoing a mutation proof → `git checkout --` restores the
  committed file → undo from a backup copy ([anim step 2 #3]).
- **P35.** A background solver died mid-run → the module it imported was edited → run long jobs from a
  frozen copy of `tools/anim`; smoke-test two frames first ([anim T6, T12]).
- **P36.** A failed bake looked like a pass → Blender exits 0 on a Python error → `--python-exit-code 1`
  ([startup 1b]).
- **P37.** Renders landed at the drive's root → a relative output path → absolute paths ([anim T12]).
- **P38.** The machine ran short of memory → a check sampled the whole cabin (3.7 GB); Blender beside
  Studio → crop to the region, one track per pass; queue Blender jobs and run numpy checks meanwhile
  ([gestures step 3], [startup]).
- **P39.** Two exports mixed in one folder → a later export overwrote the record → one folder per
  timeline ([anim X3]).
- **P40.** A gesture described the wrong way in words → written before looking → read the renders
  first ([gestures step 3]).

## Open items

- One `Pelvis` mesh and `PELVIS_CENTRE`, shaped to the SVJ's bucket, serve both cars
  (`Controllers/DriverLegs`, `Config/DriverLegs`). Whether it shows wrong in the DR458 is not
  checked. **S**
- InsideOpen played alone (the door opened while staying seated) keeps the drawn hands, so its push
  is not seen. #157
- The SVJ's clips are still checked deepest-only; per group adds no failure on them; switching is
  the owner's call. [checker], #155
- The DR458's door sounds are the SVJ's. `Config/Cars/DR458/Door.luau`
- The DR458's entry settle (f186-189) is a named contact; reworking the drop's keys is a follow-up
  of about 1-2 h. #157
