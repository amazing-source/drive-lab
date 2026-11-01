# Hero car pipeline

How the Drive Lab SVJ went from a downloaded model to a real-scale, debadged, PBR-textured car in
Studio, and what each step guards against. Each script carries its exact usage in its header.
Working files live outside the repo, in `Downloads/drive-lab-assets/<car>/`.

```
source model ─► debadge ─► clean .blend (metres) ─► [cockpit detail] ─► export glb ─► upload
                                    │                                                   │
                                    └─► emissive bake ─► maps ─► upload decals ─► SurfaceAppearances in Studio
```

## 1. Source

Pick on quality alone, among several candidates (the owner's rule for this private lab). Look for
real geometry (interior, calipers, separate wheels), sensible UVs and a full texture set.
`tools/assets/sketchfab_download.py` downloads by uid and writes `credit.json`. Inspect before
committing to a model: `blender_inspect_fbx.py` and `inspect_gltf.py`
(`research_notes/Drive lab/video_analysis/`).

**An Assetto Corsa `.kn5`** opens with `tools/blender/kn5_import.py` (our own reader, from the public
format). It builds the node tree, meshes, materials and embedded textures, written to a folder outside
the repo. It can pose a door from the mod's `.ksanim`, read the driver's `.knh` pose, and take a skin's
textures with `--skin`. Things to know:
- **Axes:** AC models face +Z with +X on the car's left. The importer's front-left-wheel check catches a
  wrong axis assumption.
- **Damage shaders** keep their dent map in `txNormal`; it is not wired.
- **The paint colour** is the tiled detail texture over a white shading map.
- **Run-time alternates** (the low-detail cockpit and wheel, blurred rims, damage glass, belts on and off)
  are all in the file. Hide them by exact name before judging the model.
- **An LOD file embeds no textures:** pass `--shared-textures`.

The SVJ came from a racing game's assets, whose maps are named by purpose: `DiffuseAOSO` (colour
with baked occlusion; its alpha is **not** opacity), `Normal`, `Material`/`MaterialOpacity`
(R = metalness, G = gloss), `Emissive`.

## 2. Debadge

`debadge_textures.py` (textures) and `blender_debadge.py` (geometry) in `research_notes/Drive
lab/video_analysis/` remove makers' badges, plates and tyre lettering. Two traps:
- **FBX embeds textures.** Edits to the files on disk do nothing until the materials point at
  the cleaned files. Unpack and repoint.
- **Some badges are geometry** (floating emblem meshes). Painting over them leaves the relief, so
  delete the meshes.

Keep the result as one clean `.blend` in metres, nose along −Y, Z up.

## 3. Cockpit detail (when the interior looks flat)

`tools/blender/hero_car_interior_detail.py`. Game models often map most of the interior onto a
few flat swatches, shared by many faces. No texture resolution fixes that: the script rebuilds a
unique UV layout from the artist's own islands, with density where the driver looks, then bakes
material detail per zone (suede, leather, perforated grips, carbon twill, satin, carpet, metal).
About 25 minutes; peak memory 2.1 GB. Its report sits in `interior_v2/REPORT.md`.

Afterwards **export from the new .blend**, since the maps only fit its UVs.

## 4. Export

`tools/blender/hero_car_export.py <car.blend> <out dir>`:
- Groups wheels and calipers before baking transforms, joins each per corner.
- Grounds the car at z = 0, centres it, and scales to studs (1 stud = 0.28 m).
- Splits by material, then halves pieces until each is under 18,000 triangles. **Roblox silently
  simplifies a MeshPart above 20,000.**
- Writes the manifest with `to_roblox(v) = (−x, z, y)`. Roblox's glTF importer turns a model
  180° about the vertical, so the nose stays along Blender −Y and lands on Roblox −Z.
- Exports glTF with normals and **tangents** (normal maps need them).

Blender traps met on the way: `Object.bound_box` is stale after `Mesh.transform` (use vertex
bounds); `matrix_world` is stale after setting a location until `view_layer.update()`; bmesh
round trips drop custom split normals (separate in Edit Mode instead).

## 5. Maps

- `tools/blender/hero_car_bake_emissive.py`: emissive textures laid out for a **second** UV set
  are baked into the first. A MeshPart has one UV set, so merging without this painted cluster
  glyphs over the steering wheel.
- `tools/assets/hero_car_maps.py`:
  - writes colour maps opaque (SurfaceAppearance's Overlay mode would show the part colour
    through);
  - merges glow colour into the colour map and keeps its brightness as the emissive mask;
  - turns gloss into roughness (`1 − G^0.8`) and R into metalness;
  - makes small uniform maps for parts with no source texture.
- Real-ESRGAN x4 (`%USERPROFILE%\tools\realesrgan`) upscales a low-res colour source before
  baking.

**Measured: Studio downloads 2048 maps at 2048** (Roblox's local cache). Do not try to measure
this with `EditableImage`: it cannot load more than 1024, so it always says 1024.

## 6. Upload and apply

`python -I tools/assets/upload_images.py <user id> <files>`: PNG → Decal, glb → Model. A decal id
is not an image id: in Studio, `InsertService:LoadAsset(decalId)` and read the Decal's `Texture`.

The glTF importer carries only colour maps, so Studio-side code builds each part's
SurfaceAppearance:
- `ColorMapContent`, `NormalMapContent`, `RoughnessMapContent` and `MetalnessMapContent` via
  `Content.fromUri`, with `Content.none` to clear one;
- `EmissiveMaskContent` with `EmissiveStrength`;
- `Color` to tint the paint.

Glass parts use Material Glass with Transparency. Set `RenderFidelity = Precise` on everything,
and Lighting `LightingStyle = Realistic` with `PrioritizeLightingQuality = true`.

To change one part's geometry later without re-importing the car: `AssetService:CreateMeshPartAsync`
from the new mesh, then `oldPart:ApplyMesh(newPart)`. Keep a backup copy of the car in
ServerStorage until the swap is verified.

## 7. Live instrument cluster

The cluster is the car's own face brought to life, not a redrawn one. For the SVJ the face is
the Assetto Corsa mod's display texture (`display.dds`, 512 × 256), read out of the mod's `.kn5`:
that file starts with `sc6969`, a version, then `count` textures stored as
(int32 flag, int32 name length, name, int32 size, bytes).

`python -I tools/assets/cluster_layers.py <display.png> <out dir> --erase x0,y0,x1,y1` cuts it
into three images and prints the dial's geometry for the car's face (`Config/Cars/<Car>/Cluster.luau`,
typed by `Config/Cluster`):
- `cluster_base.png`: the face, with each `--erase` box refilled from the rows above and below
  (the printed drive-mode name, which the game draws live);
- `cluster_lit.png`: the rev cells lit in white, tinted per drive mode in game;
- `cluster_red.png`: the red-zone cells lit in red.

How the geometry is measured, so another car's face can go through the same tool:
- the dial is a circle fitted through the top edge of the rim (SVJ: residual 0.27 px);
- cell edges are the art's dark separators, the minima of the band's brightness by angle
  (SVJ: 20 cells of 6°, 0 to 10,000 rpm, over 120.5°);
- the lit images are squares centred on the dial. In game a `UIGradient` whose transparency
  steps at its middle is rotated about that centre (`Rules/Cluster.wipeRotation`), which shows
  exactly the cells before the edge. One gradient works because the dial sweeps less than half a
  turn; a dial sweeping more needs the lit image cut in two halves, each with its own gradient.

Upload the three images as in step 6 and put the image ids in the car's face, with the
positions of the live readouts (gear, speed, mode, tell-tales) in pixels of the face image.

### Analog clusters (the Boss 302 way)

A car whose cluster is needles has no cluster image to animate: its own faces, needles, rings and
glass are separate parts of the model, and the game turns the needles (`Config/Gauges`,
`Controllers/Gauges`). What the 3D side delivers, in the car's manifest:
- each needle a `rotary` part with its pivot, an `axis` into its dial (a positive turn is clockwise as
  the driver sees it) and a `range` of [the dial's zero, its full scale] in radians from the modelled
  pose. The binding (`tools/car_binding`, settings `needles`) makes each a hinge whose rest is the
  zero and whose travel is the full scale; a needle without a range stays pending;
- each small live screen (a message centre, a digital readout) as a `mesh: false` marker part with a
  `screen` entry covering its whole dark window (settings `displays`); the rig builds a screen part
  named `Display<name>` there and the canvas takes the window's shape;
- faces and needles with a SurfaceAppearance carrying an emissive mask (white where it glows): the
  controller drives EmissiveTint and EmissiveStrength with the ignition, as the car lamps do.

The car's `Gauges` config then maps each needle to a reading and its printed scale (value, share of
the travel), the needles' damping, the backlight's glow, the screens' content and the simulated
engine (`Rules/EngineGauges`). `Contract.gaugeProblems` checks it against the binding and the
start-up, also for a car still out of the catalog.

## 8. Lights the game can drive

A model often bakes every lamp into one light mesh with one emissive map, so the brake lights
cannot brighten without the headlights and an indicator cannot blink on its own.

```
blender -b --factory-startup -P tools/blender/split_lights.py -- <car.glb> <light emissive.png> <light colour.png> <out dir>
```

- **Cutting.** The script cuts the light mesh into its four corners by face centre, then each
  corner into its lamps. A lamp is a connected group of faces, with vertices welded by position
  so a UV seam does not cut one. Each group is named after what it is on the real car, read off
  the model and the lens meshes over it:
  - **front:** the Y running light, the projector (its faces textured from the atlas's lens disc),
    the seven-cell indicator and the side marker;
  - **rear:** the Y tail and brake lamps (the emissive groups), the indicator cells under the
    amber lens, the clear reversing chevron, the fog lamp (the part of the chevron under the red
    lens), the high stop strip, the plate lamp and the side marker.

  What is left of a corner is its housing, which keeps the corner's old name. Every count is
  asserted, so another car's export stops there and its rules are written for it rather than
  mislabelling a lamp.
- **The lamps' glass.** On the SVJ the window glass mesh also formed every lamp's cover
  (near-black Glass at 0.55: a lamp behind it showed about half its light). The script moves each
  window group that overlaps a lamp's box into `LampGlass`, which is made clear; the windows keep
  their look.
- **Output.** `lights.glb`, uploaded as one model with `tools/assets/upload_images.py`, and
  `lights.json`: each piece's box, and the boxes of the parts it was cut from.
- **Into the place.** `tools/studio/lights_place.luau` (its header shows the MCP call):
  `dry()` checks each piece is in the uploaded model at its box's size and that each corner's
  pieces rebuild its old box; `apply()` backs up the parts it changes into
  `ServerStorage.CarImport_lights_backup`, swaps the housings and windows with `ApplyMesh` and
  sets their `Size` and `CFrame` (ApplyMesh sets neither), adds each lamp piece with its corner's
  SurfaceAppearance and a uniform white emissive mask (a lamp glows over its whole surface,
  shaded by its colour map), makes `LampGlass` clear Glass, all as one undo step. On the SVJ the
  car's bounding box, and so the rig's hull, does not move.
- **In game.** `Controllers/CarLights` decides (`Rules/CarLights`) and `Effects/CarLamps` drives
  each piece's EmissiveStrength and tint (a lamp behind a coloured lens also takes the lens's
  colour as its SurfaceAppearance Color: Roblox Glass blends with what is behind it rather than
  filtering it, so a white lamp face showed pink through the red lens), with the Roblox lights,
  scaled by 1 - daylight since a real lamp's light is lost in the sun's: headlight beams from the
  projectors, red tail glow, amber indicator glow, a reversing light and the cabin light in the
  roof console (`cabinLight` in `Config/Cars/SVJ/Model.luau`). The roles, the rhythm and the sources
  per lamp are in `Config/CarLights.luau`; each lamp's glow and the lights' numbers are the car's
  (`Config/Cars/SVJ/Lights.luau`). `Effects/ExhaustFlames` places its outlets from the union of each
  rear corner's pieces, which is the old cluster box, as the binding's `exhaust` names them.

## 9. Exhaust flames

The Assetto Corsa mod gives the outlets (`data/flames.ini`: two outlets 0.56 m apart, flame
direction 0, 0.175, -1) and its flame textures (`texture/flames/`): a side-view jet, turned to
point up and padded square for a velocity-parallel particle, and four fireball puffs packed into
a 2 x 2 flipbook. The outlets are placed from the rear light clusters and checked against the
model in Studio with marker balls (they sat 5 cm higher than the mod's numbers). Each pop the
engine sound plays fires a burst (`Effects/ExhaustFlames`): jets, a fireball and a 0.06 s flash.

## 10. Blurred rims

Built from the car's own wheels, so another car goes through the same two scripts:

```
blender -b --factory-startup -P tools/blender/rim_blur.py -- <car.glb> <wheel maps dir> <build dir>
python -I tools/assets/rim_blur_maps.py <build dir> <maps dir>
```

- `rim_blur.py` splits each `Wheel_*` by mesh island into the rim face (in front of a depth plane
  per axle, inside 90 % of the tyre's radius) and the rest, renders the face front-on and unlit in
  Cycles, and averages each render around every circle on the axle (the limit of accumulating
  rotated renders, without the banding a finite set leaves). It builds a disc per wheel on the
  face's front envelope and exports `rim_blur.glb` with `manifest.json` (each piece's offset from
  its wheel). It checks the readback is linear and that no mesh keeps a vertex colour set.
- **Strip vertex colours.** The export's second colour set has alpha 0: Roblox ignores it while
  a part is opaque and multiplies it in once the part is partly transparent, so a fading piece
  vanished outright.
- `rim_blur_maps.py` writes the 2048 x 1024 atlas (front rim left, rear right): colour with the
  coverage as alpha, metalness, roughness. Upload the glb and the three PNGs, resolve the decal
  ids, and put the pieces in `ReplicatedStorage.DriveLabAssets.RimBlur.<Car>.<wheel part>` with an
  `Offset` attribute each and the wheel's import size as `WheelSize` on the folder: tyre and face
  take the wheel's SurfaceAppearance, the disc its own with AlphaMode Transparency.

## 11. Opening doors

A game model's door is rarely its own object, but it is usually whole mesh islands: cut it out by
islands, never by faces, and it keeps its shading and UVs. Four scripts, each with its usage in its
header, carry one tag through the whole job: a face attribute `door_part` (0 body, 1 door, 2 the
START flap, 3 the opening's new parts, 4 and 5 the throttle and brake pedals) written into the
source meshes. Nothing is separated until the export, so every step reads the same selection. The
pedals are tagged on a copy of the door blend by `tools/blender/footwell.py --save`
(`DRIVER_LEGS.md` §4), which also prints their hinges.

```
car.blend ─► hero_car_door.py ─► svj_door.blend (tagged) + sill + button ─► hero_car_door_hinge.py ─► hinge.json
                                        │                                        │
                                        └──────► hero_car_door_render.py ◄───────┘ ─► renders, svj_door_rig.blend
                                        └──────► hero_car_door_export.py ─► door.glb + manifest ─► Studio (ApplyMesh)
```

### Split the door (`hero_car_door.py`)

- **Box first, then rules, then eyes.** An island is door when 85 % of its vertices sit in a box
  around the door. That catches the door and some strays, and misses parts of the door. The SVJ
  needed four more rules, each found by rendering the door pulled 0.7 m outboard (anything that
  floats, or anything left behind, is wrong):
  - the **outline rule**: a door part sits inside the door's own side outline (outer skin and glass,
    grown 1 cm), since a door has to pass through its opening; this drops the roof seal and fender
    slivers;
  - an **inner limit**: the cabin side of the sill and the seat trim are not door;
  - the **quarter window**: the box cut the front quarter glass off at the A-pillar, but on the real
    car the glass is one piece to the A-pillar and rises with the door (check a photograph of the
    open door from the front);
  - the **hinge**: the model carried its own hinge, an arm bolted inside the door's front face and
    pivot hardware inside the fender; arm with the door, pivot parts with the body.
  Islands the rules get wrong by eye go in an explicit, commented exclusion list (the SVJ: the
  seat-belt guide on the B-pillar).
- **Check every part the rule moves.** Plot each candidate island in side and plan view against the
  door's outline, with its share in the box: near misses (50 to 85 %) are where mistakes hide.

### Close the opening

Cast rays across the opening with the door's faces removed: on the SVJ they reached the
underbody (z 0.003 m), a black slot to the ground. The script measures, per 2.5 cm slice, the
door's lowest surface (rays up against the door alone; its skin runs long triangles along the
bottom, so its vertices say little), the outer skirt's top edge and the cabin-side trim, and lofts
a sill: a top 6 mm under the door, from under the cabin trim to the skirt, and a face up the
skirt's inside. No wall up the cabin side: the door's bin and the bottom of its card sit over the
cabin trim when shut and sweep outward through that line as it opens. Fit a
straight line through the slices and never go above it or the measurement: at its ends a slice meets
the door's front face or rear corner, not its bottom. UVs: planar at the material's own texel
density (median of its existing faces; a tiling map takes any offset).

### Fit the hinge (`hero_car_door_hinge.py`)

A hinge is a pivot and an axis; the door opens by a positive turn about it (right-hand rule).
`check` turns the door a degree at a time and lists every door triangle that cuts a body triangle,
by door island and body part. Three rules make that physical on a game mesh:
- a game mesh has **no shut gaps** (a real door has 4 to 5 mm): door and body touch or overlap along
  every seam, so a pair only counts once its door triangle has moved 2 cm, and body triangles within
  1.5 cm of the shut door (its seams) only count once it has moved 8 cm;
- door triangles within 6 cm of the axis, and body parts inside the fender's hinge pocket, are the
  hinge turning in its bracket, out of sight, and are listed apart;
- **show the check failing**: run it on a deliberately wrong axis before trusting a pass.

`fit` searches pivots and axes (a toe about Z swings the door out as it rises, a camber tilts the
axis down outboard) and keeps those clear at every degree. What decides the shape, measured on the
SVJ: every point ahead of and above the pivot moves forward and down, every point below it moves
rearward. So the front quarter window wants the pivot near its tip (far forward, high), and the
rear edge's lower corner, which then moves rearward into the body behind, needs the camber to carry
it outward. The fitted door's lean when open is compared with photographs: a near-vertical door,
its top about 12 degrees outboard (front view), measured on Commons photos (see the commit).

### Export and wire it

- `hero_car_door_export.py` replays `hero_car_export.py` exactly and stops unless every piece
  matches the place's manifest (triangles, origin, size): the place's parts are then swapped one for
  one with `ApplyMesh`. Only pieces that lost faces are uploaded.
- `ApplyMesh` copies the mesh and `MeshSize` but **not** `Size` or `CFrame`: set both from the
  manifest (the piece's centre moved when it lost the door).
- New parts copy their SurfaceAppearance(s) and material settings from the place part they came
  from (same textures, same UVs). Door glass goes in the model binding's `glazing`.
- Back up every part you change into ServerStorage first (`CarImport_door_backup`).
- Binding (`Config/Cars/<Car>/Model.luau`): `door = { parts, pivot, axis, openAngle }` and
  `controls = { <Name> = { part, pivot, axis } }` (the SVJ's `StartFlap`), points in the car frame
  from the centre of mass (before the body raise, like `seat`). `CarRig` hangs the door on one
  Weld to an invisible `DoorHinge` part whose C0's X is the axis (door parts weld rigidly to it)
  and each control on a Weld named after its part; `Controllers/CarDoor` sets
  `C0 = RestC0 * CFrame.Angles(angle, 0, 0)` from the car's entry state and, for a control, from
  the start-up move naming it (`Config/Cars/<Car>/Startup`).
  `pedals = { { part, pivot, axis } }` the same way: each pedal on a Weld named after it, turned
  by `Controllers/DriverLegs`. A binding without pedals rigs as before.
- Door sounds: one uploaded pack (`tools/audio/pack_door.py`), each sound a region; start them a
  little ahead of the door's own timeline so the shut's thump lands as it closes.

### The pull strap (`hero_car_door_strap.py`)

The seated driver closes the door by a 25 cm loop strap (the plausibility cap; aftermarket straps
are 18 to 22 cm, reviews of the SVJ describe a leather pull strap in place of a handle). A strap
is soft, so it is modelled as what a soft strap does, not as a stiff tab: a stiff strap would sit
25 cm into the cabin trim with the door shut.
- `measure` casts strap-wide rays down from the anchor (the card's inner lower edge nearest the
  seated shoulder) at every quarter degree of the swing, against the body and the door, and keeps
  the free length as a table: the strap hangs no longer than the trim below lets it (the rest of a
  real strap would lie on the trim). On the SVJ: 16 cm shut, 2 to 5 cm from 1.5 to 8 degrees while
  the door's lower edge sweeps just over the cabin trim, the whole 25 cm from 15.5 degrees. It then
  checks every hanging pose, every held pose (taut from the anchor to the palm, from the grab angle
  to shut) and the swing between them; `--full-length` must fail that check.
- `tilt` measured the alternative, tilting a full-length strap aside instead of shortening it, and
  it was not taken: shut, the strap would lie 60 degrees along the card, and between 2 and 8 degrees
  the clearing direction jumps from one quarter degree to the next.
- `build` exports the strap in its own frame (its -Y down the strap, its Z the faces' normal, full
  length), so the game aims it by its weld's C0 and sets its length by `Size.Y`, and the door card
  without the model's old short strap, size and origin unchanged for `ApplyMesh`. The strap's UVs
  sit in the old strap's red island, so it takes the card's own SurfaceAppearance. The manifest
  carries the place pose and the binding's numbers (`door.strap` in `Config/Cars/<Car>/Model.luau`).
- In the game the strap hangs on its own Weld from the chassis (`CarRig`), and
  `Controllers/CarDoor` poses it every frame with `Rules/DoorStrap`: held while a clip that closes
  the door by it plays (InsideClose, GetIn) and the door is between the grab angle and shut, aimed at
  the seated driver's animated palm and never longer than the strap; hanging otherwise.

## 12. Materials from a library (the DR458 way)

When a car is built from several sources (a game rip for the body, own models for the race
cockpit), its surfaces get physically based sets from a shared library instead of baked atlases:
tiling 1024 px maps (colour sRGB, OpenGL normal, roughness, metalness) with a real-world tile size
`tile_m`, and flat sets (a Roblox Material and a Color, no SurfaceAppearance). Meshes carry
`uv = metres / tile_m`, which relies on UVs outside 0..1 repeating on a MeshPart: measured in Studio
edit mode on EditableMesh quads (research 10, section 3.1); an uploaded mesh in a live client is still
to check. Were it ever to clamp, bake each piece's sets into its own 0..1 atlas (as in section 3).
The DR458's library builder and its sets live outside the repo (`drive-lab-assets/dr458/work/materials/`).

```
eye inventory ─► material map (+ photo per rule) ─► map check ─► apply (materials, UVs, debadged images) ─► eye renders
                                                                   │
                                                                   └─► SurfaceAppearance export (maps + contract)
```

- **See only what the driver sees.** `tools/blender/car_eye_inventory.py` renders object IDs over
  the camera's eye range (`Config/CarCamera` EYE_RANGE, look yaw to 100 degrees) and lists every
  visible mesh with its materials and UV density. The DR458: 184 of 309 meshes.
- **The map** is JSON: object rules (whole object, or split by face normal, e.g. a floor up-facing
  as diamond plate and its walls as paint), material rules by name, a `keep` list, derived sets and
  `replace_images`. A material named after a library set needs no rule, so modellers who name
  materials after sets and lay UVs at `tile_m` are covered by a lookup. Every rule names the photo
  it rests on. `tools/assets/car_material_map_check.py` fails on any visible slot neither mapped
  nor kept.
- **Apply** with `tools/blender/car_materials_apply.py`: one material per set, named after it,
  Principled inputs wired from the maps (so `hero_car_materials.py` lists them per input), custom
  properties `dl_set`, `dl_tile_m`, `dl_maps`. UVs are measured per tile size, area-weighted:
  a layout already at scale keeps its faces and only off-scale ones are re-projected (a strap or a
  tube keeps its direction); an atlas layout is re-projected whole with Smart UV Project and
  scaled to `tile_m`. Image paths are made absolute and missing ones found by name
  (`car_resolve_images.py`, also usable before any render script). It exits 1 on a missed slot, a
  bad UV group or a replaced image still read; `--break uv|set|images` shows each.
- **Debadge** atlases with `tools/assets/debadge_atlas.py` (boxes per image, new files). Two traps
  met on the DR458's source: its normal maps are two-channel (flat is olive, not 128,128,255), and
  a dash script that read as a texture was geometry in the chrome-trim object:
  `car_find_islands.py` lists such islands inside a box for the mesh's owner, and
  `car_delete_faces.py` deletes them, refusing a list made on another version of the mesh.
- **Renders** from the eye with `tools/blender/car_eye_render.py`, two fixed lights: the team's
  reference sun and a neutral overcast sky like the photos'. Under a blue sky every black reads
  blue-grey, so judge blacks in the overcast one.
- **Livery** with `tools/assets/car_livery_sheets.py` and `tools/blender/car_livery_bake.py`, after
  the apply step (then apply again for the rest of the paint). A game body's paint UVs are often
  mirrored left to right (the DR458's door skins share one region), so text would read backwards on
  one side. The bake gives the painted faces that face each side their own non-overlapping atlas
  (Smart UV Project per object, blocks shelf-packed at one density: 3.6 mm per texel at 1024 on the
  DR458) and colours every texel from its 3D position through a side-view decal sheet. Text then
  reads right on both sides whatever the UVs do. The rest of the paint takes the tiled clear-coat
  set. It fails if two faces share texels or if any sheet element lands nowhere.
- **Export** with `tools/assets/car_surface_appearances.py`: per set the four maps (at most
  1024 px, square, colour opaque unless the set blends alpha, uniform maps at 16 px as in section
  5, identical maps written once) and `surface_appearances.json` with the SurfaceAppearance and
  MeshPart properties; the upload step swaps file names for asset ids.

## 13. The cockpit from the driver's seat (the DR458 way)

Rank every cockpit job by what the driver sees, in that order: the eye point, the cage, the wheel,
the dash, then the rest of the seat's view. A check result matters where a game camera sees it.
The DR458's build scripts, its contract file (eye, H-point, wheel, control rest states) and its notes
live outside the repo (`drive-lab-assets/dr458/work/cockpit/`, `NOTES_cockpit.md`); what follows is
the method.

### Eye point (`cockpit_eye_point.py`)

The eye comes from the race seat's surface and two anthropometric rules, no photo solve: rays on the
seat's centre plane give the cushion and backrest lines, the H-point sits 0.13 m off the backrest and
0.095 m above the cushion, and a 50th-percentile torso and upright head put the eye 0.62-0.64 m above
it (SAE J941's centroid height at a 25-degree back angle is 0.635 m). The script also measures the
helmet's clearance to the roof and exits 1 on an implausible result; `--break` tilts the seat and
must fail. The points go into the manifest's `points` section (`Driver_HPoint`, `Driver_Eye`). The
game's camera eye is an offset from the seated avatar's head, so the real-driver eye is the reference
the avatar fit and the renders are checked against, not the camera's value. A seat's own placement
note is not an H-point: the DR458's sat 5 cm above its cushion surface.

### Roll cage

- Pin the A-pillar bar's top junction at the windscreen's top corner (inset by the padding's radius
  plus clearance), and fit the bar in two runs (floor to the junction, junction along the roof rail)
  so the fit cannot drag the junction down. Check the bar's shape against a photo through the door:
  the DR458's runs near-straight from the floor up the windscreen pillar (a knee at the dash pushed
  the door bars outboard and was reverted).
- The header bar is one smooth bend (a parabola in plan and height) between the pillar tops, its
  centre behind the windscreen's top edge, lowered as a whole until it clears the roof and the
  windscreen's black band. Pushing single samples off that band made it wavy.
- The roof X runs from each pillar top to the main hoop's top bar on the far side, under the roof all
  the way; the second diagonal runs a few millimetres lower through the crossing, or the two tubes'
  tops lie in one surface there and depth-fight.
- Sweep every tube along a smoothed centreline (key points, Chaikin corner cutting, a ring only where
  the line turns). Sweeping a fitted polyline with filleted corners bulges and twists wherever its
  segments are shorter than the fillet. A padding sleeve is cut from the very centreline its tube is
  swept on.
- Render the driver view over the camera's whole eye range (Config/CarCamera EYE_RANGE): the
  windscreen should be clear from the normal eye, with the tubes framing it.

### Door cards

A race card runs up to the window's bottom seal. If the source's card stops short, the door skin shows
from behind through the gap from the seat: close it with a ledge from each column's top straight
outboard to the glass or the shell, its outer edge smoothed over a few columns, and fan the step
wedges under it closed.

### Race dash from the road dash

When the race car keeps the road car's dash shell under Alcantara (the 458 Challenge does), copy the
road dash objects into the cockpit file, keep their UVs and sets, and cut what the race car does not
have: the road binnacle's insides between its gauge face and the race panel (below the hood's lip), the
climate controls, the badges. A plate under the hood's arch closes the binnacle opening behind the
race panel. Faces behind the eye go to trim objects, so the master's originals can be retired whole
with nothing lost; read the sources from the master by name, so the build gives the same dash before
and after the retirement. Plot the binnacle's faces front and side, by object, before choosing a cut:
the first cut took the hood's own lip. bmesh round trips drop the material list; carry it over.

### Soft parts against the game's own driver

Route the harness against the seated avatar's primitives (boxes and capsules from the animator), not
an anthropometric guess: push the strap centrelines and then every ribbon vertex outside the body by a
few millimetres, iterating where two shapes overlap, and give a strap the normal of the surface it
lies on. Keep two sets, worn (over the avatar, hidden) and stowed (lying on the empty seat, shown), and
carry `shown` into the manifest, as for a window net. A check that measures webbing inside the body
must fail when the webbing is moved into it.

### Freeze what a contract depends on

A parts script that measures the master (rays on the road hood) changes its output when the master
changes. The DR458's binnacle face, which also sets the screen size agreed with the display, grew
5 cm into the windscreen after a master update; its outline is now frozen to a file.

### Checks used

The DR458's check scripts are outside the repo too (`drive-lab-assets/dr458/work/checks/`).

- Holes from the eye: `render_ids` frames drawn single-sided with each glass mesh given a reversed
  twin. Outward-facing glass is culled from inside, so without the twin the windscreen counts as a
  hole and any change that uncovers it "fails".
- Depth fights a game camera sees (the scan's same-facing test, then each sample looked at from the
  eye range and the chase orbit). Layers within one part need dense area samples to find: probing
  face centres and corners missed the seat's cloth cover lying over its shell.
- Clearance from the seated avatar to the cage, and intersections between the cockpit parts.

## 14. Interior mirror and wiper (the DR458 way)

### Interior mirror (`tools/blender/car_mirror.py`)

Game models often ship the rear-view mirror as a bare glass plate, and Roblox's Reflectance on it shows
the sky, so it reads as a floating blue shape. Find the mount in the photos first: the DR458's is
glass-mounted inside the windscreen's top band, with the stalk hidden behind the head.

- **Build, on the master.** From the plate's outline, the tool makes the glass (recessed behind a lip),
  the housing with its domed back, a ball joint, a stalk to a pad that follows the glass 1.5 mm inside
  it, and the day/night tab. It turns the head on its ball so the default eye sees the rear window (the
  DR458's plate was aimed at the passenger side). The plate goes to a `Replaced_*` collection.
- **Bake, on the assembled car**, so the cage and the seats are in the image. The camera sits at the eye
  mirrored in the glass plane and is framed exactly on the glass; the glass's UVs are that camera's
  projection. The glazing is hidden so the view passes through, and a ground plane gives the road
  behind. Check what the mirror actually sees before judging the image: the DR458's first bake saw the
  cabin's inner filler skin, which covered the rear window from inside (243 of 256 rays).
- **Material.** A `baked` library set (colour map plus uniform roughness, square for the export). Roblox
  lights it like any surface, so it darkens at night and shows no sky. Door mirrors take a flat dark set
  instead: a baked exterior view is a frozen landscape.
- **Checks** (exit 1, each shown failing with `--break`):
  - the pad's gap to the glass, the aim of the reflected centre ray, and the glass's recess behind the lip;
  - no clash with the car, on the master and on the assembly;
  - UVs equal to the camera's projection, and nothing between the camera and the glass.
- **Live mirror: not built.** A ViewportFrame draws only copies cloned into it, under one directional
  light and an ambient colour (Creator docs). Prototype it and measure frame time before deciding.

### Wiper (`tools/blender/car_wiper.py`)

Read the layout from the photos; one taken with the bonnet open shows the spindle. Model the wiper parked,
as one hinged part (arm and blade) plus a static spindle boss.

- **Place the parked blade from a solved camera, not a pixel scale.** On the DR458 a scale taken off the
  photo put the blade 8 cm too far toward the centre. The sweep then cleared only 37 % of the area the game
  clears, and the driver's line of sight was at its edge. Back-projecting the blade's ends from the
  edge-aligned solve of a front photo onto the modelled glass fixed it: 58 %, with the line of sight and
  everything below it swept. Check the solve first by projecting the glass outline onto the photo.
- **A rigid blade cannot follow a doubly curved screen.** The tool tilts the spindle axis to minimise the
  worst float, then puts the rubber edge on the glass's envelope over the sweep, plus 3 mm. The DR458's
  screen base bows 21 cm in plan. On its first fit, the worst float went from 105 mm with the axis on the
  glass normal to 17 mm tilted; the final fit, with a longer reach, floats 3 to 21 mm.
- **The range** is the sweep that keeps the blade on the glass, 30 mm inside its outer edge (the blade may
  ride the printed band), cut back to where the built part would come within the minimum clearance of the
  car. A blade's inner end can reach the scuttle before its outer end reaches the edge; that happened on
  the DR458's first fit. The final range is 113°, set by the glass edge.
- **Checks** at every pose, on the mesh (exit 1, `--break clear|edge|sign`): no triangle crossing the car,
  every vertex at least 2 mm clear, and the rubber edge over the glass. The report also gives the
  clear-pane share and the share inside the area the game clears.
- **Manifest:** the hinge's pivot, axis, range and `positive`, plus the parked rubber edge's two end points,
  from which the controls work out the swept area.

## Open items on the SVJ

| Item | Plan |
|---|---|
| Console buttons | Relief may be inverted: the source normal map may be DirectX. Re-bake with `--flip-source-green`. |
| Interior SurfaceAppearances | Each interior part carries two. Remove the duplicate. |
| Seat suede, small metal parts | A faint block pattern on the dark seat suede, and bluish small metal parts. |
| Scale | Real scale in the place; `CarRig` scales it to `Units.WORLD_SCALE` (1.5) at rig time so an R6 avatar fits. |
