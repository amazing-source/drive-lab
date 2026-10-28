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
- Real-ESRGAN x4 (`C:\Users\bfhdh\tools\realesrgan`) upscales a low-res colour source before
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
into three images and prints the dial's geometry for `Config/Cluster.luau`:
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

Upload the three images as in step 6 and put the image ids in `Config/Cluster.luau`, with the
positions of the live readouts (gear, speed, mode, tell-tales) in pixels of the face image.

## 8. Lights the game can drive

A model often bakes every lamp into one light mesh with one emissive map, so brake lights cannot
brighten without the headlights. `blender -b --factory-startup -P tools/blender/split_lights.py --
<car.glb> <light object> <out dir>` cuts it into four clusters by face centre (front or rear of
the middle, left or right of the centre line), keeping positions and UVs. Upload them, give each
the original's SurfaceAppearance, and place them in the model at the original's CFrame shifted by
(new import position - old import position); keep the uncut part aside (ServerStorage) rather
than deleting it. `Controllers/CarLights` then drives each cluster's EmissiveStrength and
EmissiveTint (the SVJ's rear clusters glow white in the map, so they are tinted red) and adds
the Roblox lights: headlight beams from the front end of each front cluster, red glow, amber
blinks and a reversing light. Colours and relative strengths come from the Assetto Corsa mod's
`data/lights.ini` and `extension/ext_config.ini`.

## 9. Exhaust flames

The Assetto Corsa mod gives the outlets (`data/flames.ini`: two outlets 0.56 m apart, flame
direction 0, 0.175, -1) and its flame textures (`texture/flames/`): a side-view jet, turned to
point up and padded square for a velocity-parallel particle, and four fireball puffs packed into
a 2 x 2 flipbook. The outlets are placed from the rear light clusters and checked against the
model in Studio with marker balls (they sat 5 cm higher than the mod's numbers). Each pop the
engine sound plays fires a burst (`Effects/ExhaustFlames`): jets, a fireball and a 0.06 s flash.

## Open items on the SVJ

| Item | Plan |
|---|---|
| Console buttons | Relief may be inverted: the source normal map may be DirectX. Re-bake with `--flip-source-green`. |
| Interior SurfaceAppearances | Each interior part carries two. Remove the duplicate. |
| Seat suede, small metal parts | A faint block pattern on the dark seat suede, and bluish small metal parts. |
| Scale | Real scale in the place; `CarRig` scales it to `Units.WORLD_SCALE` (1.5) at rig time so an R6 avatar fits. |
