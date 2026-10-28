# Street lamp

A prop modelled from nothing to match a reference photo, then lit and scattered along the road.
The same route fits any roadside prop.

## 1. Model from the photo

    blender -b --factory-startup -P tools/blender/street_lamp.py -- <out dir> [--photo <jpg>]

The script builds the Victorian double lamp the owner sent (2026-10-27): octagonal stepped base,
fluted flare, ringed pole, crosshead, two C-scroll arms carrying upright six-sided lanterns with
leaded panes. Proportions are read off the photo at a 3.9 m height. Output: `street_lamp.glb`
(meshes `Iron`, `Glass`, `Bulb`; 8,064 triangles in all), `street_lamp.json` (height, footprint,
bulb centres in studs) and check renders, with `compare.png` laying the model in red over the
photo. Read the overlay before uploading: the outline matched the photo within 1–2 px.

The checks inside the script: every part a closed, outward-facing shell; the export re-imported
for names, triangle counts, UVs and size. Both were shown failing on broken input.

## 2. Make it a lamp in the place

Upload the glb (`tools/assets/upload_images.py`), load it in Studio and keep it as a Model at
`ReplicatedStorage.DriveLabAssets.StreetLamp`, its pivot at the base centre (set `PrimaryPart` to
nil and `WorldPivot` to the origin: with the post as `PrimaryPart` the pivot stayed at the post's
middle and every lamp stood half underground). Parts:
- `Iron`: Metal, near-black; `Glass`: Glass at 0.35 transparency; `Bulb`: wax-coloured
  SmoothPlastic, turned to warm Neon when lit.
- `Collider`: an invisible 0.9-stud post, the only solid part, so a car stops on it.
- Lights, all off in the model: one SpotLight between the lanterns facing down (range 60, the
  engine's maximum, angle 150, brightness 3, warm 3000 K), and a PointLight in each lantern
  (range 7, brightness 1.5).
- Tagged `DriveLabStreetLamp`.

## 3. Along the road and at night

- `Rules/StreetLamps.spots`: a slot every 35 m a side, the sides staggered by half a slot, each
  slot moved by a seeded jitter of up to 40 % and one in seven left empty, none in the first
  80 m. The same road gets the same lamps whichever chunk lays them (tested).
- `Services/Track` places a chunk's lamps on both verges, 2 m off the road's edge, arms along
  the road, and clears them with the chunk.
- `Controllers/StreetLights` (each client): lit from 18:00 to 06:30 of `Lighting.ClockTime`,
  each lamp switching at its own moment within 2.5 s; lights enabled within 250 m of the camera;
  only the 6 nearest downlights cast shadows. The game streams: a lamp model reaches the client
  before its parts, and its parts stream out and back in as new instances, so each lamp keeps
  its lights and bulb as they come and go (`DescendantAdded`/`DescendantRemoving`), and a lamp
  whose parts are not in counts as dark. Read once on arrival, every lamp stayed dark in Play
  while its glints were drawn (#44: measured in a Play session; edit mode does not stream, which
  is why the first check passed).
- Glints (`Effects/LampGlints`): each flare and wet-road streak fades out along its length to
  nothing at both ends (`Rules/LampGlints.taper`), drawn in 12 beam segments since a Beam samples
  its transparency only at its segments' ends; the flare texture is a long streak that fades only
  in its last sixteenth, and drawn at one opacity it read as a flat grey bar (#44). Neither kind
  draws until its image has loaded (ContentProvider).

Checked in edit mode, no playtest: two lamps beside the car at 21:30, lanterns glowing, pools
with the posts' shadows on the ground.
