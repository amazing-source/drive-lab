# 09: Getting a high-fidelity car into Roblox, and keeping it fast

Researched 2026-10-27. Web search and fetch only: no login, no browser automation, no model
downloaded, nothing uploaded, Studio not touched. Asset: Sketchfab "2019 Lamborghini Aventador
SVJ" by ddiaz-design (CSR2 extract, 211,767 triangles, 136,828 vertices, 54 texture files at
512 px max; see `03b_car_model_sourcing_pass2.md`).

**Tags.**
- [DOC]: Roblox docs, read on the date above.
- [ANN]: Roblox staff announcement.
- [STAFF]: a staff reply.
- [COMM]: a community post (not official).
- [KIT]: this repo's own code, which ran before.
- [INF]: my inference.
- [TEST]: must be proven in Studio before we build on it.
- [BETA]: a beta feature.

**Corrections to `03_car_model_sourcing.md` (section 5), from this pass.**
1. **Textures above 1024 are live.** 4K rendering reached published experiences on
   2026-01-30, through texture streaming. The "1024 maximum" lines still on the texture spec
   page are stale.
2. **.glb works.** Open Cloud accepts .glb since 2024-05-22, and this kit already uploads .glb
   cars that way. The Studio importer docs mention .glb, and a 2026-04 user report says it imports.
3. **Meshes can be swapped at runtime.** `MeshPart:ApplyMesh()` now exists, so a runtime LOD
   is no longer only "toggle the visibility of prebuilt parts".
4. **Emissive masks are live.** They reached published experiences on 2026-02-12, and they
   work on any MeshPart's SurfaceAppearance, not only on avatar items.
5. **A mesh over the limit is not rejected; it is silently simplified.** That is worse, and it
   needs a check that can fail.

---

## 0. Recommendation on one page

**Can the car go in at full detail? Yes.** There is a limit per MeshPart (20,000 triangles)
and **no limit per model** [STAFF 2022-12-08]. Every "imported a whole game" project does the
same thing: split the model into many meshes under the cap. One CS-style Roblox shooter
(Defuse Division) shows a 1.12-million-triangle scene built that way [COMM 2026-05-24]. Our car
is 212k triangles, so about 12 MeshParts by count; in practice 40–60, split by material and by
moving part.

**Pipeline (mostly scripted; each step is detailed in section 7).**
1. **Blender 5.2.3 LTS, headless** (not installed yet). Import the glTF, then measure scale,
   parts and textures. Split by material and by moving part, keeping every part under 18,000
   triangles. Set each moving part's origin on its real axis. Write a `manifest.json` with
   every part's role, pivot, bounding box and triangle count, plus the brief's attachment
   points. Export one GLB per group, and **only one copy of each repeated mesh** (one wheel, not four).
2. **Python + PIL, textures.** Unpack the glTF's packed maps into Roblox's separate grayscale
   maps (roughness from G, metalness from B, occlusion from R). Upscale the colour maps that the
   camera sees close up. Write a near-white paint map with a tint mask in its alpha.
3. **Upload through Open Cloud**, with the kit's existing `tools/assets/upload_images.py`:
   - GLB files as `Model`; 20 MB per file; asynchronous, poll the operation.
   - PNGs as `Decal`, then resolve each decal to its image id.
   - Turn asset privacy on first.
4. **Assemble in Studio by script** (the kit's `dev.load`, plugin security):
   - Load each Model asset and place each part from the manifest, so the result never depends
     on how the importer handled pivots.
   - Add the SurfaceAppearances (their maps can only be set at edit time) and the attachments.
   - Set the flags on every visual part and build an invisible physics chassis.
   - Save the result as an `.rbxm`.
5. **Run checks that can fail** (section 7.9):
   - Studio's triangle count against Blender's, which catches silent simplification.
   - Number of draw groups, wheel instancing, texture and mesh memory deltas.
   - Frame time with the car on screen.
   - Flags, attachments and pivots, each with a numeric tolerance.

**Why not the Studio 3D Importer as the main route?** It is a UI, with no script API found
(Roblox was only "investigating a Lua-facing Import API" in 2024). Use it **once** by hand on
the same GLB to compare: it shows per-part polycounts and makes SurfaceAppearance from PBR
textures.

**Budgets.** These are proposals to measure, not sourced limits. Roblox publishes no
per-car or per-device triangle budget.

| Item | PC | Phone | Basis |
|---|---|---|---|
| Triangles per MeshPart | ≤ 18,000 | same | Hard cap 20,000 [DOC]; over it, the mesh is silently simplified [STAFF] |
| Hero car, cockpit view | ~200k (full set) | ≤ ~150k (chase set + interior) | Source is 212k; a community claim says ~1M scene triangles are fine on modern devices [COMM] |
| Hero car, chase view | ~200k | ≤ ~120k (hide footwell, pedals, under-dash, engine internals) | [INF] |
| Other players' cars, near | LOD1 ~30–40 % (60–80k) + interior shell 3–5k | same | [INF]; automatic mesh LOD only starts at 250 studs [DOC] |
| Visible MeshParts, hero car | ≤ 60 | ≤ 45 | One draw call per unique mesh + appearance [DOC instancing rule]; shadow pass extra [INF] |
| Unique texture sets | ≤ 12 | same (streaming picks the resolution) | [INF] |
| Map size | body / wheels / main interior at 1024 (2048 only if a test shows a gain); small sets at 512 | engine streams lower mips; no 4K on Android < 3.5 GB [ANN] | Source is 512 px, so 2048 adds little real detail |
| Texture memory delta (car on vs off) | measure; aim ≤ 80 MB | aim ≤ 40 MB | Dev Console `GraphicsTexture` [DOC]; targets are [INF] |
| Frame time added by the car | ≤ 1.5 ms | ≤ 3 ms on the owner's real phone | 16.67 ms frame target [DOC]; split is [INF] |
| Collision | 1 invisible chassis (boxes or one hull) | same | Visual parts: no collide, touch or query; Massless; Box fidelity [DOC] |

---

## 1. Hard limits, as of 2026-10-27

| Item | Value | Status and source |
|---|---|---|
| **Triangles per mesh** | **20,000.** "Individual meshes can not exceed 20,000 triangles." | [DOC] Modeling specifications. Still cited as 20k in a 2026-05-23 feature request asking for 60k–200k, with no staff reply [COMM]. History: 5k → 10k in 2018 [ANN, from a search snippet only]; 20k by the 3D Importer release in 2022 [STAFF]. |
| What happens above it | **Simplified automatically, not rejected:** "The importer will simplify any mesh above this count automatically." | [STAFF tasavix 2022-12-08]; again in 2023-08 (a mesh over the limit "is being simplified" and deformed). **The trap: a silent loss of shape.** Section 7.9 compares counts. |
| Other numbers seen | "21,000" (3D Importer) and "10,000" (batch import), 2023-09-09; an avatar-path importer decimating to 10k, 2024-11 | [COMM], unconfirmed. Plan for 20k; aim at ≤ 18k. |
| Triangles per model | **No total limit** | [STAFF 2022-12-08] "no total polygon limit for a model" |
| Vertices per imported mesh | Not documented | Mesh format v2+ uses 32-bit indices [COMM, MaximumADHD's format notes]. The 60,000-vertex cap is **EditableMesh only** [DOC]. |
| Part size (bounding) | 0.001 to **2048 studs per axis** | [DOC BasePart.Size]. Irrelevant for a ~17-stud car. |
| Materials per mesh | **One:** "Mesh objects can only have one material assigned" | [DOC]. A glTF mesh with several materials imports as **one MeshPart per primitive** [DOC 3D Importer]. |
| Texture size, rendering | **Up to 4096×4096**, through texture streaming, on MeshPart (skinned and not), SurfaceAppearance, Texture, Decal and MaterialVariant | [ANN 2026-01-30] "4k Textures are now available in published experiences". Studio beta 2025-12-12. Images up to **8k** are stored and transcoded down to 4k. |
| Texture size, per device | The engine picks mips "based on the importance of each object" and device resources; **4K disabled on Android with < 3.5 GB RAM** | [ANN texture streaming update, 2026-03-23]. Streaming is on by default; creators "don't have to do anything". **EditableImage is not streamed** and is capped at 1024×1024 [DOC]. |
| Texture size, docs text | The spec page says 4096 in one place and "1024×1024 (maximum)" in two others | [DOC] last edited 2026-07-22. The 1024 lines are avatar-budget text that was never updated; the announcements above win. |
| Upload size | Open Cloud: one asset ≤ 20 MB per call; images "smaller than 8000x8000" | [DOC Assets API] |
| SurfaceAppearance maps | **5:** ColorMap, NormalMap, RoughnessMap, MetalnessMap, EmissiveMask. Separate files, not channel-packed. Albedo RGB 24-bit; others 8-bit grayscale; the emissive mask uses the red channel. | [DOC]; [ANN emissive beta 2025-10-30]. Map properties are **Plugin Security**: set at edit time, never at runtime. |
| Normal maps | **OpenGL, tangent space only** | [DOC] "Roblox only supports OpenGL format - Tangent Space". glTF already uses +Y up ("+X is right and +Y is up"), the OpenGL convention [glTF schema], so a Sketchfab glTF should need **no green flip**. Verify with the light test (7.9). |
| UVs | One UV set, 0–1, overlaps allowed | [DOC]. A tiled carbon or leather weave must be baked into the atlas. |
| DoubleSided | `MeshPart.DoubleSided`: "render both faces". Set per object in the importer ("Make Double Sided", "more performance intensive") **or by script** (write security None) | [DOC MeshPart, 3D Importer]. Use it only on single-shell glass and thin trim. |
| Vertex colours | Imported by default (importer option "Ignore Vertex Colors" is off); the mesh format stores RGBA per vertex | [DOC importer]; [COMM format notes]. How they combine with a SurfaceAppearance is undocumented [TEST]. CSR2 rips sometimes carry AO in vertex colours, so check. |
| Smoothing and normals | The mesh format stores a normal and a tangent per vertex, so the exporter's split normals (hard edges) carry through | [COMM format notes]; [INF] that Roblox does not recompute them. Prove it on one panel. Export tangents (glTF `export_tangents=True`). |
| Alpha modes | `Overlay` (default), `Transparency`, `TintMask`, `Opaque` ([BETA] in the guide) | [DOC AlphaMode enum]. Transparency mode: `MeshPart.Transparency` 0 gives hard cut-outs, ≥ 0.02 gives soft alpha [DOC]. |
| Transparency sorting | Per part, not per triangle: "When transparent parts overlap, render order may act unpredictably" | [DOC BasePart]. Partial transparency has "significant rendering costs" [DOC]. See section 5.3. |
| Emissive | `EmissiveMaskContent` + `EmissiveStrength` (studio slider 0–40, higher allowed, never negative) + `EmissiveTint`; final value "clamps" to the dynamic range | [ANN beta 2025-10-30]. Live for published experiences **2026-02-12** (that thread's update header; the linked post itself was not read). |
| Runtime mesh change | `MeshContent`/`MeshId` are not writable, but **`MeshPart:ApplyMesh(source)`** copies a source MeshPart's mesh, texture, RenderFidelity, CollisionFidelity and MeshSize | [DOC MeshPart]. Security None [TEST in a live client]. |

---

## 2. Import routes compared

| Route | Formats | Batch | Scriptable | Textures | Pivots | Verdict |
|---|---|---|---|---|---|---|
| **Studio 3D Importer** | .fbx, .gltf, .obj; .glb named in its hierarchy notes and reported working [COMM 2026-04-01] | One file (many meshes); Asset Manager for several files | **No** (UI). Roblox was "investigating a Lua-facing Import API" in 2024 [ANN]; none found shipped | PBR → SurfaceAppearance, created "automatically" when colour, roughness, normal and metalness have image textures [COMM 2026-05-07] | "Use Imported Pivot" (on) per object; "Set Pivot to Scene Origin" (on) | **Use once, by hand,** to inspect and compare. Best preview: per-part polycount, warnings |
| **Reimport** (part of the importer) | "external 3D file" | Whole model | No (one click or hotkey) | Matches PBR images by filename suffix: color / metalness / roughness / normal / emissive | Keeps Roblox properties (CollisionFidelity, RenderFidelity); matches meshes **by path and name** | Good for iterating by hand. The reimport memory is **local to one device and not saved in the place** [DOC] |
| **Asset Manager bulk import** | via the Importer | "one or more assets" | No | as the Importer | as the Importer | The 2020–2021 community route for split cars (56 road meshes; an Audi R8 split by panel) [COMM] |
| **Official Roblox Blender add-on** | not stated (Open Cloud underneath) | "any number of meshes or collections"; each object or collection becomes its own asset | Not headless: browser login ("Your browser opens and prompts for authorization") | not stated | not stated | Blender ≥ 3.2. Uploads **packages**; a re-upload updates the same package. A "reference implementation": bug fixes only. Fine by hand, **not for our script** |
| **Open Cloud Assets API** | Model: .fbx, .gltf, .glb, .rbxm/.rbxmx; Decal/Image: .png, .jpeg, .bmp, .tga; Mesh: only content from Asset Delivery | One asset per call, ≤ 20 MB; async (poll `operations/{id}`) | **Yes**, with an API key (`asset:read`, `asset:write`) | Probably kept as SurfaceAppearance or TextureID: the kit's builder handles both, but no one recorded an observation [KIT, see below; TEST]; **no import settings** can be passed [COMM, Asphalt README] | Unknown defaults → we place parts from our manifest | **The automation route.** Only .fbx content can be updated as a new version of the same asset id [DOC] |
| `AssetService:CreateAssetAsync` (Studio plugin, or Open Cloud Luau Execution) | Uploads an instance: Model, Mesh (from an EditableMesh), Image, Audio, Plugin | Scripted | Plugin or Luau-Execution context **only**; not in a live game [DOC] | Image from an EditableImage (≤ 1024) | n/a | A fallback for meshes generated in Lune or Python; same 20k cap per EditableMesh. Not needed here |
| `robloxstudio-mcp upload_asset` (local tool) | assetType Model / Decal / Audio / Animation / Video | One file per call | Yes | as Open Cloud [INF] | as Open Cloud | Equivalent to the Python uploader; the Python one already has a lockfile-free id map and decal → image resolution |

**Which route automates the whole pipeline? Open Cloud,** and the kit already uses it.
- `tools/assets/upload_images.py` sends `.glb/.gltf/.fbx/.obj` as `Model` and `.png` as
  `Decal`. It polls the operation and prints a label → asset id map.
- It reads the key from `ROBLOX_OPEN_CLOUD_API_KEY` and never prints it.
- It notes that "a decal id is not an image id: resolve the image ids afterwards
  (InsertService:LoadAsset on the decal)".
- `games/steal-cars/build/cars/MeshCars.luau` loads those Model assets with
  `InsertService:LoadAsset`. It finds the GLB's **node names preserved** on the MeshParts (it
  matches `^Wheel%u%u_`) and handles a `SurfaceAppearance` child on them.

**What that proves, and what it does not.**
- **Proven:** the upload ran. Nine cars went up this way; their Model asset ids are in
  `games/steal-cars/build/cars/meshes.luau`, generated by `tools/assets/car_meshes.py`.
- **Not proven:** that GLB textures arrive as a SurfaceAppearance. That part is the builder's
  code handling the case, which is a hypothesis, not a recorded observation. Its comment that
  some tyres arrived as "missing-texture pink" suggests textures do come through at least
  sometimes.
- **Settle it in the one-part pilot (7.10)** [TEST].

**Other upload tools (for the record).**
- **Asphalt** (`jackTabsCode/asphalt`): a Tarmac successor. Images, audio, video, .rbxm,
  and .fbx/.gltf/.glb, with a lockfile and a CI dry-run. It warns that "Roblox does not offer
  control over the import settings through the web API". Worth adopting only if we want a
  lockfile.
- **Tarmac**: images only.
- **rbxcloud v0.17**: a general Open Cloud CLI.
- **Mantle**: "no longer maintained".

**Duplicates break instancing.**
- Each upload creates new mesh ids. The importer does **not** reuse repeated meshes: one mesh
  used 20 times gives "20 drawcalls instead of 1" [COMM 2024-10-27, still open 2026-01-06].
- Reimport keeps a known-asset cache only within one Studio session [DOC].
- **So:** upload one rim, one tyre, one disc and one caliper (left and right handed if the
  shape is handed), then clone them in Studio.

---

## 3. How the "imported a whole game" projects did it

**Gap first.** The session's shared search budget ran out repeatedly. **No primary source was
found** for the CS:GO dust2, Fortnite, Minecraft-world, GTA or Forza imports the owner
mentioned, and **no YouTube tutorial titles or timestamps were reached**. None is invented
here. What was found:

| Project | Date | What they did | Numbers | Source quality |
|---|---|---|---|---|
| **Defuse Division** (Counter-Strike-style Roblox game) | Thread 2026-05-23/24 | "splitting models into multiple meshes"; a reply says no single mesh exceeds 20k | A **1.12-million-triangle** scene shown running | [COMM], in a feature-request thread |
| **Interstate 92 remake from NFS Most Wanted (2012)**, zhyperix | 2022-10-23 | "textures and some models aren't mine!", credit to Criterion. Ripped game assets | none given; no moderation reply in the thread | [COMM] |
| **Unreal MetaHuman ported to Roblox**, ZombieKicker7 | 2026-04-13 | Full character port | ~70k triangles, > 1,000 bones; hair duplicated to dodge SurfaceAppearance problems; the author calls the **materials** the weak point | [COMM] |
| **Creator Store "2021 Aventador SVJ"** A-Chassis imports | measured in pass 2 | Pre-split car | **261,187 triangles in 175 MeshParts** (315,202 in another copy); 16–93 scripts each | Measured by us, `03b` |
| **Audi R8 split for Roblox** | 2021-07-24 | Split into hood, windows, doors and other panels; FBX; Asset Manager bulk import | 10k cap at the time | [COMM] |
| **Car export help thread** | 2021-06-17 | Split the car; decimation "deforms your mesh"; 10–25k for a whole car (old cap, low-poly target) | | [COMM] |
| **Bulk import tutorial** | 2020-10-30 | Split in Blender, FBX, Asset Manager, "insert with location" | 56 road meshes | [COMM] |
| **Minecraft-style** | 2026-02-24 | Obj2Blox plugin: pasted OBJ → native block Parts (voxelising, not mesh import) | | [COMM] |

**The common method, and our plan follows it.**
1. Split under the per-mesh cap.
2. Import as one model with many MeshParts.
3. Weld them in Studio.
4. Keep textures as SurfaceAppearance (or plain TextureID on old imports).
5. Accept that repeated meshes are not deduplicated unless you clone them yourself.

**Material quality is the usual weak point.** That is section 5.

**Risks reported.**
- An imported model's chunks went invisible but stayed solid [COMM 2025-11-23, staff asked
  for a repro].
- GLB imports put every mesh in its own Model [COMM 2024-05-31]; the docs now say so for glTF.
- Real car brands: community advice only (parody the logos; low-poly is not enough because the
  silhouette stays) [COMM 2026-09-28]. No takedown cases cited. The owner has ruled the project
  a private portfolio piece (`03b`).

---

## 4. Optimising a hero car that the camera sees up close

### 4.1 Triangles
- Frame cost grows with triangles: "the number of triangles in a scene does influence how
  long a frame takes to render" [DOC]. No official budget exists.
- **Automatic mesh LOD never helps the player's own car.** `RenderFidelity = Automatic`
  renders Highest under 250 studs, Medium from 250 to 500, Lowest beyond 500 [DOC]. The cockpit
  and chase cameras are always within 250 studs.
- Avoid `Precise` on many meshes [DOC].

### 4.2 Draw calls and instancing
- Rule [DOC]: meshes with the same `MeshContent` share one draw call when their
  "SurfaceAppearances are identical if present, otherwise when TextureContents are identical".
- **Four wheels instance only if** they share one mesh asset and an identical SurfaceAppearance
  [INF]. A handed rim or caliper needs a mirrored mesh, since parts take no negative scale
  (`03`, 5.8), so count 2 draw groups per handed item.
- Every unique mesh, or the same mesh with a different appearance, is at least one draw call,
  plus a shadow pass when `CastShadow` is on [INF].
  - Turn `CastShadow` off on small interior parts [DOC: "disable shadow casting on small
    parts"].
  - The docs warn that it is not a performance switch and can cause artefacts, so test it.
- "Too many parts in a Model could cause rebuilds more often" [DOC]. Merge small static parts
  that share a material into one mesh, up to 18k triangles.
- Decals and Textures "don't batch well" [DOC], so do not use Decals for badges. Bake them into
  the atlas.

### 4.3 Texture memory
- "a 1024x1024 pixel texture consumes four times the graphics memory of a 512x512 texture";
  "it usually needs at most 512x512 pixels" unless it covers a large part of the screen [DOC].
  The hero car does cover a large part of the screen.
- Texture streaming has been on by default since 2025-12-12 [ANN]. It loads mips by importance
  and device memory. Roblox's own figure: one template went from 280 MB to 155 MB of texture
  memory [ANN].
- The streaming post's advice:
  - "unique textures where they aren't batchable";
  - atlases only for parts "typically seen together";
  - near-uniform texel density.
- **Cheapest paint:** one near-white `ColorMap` with `AlphaMode = TintMask` and the colour in
  `SurfaceAppearance.Color`. "Tinting does not affect performance", and one map serves every
  colour [DOC].
- Measure in the Developer Console: `GraphicsTexture` and `GraphicsMeshParts` [DOC], or with
  `robloxstudio-mcp get_memory_breakdown`, car spawned against not spawned.

### 4.4 LOD for a car
| Tool | What it does | Use on the hero car? |
|---|---|---|
| `RenderFidelity` Automatic | Engine LODs by distance (250/500 studs) | Leave it on (default); helps only other players' far cars |
| `Model.LevelOfDetail = StreamingMesh` | A coarse, colour-only "imposter" outside the streaming radius; "Does not support textures" [DOC] | No |
| `Model.LevelOfDetail = SLIM` | A cloud-built composite at lower resolutions, supports SurfaceAppearance. Needs StreamingEnabled, a saved place and Team Create [DOC] | **No for moving cars.** SLIM "works best on models that represent static world geometry"; runtime changes and animated models "prevent SLIM" [DOC]. Yes for parked showroom cars |
| `BasePart.LocalTransparencyModifier` | A client-only transparency multiplier; "does not replicate" [DOC]; fully transparent parts "are not rendered at all" [DOC] | **Yes.** The driver's client hides cockpit-only detail in chase view; other clients hide interior detail and show the shell beyond ~40 studs [INF; TEST that a modifier of 1 skips the draw] |
| `MeshPart:ApplyMesh(template)` | Swaps mesh + collision + texture from a prebuilt MeshPart [DOC] | Possible for distant other-player cars, to keep the instance count low [TEST]. SurfaceAppearance is a child, so it is not copied: swap it too |
| Separate LOD1 folder, toggled | Two prebuilt sets, show one | The robust fallback (`03`, step 2). Costs instance count: "Avoid creating moving assemblies with unnecessarily large numbers of instances" [DOC streaming] |

### 4.5 Streaming a vehicle
- Physical assemblies stream "as complete units". An assembly does not stream out until all
  its parts are eligible [DOC]. A welded car is one assembly.
- `ModelStreamingMode`:
  - `Atomic`: the model and all descendants stream together.
  - `Persistent`: sent at join, never streamed out.
  - **`PersistentPerPlayer` + `Model:AddPersistentPlayer(owner)`**: persistent for its owner
    and Atomic for everyone else [DOC].
- **Proposal [INF]:** player cars use `Atomic`, which keeps attachments, welds and
  SurfaceAppearances together. The driver's own car is persistent for that driver only.

### 4.6 Collision and physics on visual parts
- On every visual part: "disable collisions" (`CanCollide`, `CanTouch`, `CanQuery` all false)
  **and** use Box or Hull, "since the collision geometry is still stored in memory". "Box has
  the lowest memory overhead" [DOC].
  - Open Cloud imports arrive with the default fidelity, so the assembly script must set
    `CollisionFidelity = Box` [INF].
- `CanQuery` only takes effect when `CanCollide` is also false [DOC].
- `Massless = true` on visual parts. It works only while welded to a part with mass.
  `RootPriority` (−127..127) decides the root [DOC]. Chassis: `RootPriority = 127`, not
  massless (`03`, step 6).
- The kit's traffic cars already set the flags (no collide, no touch, no query) on every mesh part [KIT MeshCars.luau].

### 4.7 What top Roblox car games do
**Not established.** The search budget ran out before any source was found on how Driving
Empire, Car Dealership Tycoon, Jailbreak, Southwest Florida, Ultimate Driving, Greenville and
the rest build their cars: part counts, LOD, interiors, polycount in job posts. That is a gap,
not evidence that nothing is published. Closest data points:
- Hiring posts:
  - 2020-11-10 (game "Rensselaer County"): tris per car "doesn't really matter, as long as its
    not absurdly large (ex: 90k tris)". Its cars have no interior.
  - 2019-08-24 (Area 39): no polycount stated.
  - Both [COMM].
- Community A-Chassis "HQ imports": 260–315k triangles in ~175 MeshParts (our measurement).
- A commercial Roblox car pack keeps each car "under 25,000 triangles". A product listing,
  from a search snippet only.

**How to close the gap without logins:** use the Studio MCP on free Creator Store car models
(read-only insert into a scratch place, after the owner switches on "Allow Loading Third Party
Assets"). Count MeshParts, triangles, SurfaceAppearances and LOD tricks. Published games'
files cannot be inspected.

---

## 5. Materials

### 5.1 From CSR2 / Sketchfab maps to Roblox maps
- **What we have.** CSR2 sets are named `*_DiffuseAOSO`, `*_Material`, `*_Normal`,
  `*_Emissive` and `InteriorA_MaterialOpacity` (`03b`).
- **What the Sketchfab glTF will hold** is whatever the uploader wired into Sketchfab's PBR
  slots, written as standard glTF [INF]:
  - `baseColorTexture`;
  - `metallicRoughnessTexture`: "metalness values are sampled from the B channel. The roughness
    values are sampled from the G channel" [glTF schema];
  - `normalTexture` (+Y up);
  - `occlusionTexture` ("sampled from the R channel");
  - `emissiveTexture`;
  - `alphaMode` OPAQUE / MASK / BLEND.
- **Roblox wants separate grayscale files.** Unpack them with PIL: G → `Roughness.png`,
  B → `Metalness.png`, R of occlusion → multiply into the colour map (Roblox has no AO slot).
  The same advice appears for the importer [COMM 2026-05-07].
- **CSR2-specific, a hypothesis to check by looking at each channel:**
  - "DiffuseAOSO" probably has AO (and maybe a specular occlusion) baked into the colour.
  - "Material" probably packs gloss, metal or reflection masks, possibly with gloss inverted
    (gloss = 1 − roughness).
  - Dump every channel of every map to PNG and look before mapping anything.
  - A map that reads as "shiny where white" is gloss and must be inverted.
- **Baked AO**:
  - keep it in interior colour maps (contact shadows);
  - **remove it from body paint**, because TintMask multiplies the colour and baked AO turns
    into dirty paint.

### 5.2 Car paint (no clear coat in Roblox)
- SurfaceAppearance has five maps and no clear-coat layer [DOC]. Reflections come from the
  environment: `Lighting.EnvironmentSpecularScale` "will make smooth objects reflect the
  environment". **Its documented default is 0**, and with 0 "metalness has no effect"
  (`03`, 5.5) [DOC]. Set it to 1 in the bench place.
- **Recipe [INF; TEST each number]:**
  - Solid colour: Metalness 0, Roughness ~0.15–0.25 (the guide says to add "around 0.1"
    because of Fresnel).
  - Metallic paint: Metalness ~0.3–0.6 with roughness ~0.2–0.3.
  - Tint: `TintMask` alpha = 1 on paint and 0 on badges or decals, colour in
    `SurfaceAppearance.Color`.
- **Fake clear coat:** low roughness plus a strong, detailed sky (what the paint reflects) is
  most of the look [INF]. A second transparent shell over the paint is a bad idea: it adds
  sorting and overdraw.
- **Material Variants are the wrong tool for the body.** They are "for customizing the
  appearance of reusable tileable material", while SurfaceAppearance is for "a specific mesh
  with UV mapping" [DOC]. A MaterialVariant on carbon, Alcantara or tyre sidewall could save
  texture memory; how it tiles on a MeshPart is undocumented [TEST]. A 2026-05 user found
  SurfaceAppearance reliable where MaterialVariant was not [COMM].

### 5.3 Glass
- **Option A:** `Material = Glass` + `Transparency` (the kit's traffic cars use ≥ 0.35)
  [KIT]. Glass refraction "is not supported on mobile devices" [DOC]. `Reflectance` "may or may
  not be ignored depending on the Material" [DOC].
- **Option B:** SurfaceAppearance `AlphaMode = Transparency`, alpha in the colour map (a sun
  band, a dirt gradient), `MeshPart.Transparency` ≥ 0.02 for soft alpha [DOC].
- **Sorting is per part** [DOC]. So:
  - each pane (windshield, side windows L/R, rear screen, engine-cover glass) is its own MeshPart;
  - **delete the inner shell** that game rips often carry (two glass surfaces per window), and
    use one `DoubleSided` shell instead;
  - no transparent part overlaps another from the cockpit view.
- Check from both cameras (7.9). The brief rejects a windshield that reads as opaque.

### 5.4 Lights, dashboard, emissive
- **Emissive masks** (live 2026-02-12):
  - mask from the CSR2 `*_Emissive` map, converted to grayscale (red channel used);
  - `EmissiveStrength` and `EmissiveTint` have no security tag, so a script should be able to
    drive brake lights and indicators [DOC; TEST at runtime];
  - emissives "now appear at all quality levels and no longer fade out at far distances" [ANN].
- **`Neon` material** remains the glow fallback.
- **Live gauges:** a SurfaceGui on the thin `DashboardSurface` part (`03`, step 3), with the
  static dial graphics in the emissive mask.

### 5.5 The 512 px problem: upscale or re-texture
- **Real-ESRGAN** (`xinntao/Real-ESRGAN`):
  - code under **BSD-3-Clause**; the README states **no licence for the model weights**;
  - a portable Windows `realesrgan-ncnn-vulkan` build that is "portable and includes all the
    binaries and models", with "No CUDA or PyTorch environment" needed;
  - models `realesrgan-x4plus` (general) and `realesr-general-x4v3` (small, with denoise).
- **Use it only on colour maps** [INF]. A GAN invents texture: fine on leather or plastic
  albedo, wrong on normal maps, where it bends the vectors. For normal, roughness and metalness
  maps use Lanczos ×2, then renormalise the normal map.
- **Re-texture where it shows** [INF]:
  - In the cockpit (seats, dash top, steering wheel), bake real tileable PBR materials
    (leather, Alcantara, carbon) into the existing UVs at 1024 in Blender.
  - That gives true detail rather than guessed detail, and it costs a Cycles bake per set.
- **Target:** 1024 for the body, wheels, seats and dash; 512 kept for small or unseen sets.
  2048 only where a side-by-side screenshot shows a gain.

---

## 6. Runtime meshes: EditableMesh and EditableImage

| Fact | Status |
|---|---|
| EditableMesh: "a limit of 60,000 vertices and 20,000 triangles" | [DOC] |
| Created with `AssetService:CreateEditableMesh()` / `CreateEditableMeshAsync(content)` (FixedSize by default); shown through `CreateMeshPartAsync()` or `MeshPart:ApplyMesh()` | [DOC] |
| "fails by default in published games"; enable "Enable Mesh / Image APIs" (Creator Dashboard) or "Allow Mesh / Image APIs" (Studio, Security) | [DOC] |
| Age or ID verification: the **current English page says nothing**. Search snippets of older or localised pages said "13+ age verified and ID verified" | **Uncertain**: check the toggle's own prompt before relying on it |
| Client memory budgets are "strict"; creation returns `nil` when the budget is exhausted; server, Studio and plugins are unlimited | [DOC] |
| EditableImage: max 1024×1024; **not covered by texture streaming** | [DOC]; [ANN] |
| `CreateSurfaceAppearanceAsync` takes only EditableImage content, not asset ids | [DOC] |

**Verdict: they do not help the hero car.** EditableMesh has the same 20k cap as an uploaded
mesh. It costs client memory that uploaded meshes do not. It is off by default in live games.
Its images skip streaming and stop at 1024. The only plausible later uses are panel
deformation for crash damage, or a procedural tyre bulge [INF]. Neither is in the brief.

**One build-time use:** `AssetService:CreateAssetAsync` in a Studio plugin can upload an
EditableMesh as a Mesh asset [DOC]. That route would let Lune or Python generate geometry
without Blender. Open Cloud with a GLB is simpler, so it stays a fallback.

---

## 7. The pipeline we can run here

**Gate:** nothing below runs before the owner's go (`00_PLAN.md`). Uploads create assets on the
owner's account, and Studio work happens in the Drive lab bench place, never the Rob A Car place
(`04`, section 9). **The owner downloads the model**; it needs a Sketchfab login, which we do
not use. `tools/assets/sketchfab_download.py` exists if they set `SKETCHFAB_API_TOKEN`
themselves.

**Reuse, do not rewrite.** The kit has a working low-poly car pipeline [KIT]:
- `tools/blender/inspect_model.py`: lists meshes, triangles, bounds and materials.
- `tools/blender/prepare_car.py`:
  - orients the car (nose to +X), finds the four wheels by shape, merges by material;
  - decimates to a total budget with `PER_MESH_LIMIT = 9000`, shrinks textures;
  - exports `car.glb` + `manifest.json` + a preview.
- `tools/assets/upload_images.py`: the Open Cloud uploader.
- `games/steal-cars/build/cars/MeshCars.luau`: the Studio builder.

The hero car needs a **new** `prepare_hero_car.py`, because:
- the traffic one merges whole wheels and drops interiors;
- it decimates to 24k triangles in total;
- it has no pivots or attachments.

It should import the shared helpers (`load`, `orient`, `split_loose`, `find_wheels`,
`triangles`, `render_preview`).

### 7.1 Install
- Blender **5.2.3 LTS** (released 2026-10-22; 5.3 due 2026-11-10). Take the portable zip from
  blender.org, which needs no installer.
- Run it headless:
  `blender --background --factory-startup --python <script> -- <args>`.
- The machine has limited RAM. A 212k-triangle model is small for Blender; render previews at
  low samples.

### 7.2 Inspect (no changes)
Run `inspect_model.py` on the glTF. Record:
- mesh objects, triangles per object, materials per object, bounds;
- scale: the glTF unit is the metre; check the length against the real car's 4.943 m
  (wheelbase 2.700 m, `02_aventador_svj_data.md` D5);
- which wheels, calipers, discs, doors, steering wheel and wipers are **separate objects**.
  Pass 2 left this unverified.

**Stop** if the wheelbase is off by more than 3 %, or if there are no calipers, only baked-in wheels.

### 7.3 Split
1. Apply every transform. Orient to the kit convention, written into the manifest:
   - glTF is +Y up, front +Z;
   - Roblox is +Y up with `LookVector` −Z;
   - the kit's cars point their nose along +X.

   The Drive lab chooses one and the manifest states it. The orientation check (7.9) catches a
   wrong choice.
2. Separate by material: `bpy.ops.mesh.separate(type="MATERIAL")`. Then separate by loose
   parts where a moving part shares a material with the body.
3. Classify each piece into a group from a small, hand-written `groups.json`, with the
   automatic guess from `find_wheels` and from names:
   - `Body_*` (static, welded);
   - `Interior_*` (static, but its own LOD set);
   - `Corner_FL/FR/RL/RR` → `Hub` (rim + tyre + disc spin) and `Knuckle` (caliper, steers,
     never spins);
   - `SteeringWheel`, `Wipers`, `Doors_L/R`, `Pedals`;
   - `Glass_*` (one pane each);
   - `Lights_*` (emissive).
4. **Repeated meshes:**
   - keep **one** rim, tyre, disc and caliper as the master;
   - test whether the other corners are exact copies (same vertex count and positions after
     undoing the transform, tolerance 1e-4);
   - if so, export the master once and record the other corners as transforms in the manifest;
   - mirrored copies get a `_L`/`_R` mesh.

### 7.4 Reduce triangles only where safe
- **Splitting is lossless; decimating is not.** A part over 18,000 triangles is first
  **bisected along a real panel gap** into two parts with the same material. There is no
  per-model cap, so this costs only a draw call.
- Decimate (`DECIMATE` modifier, `COLLAPSE`) only:
  - what is never close to the camera (underbody, engine internals behind opaque covers,
    suspension);
  - interior props in the chase LOD set.

  Planar dissolve suits flat interior panels. Never decimate the body silhouette, the glass or
  the wheels (the community reports decimation "deforms your mesh").
- Build the **chase LOD set** and the **other-player LOD1 set** as extra exported groups:
  - the chase set drops pedals, footwell and under-dash;
  - LOD1 is about 30–40 %, plus a 3–5k interior shell.

### 7.5 Pivots and attachments
- **Hinged parts.** Set the origin exactly on the rotation axis:
  - wheel hub: centre of the tyre's bounding cylinder; axis along the axle;
  - steering wheel: the column axis;
  - wipers: each spindle;
  - doors: the scissor hinge, measured on references.

  Use `bpy.ops.object.origin_set(type="ORIGIN_CURSOR")` after placing the cursor.
- **Attachments.** Create Blender empties named exactly as the brief lists them:
  `Wheel_FL/FR/RL/RR`, `Exhaust_L/R`, `Headlight_L/R`, `BrakeLight_L/R`, `DriverEye`,
  `CameraChase`, `CameraHood`, `EngineAudio`, `ExhaustAudio`, `DashboardSurface` and
  `WiperPivot`(s). Each sits at a measured point.
- **Write `manifest.json`.** Per part:
  - name, group, role, material set and triangle count;
  - bounding-box centre and size in car space;
  - the pivot as a full CFrame (position + axis);
  - `CastShadow`, `DoubleSided` and LOD set membership.

  Per attachment: its CFrame. Everything in metres, plus the studs-per-metre factor the Drive lab
  uses (`04`, units: 1 stud = 0.28 m).
- **Why the manifest:** Open Cloud passes no import settings. The Studio side therefore places
  every part from the manifest and sets `PivotOffset` itself. Importer pivot behaviour stops
  mattering.

### 7.6 Textures (Python + PIL, `python -I`)
1. Dump every channel of every glTF image to `textures/_channels/` and label the mapping by
   looking at them (5.1).
2. Write Roblox maps per texture set:
   - `Color` (RGB; AO multiplied in for the interior only);
   - `Normal` (as is, +Y);
   - `Roughness` (G, or 1 − gloss);
   - `Metalness` (B);
   - `Emissive` (grayscale);
   - for paint, a near-white `Color` with a TintMask alpha.
3. Upscale the close-up colour maps (Real-ESRGAN) and the others (Lanczos, normal map
   renormalised). Name them `<set>_color.png`, `_normal`, `_roughness`, `_metalness`,
   `_emissive`; Reimport matches those suffixes if the Studio route is ever used [DOC].
4. Export the GLBs **without** embedded images, except when testing the importer, so the same
   image is never uploaded twice. Images are uploaded once as Decals; the meshes go up bare.

### 7.7 Upload (Open Cloud)
- Turn on asset privacy first: "Opt-in to restrict assets on creation" (`03`, 5.9).
- `python -I tools/assets/upload_images.py <user id> <group GLBs...> <PNGs...>` → a JSON map of
  label → asset id.
- Store the map in the repo (ids only, never the key).
- Resolve decal → image ids in Studio (`InsertService:LoadAsset(decal).Texture`), as the
  uploader's docstring says.
- To update a mesh, upload **.fbx**: only .fbx content can be versioned under the same id
  [DOC]. Otherwise a fix means a new id and a manifest update.

### 7.8 Assemble in Studio (script, plugin security)
A builder module like `MeshCars.luau`, run through `dev.load` inside `dev.record`:
1. `InsertService:LoadAsset(modelId)` per group; collect the MeshParts by name (names survive [KIT]).
2. Per manifest entry:
   - clone the master mesh for each instance;
   - set `CFrame` from the manifest bounding-box centre;
   - set `Size` from `MeshSize` × the studs-per-metre factor;
   - set `PivotOffset` from the manifest pivot.
3. Create the `SurfaceAppearance`s: set the maps by image id (edit time only) and `AlphaMode`.
   **Share one SurfaceAppearance setup across instances** so the wheels instance.
4. Flags on every visual part:
   - `CanCollide`, `CanTouch` and `CanQuery` false;
   - `Massless` true;
   - `CollisionFidelity` Box;
   - `CastShadow` from the manifest;
   - `DoubleSided` on glass;
   - `RenderFidelity` Automatic.
5. Build `Chassis`:
   - invisible, Box parts or one hull;
   - `RootPriority` 127, mass from `02`;
   - `Knuckle`/`Hub` with Motor6D or welds driven on the client (`03`, step 5);
   - the attachments from the manifest.
6. `Model.ModelStreamingMode = Atomic`. Interior and LOD sets go in separate folders
   (`LOD_Cockpit`, `LOD_Chase`, `LOD1`, `InteriorShell`) for `LocalTransparencyModifier` toggling.
7. Export an `.rbxm` to the repo (`robloxstudio-mcp export_rbxm`). A Lune-written rbxm drops Model
   pivots, so keep the pivots on a PrimaryPart (memory: *part-models-offline*).

### 7.9 Checks that can fail
Each check is shown failing once, on a deliberately broken copy, before it is trusted (the
kit's rule).

| # | Check | How | Fails when | Broken copy to prove it |
|---|---|---|---|---|
| 1 | Triangles per part | Blender count in the manifest; Studio count via `AssetService:CreateEditableMeshAsync(part.MeshContent)` → `#mesh:GetFaces()` in edit (plugin memory is unlimited), or `get_scene_analysis` `triangle_composition` | any part > 18,000 in Blender | an unsplit 30k panel |
| 2 | **Silent simplification** | Studio count against Blender count, per part | Studio < Blender by > 0.5 % | upload one 25k-triangle test mesh: Roblox simplifies it, and the check must fire |
| 3 | Draw groups | Count distinct (MeshContent, SurfaceAppearance signature) among visible parts, per LOD set | > 60 (PC set) / > 45 (phone set) | duplicate the wheel as 4 separate uploads |
| 4 | Wheel instancing | All corner rims share one `MeshContent` (per hand) and one appearance signature | any mismatch | re-upload one rim |
| 5 | Scale | Distance `Wheel_FL` ↔ `Wheel_RL` = 2.700 m × studs/m | off by > 1 % | scale the model by 1.05 |
| 6 | Orientation | A marker at the front-left in the manifest lands at the front-left in Studio | wrong sign on any axis | flip X in the export |
| 7 | Pivots | Rotate every hub 360° and steer the knuckles ±30°; the hub's bounding-box centre stays within 0.01 studs of the axle point | drift > 0.01 | offset one origin by 2 cm |
| 8 | Hierarchy | no caliper is a descendant of a `Hub` | any | parent one caliper to its hub |
| 9 | Flags | every visual part: no collide, no touch, no query, Massless, Box | any | leave one at Default fidelity |
| 10 | Attachments | every brief name exists exactly once, on `Chassis` | missing or duplicated | delete `DriverEye` |
| 11 | Memory | `get_memory_breakdown` tags `GraphicsTexture`, `GraphicsMeshParts`, car spawned against not, in a playtest client | above the 0-section targets | swap a set to 2048 maps |
| 12 | Frame time | `capture_micro_profiler` (`focus: render`, `include_gpu: true`), fixed camera, car on screen against off, chase and cockpit | above 1.5 ms (PC) | double the car |
| 13 | Normal map | a light orbiting one body panel; bumps must not invert | visual | flip G on one map |
| 14 | Glass | screenshots from the cockpit and chase cameras (`capture_screenshot`); no pane hides another, no opaque windshield | visual | keep the double glass shell |
| 15 | Phone | **the owner's real phone** in the private bench place, Developer Console memory + Shift+F5 frame rate | above the phone targets | n/a |

The Studio device simulator (`set_device_simulator`, `capture_device_matrix`) changes only the
viewport, resolution and pixel density; it does not emulate a phone's GPU or memory. Use it for
framing and UI only. A phone number comes from a phone (`03`, step 7).

### 7.10 Order of work and what is still unproven
1. Inspect (7.2): no risk, no upload.
2. One-part pilot:
   - export one wheel (rim + tyre + disc + caliper) and one body panel;
   - upload them; assemble them;
   - run checks 1–4 and 7, and the 25k silent-simplification test.

   This settles the [TEST] items that decide the rest:
   - textures through Open Cloud GLB;
   - default CollisionFidelity on Open Cloud imports;
   - whether `LocalTransparencyModifier = 1` skips the draw;
   - whether differing `SurfaceAppearance.Color` still instances;
   - whether emissive writes work at runtime.
3. Full car; then the LOD sets; then the phone run.

---

## Sources

All read 2026-10-27 unless marked "snippet" (seen only in a search result).

**Roblox documentation (create.roblox.com)**
- Modeling specifications: https://create.roblox.com/docs/art/modeling/specifications
- Texture specifications: https://create.roblox.com/docs/art/modeling/texture-specifications ; edit history https://github.com/Roblox/creator-docs/commits/main/content/en-us/art/modeling/texture-specifications.md (last edit 2026-07-22)
- 3D Importer: https://create.roblox.com/docs/art/modeling/3d-importer
- Reimport: https://create.roblox.com/docs/art/modeling/reimport
- Export requirements: https://create.roblox.com/docs/art/modeling/export-requirements
- PBR textures (SurfaceAppearance guide): https://create.roblox.com/docs/art/modeling/surface-appearance
- SurfaceAppearance: https://create.roblox.com/docs/reference/engine/classes/SurfaceAppearance ; AlphaMode: https://create.roblox.com/docs/reference/engine/enums/AlphaMode
- MeshPart (DoubleSided, RenderFidelity, ApplyMesh, MeshContent): https://create.roblox.com/docs/reference/engine/classes/MeshPart
- BasePart (Size, Transparency, Massless, RootPriority, CanQuery, LocalTransparencyModifier): https://create.roblox.com/docs/reference/engine/classes/BasePart
- Model; ModelLevelOfDetail; ModelStreamingMode: https://create.roblox.com/docs/reference/engine/classes/Model , https://create.roblox.com/docs/reference/engine/enums/ModelLevelOfDetail , https://create.roblox.com/docs/reference/engine/enums/ModelStreamingMode
- SLIM: https://create.roblox.com/docs/workspace/streaming/slim ; Instance streaming: https://create.roblox.com/docs/workspace/streaming
- Improve performance: https://create.roblox.com/docs/performance-optimization/improve ; Identify performance issues: https://create.roblox.com/docs/performance-optimization/identify
- Materials: https://create.roblox.com/docs/parts/materials ; Lighting: https://create.roblox.com/docs/reference/engine/classes/Lighting
- EditableMesh, EditableImage, AssetService: https://create.roblox.com/docs/reference/engine/classes/EditableMesh , https://create.roblox.com/docs/reference/engine/classes/EditableImage , https://create.roblox.com/docs/reference/engine/classes/AssetService
- Open Cloud Assets API guide: https://create.roblox.com/docs/cloud/guides/usage-assets
- Asset Manager: https://create.roblox.com/docs/projects/assets/manager
- Roblox Blender plugin: https://create.roblox.com/docs/art/modeling/roblox-blender-plugin

**Roblox announcements and staff posts (DevForum)**
- "4k Texture Rendering", FGmm_r2, 2026-01-30: https://devforum.roblox.com/t/4k-texture-rendering/4316229
- "[Studio Beta] 4k Texture rendering", 2025-12-12, update 2026-01-30: https://devforum.roblox.com/t/studio-beta-4k-texture-rendering/4144950
- "Introducing Texture Streaming", 2025-12-12, update 2026-03-23: https://devforum.roblox.com/t/introducing-texture-streaming/4144855
- "[Studio Beta] Emissive Masks", 2025-10-30, update header "live for published experiences" 2026-02-12: https://devforum.roblox.com/t/on-hold-emissives/4034414
- "3D Import Recap Mar-Apr 2024", tasavix, 2024-05-22 (Open Cloud glTF/GLB; Lua import API "investigating"): https://devforum.roblox.com/t/3d-import-recap-mar-apr-2024/2979668
- "3D Importer [Full Release]", page 3, tasavix 2022-12-08 (20k cap, auto-simplify, no model total): https://devforum.roblox.com/t/3d-importer-full-release/2057539?page=3
- "Increased polygon limit for CSG parts and Mesh parts" (2018; snippet): https://devforum.roblox.com/t/increased-polygon-limit-for-csg-parts-and-mesh-parts/195604
- SLIM newsroom post, 2025-12 (snippet): https://about.roblox.com/newsroom/2025/12/introducing-roblox-slim-scalable-lightweight-interactive-models ; Creator Roadmap 2025 RDC update (snippet): https://devforum.roblox.com/t/creator-roadmap-2025-rdc-update/3961527
- Khronos, "Roblox Announces 3D Importer Support for glTF Files (Beta)", 2023-05-10: https://www.khronos.org/news/permalink/roblox-announces-3d-importer-support-for-gltf-files-beta

**Community (DevForum; not official)**
- "Increase the max triangle limit", 2026-05-23 (Defuse Division 1.12M-triangle scene; "1 million triangles in a scene"): https://devforum.roblox.com/t/increase-the-max-triangle-limit/4650221
- "Importing more than 21k tris?", 2023-09-09: https://devforum.roblox.com/t/importing-more-than-21k-tris/2586514
- "Roblox Import 3D bug", 2023-08-04/10 (over-limit mesh "is being simplified"): https://devforum.roblox.com/t/roblox-import-3d-bug/2506325
- "21k import limit, how do I get it back?", 2024-11-10: https://devforum.roblox.com/t/21k-import-limit-how-do-i-get-it-back/3253875
- "Mesh importer really needs some improvements", 2024-10-27 (no deduplication; "20 drawcalls instead of 1"): https://devforum.roblox.com/t/mesh-importer-really-needs-some-improvements/3230564
- "Audi r8 with a lot of vertices", 2021-07-24: https://devforum.roblox.com/t/audi-r8-with-a-lot-of-vertices/1370887
- "Blender help exporting cars", 2021-06-17: https://devforum.roblox.com/t/blender-help-exporting-cars/1295412
- "Best way to reduce tris", 2020-06: https://devforum.roblox.com/t/best-way-to-reduce-tris/637135?page=2
- "Best way to import multiple meshes (bulk import)", 2020-10-30: https://devforum.roblox.com/t/best-way-to-import-multiple-meshes-bulk-import/845859
- "Importing GLB files puts every mesh into its own model", 2024-05-31: https://devforum.roblox.com/t/importing-glb-files-puts-every-mesh-into-its-own-model/2997651
- GLB import working, 2026-04-01: https://devforum.roblox.com/t/why-does-importing-my-mesh-animations-together-as-glb-work-but-separately-as-fbx-gltf-breaks-the-animation/4551325
- "Separate model into different parts?", 2026-05-06/07 (automatic SurfaceAppearance; unpack ORM): https://devforum.roblox.com/t/separate-model-into-different-parts/4621524
- "Interstate 92 Remake from NFS Most Wanted 2012", 2022-10-23: https://devforum.roblox.com/t/interstate-92-remake-from-nfs-most-wanted-2012/2031546
- "Thoughts on UE MetaHuman ported to Roblox", 2026-04-13: https://devforum.roblox.com/t/thoughts-on-ue-metahuman-ported-to-roblox/4573074
- Obj2Blox, 2026-02-24: https://devforum.roblox.com/t/obj-files-to-minecraft-style-blocks-in-roblox-studio/4435580
- "Limitations when using real car brands/models", 2026-09-28: https://devforum.roblox.com/t/limitations-when-using-real-car-brandmodels-in-roblox-experiences/4901743
- Imported chunks invisible but solid, 2025-11-23: https://devforum.roblox.com/t/large-chunks-of-imported-3d-model-disappeared-but-still-interactable/4092794
- "Roblox Mesh Format", MaximumADHD, 2019-08-09 (revised 2025-03-30): https://devforum.roblox.com/t/roblox-mesh-format/326114
- Hiring posts: 2020-11-10 https://devforum.roblox.com/t/negotiable-open-hiring-vehicle-modelers/863843 ; 2019-08-24 https://devforum.roblox.com/t/150k-seeking-3d-modeler-vehicle-design/337513
- Local visibility threads (snippet): https://devforum.roblox.com/t/toggle-model-visibility/1936276 , https://devforum.roblox.com/t/hide-objects-locally/1139730

**Tools and specs**
- Roblox Blender add-on: https://github.com/Roblox/roblox-blender-plugin
- Asphalt: https://github.com/jackTabsCode/asphalt ; Tarmac: https://github.com/Roblox/tarmac ; rbxcloud: https://github.com/Sleitnick/rbxcloud ; Mantle: https://github.com/blake-mealey/mantle
- Real-ESRGAN: https://github.com/xinntao/Real-ESRGAN
- glTF 2.0 schema (normal convention, ORM channels, alpha modes): https://github.com/KhronosGroup/glTF/blob/main/specification/2.0/schema/material.schema.json , https://github.com/KhronosGroup/glTF/blob/main/specification/2.0/schema/material.pbrMetallicRoughness.schema.json
- Blender download (5.2.3 LTS, 2026-10-22): https://www.blender.org/download/

**This repo**
- `tools/blender/inspect_model.py`, `tools/blender/prepare_car.py`, `tools/assets/upload_images.py`,
  `tools/assets/car_meshes.py`, `tools/assets/sketchfab_download.py`,
  `games/steal-cars/build/cars/MeshCars.luau`.

**Not reached (budget):** YouTube tutorials, Reddit r/robloxgamedev, X posts, primary sources
for CS:GO, Fortnite, Minecraft, GTA and Forza imports, and any source on how the top Roblox car
games build their cars.
