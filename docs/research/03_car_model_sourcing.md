# 03: Car model sourcing, Roblox import limits and import plan

Researched 2026-10-27, by web search and fetch only: no browser, no login, nothing downloaded.
Sources: the public Sketchfab Data API (`api.sketchfab.com/v3/search` and `/v3/models/<uid>`),
the public Blendkit API (`blendkit.com/api/v1/...`; BlenderKit renamed itself "Blendkit (formerly
BlenderKit)", and `blenderkit.com` now 301-redirects there), GitHub, and create.roblox.com docs.

**What this note can and cannot claim.** I read each model's metadata, its description and some
of its comments. I could not look at any images or 3D viewer, and I opened no files. So "has an
interior" means that the author says so or that the material names show one. Polycounts are the
platform's own numbers. Part separation, UV quality and scale are unverified until someone opens
the file in Blender, and every "not found" is limited to the queries listed in section 7.

---

## 1. Bottom line

1. **I found no free Aventador SVJ that has a full interior and a licence you can trust.** Every
   SVJ hit falls into one of these cases:
   - a ripped game model, which the author admits: CSR2, Need for Speed Mobile or Real Racing 3;
   - a re-upload of one of those, shown by identical face and vertex counts;
   - a non-commercial (NC) licence;
   - a licence chain that breaks: blackcube4's "Aventador with Interior" is labelled CC-BY, but it
     is built on an exterior that is now CC-BY-NC and an interior whose source page returns 404;
   - no interior and no UV unwrap: the author of the one clean CC-BY SVJ says he "didn't unfold
     this model to be able to texture it".

   The paid SVJ models on RenderHub are also "Editorial Use Only", so even paying does not give
   the right to use them in a game. See section 4.
2. **Pick A, for the private Drive lab: Blendkit "Lamborghini Revuelto" by AmJViZ (Amir Jafari).**
   - Royalty-free and free.
   - The author says it has a "fully detailed exterior and interior".
   - 79,950 base faces (477,053 with modifiers), 130 objects, 34 textures from 1.5K to 4K, and a
     .glb exists.
   - It is the SVJ's direct successor, Lamborghini's V12 flagship.
   - **Gate:** its bounding box is 4.376 m long, but the real car is 4.947 m. The width matches
     (2.020 m against 2.033 m), so the proportions may be wrong. Measure the model before
     committing to it.
3. **Pick B, if the car will ever ship in a published game: Blendkit "Lamborghini Auro PL" by
   Pierre-Louis Baril.**
   - The author's own concept design. He writes: "you can simply remove the logos and use it as
     an unbranded vehicle".
   - 862,922 base faces, 521 objects, 26 textures up to 4K.
   - Its 71 materials include `seat`, `steering`, `Suede`, `Leather Shader` and `Calipers`.
   - Quality 8.84 from 25 ratings.
   - Of all the realistic options it carries the lowest trademark risk. The catch is heavy
     decimation work.
4. **Either way, the visual car will not be an SVJ unless we build or commission one.** If the
   body changes, `02_aventador_svj_data.md` and the cockpit references must follow the chosen car.
   Otherwise the physics and the visuals describe two different cars, and that is the owner's
   call. The brief itself warns against substituting another variant's cockpit.
5. **What Roblox enforces:**
   - each mesh is limited to 20,000 triangles;
   - one material per mesh;
   - one UV set, inside 0–1;
   - PBR maps are separate files (the RGB colour map, the RGB OpenGL tangent-space normal map,
     then roughness, metalness and emissive as single-channel grayscale);
   - SurfaceAppearance texture maps are capped at 1024² (the docs also mention 4096² for
     textures in general; see section 5).

   At runtime, scripts can change the paint tint (`SurfaceAppearance.Color`) and the emissive
   strength and tint, but not the maps or the `MeshId`. Section 5 has the details.
6. **Licence hygiene for a Royalty-Free (Blendkit) asset:** turn on Roblox **Asset Privacy**
   *before* uploading. Meshes are "Open Use" by default, and the setting is not retroactive.
   Never put the asset on the Creator Store. That is how we meet Blendkit's condition that assets
   "shouldn't be directly extractable".

---

## 2. Ranked shortlist

Two kinds of risk appear below. **Provenance** is whether the uploader really owns what they
licensed. **Brand** is trademark and design-right exposure in a *published* game. Cleanup is
judged for reaching the Roblox budget in section 6.

| # | Model | Author | Licence (exact) | Formats | Faces / verts | Textures | Interior (evidence) | Provenance | Brand | Cleanup |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | [Lamborghini Revuelto 3d model car](https://www.blendkit.com/asset-gallery-detail/4146135b-e6e7-45f5-b81b-372d4bbb74e8/) | AmJViZ (Amir Jafari) | Blendkit **Royalty Free**, free | .blend (0.5K/1K/2K/4K variants, ~460 MB full), .glb ~10.8 MB, Godot .glb | 79,950 base / 477,053 render (mirror, subsurf and bevel modifiers) | 34 maps, 1536–4096 px | Author: "fully detailed exterior and interior"; materials `Leather Black`, `velour_velvet`, `Leather Right Screen`, `Windows Left Screen` | Low (original upload, 2026-03-20, author has a public ArtStation) | High (real Lamborghini) | Medium |
| 2 | [Lamborghini Auro PL](https://www.blendkit.com/asset-gallery-detail/373dddbb-0608-49db-8fdf-3e725fb32df1/) | Pierre-Louis Baril | Blendkit **Royalty Free**, free | .blend only (0.5K–4K variants); no glTF | 862,922 base / 12,723,125 render | 26 maps, up to 4096 px; PBR metallic; some procedural shaders | Materials `seat`, `steering` (×3), `Suede`, `Leather Shader`, `inside mesh`, `Emissive`, `DRL Emission`, `Calipers` | Low (his own design) | **Low** once the logos go; the design borrows Lamborghini cues | High |
| 3 | [Porsche 911 with interior](https://sketchfab.com/3d-models/877b1bc1739f4a2bb65d62fd7ffd9f75) | n.brizitskaya | **CC Attribution** (CC BY 4.0) | Sketchfab auto glTF/GLB/USDZ + source | 424,043 / 252,648 | 48 maps, ≤2048 px, metalness PBR | "Porsche 911 Turbo S with detailed interior" | Low–medium (no source stated) | High (Porsche) | Medium–high: a 2026-07-18 comment says "many parts are grouped into a single mesh" |
| 4 | [Khronos Car Concept](https://github.com/KhronosGroup/glTF-Sample-Assets/tree/main/Models/CarConcept) | Eric Chadwick; © 2024 Darmstadt Graphics Group | **CC BY 4.0** (Khronos logos under separate trademark terms) | glTF in PNG/JPG/WebP/KTX2 variants, ~10–12 MB | Not published | Small shared set, baked AO | Interior materials `Interior 1–3`, `Floormat`, `Dashboard`, emissive `Dash_E`; door hierarchies made to open | Low (optimised from a public-domain model by "Unity Fan") | Low (concept; strip the Khronos logos) | Low, but a lower realism ceiling: stylised concept |
| 5 | [Lamborghini Centenario LP-770 Interior SDC](https://sketchfab.com/3d-models/lamborghini-centenario-lp-770-interior-sdc-d679af35b5694301a185c7454a700c73) | Lambo_SC04 (SDC PERFORMANCE) | **CC Attribution** | Sketchfab auto glTF/GLB/USDZ | 325,735 / 181,575 | 7 maps @4096 (tiled carbon) | Yes; author: interior "may differ from the real" car; 1 animation | **Medium–high** (see 3.5) | High | High |
| 6 | [( FREE ) Lamborghini Aventador LP 700-4](https://sketchfab.com/3d-models/df69d51ba10146f79c8c765810ca2132) | Lambo_SC04 | **CC Attribution** | Sketchfab auto glTF/GLB/USDZ | 1,452,574 / 748,330 | **0 textures** (35 materials) | "interior and motor" | **Medium–high** (see 3.5) | High | Very high (likely no UVs; a full bake job) |

Honourable mentions, each with a reason it is not in the top six:

| Model | Licence | Why not higher |
|---|---|---|
| [FREE 1975 Porsche 911 (930) Turbo](https://sketchfab.com/3d-models/free-1975-porsche-911-930-turbo-8568d9d14a994b9cae59499f0dbed21e), Lionsharp Studios | CC Attribution | Strong pedigree: 7,261 likes, 270,841 downloads, "Game-ready high quality asset (200k triangles) + ClearCoat (40k)", Substance textures. **But the text never mentions an interior**, and it is a 1975 car. Check the viewer before ruling it in. The author notes "copyrights to the vehicle design belong to Porsche AG". |
| [FREE // Honda E (Detailed Interior) 2021](https://sketchfab.com/3d-models/814cf3f8cfd64594b1c4f96e873c3cef), Xlay3D (Alex Murias) | CC Attribution | Modelled from photos with a detailed interior, 2,186,812 faces, 39 textures. It is a city EV, not a sports car. |
| [Generic Sportscar PL](https://www.blendkit.com/api/v1/assets/506c9a94-762b-4e09-b866-17216bc439b4/), Pierre-Louis Baril | Blendkit Royalty Free, free | "not based on any existing brand"; 523,639 faces, textures up to 8K. The interior is only "basic". |
| [Ferrari 812 Super Fast GT3](https://sketchfab.com/3d-models/8fce17080c2142b5910c09d7e180bd1e), toddeppe | CC Attribution | 2,146,632 faces, "Real world scale (Metric / Centimeters)", 7 material sets including Inside and Interior. It is a racing concept, so the interior is probably a race shell, which the brief rejects ("ne pas inventer un intérieur de course générique"). |
| [Saba V12 '95](https://sketchfab.com/3d-models/3ab977050c334c13b6abb5de078b4957), Daniel Zhabotinsky | CC Attribution, plus the author's note "I unconditionally give you permission to use this model ... implement it into a digital product" | A fictional design with engine and interior, but low-poly (24,552 faces). Zero brand risk, far from "most realistic". |
| [Aventador](https://sketchfab.com/3d-models/b07aa40cfa734421a03045f675288a14), sebastian33 (2017) | CC Attribution | "complete model ... with a complete interior", 183,309 faces, 0 textures, origin unknown. Only worth a look if the owner insists on an Aventador shape. |

---

## 3. Notes per candidate

### 3.1 Blendkit "Lamborghini Revuelto" (pick A)
- Pages: [gallery](https://www.blendkit.com/asset-gallery-detail/4146135b-e6e7-45f5-b81b-372d4bbb74e8/),
  [API record](https://www.blendkit.com/api/v1/assets/f6fd9293-241e-4c15-88a8-9185d6a85a3e/).
  Created and published 2026-03-20. Blender 4.5.6, Cycles, Principled shader.
- Geometry:
  - 79,950 faces as modelled and 477,053 with the mirror, subsurf and bevel modifiers applied;
  - 130 objects and 221 nodes;
  - quad-dominant, with `manifold: false` (normal for car panels);
  - UVs present.
- Textures: 34 maps from 1536 to 4096 px. File variants are offered at 0.5K, 1K, 2K and 4K, which
  helps, since Roblox wants 1024.
- Interior: the author says "fully detailed". The material names (one space-separated string, cut
  off at the end) show black and white interior trim, leather, velour, and left/right screen
  materials, which fits the Revuelto's cockpit screens. **Not confirmed:** steering wheel, paddles,
  pedals, door cards, headliner and vents. Inventory them against the brief's list (section 6,
  step 0).
- Separation: 130 objects suggests the parts are split. Whether the wheels, calipers, doors and
  steering wheel are separate objects is **unverified**.
- **Scale and proportion gate:** the bounding box is X 2.0203 × Y 4.3764 × Z 1.0938 (Blender
  units, presumably metres). The real Revuelto
  ([Wikipedia](https://en.wikipedia.org/wiki/Lamborghini_Revuelto)) is 4,947 mm long, 2,033 mm
  wide without mirrors and 1,160 mm high, with a 2,779 mm wheelbase.
  - Width matches within 0.6%.
  - Length is 11.5% short and height 5.7% short.
  - A uniform scale error would move all three dimensions together. These do not, so the body may
    be compressed lengthwise.
  - **Measure the wheelbase in Blender first. If it is more than about 3% off, drop to pick B.**
- Quality signals: quality 9.25 from **only 4 ratings** (median 10); "working hours" 65 from
  3 ratings; 280 bookmarks.
- Cleanup: medium.
  - Choose the subsurf level per part.
  - Bake the procedural or high-res detail.
  - Split by material.
  - Bring every part under 18k triangles (section 6).
- Download: the page shows "Get this model" next to Log In and Register. I did not verify whether
  an account is needed; Blendkit downloads normally go through an account and the Blender add-on.

### 3.2 Blendkit "Lamborghini Auro PL" (pick B)
- Pages: [gallery](https://www.blendkit.com/asset-gallery-detail/373dddbb-0608-49db-8fdf-3e725fb32df1/),
  [API record](https://www.blendkit.com/api/v1/assets/07898b63-4a91-4495-b87c-8882b2301608/).
  Published 2022-08-11.
- Author: "Ultra high quality car model designed by me ... Design cues taken from various existing
  Lamborghini models ... Being a concept, this means you can simply remove the logos and use it as
  an unbranded vehicle." His profile reads "Blender specialist at Kia Europe".
- Geometry:
  - 862,922 faces as modelled and **12.7M** with modifiers (bevel, subsurf, mirror, solidify,
    shrinkwrap, lattice, array, decimate);
  - 521 objects and 1,212 nodes;
  - bounding box 2.038 × 4.649 × 1.182 m, believable supercar proportions.
- Materials (71), the ones that matter:
  - `seat`, `steering`, `steering.001`, `steering.002`, `Suede`, `Leather Shader.001`,
    `inside mesh`;
  - `Calipers.001`, `Rim`, `Rim paint`, `Tires.002`;
  - `Emissive`, `DRL Emission material PL`, `Taillight glass`, `Polarized glass`;
  - `Carbon Fiber Procedural`, which is procedural and must be baked;
  - **`lamborghini_PNG10709`, a Lamborghini logo image, which must be removed**, together with the
    badges and the licence plate.
- Interior completeness is **unverified**. The material list shows seats, steering and suede trim,
  but not a dashboard, pedals or door cards by name.
- Files: .blend only, 99 MB, plus texture-resolution variants. No glTF.
- Quality: 8.84 from **25 ratings** (median 10), 50 working hours, 1,283 bookmarks. This is the
  better-attested quality score of the two picks.
- Cleanup: high. At 862k base faces and 521 objects it needs decimation and part merging, and the
  procedural shaders need baking.

### 3.3 Sketchfab "Porsche 911 with interior" (n.brizitskaya)
- [API record](https://api.sketchfab.com/v3/models/877b1bc1739f4a2bb65d62fd7ffd9f75).
  Published 2024-06-06, updated 2024-08-03. 674 likes, 21,807 downloads.
- 424,043 faces, 37 materials, 48 textures, metalness PBR. The description reads in full:
  "Porsche 911 Turbo S with detailed interior".
- Comments: on 2026-07-18 a user reports that textures do not come through in Unreal and that
  "many parts are grouped into a single mesh", so expect to separate parts by hand. A 2024-11-26
  question "can i use this in my game?" got no answer that I saw.
- CC BY 4.0: credit is required and commercial use is allowed. Porsche's trademarks are not
  licensed (section 4).

### 3.4 Khronos "Car Concept"
- [README](https://github.com/KhronosGroup/glTF-Sample-Assets/blob/main/Models/CarConcept/README.md).
  CC BY 4.0, © 2024 Darmstadt Graphics Group GmbH; model and textures credited to Eric Chadwick.
  It started from a "public domain 3D model created by Unity Fan".
- Built to "showcase the potential for high graphical quality in glTF while maintaining a small
  download size".
  - Wheels were cut from 10,260 to 324 vertices, with a tiled tread normal map.
  - Parts under 3 cm were culled.
  - The meshes are "linked together into hierarchies" so that "a car door [can] be opened, and the
    associated parts will move along with it".
- It uses `KHR_materials_clearcoat`, `transmission`, `iridescence`, `emissive_strength` and
  `variants`. **Roblox has no equivalent for these**, so the paint, glass and iridescence must be
  re-authored with the 5 Roblox maps.
- Use it as the **pipeline test asset**: small, licensed cleanly, already organised for real time.
  It is not the final car.

### 3.5 Lambo_SC04 / SDC PERFORMANCE models (Centenario Interior, Aventador LP 700-4, SVJ SDC)
- The CC-BY labels are on the uploader's own account and nothing in these three descriptions
  credits a game. **However, the same catalogue includes:**
  - two Asphalt 9 titles, one of them described as the Terzo Millennio "as it appears in
    Asphalt 9", with links to the game;
  - a Terzo Millennio whose interior is credited to another author (0xo);
  - Revuelto models built on Sloftm_Carz's base model.

  This uploader also uses the NC licence on many works. None of this proves a rip; it means the
  account mixes its own work with work from other sources. So the risk on any SDC model is
  "medium–high": not shown to be a rip, but not clean either.
- Centenario
  ([API](https://api.sketchfab.com/v3/models/d679af35b5694301a185c7454a700c73)): 44 materials,
  7 textures, 1 animation, 31,621 downloads. Comments mention the "carbon texture is way too
  large", which points to tiled carbon and possibly no proper UVs. Another comment says "He sells
  your work for 115$", about a reseller.
- Aventador LP 700-4
  ([API](https://api.sketchfab.com/v3/models/df69d51ba10146f79c8c765810ca2132)): 1.45M faces,
  **0 textures**, "interior and motor". It is the closest free mesh to the SVJ that has an
  interior, but it is an LP 700-4: the SVJ's aero differs.
- Aventador SVJ SDC FREE
  ([API](https://api.sketchfab.com/v3/models/784e4656aca649cca55d6b18740a19b2)): CC BY, 508k
  faces, 1 texture. The interior shows only as a tag. **The author, in the comments on
  2021-09-19: "I didn't unfold this model to be able to texture it, I just put a carbon
  texture".** No UVs means no PBR without a full unwrap.

---

## 4. Licence, provenance and trademark analysis

### 4.1 Licences found and what each allows for a Roblox experience

| Licence | Game use in Roblox? | Conditions |
|---|---|---|
| CC0 | Yes | None. The shortlist has no realistic CC0 car: Sketchfab's CC0 + "car interior" query returned Smithsonian space hardware and a coffee-can amplifier, and CC0 + "car" in the cars-and-vehicles category returned a steam-yacht point cloud and a catalytic converter. |
| **CC BY 4.0** (Sketchfab "CC Attribution", Khronos) | Yes, including monetised | Credit as [§3(a)(1)](https://creativecommons.org/licenses/by/4.0/legalcode.en) requires: creator, copyright notice, licence notice, disclaimer notice, link to the material, and a note that it was modified. In Roblox: an in-game Credits panel plus the experience description. §2(a)(5)(B) bars adding terms or technical measures that restrict others' licensed rights. Uploading to Roblox does not make the asset ours. |
| CC BY-SA | Yes, with a catch | The modified mesh must stay CC BY-SA, so anyone may reuse our cleaned version. Workable, but avoid it for the hero car. |
| **CC BY-NC / BY-NC-SA** | **No** for a published experience | A Roblox experience that can earn Robux (passes, products, Premium payouts) is commercial use. Acceptable only in a private test place that never ships, and then the asset must still be replaced before anything goes public. |
| CC BY-ND / BY-NC-ND | No | Decimating and splitting the mesh is a derivative work. |
| Blendkit Royalty Free | Yes | The [FAQ](https://www.blendkit.com/docs/licenses/licensing-faq/): "Can I sell games made with Blendkit models?", "Yes, if these can't be extracted by the users in an easy way"; also "the assets shouldn't be directly extractable in the distribution". No resale "in the same form" ([licences](https://www.blendkit.com/docs/licenses/)). In Roblox, turn on Asset Privacy before the upload and never publish to the Creator Store (section 5.9). |
| TurboSquid free | No | "Available for non-commercial use under specific terms"; "Free model licenses cannot be upgraded to commercial licenses" ([help article](https://www.turbosquid.com/help/en/articles/14829413-what-are-the-limitations-and-upgrade-policies-for-3d-model-licenses-on-turbosquid)). |
| Editorial (TurboSquid, RenderHub; CGTrader not checked) | **No** | "Editorial Use models cannot be upgraded to allow Game Use or other commercial purposes"; for branded models the restriction "cannot be changed or removed" (same article). The paid RenderHub Aventador and SVJ listings carry an "Editorial Use Only Restriction". |
| TurboSquid Royalty Free (paid) | Only with protections | Games are allowed if the model "cannot be extracted or decompiled without reverse engineering" and players cannot import or export 3D files ([RF FAQ](https://www.turbosquid.com/help/en/articles/9937423-royalty-free-license-faq)). Vehicle logos and designs need separate clearance. |
| Sketchfab "NoAI" tag | Not relevant to import | It bars use "in datasets for, in the development of, or as inputs to generative AI programs" ([Sketchfab blog](https://sketchfab.com/blogs/community/introducing-the-noai-createdwithai-tags/)). None of the shortlisted tag lists returned by the API include it. Do not feed a NoAI asset into an AI remesh or texture service. |

### 4.2 Provenance: a Sketchfab licence label is only the uploader's claim
A model ripped from a game and relabelled CC-BY grants no rights; the uploader had none to give.
Three tests caught most of the bad ones:
1. what the description admits;
2. **identical face and vertex counts across different uploaders**: geometry is rarely identical
   by accident;
3. the comments.

Excluded with evidence (all are Sketchfab
[API](https://api.sketchfab.com/v3/search?type=models&q=aventador%20svj&downloadable=true&count=24)
search results):

| Model | Uploader | Labelled licence | Why excluded |
|---|---|---|---|
| 2019 Lamborghini Aventador SVJ / SVJ 63 / SVJ 63 Roadster | ddiaz-design | CC Attribution | The descriptions say "based on a CSR2 model"; the 2020 SVJ Roadster is based on a Need for Speed Mobile model. |
| Lamborghini Aventador (`e328d9f5…`) | Outlaw_Games | CC BY-NC | **211,767 faces / 136,828 verts**, identical to ddiaz-design's CSR2-based 2019 SVJ, so the same mesh. |
| 2019 Lamborghini Aventador SVJ (`a6960942…`) | outpiston | CC BY-NC-SA | "Game-based model sourced from Real Racing 3". |
| Lamborghini Aventador with Interior (`36eb1fa5…`) | blackcube4 | CC Attribution | Its description credits the exterior to "Aventador SVJ Black Ghost" ([`412e5ba4…`](https://api.sketchfab.com/v3/models/412e5ba4c1264a4fab97660ebc0695a4)), which is now **CC BY-NC**. Its interior source ([`5933b82a…`](https://api.sketchfab.com/v3/models/5933b82a092c4d6e82696bd380ada8c5)) now returns **404**. The uploader writes that the two "high-detail" source models "are not their own". |
| Lamborghini Aventador (`2263b498…`) | blackcube4 | CC Attribution | A "cleaned-up, retextured version" of the same NC Black Ghost. |
| Lamborghini with interior (`03d8012c…`) | LDawesome | CC Attribution | 803,785 faces, the same as blackcube4's composite. |
| Lamborghini Aventador LP750-4 SV (`46042571…`), Lamborghini Aventador with interior (`6c11d507…`) | ChoochooLi-sketchfab, Dan_man5000 | CC Attribution | **203,463 or 203,479 faces / 124,076 verts**, the same as Haris3D's SV. The ChoochooLi upload says its textures come "from Forza Horizon 4 and CSR 2". |
| 2019 Corvette C8, 2017 Aston Martin DB11, LP750-4 SV | Haris3D | CC Attribution | The C8 "credits Forza Horizon 4 creators; textures from FH4 and Project CARS 3". Same uploader, same style, so treat the whole catalogue as sourced from games. |
| "Lamborghini Aventador SVJ: The Apex Predator" (`c72c5d11…`) | alihassan23042009 | CC Attribution | 708,976 faces, against 708,977 for SDC's CC BY-NC "SC20 Carbon Edition". Probably a relabelled re-upload, not proven. |
| Lamborghini Terzo Millennio (`70f0b932…`) | ChoochooLi-sketchfab | CC Attribution | 108,327 faces / 63,631 verts, the same as SDC's CC BY-NC Terzo Millennio. |
| Porsche 911 turbo 930 Johnny Silverhand's, Porsche Taycan (Project Cars 3), 2022 Toyota Vellfire | various | CC Attribution | Self-declared from Cyberpunk 2077, from Project CARS 3 via 3DSimED, and from a GTA San Andreas mod. |
| Every SDC model labelled NC, the VTX_car SVJ Carbonado Mansory, the 992 GT3 RS, the SF90 XX | Lambo_SC04, VTX_car | CC BY-NC / BY-NC-SA | Non-commercial. |

Mod communities: a BeamNG QA member says that every part of an uploaded mesh "would have to be
modelled by yourself/from BeamNG/used with full permission of the original author", and that
trademarked names and designs are risky
([BeamNG docs: protecting mods](https://documentation.beamng.com/modding/programming/legal/)).
Assetto Corsa and BeamNG car mods are mostly ripped or carry no reuse licence, so they were not
pursued. That includes the Assetto Corsa SVJ in the owner's reference video. **Do not source from
them.**

### 4.3 Trademark and design rights, separate from the copyright licence
- **CC licences do not license trademarks.** CC BY 4.0 §2(b)(2): "Patent and trademark rights are
  not licensed under this Public License"
  ([legal code](https://creativecommons.org/licenses/by/4.0/legalcode.en)). The same holds for
  Royalty Free: TurboSquid's FAQ says a vehicle model "may include a real-world manufacturer's
  logo, trademark, or other protected IP", and that clearance is "solely" the buyer's
  responsibility.
- Brand exposure has three layers: (1) names and badges, (2) the car's shape, which can be
  protected as a registered design or trade dress, and (3) signature styling such as the
  Lamborghini Y-lights and hexagon motifs. Games that show real cars, like Gran Turismo or Forza,
  do so under licences from the makers. TurboSquid's FAQ says Ford and GM review each requested
  use and approve or deny it at their own discretion. Lionsharp's own page says "copyrights to
  the vehicle design belong to Porsche AG".
- **A private prototype differs from a published game.** A Roblox place that is unpublished or
  private, seen only by the owner, distributes nothing to the public, so the practical exposure is
  very low. **A published game, even a free one, is distribution.** A rights holder can file an IP
  complaint with Roblox, which can take the experience or the assets down, and moderation action
  can count against the owning account or group (274643456). I did not research Roblox's exact
  enforcement steps. Nothing here is legal advice.
- If it ships: (a) debadge (logos, wheel-centre caps, licence plate, steering-wheel bull);
  (b) rename (no "Lamborghini", "Aventador", "SVJ" or "Revuelto" in the UI or the asset names);
  (c) prefer pick B or another original design; (d) any real-car body needs an actual licence from
  the maker.

---

## 5. Roblox import constraints (docs read 2026-10-27)

### 5.1 Geometry
- **"Individual meshes can not exceed 20,000 triangles."**
  ([Modeling specifications](https://create.roblox.com/docs/art/modeling/specifications)). The
  same page says: quads where possible, no N-gons, no zero-thickness meshes, watertight geometry.
  Those rules target avatar items.
- The community still reports 20k in May 2026: a feature request posted 2026-05-23 asks for
  60k–200k and has no staff reply on its first page
  ([DevForum](https://devforum.roblox.com/t/increase-the-max-triangle-limit/4650221)). A 2023
  thread cites "21,000 tris" for the 3D Importer and 10,000 for batch import, again with no staff
  confirmation ([DevForum](https://devforum.roblox.com/t/importing-more-than-21k-tris/2586514)).
  **Plan for 20,000, aim at ≤18,000 per MeshPart.**
- No per-mesh vertex limit is documented on these pages. The EditableMesh limit of 60k vertices
  and 20k triangles is a different feature.
- "Mesh objects can only have one material assigned"
  ([Texture specifications](https://create.roblox.com/docs/art/modeling/texture-specifications)),
  so **split by material before export**.
- `MeshId` / `MeshContent` "cannot be changed directly by scripts, as the collision geometry of the
  mesh cannot be recomputed in real time"; `TextureID` can be changed
  ([MeshPart](https://create.roblox.com/docs/reference/engine/classes/MeshPart.md)). So a
  runtime LOD means toggling the visibility of prebuilt parts, not swapping meshes.

### 5.2 3D Importer
([3D Importer](https://create.roblox.com/docs/art/modeling/3d-importer))
- Formats: ".fbx, .gltf, or .obj". **.glb is not listed**, so convert in Blender to .gltf (with a
  separate .bin) or to FBX. FBX and glTF carry multiple meshes, hierarchies, PBR textures, rigs
  and animation.
- Settings that matter, with their defaults:
  - `Import Only As Model` (on); `Upload to Roblox` (on); `Add to Workspace` (on).
  - `Set Pivot to Scene Origin` (on); `Anchored` (off).
  - `World Forward` (Front), `World Up` (Top).
  - **`Scale Unit`** (Studs): "Sets what units the file was modeled in".
  - **`Merge Meshes`** (off): merges everything into ONE MeshPart. Keep it off.
  - `Invert Negative Faces` (off).
  - **`Use Imported Pivot`** (on): this is how Blender object origins become hinge pivots.
  - `Make Double Sided` (off, "more performance intensive").
  - `Ignore Vertex Colors` (off).
- The File Geometry panel shows "file dimensions and polycount", so check each part there.
- The page documents no triangle-limit warning. Meshes over the limit have been reported as
  rejected or as visibly simplified. Do not find out on the hero car.
- Blender FBX export, per
  [Export requirements](https://create.roblox.com/docs/art/modeling/export-requirements): Path Mode
  "Copy" with Embed Textures; Apply Scalings "FBX Unit Scale"; Add Leaf Bones off; Bake Animation
  off.

### 5.3 Units
- "1 stud" = "28 cm"; "1 RMU" = "21.952 kg"
  ([Units](https://create.roblox.com/docs/physics/units)). `04_roblox_engine_facts.md` owns
  units. The visual mesh's wheelbase and track must match the physics at the same scale; verify
  one known length in Studio after import.

### 5.4 Textures
([Texture specifications](https://create.roblox.com/docs/art/modeling/texture-specifications);
[GitHub source](https://github.com/Roblox/creator-docs/blob/main/content/en-us/art/modeling/texture-specifications.md))
- Upload formats: .png, .jpg, .tga, .bmp.
- The page contradicts itself:
  - "Roblox supports up to 4096×4096 pixel texture resolutions (4K)";
  - but also "Roblox supports up to 1024×1024 pixel spaces for texture maps", and the
    SurfaceAppearance sizing table says "1024×1024 (maximum)".

  **Author the SurfaceAppearance maps at 1024**, and treat 2048 for the body as an experiment.
- The engine "starts with lower quality versions of the texture and ramps up quality based on
  device resources".
- PBR maps are separate files, **not channel-packed**:
  - Albedo: RGB 24-bit.
  - Normal: RGB 24-bit, "OpenGL format - Tangent Space" only.
  - Roughness, Metalness, Emissive mask: single-channel grayscale, 8-bit each.
- UVs: "a single UV set", "within a 0:1 space", "Overlapping UVs are allowed". **Tiled carbon,
  leather or Alcantara cannot repeat outside 0–1.** Either bake the weave into the atlas, or test
  a `MaterialVariant` on those parts: the
  [Meshes](https://create.roblox.com/docs/parts/meshes) page says a MeshPart takes up to four PBR
  maps through SurfaceAppearance or MaterialVariant. How MaterialVariant tiles on a mesh is
  unverified, so test it.
  - **Contradicted by a measurement** (2026-10-30, Studio edit mode): UVs outside 0–1 do repeat on
    a MeshPart's SurfaceAppearance (research 10, section 3.1). The quote above is the import
    guidance, not the renderer's behaviour.
- Memory: "the number of pixels in the texture determines memory usage"; "Unless an image is
  occupying a large amount of physical space on the screen, it usually needs at most 512x512
  pixels" ([Improve performance](https://create.roblox.com/docs/performance-optimization/improve)).

### 5.5 SurfaceAppearance
([guide](https://create.roblox.com/docs/art/modeling/surface-appearance),
[class](https://create.roblox.com/docs/reference/engine/classes/SurfaceAppearance.md))
- Five maps: ColorMap, NormalMap, RoughnessMap, MetalnessMap, EmissiveMask (`EmissiveMaskContent`).
  Metalness workflow only.
- `AlphaMode`:
  - **Overlay** (the default) shows `MeshPart.Color` where the colour map is transparent.
  - **Transparency** cuts out transparent areas: hard edges at MeshPart.Transparency 0, soft
    edges at ≥0.02.
  - **TintMask** uses the alpha channel to control "how strongly SurfaceAppearance.Color tints".
  - **Opaque** (beta) ignores alpha.
- The normal map needs tangents: "imported meshes must include tangent information". Tick
  "Tangents" in the glTF export, or "Tangent Space" in the FBX export.
- "When Lighting.EnvironmentSpecularScale is 0, metalness has no effect." Roughness may need
  "roughly 0.1 added" because of Fresnel.
- **Changeable at runtime:**
  - **Can change:** `Color` (tint), `AlphaMode`, `EmissiveStrength`, `EmissiveTint` and
    `ResampleMode` carry no Plugin Security tag, so scripts can write them. Of these, only the tint
    is explicitly endorsed for real-time use: the guide says tinting can "programmatically modify
    your PBR surface colors in real-time". Test the emissive writes in Studio.
  - **Cannot change:** every `*Map` / `*Content` property (ColorMap, NormalMap, MetalnessMap,
    RoughnessMap, EmissiveMaskContent) is **Plugin Security**. The class page says "most
    SurfaceAppearance properties cannot be modified by scripts, as the necessary pre-processing is
    usually too expensive during runtime".
  - **Design consequence:** the paint colour is a runtime tint over a near-white colour map
    (TintMask); brake lights get brighter through `EmissiveStrength`.
- Emissive: `EmissiveStrength` above the dynamic range "will get clamped". **The guide describes
  emissive support for "3D accessories, layered clothing, and avatar bodies".** Prove it on a
  plain MeshPart in Studio before building the lights on it. Fallback: Neon light elements plus
  SurfaceLight or SpotLight.
- Instancing: parts batch together when "SurfaceAppearances are identical"; "reuse a single color
  map with different tints" to save memory.

### 5.6 Collision and physics flags
([Collisions](https://create.roblox.com/docs/workspace/collisions),
[Meshes](https://create.roblox.com/docs/parts/meshes),
[BasePart](https://create.roblox.com/docs/reference/engine/classes/BasePart.md))
- `CollisionFidelity`: Box, Hull, Default, **PreciseConvexDecomposition** (the most expensive,
  "still not a 1:1 representation"), and **Tunable**, which exposes `CollisionPrecision`.
- From the performance page:
  - for parts that don't need collisions, set "CanCollide, CanTouch and CanQuery to false";
  - **and** use Box or Hull "since the collision geometry is still stored in memory";
  - "It's generally safe to set any small anchored part's collision fidelity to Box".
- `Massless`: "the part will not contribute to the total mass or inertia of its assembly"; "Parts
  that are massless should never become an assembly root part unless all other parts in the
  assembly are also massless". `RootPriority` (−127..127) forces the root choice.

### 5.7 Level of detail
- `RenderFidelity = Automatic`: "Less than 250 studs | Highest; 250-500 studs | Medium; 500 or
  more studs | Lowest" ([MeshPart](https://create.roblox.com/docs/reference/engine/classes/MeshPart.md)).
  **The chase and cockpit cameras are always under 250 studs, so the automatic LOD never helps
  the car the player is driving.** Do not set Precise on many meshes (performance page).
- `Model.LevelOfDetail` (needs instance streaming): **StreamingMesh** is an imposter that "does not
  support textures"; **SLIM** "renders a composite of all child parts at progressively lower
  resolutions" ([Model](https://create.roblox.com/docs/reference/engine/classes/Model.md)). Use it
  for parked or distant cars, not the hero car.

### 5.8 Pivots and hinges
- Pivots: `BasePart.PivotOffset`, `Model.WorldPivot`, and `PrimaryPart` (which overrides the
  pivot) ([Pivot tools](https://create.roblox.com/docs/studio/pivot-tools)).
- `HingeConstraint` Servo: rotates to `TargetAngle` under `AngularSpeed` and `ServoMaxTorque`,
  with `LimitsEnabled`, `LowerAngle` and `UpperAngle`; the attachments' X axes align
  ([Hinge](https://create.roblox.com/docs/physics/constraints/hinge)).

### 5.9 Asset privacy, which is how we meet the Royalty Free terms
([Asset privacy](https://create.roblox.com/docs/projects/assets/privacy))
- "By default, Images, Decals, and Meshes are created as **Open Use**": any creator can load them.
- Turn on "Opt-in to restrict assets on creation" (Creator Dashboard → Settings → Advanced). For a
  group, it is "Allow restricted assets on creation" in the group settings, and **only the group
  owner** can change it.
- "The setting is not retroactive". MeshParts and Models are not covered; the underlying Mesh
  assets are.

---

## 6. Import plan for the top pick (Revuelto; applies to pick B as written)

No Studio work happens before the owner gives the go (plan rule in `00_PLAN.md`). The steps below
are the plan, not something already done.

### Step 0. Gates before any cleanup (the owner downloads; I measure)
1. Archive the asset page (date, licence, author) into `research_notes/Drive lab/credits/`, the
   start of the credits file.
2. **Proportions:** measure length, wheelbase, track and height in Blender against the real car.
   If the wheelbase is more than ~3% off, stop and switch to pick B.
3. **Interior inventory** against the brief's list: steering wheel, column, paddles, seats,
   console, controls, vents, door cards, headliner, pedals, mirrors, screens. Every missing item is
   modelled by us or the pick changes.
4. **Separation inventory:** are wheels, tyres, discs, **calipers**, doors, steering wheel and
   wipers separate objects with sensible origins?
5. Find and list the trademark items: badges, logo textures, the wheel-centre bull, the steering
   wheel logo, the licence plate.

### Step 1. Blender preparation
- Units metric, scale 1. Apply transforms on every object.
- Apply the modifiers: mirror and bevel always; subsurf **per part, at the lowest level that keeps
  the silhouette**. Reducing the subdivision level beats `Decimate (Collapse)` on hard-surface
  panels. Use Decimate (Planar or Collapse) for interior props.
- Shade panels with Weighted Normal or custom split normals. Export the normals and tangents, then
  check the shading in Studio, because a source read of the exporter is only a hypothesis.
- Delete what is never seen: engine internals behind closed covers, hidden fasteners, chassis
  detail beyond what the low chase camera shows.
- Merge small same-material parts into their parent panel (bolts, clips, trims). The brief warns
  against "des milliers de pièces individuelles".
- Keep the axis convention consistent with the kit's existing pipeline (front +Z in glTF, per the
  voxel mesh notes), and set the importer's World Forward and World Up to match.

### Step 2. Split into MeshParts, ≤18,000 triangles each, one material each
Proposed budget for the hero car at LOD0. It is a starting point to be checked with Studio's
MicroProfiler and scene stats, not a measured target.

| Group | Parts (each a MeshPart) | Triangle budget |
|---|---|---|
| Body paint | split along real panel gaps: front bumper, hood, front wings L/R, doors L/R (outer skin), sills L/R, roof, engine cover, rear wings L/R, rear bumper | ~60–80k in total |
| Carbon and black trim | splitter, diffuser, side intakes, wing, mirror caps | ~15k |
| Glass | windshield, side windows L/R, rear and engine glass | ~3k |
| Lights | head/tail housings, lenses (glass), emissive elements as separate parts | ~8k |
| Wheel (×4, instanced) | rim, tyre, brake disc; **caliper as a separate part** | ~7–9k per corner |
| Interior | dashboard, cluster/screens, centre console, seats L/R, steering wheel (+ paddles), column, pedals, door cards L/R, headliner, floor/carpet, mirror | ~40–60k |
| Underbody | one simplified tray | ~2k |
| **Total** | about 50–90 MeshParts | **~150–200k** |

- **Instancing:** upload each unique mesh once and duplicate it in Studio. "Instancing applies when
  multiple meshes with the same MeshContent are handled in a single draw call" (performance page).
  One rim, one tyre, one disc and one caliper mesh serve four corners. Roblox parts take no
  negative scale, so a handed part (directional spokes, caliper left/right) needs its own mirrored
  mesh. Watch `Invert Negative Faces` if a mirrored object reaches the exporter.
- **LOD1**, built now and kept in reserve:
  - roughly 30–40% of LOD0's triangles;
  - an interior "shell" of about 3–5k triangles that replaces the detailed cockpit when the camera
    is outside and far away;
  - the client toggles visibility, because MeshId cannot be swapped at runtime.

### Step 3. Bake and materials
- Group the materials into about 10–14 texture sets at 1024²:
  - paint: a near-white colour map and **AlphaMode TintMask**, so the colour is a runtime `Color`;
  - carbon, rubber and tyre sidewall, rim, brake (disc and caliper share), light housings, lenses;
  - interior leather and Alcantara, interior plastics and carbon, glass.
- Bake in Cycles from the high-poly source to the decimated mesh: Base Color, Roughness, Metallic
  (through an Emission pass), **Normal (OpenGL, which is Blender's default and matches Roblox)**
  and the Emissive mask. Procedural shaders (carbon, flakes) must be baked or replaced.
- **Paint:** Roblox has no clearcoat layer.
  - Approximate it with low roughness, about 0.1–0.25 plus the docs' "roughly 0.1" Fresnel margin.
  - Metalness 0 for solid colours.
  - Lighting with `EnvironmentSpecularScale` > 0.
  - Per the brief, no painted reflections in the colour map.
- **Glass:** separate parts with `Transparency` (start at 0.6–0.8) and a tint, and no
  SurfaceAppearance, or AlphaMode Transparency at ≥0.02 for soft edges. Check the sorting from the
  cockpit: the brief rejects a windshield that reads as opaque.
- **Screens / `DashboardSurface`:** a thin, flat, separate Part aligned to each screen, for Codex's
  SurfaceGui. A SurfaceGui is expected to draw on a part face, not on mesh UVs; verify this in
  Studio.

### Step 4. Import settings
- Turn on **Asset Privacy** first (section 5.9), on whichever account or group will own the
  test-place assets.
- Import FBX, or .gltf converted from the .glb. Settings: `Merge Meshes` off; **`Use Imported
  Pivot` on**; `Anchored` on for the inspection pass; `Make Double Sided` off, except a thin
  interior surface that proves to need it; `Scale Unit` matching the file's unit.
- Check every part's triangle count in File Geometry, then measure the wheelbase in Studio against
  Step 0.

### Step 5. Rig: origins in Blender become pivots in Studio
Set each moving object's **origin exactly on its rotation axis, with the axis orientation
correct**, before export:

| Part | Pivot / axis | Moves with | Notes |
|---|---|---|---|
| Rim + tyre + disc (per corner) | wheel centre, axle axis | spin, plus steer at the front | Driven by `wheelAngularSpeedRadS`, `steerAngleRad` and `suspensionCompressionM` from the telemetry contract |
| **Caliper** | welded to the knuckle (upright) | steer + suspension only | **Never a child of the spinning hub**: the brief says "Les étriers ne tournent pas avec les jantes" |
| Steering wheel | the column axis, at the hub | `steeringInput` × the steering ratio (from `02_…`) | Check whether the shift paddles are **column-mounted** (I believe the Aventador's are fixed to the column; verify on reference photos) or wheel-mounted, and rig them to match |
| Pedals | top hinge | brake01 / throttle01 | small angles |
| Wipers | `WiperPivot` at each spindle | wiper state | The sweep arc must match the future rain mask; count the arms on the chosen car |
| Doors (only if the prototype needs them) | the scissor-door hinge near the A-pillar base | `HingeConstraint` Servo, or an animated weld | Lamborghini V12 doors swing up on a mostly transverse, tilted axis; measure it on references |

- **Hierarchy:**
  - `Car` (Model) holds `Chassis` (invisible collision root, **`RootPriority` 127**, not
    massless), `Body`, `Interior`, `Corner_FL/FR/RL/RR` (each: `Knuckle` → `Hub` → rim, tyre,
    disc; caliper on `Knuckle`), `SteeringWheel`, `Pedals`, `Wipers` and `Doors`.
  - The visual moving parts are driven on the client from telemetry, using Motor6D transforms or
    weld C0 updates. They are not physics bodies, which keeps visuals and physics decoupled as the
    brief asks.
- **Named attachments from the brief, all on `Chassis`:** `Wheel_FL/FR/RL/RR`, `Exhaust_L/R`,
  `Headlight_L/R`, `BrakeLight_L/R`, `DriverEye`, `CameraChase`, `CameraHood`, `EngineAudio`,
  `ExhaustAudio`, `DashboardSurface`, `WiperPivot(s)`.

### Step 6. Collision proxy and flags
- **Physics:** the invisible `Chassis`, a few Box Parts (or one low-poly hull MeshPart with
  `CollisionFidelity = Hull`) shaped like the body, with mass from `02_…` set through
  CustomPhysicalProperties. The wheel and suspension model is decided in `01_…` and `04_…`.
- **Every visual MeshPart:** `CanCollide = false`, `CanTouch = false`, `CanQuery = false`,
  `Massless = true`, `CollisionFidelity = Box`, `Anchored = false`, welded to its driver part.
  Exception: anything a camera-occlusion or interaction raycast must hit (decided with Codex's
  camera module).
- Driver seat: an invisible `VehicleSeat` or `Seat` placed so the avatar's head lands on
  `DriverEye`.

### Step 7. Checks that can fail
- A Studio test script that **fails** if:
  - any descendant of `Body` or `Interior` has `CanCollide`, `CanTouch` or `CanQuery` true, has
    `Massless` false, or is not on Box fidelity;
  - any required attachment name is missing;
  - any caliper is a descendant of a `Hub`;
  - any MeshPart reports more than 18,000 triangles at import.

  Show each assertion failing once on a deliberately broken copy before trusting it.
- Normal-map check: a light orbiting one panel shows no inverted bumps (green channel). Metalness
  check with `EnvironmentSpecularScale` > 0.
- Pivot check: rotate each moving part by ±30° in Studio and look for gaps or interpenetration.
- Cost: frame time and memory on the owner's real phone, in the chase view and the cockpit view.
  Emulator numbers are not a measurement of a phone.

### Step 8. Credits and records
- CC BY assets (picks 3–6, or the Khronos test car): credit in an in-game Credits panel and in the
  experience description, with creator, title, link, "CC BY 4.0", and "modified (decimated,
  re-textured)".
- Blendkit Royalty Free needs no attribution. Keep the archived page and licence anyway.
- Never publish any of these meshes to the Creator Store.

---

## 7. What was searched, and what I could not check

| Source | What I did | Result |
|---|---|---|
| Sketchfab | Data API search, downloadable only, sorted by likes: "aventador svj", "aventador", "aventador interior", "huracan", "lamborghini interior", "supercar interior", "car interior" (+ cars-vehicles category), "porsche interior", "ferrari interior", "sports car interior" (licence `by`), "car interior" and "car" (licence `cc0`). Model and comment records for the shortlisted ones. | Responses were cut at ~100k characters, so I read about 13–20 results per query; for two queries I read on with an offset. **"Not found" means not in those results.** No images or viewers seen. |
| Blendkit (ex-BlenderKit) | API search "lamborghini", "aventador", "car interior" (free) + asset records + licence pages | Search responses were cut after 3 results per query. The asset records are complete. |
| Poly Haven | [API, vehicles-transport](https://api.polyhaven.com/assets?type=models&category=vehicles-transport) | 11 assets: "Covered Car", tyres, rims, ships. No usable car. |
| Khronos glTF Sample Assets | CarConcept README | Shortlisted, #4. |
| Blend Swap | [search "lamborghini"](https://www.blendswap.com/search?keywords=lamborghini) | No Lamborghini returned. A Bugatti Chiron (CC-BY-NC) and a BMW M4 F82 (CC-BY, interior unknown) appeared; not pursued. |
| CGTrader free | search page | The page came back empty (client-rendered). **Not checked.** |
| TurboSquid free | search page | HTTP 403. The licence terms come from their help articles (section 4.1). **Listings not checked.** |
| Free3D | search page | HTTP 403. **Not checked**; its licence wording is unverified. |
| Open3DLab | home page | Mostly characters, "explicitly game-extracted" content, and no licence system. Excluded. |
| RenderHub (paid) | from search results | SVJ and Aventador models with interiors, all "Editorial Use Only". |
| BeamNG / Assetto Corsa mods | BeamNG legal docs | Not a source (section 4.2). |
| Roblox docs | the pages cited in section 5 | The texture page contradicts itself (4096 against 1024). The importer page sets no triangle limit and does not list .glb. Emissive on a plain MeshPart is not confirmed by the docs. |

**Next actions for the owner:**
1. Download picks A and B. Each needs a free Blendkit account, as far as I can tell.
2. Optionally download the Khronos Car Concept as the pipeline test.
3. I run the Step 0 gates on the files and report back before any Studio work.
