# Driver legs

Real-length legs and shoes on the SVJ's real pedals, seen from the cockpit and through an open
door, on every player: the right foot on the throttle and over on the brake while braking, the
left foot on the footrest, the pedals turning under them.

## 1. Research first

- **The car's pedals.** Two pedals and a footrest; "the accelerator was organ pedal style, the
  brake was hanging type" (Gigazine's Aventador S review,
  https://gigazine.net/gsc_news/en/20170824-lamborghini-aventador-s). The cabin mesh agrees: a
  plate hinged on the floor for the throttle, a pad on an arm from under the dash for the brake,
  a perforated footrest.
- **Travel.** Accelerator pedal modules turn 12.6 to 17 degrees over their stroke (Bosch
  Motorsport's module about 16 degrees and 70 mm; CTS series 552 12.6 / 14; a WM treadle 17):
  the SVJ's throttle gets 16 degrees (7 cm at the ball of the foot). A boosted brake pedal moves
  a few centimetres at the pad under hard braking (one service limit 63.5 mm): 12 degrees here
  (4.5 cm at the pad).
- **One foot for both pedals**, the heel on the floor, as road drivers do; the left foot rests.

## 2. Sources for the meshes

Compared on 2026-10-28:

| Candidate | Licence | Verdict |
|---|---|---|
| MakeHuman system assets, shoes04 (black leather) | CC0 | **used**: 1,660 triangles a shoe, a clean leather texture, no logos |
| MakeHuman shoes05 / shoes06 (sneakers) | CC0 | rejected: their textures carry brand marks (three stripes, a swoosh) |
| MakeHuman shoes01 (brown leather) | CC0 | the same mesh as shoes04; a colour alternative |
| Khronos glTF sample "MaterialsVariantsShoe" (Shopify) | CC-BY 4.0 | rejected: attribution, and 22,700 triangles (Roblox simplifies above 20,000) |
| Trousers | ours | procedural cloth tubes, the same method as the arm sleeves |

Download only the shoes from the pack
(`files2.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip`,
267 MB; extract `clothes/shoes04/*`); keep it under `drive-lab-assets/driver/sources/`.

## 3. Model

    blender -b --factory-startup -P tools/blender/driver_legs.py -- <out dir> <shoes04.obj> --keep -x --toe -y

- **Trousers**: a thigh tube (17 x 15 cm at the hip, 12.5 x 12 cm at the knee, flattened as a
  seated thigh is) and a shin tube (12 cm at the knee, a slight calf, an open hem 11.5 cm across
  that hangs over the shoe), soft folds where cloth bunches at the hip, the knee and the hem; one
  stud long, real cross-sections: the game stretches each to its bone.
- **Shoe**: the pair's right shoe (MakeHuman's figure faces -y, its right is -x), turned into the
  shoe's frame (origin at the ankle joint, x to the car's right, y up out of the instep, z from
  the toes to the heel), scaled to 28.5 cm heel to toe, its sole's lowest point 8.5 cm below the
  ankle and its heel 7.5 cm behind it (`Config/DriverLegs` ANKLE_UP, ANKLE_ALONG). The left shoe
  is the right mirrored. The sock rising from the shoe stays inside the trouser hem.
- **Trousers' seat** (`pelvis.glb`): a soft block 33 x 22 x 25 cm under the R6 torso. Roblox's
  upright sit holds the torso's bottom 13 to 22 cm above the bucket's cushion; the block fills
  that room so the thighs grow out of cloth that sits on the seat, not out of the air.
- `legs.json` gives the shoe's mesh centre in its frame (`SHOE_CENTRE`); read the renders.

Upload `thigh.glb`, `shin.glb`, `pelvis.glb`, `shoe_R.glb`, `shoe_L.glb` and the shoe's colour map
(`tools/assets/upload_images.py`); keep them at `ReplicatedStorage.DriveLabAssets.Legs.Thigh`,
`Shin`, `Pelvis` (Fabric, the trouser colour), `Shoe_R`, `Shoe_L` (a SurfaceAppearance with the
colour map; the decal's image id is resolved in Studio with `InsertService:LoadAsset`).

## 4. Measure the footwell

    blender -b <car.blend> --factory-startup -P tools/blender/footwell.py -- <out dir> [--save <tagged.blend>]

The pedals are islands of the cabin mesh, found by box and, for the throttle, by lying within a
few millimetres of its ribbed face's plane (its base, housing and rod stay with the cabin). The
script prints, in metres in the driver's seat frame, each pedal's hinge (a line across the car)
and where the sole meets it at rest (heel and ball, 20 cm apart), and the footrest's; these go
into `Config/DriverLegs`. With `--save` it tags the pedals' faces (`door_part` 4 throttle, 5
brake) for the cabin export (section 6). Its render colours the selection: read it.

## 5. Fit the legs

`Rules/DriverLegs` places each sole, then the ankle 7.5 cm along it and 8.5 cm up off it, and
reaches it from the hip with two bones (`Rules/ArmIK`), each knee bending up toward a point of
its own (`KNEE_TOWARD`, seat frame):
- the throttle's sole lies on its plate and turns with it about the floor hinge; the brake's
  heel stays on the floor while the ball rides the pad about the top hinge; between them the
  foot crosses in 0.18 s, the heel sliding on the floor while the ball lifts 3.5 cm over the
  pads (lifting the whole foot raised the knee into the dash);
- a pedal turns only under the foot, by its readout; through the start-up the right foot holds
  the brake (`Rules/CarEntry.startupBrake`), so every client shows it;
- the hips sit at the R6 torso's bottom edge (`HIP`): lower, the thighs would lie on the cushion
  but the resting hands (`DRIVER_HANDS.md` §8b) would be out of the R6 arms' reach. The trousers'
  seat fills the room below.

Lengths: thigh 0.46 m, shin 0.45 m, the floored throttle at 96 % of the leg's reach.

**The knees against the cabin.** The right knee has little room: the steering column on its
left, the centre console on its right, the dash above. Measure every change:

    lune run tools/legs/poses <SEAT_WELD.json> <poses.json>
    blender -b <svj_door.blend> --factory-startup -P tools/blender/leg_clearance.py -- <poses.json>

It prints, for 26 poses (21 across the pedals, the throttle and the brake half and fully
pressed, the left foot at rest), how far the knee ball and the thigh and shin tubes stay off the
nearest cabin surface. The SVJ with the knee points as set (2026-10-28):

| Right leg | knee | thigh | shin |
|---|---|---|---|
| on a pedal, worst | 0.0 cm | +0.3 cm | -0.6 cm (throttle at rest) |
| brake fully pressed | +0.5 cm | +1.0 cm | +0.5 cm |
| crossing, worst (half way) | -0.7 cm | -1.0 cm | -0.6 cm |

A negative gap is contact: the trousers touch the console's side and the column as a real
driver's knee rests on the tunnel. The left leg clears everything by 5 cm. Bent straight out
(the first fit), the right knee sat 5 cm inside the console; an upward ray from the knee had
missed it, so measure the nearest surface, not one direction. Hips lowered by up to 8 cm, other
splays and other thigh-to-shin splits did not do better than 0.0 cm. Light contact was accepted
on 2026-10-28 (coordinator); 1 cm clear everywhere would take slimmer trousers or a smaller knee.

`tests/DriverLegs.spec.luau` keeps the rule's shape true (lengths, reach, knee toward its point,
the heel planted while crossing); the clearance itself is the tool's to measure.

## 6. Pedals as parts

The pedals are cut out of the cabin piece that holds them by the same export that cuts the door
(`tools/blender/hero_car_door_export.py`, tags 4 and 5), each its own MeshPart with the cabin's
look; that piece is swapped in the place with `ApplyMesh`. The car's binding names them
(`SVJModel.pedals`: part, hinge pivot, axis); `Car/CarRig` hangs each on a Weld named after it at
its hinge (C0's x along the car's width), and `Controllers/DriverLegs` turns the welds' C0
(`RestC0 * CFrame.Angles(angle, 0, 0)`). A car whose pedals are still part of its cabin has no
such welds: the feet still work them, the pedals stay still. The binding and the rig's hook come
with the pedals' own change (`HERO_CAR.md` §10).

## 7. Checked in edit mode

The probe of `DRIVER_HANDS.md` §8e, with `Throttle` and `Brake` attributes set on the car (a
render step can't see them move unless Studio's window is showing: minimized, it renders no
frame). The cockpit eye looking down (the player's look is limited to 40 degrees) sees the thighs
under the wheel; the knees and feet are under the dash. To see the feet, look from the passenger
footwell, or hide the door and the left leg with `LocalTransparencyModifier`. Captures of
2026-10-28: `drive-lab-assets/driver/captures_v2/legs_*`.

## Owner decisions

| Date | Decision |
|---|---|
