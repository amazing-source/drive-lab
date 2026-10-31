# Modelling playbook: a new car's model and interior

Read this before touching a new car's mesh. It distils the SVJ and the DR458 into one order of work,
the checks that catch the expensive mistakes, the time each stage really took, and the traps.

The how-to for each step already exists and is linked, not repeated:
- [HERO_CAR.md](../pipelines/HERO_CAR.md), sections 1-14;
- research [03](../research/03_car_model_sourcing.md), [03b](../research/03b_car_model_sourcing_pass2.md),
  [07](../research/07_visual_references.md), [09](../research/09_roblox_import_pipeline.md),
  [10](../research/10_car_materials_and_wet_look.md) and [12](../research/12_dr458_challenge_evo.md).

For the whole new-car runbook, see [NEW_CAR.md](NEW_CAR.md). For the driver's animations, see
[ANIMATION.md](ANIMATION.md).

**The bar (owner, 2026-10-30).** An excellent driver experience and a good driver's view, faithful on
the main things. Millimetre precision is not the target. Rank every job by what the driver's eye sees,
then the chase camera, then a player walking up.

**How to read the tags.**
- **[measured]**: a number from a run, a render or a notes file, with its source.
- **[judgement]**: my recommendation; not measured.
- **Notes** means the DR458 agents' running notes in `drive-lab-assets/dr458/work/NOTES_<topic>.md`.
  They sit in the work folder, outside the repo.

Third-party models, textures and photos never go in the repo. **Licences decide what ships**:
see research 03 §4, and record provenance for every source.

## Contents

- [Order of work](#order-of-work)
- [Hand-off to animation](#hand-off-to-animation)
- [What reads as realistic in Roblox](#what-reads-as-realistic-in-roblox)
- [Checks](#checks)
- [Time](#time)
- [Pitfalls](#pitfalls)

## Order of work

### 0. Before the first Blender run

- **One job at a time, under a lock.** Take `drive-lab-assets/.blender-lock` (plus the area lock,
  e.g. `.blender-lock-exterior`), each with an owner file. Run only with 2.5 GB free and at most
  one other `blender.exe` (common brief).
- **A runner that fails loudly.** Pass `--python-exit-code 1`: Blender exits 0 when a `-P` script
  raises (notes: lead step 15). Stop at the first failing job: a failing bake once saved its file and
  overwrote shared maps, and the chain ran on (lead step 17). Never wrap the runner in `timeout`: a
  killed run leaves its lock behind (lead shortcuts).
- **Candidate, then swap.** Build `master_vNN.blend` from the master, check it, ask, then back up
  the master with a date and copy the candidate over it via a temporary file and a rename. Never
  edit the master, or a parts file another agent links, in place (notes: polish, lead).
- **Notes with clock times** from the first step: they are where the [time table](#time) comes from.

### 1. References

- **Exterior:** front, rear, both sides, all four three-quarters, the roof, every lamp close up, and
  one photo with the bonnet open. The DR458's bonnet-open photo was the only place the wiper
  spindle showed (notes: mirror_wiper).
- **Interior:** the driver's view; the dash, wheel, binnacle and every control panel square on; the
  seat and harness; the roof panel and mirror; the door card; the footwell and pedals; the rear wall.
  The DR458 set had 38 interior photos, and each cockpit decision cites one ([12](../research/12_dr458_challenge_evo.md) §2, notes: cockpit).
- **One full listing beats scattered images** [judgement]. It is the same car, in the same light and
  the same state. The DR458's whole set came from one auction listing, 131 photos
  ([12](../research/12_dr458_challenge_evo.md), "Local reference status").
- **Check each reference against its source** before trusting it ([07](../research/07_visual_references.md),
  "How each one was checked").

### 2. The base model

- Rank candidates by quality, then check the licence and its provenance: a Sketchfab label is only
  the uploader's claim ([03](../research/03_car_model_sourcing.md) §4.2, [03b](../research/03b_car_model_sourcing_pass2.md)).
- A game model is usually the best base. It is already split, UV-mapped and sized for real time.
  Expect its traps: split edges at every UV seam, a road car's dash, bare mirror plates and brand
  lettering in the geometry (notes: lead, materials; [HERO_CAR](../pipelines/HERO_CAR.md) §1-2, §14).
- **Body and parts from different sources are fine.** The DR458 is a Forza 458 Italia body plus
  Codex-built Evo parts, refitted to the 2014 rule heights (coordinator handoff).

### 3. Camera solve, checked by projecting outlines

- **Solve the camera of two or three photos against the model**, and **check the solve by projecting
  the model's outlines** (the glass, the panel gaps) onto the photo before measuring anything with it.
  The DR458's edge-aligned solve of exterior/002 put the windscreen's outline on the photo's
  A-pillars and glass edge (scripts: `drive-lab-assets/dr458/work/overlay/v2/`).
- **Measure from the solve, never from a pixel scale.** A scale off the same photo put the parked
  wiper 8 cm toward the centre [measured]. The sweep then cleared 37-40 % of the area the game clears;
  from the solve, 58-60 % ([HERO_CAR](../pipelines/HERO_CAR.md) §14, notes: mirror_wiper).
- **Render the model from the solved camera beside the photo** ("matched view", notes: lead step 7).
  Silhouette errors show at once.

### 4. Real scale and ride height

- Work in metres in Blender, with the origin on the ground under the rear axle and the nose toward -Y
  (the DR458 manifest frame). The game converts at 0.28 m per stud and scales the world 1.5× at rig
  time ([README](../../games/drive-lab/README.md) decisions, 2026-10-27).
- Set the ride height from the rules or the spec sheet, and the body off its tyres by the measured
  overlap. The SVJ needed a lift (game-kit commit `f7ad03a`); the DR458 sat at the rule heights
  ([12](../research/12_dr458_challenge_evo.md) §1).

### 5. Debadge

- **No brand marks**: lettering in the geometry and in the textures
  ([HERO_CAR](../pipelines/HERO_CAR.md) §2, §12).
- **Lettering can be geometry, not texture.** On the DR458 a dash "458 Italia" script was faces in
  the chrome-trim object. `car_find_islands.py` lists such islands and `car_delete_faces.py` deletes
  them, refusing a list made on another version of the mesh (§12).
- Owner exceptions are written down: the DR458's cool-suit box keeps its lettering (coordinator
  handoff).

### 6. Interior, in the order the driver's eye sees it

[HERO_CAR](../pipelines/HERO_CAR.md) §13 is the method. The order that paid off on the DR458:

1. **The eye point**, from the seat and a 50th-percentile driver (`cockpit_eye_point.py`). Every
   later check looks from it and the game's eye range (`Config/CarCamera` EYE_RANGE).
2. **What crosses the view:** the cage (the DR458's front bar sat at eye height), the A-pillars, the
   mirror.
3. **The wheel and the binnacle:** the race wheel, its buttons with real pivots, the display face.
   Freeze any outline a contract depends on (the binnacle face once grew 5 cm after a master update, §13).
4. **The dash top and door cards** (the door band below the window showed sky through the body,
   notes: lead step 11).
5. **The seat and harness**, checked against the game's own seated driver (§13, "Soft parts").
6. **The rest of the cabin the eye reaches:** the tunnel, the switch panel, the floor, and the rear
   wall seen in the mirror.
7. **Last:** what only a walk-up camera sees (footwells, under the dash).

Cut the road car's leftovers (dash, pedals, console) into a retire collection; never delete them.
Rendering a "look" from the eye, with the glass hidden, shows in a minute what counts only hint at
(notes: lead step 11).

### 7. Exterior fixes

- **Fix what the chase camera and a walk-up see**, in that order: lamps, mirrors, wheels and the fit
  at the tyre, exhaust outlets, aero parts. The DR458's black mirror shells, exhaust cut and fog lamps
  each came from a photo (notes: lead steps 17 and 21, polish item 5).
- **A boolean on a game mesh needs a verify and a render**: the DR458 exhaust cut kept a sleeve of
  cutter faces that the counts did not show (notes: lead step 17).

### 8. Materials

- **A library of sets, not per-car textures:** tiled sets at real scale (UV = metres / `tile_m`),
  flat sets, baked sets (livery, mirror) and source-derived sets. A map JSON names each rule's
  photo; a material named after a set needs no rule ([HERO_CAR](../pipelines/HERO_CAR.md) §12).
- **Apply, then check** (`car_materials_apply.py`, `car_material_map_check.py`).
- **Export the SurfaceAppearance contract** (`car_surface_appearances.py`):
  - maps at most 1024 px, square, a power of two;
  - uniform maps written at 16 px;
  - colour maps opaque unless the set blends (§12, research [10](../research/10_car_materials_and_wet_look.md) §6).
- **Baked vs tiled:**
  - Tiled sets carry the surface grain at real scale and are reused across cars.
  - Baked sets carry what is unique to this car (livery text, the mirror's image).
  - Flat sets carry what the camera never reads closely (glass tints, small plastics).
- **The colour-space trap:** a generated image whose colour space is set *after* its pixels comes out
  black [measured]. The DR458 mirror's roughness was written as zeros (0/255 for 15). Set the colour
  space first and read every written map back from disk (§14, notes: mirror_wiper step 11).
- **Judge blacks under an overcast light.** Under a blue sky every black reads blue-grey (§12).

### 9. Lamps

- **Name them for the game's lamp code:** `Light_<Corner>_<Role>`, one emissive object each
  ([HERO_CAR](../pipelines/HERO_CAR.md) §8, notes: lead step 18).
- **Give each lamp the emissive mask** at import (notes: import).
- **Projectors were dark at any strength** because Roblox multiplies the emissive by the colour map,
  and the atlas under them was a dark lens texture. A white colour map at import fixed it [measured]
  (notes: import, 04:31-04:47).
- **Lens glass is its own set**, not window glass, so the lamp shows through it. Nothing opaque may
  sit in front of a lamp: the DR458's polish pass deleted reflector lips until the lamp was the
  first surface (notes: polish item 5).

### 10. Glass and mirrors

- **Glass faces outward, so from inside it is culled.** Checks draw each glass mesh with a reversed
  twin, so a gap seen through the glass counts as glass, not as a hole (notes: lead step 11).
- **In the cockpit view the windows switch to see-through plastic**: Roblox's Glass draws no
  particles behind it (`Controllers/CockpitGlazing`, [README](../../games/drive-lab/README.md)).
- **Reflectance shows only the skybox** ([10](../research/10_car_materials_and_wet_look.md) §2.1).
  A mirror with Reflectance reads as a sky-blue shape. The interior mirror gets a baked image of what
  it shows; door mirrors get a flat dark set ([HERO_CAR](../pipelines/HERO_CAR.md) §14).

### 11. Budget

- **At most 10,000 triangles per piece** (the DR458 plan; Roblox's limit is 20,000 per mesh,
  [03](../research/03_car_model_sourcing.md) §5.1). Set per-area lines and meet them. The DR458's lines:
  exterior 90k, wheels 38k, engine 12k, cabin shell 23k (notes: lead step 4, lead5 handoff).
- **The final car** [measured]: 287 pieces, 190,290 triangles, largest piece 7,156 (notes: import,
  second import).
- **Decimate with the outline protected:** weld first, and give the outline weight 0 in the vertex
  group (0 protects). Otherwise slits open at object edges (pitfalls).

### 12. Manifest and binding points

- **One manifest per area, merged and validated** (`manifest/merge_manifest.py`):
  - parts with group, motion, pivot, axis and range, in the frame {forward, right, up};
  - named points: Driver_Eye, the windscreen corners, the wiper's blade ends;
  - contract names for everything that moves (the parts draft).
- **The binding writer turns it into the car's config**: `lune run games/drive-lab/tools/dr458_binding --write`,
  built on `games/drive-lab/tools/ManifestBinding.luau`. It throws when a part it needs is missing.
- **Ask the consumer for the format before writing it.** One message saved a rework (notes: lead
  step 6).

### 13. Assemble, then export (never the master alone)

- **The export input is the assembled car**: the master plus the cockpit parts files. On the master
  alone the cockpit parts are missing, and the export's own check fails (notes: import, 01:24).
- **What the export does:** one piece per material, pieces over the limit halved, metres to studs,
  lit faces turned toward the driver, a TANGENT on every primitive. It reads the glb back and exits 1
  on any gap (`export_dr458.py`, work folder; [HERO_CAR](../pipelines/HERO_CAR.md) §4 for the SVJ's
  `hero_car_export.py`).
- **Check sizes on the glb, not on the export's own report.** The glTF writer drops loose vertices
  (notes: import, 01:53).

### 14. Import checks

- **Keep the Studio build script as a file**: the first import's script had to be recovered from a
  transcript (notes: import, second import).
- **Place the new car by the offset of pieces that did not change**, and keep the old car as an
  untagged backup (notes: import).
- **Studio raycasts lie on this car** (collision hulls, not render faces): judge lamps by captures
  (notes: import, 04:29).
- **Agents need the owner's go** for Studio, uploads and publishing. Uploads go through the
  coordinator.

## Hand-off to animation

The animator's side is in [ANIMATION.md, "Inputs the model must give"](ANIMATION.md#inputs-the-model-must-give).
The model owes it:

- **Stable pivots and names.** Every control the hands touch has a manifest name, pivot, axis and
  travel that do not move between versions. A change goes to the animator first. The polish pass
  tilted two button caps about their own pivots and told the animator, and an independent dump diff
  confirmed nothing else moved (notes: polish).
- **Clearance against the seated avatar.** Soft parts (the harness, padding) are checked by
  triangle-interior sampling against the avatar's primitives, not by vertices. A worn strap passed a
  vertex check while 1.43 cm inside the torso (notes: polish item 1).
- **Worn and stowed sets for the harness**, and a check against the entry's swept volume (an npz
  from the animator) once it exists (notes: polish handoff).

## What reads as realistic in Roblox

Measured or documented:

- **Scale first.** Real metres, the game's 1.5× world, and the eye at the real height from the real
  seat. A wrong eye height makes every other fix look wrong (§13, README decisions).
- **What the camera shows.** The cockpit field of view is 60° (README decision, 2026-10-28). At that
  distance the wheel, the binnacle, the dash top, the A-pillars and the mirror fill the frame. A check
  result only matters where a game camera sees it (notes: lead, the bar).
- **MeshParts are single-sided.** A face seen from behind is invisible, so a body panel seen from
  inside needs a reversed copy ("backing", notes: lead step 11).
- **Reflections are the skybox only**: no other parts, no other cars
  ([10](../research/10_car_materials_and_wet_look.md) §2.1). Mirrors and chrome need a baked image or
  a dark set, not Reflectance.
- **Paint has no clear coat** in Roblox. Start from the library's paint sets ([10](../research/10_car_materials_and_wet_look.md) §1).
- **Maps:**
  - tangent-space, OpenGL-green normal maps;
  - a source normal map with two channels (flat reads olive) needs its blue rebuilt;
  - n-gon caps lose their tangents, so triangulate them;
  - see [HERO_CAR](../pipelines/HERO_CAR.md) §12 and notes: lead step 14, import.
- **UVs outside 0..1 repeat**, measured on EditableMesh in Studio only, not yet on an uploaded mesh
  ([10](../research/10_car_materials_and_wet_look.md) §3.1).
- **Emissive is multiplied by the colour map:** a lamp over a dark texture stays dark (notes: import).

What did not matter [judgement, from the owner's bar and the seen-only checks]:

- millimetre precision;
- faces no game camera reaches: under the floor, inside closed panels, behind opaque bulkheads;
- surfaces the eye only sees at a glance, which can stay flat sets.

## Checks

The DR458's check scripts live outside the repo, in `drive-lab-assets/dr458/work/checks/`
([HERO_CAR](../pipelines/HERO_CAR.md) §13). The repo tools live in `tools/blender/` and `tools/assets/`.

| Check | What it catches |
|---|---|
| Holes from the eye | sky seen through the body from the seat; new holes vs the last master |
| Window-through | rays through a window that leave the car through no glass |
| Seen depth fights | coplanar pairs a game camera actually sees, sized in pixels |
| Clashes | new pieces crossing the car; soft parts inside the avatar |
| Export dry run | missing parts, oversized pieces, missing tangents, bad names |
| Read-back | a written map that differs from what was meant |
| Tool self-checks | each tool's own rules (pad gap, aim, sweep, UVs) |

**Commands** (Blender is `blender -b <file> --factory-startup --python-exit-code 1 -P <script> -- <args>`):

- **Holes:** `checks/render_ids.py <out dir> <seed>` on the old and the new assembly, then
  `python -I checks/holes_check.py <before> <after> 0.0005 [--absolute 200]`.
- **Window-through:** `checks/window_through.py <out.json>`. `--break bay` removes the engine bay, so
  the check fails.
- **Seen fights:** `checks/zfight_seen.py <out.json> <manifest> 20 --controls [--seams-shared]`.
  Compare against the last master's run: the scan's sampling shifts when objects change, so read the
  new pairs, not the exit code.
- **Harness:** `checks/harness_check.py <avatar prims> <out> --keepout <json> [--swept <npz>]`.
- **Export:** `assembly/assemble_preview.py <asm.blend>` on the master, then
  `assembly/export_dr458.py <manifest> <out dir>` on the assembly.
- **Manifest:** `python -I manifest/merge_manifest.py <out> <area files...>`.
- **Materials:** `tools/blender/car_materials_apply.py <car> <map> --out <out>`, `tools/assets/car_material_map_check.py`,
  then `tools/assets/car_surface_appearances.py` (each with its `--break`).
- **Mirror and wiper:** `tools/blender/car_mirror.py` and `tools/blender/car_wiper.py`, with their
  `--break` lists ([HERO_CAR](../pipelines/HERO_CAR.md) §14).

**The --break discipline.** Every check has a deliberate break that must make it fail, run once per
change: a check never seen failing proves nothing ([AGENTIC_WORKFLOW](../engineering/AGENTIC_WORKFLOW.md),
evidence standard). It pays: running `car_wiper --break clear` showed the wiper's range could collapse
to 0° and still pass, so a rule was added (notes: mirror_wiper step 9).

## Time

### The DR458, per stage [measured, from the notes]

Hours are agent working time as each agent wrote it ("about"). Several agents ran in parallel.

| Stage (agent) | Hours | Source |
|---|---|---|
| Master v1-v9: body, Evo parts, wheels, aero, cabin (leads 1-2) | ~1.2 + untimed | master file times 19:03-20:16 |
| Clean-up, budget, fights, backing, export, manifest (leads 3-5) | ~9.5 | lead steps 1-21 |
| Cockpit: eye, cage, wheel, dash, rest, harness (cockpit artist) | ~9.3 | cockpit "Times" |
| Materials: map, apply, debadge, contract, livery | ~4.8 | materials steps (clock 22:58-01:25, steps overlap) |
| Polish: harness fit, fights, lamps, fog | ~6.2 + 1.5 waiting for RAM | polish "Times" |
| Export, upload, import, Play check, two imports (systems) | ~2.5 | import, 01:05-02:33 and 04:01-05:00 |
| Mirror and wiper (3D artist) | ~2.8 wall clock | mirror_wiper, 13:20-16:05 |
| **Total** | **~36 agent-hours** | |

[measured] The first drivable import ran about 7 hours after master v1: master v1 at 19:03 on 30 October,
the first Play check at 02:05 on 31 October (notes: import).

**Missing:**
- the Codex/ChatGPT Evo parts and the first lead's sourcing before master v1;
- the fourth lead's step 12 (the seen-fights reading);
- the v17 re-import, still running when this was written.

### The SVJ [measured bounds only]

No notes recorded the SVJ's times. The game-kit history gives bounds, not effort:
- the hero car pipeline scripts landed in one commit on 2026-10-27 at 21:39;
- that evening's SVJ commits (physics core, pipeline scripts, body lift, cluster face) run from 20:18 to 23:11;
- the door pipeline on 2026-10-28 runs from 16:26 to 17:39 (commits);
- the lamp split from 22:09 to 22:43 (commits).

### What ate the time [measured]

- **Cage:** 2 h 30 with three wrong turns (cockpit step 2).
- **Harness:** 2 h 15 of work over seven measured iterations, plus 1 h 30 waiting for RAM (polish item 1).
- **Visibility cut and decimation regressions:** footwell holes, slits; about 2 h 50 (lead steps 1, 4, 10).
- **Depth fights:** 1 h 30 plus untimed reading and 1 h of probing (lead step 2, polish items 2-3).
- **Export failures:** duplicate names, a segfault, missing tangents; about 1 h 15 (lead steps 14-16).
- **Livery:** 1 h 50 (materials).
- **Waits:** RAM and locks around Studio and parallel Blender jobs (polish, import); EEVEE renders
  about 3× slower in the afternoon (mirror_wiper step 12).
- **Rework from measuring wrong:** the wiper placed from a pixel scale (30 min, mirror_wiper step 7).

### Car 3: target and shortcut [judgement]

| Stage | Target | Shortcut |
|---|---|---|
| References + base model | 1 h | the reference list above; research 03's licence table |
| Camera solve + scale | 0.5 h | solve 2-3 photos, check by projected outline |
| Clean-up | 3 h | rerun the DR458 cut, budget and backing scripts with today's rules |
| Cockpit | 3 h | the DR458 cockpit build scripts (work folder `cockpit/scripts`, `cockpit/lead_scripts`), re-parameterised |
| Materials | 1.5 h | the library sets as they are; rules by material name |
| Polish | 2 h | soft parts routed by control points, checked by triangles from the first build |
| Export + import | 1 h | assemble + export runner; the Studio build script kept as a file |
| Mirror + wiper | 0.5 h | `car_mirror.py`, `car_wiper.py`, a solved camera |
| **Total** | **~12-13 h** | vs ~36 agent-hours for the DR458 |

The shortcut that matters most: **the rules in the pitfalls below exist now.** The DR458 paid for
discovering them. Car 3 starts with them in the scripts.

**The per-car contract** (`Config/Cars/<Car>/`, `Config/Cars/Contract.luau`, "Wiring a new car" in
the [README](../../games/drive-lab/README.md)) means a new car is data plus a binding, with no new game code.
Plan the import early, so animation and controls never wait on polish [judgement, owner 2026-10-30:
drivable first].

## Pitfalls

Each entry is **symptom → cause → fix**, with its source.

### Geometry and clean-up

- **New holes in the footwell after a visibility cut** → the cut treated faces met from behind as
  occluders, and looked from the wrong eye range → single-sided rays and viewpoints from the game's
  camera limits (notes: lead step 1).
- **Slits along object edges after decimation** → the outline retreated while the deviation passed,
  and a vertex-group weight of 1 leaves a vertex free (0 protects) → weld first, give the outline
  weight 0, check the outline itself (notes: lead step 10).
- **Body panels seen from behind from the seat** → MeshParts are single-sided, and the holes check
  only failed new holes → reversed backing copies, and glass twins in the holes frames (notes: lead
  step 11).
- **The depth-fight fixer moved the windscreen frit and deleted the faces behind lamp lenses** → glass
  and lens pairs treated like paint → list them, never move them (notes: lead step 11).
- **A "depth fight" between parts that only share an edge** → the scan counts long shared seams →
  ray-test along the normal first; `--seams-shared` (notes: polish item 2).
- **Deleting filler faces opened new sky** → faces turned away from the eye counted as cover → same-facing
  only (notes: polish mistakes).
- **The rear window was a black wall from inside** → a filler skin covered it 6 mm in front of the glass
  → delete only the covering faces, then check rays through the window (notes: mirror_wiper step 4).
- **Parts land at the world origin when files are assembled** → their parent empties were not linked →
  link every appended object (notes: lead step 5).
- **Topology steps misbehave on a game mesh** → split edges at every UV seam → weld first (notes: lead
  shortcuts).

### Materials and lamps

- **Roughness map written as zeros** → colour space set after the pixels on a generated image → set it
  first, read the file back (notes: mirror_wiper step 11).
- **Projectors dark at any strength** → emissive multiplied by a dark colour map → a white colour map
  at import (notes: import).
- **Livery text reads backwards on one side** → the body's paint UVs are mirrored → bake a separate atlas
  per side ([HERO_CAR](../pipelines/HERO_CAR.md) §12).
- **Blacks look blue-grey in renders** → a blue sky light → judge under overcast (§12).
- **The mirror is a sky-blue shape** → Reflectance shows the skybox → a baked image or a dark set (§14).

### Export and import

- **Export fails with duplicate names, then segfaults** → several slots per material, and a freed object
  written into a property → merge the slots by material before splitting (notes: lead step 16).
- **Primitives without tangents** → n-gon caps → triangulate before export (notes: lead step 14).
- **150 manifest parts with no piece** → exported the master alone → assemble first (notes: import, 01:24).
- **A piece looks smaller in Studio than in the report** → the glTF drops loose vertices → measure the
  glb (notes: import, 01:53).
- **Raycasts say a lamp is hidden** → collision hulls, not render faces → captures (notes: import, 04:29).
- **The export's summary never printed** → the runner's `head` filled with INFO lines → filter them
  (notes: lead step 16).

### Measuring and checking

- **A part placed 8 cm off** → scaled from a photo by pixels → a solved camera, checked by projected
  outline (notes: mirror_wiper step 7).
- **A strap 1.43 cm inside the torso passed** → the check read vertices only → sample triangle interiors
  (notes: polish item 1).
- **A wiper that barely moves passed every pose** → its range collapsed to where it first met the car →
  fail any range under the minimum sweep (notes: mirror_wiper step 9).
- **A contract face grew 5 cm** → its script measured the master, which had changed → freeze the outline
  to a file ([HERO_CAR](../pipelines/HERO_CAR.md) §13).

### Running jobs

- **A script raised, and the run reported success** → Blender exits 0 → `--python-exit-code 1`
  (notes: lead step 15).
- **A failed bake overwrote shared maps** → the chain ran on → stop at the first failing job
  (notes: lead step 17).
- **A lock left behind** → the runner killed by `timeout`, or a batch stopped from its parent only →
  never wrap it in `timeout`; stop the whole process tree, then remove only your own locks
  (notes: lead shortcuts, mirror_wiper step 10).
- **A runner behaved strangely mid-run** → it was edited while running (`sh` reads as it goes) →
  write a new file (notes: polish run log).
- **Evidence renders took 20 minutes a view** → EEVEE slowed for a reason not found → render evidence
  with Cycles on the CPU (29 s a view) (notes: mirror_wiper step 12).
