# 10: Car materials and the wet look

Researched 2026-10-27. Web search and web fetch only: no login, no browser automation, no asset
downloaded, Studio not touched. Builds on `04_roblox_engine_facts.md` (section 7.1),
`09_roblox_import_pipeline.md` (section 5) and `05_video_observations.md`. Where this note and
those files overlap, this one is newer.

**Tags.**
- [DOC]: Roblox documentation, read on the date above (the create.roblox.com page or its source in
  the `Roblox/creator-docs` GitHub repo).
- [ANN]: a Roblox staff announcement. [STAFF]: a staff reply.
- [COMM]: a community post (not official). [SNIP]: seen only in a search-result snippet.
- [REF]: a rendering reference from outside Roblox (Lagarde, Filament, Unreal).
- [MEAS]: measured by me today (numbers from the reference frames).
- [INF]: my inference. [TEST]: must be proven on the bench before we build on it.
- [BETA]: a beta feature, or a feature whose release status I could not confirm.

**Gaps, said plainly.**
- The session's shared search budget (200 searches) ran out during this pass. Not done: GitHub
  searches for wet-car modules, more DevForum showcases, and X posts beyond what one search
  returned.
- **No YouTube video was watched.** The titles in the sources come from search results, so there
  are no timestamps. None of the claims below rests on a video.
- No DevForum post was found that shows a "wet car" effect on a Roblox car. The closest
  precedents are wet *world* surfaces (section 4.4).

---

## 0. Recommendation on one page

**The ceiling, in one sentence.** Roblox gives one PBR layer per surface (colour, normal,
roughness, metalness, emissive). It reflects the sky outside and a periodically refreshed local
environment map in covered areas. It does not reflect nearby moving objects, has no clear coat
and no anisotropy, and its maps cannot be edited by scripts. So the look is won by three things:
**the lighting and sky the paint reflects**, **clean per-material values**, and **layering** for
wetness. The paint shader cannot win it on its own.

**Lighting (bench place, set at edit time).**
- `LightingStyle = Realistic` and `PrioritizeLightingQuality = true`. That gives per-pixel local
  lights with specular highlights, and keeps lighting quality when the device drops quality
  level [DOC; ANN 2025].
- `EnvironmentSpecularScale = 1` and `EnvironmentDiffuseScale = 1`. Both default to 0 in the API
  docs, and with the specular scale at 0 "metalness has no effect" [DOC].
- One custom sky per exterior preset, with a darker lower half [DOC tutorial]. In the tunnel, warm
  local lights do the work.
- Three presets: tunnel (warm), exterior blue hour (cold), and the exit between them. Section 6.2
  gives values to start from.

**Paint: one layer, no texture, tuned by measurement.**
- SurfaceAppearance with:
  - no colour detail: `TintMask` with a white 4×4 ColorMap, colour in `SurfaceAppearance.Color`;
  - a constant 4×4 roughness map, **0.08–0.15**;
  - metalness **0** (sweep 0.15–0.45 if the pearl look needs tinted reflections);
  - a flat normal map, or none.
- Colour stays scriptable. Section 1.2 says why a pink-violet base turns copper under warm light
  and violet under cold light, as the reference does.
- **A clear-coat shell is an experiment, not the plan.**
  - A transparent shell can only *blend* its reflection in: it caps the reflection at its own
    opacity and darkens the paint under it.
  - A Glass-material shell keeps the reflection, but it brings refraction and hides every
    transparent object behind it.
  - Test it once (M2, M7); adopt it only if a capture shows the gain.

**Reflections: what to expect, and the tricks worth using.**
- Expected:
  - the sky outside;
  - in the tunnel, the engine's local "indoor" environment map, which refreshes over time
    (what it contains is undocumented: [TEST] M3/M4);
  - the specular highlights of the lights;
  - screen-space reflections only on terrain water [COMM].
- Tricks:
  - a sky swap per zone (Sky properties are scriptable [DOC]);
  - emissive ceiling panels in the tunnel, so the highlights and the environment map have
    something bright to show;
  - a ViewportFrame rear-view mirror, in the cockpit only and small: it renders no shadows and
    no post-processing, and its environment scales are 0 unless it has a Sky child [DOC].

**Other materials:** see the spec table (section 6.1). The headlines:
- **Glass:** not the Glass material in the cockpit when it rains. Glass hides particles and every
  other transparent object behind it [ANN 2017; COMM 2025], which would delete the rain. Use a
  transparent SurfaceAppearance pane, and switch the windscreen's `Material` locally by camera
  mode [TEST M10].
- **Emissives:** final colour = (mask × strength × tint + light) × ColorMap [ANN]. A dark colour
  map dims the glow, so LED areas need a bright colour map.
- **Brake-disc glow** is possible: a ring emissive mask, with `EmissiveStrength` and
  `EmissiveTint` driven by brake temperature.

**Wet state (rain): three layers, in order of value per cost.**
1. **Material state, no extra draw.**
   - Porous or rough parts (tyres, matte trim, matte carbon) darken and turn glossy.
   - Paint does **not** darken: it is non-porous and already glossy (Lagarde [REF]).
   - Mechanism: pre-built SurfaceAppearance variants, swapped in steps (a DevForum creator ships
     12 steps [COMM 2026-08-19]).
   - For the untextured paint, an `EditableImage` roughness map of a few pixels could give a
     continuous value instead [TEST M6]. It needs the experience's "Mesh / Image APIs" toggle.
2. **Droplet layer, one transparent pass over the top panels.** Two candidates to compare on the
   bonnet:
   - (a) a **shell mesh** of the top panels (bonnet, roof, engine cover, wing, upper wings), with
     a droplet SurfaceAppearance (`AlphaMode Transparency`, droplet normal map, roughness about
     0.03), faded in through `MeshPart.Transparency` (1 → 0.05);
   - (b) a **top-face PBR Decal** on those panels, faded through `Decal.Transparency` [BETA status
     unconfirmed; TEST M8].
   - Both fade smoothly. Both cost about one extra blended pass over the pixels they cover.
3. **Motion, Codex's side:** spray, run-off, beads blown back at speed, and glass droplets with
   wipers (DRIVECLUB, `07` R11/R12).
   - Running streaks on the side windows: a `Texture` with `OffsetStudsV` tweened by speed (the
     docs show tweening offsets for animated surfaces [DOC]).
   - Avoid many UV-animated decals on one part: staff call the cost "expected" (40 such decals
     dropped a GTX 1050 Ti to 20 FPS) [COMM/STAFF 2026-09-01].

**Cost and gates.**
- In chase view the car covers roughly 10 % of the screen, so one droplet layer is cheap [INF].
- **In the cockpit the windscreen covers most of the screen.** Allow one transparent windscreen
  layer only. Put the wet droplets into that pane's own SurfaceAppearance variant, and do not
  stack a second layer.
- Gate the droplet shell off on phones and at low quality [TEST M13]. Every gate needs a frame-time
  measurement (M9), not a guess.

**How we will know it is right (section 6.3).**
- The same chase framing as `LOOK_TARGET.jpg`.
- A grey ball and a chrome ball next to the car.
- Captures in each preset, scored by a Python script on the paint's median hue, saturation and
  value and its highlight fraction.
- Targets measured on the reference today [MEAS]:
  - tunnel paint hue **0–13°**, saturation about 0.53, value 0.55–0.71;
  - exterior paint hue **240–297°**, saturation about 0.3, value 0.15–0.47.

**Unproven, to settle on the bench before building:** M1–M13 in section 6.4. The most important:
- M3, M4: what the tunnel reflection contains, and how fast it refreshes;
- M6: whether an EditableImage-backed SurfaceAppearance updates live;
- M7, M8: shell versus decal droplets;
- M9: the frame-time cost on the owner's phone;
- M10: whether the Glass windscreen deletes the rain.

---

## 1. Paint

### 1.1 What Roblox gives a car body

- **Maps** [DOC]:
  - SurfaceAppearance has `ColorMap`, `NormalMap`, `RoughnessMap`, `MetalnessMap` and
    `EmissiveMaskContent`.
  - The map properties are **Plugin Security**: set at edit time, or at creation through
    `AssetService:CreateSurfaceAppearanceAsync` (EditableImage content only).
  - Scripts can change `Color`, `AlphaMode`, `EmissiveStrength`, `EmissiveTint` and
    `ResampleMode`.
  - The class description: "most SurfaceAppearance properties cannot be modified by scripts"
    because "the necessary pre-processing is usually too expensive during runtime".
- **Publishing packs the maps** [DOC]: "the engine bakes its individual texture maps into a
  single texture pack asset" (`TexturePackContent`).
  - Inference: two SurfaceAppearances that share colour and normal maps but differ in roughness
    may each carry a full pack, so wet variants could cost more memory than one extra roughness
    map [INF; TEST M12].
- **One specular lobe, metalness workflow** [DOC]:
  - "Studio uses only the metalness workflow".
  - "Metals only reflect light the same color as the metal".
  - The docs name no clear coat, no anisotropy and no sheen.
  - The dielectric reflectance (F0) is not documented. I assume about 0.04, as in standard
    metalness PBR [INF].
- **Fresnel** [DOC guide]:
  - Studio's processing aims for physical accuracy, so rough surfaces still show reflections at
    grazing angles.
  - "you can compensate by increasing your roughness map value by around 0.1 more rough".
- **Ways to tint** [DOC guide]:
  - `TintMask`: `SurfaceAppearance.Color` tints where the ColorMap alpha is 1, and "Tint masking
    is not affected by MeshPart.Color".
  - `Overlay` (the default): transparent ColorMap areas reveal `MeshPart.Color`.
  - "Tinting does not affect performance".
  - Both colour properties are scriptable, so the paint colour can change at runtime.
- **Device dependence** [DOC]: "Appearance of this object on a MeshPart depends on the user's
  device and graphics quality level."

### 1.2 Paint values to start from (all [INF]; each is swept on the bench)

| Parameter | Start | Sweep | Why |
|---|---|---|---|
| ColorMap | 4×4 white, alpha 1, `AlphaMode = TintMask` | none | The model's paint has no texture; colour goes in `SurfaceAppearance.Color` (scriptable) |
| Colour (sRGB) | **(150, 70, 140)**, a pink-violet | ±20 per channel | Check under warm light (1.0, 0.65, 0.4): about (150, 45, 56), red-copper. Under cold light (0.6, 0.7, 1.0): about (90, 49, 140), violet. That matches the reference's measured shift (hue 0–13° in the tunnel, 240–297° outside) [MEAS + INF arithmetic] |
| Roughness | **0.12** | 0.04, 0.08, 0.12, 0.18, 0.25 | Clear coat is glossy (Filament clamps clear-coat roughness at a minimum of 0.089 [REF]). The docs advise +0.1 for Fresnel [DOC]. Too low turns the paint into a sky mirror |
| Metalness | **0** | 0.15, 0.30, 0.45 | Partial metalness tints reflections with the paint colour (a pearl or metallic look) but cuts the diffuse colour and darkens the paint in a dark environment [DOC metalness; INF] |
| Normal | flat (none) | weak orange peel only if a 2048 test shows it | A 4.9 m body over 1024 px is about 5 mm per texel. Orange peel is finer than that, so it cannot show [INF] |
| Baked AO | **none on broad panels**; a faint cavity-only AO in vents and louvres is allowed | 0 / 15 / 30 % | TintMask multiplies the colour, so broad AO reads as dirt (`09` 5.1). Gaps and louvres need some darkness to read, as in the reference tunnel frame [INF] |

**There is no colour flop.** The reference paint looks pearlescent. Real flop (the hue changing
with view angle) has no Roblox equivalent [DOC: no such map]. Fresnel only lifts reflections at
grazing angles, so most of the reference's colour change must come from the light colour on the
diffuse paint. Lighting carries that, not the shader [INF].

### 1.3 A clear coat: the options and their cost

| Option | How | Gains | Costs and risks | Verdict |
|---|---|---|---|---|
| **A. One layer** (recommended) | Low roughness, metalness 0 | A dielectric gloss layer over a coloured diffuse base is already physically close to a solid clear-coated paint (F0 0.04, the same as polyurethane clear coat [REF Filament]) | No separate flake lobe under the coat | Default |
| B. Partial metalness | Metalness 0.15–0.45 | Reflections pick up the paint colour, a "candy" look | Loses the sharp white clear-coat glints; darker in a dark environment | Sweep it; adopt only if a capture looks closer |
| C. Transparent shell, normal material | Duplicate the paint mesh, offset 3–5 mm along the normals; SurfaceAppearance roughness 0.03, black ColorMap, `MeshPart.Transparency` about 0.7 | A separate gloss layer over a rougher, more metallic base | Alpha blending scales the shell's reflection by its opacity (here 0.3) and darkens the paint under it by the same amount [INF from alpha blending]. The whole body is drawn twice; per-part transparency sorting against the glass [DOC BasePart]; z-fighting if the offset is too small [TEST M7] | Likely worse than A. Test once |
| D. Glass-material shell | The same shell with `Material = Glass`, Transparency ≥ 0.5, `Reflectance` up | Glass keeps sky reflections while see-through: "Reflectance determines how much light comes from reflections of the Skybox" [ANN 2017] | Refraction distorts the paint under it on high quality, and is absent on mobile [DOC]. "Non-opaque objects are currently not visible through glass" [ANN 2017], still by design in 2025 [COMM]. Unknown how a SurfaceAppearance interacts with the Glass material [TEST M2] | Experiment only |
| E. MaterialVariant | A custom material on the body | World-tiled detail such as flakes needs no UVs | The docs call it "for customizing the appearance of reusable tileable material" and SurfaceAppearance "for a specific mesh with UV mapping" [DOC]. How it tiles on a MeshPart is undocumented [TEST] | Not for the body; maybe for carbon (section 3.1) |

What the big engines do, for reference only:
- Unreal's Clear Coat model "was specifically designed to model smooth colored films over a
  non-colored metal" and has an optional second normal map under the coat [REF Unreal].
- Filament adds "a second specular lobe" and scales the base by the coat's Fresnel loss [REF].
- Roblox has neither, so options C and D are approximations of that second lobe.

### 1.4 How the Lighting settings change paint

| Setting | What the docs say | Effect on paint | Bench start |
|---|---|---|---|
| `LightingStyle` | Realistic gives "the most advanced and realistic lighting and shadows"; Soft is "a flat, retro‑Roblox look" [DOC] | Realistic is needed for per-pixel local lights with "precise shadows, illumination, and specular highlights" [DOC tutorial]. Mapping: Future → Realistic + Enabled; ShadowMap → Soft + Enabled; Voxel → Soft + Disabled [ANN 2025] | **Realistic** |
| `PrioritizeLightingQuality` | true "prioritizes features such as advanced shadows and high‑quality shaders at closer distances" as quality drops [DOC] | Keeps the car's shading on weaker devices; view distance drops first | **true** |
| `Technology` | Deprecated, superseded by the two above [DOC] | — | — |
| Scriptability | The Unified Lighting post says "Neither of these properties are scriptable" [ANN 2025-01-21]; the current API source lists no security tag on `LightingStyle` [DOC]. They conflict | Set them at edit time; do not plan runtime switches | [TEST] if it matters |
| `EnvironmentSpecularScale` | "make smooth objects reflect the environment … especially important to make metal look more realistic", default 0 [DOC API] | **0 kills reflections**, and metals look flat | **1** |
| `EnvironmentDiffuseScale` | Ambient light "derived from the environment … can change according to the sky and time of day", default 0 [DOC] | Sky-coloured fill on the paint's diffuse; at 1 the blue-hour sky tints the car blue | **1** (sweep 0.5) |
| `Brightness` | The sun or moon's effect on the scene [DOC] | Scales the key light, so the sun highlight on the paint | 2 (exterior), sweep 1.5–3 |
| `ExposureCompensation` | "a bias to the exposure level … prior to the tonemap step", −5 to 5 [DOC] | Overall paint value without changing the materials; the tool for the tunnel-exit exposure change | 0; per preset ±1 |
| `Ambient` / `OutdoorAmbient` | Ambient defaults to black and colours sky-occluded areas; OutdoorAmbient defaults to (127, 127, 127) [DOC] | Flat fill that washes reflections out. A tutorial uses (156, 136, 176) for a mood, which is not realism [DOC tutorial] | Ambient (0, 0, 0); OutdoorAmbient low and cool (about 70, 80, 105) [INF] |
| `ColorShift_Top` / `_Bottom` | A hue on surfaces facing toward or away from the sun [DOC] | A cheap warm/cold split on the paint | 0; touch only if the presets need it |
| `ShadowSoftness` | Default 0.2; valid only with Realistic [DOC] | Contact shadow under the car | 0.1–0.2 |
| Sky | "A skybox's lower hemisphere should be darker than the upper hemisphere" [DOC tutorial]. Skybox properties are scriptable [DOC Sky] | The paint's mirror image outside. Bright clouds near the horizon give the pink highlights seen in the reference exterior frame | One per exterior preset |
| Atmosphere | Haze is visible "far into the distance"; high haze affects "objects that have a particularly powerful fresnel effect" [DOC] | Washes the grazing reflections on the side panels | Haze 1–2; check the side panels |
| Bloom | "brighter colors … glow"; Threshold 1 means only pure white blooms [DOC] | Lamps and the sun glint bloom; the paint should not | Threshold 0.9–1.0, Intensity 0.5–1, Size about 24 [INF] |
| ColorGrading | `TonemapperPreset` Default = "vivid colors and high contrasts" [DOC] | The reference is heavily graded (crushed blacks, high contrast) | Tune materials with Default, **then** grade (Codex owns post-processing) |

**Strongest believable reflections** come from three settings together: `EnvironmentSpecularScale
= 1`, a sky with real contrast (bright horizon clouds, dark ground), and roughness 0.08–0.15
[INF]. Raising Brightness only makes highlights hotter; it does not make reflections sharper.

**Why the reference paint takes the tunnel's colour.** Looking at the frames:
- In the tunnel, warm overhead light dominates the diffuse paint, so pink turns copper. The
  louvres catch hard highlights, and the engine cover mirrors the bright chequered ceiling.
- Outside, the paint is dark plum. It reflects the sky and pink clouds, and droplets are visible
  on the engine cover.
- In Roblox, the diffuse part (warm `SurfaceLight` rows) and the highlights (Realistic per-pixel
  specular) are reliable.
- The mirrored ceiling depends on whether the indoor environment map captures the lit tunnel
  [TEST M3]. Emissive ceiling panels raise the chance either way [INF].

---

## 2. Reflections

### 2.1 What Roblox actually reflects (October 2026)

| Source | What appears in the paint | Evidence |
|---|---|---|
| **Sky cubemap** (outdoors) | The skybox, tinted by the surface; scaled by `EnvironmentSpecularScale` | [DOC] Reflectance "how much a part reflects the sky"; [COMM 2020–2026] "everything still reflects the same skybox regardless of where the object is" (2026-04-18) |
| **Local "indoor" environment map** (sky-occluded areas, Future/Realistic) | Something local; the docs promise reflections "that update periodically as the environment dynamically changes" [DOC indoor tutorial] | Placement rule from release notes 603, quoted in a bug thread: "A probe and a focus point-e.g. the camera- should now have a straight line unblocked through them" [COMM quoting release notes]. Staff 2023-12-11: a change "triggers envmap updates more aggressively than before" [STAFF]. A community claim: it updates "about every 10 seconds" (2024-06-24) [COMM, unverified]. **Whether it holds visible geometry, and its refresh rate: [TEST M3, M4]** |
| Direct specular highlights | Sun and local lights (Spot, Point, Surface) | Future Phase 3 added "proper specular highlights for local lights" (2020-11-19) [ANN]; the number of per-pixel and shadowed lights per frame is capped [ANN] |
| Screen-space reflections | **Terrain water only** | [COMM 2020] "Terrain water supports screen space reflections"; the docs say opaque surfaces "work better with … water reflection" [DOC] |
| Nearby parts, other cars, characters | **Not in the sky reflection.** In the indoor map: unknown, and certainly not moving objects in real time | [COMM 2020] "does not reflect you character"; [COMM 2023-11-11] "so we can't make real time reflection" |
| Baked / custom probes | None you can place | Feature requests 2019–2026 without a staff answer [COMM] |

### 2.2 Rendering changes in 2025–2026 that matter for the car

| Date | Change | Status | Relevance |
|---|---|---|---|
| 2025-01-21 → 2025-07-23 | Unified Lighting: `LightingStyle` + `PrioritizeLightingQuality` replace `Technology` | Live [ANN] | Realistic + true is the Future equivalent |
| 2025-07-22 (API build 683) | `Decal` gains `NormalMapContent`, `RoughnessMapContent`, `MetalnessMapContent`, `UVScale`, `UVOffset`; `ColorMapContent` 2025-09-09 (690); `Rotation` 2026-02-24 (710) | In the API [DOC; API history site]. **No release announcement found** [BETA?] | PBR droplet decals (section 4) |
| 2025-10-30 → 2026-02-12 | Emissive masks on SurfaceAppearance, MaterialVariant and TerrainDetail | Live in published experiences [ANN] | Lamps, screens, brake glow |
| 2025-12-12 → 2026-03-23 | Texture streaming (MeshPart, SurfaceAppearance, Texture, Decal, MaterialVariant, Beam, ParticleEmitter; **not** EditableImage, Sky) | Live [ANN] | Memory; textures are sized by screen footprint |
| 2026-01-30 | 4K textures, through streaming | Live; off on Android under 3.5 GB [ANN] | Body and interior maps above 1024 become possible |
| Nov 2025 → 2026-03-18 | `WrapTextureTransfer` + `ComposeDecalAsync` (avatar makeup) | Studio beta [ANN, SNIP] | A future UV-space decal layer; not for now |
| 2026-09-10/12 (RDC) | Terrain technology, "projected decals for realistic textures like tire tracks", and "Roblox Reality" (an AI video layer for weather and lighting) | Announced; no dates [secondary press, 2026-09-11] | No reflection, SSR or probe feature announced |

**No 2025–2026 announcement of better reflections, reflection probes or SSR was found.** The
April 2026 replies in the probe request still describe sky-only reflections [COMM]. This comes
from a search pass that ran out of budget, so it is the absence of a finding, not proof of
absence.

### 2.3 Tricks used by creators, and their cost

| Trick | How | Moving car? | Cost | Use for us |
|---|---|---|---|---|
| Custom sky per scene | Swap `Sky` faces or the Sky object when entering a zone (scriptable [DOC]) | Yes | One cubemap; streaming does not cover Sky [ANN] | Exterior presets; a "tunnel sky" only if M3 shows the indoor map uses the sky [TEST] |
| Bright emissive set pieces | Emissive ceiling panels, light strips | Yes | Cheap; emissives show at all quality levels [ANN] | Tunnel ceiling |
| Flipped-clone floor | A mirrored copy of the scene under a transparent floor | Static only | "the most costly" [COMM 2023] | No |
| Terrain water | A thin water layer for real SSR | Reflects the car | Waves, clipping; affects the road, not the paint | Note for Codex's wet road (opaque parts reflect best [DOC]) |
| ViewportFrame mirror | A camera behind the mirror, clones of nearby objects in a ViewportFrame on a SurfaceGui | Yes, scripted | "No shadows or post-processing effects are rendered"; "Neon and Glass materials render at the lowest quality"; environment scales act as 0 unless a Sky child is present [DOC]. A cloned car in a mirror "will cost a lot of performance" [COMM]. A horizontal flip "screws up meshes" [X post, SNIP] | Cockpit rear-view mirror only: low resolution, a Sky child, at most 4–5 low-poly proxy cars, updated at 30 Hz, off in chase view [INF] |
| Client shaders (ReShade and similar) | Outside the game | — | Not available to players | No |

---

## 3. Other materials

### 3.1 Carbon fibre

- **No anisotropy in Roblox** [DOC: no such property]. Real 2×2 twill flips light and dark
  between tows because each tow's fibres point another way.
- **The fake** [INF]: bake the weave into the part's UVs. Tows alternate:
  - in the colour map: albedo about sRGB 35–60, alternating by tow;
  - in the roughness map: alternating values in the band given below;
  - in a **weak** normal map: each tow tilted along its fibre direction.
  Under a moving highlight, alternating tows brighten in turn. That is most of the carbon read.
- **The coat problem.** Real gloss carbon has a flat clear coat over the weave. A strong weave
  normal in one layer bends the coat's reflection, which looks wrong. Unreal solves it with a
  second normal under the coat [REF]. We cannot, so keep the normal strength low (about 0.3)
  and carry the weave in albedo and roughness.
- **Values:**
  - gloss carbon: metalness 0, roughness 0.12–0.2 overall, ±0.05 between tows;
  - matte or forged carbon: roughness 0.35–0.5.
- **The model already ships** `common_carbon05_black_diff.png` + `_norm.png` (a CSR2 tiling
  carbon). Check its UV scale. Roblox has one UV set (`09`), so a tiled weave works only if the
  carbon parts' UVs already tile it.
  - Whether UVs outside 0–1 repeat in Roblox: [TEST].
  - Fallback: a carbon MaterialVariant at about 0.35 studs per tile (8×8 tows), if a MeshPart
    takes it cleanly [TEST, like the paint variant in 1.3 E].
- Weave scale [INF]: a 3 mm tow gives a 12 mm twill repeat, about 0.043 studs at 0.28 m per
  stud. That is too fine for 1024 px over a big part, so bake at 2048 for the wing and engine
  cover, and judge in a side-by-side capture.

### 3.2 Glass

- **Glass material** [ANN 2017-12-06, still by design per a 2025 thread]:
  - refraction "On high graphics quality levels" (not on mobile [DOC]);
  - "Reflectance determines how much light comes from reflections of the Skybox";
  - Transparency 0 to 0.5 fades the diffuse; 0.5 to 1 fades the whole effect.
  - **"Non-opaque objects are currently not visible through glass"**: transparent parts, decals
    on transparent parts, particles and world-space GUIs.
- **What that means for the car** [INF]:
  - The cabin is opaque, so it stays visible through any glass.
  - From the cockpit, a Glass windscreen **hides the rain particles, the spray, and other cars'
    windows**.
  - From the chase camera, the rear glass would hide the windscreen behind it, which is a minor
    effect.
- **Plan:**
  - chase view: `Material = Glass`;
  - cockpit view: `SmoothPlastic` plus a SurfaceAppearance;
  - switch the windscreen locally by camera mode (`Material` is a normal BasePart property) [TEST
    M10].
- **SurfaceAppearance glass** [DOC]:
  - `AlphaMode = Transparency` with `MeshPart.Transparency ≥ 0.02` for soft alpha;
  - tint and the black frit band go in the ColorMap alpha;
  - roughness 0.02–0.05, metalness 0.
  - Expect weaker reflections than the Glass material, because blending scales them by opacity
    [INF; TEST M2].
- **Tint:** about 15–30 % opacity on the windscreen and 40–60 % on the side and rear glass, the
  colour a cool dark grey (20, 24, 28) [INF; the SVJ's real tint is not sourced].
- **Sorting is per part** [DOC: "render order may act unpredictably"]:
  - one MeshPart per pane;
  - delete the inner duplicate shell that game rips carry, and use `DoubleSided` (`09` 5.3).

### 3.3 Chrome, aluminium, titanium

- Values are from the CC0 physicallybased.info database, linear values converted to 8-bit sRGB
  [REF]:

| Metal | Colour (sRGB) | Roughness |
|---|---|---|
| Chromium | (211, 216, 218) | 0.02–0.06 (chrome trim, exhaust tip rims) |
| Aluminium | (245, 246, 246) | polished 0.05–0.15; forged or satin wheels 0.25–0.45 |
| Titanium | (177, 170, 162) | about 0.3 (exhaust tips, with heat tint in the colour map) |
| Stainless | (214, 209, 203) | per part |

- Metalness 1.
- Metals show only what they reflect: in a dark tunnel chrome goes dark except for its
  highlights. That is correct, not a bug [INF].
- Brushed metal has no anisotropy, so fake it with fine directional lines in the normal and
  roughness maps [INF].

### 3.4 Tyre rubber

- Tyre albedo **0.023 linear, about sRGB (42, 42, 42)**; roughness 0.7 in the database [REF].
- In game: sidewall 0.8–0.9, tread 0.7. The sidewall lettering is already removed (`00_PLAN`
  debadge).
- The normal map carries the sidewall moulding and the tread; metalness 0.
- Wet: albedo ×0.8 and roughness 0.4–0.5 (section 4.1).

### 3.5 Lights, dashboard, emissive

- **The emissive formula** [ANN 2025-10-30]: "Final Color = (EmissiveMask × EmissiveStrength ×
  EmissiveTint + Combined light) × Color Map".
  - So the LED strips' ColorMap must be bright (white or amber) under the mask.
  - Strength slider 0–40 in Studio, higher allowed; the value "clamps to the maximum dynamic
    range".
  - Emissives "appear at all quality levels" and "won't fade out in far distances" [ANN].
  - `EmissiveStrength` and `EmissiveTint` are scriptable [DOC; ANN].
- **Taillight and DRL states** [INF; tune against bloom]:

| State | EmissiveStrength |
|---|---|
| Off | 0 |
| Position | 3–6 |
| Brake | 15–25 |
| Indicator | pulses 0 ↔ 20 |

- **Light that falls on the road** needs real lights, which have their own limits:
  - `SpotLight` ("ideal for … headlights" [DOC]);
  - range 60 studs by default, 120 with `Lighting.ExtendLightRangeTo120`, which is not
    scriptable [DOC];
  - shadowed lights "cost much more" [ANN 2020].
- **Dashboard and screens:**
  - static dial art in the emissive mask;
  - live content on a `SurfaceGui` with `LightInfluence 0` and `Brightness` up to 1000 (default
    1) [DOC].
  - Does a SurfaceGui above 1 trigger Bloom? [TEST M11].
- **The outer lens:** clear, transparent (as glass); the inner reflector is chrome (metalness 1,
  roughness 0.1).
- **Bloom:** "Threshold determines how bright a color can be before it blooms" [DOC]. Keep the
  threshold near 1, so only the lamps and the sun glint bloom and the paint does not.

### 3.6 Brake-disc glow

- **Possible with what exists** [INF from ANN]:
  - a ring-shaped emissive mask on the disc's SurfaceAppearance;
  - `EmissiveTint` ramping from dull red (about 120, 20, 5) to orange (255, 110, 20);
  - `EmissiveStrength` driven by a brake-temperature value from the vehicle model's telemetry.
- Real steel glows visibly from about 525 °C (the Draper point) [general physics; not
  car-sourced].
- Carbon-ceramic discs like the SVJ's can run hotter in track use. Treat the onset temperature as
  a tuning value.
- The disc's grey ColorMap multiplies the glow (formula above). Compensate with strength (a 0.3
  grey needs about 3× the strength); the hue stays the tint's.
- Optional: a small orange `PointLight` on the caliper (Range 2–3 studs, no shadows) when hot.
  It costs one per-pixel light [ANN 2020].

### 3.7 Interior

- **Leather** [INF]:
  - black leather albedo sRGB 30–45; roughness 0.45–0.6;
  - fine grain baked into a normal map at 1024 for the seats and dash top (`09` 5.5).
- **Alcantara** [INF]:
  - albedo sRGB 45–60; roughness 0.9–1.0; a very weak fibre normal.
  - Roblox has no sheen lobe, and Fresnel still lifts grazing angles [DOC]. Accept a slightly
    plastic edge.
- **Plastics** [INF]:
  - textured black PP: albedo sRGB 35–50, roughness 0.65–0.8;
  - satin trim: roughness 0.4–0.5.
- **Screens (off):** near-black (10, 10, 12), roughness 0.05–0.1, so they reflect like glass.
- **Interior baked AO stays** in the colour maps (contact shadows).

---

## 4. The wet state

### 4.1 What "wet" looks like, and what the big games do (concepts only)

- **Lagarde, "Water drop 3b – Physically based wet surfaces", 2013-04-14** [REF]:
  - Darkening depends on porosity: `factor = lerp(1, 0.2, Porosity)`, applied to the diffuse by
    the wet level.
  - Gloss rises toward water (water is smooth).
  - F0 barely changes (water about 0.02 against about 0.04), "not visible enough in game".
  - **For metals and smooth surfaces, ignore the darkening.**
  - Puddles are flat water.
  - Drying is a sigmoid, which games simplify to a lerp over about a minute.
  - A commenter notes the gloss formula does not return to the dry value at zero wetness; take
    the shape, not the exact code.
- **So, per material on the car** [INF from REF]:

| Material | When wet |
|---|---|
| Paint | Does not darken. It gains **beads** (wax) or a **water sheet**, and its reflections change because the world got darker and wetter |
| Glass | Droplets and streaks |
| Tyres, matte plastics, matte carbon, the textured underside | Darken 15–30 % and turn glossy |
| Chrome | Droplets only |

- **DRIVECLUB (2014 coverage)** [SNIP]:
  - drops act independently "according to the wind and way that the car is moving";
  - they slide back on the windscreen at speed and fall when the car slows;
  - the screen dries in proportion to wiper strokes;
  - the art director cites "dampening surfaces, moisture absorption, changing material
    appearances".
- **Forza Motorsport press still** (`07` R14): the clear-coat reflection takes the neon colour
  on a wet floor. The floor's stretched reflection does more for "wet" than the car does.
- **Polycount discussion of game windscreen rain** [SNIP]:
  - front glass: a 2D particle simulation with wind and wiper deflectors;
  - side glass: "looping normal maps/height maps (water streaks repeat)".
- **The reference video**, exterior frames [MEAS by eye]:
  - small droplet specks on the engine cover;
  - dark streaks and spray behind the rear tyres;
  - lens droplets (`05`).
  - Most of the wet read comes from the road mirroring the sky.

### 4.2 Options compared

Each option is judged on quality, fade, cost and risk. Costs are relative estimates [INF] until
M9 measures them.

| # | Technique | What it shows | Smooth fade? | Extra draws / overdraw | Memory | Phone | Risks | Verdict |
|---|---|---|---|---|---|---|---|---|
| 1 | **Pre-built SurfaceAppearance variants, swapped in steps** (dry → wet in N steps) | Darkening and gloss on textured parts (tyres, trim, carbon) | Stepped. Kalebosarus uses 12 steps of pre-generated roughness maps, swapped at runtime [COMM 2026-08-19]. With 4–6 steps over about 20 s the steps should not read as pops [INF; TEST] | None (same part, same draw) | One pack per variant [DOC pack; INF]; small if only roughness differs | OK | A first-swap hitch until the textures load, so preload them [TEST M12] | **Yes**, for porous parts |
| 2 | **Paint roughness through EditableImage**: `CreateSurfaceAppearanceAsync({RoughnessMap = ei, MetalnessMap = ei})` with tiny images, written by `WritePixelsBuffer` | A continuous gloss value on the untextured paint | Continuous | None | Tiny (4×4) | Budgets are "strict" on clients [DOC] | Needs "Enable Mesh / Image APIs" in the published game [DOC]. Only one EditableImage updates per frame on display [DOC]. Every map of that SurfaceAppearance must come from an EditableImage [DOC; COMM]. Unknown whether one image can feed several SurfaceAppearances, and whether `MeshPart.Color` shows when no ColorMap is set [TEST M5, M6] | Optional. Paint gloss barely changes when wet (4.1), so option 1 with 4 steps may be enough |
| 3 | **Droplet shell** (duplicate top-panel meshes, offset 3–5 mm; SurfaceAppearance `Transparency` mode; ColorMap alpha = drop coverage; droplet normal map; roughness about 0.03) | Beads that catch highlights and the sky, UV-mapped on curved panels | **Yes**: `MeshPart.Transparency` 1 → about 0.05 (≥ 0.02 for soft blending [DOC]) | +4–8 MeshParts; one blended pass over the covered pixels | 1 droplet set at 1024–2048 | Gate off on low-end [TEST] | Z-fighting if the offset is too small [TEST M7]; sorting against the glass (keep the shell off the glass); `CastShadow = false` | **Yes**: the main visible wet cue on the paint |
| 4 | **Top-face PBR Decal** on the top panels (`Face = Top`; droplet colour/normal/roughness maps set at edit time; `Transparency` scripted) | The same beads, projected straight down, which suits rain on horizontal panels | **Yes**: `Decal.Transparency` | +1 draw per decal (decals "don't batch well" [DOC]); re-renders the whole part surface it sits on [STAFF reply 2026-09-01] | 1 set | As 3 | Projection on a curved MeshPart is undocumented (stretching on slopes, wrong faces?) [TEST M8]; PBR decal release status unconfirmed [BETA?] | **Prototype against 3**; keep the better one |
| 5 | **Scrolling `Texture`** (OffsetStudsV tween, a streak image) | Running streaks on the side glass and doors at speed | n/a (Transparency fades it) | +1 draw per texture, as decals | Small | OK if few | Repeating pattern; the cost multiplies with UV animation if many [STAFF] | **Yes**, side glass only (Codex owns glass droplets) |
| 6 | `MeshPart.Reflectance` tween | Extra sky reflection | Yes | None | None | OK | "may or may not be ignored depending on the Material" [DOC]; with a SurfaceAppearance present: **unknown** [TEST M1] | Only if M1 shows it works |
| 7 | `Material` switch (SmoothPlastic → Glass) on the shell | Refracting "lens" drops | Pop | Refraction pass, high quality only | — | No refraction on mobile [DOC] | Hides transparent objects behind it | No (maybe as an experiment) |
| 8 | MaterialVariant swap (`BasePart.MaterialVariant`, a "rain" variant) | World-tiled wet look | Pop | None | Small | OK | The wet-world precedent [COMM 2023]; not for a UV-mapped car body | No for the body |
| 9 | ParticleEmitters (drops hitting the bonnet, run-off off the rear) | Motion | — | Particles | — | Particle limits scale with quality [DOC] | Billboards do not follow curved panels | **Yes, Codex's side** |
| 10 | EditableImage droplet normal map, animated | True animated drops | Yes | None | 4 MB per 1024² image, not streamed, max 1024 [DOC] | Budget risk | One image update per frame on display; the creator in 2026 hit the memory budget [COMM] | Not now |

### 4.3 Recommended wet pipeline

- **One value per car:** `Wetness` from 0 to 1, computed on each client.
  - It rises with rain intensity while exposed (about 20–30 s to full).
  - At speed, airflow halves the bead layer on the bonnet and engine cover [INF; tune against
    DRIVECLUB R11].
  - It dries with a lerp over 60–120 s once the rain stops (Lagarde's simplification).
- **Bands drive the layers:**
  1. `Wetness > 0.05`: the droplet shell (or decal) fades in by Transparency, proportional.
  2. Porous parts step through 4 SurfaceAppearance variants at 0.25, 0.5, 0.75 and 1.0.
  3. Paint roughness steps 0.12 → 0.08 (or stays fixed if M6 is not worth it).
  4. Side-glass streak Textures scroll with speed.
  5. Codex's VFX read the same `Wetness` and rain intensity.
- **Boundary with Codex** (`00_PLAN`: one producer per state):
  - The car's material module (Claude) produces `Wetness` and owns the car's own surface states:
    variants, shell, decals.
  - Codex owns the rain, spray, splashes, run-off, glass droplets, wipers and lens rain, and
    reads `Wetness` from the telemetry.
  - This split is a proposal for the owner to confirm.
- **In the cockpit:**
  - the windscreen's wet look is a variant of the windscreen's own SurfaceAppearance, not an
    extra layer;
  - Codex's droplet and wiper effect sits on it.
  - That gives at most **one** transparent screen-filling layer, plus Codex's droplets [INF].

### 4.4 Roblox precedents found

- **"Simulating 'Wetness' using EditableImages"**, Kalebosarus, 2026-08-19 [COMM]:
  - runtime EditableImage edits of the roughness maps "quickly exhausted the memory budget";
  - Roblox appeared to require loading every map (colour, normal, metalness) to modify one;
  - the final design pre-generates 12 roughness steps per object with a plugin
    (`CreateAssetAsync`) and swaps them at runtime, at 256–512 px;
  - a reply describes updating an ocean's normal map live through an EditableImage, so live
    updates do work in some form.
- **"Rain Material Swapper v1.0.0"**, 2023-12-29 [COMM]:
  - swaps world parts to wet or shiny variants a few parts per frame, from a LocalScript;
  - no lag spikes at 24,000 parts, by the author's report;
  - world surfaces, not cars.
- **"How to make surfaces appear wet"**, 2023-07-19 [COMM]:
  - a MaterialVariant with low roughness and a modest normal map;
  - "less roughness works best"; metals less effective;
  - the author marks it "slightly outdated" (2024-12).
- **"Screen Distortion Rain"**, boatbomber, 2019-02-11 [COMM]:
  - Glass-material droplet balls in front of the camera, stretched to run;
  - turned off below graphics level 8 because Glass "doesn't render properly on low graphics";
  - inherits Glass's hiding of transparent objects.
- **Formula Roblox, update 1.20.0** [SNIP]: a wet track with grip tied to rain intensity and
  wetness percentages. That is physics, not visuals.
- **1ForeverHD/Rain** (Apache-2.0, a fork of buildthomas/Rain): rain particles with occlusion
  by casts, a splash texture and sounds; no wet surfaces [GitHub].

---

## 5. Performance

### 5.1 What the docs say

- **Transparency** forces "the engine to render the overlapping pixels multiple times";
  "partially transparent objects have some significant rendering costs"; sorting is per part
  [DOC].
- **Draw calls** "have significant overhead".
  - Identical meshes batch when "SurfaceAppearances are identical if present, otherwise when
    TextureContents are identical".
  - "decals, textures, and particles don't batch well and introduce additional draw calls"
    [DOC].
- **Decals with UV animation** (staff reply, 2026-09-01, to a 2026-08-11 report) [COMM report;
  reply "expected unfortunately"]:
  - 40 decals using `UVOffset`/`UVScale` on one part dropped a GTX 1050 Ti to about 20 FPS, while
    1,000 decals on 1,000 small parts held 60;
  - with UV animation the part's surface renders again for each decal, "computing each pixel 40
    times".
  - **Lesson:** a decal's cost is the area of its parent part, not of its image.
- **Shadows:** "disable shadow casting on small parts"; "Disable shadows on moving objects when
  possible" [DOC]. Give every overlay layer `CastShadow = false`.
- **Lights:** "Use fewer light instances", and "Limit the range and angle" [DOC]. The per-frame
  caps on per-pixel and shadowed lights apply [ANN 2020].
- **Texture memory** [DOC; ANN]:
  - 1024² costs four times 512²;
  - streaming picks mips by screen footprint within a per-frame budget;
  - 4K is off on Android under 3.5 GB;
  - **EditableImage is not streamed** and is capped at 1024.

### 5.2 Estimated cost of each layer (to measure in M9)

| Layer | Chase view (car about 25–35 % of frame width, roughly 8–12 % of the screen) | Cockpit view | Phone |
|---|---|---|---|
| Opaque car, about 45–60 MeshParts | Base cost (`09`) | Base | Base |
| Window glass (one layer) | Small area | **The windscreen covers 50–70 % of the screen**, so one full-screen blended layer; with the Glass material add a refraction pass on high quality | Keep |
| Droplet shell or decals on the top panels | About 40 % of the car's pixels get one more blended pass, so about 4 % of the screen | Bonnet visible: modest | Gate (off or reduced) |
| Clear-coat shell (if ever) | The whole body twice | — | Off |
| Side-glass streak Textures | Small | Side windows: modest | Off |
| Porous-part variants | No extra draw | — | Keep; preload |
| ViewportFrame mirror | — | One small extra scene render | Off |

### 5.3 Quality levels: what degrades

- **Officially:** as `QualityLevel` rises, Roblox raises "the rendering distance, shading quality,
  apparent geometry and texture resolution, limits on particles …, fidelity of trail effects,
  post-effect quality"; at low levels "some post effects may be completely disabled". And:
  "The specific effects of quality level … are platform- and device- specific and can not be
  relied upon" [DOC].
- Known pieces:

| Feature | At lower quality or on weak devices |
|---|---|
| SurfaceAppearance | Seen from graphics level 3 up, by 2020 user reports [COMM]; the docs say only "depends on the user's device and graphics quality level" [DOC] |
| Glass refraction | High quality only; not on mobile [ANN; DOC] |
| Per-pixel local lighting | Its distance depends on quality; `PrioritizeLightingQuality = true` sacrifices view distance first [ANN; DOC] |
| Emissives | At every quality level, no distance fade [ANN] |
| Textures | Lower mips under memory pressure; no 4K on Android under 3.5 GB [ANN] |

- **Gating our layers.** A LocalScript can read the player's saved quality level through
  `UserGameSettings` [INF from common practice; TEST M13]. Gate the droplet shell, streak
  Textures and mirror on it. Check on the owner's phone what actually disappears at levels
  1–10.

---

## 6. The material spec, and how to measure it

### 6.1 Per material class

Colours are 8-bit sRGB as stored in the PNG maps. "Rough." is the roughness map value (0 to 1).
All values are starting points [INF] except where marked [REF].

| Class | Maps (from the CSR2 sets, `09` 5.1) | Colour | Rough. | Metal. | Alpha / material | Wet state | Notes |
|---|---|---|---|---|---|---|---|
| **Paint** | 4×4 white ColorMap, 4×4 roughness, 4×4 metalness; no normal | (150, 70, 140) through `SurfaceAppearance.Color` | 0.12 | 0 | TintMask | Droplet shell or decal fades in; roughness 0.12 → 0.08 (optional, M6) | No broad AO; faint cavity AO only |
| **Gloss carbon** (wing, splitter, skirts, diffuser, engine cover) | Baked twill: colour, roughness, weak normal (2048 on large parts) | Tows alternating sRGB 35–60 | 0.12–0.2, ±0.05 | 0 | Opaque (Overlay, no alpha) | Droplet layer where it faces up | Normal strength about 0.3 |
| **Matte / forged carbon** | Same | sRGB 30–50 | 0.35–0.5 | 0 | Opaque | 4 variants: colour ×0.85, roughness → 0.2 | |
| **Windscreen** | ColorMap with tint and frit in alpha | (20, 24, 28), alpha about 0.2; frit opaque black | 0.03 | 0 | Chase: Glass material. Cockpit: SmoothPlastic + `Transparency` mode, Transparency ≥ 0.02 | Wet variant of the pane's own SurfaceAppearance (droplets in alpha and normal); Codex's droplets and wipers on top | M10 |
| **Side and rear glass** | As above | Alpha 0.4–0.6 | 0.03 | 0 | As above | Streak Texture scrolling with speed | One part per pane; delete the inner shell |
| **Chrome** | Colour + roughness | (211, 216, 218) [REF] | 0.02–0.06 | 1 | Opaque | Droplets only (shell, if it covers them) | Needs `EnvironmentSpecularScale` > 0 |
| **Wheel aluminium** | Colour, roughness, normal (one wheel, cloned, `09`) | (245, 246, 246) [REF], or the rim finish | 0.25–0.45 | 1 | Opaque | none | |
| **Exhaust titanium** | Colour with heat tint | (177, 170, 162) [REF] | 0.3 | 1 | Opaque | none | Emissive glow ring for the orange idle glow seen in `05` |
| **Tyre** | Colour, normal (tread and sidewall), roughness | (42, 42, 42) [REF] | Sidewall 0.85, tread 0.7 | 0 | Opaque | 4 variants: colour ×0.8, roughness → 0.45 | Lettering removed |
| **Brake disc** | Colour, roughness, normal, ring emissive mask | Grey (90, 90, 92) | 0.4 | 0.6 (cast iron), or 0 for carbon-ceramic grey | Opaque | none (wet discs are not visible) | Strength and tint from brake temperature |
| **Caliper** | CSR2 caliper set, debadged | Per spec | 0.3 | 0 | Opaque | none | |
| **Plastic trim** (textured) | CSR2 sets | (35–50) | 0.65–0.8 | 0 | Opaque | 4 variants: ×0.8, roughness → 0.35 | |
| **Lamps** (inner LED strips) | Colour (bright under the mask), emissive mask | White (DRL), amber (taillight edges, `05`) | 0.2 | 0 | Opaque | none | Strength 0 / 3–6 / 15–25 |
| **Lamp lenses** | Clear | (230, 230, 235), alpha 0.1–0.2 | 0.02 | 0 | Transparency mode | Droplets optional | |
| **Leather** | `InteriorA` set + grain baked at 1024 | Black sRGB 30–45 | 0.45–0.6 | 0 | Opaque | none | Keep the baked AO |
| **Alcantara** | Fibre normal (weak) | sRGB 45–60 | 0.9–1.0 | 0 | Opaque | none | No sheen available |
| **Screens** | Emissive mask (dials) + SurfaceGui | Off: (10, 10, 12) | 0.05–0.1 | 0 | Opaque | none | SurfaceGui `LightInfluence 0`, `Brightness` > 1 (M11) |

### 6.2 Bench lighting presets (starting values; tune by measurement)

These are **test fixtures for materials**. Codex owns the final presentation and post-processing.

| Preset | Sky / sun | Lighting | Local lights | Post |
|---|---|---|---|---|
| **T, tunnel** | Covered by a 60-stud tunnel shell | Realistic, PrioritizeLightingQuality true, env scales 1, Ambient (0, 0, 0), ExposureCompensation 0 to +0.7 | Ceiling rows of `SurfaceLight` (255, 175, 110), Brightness 2–4, Range 16–20, shadows on 2–3 only; emissive ceiling panels | Bloom threshold 0.95 |
| **E, exterior, blue hour after rain** | Dusk skybox with bright horizon clouds and a dark ground; ClockTime about 17.5–18.5 | Brightness 1.5–2.5; OutdoorAmbient about (70, 80, 105); env scales 1; Atmosphere Density about 0.3, Haze 1–2, cool colour | none | Bloom 0.95; ColorCorrection only after the material pass |
| **X, exit** | T then E along one drive | ExposureCompensation change (Codex) | — | — |

### 6.3 Measurement plan against the reference frames

1. **Scene.**
   - The neutral bench (`00_PLAN`), plus a tunnel section and an open stretch.
   - Next to the car: a **chrome ball** (metalness 1, roughness 0), a **grey ball** (50 % grey,
     roughness 0.5) and a small grid of colour patches. This standard look-development set
     separates exposure errors from material errors [INF].
2. **Cameras.**
   - C1: the chase camera matched to `LOOK_TARGET.jpg` and frames `00_23`, `01_33` and `01_44`
     (lens about at roof height, slightly above; the car 25–35 % of the frame width, in the lower
     middle third (`05`); FOV about 70–80 to match the stretch).
   - C2: a fixed rear three-quarter view.
   - C3: the cockpit.
3. **Capture.**
   - 1920×1080 where the tool allows, with `robloxstudio-mcp capture_screenshot`.
   - Studio Editor Quality at maximum, then a mid level, then the device simulator for framing
     only (it does not simulate the GPU, `04` §8). The owner's phone gives the real low end.
4. **Score.** A Python + PIL script, run with `python -I`:
   - median HSV on paint patches at the same screen places as the reference patches below;
   - the highlight fraction on the paint (V > 0.9);
   - the contrast between the lit engine cover and the shadowed rear bumper.
   - **Reference values measured today** (median of a crop) [MEAS]:

| Frame | Patch (x0, y0, x1, y1) | Median sRGB | Hue | Sat | Val |
|---|---|---|---|---|---|
| `00_23` tunnel | rear bumper left (585, 800, 680, 870) | (139, 62, 62) | 0° | 0.55 | 0.55 |
| `00_23` tunnel | rear bumper right (1150, 800, 1240, 870) | (181, 104, 83) | 13° | 0.54 | 0.71 |
| `00_23` tunnel | engine cover side (660, 640, 760, 700) | (139, 78, 67) | 9° | 0.52 | 0.55 |
| `01_33` exterior | engine cover centre (860, 640, 1060, 690) | (68, 68, 104) | 240° | 0.35 | 0.41 |
| `01_33` exterior | rear deck left (700, 650, 800, 700) | (27, 26, 39) | 245° | 0.33 | 0.15 |
| `01_33` exterior | rear deck right (1080, 660, 1180, 700) | (118, 85, 120) | 297° | 0.29 | 0.47 |

   - These frames are **graded** (the Assetto Corsa video's look). Compare at two stages:
     - materials with the Default tonemapper and no grade, checked against the grey and chrome
       balls for sanity;
     - then with Codex's grade, against these numbers.
     Never tune a material to make up for the grade.
5. **Proposed pass bands** (proposals, to revise after the first capture):
   - tunnel paint hue within ±15° of 5°;
   - exterior paint hue between 230° and 310°;
   - tunnel/exterior value ratio within ±30 % of the reference's (about 1.4–2);
   - a visible highlight band on the engine-cover louvres in preset T (highlight fraction on
     that patch > 2 %).
6. **Record** every capture with its preset, quality level and material version next to the
   screenshot, so that a result can be traced back.

### 6.4 Bench tests that can fail (bench place only, never the Rob A Car place)

| # | Claim to settle | Test | Fails if |
|---|---|---|---|
| M1 | `MeshPart.Reflectance` still adds reflection with a SurfaceAppearance present | Two identical paint parts, Reflectance 0 and 0.5, under the E sky | No visible difference: drop option 6 |
| M2 | A SurfaceAppearance on a Glass-material part keeps glass behaviour; a transparent SurfaceAppearance pane's reflection is weaker than Glass | Three panes: Glass, Glass + SurfaceAppearance, SmoothPlastic + `Transparency` SurfaceAppearance; chrome ball behind | The Glass + SurfaceAppearance pane loses refraction or reflection |
| M3 | The tunnel's indoor environment map shows lit geometry | Chrome ball and paint panel inside the tunnel, with a bright red emissive panel 10 studs away | No red appears in the chrome ball: the tunnel reflections must come from local light highlights only |
| M4 | How fast that map refreshes, and whether a fast car gets a fresh one | Drive at 30 m/s from the open air into the tunnel; time-stamped captures | The reflection lags more than 1 s, or still shows the sky inside the tunnel |
| M5 | A SurfaceAppearance with no ColorMap shows `MeshPart.Color` (the alternative to TintMask) | A paint part with only roughness and metalness maps | It renders white or grey |
| M6 | An EditableImage roughness map updates the SurfaceAppearance live, and one image can feed several SurfaceAppearances | `CreateSurfaceAppearanceAsync` with a 4×4 image, write 0.1 → 0.6 over 2 s; then share it across two parts | No live change, or an error when sharing. Also check that the published game's "Enable Mesh / Image APIs" toggle is acceptable to the owner |
| M7 | A shell offset of 3–5 mm does not z-fight at chase and far distances | Shell over the bonnet, camera at 5, 20 and 60 studs | Flicker at any distance |
| M8 | A top-face PBR Decal projects cleanly on the curved bonnet | Decal `Face = Top` with a droplet normal map | Stretching on slopes, or drops on the wrong faces |
| M9 | Frame cost of each layer | MicroProfiler and render stats with the car, then + glass, + shell or decal, + streaks, + mirror; PC and the owner's phone | Over the `09` budget (≤ 1.5 ms PC, ≤ 3 ms phone for the whole car) |
| M10 | A Glass windscreen hides rain particles from the cockpit, and a local material switch fixes it | Rain emitter outside, cockpit camera, toggle `Material` | Particles stay visible through Glass (then no switch is needed) |
| M11 | `EmissiveStrength` above a value blooms; a SurfaceGui with `Brightness` > 1 blooms | Sweep 1–40 against Bloom threshold 0.95 | No bloom at any strength |
| M12 | Swapping a pre-built SurfaceAppearance has no hitch if preloaded, and the memory delta per variant | First swap without and with `ContentProvider:PreloadAsync`; Developer Console texture memory | A visible hitch after preload, or a full-pack memory cost per variant |
| M13 | What disappears at graphics levels 1–10, and that the client can read the level to gate layers | Step through the levels; log the value from a LocalScript | The level cannot be read: gate on device class instead |

---

## Sources

All read 2026-10-27 unless marked [SNIP] (seen only in a search result).

**Roblox documentation (create.roblox.com; source text from github.com/Roblox/creator-docs)**
- SurfaceAppearance class: https://create.roblox.com/docs/reference/engine/classes/SurfaceAppearance (source `content/en-us/reference/engine/classes/SurfaceAppearance.yaml`)
- PBR textures guide: https://create.roblox.com/docs/art/modeling/surface-appearance (source `art/modeling/surface-appearance.md`)
- AlphaMode enum: https://create.roblox.com/docs/reference/engine/enums/AlphaMode
- Lighting class: https://create.roblox.com/docs/reference/engine/classes/Lighting ; Lighting guide: https://create.roblox.com/docs/environment/lighting
- Enhance indoor environments: https://create.roblox.com/docs/tutorials/building/environments/enhancing-indoor-environments
- Enhance outdoor environments with Future lighting: https://create.roblox.com/docs/tutorials/3D-art/enhancing-outdoor-environments-with-future-lighting
- Skybox: https://create.roblox.com/docs/environment/skybox ; Sky class: https://create.roblox.com/docs/reference/engine/classes/Sky
- Atmosphere: https://create.roblox.com/docs/environment/atmosphere
- Post-processing effects: https://create.roblox.com/docs/environment/post-processing-effects ; BloomEffect: https://create.roblox.com/docs/reference/engine/classes/BloomEffect
- Materials: https://create.roblox.com/docs/parts/materials ; MaterialVariant: https://create.roblox.com/docs/reference/engine/classes/MaterialVariant
- BasePart: https://create.roblox.com/docs/reference/engine/classes/BasePart
- Decal: https://create.roblox.com/docs/reference/engine/classes/Decal ; Texture: https://create.roblox.com/docs/reference/engine/classes/Texture ; Textures and decals: https://create.roblox.com/docs/parts/textures-decals
- AssetService (CreateSurfaceAppearanceAsync, CreateEditableImage): https://create.roblox.com/docs/reference/engine/classes/AssetService ; EditableImage: https://create.roblox.com/docs/reference/engine/classes/EditableImage
- ViewportFrame: https://create.roblox.com/docs/reference/engine/classes/ViewportFrame ; ViewportFrames guide: https://create.roblox.com/docs/ui/viewport-frames
- QualityLevel enum: https://create.roblox.com/docs/reference/engine/enums/QualityLevel
- Improve performance: https://create.roblox.com/docs/performance-optimization/improve
- Light sources: https://create.roblox.com/docs/effects/light-sources
- SurfaceGui: https://create.roblox.com/docs/reference/engine/classes/SurfaceGui
- WrapTextureTransfer [SNIP]: https://create.roblox.com/docs/reference/engine/classes/WrapTextureTransfer
- Release notes 603 page (no content on probes; the probe rule was only seen quoted in a thread): https://create.roblox.com/docs/release-notes/release-notes-603
- API member history (Decal; third-party dump of Roblox API builds): https://robloxapi.github.io/ref-temp/class/Decal.html

**Roblox announcements and staff replies (DevForum)**
- "Introducing New Material: Glass", Homeomorph, 2017-12-06: https://devforum.roblox.com/t/introducing-new-material-glass/64231
- "SurfaceAppearance Studio Beta [Released]", 2020-07-09: https://devforum.roblox.com/t/surfaceappearance-studio-beta-released/663449
- "Future is Bright Phase 3 Released", vrtblox, 2020-11-19: https://devforum.roblox.com/t/future-is-bright-phase-3-released/878634
- "Let There Be (Unified) Light! Unified Lighting is Fully Live", 2025-01-21, update 2025-07-23: https://devforum.roblox.com/t/let-there-be-unified-light-unified-lighting-is-fully-live/3401512
- "[Studio Beta] Emissive Masks", FGmm_r2, 2025-10-30, "Now Live for Published Experiences" 2026-02-12: https://devforum.roblox.com/t/on-hold-emissives/4034414
- "Introducing Texture Streaming", 2025-12-12, status update 2026-03-23: https://devforum.roblox.com/t/introducing-texture-streaming/4144855
- "4k Texture Rendering", 2026-01-30: https://devforum.roblox.com/t/4k-texture-rendering/4316229
- "[Studio Beta] Introducing Avatar Makeup" (WrapTextureTransfer, ComposeDecalAsync), Nov 2025 to 2026-03-18 [SNIP]: https://devforum.roblox.com/t/studio-beta-introducing-avatar-makeup/3973764
- "Indoor Reflections Bug", 2023-12-08; staff reply LightSettingsGuy 2023-12-11: https://devforum.roblox.com/t/indoor-reflections-bug/2734097
- "Decals do not render correctly unless modified during runtime", 2025-10-10, fixed the same day (staff): https://devforum.roblox.com/t/decals-do-not-render-correctly-unless-modified-during-runtime/3987081
- "Decal UVOffset / UVScale causes significant performance impact", 2026-08-11; reply 2026-09-01: https://devforum.roblox.com/t/decal-uvoffset-uvscale-causes-significant-performance-impact/4802916
- RDC 2026 coverage, GamesBeat, 2026-09-11 (secondary press): https://gamesbeat.com/?p=334453

**Community (DevForum; not official)**
- "Reflection Probes for Roblox", 2020-09-27, replies to 2026-04-19: https://devforum.roblox.com/t/reflection-probes-for-roblox/793495
- "How to get a reflective surface", 2020-03-22 (replies to 2021-01-07): https://devforum.roblox.com/t/how-to-get-a-reflective-surface/491868
- "Cube map reflections?", 2019-05-03: https://devforum.roblox.com/t/cube-map-reflections/275683
- "Real-time floor reflection", 2023-11-10: https://devforum.roblox.com/t/real-time-floor-reflection/2694706
- "Simulating 'Wetness' using EditableImages", Kalebosarus, 2026-08-19: https://devforum.roblox.com/t/simulating-wetness-using-editableimages/4819957
- "Rain Material Swapper v1.0.0", N0tKep, 2023-12-29: https://devforum.roblox.com/t/rain-material-swapper-v100/2768647
- "How to make surfaces appear wet (Material Pack Incl.)", leoburk, 2023-07-19: https://devforum.roblox.com/t/how-to-make-surfaces-appear-wet-material-pack-incl/2476461
- "Screen Distortion Rain", boatbomber, 2019-02-11: https://devforum.roblox.com/t/screen-distortion-rain/238754
- "Glass Material Issue", 2025-09-07: https://devforum.roblox.com/t/glass-material-issue/3924658
- Mirror via ViewportFrame [SNIP]: https://devforum.roblox.com/t/camera-connect-to-gui/768546 ; ViewportFrame cost [SNIP]: https://devforum.roblox.com/t/how-much-do-viewport-frames-affect-performance/376225
- "Allow CreateSurfaceAppearanceAsync to Accept All Static Content Types" [SNIP]: https://devforum.roblox.com/t/allow-createsurfaceappearanceasync-to-accept-all-static-content-types/4843351
- "Need feedback on a modeling style" (Mini Cooper; SurfaceAppearance advice for glass and metal) [SNIP]: https://devforum.roblox.com/t/need-feedback-on-a-modeling-style/4209415
- Formula Roblox update log 1.20.0 (wet track) [SNIP]: https://devforum.roblox.com/t/formula-roblox-update-log-1200/1756155

**X posts (search snippets only, not opened)**
- MaximumADHD, Sky in ViewportFrames controls their cubemap reflections: https://x.com/MaximumADHD/status/1785110948383998116
- Merely, ViewportFrame mirror and the horizontal flip problem: https://twitter.com/MerelyRBLX/status/1500266651513548800
- H3ichou, environment scales at 1 plus Reflectance: https://x.com/H3ichou/status/1333258219876200454

**YouTube (titles from search results; not watched, so no timestamps)**
- "How to Make Your ROBLOX Cars Reflective in Under a Minute!!": https://www.youtube.com/watch?v=qQ9punICDdc
- "How to get Realistic REFLECTIONS in ANY Roblox game": https://www.youtube.com/watch?v=RGcUFX8gaj8
- "Realistic Reflective Glass (Roblox Studio)": https://www.youtube.com/watch?v=lucyusN4Ej0
- "How To Make Fake Reflection In Roblox Studio": https://www.youtube.com/watch?v=UJ7zXYIArKQ
- "How To Add Realistic Materials and Textures in Roblox Studio": https://www.youtube.com/watch?v=Fsj-y9NHOgo
- "Roblox Studio realistic rain (with real water drops on screen)": https://www.youtube.com/watch?v=nIpMYh_t-ZI
- "This Roblox Driving Game Looks Too Real to Be Allowed..| Relastic car driving": https://www.youtube.com/watch?v=UA4qyhXanz4
- "Most Realistic Car startup and Car showcase in roblox": https://www.youtube.com/watch?v=-yNtCSYXzWo

**GitHub**
- 1ForeverHD/Rain (Apache-2.0, fork of buildthomas/Rain): https://github.com/1ForeverHD/Rain
- Roblox creator docs source: https://github.com/Roblox/creator-docs

**Rendering references (outside Roblox)**
- Sébastien Lagarde, "Water drop 3b – Physically based wet surfaces", 2013-04-14: https://seblagarde.wordpress.com/2013/04/14/water-drop-3b-physically-based-wet-surfaces/
- Filament, "Clear coat model": https://google.github.io/filament/Filament.md.html
- Unreal Engine, "Shading models" (Clear Coat): https://dev.epicgames.com/documentation/en-us/unreal-engine/shading-models-in-unreal-engine
- physicallybased.info (CC0 material database; values read through its API, linear values converted to sRGB): https://physicallybased.info/ , https://api.physicallybased.info/materials
- DRIVECLUB weather coverage, 2014 [SNIP]: https://blog.playstation.com/?p=135255 , https://www.destructoid.com/driveclub-has-the-best-dynamic-weather-engine-ive-ever-seen/ , https://gamingbolt.com/driveclub-uses-real-world-weather-physics-weather-effects-compared-with-forza-horizon-2
- Polycount, game windscreen rain techniques [SNIP]: https://polycount.com/discussion/comment/2336117
- Forza Motorsport press kit still and DRIVECLUB rain references: `07_visual_references.md` R11, R12, R14

**This repo**
- `04_roblox_engine_facts.md` §7.1, `09_roblox_import_pipeline.md` §1, §4, §5, `05_video_observations.md`,
  `07_visual_references.md`, `00_PLAN.md`; reference frames in
  `reference_pack/Roblox_Driving_Reference_Pack/frames/` (`00_23_tunnel_materials.jpg`,
  `01_33_wet_reflections.jpg` measured above); the model's textures in
  `C:\Users\bfhdh\Downloads\drive-lab-assets\svj_ddiaz\clean\`.
