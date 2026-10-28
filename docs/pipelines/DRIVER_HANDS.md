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

## Owner decisions

| Date | Decision |
|---|---|
| 2026-10-27 | One hand model for every player; no male/female variants. |
| 2026-10-27 | Hands follow the wheel up to 110 degrees each way, then the wheel slides through them. Kept for now. |
| 2026-10-27 | The forearms and sleeves follow the shape of the hands; the cockpit view is moved back from the wheel. |
| 2026-10-27 | Models are made by us when that fits better than an import (the owner's reminder). |
