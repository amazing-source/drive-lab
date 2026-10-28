# Driver hands

Hands that really hold a car's steering wheel, seen in first person, on every player.

## 1. Source

A rigged realistic hand with finger bones. Used for the SVJ: Godot XR Tools' CC0 hands
(`addons/godot-xr-tools/hands/model/Hand_Nails_R.gltf`, 3,400 triangles, 26 joints) and their
`caucasian_realistic_baseColor`, `hands_normal` and `hands_occlusionRoughnessMetallic`
textures, straight from the GitHub repository. Candidates compared on 2026-10-27: MPFB2
(MakeHuman in Blender: full arms, but a generator), OpenGameArt "fps arms" (low-resolution
texture), Blender Studio's Human Base Meshes (best shapes, no rig, no texture), MB-Lab (archived).

## 2. Measure the rim

The wheel's own frame: x to the car's right, y up the wheel's face, z toward the driver, from
the car export's `points.json` (`wheel_centre`, `wheel_axis`). Slice the wheel's vertices at
several heights around 3 o'clock (`tools/blender/rim_profile.py <wheel.glb> <points.json>` prints the slices)
to find the rim tube's centre and thickness and where the spoke joins. SVJ: rim 36 cm across,
tube centre 0.167 m from the axis, about 3 cm thick, the spoke up to 14 degrees above 3 o'clock.

## 3. Pose and export

    blender -b --factory-startup -P tools/blender/hand_grip.py -- <Hand_Nails_R.gltf> <wheel.glb> <points.json> <out dir> --bar-tilt 10 --wrist-turn -10

- The rim at the grip is treated as a straight tube along the knuckle line; over a hand's
  width the rim's curve moves it 3 mm.
- The tube lies against the palm across the base of the fingers. Each finger's three joints
  close in turn, each until its bone touches the tube plus the finger's thickness, within the
  joint's range. Closing greedily around a convex tube never ends inside it.
- The rim crosses the palm slightly diagonally (`--bar-tilt`), as in a real power grip; it drops
  the wrist a little below the rim. 28 degrees was tried and rejected: the fingers stopped
  wrapping and the hands hung off the rim.
- The hand is turned into the wheel's frame at 3 o'clock, rolled round the rim by
  `--wrist-turn` (-10: the wrist a little inside, toward the shoulder), then round the wheel by
  `--grip-angle` (25 degrees for the SVJ: the little finger clears the spoke). The left hand is
  the right mirrored.
- A short sleeve cuff is built round each wrist along the hand's own axis. It covers the hand's
  cut end whatever angle the forearm arrives at; the forearm's sleeve ends inside it.
- Output: `hand_{R,L}.glb` and `cuff_{R,L}.glb` in studs at the world scale and already in the
  wheel's frame, `hands.json` (mesh centres, wrist, the forearm's direction and the back of the
  hand, in that frame), and four check renders.
  Read the renders before uploading: fingers round the rim, nothing through the spoke.

Roblox keeps the exported position: the imported MeshPart sits at the `centre` the script
printed, unrotated. That is what lets the game place a hand with the wheel's frame alone.

## 4. Skin that takes any player's colour

    python -I tools/assets/hand_maps.py <baseColor.png> <normal.png> <occlusionRoughnessMetallic.png> <out dir>

The colour map becomes the skin's detail around white (painted colour divided by the skin's
median, times the baked occlusion). The game sets `SurfaceAppearance.Color` to the avatar's
arm colour, so every skin tone keeps the creases, knuckles and nails.

## 5. Sleeves

    blender -b --factory-startup -P tools/blender/driver_sleeves.py -- <out dir>

An upper-arm and a forearm sleeve: oval tubes with soft folds, real-sized cross-sections, one
stud long; the game stretches each to its bone and keeps the cross-section, turns the forearm
so its flat sides lie with the hand's, and fills the elbow with a ball of the same cloth.

## 6. Upload and store

Upload the glbs and the three skin maps (`tools/assets/upload_images.py`), resolve the decals'
image ids, and keep each hand as an anchored, non-colliding MeshPart with a SurfaceAppearance at
`ReplicatedStorage.DriveLabAssets.Hands.Hand_R` / `Hand_L` (cuffs `Cuff_R` / `Cuff_L`, Fabric)
and the sleeves at `ReplicatedStorage.DriveLabAssets.Sleeves.UpperArm` / `Forearm`. That folder is outside the synced
tree, so a sync never removes it; it lives in the place file, which has to be saved.

Put the right hand's numbers from `hands.json` into `Config/DriverArms.luau`. The arm
controller reaches each forearm to the wrist (`Rules/ArmIK.luau`), bending the elbow toward where
the forearm would lie straight down the hand's axis.

## 7. Fit to the seat, checked in edit mode

No playtest needed: rig a copy of the car, seat an R6 dummy, start the controller and capture
from the cockpit eye and from beside the driver (the probe is in the session log of
2026-10-27). What the SVJ taught:
- With real arm proportions the shoulders were too close to the wheel: elbows at 100 degrees,
  forearms rising almost vertically into hands that point at the wheel, wrists' cut ends on
  show. Arms of 0.82 + 0.77 studs (scale 1) keep the elbows near 135 degrees and the forearms
  in line with the hands.
- Level with the forearms, the cockpit eye saw only sleeves; raised 7 cm it looks over them onto
  the hands.

## 8. The start-up: resting hands, the START flap, onto the wheel

Once seated (`Rules/CarEntry`'s phase), the custom arms rest on the thighs while the engine is
off, then follow the start key: the right hand lifts the red flap by its free edge, presses
START, lets the flap fall and takes the wheel; the left hand is on the wheel by 1 s. While
getting in and out the body animation moves the blocky arms instead. Every client plays it from
the car's replicated state, so other players see the same start-up.

    STARTUP (Config/CarEntry)   0 ... 0.75 lift ... 1.0 up ... 1.5 press ... 2.1 fall ... 2.9 wheel
    right hand                  Rest -> Point at 0.2 s   index under the edge, rides it up,
                                pushes START 4 mm, out from under before 2.1, Grip at 2.5, on the rim
    left hand                   Rest -> Grip at 0.4 s, on the rim at 1.0 s

### 8a. Posed hands

    blender -b --factory-startup -P tools/blender/hand_poses.py -- <Hand_Nails_R.gltf> <out dir>

The same CC0 hand as section 3, posed by joint angles: **Point** (index straight, the other
fingers curled, the thumb over them) and **Rest** (relaxed, fingers a little curved and apart).
Each is exported in its own **wrist frame**: origin at the wrist joint, z up the forearm, y out
of the back of the hand (the frame the game moves a hand by), plus one sleeve cuff for both, the
left hand the right mirrored in x. `poses.json` gives each mesh's centre, the index tip and the
palm's middle in that frame. Read the four renders: the thumb tucked, no finger through another.
The index tip is the skin's vertex nearest the end bone's tail: the tail runs about 2.5 cm past
the finger, and aiming with it left the finger short of the flap in Studio. The palm point is
taken between the wrist and the knuckles across the middle of the hand; with the thumb in it,
the resting hand sat 4 cm off the thigh's centre.

### 8b. The resting pose

    python -I tools/blender/rest_pose.py <SEAT_WELD.json> <poses.json> <REST_POSE.json>

`SEAT_WELD.json` is the seated R6 measured in Studio (the SeatWeld puts the torso's centre at
(0, 1.557, 0) studs in the DriverSeat frame at driver scale, upright). The script places each
hand's palm on its thigh 45 % of the way from hip to knee (thighs from `Config/DriverLegs`, the
right foot on the throttle, the left on the footrest), pitched so palm and fingertips both lie on
the cloth. `REST_POSE.json` also gives, for the entry animation's blocky arms, the palm's centre
and where an R6 arm aimed at it ends. Shoulders are 0.82 + 0.77 studs from the hand: the hands
cannot reach the knees on real-length legs. Its leg numbers (lengths, `KNEE_TOWARD`, the pedals'
heel and ball points) are copies of `Config/DriverLegs`; change them together.

### 8c. Keyed paths

    blender -b <svj_interior_v2_wheel.blend> --factory-startup -P tools/blender/startup_paths.py --
        <inputs.json> games/drive-lab/src/shared/Config/DriverStartup.luau <out dir>
    stylua games/drive-lab/src/shared/Config/DriverStartup.luau

`inputs.json` (example: `drive-lab-assets/driver/startup_inputs.json`) names the seat's origin in
the blend, the measured files above, the hands of section 3, the STARTUP times and the flap: its
hinge line, the point under its free edge, START's top face and the console's normal (agent B's
door work measured them). The script moves the cabin into the seat frame, then keys an Empty:
- each Point pose is aimed so the index tip lands on its target with the hand in line with the
  forearm the arm controller would draw (three passes through its elbow rule);
- the lift is keyed every 0.05 s on the edge's arc, turning about the hinge as `Rules/CarEntry`
  turns the flap, so the bake cannot cut the corner;
- the press: 4 mm above START, down to its face at `pressAt`, held, back up;
- the last key is the grip of section 3 on the wheel as the rig rests it.

Blender's Bezier easing between keys, baked every 1/30 s. The script stops if a wrist leaves 96 %
of the arm's reach, prints how far the index strays from the edge (0.4 mm for the SVJ) and where
it is at the press, renders eight moments from the cockpit eye, the passenger seat and the flap,
and writes `Config/DriverStartup.luau`: the keys in metres in the seat frame, the shape changes,
and the geometry they were made against. **Re-bake whenever STARTUP's times or the flap change**:
`tests/StartupArms.spec.luau` checks the index against `Rules/CarEntry`'s flap and press times
and fails otherwise.

### 8d. Store and play

Upload `hand_{Point,Rest}_{R,L}.glb` and `cuff_{R,L}.glb`; keep them at
`ReplicatedStorage.DriveLabAssets.Hands.HandPoint_R` / `_L`, `HandRest_R` / `_L` and
`WristCuff_R` / `_L`, each with a copy of `Hand_R`'s / `Hand_L`'s SurfaceAppearance (the cuffs
`Cuff_R`'s look). Without them the grip hand stands in for both shapes.

In game, `Rig/StartupHands` places every hand from a wrist frame: sampled from the keys
(`Rules/StartupArms`: positions on a cubic through every key, rotations turned evenly between
them), and over the last 0.5 s bent toward the live grip, so a later change to the wheel's rest
does not leave a jump. Shapes swap while the hand is moving: Rest to Point leaving the thigh,
Point to Grip half way to the wheel. `Controllers/DriverArms` reaches the arm to that frame as
before; only `phase == "Seated"` draws the custom arms.

### 8e. Checked in edit mode

Rig a copy of `workspace.CarImport` with `CarRig.build` well away from the car, seat an R6 from
`Players:CreateHumanoidModelFromDescription` scaled to `Driving.DRIVER_SCALE` (`Seat:Sit`), write
the car's entry state (Entry "Enter" long ago, door shut), start `DriverArms` and `DriverLegs`
(`RenderStepped` runs in edit mode), and bind a render step before them that sets `EngineAt` to
now minus the moment wanted, which freezes the start-up there. Capture from the cockpit eye (the
head and torso hidden, as `CarCamera` does), from the passenger seat and close on the console;
restore the camera and destroy the copy and the controllers' folders afterwards. Captures of
2026-10-28: `drive-lab-assets/driver/captures_v1/arms_*.jpg` (the `arms_side_*` pair after the
fingertip fix: the index at the lifted flap's edge at 0.9 s and on START at 1.5 s). Studio must
be visible: minimized, it renders no frame, so `RenderStepped` and captures both stop.

## Owner decisions

| Date | Decision |
|---|---|
| 2026-10-27 | One hand model for every player; no male/female variants. |
| 2026-10-27 | Hands follow the wheel up to 110 degrees each way, then the wheel slides through them. Kept for now. |
| 2026-10-27 | The forearms and sleeves follow the shape of the hands; the cockpit view is moved back from the wheel. |
| 2026-10-27 | Models are made by us when that fits better than an import (the owner's reminder). |
