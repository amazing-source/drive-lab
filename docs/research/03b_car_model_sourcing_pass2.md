# 03b: Car model sourcing, pass 2

Researched 2026-10-27. Public APIs and image GETs only: no login, no browser automation, no model
file downloaded. Images saved in `model_candidates/` (one folder per candidate) and tiled into
labelled sheets in `model_candidates/_contact_sheets/`. Start with `00_top5.jpg`.

**Rules changed twice during this pass.** The owner first allowed NC licences, then ruled the
project a private portfolio piece: game rips and unlicensed models are accepted, and **the ranking
is on quality only**. Licence and provenance are still recorded in one column, for the record, and
do not move the ranking.

**What "interior" means here.** I could not open a 3D viewer. Interior verdicts come from three
things, and each row says which: (1) what the image shows through the glass or in an interior
render; (2) the model's texture names, read from Sketchfab's public texture listing
(`sketchfab.com/i/models/<uid>/textures`), e.g. `InteriorA_Emissive`, `seatbelt_001`,
`upholstery`; (3) the author's text and the comments. Separation (doors, calipers, wheels) is
**unverified** for every model until the file is opened in Blender.

---

## 1. Answer

**Best pick: ddiaz-design, "2019 Lamborghini Aventador SVJ" (Sketchfab, a CSR2 extract).**
It is the only free model I found that is (a) a stock Aventador SVJ, (b) built with a complete
interior, and (c) already game-ready: 211,767 triangles, UV-mapped, baked AO, separate texture
sets for interior, wheels, calipers, lights and engine. That is close to the Roblox budget as it
stands (about 12 MeshParts at 18k triangles), so little detail is lost converting it.
Its weakness is texture resolution: **512 px** (mobile-game textures), so the cockpit will look
soft in a close camera unless the interior textures are re-made.

**If the owner would trade the SVJ for the most realistic car:** pick #2, the AnatolianStudios
Revuelto (2048 px textures, 547k triangles, very realistic in real time), and switch the
simulation data to the Revuelto.

**Download route for the best pick:**
- Page: https://sketchfab.com/3d-models/1910d24bbad34fdda0c4fe30f01b3cc1
- Needs a **free Sketchfab account** (downloads require sign-in).
- Formats offered (from the API's archive list): **glTF (6.5 MB)**, GLB (15.9 MB), USDZ (5.9 MB)
  and the uploader's original "source" archive (13.3 MB, format not stated). Take the **glTF**:
  Roblox's 3D Importer takes .gltf/.fbx/.obj, not .glb (pass 1, section 5.2).
- Same mesh, other uploads: the "SVJ 63" livery version by the same author
  ([89258ec0…](https://sketchfab.com/3d-models/89258ec08a6c4e9dbc4194cf71c0aa08)), and Outlaw_Games'
  re-upload ([e328d9f5…](https://sketchfab.com/3d-models/e328d9f5dcfd48bdbe8c73324b52ece3)),
  whose front image shows the cabin best.

---

## 2. Ranked top 5 (quality only)

| # | Model | Link | Licence / provenance (record only) | Triangles | Textures | Interior verdict (evidence) | Part separation | Real-car documentation | Images |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **2019 Lamborghini Aventador SVJ**, ddiaz-design | [Sketchfab](https://sketchfab.com/3d-models/1910d24bbad34fdda0c4fe30f01b3cc1) | Labelled CC BY. Author: "Based on a CSR2 3d model". Game extract. | 211,767 (136,828 verts) | 54 files, max **512 px**; CSR2 sets `DiffuseAOSO` + `Material` + `Normal` + `Emissive` | **Complete game interior.** Texture sets `InteriorA_DiffuseAOSO/Normal/MaterialOpacity/Emissive` (an emissive interior map means lit gauges/screens); cabin and seats visible in its image and in Outlaw_Games' front view of the same mesh | Separate texture sets for `Wheel1A`/`Wheel2A`, `CalliperBadgeA`, `EngineA`, `LightA`, `Grille1-3A`. Separate objects: unverified | **High.** The SVJ is the owner's reference and `02_aventador_svj_data.md` is being written for it | `sf_svj2019_csr2_ddiaz/thumb.jpg`, `sf_aventador_outlaw/thumb.jpg`, `sf_svj63_csr2_ddiaz/thumb.jpg`; sheet `09_svj_rips_a.jpg` |
| 2 | **Lamborghini Revuelto**, AnatolianStudios | [Sketchfab](https://sketchfab.com/3d-models/099b60042519463ead19ce054d479724); also free on [CGTrader](https://www.cgtrader.com/free-3d-models/car/sport-car/lamborghiini-revuelto) | Labelled CC BY. Texture names follow the Forza shared-library style (`stitch_033_nrml`, `seatbelt_001_nrml`, `undercarriage_001_glos`), so probably a Forza Horizon extract (not proven) | 547,717 | 38 files, max **2048 px** | **Detailed.** Seats and dash visible through the glass in a real-time capture; textures for `suede`, `stitch`, `seatbelt`, `steel_heat_treated` | Unverified | Medium. Official power, torque and dimensions exist; the hybrid (3 e-motors, 8-speed DCT) is harder to simulate faithfully | `sf_revuelto_anatolian/thumb.jpg`; sheet `04_interior_leaders.jpg` |
| 3 | **Lamborghini Revuelto**, AmJViZ (Amir Jafari) | [Blendkit](https://www.blendkit.com/asset-gallery-detail/4146135b-e6e7-45f5-b81b-372d4bbb74e8/) | Blendkit Royalty Free, free. Authored in Blender (live mirror/subsurf/bevel modifiers, which a rip would not have) | 79,950 base / 477,053 with modifiers | 34 maps, 1536–4096 px | **Seen complete** in the author's interior render: steering wheel, cluster, carbon dash, console screen, seats | 130 objects, so probably well split; unverified | Medium (same car as #2) | `bk_lamborghini_revuelto_amjviz/thumb.jpg` |
| 4 | **Porsche 911 with interior** (992 Turbo S), n.brizitskaya | [Sketchfab](https://sketchfab.com/3d-models/877b1bc1739f4a2bb65d62fd7ffd9f75) | CC BY. Authored-looking bakes (`AO_leather_int_1024`, `AO_rug_interior_1024`) | 424,043 | 46 files, max 2048 px | **Detailed** by texture names: `upholstery`, `leather_seam`, `Leather_perfo`, `belts`, `rug`; cabin visible through glass | A 2026-07 comment: "many parts are grouped into a single mesh". Hand separation needed | **Very high.** Porsche publishes PDK ratios, torque curves, masses | `sf_porsche911_brizitskaya/thumb.jpg` |
| 5 | **2021 Lamborghini Aventador SVJ**, Roblox Creator Store (same import re-uploaded: [18362571957](https://create.roblox.com/store/asset/18362571957), [16905561938](https://create.roblox.com/store/asset/16905561938), [17221477333](https://create.roblox.com/store/asset/17221477333), SVJ 63 [12713929163](https://create.roblox.com/store/asset/12713929163)) | Creator Store | Free. A-Chassis import of an unknown source | 261,187 (175 MeshParts); 315,202 for 17221477333 | 38–49 decals; SurfaceAppearance unknown | **Present**: seats and red belts visible in three thumbnails | Already split into Roblox MeshParts | High (SVJ) | `rbx_18362571957_svj_2021/thumb.png`, `rbx_12713929163_svj63_2021/thumb.png`, `rbx_17221477333_svj_2021/thumb.png` |

**Why this order.**
- **#1 over #2–#4:** it is the owner's car, stock, with a full cabin. It is already near the Roblox
  budget, so the 2.5–7× decimation the others need (and the detail it costs) is avoided. It loses on
  texture resolution, and only there.
- **#2 over #3:** the AnatolianStudios image is a real-time capture, which predicts how the car
  looks in an engine better than #3's offline render. It also has 4× the texture resolution of #1.
  But #3's interior is the only one I actually saw from inside, and #3 has a proportion gate:
  4.376 m long against 4,947 mm for the real car (pass 1, section 3.1). Measure it before use.
- **#4:** the cleanest non-Lamborghini with a real interior and the best-documented car for the
  simulation. It is not the SVJ look.
- **#5:** the most convenient (already in Roblox, already split), but the lowest confidence on
  quality. Thumbnails render flat. The 41–65 scripts in each copy must all be deleted before use
  (backdoor risk). I could not preview its hierarchy: `preview_asset` needs "Allow Loading Third
  Party Assets" switched on in the place's settings, and I did not touch the place.

---

## 3. Close but not in the top 5

| Model | Licence / provenance | Why it is not higher |
|---|---|---|
| [Lamborghini Aventador LP750-4 SV](https://sketchfab.com/3d-models/fec3fec276d240f6b8a660e2a7874435), Haris3D | CC BY label; Forza Horizon 4 + CSR2 textures | Author: "complete Interior but without a complete engine"; 203,479 tris, 1024 px. The SV, not the SVJ (different bumpers, intakes, wing). Best fallback if #1's 512 px textures are a dealbreaker; worth comparing side by side. |
| [2019 Aventador SVJ 63](https://sketchfab.com/3d-models/89258ec08a6c4e9dbc4194cf71c0aa08), [SVJ 63 Roadster](https://sketchfab.com/3d-models/3a1191226c534574bf00f491d0deea0d), ddiaz-design | CSR2 extracts | Same mesh family as #1; the 63 livery and a Roadster. |
| [2020 Aventador SVJ Roadster](https://sketchfab.com/3d-models/2e4e4865188748058634b0e881aa5c68), ddiaz-design | Need for Speed (mobile) extract | 109,524 tris, packed `ARM` textures, `TEX_Details_INT_ARM` interior set. Roadster, half the geometry of #1. |
| [Aventador SVJ SDC (FREE)](https://sketchfab.com/3d-models/784e4656aca649cca55d6b18740a19b2), Lambo_SC04 | CC BY | Stock-looking SVJ, 508k tris. Interior probable (tag `interior`; source file is the "LAMBORGHINI CENTENARIO INTERIOR SDC" file; leather/plastic/fabric textures) but **no UVs**: the author says "I didn't unfold this model to be able to texture it". |
| SDC SVJ family: [Black-Ghost](https://sketchfab.com/3d-models/412e5ba4c1264a4fab97660ebc0695a4) (BY-NC), [SC20 Carbon](https://sketchfab.com/3d-models/7c2ec7bcd5a94dc8a482b6a5773b5260) (BY-NC), [Katana](https://sketchfab.com/3d-models/3a180dd964ae47ff91f65011a4b9b7f7) (BY), [Infinity](https://sketchfab.com/3d-models/2b46e077b12b41cd96b6c57f8f54be89) (BY), [SC20 Edition](https://sketchfab.com/3d-models/f5200e2c564a4ebab12c7e0f606a1303) (BY-NC-ND) | SDC's own work | Beautiful exteriors (sheets `01`, `02`), but custom bodies (wide-body, SC20 speedster, liveries), not a stock SVJ. **Probably no cabin:** blackcube4 had to graft an interior onto Black-Ghost, and z1Rome's Blend Swap re-upload calls the file "gutted". |
| [Aventador with Interior](https://sketchfab.com/3d-models/36eb1fa54a0d4be695d4cd90c30f4ff1), blackcube4 | CC BY label on an NC exterior; interior source now 404 | Black-Ghost wide-body plus a grafted interior (`interior.png`, `display.png`); 803k tris, 1024 px. Wide-body, not stock. |
| [( FREE ) Aventador LP 700-4](https://sketchfab.com/3d-models/df69d51ba10146f79c8c765810ca2132), Lambo_SC04 | CC BY | "interior and motor", doors modelled open (image shows seats); 1.45M tris, **no textures**. |
| [LamborghiniAdventador2012](https://www.blendkit.com/api/v1/assets/0222f91f-9902-4aa9-9a6b-1581cc441a07/), Reza Yousefi | Blendkit RF; probable Forza extract (no modifiers, `Material.0xx` names, Forza-style catalogue names such as "Caterham Seven 620r 2013") | Full interior **seen** in its render (wheel, cluster, console, orange seats); 345k faces, 134 objects, but 0 image textures. An LP700-4. |
| [Lamborghini Aventador Svj](https://sketchfab.com/3d-models/075ec66fbbaf436a918bf45f23345725), Pasha. | Sketchfab "Free Standard" | Body reads as an LP750-4 SV ("SV" side badge); 529k tris, 1024 px, a `Painel` (dashboard) texture, cabin visible. |
| [Aventador SVJ](https://sketchfab.com/3d-models/6d30b5df8de14d90a3266fb5680679a7), niev | `Meshpart53_diff.png`-style names: an engine export | Stock SVJ front with a visible cabin, but a poor capture, 1024 px textures and no description. |
| [SVJ Carbonado Mansory](https://sketchfab.com/3d-models/d0da3ea7aa76469ca623ada132e72719), VTX_car | NC-SA; 155 textures named `Image_18_24.png`, a texture-dump pattern | Mansory body kit, not stock; capture too small to judge. |
| Porsche 911 992, Kentik ([Blendkit](https://www.blendkit.com/api/v1/assets/f2a3cbf2-224c-402b-9528-0f2e88c9a31c/)); McLaren 720S Spider, Kentik; Audi R8 2023, AmJViZ; Lamborghini Auro PL, P-L Baril | Blendkit RF, authored | Good authored cars (the 992's author: "Well designed interior"), images in `bk_*`. None beats #2–#4 on what I could see. The Auro is fictional, so it has no real data for the simulation. |
| [Real Racing 3 SVJ](https://sketchfab.com/3d-models/a69609425ed14c9aabf433ccb6ea8298), outpiston | RR3 extract | 44,384 tris, no interior textures. Too low. |

Re-included rips that turned out weak, so the owner knows they were looked at: the Asphalt 8/9
Aventadors (≈30k tris), the CSR2 Ultimae (ddiaz, 75 textures at 512 px), the CSR2 SVJ Roadster
from GameModels_ru (raptorgamingyt00, 129 textures, a tiny capture), shadowvox's CSR2 BMW M8,
MdMahib's Forza Chiron, mixmamo's Forza 600LT, VTX_car's GTA V-style Fenomeno
(`script_rt_dials_race`), and BlackSnow02's Assetto-Corsa-style Huracan (`.dds`, Italian material
names). All are real cars with interiors, none is an SVJ, and none looked better than #2.

---

## 4. The trade-off: the SVJ look against the best model

- **The SVJ look wins on the things the project is built on.** The physics data and the look
  reference are both the SVJ, and #1 needs the least decimation. The cost is 512 px textures, a
  mobile-grade cabin (good shapes, soft surfaces) and roughly 10–15 interior texture sets to
  repaint or upscale if the cockpit camera shows the softness.
- **The best-looking model is a Revuelto (#2 or #3).** It has better textures and more realistic
  materials, and #3's cockpit is the only one I saw rendered from inside. Choosing it means
  switching the simulation to the Revuelto: a hybrid V12 with an 8-speed DCT and front e-axle
  torque vectoring, with less public gear and motor data than the SVJ. It also means
  decimating by about 2.5× (#2) or picking subsurf levels (#3).
- **Middle path, if #1's cabin disappoints in Studio:** keep the SVJ exterior from #1 and
  re-texture its interior at 1024 px. The geometry is the expensive part, and it is already there.
  Haris3D's LP750-4 SV (1024 px, "complete Interior") is the second opinion to compare it against.

---

## 5. What was searched

| Source | What I did | Candidates examined |
|---|---|---|
| **Sketchfab** (public API) | 409 search queries: 55 terms × licence filters (`by`, `cc0`, `by-sa`, `by-nc`, `by-nc-sa`, plus none for the SVJ terms) × sorts (likes, views, relevance), 3–10 pages each, paginated with `next`. Merged and de-duplicated locally, so nothing was cut off at ~20 results as in pass 1. | **4,302 unique models** (11,448 result rows); 3,753 cars; 821 mention an interior; **52 deep-checked** (full record, comments, texture names, thumbnail and description images). Rip flags from game names in the text and from identical face/vertex counts across uploaders. |
| **Blendkit** (public API) | 25 queries, free models only, every page. | **1,291 free models**; 235 in car categories; 15 read in full; 11 thumbnails saved. All downloads need a free account (`canDownloadError` is true when signed out). |
| **Roblox Creator Store** (Studio MCP, read-only) | 8 searches (Aventador SVJ, Lamborghini, Lamborghini Aventador interior, realistic car interior, A-Chassis Lamborghini, supercar interior (0 results), SVJ interior, MeshPart "Aventador"). | About 240 results listed, **13 asset details**, 8 thumbnails. Every car is an A-Chassis import with 16–93 scripts. "Premium LAMBORGHINI AVENTADOR" and "(HQ Import) Bugatti Veyron" cost $2.99, so they are not free. |
| **Blend Swap** | `keyword=` search (the `keywords=` parameter pass 1 used is ignored by the site), 8 terms, plus 28 detail pages. | About 130 listed. The best cars are 2012–2016 hobby models: Papa_Dragon's Aventador (CC-BY-NC-SA, staff pick, 6,157 downloads), pranavjit's Aventador (CC-BY, "tried to replicate the interiors"), Neubi's Gallardo + Interior (CC-BY-SA). Not competitive with the top 5. |
| **CGTrader** | Direct GETs answer HTTP 202 with an empty body (bot challenge), and the internal API 404s. | One free Revuelto found through web search (the same model as #2). **Listings otherwise not checked.** |
| **TurboSquid, Free3D, itch.io, ArtStation** | Direct GETs and WebFetch. | **HTTP 403** (Cloudflare) on all four. Not checked. |
| **OpenGameArt** | 4 searches. | Only low-poly; a CC0 "Ultimate 3D Car Assets Pack (w Interiors)" of 20 stylised cars. |
| **open3dmodel.com** | 1 listing page. | A rip host ("Forza Horizon Lamborghini Huracan…"); nothing beats the Sketchfab copies. |
| GitHub, Poly Haven, Khronos | 1 web search (GitHub); Poly Haven and Khronos are covered in pass 1. | Nothing new beyond Khronos Car Concept. |
| **Not checked** | Polycam, Smithsonian, more itch.io/GitHub searches. | The session's shared web-search budget ran out after 6 searches. |

**Limits on these claims.**
- "Not found" means not in the results listed above.
- The interior verdicts are inferences from images and texture names; nobody has looked inside a
  model in a 3D viewer.
- Texture resolution is the maximum in Sketchfab's converted archive.
- Real-car documentation levels are from my own knowledge, not checked this session.
- The CSR2/Forza/NFS attributions come from the authors' own words where quoted; otherwise from
  naming patterns, which suggests a source but does not prove it.

**Next step.** The owner downloads #1 (glTF) and, for comparison, #2 or #3 and Haris3D's SV.
I then open them in Blender and check, before any Studio work: interior completeness against the
brief's list, separate doors, calipers, wheels, steering wheel and wipers, real-world scale, and
how soft the 512 px cabin textures look.
