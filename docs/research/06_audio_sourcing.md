# 06: Audio sourcing for the SVJ (engine, gearbox, tyres, wind, water)

> **Read "Pass 2: quality-only ranking" at the end first.** The owner's final decision
> (2026-10-27) accepts game-ripped and unlicensed audio for this private project. Pass 2 re-ranks
> the engine sources on quality and fit only, and supersedes sections 1, 2 and 6 for the engine
> route. Sections 3 (secondary layers), 7, 8 and 9 still apply.

Researched 2026-10-27 using web search, page fetches and public APIs only. No login, no browser
automation, no audio file downloaded. I did download text lists to read: the Sonniss track
lists (CSV), one library file list (PDF), and engine-sim source files from GitHub.

**Licence rule, as updated by the owner on 2026-10-27.** The Drive Lab is a **non-commercial
portfolio showcase** that earns no Robux.
- **Allowed:** CC-BY-NC and other non-commercial licences, ranked on quality like everything else.
  Record the exact licence and the attribution.
- **Never used as assets:** audio ripped from commercial games or mods, and audio from YouTube.
  YouTube is for reference listening only (section 9).

**Evidence tags.**
- `[PAGE]` I read the source page.
- `[LIST]` I read the publisher's own file or track list.
- `[CODE]` I read the source code.
- `[SNIP]` A search-result snippet only.
- `[INF]` My inference.
- `[NV]` Not verified.

**Limits of this note.**
- The session's web-search budget ran out near the end. So I did not check:
  - BBC Sound Effects' catalogue for Lamborghini or V12 content;
  - the exact EULA wording at A Sound Effect, Pole Position and Sound Ideas;
  - GameDev Market's racecar packs;
  - the car list of Soundholder's "Game Audio Engines".
- Every "not found" covers only the queries listed in section 11.
- I listened to nothing. Every quality remark comes from descriptions, file names, mic lists and
  comments.

Car facts used below come from `02_aventador_svj_data.md`: 60° V12, bore 95.0 mm, stroke 76.4 mm,
fuel cut at 8,700 rpm, idle about 950 rpm warm and 1,200 cold (estimated), shifts "up to 50 ms",
an exhaust valve that changes with the drive mode, and pops on overrun in Sport and Corsa.

---

## 1. Bottom line

1. **Nothing free gives a ready-made, rpm-stamped, on-load/off-load SVJ bank.**
   - Freesound, Pixabay and OpenGameArt hold only short revs, start-ups and pass-bys of
     Lamborghinis or V12s, with no fixed-rpm loops (section 2.3).
   - The rpm-stamped V12 banks in the Roblox Creator Store and Pixabay are, by their naming,
     ripped from games. Excluded (section 4).
2. **The best real recordings of this engine are paid.**
   - Pole Position Production's **Lamborghini Aventador 2014** library: an LP700-4 with the same
     L539 V12 family and ISR gearbox; 286 files, 24-bit/96 kHz; listed at $249 [PAGE].
   - Its file list shows exactly the takes a crossfaded engine needs [LIST]:
     - `ONBRD - STEADY RPMS`, `RAMPS`, `GEARSHIFTS` and `IDLE`;
     - each with exhaust L/C/R, engine L/C/R, intake L/R and interior microphones.
   - The SVJ libraries on sale are **not stock**:
     - Pole Position's SVJ 2019: "aftermarket exhaust";
     - Sounding Sweet's Aventador: "custom straight-pipe exhaust".
3. **There is a free slice of that same 2014 Aventador library.** The Sonniss **GDC 2020** free
   bundle contains three of its files [LIST]:
   - `lamborghini_aventador_t14_onbrd_start_drive_ramps_stop_off_exhaust_right_DPA4062.wav`: an
     onboard **ramps** take at the exhaust;
   - `lamborghini_aventador_t9_ext_fast_by_four_times_ORTF_MKH8040.wav`: **four fast exterior
     pass-bys**;
   - a horn take.

   The Sonniss licence is royalty-free and commercial, needs no attribution, and bans AI training
   [PAGE].
4. **The route that is complete, legal and fully ours is procedural:** AngeTheGreat's
   **engine-sim** (MIT licence) with a V12 script adapted to the L539.
   - Its dynamometer **hold** mode can drive *and* brake the crankshaft at a fixed rpm [CODE]. That
     gives true steady **on-load** (full throttle, dyno braking) and **off-load** (throttle shut,
     dyno driving the engine) recordings at any rpm, in 100 rpm steps.
   - The repo already ships two V12 scripts (Ferrari 412 T2, Merlin) to start from [PAGE].
5. **Recommended route** (section 6):
   - an engine-sim L539 bank for the engine loops, tonally matched against the free GDC Aventador
     ramp and the stock-SVJ reference videos;
   - real recordings (GDC, Freesound CC0, Roblox's own Pro Sound Effects catalogue) for the
     secondary layers and one-shots;
   - procedural synthesis for wind and gearbox whine.
   - **Owner decision:** buying the $249 Pole Position Aventador 2014 library is the one upgrade
     that swaps synthetic engine loops for the real L539. Its cabin, intake and mechanical
     character is what engine-sim cannot produce.

---

## 2. Ranked shortlist (a): engine and exhaust layers

Ranking weighs four things: how close the sound is to this engine, how far the takes fit an
rpm/load bank, recording quality, and how clean the licence is.

### 2.1 Ranked table

| Rank | Source | What it is | Licence | Format | Fit for the bank | Notes |
|---|---|---|---|---|---|---|
| **1** | **engine-sim, own L539 script** (github.com/ange-yaghi/engine-sim) | Physics-based engine audio synthesis | **MIT**, "Copyright 2022 AngeTheGreat (Ange Yaghi)" [PAGE]. The recordings are our own output. | Renders at **44,100 Hz**, hard-coded [CODE] | **Complete:** any rpm, any throttle, steady holds, ramps, limiter | Synthetic. No intake, cabin, mechanical noise or afterfire pops [INF]. Needs a Windows build from source, or the community-edition binary whose licence is not stated (section 5.1). |
| **2** | **Sonniss GDC 2020 bundle:** 3 files from Pole Position's *Lamborghini Aventador 2014* | Real L539. Onboard ramps at the exhaust (DPA4062), 4 exterior fast pass-bys (ORTF MKH8040), horn | GDC bundle licence: royalty-free, commercial, **no attribution**, unlimited projects, **no AI training**, no resale as sound effects [PAGE] | Pole Position records at 24/96 [PAGE]. Lengths are not on the list. | **Ramps:** the sweep up is on-load and the sweep down is off-load. You can cut short grain loops or take a tonal reference, but not long steady loops. The pass-bys are exterior one-shots. | Free. The bundle is 48.2 GB in 14 zip parts, so only the part holding these files is needed [PAGE]. Stock exhaust not stated. |
| **3** | **Pole Position Production, *Lamborghini Aventador 2014*** (A Sound Effect, $249) | Real L539 / ISR, 2014 LP700-4. 19 synced takes. Onboard: 12 channels, 11 perspectives (exhaust, engine, intake, cabin). Exterior: 10 perspectives. | "Royalty-free, you can select the number of users on checkout" [PAGE]. The game-use clause was not read [NV]. | 24-bit/96 kHz WAV, 286 files [PAGE] | **Best real source.** File list [LIST]: `t5 RAMPS`, `t6 STEADY RPMS`, `t4 GEARSHIFTS`, `t7/t11 IDLE` (with blips and steadies in neutral), all onboard and exterior | Same engine family as the SVJ, but 690 vs 770 hp, and the SVJ has a different, lighter exhaust and titanium intake valves (see 02). Stock exhaust not stated. Paid, so **the owner decides**. |
| 4 | Pole Position, *Lamborghini Aventador SVJ 2019* (Sonniss, $99 spotting / $249 complete) | Real SVJ. 13 synced takes, 25 perspectives, 343 files, 38 GB | Royalty-free [PAGE] | 96/24 | Has "steady RPMs", ramps, gearshifts and idles [PAGE] | **"With aftermarket exhaust"** [PAGE]. Not the stock sound. |
| 5 | Sounding Sweet, *Lamborghini Aventador* (Sound Ideas, $249) | 15 mics: engine bay, over the exhausts, in the intakes; ambisonic cabin; 255 files | Not stated on the page [PAGE] | 96/24 | Unknown. The page itemises no steady rpm or ramps. | **"Custom straight-pipe exhaust"** [PAGE]. Not stock. |
| 6 | Sonniss GDC bundles, **other V12/V10 cars** (free) | GDC 2019: **Aston Martin DB9** V12, onboard "Idle Blips Steadies in Neutral", engine mic. GDC 2023: DB9 exterior ramps. GDC 2020: **Ferrari F12** V12 onboard engine mic; Ferrari 488 "steady RPMs" at the exhaust. GDC 2020: **Lexus LFA** V10 "Designed 2k RPM loop" (onboard) and "8k RPM loop" (interior). GDC 2023: Ferrari Testarossa flat-12, onboard steady RPMs. | GDC licence (as rank 2) | Mostly 96/24 | Real steady and neutral material, but **other engines** | Good for texture layers (mechanical, intake), for testing the pipeline, and for checking what a "designed rpm loop" looks like. Not the L539 voice. [LIST] |
| 7 | Freesound **djbono, "Ferrari F456.wav"** (sound 18771) | Ferrari 456 V12 revving 800 to 6,200 rpm, mics behind the exhaust and under the engine (SM58) | **Sampling+ 1.0** [PAGE]. Usable now that non-commercial use is acceptable. | WAV 44.1/16 stereo, 1:25 | Free revs only, no load | Old (2006), a dynamic mic, a different V12 (65°, front-engined) |
| 8 | Freesound **florianreichelt, "Acceleration of a Sports Car Engine like Ferrari or Lamborghini or Porsche"** (457560) | Exterior acceleration in Dubai. Car unknown. | **CC0** [PAGE] | WAV 96/24 stereo, 16 s | Exterior one-shot | The model is unknown, so it may not be a V12 |
| 9 | Freesound **JaimeLopes, "Lamborghini Sounds"** (564375) | Huracán EVO Spyder: door, start, drive-off | **CC-BY 4.0** [PAGE] | WAV 48/24 stereo, 36 s | Start-up one-shot at most | V10, recorded on a Tascam DR-07's internal mics |
| 10 | Freesound **enginemusic, "ferrari340america2.mp3"** (43483) | 1950s Ferrari 340 America 4.1 L V12 revving | **CC-BY 3.0** [PAGE] | **MP3 192 kbps**, 12 s | Not usable for loops | Lossy. A historic V12. |
| 11 | DasEtwas **enginesound** (Rust, github.com/DasEtwas/enginesound) | Procedural engine sound generator | **MIT** [PAGE] | WAV export, sample rate set by `-q` (default 48 kHz), `-r` rpm, `-l` length, `-w` warmup, `-f` crossfade for a seamless loop [PAGE] | Outputs fixed-rpm loops directly | The author calls it "pseudorealistic" [PAGE]. V12 and firing-interval support not verified. A backup to engine-sim. |
| 12 | itch.io **Magic Sound Effects, "Car Engines" / "Vol. 2"** ($25+ / $30+) | 70 / 80 "seamless loops" at 5 speed bands (idle, low, mid, high, very high), plus transitions | "personal use and one commercial project" [SNIP] | — | Speed bands, not rpm-stamped; no on/off load mentioned [SNIP] | Generic engines, not V12. Recorded or synthesised is not stated. |
| 13 | OpenGameArt **domasx2, "racing car engine sound loops"** | Six loops that differ "only in pitch", cut from a public-domain start-up recording | **CC0** [PAGE] | WAV, about 55 to 76 KB each | Not a bank | Low quality ("very quiet", per a comment). A placeholder only. |
| 14 | OpenGameArt **qubodup, "Car Engine Loop 96kHz 4s"** | A 4 s loop, estimated by a commenter as a 4-cylinder at about 7,470 rpm | **CC-BY 3.0 / GPL 2 / GPL 3** [PAGE] | WAV 96/24 + 44.1/16 | One loop | Not V12. Placeholder only. |

### 2.2 Why the procedural route ranks first, ahead of the real L539

- Only engine-sim gives **every** loop the bank needs, from one consistent source and under
  licences we fully control:
  - steady on-load, steady off-load and part-load, at any rpm;
  - the limiter;
  - idle;
  - cold start.
- The free GDC ramp and pass-bys are real and the right engine, but too few to build a bank.
- The paid 2014 library is the best real material, but it costs money, which is the owner's call,
  and it needs a day or more of editing. Its "STEADY RPMS" takes were recorded while driving, so
  load and rpm drift [INF].
- Greg Hill, who records engines for racing games, says granular reconstruction can sound "pretty
  synthetic". He prefers crossfaded loops cut from steady and ramp recordings
  (designingsound.org, 2014) [PAGE]. The ranking therefore holds only until the owner judges
  engine-sim's L539 by ear. If it fails that test, rank 3 becomes rank 1.

### 2.3 What Freesound actually holds (exact queries, 2026-10-27)

| Query | Results | Useful |
|---|---|---|
| `aventador` | 0 | none |
| `lamborghini` | 16 (10 CC0, 5 CC-BY, 1 CC-BY-NC) | Gallardo and Huracán revs and starts; kevp888's Paris sports-car pass-bys (CC-BY 4.0, 48/24) |
| `v12` | 57,464, mostly noise | djbono's Ferrari 456 (Sampling+); monsteruno "V12 Formula One Engine.mp3" (licence not checked) |
| `supercar` | 35 (31 CC0) | V8 Supercar fly-bys; Goodwood trackside (richwise) |
| `car engine loop` | 92 | Idle loops from ordinary cars only |
| `engine rpm loop`, `rpm loop`, `engine on load` | 9 / 28 / 0 | No car rpm banks |
| `dyno` | 80 (76 CC0) | **"The Dyno Sessions: 190E"** by Chippy569: 64 CC0 files from Track Time Audio of a Mercedes 190E 2.3-16V, a 4-cylinder. The pack page shows only horn, door and start files. GT-86 dyno runs (dezoris). |
| `ferrari` | 43 | 340 America, 355 underhood (enginemusic), F456 |

So Freesound helps with secondary layers (section 3), but not with the engine bank.

---

## 3. Ranked shortlist (b): secondary layers

"Roblox PSE" means the free-to-use **Pro Sound Effects** catalogue already in the Roblox Creator
Store (suffix "(SFX)"). It needs no upload, and its asset ids come from the public toolbox search
API (section 8).

| Layer | 1st choice | 2nd | 3rd / procedural | Notes |
|---|---|---|---|---|
| **Tyre skid (beyond the limit)** | Sonniss GDC 2018, Pole Position **"Skids & Screeches Tarmac"**: `t4 exterior skidding in circles`, `t3 exterior skidding wet tires` [LIST]; GDC licence | Freesound **audible-edge, "Chrysler LHS tire squeal 01-04"** (71736 to 71739): **CC0**, 96 kHz/24-bit mono, 11 to 150 s, Rode NTG2, rated "A", 9.6 k downloads [PAGE] | Roblox PSE `Vehicle Skids Long Heavy Tire Squeal 1-4 (SFX)` 9120399080 / 9120399166 / 9120399077 / 9120399191 | Loop a steady squeal section. Pitch and volume follow slip speed; brightness follows load [INF]. |
| **Tyre scrub (near the limit)** | Built from the skid loop: low-passed, lower pitch, low volume, faded in by slip angle before the peak [INF] | Roblox PSE `Tire Chirp Engine Car In Short Punchy Skids (SFX)` 9126103903 for chirps | — | ACC treats scrub and skid as separate logic (01 note). No clean free "scrub" recording found. |
| **Tyre rolling / road (dry)** | Sonniss GDC 2023 **"Kia Niro Hybrid - t11 - ONBRD - STEADY RPMS - ELECTRIC"** [LIST]. An electric-mode onboard drive carries almost only tyre, road and wind noise [INF]. GDC licence. | Roblox PSE `Tires Constant On Bridge 1/2 (SFX)` 9112887000 / 9112887004 (loops) | GDC 2026 InMotionAudio "Car Interior Driving Ambience" (includes engine) | Two surface variants (smooth, coarse); speed drives pitch and volume. |
| **Tyre rolling (wet hiss)** | Freesound **Breviceps, "Passing Car (Wet road)"** (462862): **CC0**, 48/16 stereo, 5.8 s, about 100 km/h [PAGE] | Freesound **TimoSchmied, "Car Drive By Fast"** (530965): **CC-BY 4.0**, 48/24 stereo, 11 s, Zoom H5 [PAGE] | Sonniss GDC 2018 Soundholder "Cars In Motion": `Jeep ... wet asphalt passby 50kmph` [LIST] | Make a loop from the hiss under the pass-by, plus a filtered-noise bed scaled by speed × wetness [INF]. |
| **Spray / puddles** | Freesound **Milkybread, "Cars running over puddles"** (830376): **CC0**, 44.1/16, 2:22, DR-40X [PAGE] | Freesound Robinhood76 "fast car starting on wet road" (588720) [NV licence] | — | Cut 4 to 6 one-shots. Codex owns the spray VFX; the sound keys off the same telemetry. |
| **Rain on the car (interior)** | Sonniss GDC 2018 **"Rain INT_Car C4 - Front seat"** [LIST] | Sonniss GDC 2026 Jake Fielding "Interior Wind Rain and Storms": `Heavy Rain on Window, Constant` [LIST] | Freesound eRobb4 "Hard Rain in Moving Car.wav" (344464) [NV licence] | A loop for the cabin bus only. |
| **Wind** | **Procedural:** band-passed noise whose centre and level rise with airspeed, in two flavours (cabin: darker, quieter; exterior). No licence question. [INF] | Sonniss GDC 2026 Epic Stock Media `WINDInt_Loop Weather Wind Whipping Constricted Flow Turbulent 01` and 344 Audio "Extreme Winds" [LIST] | Roblox PSE `Barstow Wind Light Blustery Low Howl 1-3 (SFX)` 9113286782 / 9113286969 / 9113287001; `Rumble Ambience Interior Wind Turbo Shaft (SFX)` 9118747525 | Freesound WaveAdventurer F-150 highway (254873) is **CC-BY-NC 4.0**, FLAC 44.1/16, 45 s, "loops well" [PAGE]: acceptable now, but carries engine and traffic. |
| **Transmission whine** | **Procedural:** a narrow-band tone at the gear-mesh frequency (shaft rpm/60 × teeth). Its level follows drivetrain torque, and the pitch is fixed per gear ratio. The SVJ tooth counts are unknown, so tune by ear [INF]. | Sonniss GDC 2020 Rock The Speakerbox "Gearbox" (4 files) [LIST] | GDC 2023 "Allison Gearbox 6000 - STEADY RPMS - GEARBOX mic" [LIST] (a truck gearbox, wrong character) | Keep it subtle; it is mostly audible on overrun and in reverse. |
| **Gearshift mechanics (ISR clunk, paddles)** | The **gearshift** takes of the paid 2014 library (`t4 ONBRD GEARSHIFTS`, interior mic) [LIST] | Sonniss GDC 2026 344 Audio "Car Foley Vol. 1" and GDC 2020 "Car Interiors" (Sounds Great) [LIST] for clicks and switches | — | The paddle click is a small one-shot; the clunk is a low thump on engagement. |
| **Suspension thumps / kerbs** | Roblox PSE `Botts Dots 1-6 (SFX)` 9113558300 and others (bump thunks) | Freesound jorickhoofd "peugot 206 car interior ... suspension and tire squeek bumping" (176641) [NV licence] | Procedural low thump (a damped 40 to 80 Hz sine burst) triggered by damper-velocity spikes [INF] | Separate light and heavy sets; a kerb-rumble loop from the Botts Dots set. |
| **Brakes** | Roblox PSE `Vehicle Brake Squeaks Ronks 6 (SFX)` 9120367386 | — | — | Optional. Carbon-ceramic brakes are mostly quiet [INF]. |

---

## 4. Looked at and excluded

| Source | Why it is out |
|---|---|
| Roblox Creator Store community uploads named `ks_lamborghini_huracan_performante...`, `lamborghini_aventador_svj_gintani_redd_spec`, `gb_lamborghini_aventador_sv`, `amr_eng_acc_4756`, `SVJ EngineLow` (119404279673406), and others | The names follow Assetto Corsa and mod sound-bank folders, which points to audio ripped from games. Banned by the owner's rule. These assets are also private to their uploaders. |
| Pixabay "Lamborghini Aventador SVJ Racing Sound effect" (mizanstock), "Lamborghini Urus Racing Sound Effect" | Provenance not stated. Pixabay's other Lamborghini items are `freesound_community` mirrors of Freesound uploads, so use the Freesound originals, which carry the licence. |
| GTA V / FiveM "Lamborghini Aventador (L539 V12) Engine Sound" | Built from Forza Horizon 3 and GT Sport audio [SNIP]. Game rip. |
| The owner's reference video `LAMBORGHINI AVENTADOR SVJ _ Assetto Corsa.mp4` | Game audio, possibly modded (05 note). Feel reference only. |
| YouTube | Reference listening only (section 9). |
| BBC Sound Effects (RemArc) | Licensed for "personal, educational or research purposes" [SNIP]. A public Roblox experience is likely outside that scope, even when non-commercial. Commercial use goes through Pro Sound Effects. I could not fetch the licence page or search the catalogue for this car [NV]. |
| Pole Position SVJ 2019, Sounding Sweet Aventador | Aftermarket and straight-pipe exhausts (section 2.1). Keep them in mind only if the owner ever wants a "tuned" sound. |
| Sound of Italy "Italian Cars" ($86) | Has Aventador SVJ exterior drives, revs and three cabin drives, but no steady-rpm or ramp takes [PAGE]. Fine for one-shots, weak for a bank. |
| Wwise / FMOD granular middleware (Crankcase REV, AudioMotors) | Runtime engines that cannot run inside Roblox. Pre-rendering loops through them depends on their licence [NV]. |

---

## 5. Procedural route in detail

### 5.1 engine-sim (AngeTheGreat)

**What it is.**
- A physics simulation that **generates engine audio from the simulated gas flow**.
- Repo `ange-yaghi/engine-sim`: MIT, 9.6k stars [PAGE]. The README says it "currently only builds
  on Windows" (CMake, SDL2, SDL2_image, Boost, Flex and Bison, Visual Studio) [PAGE].
- The newest binary moved to `Engine-Simulator/engine-sim-community-edition` (v0.1.14a). That repo
  says the project "is no longer open source" and is "no longer actively maintained", being
  replaced by a newer version [PAGE]. No licence is stated for that binary.
- **Use the MIT source build** so the tool's terms are clear.
- My reading of the licence: the audio it renders is our own output; MIT covers the code [INF].

**Can it do a V12? Yes.**
- `assets/engines/atg-video-2/` contains `11_merlin_v12.mr` and `12_ferrari_412_t2.mr` [PAGE].
- The 412 T2 script is a full 12-cylinder description [PAGE]:
  - two banks `b0`/`b1` at ±37.5°;
  - six rod journals at 0/120/240/240/120/0°;
  - 12 ignition wires with explicit firing angles;
  - `redline`, `rev_limit`, `limiter_duration`;
  - per-exhaust `length`, `impulse_response: ir_lib.minimal_muffling_01`, `audio_volume`;
  - per-cylinder `sound_attenuation`;
  - `simulation_frequency: 5000`.

**What to change to make it an L539.**

| Parameter | 412 T2 value | L539 / SVJ value | Source |
|---|---|---|---|
| Bank angle | 75° (`(75 / 2.0) * units.deg` per bank) | **60°** (±30°) | 02 note E1 |
| Bore × stroke | 86 × 43 mm | **95.0 × 76.4 mm** | 02 note E3 |
| Firing order | 1 12 5 8 3 10 6 7 2 11 4 9 (script comment) | **1-12-4-9-2-11-6-7-3-10-5-8** | Wikipedia, LP700-4 [SNIP]. Lamborghini's cylinder numbering convention must be checked before mapping wires. |
| Firing interval | 60° crank (12 cylinders in 720°) | 60° crank, even fire [INF] | — |
| Redline / limiter | 18,000 / 18,500 | **8,500 power peak, 8,700 fuel cut** | 02 note E9 |
| Idle | idle flow and throttle-plate settings | about 950 rpm warm, 1,200 cold (estimated) | 02 note E10, to calibrate from the stock idle video (section 9) |
| Exhaust | 20 and 56 inch, minimal muffling | Short, high, central, lightweight titanium system with two outlets and a mode valve | 02 note 2.13. Pick an IR by ear against the references. |
| Rod length, cam timing, flow tables | race values | Not published | Estimate. Then judge by ear and by spectrum, not by spec. |

**The recording rig is built in** [CODE, `engine_sim_application.cpp`, `dynamometer.cpp`, `es/objects/objects.mr`]:
- `D` turns the dyno on. With hold off, the dyno ramps up at **500 rpm per second** until the
  redline. That is a ready-made full-throttle **on-load ramp**.
- `H` is hold. `G` + scroll moves the hold speed by `dyno_hold_step`, default **100 rpm**, between
  `dyno_min_speed` (default 1,000 rpm) and `dyno_max_speed` (default the redline).
- In hold mode, the dyno torque limit is ±`m_maxTorque` (10,000 lb-ft), **in both directions**.
  - At full throttle it brakes the engine at the set rpm: **steady on-load**.
  - With the throttle shut it drives the engine: **steady off-load (overrun)**.
  - Without hold it only absorbs torque.
- Throttle: `Q`/`W`/`E`/`R` set fixed throttle positions, and `Space` + scroll fine-tunes. So a
  **part-load "maintain"** layer (say 20 to 30 % throttle) can be recorded for real, rather than
  blended from on and off. Greg Hill notes that in most games "steady load is usually a subtle
  blend" of the two [PAGE].
- Ignition `A` and starter `S` give the start and shutdown. Holding the throttle with the dyno off
  gives the limiter bounce (`rev_limit`, `limiter_duration`).
- The UI also exposes volume, convolution level, high-frequency gain, low- and high-frequency
  noise, and simulation frequency (`Z`/`X`/`C`/`V`/`B`/`N` + scroll). **Freeze all of them before
  the first take** and never touch them between takes. A changed setting mid-bank creates seams
  that crossfading cannot hide [INF].

**Its limits, all inferred** [INF]:
- It renders the exhaust through convolution. There is no separate intake roar, valvetrain or
  gear noise, and no cabin perspective.
- No afterfire or overrun pop modelling was found.
- It is mono-ish.
- So the **interior** bank must be built by processing (low-pass, cabin resonance, a mid-engine
  intake emphasis) plus real texture layers (section 6).

**Capture.** There is no export button. Capture the system output by WASAPI loopback, for example
Audacity's "Windows WASAPI" host with loopback, at **44.1 kHz** to match the render rate [CODE].
Do not resample up. Roblox accepts up to 48 kHz (section 8).

### 5.2 Other synthesis options

- **DasEtwas/enginesound:** MIT, 385 stars. Exports mono WAV at a fixed rpm, with built-in
  `--crossfade` for seamless loops and `--warmup` so the acoustic chambers settle first [PAGE].
  It is the simplest batch tool for fixed-rpm loops, but its realism is lower and V12 support is
  unverified. Backup only.
- **Granular** (Crankcase REV, AudioMotors): splits a ramp into single combustion cycles and
  replays them at any rpm [PAGE designingsound / MCV]. It needs a per-sample scheduler. In Roblox
  that would mean many `AudioPlayer:Play(atTime)` grains a second, so it is not recommended for v1
  [INF].
- **combustionlab.net** (a web engine simulator on Hacker News in 2026): HN comments suggest it
  has no sound yet [PAGE]. Not useful.

### 5.3 How racing games build the engine (so our bank matches practice)

- **Loops crossfaded by rpm and load are still the norm.** In Greg Hill's words, "Most of the
  cross-faded engine sounds in games today have on-load and off-load looped samples"; recording
  uses on-load ramps from low to high rpm and off-load ramps from high to low (Game Developer,
  2002) [PAGE].
- **Project CARS** uses "well over one hundred separate wave files" per car and crossfaded layers.
  Its "Helmet Cam" mainly applies comb and low-pass filtering for the interior (designingsound.org,
  2014) [PAGE].
- **Forza Motorsport 5** drives FMOD Studio from rpm (separately for engine, turbo and
  transmission), throttle, engine load, torque, clutch and gear, with different on- and
  off-throttle character [PAGE].
- **Fixed-rpm loops need "quite a few recordings"** because simple pitch shifting degrades quickly
  (AudioMotors / MCV, 2016) [PAGE].
- **Assetto Corsa** ships an FMOD audio pipeline in its SDK. A modder ties on-throttle loudness to
  torque and off-throttle to friction, which "gets louder with higher rpm" [SNIP].

---

## 6. Recommended production route

### 6.1 Route, in order

1. **Build the L539 in engine-sim from source** (MIT), from `12_ferrari_412_t2.mr` with the table
   in 5.1.
2. **Validate before recording anything.** Use the same spectrogram method as
   `video_analysis/engine_order_track.py`:
   - a V12 fires at rpm/10 Hz; the reference showed orders 3, 6 and 12 (05 note);
   - compare engine-sim at 4,000, 6,000 and 8,000 rpm against the free GDC Aventador ramp and the
     stock-SVJ videos (section 9);
   - adjust exhaust lengths, IR and per-cylinder attenuation until the order balance matches.

   The owner signs off by ear.
3. **Record the bank** with dyno hold (asset list in 6.3). Give each hold 10 to 15 s; discard the
   first 2 s.
4. **Cut the loops to whole engine cycles.**
   - One four-stroke cycle is 2 revolutions, so 120/rpm seconds: 30 ms at 4,000 rpm, 14 ms at
     8,500.
   - A loop of N whole cycles, cut at zero crossings, repeats without a phase jump and keeps a
     clean pitch [INF].
   - Aim for 2 to 4 s per loop. Use a short crossfade at the seam if needed.
5. **Make the interior bank from the exterior takes:**
   - low-pass at about 2 to 4 kHz;
   - a low-mid lift;
   - a mild comb or cabin resonance, as Project CARS does;
   - an intake and mechanical texture layer from real recordings: the GDC F12, DB9 and LFA engine
     and intake mics, or the paid 2014 library's intake L/R if bought.

   Then compare against the same-car interior/exterior pairs in section 9.
6. **Use real recordings for the events and the world:**
   - the GDC Aventador pass-bys as exterior distance one-shots;
   - the skid, wet, rain and puddle sources from section 3;
   - procedural wind and gearbox whine.
7. **Upgrade path, the owner's decision:** buy the Pole Position *Aventador 2014* library.
   - Its `STEADY RPMS` / `RAMPS` / `GEARSHIFTS` / `IDLE` takes with exhaust, engine, intake and
     cabin mics would replace the engine-sim exterior bank and give a real interior bank.
   - Same cutting method. Check its EULA's game clause first.

### 6.2 Licence status of the route

| Part | Licence | Attribution needed | Commercial-safe |
|---|---|---|---|
| engine-sim recordings | Our output; tool under MIT | None needed. A thank-you credit to AngeTheGreat is courteous. | Yes |
| GDC bundle files (Aventador ramp and pass-bys, skids, rain, wind, Kia EV) | Sonniss GDC licence | None | Yes. No resale as SFX, no AI training. |
| Freesound CC0 (audible-edge, Breviceps, Milkybread, florianreichelt) | CC0 | None (credit is courteous) | Yes |
| Freesound CC-BY 4.0 (TimoSchmied, kevp888, JaimeLopes) | CC-BY 4.0 | **Yes**: in-game credits with author, title, link, licence and "modified" | Yes |
| Freesound CC-BY-NC (WaveAdventurer) / Sampling+ (djbono) | NC / Sampling+ 1.0 | **Yes** | **No.** Swap out before any monetisation; keep the place non-earning (section 8.4). |
| Roblox PSE "(SFX)" | Roblox Creator Store, "free-to-use" on Roblox | None stated | Yes, inside Roblox only |
| Pole Position *Aventador 2014* (if bought) | Royalty-free; seat count chosen at checkout | Per EULA [NV] | Expected yes; read the EULA |

Keep `audio/CREDITS.md` (or an equivalent) beside the asset ids. Each line: source URL, author,
licence, modified (yes/no), Roblox asset id. That file is what makes the upload attestation true.

### 6.3 Asset list for v1

The rpm steps are spaced **geometrically**, about +18 % per step. With equal-power crossfades no
loop is pitched more than about ±9 % (≈ ±1.5 semitones). That keeps the exhaust resonances from
audibly sliding with pitch, which is the "single loop pitched with speed" failure the owner rules
out [INF].

**Engine loops.** Fourteen rpm steps: 1,000 · 1,200 · 1,400 · 1,650 · 1,950 · 2,300 · 2,700 ·
3,200 · 3,750 · 4,450 · 5,250 · 6,200 · 7,300 · 8,500.

| Bank | Load | Steps | Perspective | Count |
|---|---|---|---|---|
| Exhaust / exterior | On-load (100 % throttle, dyno hold) | 14 | Exterior | 14 |
| Exhaust / exterior | Part-load "maintain" (about 25 %) | 14 | Exterior | 14 |
| Exhaust / exterior | Off-load (0 %, dyno motoring) | 14 | Exterior | 14 |
| Cabin | On / part / off | 14 each | Interior (processed + texture) | 42 |
| Idle | Warm idle about 950, cold fast-idle about 1,200 | — | Both | 4 |
| Limiter | Bounce loop at 8,700 | — | Both | 2 |

That is **90 loops**: mono for the exterior (it goes through an emitter), stereo for the interior.
A lighter first pass:
- **8 steps:** 1,000 · 1,450 · 2,100 · 2,900 · 3,900 · 5,100 · 6,600 · 8,500, about +35 % per
  step;
- **2 loads:** on and off;
- **2 perspectives**;
- total **32 loops**, plus idle and limiter.

**Engine one-shots.**

| Event | Variations | Perspective | Source |
|---|---|---|---|
| Starter + cold-start flare (about 1,200, settling to about 950) | 2 | Both | engine-sim (`S`, `A`) + the stock cold-start videos for timing |
| Shutdown | 2 | Both | engine-sim |
| **Upshift cut** (the ISR ignition cut, a "crack" in Sport/Corsa) | 4 to 6 | Both | engine-sim ignition toggle at high rpm, plus a pop layer. Duration from the drivetrain model (the 02 note gives "up to 50 ms" for the Aventador S; 05 measured an rpm fall of 8,330 → 6,830 over about 0.3 s in the reference). |
| **Re-engage clunk** (single-clutch "head nod") | 3 | Interior (exterior faint) | Paid 2014 library `GEARSHIFTS`, or foley |
| **Downshift blip** (throttle blip to the target rpm) | 4 | Both | engine-sim with a quick throttle tap and the dyno off |
| **Overrun pops / crackle** (short) | 10 to 12 | Exterior louder | **Real-recording gap.** Freesound klankbeeld "car pass by - afterfire crackle" (873008) and JustInvoke "Backfire" (446101), licences not checked [NV]; or designed from noise bursts. Timing follows the 05 measurement: pulse trains of 150 to 380 ms. |
| Lift-off afterfire train | 3 | Exterior | As above, sequenced as pulses |
| Paddle click (up / down) | 2 + 2 | Interior | GDC "Car Interiors" / 344 Audio "Car Foley" |
| Reverse-gear whine | 1 loop | Both | Procedural |

**Secondary layers.**

| Layer | Loops | One-shots |
|---|---|---|
| Tyre rolling dry | 2 surfaces | — |
| Tyre rolling wet hiss | 1 | — |
| Tyre scrub | 1 | — |
| Tyre skid | 2 (dry, wet) | 3 chirps |
| Wind | procedural (or 2 loops: exterior, cabin) | — |
| Transmission whine | procedural (or 1 loop) | — |
| Rain on the car (cabin) | 1 | — |
| Kerb rumble | 1 | — |
| Suspension | — | light × 3, heavy × 3 |
| Puddle / spray | — | 4 to 6 |
| Brake squeal | optional 1 | — |

**File specification.**
- **OGG Vorbis** (or WAV), never MP3. MP3 encoder padding clicks at every loop seam (section 8.3).
- 44.1 kHz for engine-sim material, ≤ 48 kHz for everything else.
- Name files like `eng_ext_on_4450.ogg`. Put the sample rpm in the file name: the code computes
  `PlaybackSpeed = rpm / sampleRpm` from it.

---

## 7. What a Roblox implementation can do (the API side, for the engine design)

Full API facts are in `04_roblox_engine_facts.md` §7.3. What matters for this bank:

- **Pitch:** `AudioPlayer.PlaybackSpeed` from 0 to 20 sets speed and pitch together; there is no
  separate pitch control [DOC]. Per loop, `PlaybackSpeed = rpm / sampleRpm`.
- **Synced layers:** `Play(atTime)` / `Stop(atTime)` are scheduled on the mixer clock
  (`GetMixerTime()`), "sample-accurate", so every layer of a bank can start together [DOC].
  Crossfaded rpm loops do not need phase lock with each other; layers of the same take do
  (exhaust, engine and intake from one paid-library take).
- **Crossfades:** per-layer `Volume` (0 to 10). Use equal-power curves between the two loops around
  the current rpm, and across on/part/off by an engine-load value. Load comes from engine torque
  over full-throttle torque at that rpm, smoothed over about 50 to 100 ms, so a lift snaps to
  off-load fast and re-application is slightly smoothed [INF].
  - **There is no `AudioCrossfader`**, so the crossfade is script math (04 note).
  - Ramp volumes every frame, never step them. The docs say nothing on parameter smoothing, so
    listen for zipper noise [DOC/INF].
- **Groups:** one `AudioFader` per load group and one per perspective. The camera-mode switch fades
  perspectives over about 150 ms [INF].
- **Interior muffling:**
  - `AudioEqualizer`: 3 bands, gains −80 to +10 dB [DOC];
  - `AudioFilter`: low-pass or shelf, 20 to 22,000 Hz, `Q` 0.1 to 10, ±30 dB [DOC].
  - That is enough for the cabin low-pass and shelf.
- **Space:** `AudioEmitter` on the exhaust and engine attachments.
  - `SetDistanceAttenuation` takes up to 400 points; `SetAngleAttenuation` gives directional
    exhaust falloff [DOC].
  - The interior bank goes to the output non-spatially (or through an emitter at the driver's
    head).
  - **No Doppler** in the new API (`DopplerScale` does not affect it). Compute it into
    `PlaybackSpeed` for exterior views [DOC].
- **Voices:** no documented cap on concurrent `AudioPlayer`s [COMM]. Play only the loops whose
  gain is above a threshold, which is at most 2 rpm × 3 loads per perspective, so about 6 to 8
  live engine voices. Start the others on demand at a random `TimePosition` [INF].
  - Add a device voice and CPU test to the Studio test list (T-series in the 04 note).
- **Telemetry the audio needs from the physics** (Claude publishes, audio consumes):
  - rpm, throttle, engine torque (load sign), gear, clutch state;
  - shift events (cut start, engage);
  - limiter state;
  - per-wheel slip ratio, slip angle and contact load;
  - wheel speed, vehicle speed, surface wetness;
  - per-corner damper velocity;
  - camera mode;
  - drive mode (the exhaust valve opens earlier in Corsa, per the 02 note).

---

## 8. Roblox audio constraints

(Researched 2026-10-27 from create.roblox.com docs, DevForum posts and the public toolbox API.)

### 8.1 Uploads [DOC create.roblox.com/docs/audio/assets unless marked]

- **Formats:** `.mp3`, `.ogg`, `.wav`, `.flac`, each a single track. OGG means **Ogg Vorbis**;
  users report that other OGG codecs fail, and that Roblox transcodes everything [COMM].
- **Limits:** "less than 20 MB in size and 7 minutes in duration".
  - Sample rate **≤ 48 kHz**.
  - Channels: mono, stereo, 3.0 or 5.1.
  - Studio transcodes on import; the bitrate is not documented.
- **Quota and cost:**
  - Free.
  - ID-verified accounts: **2,000 audio assets per 30 days**. Unverified: 100.
  - Distribution to the Creator Store has a lower cap (100 / 10) and needs age or ID
    verification.
  - Free uploads date from 2022-03-09.
- **Rights attestation:** importing requires confirming "You have the legal rights to that audio
  asset". Every upload is moderated, with no published turnaround (DevForum threads report audio
  stuck in review).
- **Privacy:**
  - Since 2022-03-22, new audio is **private by default**.
  - Private audio plays only in experiences "uploaded by the same user or Group that created the
    experience". Other experiences need a permission grant, which "cannot be revoked".
  - Without a grant, the audio does not play at runtime and Studio logs an error.
  - The Asset Privacy toggle does not apply to audio.
  - **Our case:** the Drive Lab place is group-owned, so **upload the bank as that group**, or
    grant the universe each asset.

### 8.2 Creator Store audio

- Roblox lists ">100,000 sound effects and music tracks" as **free-to-use** [DOC]. Partners at the
  2022 launch: APM, Monstercat, **Pro Sound Effects** (the "(SFX)" assets), Nettwerk and Position
  Music [ANN].
- Licensed content "can only be used on the Roblox platform" [SNIP; help page 403].
- **No rpm-stamped engine loops from a partner were found.** PSE car material is whole
  performances, for example:
  - `1969 Chevrolet Chevelle Convertible 1 (SFX)` 9112734366, 56 s;
  - `Hot Rod Fast Maneuvers 13 (SFX)` 9114831818.
- PSE skids, tyre rolling, wind, Botts Dots and brake sounds are listed in section 3.
- One generic `Car-Engine-Loop` (80317022777602, 9 s) comes from the verified group "Roblox
  Resources" and is marked public domain.
- Community "Lamborghini" / "SVJ" engine uploads look game-ripped (section 4).

### 8.3 API notes specific to engine loops

- **Upload loops as OGG, not MP3.** A Roblox sound designer's staff tutorial (2024-02-26) says MP3
  adds "a few milliseconds of silence to the beginning", which clicks on every loop; OGG "will
  loop seamlessly". Cut at a zero crossing on both channels.
- `LoopRegion` / `PlaybackRegion` are in seconds. `IsReady` can drop to false "under extreme memory
  pressure". `AutoLoad = false` defers loading. Consider loading the cabin bank only when the
  cockpit camera is used.
- Legacy `Sound` has built-in Doppler, `SoundGroup` and `EqualizerSoundEffect`, but no graph. The
  new API remains the route (04 note).

### 8.4 Non-commercial licences on Roblox: the risk that remains

- **Robux can accrue without any monetisation.** Since 2025-07-24, Creator Rewards covers "All
  experiences on Roblox that meet our Community Standards/Terms"; no opt-out was found [ANN].
  - A **public** Drive Lab could earn Robux, which strains an NC licence.
  - **Keep the place private** (or friends-only) as long as NC or Sampling+ assets are in it.
- **Licence chain.** CC 4.0 is non-sublicensable. Roblox's Terms take a broad licence to uploaded
  content; I could not fetch the verbatim clause [NV].
  - Uploading any CC material arguably grants Roblox more than the uploader holds. This applies to
    CC-BY too, not only NC.
  - The risk is low for a private showcase and grows if the place goes public.
- This is why the recommended core (engine-sim, GDC, CC0) avoids NC assets entirely. Only optional
  extras carry NC terms.

---

## 9. Reference listening (analysis only, never assets)

**These are for listening only.** No YouTube audio and no game recording (Assetto Corsa, Forza
mods) may be used as an asset. Use them to time shifts, read rpm off the spectrum
(firing frequency = rpm/10 Hz) and judge tone.

**Timestamp tags:**
- `[CH]` a chapter set by the uploader;
- `[DESC]` the video description;
- `[COM]` a viewer comment (a lead, not a fact);
- `[NV]` not verified, scan the video.

Titles, dates and lengths come from the public watch pages, fetched 2026-10-27. Transcripts could
not be read.

**Stock exhaust, three levels:**
- **Stated:** the uploader or Lamborghini says so, or it is the factory car.
- **Inferred:** a press or dealer car.
- **Unknown.**

### 9.1 Onboard full-throttle pulls (shift timing, rpm drop)

| Video | Channel, date, length | Stock? | Useful moments |
|---|---|---|---|
| [Aventador SVJ Nürburgring record lap, full onboard](https://www.youtube.com/watch?v=QRsq35Et-EY) | **Lamborghini (official)**, 2018-07-26, 6:55 | **Stated:** the factory record car (on optional Trofeo R tyres) | 0:16 a messy shift [COM]; 3:21 5th→6th at high rpm [COM]; 5:32 about 254 km/h [COM]. Many full-throttle upshifts and braking downshifts [NV]. **Best stock source for the ISR gap and the rpm drop per gear.** |
| [SVJ launch control 0-270 km/h](https://www.youtube.com/watch?v=2Puv6q1H7Yo) | Motorsport Magazine (FR), 2018-10-19, 1:04 | Inferred (press car) | Launch about 0:30-0:35 [COM], then a continuous pull [NV]. A commenter: "why do the shifts seem so lazy", which is the single-clutch character. |
| [SVJ Roadster 0-100, ¼ mile, 100-200, 0-250, Autobahn POV](https://www.youtube.com/watch?v=xtZj5rxNBxA) | AutoTopNL, 2022-03-01, 9:15 | Inferred (comments: "just needs that Gintani") | 0:00 POV [CH]; 2:24 exterior exhaust [CH]; 4:22 GPS runs [CH]; 5:42 Autobahn POV [CH] |
| [770 HP SVJ review + Autobahn](https://www.youtube.com/watch?v=se1fHX148As) | Moscarblog, 2024-03-19, 11:58 | Inferred | 3:26-3:51 soundcheck [CH/DESC]; 4:31 B-road [CH]; 6:46-11:58 Autobahn POV [CH/DESC] |
| [Throttle House SVJ review](https://www.youtube.com/watch?v=O6pzSeQlSbY) | 2020-02-12, 17:39 | Unknown (press car; music in places) | 3:59 driving [CH]; 4:31 hard shift [COM]; 5:20 upshift [COM]; 7:15 loud pass [COM]; 10:43 exterior [CH] |
| [Autotrader (Rory Reid) SVJ review](https://www.youtube.com/watch?v=MRs0PSM6Ffs) | 2020-09-25, 12:26 | Unknown | 3:08 driving [CH]; 4:23 / 4:30 full-throttle shifts [COM]; 7:13 track [CH]; 10:50 V12 pass [COM] |

### 9.2 Exterior pass-bys and revs

| Video | Channel, date | Stock? | Useful moments |
|---|---|---|---|
| [SVJ - LOUD Revs & Engine SOUNDS!](https://www.youtube.com/watch?v=eAAvR1U56K8) | cvdzijden, 2019-03-31, 4:00 | Inferred: a commenter says "This has a stock exhaust" | 1:12, 1:28, 2:35, 3:22 revs and pull-aways [COM] |
| [SVJ - Full Throttle Exhaust Sounds on Track!](https://www.youtube.com/watch?v=CfUi8jZj2f0) | Gumbal, 2020-11-01, 6:49 | Unknown | Track pass-bys under load [NV]. Use with care until the exhaust is confirmed. |
| [The BEST STOCK SVJ Drive](https://www.youtube.com/watch?v=rLK_Yey4atk) | Ishaaq Vlogs, 2025-07-04, 9:48 | **Stated:** "completely stock" (description) | POV and pull-aways [NV] |
| [SVJ Exhaust Sound! REVS & LOUD Acceleration!](https://www.youtube.com/watch?v=vG3aqkEh99w) | HubraumTV, 2019-07-05, 1:55 | Unknown | Revs, one hard acceleration [NV] |

### 9.3 Cold start and idle

| Video | Channel, date | Stock? | Useful moments |
|---|---|---|---|
| [SVJ w/ Fi exhaust vs Stock Sound Comparison](https://www.youtube.com/watch?v=k1AVM9boun0) | FiExhaust, 2021-05-07, 1:56 | **Stated: 0:00-0:50 is the factory exhaust** | 0:00-0:50 stock idle [CH/DESC]; 0:50-1:55 aftermarket [CH/DESC]. **Best stock idle reference, with an A/B built in.** |
| [LOUD SVJ Cold Start](https://www.youtube.com/watch?v=W3R0FGE9tuM) | SytnerGroup (UK dealer), 2021-01-13, 0:35 | Inferred (dealer car) | The whole clip: start flare, then fast idle [NV] |
| [SVJ Roadster POV Test Drive (3D Audio)](https://www.youtube.com/watch?v=WGxsZjy73VQ) | MilesPerHr, 2020-06-12, 21:29 | Inferred (test car) | 1:21-1:22 start-up from the cabin [COM]; read idle rpm off the tachometer after it [NV] |

### 9.4 Downshifts, overrun, pops

| Video | Stock? | Useful moments |
|---|---|---|
| MilesPerHr 3D-audio POV (above) | Inferred | 5:29, 5:47, 6:05 downshifts [COM]; 9:02 [COM]; 12:01 launch [COM]; 13:49 downshift [COM] |
| [SVJ Xago Edition POV binaural](https://www.youtube.com/watch?v=ACfdo_SNa2U) (Tedward, 2021-09-12) | Inferred | 6:54 performance drive [CH]; 9:02 crackles under a bridge [COM] |
| Lamborghini record-lap onboard (9.1) | Stated | Braking downshifts: the cleanest stock overrun reference [NV] |

### 9.5 Interior vs exterior, same car

- **AutoTopNL SVJ Roadster** (xtZj5rxNBxA): cabin at 0:00, exterior at 2:24 [CH].
- **Moscarblog SVJ coupé** (se1fHX148As): exterior soundcheck at 3:26, cabin at 6:46 [CH].
- A Roadster cabin is brighter and louder than the coupé we model, so tune the interior filter
  mainly on coupé material: the record lap and Moscarblog.
- Lamborghini's [SVJ Engine (8D Audio)](https://www.youtube.com/watch?v=fCrXVS2Q9A8) is stock and at
  full throttle, but processed with moving panning. Use it for timbre only.

### 9.6 Excluded as a stock reference (aftermarket or game)

- AutoTopNL "344 km/h" (odly5F8jgTw), which Supercars.net names as Gintani.
- KBH (ZbwhgSfO-NE), Gintani.
- Other Gintani clips: MLbG8Fh2OmE, LYGIcXvRiLI, dMetBiFR-gw, Z5zXDbaX4I0, vX06xrruAXY.
- Novitec pdZHfFKc-EE, Capristo Sd_SKu6ODVU, Balboni 936zt80heiA.
- Game audio: Assetto Corsa 6vpLD01nqK4, Forza mod lwLWwBlSSrU.

### 9.7 What to measure

- **Record lap and Motorsport Magazine launch:**
  - rpm before and after each upshift;
  - the length of the torque-cut gap;
  - whether a pop falls inside it.
- **FiExhaust stock segment:** the idle firing line (so idle rpm) and how steady it is.
- **Interior filter:** compare an exterior segment with the same car's cabin segment by spectral
  tilt and 2 to 5 kHz content, not by loudness.

---

## 10. Decisions and tests for the owner

1. **Buy or not:** the Pole Position *Lamborghini Aventador 2014* library ($249 on A Sound Effect,
   seats chosen at checkout). It is the only real, steady-rpm, multi-mic L539 source found.
   Recommendation: build the free route first, judge engine-sim's L539 by ear, then decide.
2. **NC assets** only while the place stays private / non-earning (section 8.4). The core route
   needs none.
3. **Studio tests to add to the 04 note's T-series:**
   - concurrent `AudioPlayer` count and CPU on a phone;
   - OGG loop-seam check (MP3 as the negative control: it should click);
   - `Volume` ramp zipper check;
   - `PlaybackSpeed` stepping smoothness at 60 fps.
4. **engine-sim build** needs Visual Studio + CMake + SDL2 + Boost + Flex/Bison on this PC. It is
   light at runtime, which suits the limited RAM.

---

## 11. Searches run (for the "not found" claims)

- **Freesound site search:** `aventador`, `lamborghini`, `v12`, `engine rpm loop`,
  `engine on load`, `supercar`, `car engine loop`, `onboard car`, `engine ramp`, `dyno`, `ferrari`,
  `190E dyno`, `car interior acceleration`, `engine loops`, `rpm loop`, `tire squeal`,
  `car wet road`, `backfire exhaust`, `gear whine`, `car interior wind highway`,
  `car suspension bump`.
- **Freesound API:** not used; it needs a token.
- **Pixabay:** `lamborghini`.
- **OpenGameArt and itch.io:** web search for engine loop packs.
- **Sonniss:** GDC track lists 2016, 2017, 2018, 2019, 2020, 2023 (the 2021-2024 sheet exposes only
  2023) and 2026, grepped for car, engine, rpm, steady, ramp, skid, tyre, wind, rain, gearbox.
- **A Sound Effect:** tag `lamborghini`.
- **Sound Ideas:** the Aventador product.
- **Roblox:** toolbox search API, `lamborghini` and `car engine`.
- **GitHub:** ange-yaghi/engine-sim (README, LICENSE, `assets/engines`, the 412 T2 script,
  `engine_sim_application.cpp`, `dynamometer.cpp`, `es/objects/objects.mr`),
  Engine-Simulator/engine-sim-community-edition, DasEtwas/enginesound, GDCorner/engine-sim (a fork
  with no stated additions).

## Sources

- Freesound sound pages:
  - 18771 https://freesound.org/people/djbono/sounds/18771/
  - 43483 https://freesound.org/people/enginemusic/sounds/43483/
  - 457560 https://freesound.org/people/florianreichelt/sounds/457560/
  - 564375 https://freesound.org/people/JaimeLopes/sounds/564375/
  - 585710 https://freesound.org/people/kevp888/sounds/585710/
  - 71737 https://freesound.org/people/audible-edge/sounds/71737/
  - 462862 https://freesound.org/people/Breviceps/sounds/462862/
  - 530965 https://freesound.org/people/TimoSchmied/sounds/530965/
  - 254873 https://freesound.org/people/WaveAdventurer/sounds/254873/
  - 830376 https://freesound.org/people/Milkybread/sounds/830376/
  - Pack 9658 https://freesound.org/people/Chippy569/packs/9658/
- OpenGameArt:
  - https://opengameart.org/content/racing-car-engine-sound-loops
  - https://opengameart.org/content/car-engine-loop-96khz-4s
- Pixabay: https://pixabay.com/sound-effects/search/lamborghini/
- Sonniss:
  - GDC portal https://gdc.sonniss.com/
  - Archive https://sonniss.com/gameaudiogdc
  - Licence https://sonniss.com/gdc-bundle-license/
  - SVJ 2019 listing https://sonniss.com/?p=413406
  - GDC 2026 list https://docs.google.com/spreadsheets/d/1MkoGwA6FfgNXhye9wLnY0gNLvjEp4H2iYXM1YxMI6Qs
  - GDC 2020 list https://docs.google.com/spreadsheets/d/1QqIcxJ7y0Acq3HAj9qQvFgvyeBjJ_7JvX8-GguUHIVk
  - GDC 2019 list https://docs.google.com/spreadsheets/d/1-McgwdktLVmctBrI4OGbgIBxeCp0A4KyKJzxOOTP6FY
  - GDC 2018 list https://docs.google.com/spreadsheets/d/1h_aunO31U1g-QAxYxziSZn22LVe1eyA4o10KEnXKmIc
  - GDC 2021-24 list https://docs.google.com/spreadsheets/d/1HAJdNA-QIug2IZjUV-DwCo1IZ-XJ4Vv9gWIaumNScfc
- A Sound Effect:
  - https://www.asoundeffect.com/sound-library/lamborghini-aventador-2014/
  - File list https://asoundeffect.com/wp-content/uploads/2019/12/Lamborghini_Aventador_Sound_File_List.pdf
  - https://www.asoundeffect.com/sound-library/italian-cars/
  - https://www.asoundeffect.com/product-tag/lamborghini
- Sound Ideas: https://portal.sound-ideas.com/Product/2429/Lamborghini-Aventador-by-Sounding-Sweet
- itch.io (search snippets): https://magicsoundeffects.itch.io/car-engines ·
  https://magicsoundeffects.itch.io/car-engines-vol-2 · https://indiesfx.itch.io/indiesfx-s017c
- engine-sim:
  - https://github.com/ange-yaghi/engine-sim
  - Scripts https://github.com/ange-yaghi/engine-sim/tree/master/assets/engines/atg-video-2
  - https://github.com/Engine-Simulator/engine-sim-community-edition
- DasEtwas: https://github.com/DasEtwas/enginesound
- Practice:
  - Greg Hill, "Capturing Engine Sounds for Games" (2002) https://www.gamedeveloper.com/audio/capturing-engine-sounds-for-games
  - Designing Sound (2014) https://designingsound.org/2014/08/11/vehicle-engine-design-project-cars-forza-motorsport-5-and-rev/
  - MCV / AudioMotors (2016) https://www.mcvuk.com/development/how-to-make-racing-car-engines-roar-using-audiomotors-fmod
  - Audiokinetic loop-based engine series (403 to fetch; seen through search) https://www.audiokinetic.com/en/loop-based-car-engine-design-with-wwise-part-1/
  - AC sound modding guide (snippet) https://assettocorsamods.net/goto/post?id=8266
- Roblox:
  - https://create.roblox.com/docs/audio/assets
  - https://create.roblox.com/docs/projects/assets/privacy
  - https://create.roblox.com/docs/production/creator-store
  - https://create.roblox.com/docs/reference/engine/classes/AudioPlayer
  - https://create.roblox.com/docs/reference/engine/classes/AudioEmitter
  - https://create.roblox.com/docs/reference/engine/classes/AudioEqualizer
  - https://create.roblox.com/docs/reference/engine/classes/SoundService
  - https://devforum.roblox.com/t/creating-perfect-audio-loops/2849057
  - https://devforum.roblox.com/t/1701697
  - https://devforum.roblox.com/t/creator-rewards-is-live/3838257/1
  - https://apis.roblox.com/toolbox-service/v2/assets:search?searchCategoryType=Audio&query=lamborghini
  - https://creativecommons.org/licenses/by-nc/4.0/legalcode.en
- Car facts: `02_aventador_svj_data.md`; Wikipedia "Lamborghini Aventador" (firing order).
- Reference videos: the YouTube links in section 9. Exhaust-status sources:
  https://www.motor1.com/news/700007/lamborghini-aventador-svj-with-f1-exhaust-on-autobahn-video/ ·
  https://lamborghini.com/en-en/history/aventador-svj

---

## Pass 2: quality-only ranking (owner decision, 2026-10-27)

**The decision.** The Drive Lab is a **private** portfolio project. The owner accepts sounds
ripped from games (Assetto Corsa banks, Forza-derived packs, the Roblox Creator Store and Pixabay
SVJ uploads excluded in section 4) and unlicensed sounds. This pass ranks the engine sources only
on:
- **quality** of the recording;
- **fit to our needs:**
  - fixed-rpm on-load and off-load loops, or ramps we can loop;
  - interior and exterior;
  - shift and overrun one-shots;
- **closeness** to a stock SVJ and to the owner's reference video, which is itself Assetto Corsa
  audio (05 note).

**Method and limits.**
- **Creator Store:** I queried the public toolbox API (12 queries, up to 3 pages of 100 each):
  1,767 unique audio assets, of which 193 have SVJ/Aventador in the name. Not exhaustive: the API
  caps each query at 1,000 results.
- **I listened to nothing.** Contents are read from asset names, durations and descriptions
  (mostly just "Audio"). A duration of "0 s" means under one second.
- **Web search** ran out again partway through. The Assetto Corsa mod pages (Modland, Overtake)
  answered 403, so the mod details come from search snippets.
- **Assetto Corsa is not installed on this PC.** The only Steam library is
  `C:\Program Files (x86)\Steam`, and it has no `assettocorsa` folder.

### P2.1 The honest answer: which route gives the best result fastest

**Best result, fastest: decode an Assetto Corsa car sound bank** (FMOD Studio `.bank`) with
vgmstream.
- **Why it fits.** An AC car's engine sound is built for an rpm × throttle crossfade, with
  exterior and interior and on- and off-throttle behaviour. A modder's guide speaks of the
  "on-pedal" and "off-pedal" tracks [SNIP]. So the loops arrive already cut for the kind of engine
  we are building. That removes the slowest step of every other route: finding loop points.
- **The tool.** vgmstream decodes FMOD `.bank` (`fsb5_fev_bank`, subfiles FSB5 or encrypted FSB)
  [CODE, `doc/FORMATS.md`]. The command `vgmstream-cli -S 0 file.bank` "writes from subsong 1 to
  max subsong"; the default output name is `?f#?s.wav` [CODE, `doc/USAGE.md`].
- **Evidence the route works.** The Creator Store uploads named `gb_lamborghini_aventador_sv#170`
  and `ks_lamborghini_aventador_sv [175]` carry that exact subsong numbering. Uploaders have already
  done this with AC Aventador banks holding at least 179 subsongs [INF].
- **Which bank:**
  - **Closest to the reference video:** the bank of the AC SVJ mod used in that video. Ask the
    owner which mod it is; the video title does not say.
  - **Closest to a stock car:** Kunos's own `ks_lamborghini_aventador_sv`, the official Aventador
    SV. It has the same L539 family; the SV is 750 hp against 770, and the SVJ's exhaust differs.
    The `ks_` prefix marks Kunos content. Whether the SV ships in the base game or a DLC was not
    verified.
- **Time** [INF]:
  - an hour or two to decode and sort one bank (tag each subsong as loop or one-shot, rpm, on or
    off, interior or exterior);
  - then the same trimming and OGG export as section 6.

  Subsong names may be lost, so rpm is read off the firing line (rpm/10 Hz) with the method in
  `video_analysis/engine_order_track.py`.
- **What it needs:** an AC install (the owner's other PC, which holds the AC reference video) or a
  downloaded mod zip. A mod bank decodes without owning the game.

**Same-day placeholder (minutes): reference Creator Store sets by asset id.**
- No upload is needed, because distributed Creator Store audio plays in any experience.
- That is enough to wire up and test the crossfade code today (sets in P2.3).
- Drawbacks:
  - the sets are short (1 to 9 s) and sparse in rpm, and many are Gintani (aftermarket);
  - quality is unheard and Roblox-transcoded;
  - **any uploader's asset can be moderated away at any time**, which would silence the car.

  So it is a placeholder, not the final bank.

**Slower routes:**
- **The paid Pole Position *Aventador 2014*** (section 2) has the most authentic raw L539, plus a
  real cabin and intake. It needs a day or more of loop cutting.
- **engine-sim** (section 5) is the slowest route to a good result: a build, an L539 script and by-ear
  tuning, and still synthetic. It stays the fallback that is fully ours.

### P2.2 Quality-only ranking, engine layers

| Rank | Source | Fit (loops, load, int/ext, events) | Close to stock SVJ | Close to the AC reference | Speed to a working bank | Notes |
|---|---|---|---|---|---|---|
| **1** | **AC bank of the SVJ mod in the owner's reference video** | High: full AC engine model, int + ext, on/off throttle; usually limiter and backfire events [INF] | Unknown; many AC SVJ mods are Gintani or "F1" (aftermarket) | **Exact, by definition** | Fast (hours) | Identify the mod first |
| **1=** | **AC bank `ks_lamborghini_aventador_sv` (Kunos official)** | High, same structure | **Best available stock voice** (Aventador SV, L539) | High (same game and audio engine) | Fast, if an AC install is at hand | Bank location in the install not verified [NV] |
| 3 | Pole Position *Aventador 2014*, paid $249 (section 2) | Medium: steady rpm, ramps, gearshifts and idle, with exhaust, engine, intake and cabin mics, but **needs cutting** | High (real L539, ISR; stock not stated) | Medium | Slow (a day or more) | Best real recording |
| 4 | **Other AC SVJ mod banks** (Modland: "Lamborghini Aventador SVJ 1.0.1" about 105 MB, "SVJ Gintani F1 1.0" about 255 MB, "SVJ FIERCE V1.5" about 87 MB; all need CSP) [SNIP] | High (AC structure) | Low for Gintani F1 and FIERCE (aftermarket / 1000 bhp); unknown for 1.0.1 | High | Fast | A commenter on the Gintani F1 mod: "probably the closest thing you'll get to a good sounding Aventador" [SNIP]. Its samples are credited to **gabeIS300**, whose AC Gintani F1 SVJ sound was also ported to GTA V (2022-01-24, rated 4.95/5) [PAGE]. |
| 5 | **Roblox Creator Store sets** (P2.3) | Low to medium: 2 to 6 rpm bands, few off-load takes, a few shift and crackle one-shots | Mixed; many Gintani | Unknown | **Fastest (minutes, no upload)** | Placeholder; may vanish |
| 6 | FiveM pack "Lamborghini Aventador (L539 V12) Engine Sound" by TheAdmiester (2022-04-02): engine and exhaust from **Forza Horizon 3**, start-up from **GT Sport**, custom crackles; 63k downloads, 4.74/5 [PAGE] | Low for us: GTA V's engine format is granular (ramps plus grain data), not a loop bank [INF], and needs OpenIV or CodeWalker to export | Fairly high (a Forza recording of a stock Aventador) [INF] | Low | Medium | Better as a tone reference than as the bank |
| 7 | engine-sim L539 (section 5) | Complete and consistent | Depends on tuning | Low to medium | Slow | Fully ours |
| 8 | Sonniss GDC 2020 Aventador ramp and pass-bys (section 2) | Low (one ramp, pass-bys) | High (real) | Medium | Medium | Tone reference and exterior one-shots |
| 9 | Pixabay "Lamborghini Aventador SVJ Racing Sound effect" (mizanstock, 0:18) | Very low: one drive clip | Unknown | Unknown | — | Origin unknown; not a bank |

**Not worth it:** `Lambo V12 sound` (96905588102340), whose description says "From Asphalt 5, 6,
3D, Injection, 7, 8, and Nitro": mobile-game audio, low fidelity [INF].

### P2.3 Roblox Creator Store SVJ / Aventador engine sounds

All are free and distributed on the Creator Store. Asset ids are as returned on 2026-10-27.
Durations are in seconds.

**Ranked sets (best fit first):**

1. **"Lamborghini_Aventador ex_*" bands.** These look like **one bank split between two
   uploaders**: the naming is identical and both are exterior. Together they give **six on-load
   bands** (very low, low, mid, mid-high, high, very high), one off-load band, an idle and a rev.
   That is the most rpm coverage of any set here. Source game unknown.
   - **Takumi112892** (2026-04-02):
     - `Lambo_ex_Aventador_onverylow_mix` 76897271727579 (7)
     - `Lamborghini_Aventador_ex_on_mid` 72275841063718 (5)
     - `Lamborghini_Aventador_ex_on_high` 119803794812033 (3)
     - `Lambo_ex_Aventador_offmid3` 95999591700667 (4)
     - `Lamborghini_Aventador_idle` 73235710388670 (8)
     - `Lambo_Aventador_rev_ex` 99078132980883 (1)
   - **Kingdanny2021** (2025-11-26):
     - `Lambo_z_Aventador_onlow` 112345095084500 (4)
     - `Lambo_z_Aventador_onmidhigh` 127016136605753 (4)
     - `Lambo_z_Aventador_onveryhigh` 123590622016111 (4)
     - `Lamborghini_Aventador_ex_on_high` 88675881497471 (3)
     - `Lamborghini_Aventador_idle` 80692873028903 (8)
     - `Lambo_z_Aventador_rev` 129887222263423 (1)
2. **KVERTH "Aventador" set** (2024-12 to 2026-04). **The best event coverage:** on-load in two
   bands (Rev A/B), off-load in two bands (Rel A/B, "release"), limiter, upshift, four downshifts,
   idle and start.
   - `RevA Aventador` 79388569790507 · `RevA Aventador (1)` 92477575114874 (5 each)
   - `RevB Aventador` 91557975737948 · `RevB Aventador (11)` 127970189210558 (5 each)
   - `RelA Aventador (1)` 139541011370095 · `RelB Aventador (3)` 76138928637941 ·
     `RelB Aventador (10)` 75234523416885 (5 each)
   - `Limiter (Red) Aventador (1)` 137849905001581 (1)
   - `Upshift 1234 Aventador` 85787492008713 (&lt;1)
   - `Downshift Aventador 1 (1)` 139859481754833 · `2 (1)` 140398647608699 · `3 (1)`
     124393969219032 · `4` 121534718439545
   - `Idle Aventador SVJ` 120644313772076 (4) · `Startup Aventador SVJ` 96021999181599 (4)
3. **Adhamkhedrhuman "Aventador SVJ" set** (2025-07-29). **The only set with explicit rpm stamps
   and on/off pairs.** But it has just 3 rpm points (1,000 / 4,198 / 8,375), so each loop would be
   stretched far, and there is no decel take at 8,375. It also has separate engine and exhaust
   idles and five crackles.
   - `Revloop1_1000RPM_Accel` 119490640867505 (5) · `Revloop1_1000RPM_Decel` 100720462469672 (6)
   - `Revloop2_4198RPM_Accel` 92450788511165 (6) · `Revloop2_4198RPM_Decel` 138754428710636 (5)
   - `Revloop3_8375RPM_Accel` 78043082471839 (4)
   - `Engine_Idle` 140110494929877 (1) · `Exhaust_Idle` 104336520434472 (4)
   - `Startup` 70853763868958 (6) · `Disengage` 103132432773608 (1)
   - `Crackle1-5`: 97354969724257, 134533799911343, 128716617727916, 105065066916581,
     78429083764516 (&lt;1 each)
4. **Gintani (aftermarket) SVJ sets.** Good for loud overrun and shift one-shots; not stock.
   - **Jiveian** `GNT_SVJV2_*` (2025-12):
     - `OnMid` 70783605428332 · `OnHigh` 134015976721002 · `OffHigh` 81848294346465
     - `DSHigh` 102547913062984 · `DSHigh2` 118940717435349 · `DSMidHigh` 136811830351381
       (downshifts)
     - `UpMidHigh` 122076171094835 · `BoomMidHigh` 116713101274714
     - `LaunchShort` 100034849111835
     - `GNT_SVJ_OnRed1` 93349965651648 · `SVJ_ONIDLE1` 14791908745 · `GNT_SVJ_Launch2`
       73503930892541
   - **KENJI_UNIVERSE** `GNT_SVJ_*`:
     - `OnIdle` 86888239641129 · `IDLECold` 111134345110926 · `STRUPCold` 82787494674797 (cold
       start)
     - `OnRed3` 134113129919228 · `Start2` 17876127448 · `GNT_SVJ` 17876141674
   - **AlbertAtgov:**
     - `SVJGintaniHigh` 133867161318679 / 84394866496825 · `SVJoffhigh` 89356144743105
     - `SVJidle` 102872613246436 · `SVJstart` 103591801272237 · `SVJshiftflames` 80083724484107
   - **R5ist:** `Lamborghini Aventador SVJ Gintani idle` 88513199547800 · `... Startup`
     83784119337144 · `GNT_SVJ_REV` 82141662008108
5. **Decoded AC-bank subsongs.** Fragments only, but they prove the AC route.
   - **Kunos official SV:** `ks_lamborghini_aventador_sv` 89938772505894 (8), `_sv2`
     99571306648159 (3), `_sv3` 94341977283439 (1) by OnlyRealHamster; `[51]` 73516237342409,
     `[79]` 75287592687614, `[175]` 112141354930398 by YaBoyZenvo.
   - **AC mods:**
     - `gb_lamborghini_aventador_sv#53/#96/#121/#170/#179`: 130668681615480, 116622116393338,
       73029576663301, 125689494043373, 137687923742410
     - `gbe_lamborghini_aventador_svj_f1 [2]` 89975190193937
     - `gbe_..._svj_f1v2 [2]` 103425022538777 and `[55]` 126720121620450
     - `lamborghini_aventador_svj_gintani_redd_spec [45]` 98994827035740
     - `SVJ_Roadster2020_Patreon_Edition [2]/[3]/[15]/[42]/[48]/[60]/[104]/[161]` (c0rpseheav3n):
       94476418697007, 117350892279372, 71344878651708, 117633193118776, 115065253265467,
       70911039669065, 103382514441441, 100485335547568
6. **Forza-derived and long takes** (useful as ramps or references):
   - `Aventador-Revloop_FM7_short` 94163990789815 (8), Forza Motorsport 7
   - `Aventador S Revloop fixed` 10006383812 (2)
   - `Lamborghini Aventador SVJ Redline loop` 7298903352 (5)
   - `Lamborghini Aventador revving` 4428148211 (**52**, "Lamborghini L539 engine revs")
   - `Lamborghini Aventador Acceleration` 991101445 (10) and `Deacceleration` 991103905 (**20**),
     by Vexyls, 2017: whole ramps up and down
   - `Lamborghini Aventador SVJ Revloop` 102493355978302 (9) and `Lamborghini Aventador Revloop`
     129226849090605 (9), by e92nic
7. **Loose one-shots worth trying:**
   - overrun and pops:
     - `aventadorcrackleextoff` 133562674958174 (2)
     - `svj boom` 125121319222420 · `svj boom 2` 113649875148102 · `flame svj` 98155563266794
     - `aventadorthrottlefart*` (throttle-lift): 135266353904212, 122021156341820,
       120314506403501
   - `svj mid load rolloff` 96560667686466 (3)
   - `limiter aventador` 130528742778883 (9)
   - `svj downshift gintani` 109515735710638
   - `V12NM_Aventador_HighDet_07` 75109009844646 · `LowDet_01` 96297855478529 (source unknown)

**Explicitly aftermarket, so not stock:**
- Fi Exhaust: 6950963118, 5610820277, 5610973071
- Gintani: 6968659357
- Forged-carbon / "Stradman's car": 4637274841, 4637660769
- Capristo: 76919344144676, 109789679916453
- "SVJ Brilliant Exhaust": 87917111981420, 91894093368654

**Interior coverage is the gap.** Almost every set is exterior (`ex_`) or unlabelled. Only an AC
bank or the paid library gives a true cabin perspective. Otherwise the cabin is built by filtering
(section 6, step 5).

### P2.4 Where to get Assetto Corsa banks, and the format

- **Format.** AC car audio is FMOD Studio. A `.bank` file holds an FSB5 sample bank, which
  vgmstream decodes [CODE]. The FMOD event map is in `GUIDs.txt`. Sound fixes swap `GUIDs.txt`,
  `common.bank` and `common.strings.bank` [SNIP, Overtake "sound switcher" app].
  - Mod cars usually ship `content/cars/<car>/sfx/<car>.bank` with `GUIDs.txt` [INF, community
    convention, NV].
  - The AC SDK ships an "AC Audio Pipeline" PDF and an example FMOD project; a guide names FMOD
    Studio 1.08.12 [SNIP].
- **Sources:**
  - an **AC install**, for Kunos `ks_lamborghini_aventador_sv`;
  - **Modland** (modland.net/assetto-corsa-mods/cars/...): the three SVJ mods in P2.2, all needing
    Custom Shaders Patch to drive, though not to decode the bank;
  - **Overtake.gg** (formerly RaceDepartment) and assettocorsa.club host more mods and sound fixes;
    not checked (403 / search budget);
  - Patreon editions (e.g. "SVJ_Roadster2020_Patreon_Edition") are behind a paywall.
- **Decode.** `vgmstream-cli -S 0 -o "?n_?04s.wav" <car>.bank`. `?n` uses the internal stream name
  if the bank kept one; `?04s` is the zero-padded subsong index. If a bank is FSB-encrypted,
  vgmstream reads a `.fsbkey` file holding the key in hex [CODE]. Without a key, that bank is out.
- **Sort the output:**
  - loops vs one-shots (by length and loopability);
  - rpm, from the rpm/10 firing line;
  - on vs off (on-load is louder and brighter);
  - interior vs exterior (by spectral tilt).

  Then trim to whole engine cycles and export OGG (section 6).

### P2.5 Risks that remain even when the owner accepts the licence side

These are about the owner's own accounts and work, not about licensing:
- **Uploading.** Roblox asks every uploader to attest "the legal rights to that audio asset".
  Ripped audio can be moderated, and a copyright claim lands on the uploading account or group.
  - **Do not upload under the group that owns Rob A Car And Escape (274643456) or under the owner's
    main account.** A strike there could reach the live game.
  - Referencing other people's Creator Store ids avoids uploading, but those assets can disappear
    without notice.
- **Portfolio.** A studio reviewer may recognise AC or Forza audio. Credit it honestly on the page
  (for example "engine audio: Assetto Corsa / Kunos Simulazioni, used privately") rather than leave
  it to look self-made.
- **Private means private.** If the place ever goes public, it falls under Creator Rewards (section
  8.4), and these sources have to be replaced: by engine-sim, the free sources in sections 2 and 3,
  or the paid library.

### P2.6 Recommendation, pass 2

1. **Today:** wire the crossfade engine to Creator Store ids as placeholders. Use the "ex_*" bands
   (P2.3 set 1) for on-load, KVERTH's RelA/RelB for off-load, and KVERTH's shift, limiter and idle
   events. This tests the code path, not the final sound.
2. **Next (best result, fastest):** the owner names the AC SVJ mod in the reference video, or
   provides `ks_lamborghini_aventador_sv` from an AC install.
   - Decode it with vgmstream and sort it into the section 6.3 bank layout (rpm steps × on/part/off ×
     int/ext, plus events).
   - Upload it from a side account or group, not the live game's.
   - **Owner's call between the two banks:** the mod bank matches the reference exactly; the Kunos
     bank is the closest to a stock car.
3. **Keep engine-sim** as the fully owned fallback, and the paid Pole Position library as the
   authenticity upgrade. Neither is needed for a private showcase if the AC bank sounds right.
4. **Secondary layers** stay as in section 3; nothing in pass 2 beats those sources on quality.

**Pass 2 sources:**
- Roblox toolbox search API, `https://apis.roblox.com/toolbox-service/v2/assets:search?searchCategoryType=Audio&query=<q>&maxPageSize=100`,
  with these queries: svj, aventador, aventador svj, svj engine, aventador engine, lamborghini v12,
  lambo v12, svj revloop, aventador revloop, ks_lamborghini_aventador.
- vgmstream: https://github.com/vgmstream/vgmstream (`doc/FORMATS.md`, `doc/USAGE.md`, `COPYING`).
- GTA V ports:
  - https://www.gta5-mods.com/id/vehicles/gintani-f1-lamborghini-aventador-svj-v12-sound-mod-sp-add-on-fivem
    (gabeIS300 credit)
  - https://www.gta5-mods.com/hu/vehicles/lamborghini-avendator-l539-v12-engine-sound-oiv-add-on-fivem
    (Forza Horizon 3 / GT Sport sources)
- Modland (403; search snippets only):
  - https://www.modland.net/assetto-corsa-mods/cars/lamborghini-aventador-svj.html
  - https://www.modland.net/assetto-corsa-mods/cars/lamborghini-aventador-svj-gintani-f1.html
  - https://www.modland.net/assetto-corsa-mods/cars/lamborghini-aventador-svj-fierce.html
- Overtake (403; snippet): https://www.overtake.gg/downloads/assetto-corsa-sound-switcher-in-game-app.26322/
