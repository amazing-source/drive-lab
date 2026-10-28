# 07 — Visual references (brief section 3)

Researched 2026-10-27 for the Drive Lab brief (`reference_pack/.../01_PROMPT_CLAUDE_FEEL.txt`, §3).
17 retained references, then the gaps still to consult, then the rejected candidates.

## How each one was checked (read this before trusting an entry)

- **Seen (full image)**: the still was downloaded and opened. Local copy in `references/`.
- **Seen (storyboard)**: a video. I cannot play video or hear audio. I checked it through YouTube's
  public storyboard thumbnails (one frame every 1 to 20 s, 160x90 or 320x180 px) and the
  1280x720 auto-frames YouTube makes for each video. That proves what is on screen and roughly when.
  It does **not** show a wiper stroke, a gear-change transient or a spray plume at full resolution.
  Every timing below that needs more than about 1 s of precision is marked **to measure**.
- **Audio not heard**: no sound was evaluated. Those entries are "à écouter".
- Chapter timestamps come from the uploader's description where one exists, and are marked as such.
- The web search budget for the session ran out midway (a 200-call limit shared by every agent).
  Some of the gaps listed at the end come from that, not from the reference not existing.

**Copyright.** `references/` holds third-party stills (Lamborghini, Microsoft/Turn 10, BeamNG,
YouTube frames). They are kept locally for study only and are never assets for the game. The
folder is currently untracked in `rbx-game-kit` and **not git-ignored**, so do not commit it.
Adding `research_notes/Drive lab/references/` to `.gitignore` is the owner's call. The only
freely licensed image is R05 (CC0).

## Summary

| # | Domain | Reference | View type | Status |
|---|---|---|---|---|
| R01 | Cockpit geometry | Lamborghini, SVJ interior (passenger-side view) | manufacturer photo | seen (full) |
| R02 | Cockpit materials, modes | Lamborghini, console close-up + ANIMA selector | manufacturer photo + CG illustration | seen (full) |
| R03 | Cluster | Motorsport Magazine, SVJ launch 0-270 km/h, cluster onboard | real onboard video | seen (storyboard, 1 fps) |
| R04 | Exterior proportions | Lamborghini, SVJ side profile at speed | manufacturer photo | seen (full) |
| R05 | Exterior proportions | Commons CC0, SVJ near-orthogonal rear, overcast | real photo | seen (full) |
| R06 | Exterior details | Lamborghini, rear 3/4 close-up (exhaust, diffuser) | manufacturer photo | seen (full) |
| R07 | Light on paint, chase framing | Lamborghini, rear 3/4 tracking shot at dusk | manufacturer photo | seen (full) |
| R08 | Light on paint (warm) | Lamborghini, front 3/4 in low warm sun | manufacturer photo | seen (full) |
| R09 | Suspension rig | Lamborghini, pushrod suspension illustration | manufacturer CG illustration | seen (full) |
| R10 | Cockpit presentation, HUD | GT7, Aventador LP 750-4 SV '15, cockpit gameplay | gameplay (then replay) | seen (storyboard) |
| R11 | Rain on glass, wipers (day) | Cycu1, GT7 vs DRIVECLUB rain comparison | gameplay | seen (storyboard + frame) |
| R12 | Rain on glass (night) | DRIVECLUB night heavy rain, cockpit, no HUD | gameplay | seen (storyboard) |
| R13 | Tyre spray | Cycu1, GT7 vs ACC rain comparison, ACC chase cam | gameplay | seen (storyboard + frame) |
| R14 | Materials (paint, carbon, metal, rubber) | Forza Motorsport press kit 08 (+02) | press still, capture mode not stated | seen (full) |
| R15 | Suspension motion | BeamNG official physics page, damping animation | developer doc animation | seen (all 267 frames analysed) |
| R16 | Onboard sound (cockpit) | Same video as R03 | real onboard video | **audio not heard** |
| R17 | Exterior sound, real follow framing | Ishaaq Vlogs, "stock" SVJ, London at night | real follow-car video | seen (storyboard); **audio not heard** |

One image for the look and one sequence for the motion, per sensation:

| Sensation | Image (look) | Sequence (motion) |
|---|---|---|
| Sitting in the cockpit | R01, R02 | R10 7:50–14:50 |
| Reading the instruments | R02 (mode labels); a still of the cluster is still missing | R03 0:35–0:58 |
| Low, wide silhouette | R04, R05, R06 | R03 0:22–0:24 (rear on track), R17 |
| Light changing on the paint | R07, R08, R14 | the owner's AC video (pack) |
| Water on the windscreen | R11 frame, R11c | R11 9:22–11:46, R12 |
| Tyre spray | R13b | R13 2:57–5:57 |
| Suspension working | R09 | R15 (principle only) |
| Engine and shifts | R03 | R16 (cockpit), R17 (exterior): to listen |

---

## R01 — Cockpit geometry: SVJ interior, manufacturer photo

- **Source**: Lamborghini's own SVJ page, https://www.lamborghini.com/en-en/history/aventador-svj
- **Image URL**: https://www.lamborghini.com/sites/it-en/files/DAM/lamborghini/facelift_2019/model_detail/aventador/svj/2020/restyle_12_22/s/aven_svj_s_03.jpg
- **Local**: `references/01_svj_interior_lamborghini_s03.jpg` (800x800)
- **View type**: manufacturer photo. Shot from the passenger door at about seated shoulder height,
  looking across at the driver's station. Wide lens.
- **Lighting**: daylight through the glass, soft, no hard sun patches.
- **Reproduce**:
  - The order of depth from the driver: rim, then a deep carbon-edged cluster hood with the screen
    set well back inside it, then a flat dash top running forward to a very low, very raked
    windscreen.
  - The tall centre stack, angled toward the driver: a small screen in a carbon surround, a row of
    toggle switches, the red hinged start-button flap, a rotary controller lower on the tunnel.
  - The wheel: thick rim, Alcantara with perforated leather grips at 9 and 3 o'clock, a red centre
    marker at 12, a carbon lower section, a large metal paddle visible behind the right of the rim.
  - Materials side by side: matte Alcantara (no highlight), clear-coated carbon (tight highlight),
    satin grey console sides, red Alcantara seat inserts.
- **Do not take**: the red trim (a specification option); camera height or field of view (this is
  not the driver's eye view, and the wide lens stretches depth); the screen content (a splash
  screen, not a driving display). Whether the paddles are fixed to the column cannot be seen
  here: check before rigging them.
- **Variant**: published on Lamborghini's SVJ page. No SVJ plaque is visible in the frame, so the
  variant rests on where Lamborghini placed the image.

## R02 — Cockpit materials and driving modes: console close-up + ANIMA selector

- **Image URLs**:
  - https://www.lamborghini.com/sites/it-en/files/DAM/lamborghini/facelift_2019/model_detail/aventador/svj/2021/03_19/aventador_svj_s4.jpg
  - https://www.lamborghini.com/sites/it-en/files/DAM/lamborghini/facelift_2019/model_detail/aventador/svj/driving_dynamics/Aventador%20SVJ%20DrivingModes.jpg
- **Local**: `references/02_svj_console_lamborghini_s4.jpg`, `references/02b_svj_anima_selector_lamborghini.jpg`
- **View type**: manufacturer photo (close-up) and manufacturer CG illustration (selector).
- **Lighting**: photo is low-key, dark, small highlights only. Illustration is a flat grey studio.
- **Reproduce**:
  - The four mode buttons and their labels: STRADA, SPORT, EGO, CORSA. In the photo the active
    one (SPORT) is lit red and the others are white. Lamborghini's page lists the same four modes
    ("choosing between STRADA, SPORT, CORSA and EGO MODE").
  - The scale of the carbon weave against the switches: the weave cells are small next to a
    toggle tip. Get this scale right or the carbon reads as a texture pattern, not a material.
  - The red hexagonal start flap, the climate rotary with a blue/red ring, chrome-tipped toggles.
- **Do not take**: the dark grade of the photo; the greyed-out background of the illustration
  (it is a diagram, not a material reference).

## R03 — Instrument cluster in motion: SVJ launch control onboard

- **Title**: "Lamborghini Aventador SVJ launch control 0-270 km/h", Motorsport Magazine (FR), 1:04,
  published 2018-10-19
- **URL**: https://www.youtube.com/watch?v=2Puv6q1H7Yo
- **Local**: `references/03_svj_cluster_launch_storyboard_0034-0058.jpg` (storyboard, one frame per
  second, 160x90 each)
- **View type**: real car, magazine test. 0:35–0:58 is a camera framed tightly on the TFT cluster
  while the car accelerates and brakes, so this is the normal driving display, not the start-up
  self-test.
- **Timestamps** (read off the 1-per-second storyboard, so ±1 s):
  - Launch ≈0:37–0:38
  - Upshifts 1→2 ≈0:39–0:40, 2→3 ≈0:41–0:42, 3→4 ≈0:44–0:45, 4→5 ≈0:47–0:48
  - Peak ≈270 km/h ≈0:52, then braking with the gear readout stepping back 5→4→3→2 by 0:58
  - Also useful: 0:12–0:19 exhaust and rear details, 0:22–0:24 near-orthogonal rear on track,
    0:25–0:26 interior seen from the door
- **Lighting**: daylight; the screen is self-lit.
- **Reproduce**:
  - The layout as far as 160x90 shows it: a big red gear digit in the centre; an arc rev counter
    across the top with coloured segments; digital speed in km/h at lower right; a car silhouette
    graphic at lower centre (its function is not identified).
  - The gear digit changes once per shift, with no animation visible at 1 frame per second.
  - Approximate speed per gear, read from the thumbnails: 1st up to ≈70, 2nd ≈97–123, 3rd
    ≈143–180, 4th ≈195–222, 5th ≈233–270 km/h. Braking from ≈270 to ≈73 km/h takes about 6 s
    (≈9 m/s², ±1 s). This is a sanity check for the drivetrain and brake data, not a source.
- **Do not take**:
  - The mode name. It is **not identified**: it could be Sport or Corsa. Do not label this layout
    "Corsa" without a still that says so.
  - Typography, exact colours or small icons. The thumbnails are too small to copy them.
  - A launch-control run as normal driving.
- **To measure**: extract full-resolution frames from 0:35–0:58 by stepping frame by frame.

## R04 — Exterior proportions: side profile at speed

- **Image URL**: https://www.lamborghini.com/sites/it-en/files/DAM/lamborghini/facelift_2019/model_detail/aventador/svj/2021/03_19/Gallery/aventador_svj_g2.jpg
- **Local**: `references/04_svj_profile_lamborghini_g2.jpg` (resized to 1280 wide)
- **View type**: manufacturer photo. Panning shot, left profile, nearly orthogonal, long lens.
- **Lighting**: hard midday sun, sharp shadow under the car.
- **Reproduce**:
  - Wheelbase against overall length, front and rear overhangs.
  - The tyre filling the arch, the very low ride height (the side skirt sits close to the bottom
    of the rim), the glasshouse and roofline.
  - The wing on its pylons above the deck.
  - The driver's head visible in the side window, sitting low and well below the roof line.
    Use it to sanity-check `DriverEye` once the dimensions in `02_aventador_svj_data.md` set the scale.
- **Do not take**: the green paint; the panning blur on the wheels and background (photographic);
  absolute sizes (take ratios from the photo, take scale from the documented dimensions).

## R05 — Exterior proportions: near-orthogonal rear, diffuse light

- **Page**: https://commons.wikimedia.org/wiki/File:Lamborghini_ABA-47L541_Aventador_LP770-4_SVJ_(22080710001).jpg
  (CC0, author 先従隗始, 2022-08-07, Kasamatsu Supercar Festival, Japan)
- **Local**: `references/05_svj_rear_orthogonal_overcast_commons_cc0.jpg` (1280 wide)
- **View type**: real photo (owner's car at a show). Rear, nearly orthogonal. The camera is
  slightly above the deck, so the engine-cover louvres are visible.
- **Lighting**: overcast, diffuse. No hard reflections, which makes the forms easy to read.
- **Reproduce**:
  - Body width against wing span (the wing reaches almost to the body sides).
  - The two round exhausts set high and close together inside a hexagonal mesh panel.
  - The taillight position; the diffuser fins (the outer ones taller); the carbon lower diffuser.
  - The step between the body-colour surround and the black rear fascia.
- **Do not take**: the orange accents on the fins and louvres (this car's specification); the
  Japanese plate; the vertical proportions as if this were an orthographic drawing (the camera is
  raised). The chassis number is not given. Another photo of a different SVJ in the same set says
  "Installed some afterparts" (see Rejected); this one does not, but options cannot be excluded.

## R06 — Exterior details: rear 3/4 close-up (exhaust, diffuser, wing)

- **Image URL**: https://www.lamborghini.com/sites/it-en/files/DAM/lamborghini/facelift_2019/model_detail/aventador/svj/feeltheengine-desktop.jpg
- **Local**: `references/06_svj_rear34_exhaust_diffuser_lamborghini.jpg` (resized to 1200 wide)
- **View type**: manufacturer photo, rear 3/4, close, car stationary.
- **Lighting**: bright daylight with sea glare, high key, soft shadows.
- **Reproduce**:
  - The exhaust outlets: wall thickness, depth, and placement high in the fascia inside the mesh.
    Lamborghini's page calls them "lighter, and higher exhaust outlets".
  - The diffuser strakes; the three-chevron LED taillight segments; the thickness of the deck edge.
  - The wing: Lamborghini's page calls it "omega-shaped". Check its plan shape here and in R05.
  - Panel gaps and the carbon parts against the paint.
- **Do not take**: the white paint and high-key exposure; the "SVJ" side graphic (a livery option).

## R07 — Light on paint and chase framing: rear 3/4 at dusk, in motion

- **Image URL**: https://www.lamborghini.com/sites/it-en/files/DAM/lamborghini/facelift_2019/model_detail/aventador/svj/2021/03_19/aventador_svj_s1.jpg
- **Local**: `references/07_svj_rear34_dusk_motion_lamborghini_s1.jpg` (800x800)
- **View type**: manufacturer photo, car-to-car tracking shot. Rear 3/4 left, camera at about
  taillight height.
- **Lighting**: dusk. A blue sky with peach and pink clouds; soft skylight, no direct sun;
  taillights on.
- **Reproduce**: this is the closest real photo to our chase camera.
  - The framing and camera height.
  - The cool sky lighting the top surfaces (wing, deck, roof) while the sides fall darker.
  - The lit taillight graphic.
  - A sharp car against a blurred road, which is what reads as speed.
  - Compare it with `LOOK_TARGET.jpg` for how bright the paint should sit under a blue-hour sky.
- **Do not take**: the green paint; the photographic motion blur (blur is Codex's camera and
  post-processing decision); the bridge.

## R08 — Light on paint, warm: front 3/4 in low sun

- **Image URL**: https://www.lamborghini.com/sites/it-en/files/DAM/lamborghini/facelift_2019/model_detail/aventador/svj/2021/03_19/Gallery/aventador_svj_g5.jpg
- **Local**: `references/08_svj_front34_low_sun_lamborghini_g5.jpg` (resized to 1280 wide)
- **View type**: manufacturer photo, front 3/4, car stationary, low camera.
- **Lighting**: low sun behind and to the side of the car, warm sky, soft fill.
- **Reproduce**: the warm-light check from brief G ("les arêtes prennent la lumière").
  - The highlights running along the shoulder crease, the front-wing edges and the top of the
    windscreen.
  - The dark wheels and black lower aero staying readable instead of crushing to black.
- **Do not take**: the yellow paint; the front framing (our chase camera sees the rear, so use
  this for how the material responds, not for composition); the HDR-like processing.

## R09 — Suspension rig: manufacturer pushrod illustration

- **Image URL**: https://www.lamborghini.com/sites/it-en/files/DAM/lamborghini/facelift_2019/model_detail/aventador/svj/driving_dynamics/Aventador%20SVJ%20Suspension.jpg
- **Text on the same page**: "magneto-rheological front and rear shock absorbers with pushrod systems"
- **Local**: `references/09_svj_pushrod_suspension_render_lamborghini.jpg`
- **View type**: manufacturer CG technical illustration (not a photo; not a generated or fan render).
- **Lighting**: white studio.
- **Reproduce**: the layout for the rig. Double wishbones; a pushrod to a rocker; a horizontal
  inboard coil-over. The damper is not at the wheel: wheel travel goes through the pushrod and
  rocker to the spring. Those are the parts that could show in a close-up.
- **Do not take**: hardpoints or dimensions (no scale, and the axle is not labelled); the generic
  tyre; the rendering style.

## R10 — Cockpit presentation and HUD: GT7, Aventador SV, cockpit gameplay

- **Title**: "Gran Turismo 7 - Lamborghini Aventador LP 750-4 SV 2015 - Gameplay (PS5 UHD)
  [4K60FPS]", Throneful, 31:10, published 2022-04-14
- **URL**: https://www.youtube.com/watch?v=shaeqMIRU1Q
- **Local**: `references/10_gt7_aventador_sv_cockpit_storyboard_0750-1450.jpg` (one frame every
  20 s, 320x180)
- **Timestamps** (from the storyboard):
  - 0:20–7:40 gameplay, chase camera
  - **7:50–14:50 gameplay, cockpit view** (Nürburgring Nordschleife, daylight)
  - ≈15:30 results screen
  - from ≈15:50 **replay** (broadcast cameras). Do not mix the replay with the gameplay.
- **Variant check**: the game's own label at the start reads "LAMBORGHINI Aventador LP 750-4 SV
  '15". This is the **SV, not the SVJ**. I did not find an SVJ among GT7's Aventadors in the
  results I saw (LP 700-4 '11 and LP 750-4 SV '15), but I did not check the full car list.
- **View type**: gameplay (cockpit view).
- **Lighting**: midday, clear.
- **Reproduce** (presentation principles only; geometry comes from R01):
  - The road fills about the upper half of the frame, dashboard and wheel the lower half.
  - The wheel is large and cut by the bottom edge; the cluster shows through the rim.
  - The essentials (speed, gear) sit large at the bottom centre; secondary items are small at the
    edges; every element stays in a fixed place.
  - The horizon stays steady.
- **Do not take**: the race HUD (position tower, lap timer, map, rival list); the SV's yellow
  cluster graphics (another car); the arm and glove models; the wheel motion (it follows a
  physical G29 wheel); the field of view (not measured here).

## R11 — Rain on glass and wipers, daylight: GT7 vs DRIVECLUB

- **Title**: "Gran Turismo 7 vs Driveclub Rain Effect Comparison", Cycu1, 14:29, published
  2022-03-03. Description: "Both games captured on PS5."
- **URL**: https://www.youtube.com/watch?v=O4pZH5D7zUI
- **Chapters (uploader's description)**: GT7 chase 0:00; Driveclub chase 2:28; chase
  side-by-side 4:43; GT7 cockpit 7:00; **Driveclub cockpit 9:22**; **cockpit side-by-side 11:46**.
- **Local**:
  - `references/11_driveclub_vs_gt7_cockpit_wiper_frame.jpg`: a 1280x720 auto-frame from the
    side-by-side cockpit section. Both blades are caught mid-stroke.
  - `references/11b_driveclub_cockpit_rain_storyboard_0920-1145.jpg`: one frame every 5 s.
  - `references/11c_driveclub_lotus_loaded_glass_frame.jpg`: a complementary frame from another
    video, https://www.youtube.com/watch?v=Q-tBACrQ8rI ("DRIVECLUB India Stormy Rain Lotus
    Gameplay (No HUD, Cockpit)", 2014). It shows the glass fully loaded at dusk.
- **View type**: gameplay, cockpit, heavy rain, daylight. The DRIVECLUB car is a Mercedes-AMG GT
  (Mercedes star on the wheel).
- **Reproduce**:
  - A droplet field of mixed sizes (dense small drops plus larger beads) that sits **on the
    glass**: it moves with the car, while the world behind stays readable.
  - A thin dark blade pivoting from the bottom of the screen.
  - The cleared wedge behind the blade, then drops re-forming.
  - The 9:25–11:40 frames alternate between loaded glass and clearer glass, which shows the wipe
    cycle working, but at 5 s per frame it cannot be timed.
- **To measure**: the wipe period, the blade's angular speed and the time for drops to re-cover
  the cleared zone. Step through 9:22–11:46 frame by frame. The three states the brief asks for
  (loaded, blade moving, just cleared) must come from **one** stroke at full frame rate.
- **Do not take**: the AMG interior; the GT7 half of the frame (that is the comparison); detail
  the YouTube compression smears; drop behaviour inferred from one frame.

## R12 — Rain on glass at night (headlight visibility): DRIVECLUB, no HUD

- **Title**: "DRIVECLUB Gameplay @Night - Heavy Rain Cockpit View No HUD - Lamborghini Gallardo
  1080p", LunaticDoubloon, 7:45, published 2017-06-17 (PS4 Pro, Scotland)
- **URL**: https://www.youtube.com/watch?v=V5wx6E0R53c
- **Local**: `references/12_driveclub_night_rain_cockpit_storyboard_0230-0455.jpg` (one frame
  every 5 s, 320x180)
- **Timestamps**: menus 0:00–0:50; race in cockpit view 0:55 to ≈7:30. A blade is visible in the
  storyboard at ≈2:45, 3:10, 3:15, 3:45 and 4:10.
- **View type**: gameplay, cockpit, no HUD (stated by the uploader), night, heavy rain.
- **Reproduce**:
  - At night the drops catch headlights and trackside lights as short bright streaks, so the
    glass itself becomes the main carrier of light.
  - The interior stays very dark while the white dials stay readable.
  - How much visibility drops.
- **Do not take**: the Gallardo cockpit (another car); streak brightness, which may be partly
  capture and compression; any wipe timing (not resolvable at 5 s).

## R13 — Tyre spray: ACC chase camera, heavy rain

- **Title**: "Gran Turismo 7 vs Assetto Corsa Competizione Rain Effect Comparison", Cycu1, 17:04,
  published 2022-03-04. Description: ACC "(Next-Gen Patch) captured on Xbox Series X".
- **URL**: https://www.youtube.com/watch?v=KM4hAqcKgLY
- **Chapters (uploader's description)**: **ACC chase cam 2:57**; chase side-by-side 5:57; ACC
  cockpit 11:11. The description says the ACC footage in the side-by-side sections was **sped up
  about 10%**, so time nothing there; use 2:57–5:57.
- **Local**: `references/13_acc_wet_chase_spray_storyboard_0300-0550.jpg` (one frame every 10 s);
  `references/13b_acc_vs_gt7_wet_chase_frame.jpg` (1280x720 auto-frame from the side-by-side: GT7
  left, ACC right).
- **View type**: gameplay, chase camera, heavy rain, daylight, GT3 car.
- **What the storyboard shows**: the player car's own spray behind the rear tyres in every frame.
  Other cars ahead at different distances at ≈3:10, 3:30, 4:20 and 4:30; a car alongside at ≈5:30.
- **Reproduce**:
  - Spray starts at the tyre contact patch and rises into a plume behind the rear tyres.
  - It is dense and low just behind the tyre and thins into haze higher and further back.
  - A car ahead lays a grey curtain that lowers the contrast of everything behind it.
  - A close car shows one plume per wheel; a far car shows one merged mist.
- **To measure**: plume height against tyre height and its decay distance, from full-resolution
  frames at several speeds.
- **Do not take**: the GT3 wheel arches and body (the SVJ's wheel houses will shape spray
  differently); race traffic (out of scope); the GT7 half; any particle count.

## R14 — Materials: Forza Motorsport press kit (paint under coloured light, carbon, metal, rubber)

- **Source article**: https://forza.net/news/forza-motorsport-the-most-technically-advanced-racing-game-ever-made
  (it states "real time ray tracing on track" and "anodized aluminum, and carbon fiber")
- **Image URLs**:
  - https://cdn.forza.net/strapi-uploads/assets/xlarge_Forza_Motorsport_Xbox_Games_Showcase2022_Press_Kit_08_16x9_WM_bdada51e96.jpg
  - https://cdn.forza.net/strapi-uploads/assets/xlarge_Forza_Motorsport_Xbox_Games_Showcase2022_Press_Kit_02_16x9_WM_2119515cde.jpg
- **Local**: `references/14_forza_motorsport_presskit08_jesko_wet_pitlane.jpg`,
  `references/14b_forza_motorsport_presskit02_787b_wheel.jpg` (750 wide)
- **View type**: official press-kit stills from the Xbox Games Showcase 2022, a year before the
  game shipped. The capture mode is **not stated**. These are staged compositions, likely photo
  mode or a beauty render, **not gameplay**. The page's alt text calls the car only "A Koenigsegg";
  the shape matches a Jesko, which is not confirmed.
- **Lighting**: 08 is a night pit lane with red and pink neon, cool white overheads and a wet
  floor. 02 is a low angle in a dim pit garage with a wet, reflective floor.
- **Reproduce**:
  - 08: the clear-coat reflection takes on the neon's colour (a pink-red highlight over a teal
    base) while the base colour stays recognisable. That is brief G's "same material, two lights".
    Exposed carbon (splitter, side) reads darker, with a tighter highlight broken up by the weave.
    The tyres are matte. The floor reflection stretches.
  - 02: the chrome rim lip is a sharp mirror; the gold wheel has tinted reflections; the rubber is
    matte; the decals share the paint's clear coat.
- **Do not take**: ray-traced reflections (Roblox has no equivalent); the overall saturation and
  grade; these cars; any pre-release image as the shipped look.
- **Missing**: a driving shot of the same car, to tell presentation detail from what reads in play.
  **To consult.**

## R15 — Suspension motion principle: BeamNG official damping animation

- **Page**: https://www.beamng.com/game/about/physics/ ("Soft-body Physics", official documentation)
- **Animation**: https://www.beamng.com/game/features/soft-body/Damping.gif. Captioned "Left: No
  Damping | Right: Some Damping": the same light vehicle lands on two springs of equal stiffness.
- **Local**: `references/15_beamng_doc_damping_gif_frames.jpg` (16 of the 267 frames)
- **View type**: developer documentation animation (in engine).
- **Lighting**: neutral daylight.
- **Measured from the GIF** (body centroid tracked in every frame; 30 ms per frame, 8.0 s loop;
  times are GIF time, and the GIF is not confirmed to be real time):
  - Contact ≈2.2 s; maximum compression ≈2.6–2.7 s.
  - The damped car makes **one rebound** and is back within 2 px of rest by ≈3.2 s, about 1 s
    after contact.
  - The undamped car is still oscillating at the end of the loop: ≈25 px peak to peak over the
    last 2 s, a period of about 0.8–0.9 s.
- **Reproduce**: the causal order (contact, compression, rebound, settle) and the difference
  between an underdamped bounce and a damped settle with one small overshoot. That is the
  "serré, amorti" target of brief A.
- **Do not take**: the amplitudes (a light vehicle dropped on a test spring, nothing like a
  supercar on its tyres); the BeamNG values quoted on the page (40000 / 4500 for suspension
  springs and dampers are node-beam values, not our model).
- **Missing**: a road car in BeamNG over a bump, or braking, in slow motion. **To consult** (see
  Rejected for the candidates that failed).

## R16 — Onboard sound, cockpit: SVJ press car launch

- **URL**: https://www.youtube.com/watch?v=2Puv6q1H7Yo (same video as R03)
- **Timestamps**: 0:35–0:58 onboard run; shift times as in R03 (five events in about 10 s).
  Braking with downshifts 0:53–0:58.
- **Local**: `references/16_svj_press_car_rear_track_frame.jpg`: an auto-frame of the same car's
  rear on track (≈0:22–0:24), for the exhaust check.
- **Is it stock?** It is a magazine press test: the end card is the cover of Motorsport n°84,
  Oct–Nov 2018, "Essai Lamborghini Aventador SVJ". The outlets seen at 0:12–0:19 and in the local
  frame are the factory pair set high in the mesh, as in R05 and R06. The external geometry
  matches stock. Internal changes cannot be ruled out from video, but a press car is the best
  "stock" evidence I found.
- **Recording**: microphone position unknown. The camera is on the cluster, which suggests cabin
  sound, but the soundtrack may be post-mixed.
- **Reproduce (after listening)**: the rpm climb in each gear, the torque cut and rpm drop at each
  shift, and what the engine does on the downshifts.
- **Status**: **AUDIO NOT HEARD. À écouter.** Nothing about the sound is claimed here.

## R17 — Exterior sound and a real chase framing at night

- **Title**: "The BEST STOCK Lamborghini Aventador SVj Drive! \*Loud Accelerations & REVS!\*",
  Ishaaq Vlogs, 9:48, published 2025-07-04
- **URL**: https://www.youtube.com/watch?v=rLK_Yey4atk
- **Local**: `references/17_svj_follow_car_night_storyboard_0500-0725.jpg` (one frame every 5 s,
  320x180)
- **Timestamps** (storyboard): pulling out and close exterior 0:00–0:30; follow-car footage from
  ≈0:50 onward; 5:00–7:25 a long follow at varying distances.
- **Is it stock?** The description says "completely stock Aventador SVJ". That is the uploader's
  claim and is not verified: at 320x180 the rear shows the twin high outlets, but that cannot
  exclude an aftermarket system with factory-style tips.
- **View type**: real exterior footage from a following car; London at night; the streets look dry.
- **Reproduce**:
  - Audio, after listening: the exterior note at moderate speed and the reflections off buildings.
  - Visual: real taillights and brake lights seen from a chase position at night, and how far a
    following camera drifts.
- **Do not take**: traffic and the city (out of scope); the handheld shake; any music (unknown).
- **Status**: **AUDIO NOT HEARD. À écouter.**

---

## Still to consult (not found or not reachable in this pass)

1. **SVJ driver's eye-height photo**: wheel, cluster hood, windscreen and pillars from the driver's
   eyes. R01 is from the passenger side. Not found before the search budget ran out.
2. **SVJ seat, side view.**
3. **SVJ cluster stills in Strada, Sport and Corsa**, kept apart from the start-up self-test.
   R03 shows only one, unidentified mode at 160x90.
4. **DRIVECLUB wipe timing**: frame-step R11 at 9:22–11:46.
5. **Forza Motorsport driving shot of the same car as R14.**
6. **BeamNG road car, bump or braking, slow motion** (the vehicle-level sequence for brief A and C).
7. **Listening**: R16, R17 and the owner's AC video.
8. **GT7 official manual, "driving views"** (https://www.gran-turismo.com/us/gt7/manual/race/03):
   the page is rendered by JavaScript and returned only its title to a fetch. Open it in a browser.

## Rejected candidates

| Candidate | Why it was dropped |
|---|---|
| Commons "Lamborghini Aventador SVJ (Ank kumar, Infosys) 01–06" | **Misidentified variant.** EXIF date 2015-03-14, three years before the SVJ was unveiled (Lamborghini: "Aventador SVJ Unveiled at Monterey Car Week", August 2018). Two sibling files by the same author are titled "SuperVeloce". Probably an SV. |
| Commons "Lamborghini ABA-47L541 Aventador LP770-4 SVJ (22080709384)", purple | The description says "Installed some afterparts": a modified car. Tempting for the purple paint, rejected for the geometry. |
| Commons "Lamborghini Aventador SuperVeloce at Geneva 2018 (Ank Kumar)" and other SV/S files | Another variant. |
| YouTube Sd_SKu6ODVU (Capristo/Grail), w6kKVs-h9Ns, e27hpD5Zwgc, c2wguMa7a30 (Gintani) | Aftermarket exhausts, by their own titles. Not stock sound. |
| YouTube zqv9zLtHsUM (source of a Commons SVJ audio file) | A compilation re-upload (75 views) crediting other channels. Provenance and the state of the car are unknown. |
| YouTube vG3aqkEh99w (HubraumTV, three SVJs) | The exhaust state is not stated. R17 covers exterior sound with an explicit, if unverified, stock claim. |
| YouTube QOaGH18Xuno "First look at BeamNG 0.27 - Slow Motion Suspension" | "Video unavailable". |
| YouTube JlgoU4TCO1g "BeamNG - car suspension test" | Its own description: "slow motion two cars frontal crash". Not suspension. |
| YouTube -6OiHfPDjmI "The Physics of BeamNG" | A general explainer (node/beam visualisation, aero, environment). The storyboard shows no bump or braking sequence. |
| YouTube 4hbRlYsg1Ak "BeamNG Drive - A Study in Suspension" | Under-chassis cameras on off-road trucks in a desert. The 10 s storyboard cannot confirm a clean bump sequence; amplitudes are far from a supercar. Fallback only. |
| YouTube zbUkOFfO82s GT7 "Lambo V12 VGT" cockpit | A concept car, not a road-car cockpit. |
| YouTube 4UeWe6_PFko GT7 Aventador LP 700-4 | An older variant. The SV video was chosen because its cockpit section was verified. |
| YouTube jedyEpf2qfk DRIVECLUB first-person rain | HUD on, and a snow and rain mix on an alpine stage. |
| YouTube Eh_dJLxM7WM and pwAhQB5Nx68 (ACC wet races, 2018) | Early Access and pre-release event builds. The 2022 next-gen capture in R13 is closer to the shipped game. |
| NetCarShow SVJ gallery | Every image request timed out. Not viewed. |
| Lamborghini news pages for the SVJ launch | Rendered by JavaScript; the pages returned no content to a fetch. The model page's own images were used instead (R01–R09). |
| Audi Media Center "Lamborghini Aventador SVJ" (A202110) | Caption only, no description of the view; not opened. |
