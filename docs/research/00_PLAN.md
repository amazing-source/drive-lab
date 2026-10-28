# Drive Lab: plan and status

Started 2026-10-27. One car, the highest realism reachable in Roblox: driving, exterior, interior
and the effects around it. The owner's brief (written with ChatGPT, for Claude and Codex) is the
reference; this file tracks where the work stands, so it survives a context reset.

## Split of work (from the brief)

- **Claude:** Luau architecture, controls, chassis, tyres, suspension, engine and drivetrain,
  driver assists, mechanical states, network physics, telemetry, tests, the exterior and interior
  model, the rig of moving parts, mechanical animation, vehicle PBR materials, mechanical audio.
- **Codex:** HUD, menus, cockpit screen content, visual direction, post-processing, presentation
  camera, rain, spray, smoke, skid marks, flames, headlight visuals, droplets and other VFX.
- **Boundary:** Claude publishes physical state (telemetry), events, dashboard surfaces, pivots and
  attachments. Codex consumes them. One producer per state.

## Owner's targets added on 2026-10-27

- A fully working, realistic car: first-person and third-person modes; a cockpit that comes alive
  (instruments, headlights and every light); in first person the player's own hands are on the
  wheel and follow it (IK to grip points on the rim).
- Config-driven: another car can be added for testing with a config and a model, no code rewrite.
  The SVJ itself is naturally aspirated: no turbo in its config, but the config supports one.
- Shiny and reactive: glossy paint and materials with the reflections Roblox can actually render
  (no real-time reflections of nearby moving objects exist), and a dry/wet material state for rain
  (drops and spray stay Codex's). Research: `10_car_materials_and_wet_look.md`.
- Order agreed: **the car imported and working first**, then the interior, systems and polish.

## Out of scope for this stage

No map, city, traffic, race, mission, economy, shop or second car. A neutral test bench only:
flat ground, a dry/wet strip, suspension calibration bumps, a removable lighting panel.

## Phases (each one ends with files or measurements someone can check)

1. References studied, useful captures, architecture choice.
2. Numbered mechanical model of the car, and the telemetry contract (v1) for Codex.
3. Physics prototype on the neutral bench (proxy body).
4. Calibration: controls, suspension, tyres, transmission, against measured targets.
5. Final exterior/interior model and mechanical animation.
6. Integration of Codex's UI/VFX modules.
7. Side-by-side comparison of captures and measurements, fixing the gaps.

Rules carried over: plan before code and wait for the owner's go; two adversarial breakers per
change; no publish; Studio work in a separate place, never the Rob A Car place.

## Phase 1 research (running 2026-10-27)

| File | Topic | Status |
|---|---|---|
| `01_sim_vehicle_dynamics.md` | How AC, ACC, BeamNG, GT7 and Forza model and tune cars; tyre/suspension/drivetrain/aero models; tuning targets; input filtering; numerical stability | done 2026-10-27. Key finding: wheel spin is the stiffest state (an explicit step is stable only above about 260 km/h at 60 Hz, 65 km/h at 240 Hz), so it needs internal sub-steps or an implicit update. Its assumption that script-set forces hold through Roblox's 240 Hz steps matches `04` (a constraint force stays constant across the frame's physics steps) |
| `02_aventador_svj_data.md` | SVJ data, sourced or marked as estimates | done 2026-10-27. Sim mass 1,845 kg (1,770 kg measured with fluids + 75 kg driver); effective rear reduction 3.52, not the published 2.867 (EPA rpm/mph and front axle ratio agree); CG, inertia, torque curve and aero are estimates with calibration targets. The video's 0.82 upshift step matches the real 4-5 / 5-6 steps within 1 % |
| `03_car_model_sourcing.md` | Free, licensed, realistic car models with interiors; Roblox import limits; import plan | done (pass 1): no free SVJ with a full interior and a trustworthy licence; picks Blendkit Revuelto (private lab) and Blendkit Auro PL concept (publishable); saw no images |
| `03b_car_model_sourcing_pass2.md` | Exhaustive pass 2 at the owner's request: Sketchfab API with many pages, Blendkit, other stores, Roblox Creator Store, images actually viewed | done 2026-10-27. Pick: ddiaz-design "2019 Lamborghini Aventador SVJ" (Sketchfab 1910d24bbad34fdda0c4fe30f01b3cc1, CSR2 extract, about 212k tris, separate interior/wheel/caliper/light texture sets, 512 px textures); fallback Haris3D Aventador LP750-4 SV (1024 px); #2 AnatolianStudios Revuelto would mean a hybrid powertrain. Ranked on quality only (owner's decision). Download needs a Sketchfab login in the owner's Chrome |
| `08_how_sims_use_real_data.md` | How studios turn real car data into game cars, where they deviate and how they validate | done 2026-10-27. Adopt: the physical car stays built from data; all keyboard/gamepad help lives in a separate input layer; generic road-tyre family tuned to the SVJ's measured targets; validation ladder (targets, then a driver). Don't adopt: balance-of-performance or "easier" car numbers; numbers from mods (the AC SVJ mod uses the 1,520 kg dry weight). Reddit and the big sim forums were blocked to the agent, and the Chrome extension blocks Reddit too |
| `09_roblox_import_pipeline.md` | Owner chose the SVJ (2026-10-27). Extensive research on getting it into Roblox and optimized: current limits, import routes (Studio importer, Blender add-on, Open Cloud), how "whole game" imports were done, hero-car optimization (draw calls, LOD, texture memory, collision), materials and texture upscaling, EditableMesh, a scripted end-to-end pipeline with checks | done 2026-10-27. 20k tris per MeshPart, no per-model cap, over-cap meshes are silently simplified (so compare counts); 4K textures live since 2026-01-30 via streaming (not on phones under 3.5 GB); route = Blender split + pivot manifest, Open Cloud upload (repo already does it for the traffic cars), Studio assembly by script; upload one wheel and clone it; per-camera detail via LocalTransparencyModifier (to test); pilot with one wheel + one panel first; 15 checks. Gaps: how the big Roblox car games build their cars, and primary sources for the famous game imports |
| `07_visual_references.md` + `references/` | 17 curated references (SVJ interior from Lamborghini's page, cluster launch video, exterior views, GT7 cockpit, DRIVECLUB rain, ACC spray, Forza paint, BeamNG damping, sound sources) | done 2026-10-27. `references/` holds copyrighted stills: never commit it |
| `06_audio_sourcing.md` | Licensed engine and car sound sources, procedural routes (engine-sim), reference listening with timestamps, Roblox audio rules | done 2026-10-27. Route: engine-sim (MIT) V12 recorded at fixed rpm and load (14 rpm steps x on/part/off x interior/exterior, about 90 loops, 32 for a first pass), matched by ear and spectrum to real Aventador recordings (free Sonniss GDC 2020 rev ramp and pass-bys, commercial use allowed); real free recordings for tyres, wind, rain; optional paid Pole Position Aventador library ($249, owner's call). Upload as OGG under the group. Caveat it raised: Roblox Creator Rewards may pay any public experience, so keep the place private while it holds any non-commercial asset (claim to verify). **Pass 2, quality only (owner's decision):** fastest best result = decode an Assetto Corsa car sound bank (FMOD `.bank`, rpm x throttle loops, interior/exterior) with vgmstream; stock-closest file is Kunos's `ks_lamborghini_aventador_sv`; needs the file from the owner's other PC or a mod download. Placeholder for code testing: public Creator Store SVJ/Aventador engine sounds by asset id (listed in the note) |
| `07_visual_references.md` | The brief's 12-18 curated references (cockpit, cluster, exterior, GT7, DRIVECLUB rain, ACC spray, Forza materials, BeamNG suspension, SVJ onboard) | running |
| `04_roblox_engine_facts.md` | Units, simulation loop, forces, casts, network ownership, audio/rendering APIs, verified against current docs | done 2026-10-27 (10 Studio tests T1-T10 to run before phase 3) |
| `05_video_observations.md` + `video_analysis/` | Frames, exhaust timing at 60 frames/s, engine-order audio track | done 2026-10-27 |

Decisions the engine facts put on the owner's table (for the phase 1-2 package):
- **Gravity.** Roblox's default gravity is 196.2 studs/s², about 5.6 g at 0.28 m per stud; the docs
  call 35 studs/s² realistic. Either set `Workspace.Gravity` to about 35 for this place (simple,
  every real spring and tyre number then works as is; characters jump differently), or keep the
  default and cancel the extra weight with a per-car force (keeps the world as is, but every
  contact force the engine computes still sees 5.6 g).
- **Loop.** No script runs once per 240 Hz physics step; the recommendation is the model on the
  driver's client in `PreSimulation`, with internal sub-steps of about 1 ms, forces summed into
  one `VectorForce` and one `Torque` at the centre of mass.
- **Network.** Driver ownership with server plausibility checks now; the model written as a pure
  step function so it can move to Server Authority later.

## The chosen model (owner, 2026-10-27): ddiaz-design SVJ

- Files: `C:\Users\bfhdh\Downloads\drive-lab-assets\svj_ddiaz\` (original FBX in
  `fbx/source/final_model/FINAL_MODEL.fbx` with its textures; glTF in `gltf/`). Downloaded through
  the owner's Chrome after they signed in to Sketchfab.
- Blender: `C:\Users\bfhdh\tools\blender-5.2.2-windows-x64\blender.exe` (stable; a 5.2.3 candidate
  also sits in Downloads). Run headless with `-b --factory-startup --python`.
- Measured in Blender (FBX is in centimetres, scaled x100): 4.945 x 2.274 x 1.071 m (real car
  4.943 m long, 2.273 m with mirrors). FBX axes: long axis Y, **front at -Y**, Z up. Left-hand
  drive: the steering wheel is on the +X seat. A good seated eye point is about
  (x +0.36, y -0.05, z ground+0.86) m in FBX space.
- 211,767 triangles. Over Roblox's 20k-per-mesh limit: interior 41.5k (one mesh, steering wheel
  inside it), coloured plastics 36.6k, paint 33.0k, carbon 23.8k. Under: engine 19.7k, lights
  6.5k. Wheels already separate per corner (about 8.8k each, 200+ small pieces each, to merge).
  Calipers already separate from the wheels. Doors are part of the body.
- Renders: `model_candidates/svj_ddiaz_renders/` (`svj_first_look.jpg`).
- **Debadged copy (owner's request, 2026-10-27):** `svj_ddiaz/clean/` holds `svj_clean.blend` (in
  metres) and the cleaned textures; the originals are untouched. Made by
  `video_analysis/debadge_textures.py` (paints over the shields on the steering wheel and wheel
  caps, the dashboard start-up shield, the engine label, the Pirelli/P Zero/Trofeo R sidewall
  lettering; blanks the badge and caliper-lettering textures and the plate) and
  `video_analysis/blender_debadge.py` (deletes the badge object: nose shield, rear lettering, side
  SVJ decals; repaints the 766 black "SV" livery faces body colour; forces the cleaned files
  because **the FBX embeds its own copies of the textures**). Checked in renders under
  `clean/check_renders/`. Left as is: the shield-shaped recess in the bonnet and the shield-shaped
  hub of the steering wheel (plain geometry, no graphic). The car needs a generic name in game.

## Import into Roblox (2026-10-27)

- Branch `feat/drive-lab`, worktree `C:\Users\bfhdh\Downloads\rbx-game-kit-drivelab` (from
  `origin/speed-redesign`). Scripts: `tools/blender/hero_car_pilot.py`,
  `tools/blender/hero_car_export.py`; upload with `tools/assets/upload_images.py <user id> <glb>`
  (key owner rencoolbro = 2746107833; `unset ROBLOX_OPEN_CLOUD_API_KEY` first in an old shell).
- **Pilot** (asset 124615722896386): one glTF unit = one stud; triangle counts arrive unchanged;
  **Roblox's importer turns a glTF model 180 degrees about Y**, so the export keeps the nose along
  Blender -Y and Roblox ends up with it along -Z; only the colour map comes through (as
  `TextureID`), so PBR maps must be uploaded and applied with SurfaceAppearance.
- **Full car** (asset 103532236855246): 36 exported pieces under 18k triangles each, by material
  and by moving part (4 wheels, 4 calipers, 5 interior, 6 glass, 2 paint halves, 3 carbon, 7 trim,
  engine, lights, underbody, plate); in Studio: 38 MeshParts, 211,234 triangles (identical),
  bounding box 8.121 x 3.808 x 17.642 studs, wheels at FL (-3.109, 1.297, -4.821) and so on, nose
  at -Z. Wheelbase 9.643 studs = 2.700 m, as on the real car. Two more MeshParts than exported
  pieces: to identify. Inserted as `workspace.CarImport` in an unsaved empty place (Place1).
- Studio's viewport capture comes back black in that place (CaptureService fallback); visual
  checks need the owner's eyes or a playtest capture.
- **Materials pass (2026-10-27, place "Expérience sans titre" 125864048446486, model asset
  113298924737852 re-exported with tangents):** the glTF importer only carried 6 colour maps, so
  materials are built by script: 31 SurfaceAppearances (colour, normal, roughness, metalness,
  emissive), 6 glass panes as Glass material, RenderFidelity Precise, LightingStyle Realistic +
  PrioritizeLightingQuality (the old "Technology" property no longer exists), environment scales 1,
  paint (150, 70, 140). Image ids in `drive-lab-assets/svj_ddiaz/maps*/`. Per-pixel roughness
  (1 - gloss^0.8) and metalness from the source's material masks (R = metalness, G = gloss,
  B = opacity). **Mistake fixed:** the cockpit and lights carry a second UV set, UVChannel_2, used
  by their emissive textures; merging those pixel-for-pixel painted red glyphs over the steering
  wheel and mirror. `tools/blender/hero_car_bake_emissive.py` now bakes them into UVChannel_1 at
  2048 px, and the colour + glow maps are rebuilt from that.
- Captures from Studio show the owner's own viewport when they move the camera; setting
  workspace.CurrentCamera from a script does not hold while they inspect.
- Real-ESRGAN v0.2.5.0 (official GitHub build, 45.5 MB, owner's go 2026-10-27) installed at
  `C:\Users\bfhdh\tools\realesrgan\`. The 4x upscale sharpens edges but shows the source cockpit
  texture is nearly flat colour: realism needs added material detail. An agent bakes per-zone
  detail (Alcantara, perforated leather, clear-coated carbon, satin plastic, metal) in object space
  into UVChannel_1 at 2048, guided by the real SVJ photos (references R01, R02); output in
  `drive-lab-assets/svj_ddiaz/interior_v2/` with before/after renders and a REPORT.md.
- Open interior items (earlier list): upscale the 512 px textures (done for the cockpit colour), an "SV"
  emblem left on the seats, mirrored text on the overhead console (source or conversion?), and the
  owner's "chopped" impression to re-check after the glow fix.

## Inputs received

- 2026-10-27: the owner's reference pack, extracted to `reference_pack/`. It holds the full brief
  with the FEEL section (`01_PROMPT_CLAUDE_FEEL.txt`, which supersedes the first brief), the look
  target, six 1 frame/s sheets, eight 1080p frames and two 10 frames/s motion sequences. What the
  frames show is in `05_video_observations.md`.
- The FEEL section asks, before any code, for a lived 20-second drive (pull away, accelerate,
  shift, gentle turn, brake), with each sensation tied to a measurable mechanism, and three
  sentences per system (what the player feels, which signals produce it, how to check it).

## Missing inputs

- The full reference video, with its sound (`LAMBORGHINI AVENTADOR SVJ _ Assetto Corsa.mp4`), is
  still only on the owner's other PC; needed to measure timing and listen to the engine.
- For phase 3: a new Baseplate place open in Studio on this PC (the Studio connection only
  reaches this machine).
