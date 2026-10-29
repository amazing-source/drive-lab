# Roadside: furniture, road marks and lamp glints

What makes speed felt on the endless test road, and makes the night read as a photograph:
things close to the car streaming past (delineator posts, guardrail posts), things overhead
(sign gantries, with their shadows across the road), coarse and varied detail on the asphalt,
and at night the lamps' flares and their streaks on a wet road. Research behind it: Shawn
Hargreaves (MotoGP) and Burnout 3 on speed cues; irregular spacing, because evenly spaced
objects strobe at 60 FPS (at 300 km/h the car moves 1.4 m a frame, 0.7 of a 2 m post period,
so a regular row seems to crawl backwards).

## 1. Models

    blender -b --factory-startup -P tools/blender/roadside_props.py -- <out dir>

Italian two-lane extra-urban road furniture, from the rules and a manufacturer's sheet (sources
in the script's header): the delineator (white, 1.05 m, 25 cm black band, red reflector to its
own side's traffic and white to the oncoming, as the rules ask on a two-way road), a W-beam
guardrail (class N2, 0.75 m) in two 12 m sections whose posts sit up to 0.25 m off the 2 m
grid, its buried flared terminals, and a portal sign gantry (5.58 m under the truss, above the
5.10 m minimum). One glb, one object per Roblox part named `<Model>_<Part>`; 8,032 triangles in
all. The script checks every part is a closed outward shell and re-imports the export.

Look at `check_props.png` and `check_closeup.png` before uploading.

## 2. Textures

    python -I tools/assets/roadside_textures.py <out dir> <vfx extras dir> --patch <AsphaltDamage001 dir>

Road marks as dark-on-clear RGBA decals (patch from ambientCG's AsphaltDamage001, CC0; sealed
crack, skid marks, oil stain, drip line drawn from seeded noise), alpha under 1 so the wet
road's gloss shows through. Bold enough to read from the chase camera: a first pass with 1-2 cm
tar bands and alpha around 0.3 was invisible past 20 m, so the sealant bands are 5-7 cm and the
marks' alpha 0.5-0.9. The two gantry signs (white on blue, Arial Bold standing in for Italy's
alphabet). The owner's ChatGPT flare and wet-reflection textures: the flare cut to a 64-row
band with its core line thickened (at a few pixels tall the 6-pixel line broke into dashes),
the reflection turned along the image's width with its bright end faded (it touched the edge
and drew a hard cut). A Beam draws the image's right edge at Attachment0, the opposite of what
one would guess: seen in Studio.

## 3. In the place

Upload the glb and the PNGs (`tools/assets/upload_images.py`), resolve each decal to its image
(`InsertService:LoadAsset`, the Decal's Texture). Load the glb asset, group its MeshParts by
the name prefix into Models under `ReplicatedStorage.DriveLabAssets` (`Delineator`,
`GuardrailA`, `GuardrailB`, `GuardrailStart`, `GuardrailEnd`, `SignGantry`), each with
`WorldPivot` at the origin and no `PrimaryPart`:
- MeshParts anchored, CanCollide/CanQuery/CanTouch off; delineator white and black
  SmoothPlastic; steel galvanised grey SmoothPlastic (176, 180, 182), reflectance 0.08 (Metal
  mirrored the sky and read dark blue); footings Concrete.
- Reflector parts (`ReflectorRed`, `ReflectorWhite`) tagged `DriveLabReflector`.
- Guardrail sections carry an invisible `Collider` (12 x 0.75 x 0.28 m); the gantry a `Footing`
  and a `Post` collider at each leg. Delineators are not solid.
- The gantry's sign faces are Parts (`SignRight`, `SignLeft`) with a Decal on the face turned to
  their lane's traffic.

## 4. Along the road, at night

- `Rules/Roadside` places everything on `Rules/Scatter`'s seeded lattice, so a chunk gets the
  same furniture however the road is cut (tested): delineators about every 50 m, guardrail
  stretches of whole sections (delineators give way to them), a gantry about every 1.2 km,
  and about one mark every 30 m a lane, each kind with its own size, place and turn.
- The server's `Roadside` lays them with each chunk (`Services/Track`), yielding every 40
  pieces, and they go with the chunk.
- The road's start is closed by the same guardrail (`Roadside.layRoadEnd`, #69): whole sections
  across the road and both verges (`Rules/Roadside.roadEnd`), 1 m behind the first metre of
  asphalt, the beam facing the road and a terminal at each end. `Services/Track` lays it once at
  start into `Workspace.RoadEnd`; it stays when chunks are cleared.
- `Controllers/Reflectors` (each client) turns reflectors to neon in the driven car's
  headlights: in the beams, facing the car, fading to 320 m, in four steps. A reflector is
  under a pixel past 40 m, so the 40 nearest lit ones also get a round billboard dot of 5 to 2
  pixels (`Effects/ReflectorDots`): the receding row of red and white points of a road at night.
- `Controllers/StreetLights` hands the nearest lit lamps in view to `Effects/LampGlints`: a
  faint additive flare on each head, level on screen and sized with distance so it keeps its
  size on screen as a lens flare does, and on a wet road a streak on the line from the lamp to
  the eye (which the camera sees straight below the lamp), from just short of the mirror point
  to where the line leaves the asphalt, scaled by `Wetness` and none when dry.

Checked in edit mode on a 1 km stretch laid by these modules, no playtest: captures in
`Downloads/drive-lab-assets/roadside/captures/`. The verge's terrain grass hides the guardrail
posts and much of each delineator from the chase camera.
