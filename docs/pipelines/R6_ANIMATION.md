# R6 animation pipeline

How the Drive Lab walk and run were made, so the next animation comes out the same quality
without rediscovering anything. Everything is scripted: the keys are text, the rig is Roblox's
own joint layout, every step can be re-run.

```
keys script ──► .blend (rig + keys) ──► bake ──► contact check ──► review renders
 (tools/anim)     (tools/blender/r6_rig.py)       (contact_report)   (r6_render.py)
                                    │
                                    └──► KeyframeSequence .rbxm ──► Open Cloud upload ──► config id
                                         (tools/anim/build_keyframes)  (tools/assets/upload_images.py)
```

## 1. The rig is Roblox's, not a guess

`tools/blender/r6_rig.py` builds the R6 rig from the joint data Roblox returns for
`Players:CreateHumanoidModelFromDescription(desc, R6)` (part sizes, every Motor6D's C0 and C1,
read 2026-10-27). Roblox places a joint's child at `Part0 * C0 * Transform * C1^-1`; the Blender
rig reproduces that exactly, with each joint animated in **body axes** so curves read naturally.

Proof that a pose in Blender is the pose in game: a test animation played on a real R6 rig in
Studio put every part within **0.0002 studs** of Blender's position. Re-run that check if the
rig code changes (`pipeline_test.keys.json` in `drive-lab-assets/anim`).

Signs (Roblox frame: +X right, +Y up, −Z forward):

| Joint | rot X + | rot Y + | rot Z + |
|---|---|---|---|
| limbs | swing forward | twist | right limb out / left limb in |
| RootJoint (torso) | lean back (forward is −) | turn left | lean left |
| Neck | nod up | look left | tilt left |

A limb's angle in the world is its joint angle minus the torso lean: a leg straight down under
a torso leaned 40° forward is a hip angle of +40.

## 2. Authoring keys

A cycle is **one authored step plus its mirror** (`tools/anim/cycle_keys.py`): every cycle plants
the left foot first, so cycles blend without swapping feet. Write the step as a list of key
poses; a key may give only some joints. `linear={...}` makes chosen keys interpolate linearly
(planted legs, sharp drops); everything else is eased.

```
python tools/anim/walk_keys.py <out.keys.json>
blender -b --factory-startup -P tools/blender/r6_rig.py -- build <keys.json> <out.blend>
blender -b <out.blend> -P tools/blender/r6_rig.py -- bake <out.json> [substeps]
```

Markers (`markers=[("Swap", 6)]`) become KeyframeMarkers, which scripts hook with
`AnimationTrack:GetMarkerReachedSignal`. Leave the Neck at rest when a script drives the head
(`--rest Neck` at export).

## 3. Checks before anyone sees it

`python tools/anim/contact_report.py <baked.json> <speed studs/s>` prints, per frame, each foot's
lowest corner (ground is y = 0) and how fast it slides against a floor moving at the travel
speed. Bake with substeps (`... bake out.json 2`) to see between frames.

Read it like this: planted foot near 0 and slip near 0 is a planted foot; negative y is a foot in
the floor; a swinging foot below ~0 scrapes.

## 4. What R6 bodies can and cannot do (learned the hard way)

- **No knees.** A 2-stud rigid leg covers about ±2 studs. At Roblox walk speeds a planted foot
  must slide; at a quick cadence it can stay planted but the walk looks hurried. The owner chose
  speed (12.5 studs/s, feet slide, as in Roblox's own R6 walk) over planted feet.
- **Box feet land on their corner.** Body height that keeps a tilted leg on the floor is
  `2 cos a + 0.5 sin a − 2`, not `2 cos a − 2`. Getting this wrong buried the feet 0.3 studs.
- **A swinging box foot near vertical always reaches lower than the planted one.** Swing it
  through vertical early, while the standing leg still slants (the hips ride highest then).
  Swinging the leg outward does not help: the hip pivots at the leg's outer top edge, so the
  inner corner drops.
- **Feel beats physics.** Measured-correct motion that the owner rejected:
  - the stiff-leg vaulting bob read as "bouncing";
  - a 6° then a 2° sideways roll read as "waddling";
  - three steps a second read as "trembling".

  What landed: one sharp two-frame drop at contact (weight), then a slow rise. A leg that visibly
  reaches forward (48°) before it sets down. Arms that cross a little, turn in, and peak a beat
  after the feet.
- **Stylised runs are holds plus snaps.** The reference run holds the throw pose for ~5 frames and
  swaps in 2. An evenly eased run reads as floaty.

## 5. Review renders

```
blender -b <anim.blend> -P tools/blender/r6_render.py -- <out_dir> --speed 22 --loops 3 --cams ref,game,side --res 480
```

Workbench renders, since Eevee produced nothing in background mode on this machine. The floor
scrolls at the travel speed so slides show. Cameras: `side`, `game` (Roblox's default
third-person framing), `ref` (low front three-quarter, the reference clip's angle). `--stretch 4`
renders a smooth quarter-speed version. Stack against the reference with ffmpeg `hstack`.

The owner's playtest is the final gate for feel; renders are for catching what the numbers say.

## 6. Export, upload, wire

```
lune run tools/anim/build_keyframes <baked.json> <out.rbxm> <Name> --loop --priority Movement --keys <keys.json> --rest Neck
python -I tools/assets/upload_images.py <user id> <out.rbxm>     # unset ROBLOX_OPEN_CLOUD_API_KEY first in old shells
```

Open Cloud accepts the Lune-built `.rbxm` as an Animation. It returns a new asset id each upload;
put it in `games/<game>/src/shared/Config/Movement.luau`. Set `WALK_PACE` / `RUN_PACE` to the speed
the cycle was authored for: playback runs at ground speed ÷ pace, so feet stay where they were
authored at any speed.

## 7. Playing it

`Controllers/Locomotion` plays the walk and run over Roblox's own R6 idle, jump, fall, climb and
sit (Roblox-owned, they play anywhere). A `StarterCharacterScripts/Animate` stub stops Roblox
inserting its default script. Animations played on the local character replicate to everyone.

Procedural layers (head follow, body lean) are separate scripts writing the joint's `Transform`
in `RunService.PreSimulation`, after the Animator, as `turn * animated` (`Rig/JointLayer`). Player
R6 characters use Motor6Ds; R15 and description-built rigs use AnimationConstraints, whose C0 is
read-only. `Transform` works for both.
