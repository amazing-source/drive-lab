# 08 · How driving sims turn real car data into in-game cars

Date: 2026-10-27. Every source was accessed on that date. Web search and web fetch only. No logins, nothing posted.
Scope: the practical side. What studios get from manufacturers, what is missing, how they fill the gaps, where they bend reality on purpose, and how they check the result. The physics models are in `01_sim_vehicle_dynamics.md` and the SVJ's numbers are in `02_aventador_svj_data.md`; this note does not repeat them.

**Evidence tags**
- **(a)** a developer or manufacturer statement (their own site, a press release, an interview, patch notes).
- **(b)** a credible community, modder or press source.
- **(c)** my inference. The reasoning is given.
- **[excerpt]**: I saw the claim only in a search-result summary. The page itself blocked this tool or was not fetched. Treat it as weaker.

**Access limits that shape this note.** The shared web-search budget ran out several times during the run, so many planned searches never ran. Reddit (www and old, including the `.json` endpoints) refused this fetch tool outright, so **no Reddit thread is used**. Overtake/RaceDepartment, the GTPlanet forum, Fandom wikis, Top Gear, Kudosprime and the Kunos modding threads answered 403 or 402. No public LinkedIn or X post turned up in the searches that did run. The community voice therefore comes from Steam forums and press. Where something was searched and not found, section 3.4 says so.

---

## 0. One-page summary

### What studios actually do (the common pipeline)

1. **Get a data pack if they can, and take a race car's pack over a road car's specs.** The best case on record is BMW's pack for iRacing's M4 GT4: CAD for every part, a laser scan of a real car, and a "driving dynamics" set with damper curves, engine curves, axle kinematics, weight distribution and aero values. That is the same set BMW feeds its own lap-time simulation. **(a)** [BMW 2020]. Road cars rarely come with that.
2. **Don't trust the spec sheet.** Turn 10 doesn't trust makers' horsepower and weight figures. It runs its own dyno tests and weighs parts **(a, reported)** [Jalopnik 2014]. Greenawalt calls the path from engineer to published number "a game of telephone" through marketing and legal **(a)** [Jalopnik 2010].
3. **Tyres are the universal gap.** Yamauchi says even tyre makers are "mysterious in how they do things" **(a)** [evo 2026]. Studios buy or borrow tyre data from Pirelli, Toyo, Michelin, Goodyear, or from Calspan tests **(a)**. Modders generate tyres from other tyres by size **(b)**.
4. **Fill the remaining gaps with physics plus measured behaviour, never with hard-coded results.** Turn 10 models component weights and lets 0–60 come out of the simulation **(a)** [MCV 2013]. Its "Automagic" tool extrapolates missing values from hundreds of data points **(a)** [Jalopnik 2010]. Reiza starts each car from a similar existing car **(a)** [Reiza 2023]. Polyphony makes "educated guesses" when a maker won't share **(a)** [PlayStation Blog 2017].
5. **Validate the numbers first, then the feel, with people who drove the real car.** Polyphony matched real lap times by 2007, and calls feel the hard part **(a)**. Yamauchi test-drives every car himself **(a)**. iRacing fed NASCAR test data back in after every real test, and a Cup driver compared the two **(a)**. Racing drivers caught a tyre-model flaw in Project CARS 2 **(a)**.
6. **Bend reality at the edges, not in the car.** The documented deviations sit in the **input layer** (pad assists), in **competition rules** (balance of performance), in **presentation** (licensing limits on damage, force-feedback cues) or in **scope cuts** (no tyre wear in Project CARS 3). The physical car stays as close to data as the studio can get it. Greenawalt: "The physics should never be interfered with." **(a)** [Jalopnik 2010].

### Deliberate deviations on record

| Deviation | Who | Why | Tag |
|---|---|---|---|
| Balance of performance: power and weight percentages per car, only in BoP races, tuning locked | GT Sport, GT7, ACC | Fair competition between different cars | (a) |
| More steering help on a pad than a wheel; less input sensitivity as speed rises | Forza (2010), Forza "Normal" steering, GT7 countersteer assist | A pad has no feel and little travel | (a) |
| Front ride height +20 mm to make a concept car easier to drive, agreed with the maker's engineers | Polyphony, Vision GT concepts | No real car exists to match | (a) |
| Tyre core held at a fixed, always-ideal state: no wear, no fuel, no pit stops | Project CARS 3 | "a conscious decision" to focus on driving | (a) |
| Brake temperature simulated on only three cars when it was introduced | Assetto Corsa v1.7 | Rolled out car by car; the Aventador SV was not one of the three | (a), consequence (c) |
| Tyres as generic compound classes (Comfort/Sports/Racing) with placeholder sizes | GT7 | One tyre system for 400+ cars | (b) |
| Extra force-feedback cues a real wheel would not give, switchable | Kunos (ACC) | Replace the senses a sim lacks | (a) |
| Damage capped at the strictest licensor's level; roof never damaged | Licensed racing games (anonymous developer) | Licence terms and manufacturer approval | (a, anonymous) |
| Unrealistic setups allowed but physically penalised | Kunos (ACC) | Blocking them would hide the physics' limits | (a), via `01` |

**Searched for and not found as a developer statement:** grip boosts for gamepad players, removal of top-speed limiters, a stated policy of removing brake fade, engine sound decoupled from rpm, and a manufacturer demanding that its car not look slow. See 3.4.

### What to adopt for our SVJ, and what not to

**Adopt**
1. **Two layers, kept apart.** The car is built from `02` data and the `01` model, and is never tuned for gameplay. Keyboard and pad help lives in an input layer between the device and the rack, as in Forza, GT7 and KartKraft (section 3.2). If the car feels wrong on a pad, change the input layer. Change the car only when a measured target is missed.
2. **Treat every spec figure as a hypothesis and cross-check it.** We already did: the 2.867 final drive became 3.52, and 1,525 kg dry became 1,845 kg running (`02`). That is Turn 10's habit **(c)**.
3. **Never hard-code a result.** 0–100 km/h in 2.8 s, 30 m braking and 350 km/h are test targets that the model must produce, not values the code forces (Turn 10, MCV 2013).
4. **Tyre = a generic ultra-high-performance road-tyre family, sized to the SVJ's 255/30 R20 and 355/25 R21 and tuned to the SVJ's targets.** This is what modders' tools and GT7 effectively do. Name it as an estimate in the provenance table.
5. **Custom code for the car's unusual systems.** ALA 2.0 aero, rear-wheel steer and the Haldex coupling each get their own small controller, as Polyphony does for torque vectoring and active aero on concept cars **(a)** [GTPlanet 2025].
6. **A validation ladder:** numbers (bench tests), then behaviour checks (a slide to a stop, a slide that can be caught), then a feel pass by a driver. Each check becomes a regression test that can fail.
7. **Keep the real character, flaws included.** Reviewers call the Aventador SV understeery on track **(b)** [excerpt]. Turn 10 kept the Ferrari Enzo's handling flaw and magazines later confirmed it **(a)**. Kunos says it does not use made-up numbers to make cars more exciting **(a)**. Don't "fix" mild understeer in the car; offer help in the input layer.
8. **A provenance column for every parameter** (OEM / DER / EST, as `02` already does). It is our equivalent of BMW's data pack: anyone can see which numbers are real.

**Do not adopt**
- **Balance of performance.** There is one car and no competition, so there is nothing to balance.
- **Changing the physical car for drivability** (Polyphony's +20 mm on a concept). It is only defensible when no real car exists. Ours exists, so drivability goes in assists.
- **Copying a mod's numbers.** Our reference video is an Assetto Corsa SVJ **mod**, not a Kunos car. One SVJ mod lists **1,520 kg**, which is the dry weight and about 325 kg (18 %) under our 1,845 kg running mass **(b, c)** [excerpt]. Use the video for look and sound timing, not as a handling ground truth.
- **Dropping tyre heat and wear for good**, as Project CARS 3 did. Leaving it out of v1 is fine (`01` says so), but as a scoped v1 decision, not a design rule.
- **(c), outside the physics brief:** licensed titles get the maker's approval for the car's depiction (section 4.3). We have no licence, so a public build carrying Lamborghini names or badges is a trademark question for the owner. `03` already separates a private lab model from a publishable one.

---

## 1. Where the data comes from, and what is typically missing

### 1.1 Sources by studio

| Studio | What they get or make | Tag, source |
|---|---|---|
| **Kunos (Assetto Corsa, ACC)** | Modern cars: data directly from the manufacturer (power, torque and technical figures). Classic cars: blueprints, photos and, lately, laser scans. A network of manufacturers, drivers and engineers refines the car. | (a) Massarutto [Custodian 2021] |
| | GT3 cars: manufacturers "provide us with a lot of information" used as the base. "Each car has its own unique set of tweaks" covering suspension, brakes, gearbox, engine, ABS and TC. | (a) Vasilakos [FIA 2022] |
| | Licences give "full access" to the cars' setup and design data. | (a) Vasilakos [RAVSim 2012] |
| | For cars without telemetry: find the engineers who worked on the car, get access to it, measure its parts, collect lap times. Older cars are reverse-engineered. | (a) Vasilakos [Petrolicious, excerpt] |
| | ACC tyres built with Pirelli telemetry; damper curves imported from manufacturers. | (a), via `01` |
| **Polyphony (Gran Turismo)** | Laser scans of exterior and interior (point cloud, about three months to convert); aero maps from CFD plus wind tunnel; data collected from the real car. | (a) [GTPlanet 2017 lecture] |
| | Some cars had design data and measured data; some makers would not share it. | (a) Yamauchi [PlayStation Blog 2017] |
| | Concept cars: the maker supplies CAD, drivetrain type, suspension geometry, size and specs. | (a) [GTPlanet 2025] |
| | Manufacturers often hand Polyphony a car before anyone outside the maker has driven it. | (b) evo's own framing [evo 2026] |
| **Turn 10 (Forza)** | Inputs it needs: moment of inertia, CG height, braking distances, a precise torque curve. Complete figures are hard to get from makers. | (a) Greenawalt [Jalopnik 2010] |
| | CAD from makers is usually poor for game cars (made for engineering), sometimes a starting point. Own dyno tests and part weighing replace the published HP and weight. | (a) reported, not quoted [Jalopnik 2014] |
| | McLaren P1: "We need raw data". Component weights (doors, drivetrain), not lap-time figures. | (a) Greenawalt [MCV 2013] |
| | Confidential tyre data from Toyo, Michelin and Ferrari (deformation, heat response). FM4 used Pirelli data. FM5: tyre tests with Calspan. | (a) [Jalopnik 2010] [Wikipedia FM4 → Develop 2011] [Xbox Wire 2013] [GamingBolt 2013] |
| | When a part is unavailable, Turn 10 goes to the parts maker, then works out inertia and suspension geometry; for FM5 it sent tyres to Calspan for weeks of testing. | (b) [Top Gear, excerpt] |
| **iRacing** | BMW M4 GT4: licence agreement first, then two multi-gigabyte packs. CAD of every part ("the same data a supplier gets") plus a laser scan of Turner Motorsport's car and photos. Then a dynamics pack: damper curves, engine curves, axle kinematics, weight distribution, aero values, the same set BMW uses for lap-time simulation. | (a) BMW + iRacing staff [BMW 2020] |
| | NASCAR Next Gen: data from Chevrolet, Ford and Toyota; every real test's data fed into the model. | (a) Myers [Kickin' the Tires 2021] |
| | Tyres: basic measurements taken without a tyre test machine, then a first-principles model. | (a) Kaemmer [iRacing 2011] |
| **Reiza (Automobilista 2)** | "Sometimes manufacturers will provide us with all we could need." Otherwise "various sources". CAD → suspension coordinates; mass, power, ratios, aero positions, wheelbase and track; factory setup sheets. Historic cars: geometry plotted from photos. | (a) [Reiza 2023] |
| **Slightly Mad (Project CARS 2)** | Pirelli supplied carcass simulation, slip-angle curves, heating, and cut/wear behaviour; used for 180+ cars. | (a) [Tyrepress 2017] |
| **Studio 397 (rFactor 2)** | Goodyear shared "data and insight"; each tyre set "tailor-made" to its real counterpart. | (a) [Studio 397 2023] |
| **Modders (Assetto Corsa)** | Best case (RSR's F3): laser-scanned track, the real car and driver, full telemetry, measured suspension and dampers, the tyre maker's data for one compound. | (b) [Bsimracing 2015] |

### 1.2 What is typically missing, ranked by how often studios say so

| Missing item | Who says it is hard | Our SVJ status (from `02`) |
|---|---|---|
| **Tyre force data** (slip curves, load sensitivity, heat) | Yamauchi: "even the manufacturers are mysterious" and contact patch behaviour is unsolved (a). Turn 10 rejected Pacejka fits and went to Calspan (a). | None published. EST. |
| **Inertia and CG height** | Turn 10 lists them as inputs makers rarely give complete (a). | EST (lumped-mass model). |
| **Damper curves, kinematics** | Only in race-car packs (BMW, ACC) (a). Road makers publish relative changes at most (c). | Only "+50 % anti-roll bars, +15 % damping range". |
| **Aero maps** | Polyphony builds its own from CFD and wind tunnel (a). | Only relative figures and one unverified press number. |
| **Control electronics logic** (diffs, AWD, ESC, active systems) | Electronic drivetrain management varies widely between makers; EVs add more (a, reporter's summary) [GTPlanet 2026]. | Mode splits only (Aventador S kit). |
| **Trustworthy headline specs** | Turn 10 distrusts HP and weight (a). | Already cross-checked (3.52 final drive, 1,845 kg). |

**(c) What this means for us:** we are in the "road car, no data pack" case, the same position as Polyphony with a maker that won't share, or as a modder. The studios' answer in that case is educated estimates plus measured behaviour targets. That is what `02` §2.15 already sets up.

---

## 2. How they fill the gaps

1. **Measure it yourself.** Dyno and part weighing (Turn 10) **(a, reported)**. Measure the car's parts and talk to its engineers (Kunos) **(a)** [excerpt]. Turn 10 also tests parts rather than whole cars, assembling a car from related components when the real one is unavailable **(a, reported)** [Red Bull, excerpt; the fetched page did not contain it].
2. **A physics model with few measurable inputs, behaviour emerging.** iRacing: "There are comparatively few numbers involved in describing a tire now." **(a)**. Turn 10's Automagic takes hundreds of data points, extrapolates a performance model and calculates the missing values **(a)** [Jalopnik 2010]. Turn 10 doesn't hard-code acceleration; it models part weights **(a)** [MCV 2013].
3. **Start from a known reference car.** Reiza bases each new car on a similar existing one, or on the previous version **(a)**. Kunos started Assetto Corsa from a simple reference, its own Fiat 500 Abarth on road tyres at about 1 g **(a)** [RAVSim 2012]. **(c)** A car you can drive and measure anchors the whole model.
4. **Educated guesses, judged by character.** Polyphony: "Some manufacturers were not willing to part with that level of data", "we had to make educated guesses" **(a)**. A search summary of the same source adds that the guesses usually caught each car's character **[excerpt]**.
5. **Generic tyres scaled by size.** Content Manager, the main Assetto Corsa modding tool, ships a "Tyres Machine". In its source code, a tyre's WIDTH, RADIUS and PROFILE go into small neural networks (two hidden layers of 15), trained on a set of existing tyres, which predict the remaining tyre parameters **(b, read from code)** [actools GitHub]. **(c)** That is a tyre "family" interpolated by size; what the training tyres were is not stated in the files I read. GT7 uses compound classes shared across cars **(b)** [The Drive 2024]. RSR's F3 mod had one real compound and two "modified versions" of it **(b)** [Bsimracing 2015].
6. **Tune the unknowns until they match measured data.** Reiza tunes tyre carcass, spring/damper and aero coefficients until the car matches the data it gathered **(a)**. VPP's version of this (tyre targets from braking, top speed and skidpad) is in `01` §3.1.
7. **Custom code for unusual hardware**, rather than forcing it into the generic model: torque vectoring, hybrid delivery, active aero (Polyphony) **(a)** [GTPlanet 2025]. Kunos needed extra work for an unusual rear suspension (Alfa GTA) **(a)** [Custodian 2021].
8. **Real data feeds in continuously when it exists.** iRacing updated the NASCAR model after each real test **(a)**.

---

## 3. Where they deliberately deviate, and why

### 3.1 Balance of performance (competition only)
- GT Sport 1.40 (2019) changed per-car "power ratio" and "weight reduction ratio", for example the Lamborghini Huracán GT3 '15 power 96 % → 94 % and weight 108 % → 106 %. GTPlanet says cars are equalised using AI reference laps and human test drivers, and calls it "not an exact science" **(b, reporting the patch)** [GTPlanet 2019].
- GT7 daily races: BoP sets each car's power and weight, and "No vehicle settings are permitted" **(b)** [GTPlanet 2022].
- ACC: "BoP fine-tuning" per track and "provisional BoP" for new cars in hotfixes. The article does not say whether it copies SRO's real BoP **(b)** [Traxion 2023].
- Real-world origin: series organisers adjust power, weight and aero from telemetry and tests **(b)** [Wikipedia].
- **(c)** BoP is a rule set applied on top of each car in certain events. It does not change the car's physics outside them. Irrelevant to a single-car sim.

### 3.2 Input-layer help for pads and keyboards
- Forza (2010): the help depends on the controller, a wheel gets the least, and steering sensitivity falls as speed rises. Greenawalt: "The physics should never be interfered with." **(a)** [Jalopnik 2010].
- Forza "Normal" steering is several systems layered together; "Simulation" turns them off. GT7 *reduced* countersteer assistance in update 1.31 **(a)**, both in `01` §4.
- Community claims about Forza's Normal mode (input assists switched off for wheels; tyre heat felt less in Normal) are anecdotal and disputed **(b, weak)** [Forza forums, excerpt].
- KartKraft: the whole team plays on a pad; "Not dialling down the physics at all"; ABS-type assists are added instead **(a)** [Traxion 2021].
- Assetto Corsa: a player relays that the developers suggested at least 65 % stability control on a pad, with no link to a developer source **(b, weak)** [Steam 2015].
- **(c)** The pattern: help is added between the input and the car, and the car is not made grippier. This matches `01` §4.

### 3.3 Simplifications and presentation choices
- **Concept-car drivability:** after test drives, Polyphony raised a concept's front ride height by 20 mm to make it easier to drive, and sent the change to the maker's engineers **(a)** [GTPlanet 2025]. Only possible because no real car exists.
- **Tyre wear and fuel removed:** Project CARS 3 fixed the tyre's bulk layer at an always-optimal state, with no wear, no fuel and no pit stops. Principal vehicle handling designer Nick Pope called it "a conscious decision". GTPlanet's report says the core simulation was not reduced **(a)** [GTPlanet 2020].
- **Brake temperature introduced car by car:** Assetto Corsa v1.7 added disc temperature simulation for the Ferrari 488 GT3, Maserati GT4 and Levante only **(a)** [AC forum 2016]. **(c)** So when it shipped in that same update, the Aventador SV had no brake-temperature model, and therefore no fade. Later patches were not checked.
- **Generic tyre classes:** in GT7, several cars share a placeholder tyre size (123/45ZR67) on the sidewall, and the compounds are classes; Michelin branding came only in 1.49 (2024) **(b)** [The Drive 2024].
- **Added cues:** Kunos's force feedback adds gravel and tyre vibrations a real wheel would not transmit, and lets players switch them off **(a)** [Custodian 2021].
- **Damage capped by licensing:** roofs never damaged; damage models sent to each maker for approval; every car reduced to the strictest brand's "B level" **(a, anonymous developer)** [Jalopnik 2023].
- **Allowed but penalised setups (Kunos)** and the GT7 assist retune: in `01` §3.1 and §4.

### 3.4 Searched for, not found (scope: this session's limited search budget)
- **Grip boosts for gamepad players:** no developer statement found. Every statement found says the opposite: help goes in the input layer (3.2).
- **Top-speed limiters removed:** none found for GT7 or Forza. One search returned only a GT6 forum complaint and a glitch video **(b)**.
- **Brake fade removed as a policy:** none found. Only the Assetto Corsa per-car rollout above **(a)**.
- **Engine sound vs real rpm:** not researched here; it belongs to `06_audio_sourcing.md`.
- **"Don't let our car look slow":** no developer or manufacturer statement found. The nearest are manufacturer approvals of appearance and damage (4.3), and Yamauchi declining to say which makers he turned down ("I cannot answer.") **(a)** [evo 2026].

### 3.5 Where they explicitly refuse to deviate
- Kunos does not use "magical, made-up numbers" to make cars more exciting, and reproduces famous cars as they were even when that makes them less fun **(a)** [Custodian 2021].
- Turn 10 modelled the Ferrari Enzo from Ferrari's data, found its handling badly flawed, and assumed its own maths was wrong. Magazines later reported the same flaws **(a)** [Jalopnik 2010].
- Polyphony aims at "the idiosyncrasies of how the cars deliver their performance", not exaggeration **(b, evo framing)** [evo 2026].
- Kunos rebuilt its engine rather than reuse one that "would have involved too much fudging" **(a)** [RAVSim 2012].

---

## 4. How they validate, and what manufacturers ask for

### 4.1 Numbers
- Polyphony tuned tyres to real lap times "back in 2007"; making it drivable is the hard part ("The most difficult simulation is the tire model") **(a)** [GTPlanet 2017].
- Kunos matches lap times to historic times on laser-scanned tracks **(a)** [Petrolicious, excerpt].
- iRacing checks behaviours: "When a car slides to a stop it takes the right amount of time"; burnouts look right **(a)** [iRacing 2011].
- Reiza: a "virtual shakedown", tests on many tracks, traction circles, wheel-slip graphs and spectral analysis of tyre flex. It does not mention lap times or manufacturer sign-off **(a)** [Reiza 2023].

### 4.2 People
- Yamauchi: "I test-drive the car at the end to make sure everything is okay." About eight months per car, look and physics together **(a)** [evo 2026].
- Project CARS 2: Bentley driver Guy Smith spun at Bathurst in the sim and said "that's not real, i would have been able to catch it"; David Brabham (spelled "Brabban" in the interview) reported the same. SMS then wrote new sliding-tyre code ("Rip Grip") **(a)** [Thumb Culture 2017].
- NASCAR Next Gen: William Byron drove the real car early, then "a lot of testing on our model" to say how close it was **(a)** [Kickin' the Tires 2021].
- BMW M4 GT4: "initial feedback from people who have driven the real car is very positive" (Steve Reiss, iRacing) **(a)** [BMW 2020].
- Kunos: pro drivers refined ACC's handling and sounds. The faster driver in a team tends to call the sim realistic and slower drivers report problems. Kunos prefers race engineers' input because "the numbers never lie" **(a)** [Custodian 2021]. **(c)** A tester's skill changes the verdict, so record who drove each feel pass.
- Turn 10: racing driver Stefan Sarazen practised on Turn 10's simulator and took pole at a track he had never raced **(a)** [MCV 2013].

### 4.3 Manufacturers
- **Formal inspection (race car):** at the end, BMW Motorsport inspects the virtual M4 GT4 "in exactly the same way as a real car": appearance, handling and interior details. BMW says it is responsible for the virtual car meeting its requirements **(a)** [BMW 2020].
- **Engineering loop (concept cars):** Polyphony refines the car in back-and-forth with the maker's engineers **(a)** [GTPlanet 2025].
- **Depiction:** damage approvals; road cars expected to look like the brochure; livery restrictions **(a, anonymous)** [Jalopnik 2023].
- **Licensing posture:** SMS said makers "like our commitment to simulation and realism", and that Ferrari and Lamborghini "wasn't that hard" **(a)** [Thumb Culture 2017].
- **(c)** For road cars, nothing public shows a maker asking for more pace. The documented demands are about depiction and, for race cars, fidelity to the maker's own data.

---

## 5. The Lamborghini Aventador and SVJ in sims

### 5.1 Assetto Corsa
- **Official car: Aventador SV (LP 750-4), not the SVJ.** It shipped in the Red Pack DLC with v1.7, announced 14 July 2016. Kunos's text gives 750 hp, −50 kg, 2.03 kg/hp, 0–100 in 2.8 s and >350 km/h **(a)** [AC forum 2016]. The same update brought "Tyre Model V10 for selected RED PACK cars" and made tyre radius depend on wheel speed **(a)**. Brake temperatures: not on the SV at launch (3.3).
- **How Kunos built it:** no SV-specific statement was found. **(c)** Kunos's general practice is data directly from makers for modern cars [Custodian 2021], so manufacturer figures are likely but unconfirmed for this car. Kunos encrypts its car data, and no one in this run read it.
- **Community critique, Steam (2023):** "Do Lamborghini's really have that much understeer?" Replies blame drivers asking too much of the car. One reply says AC's tyre model "does exaggerate balance at times" but "within reason". Another says AC feels "worlds apart" on a wheel versus a pad **(b)** [Steam 2023].
- **Steam (2017), Sesto Elemento:** understeer into snap oversteer on semi-slicks; on Trofeo tyres the car was more forgiving and over four seconds faster at Laguna Seca; one poster praises the Aventador SV **(b)** [Steam 2017].
- **Real-car cross-check:** road testers called the SV "disappointingly understeery on track" (CAR) and reported a little early understeer, "right and proper for a road car" (Top Gear) **(b)** [excerpt]. **(c)** The sim's understeer is at least partly the real car's character, which supports summary rule 7.
- **SVJ mods:** the SVJ exists in AC only as mods. One listing, "Aventador SVJ Gintani F1", gives 680 whp, 650 Nm, 1,520 kg and 350 km/h, credits "physics" without naming a source, and needs Custom Shaders Patch **(b)** [Modland, excerpt]. **(c)** 1,520 kg is essentially the 1,525 kg dry weight; Gintani is an aftermarket tune. Neither suits a stock SVJ. **Our reference video (`LAMBORGHINI AVENTADOR SVJ _ Assetto Corsa.mp4`) is a mod of this kind**: whichever mod it is, its handling numbers are unknown.

### 5.2 Gran Turismo 7
- A GT7 Lamborghini list updated 12 May 2022 shows the **Aventador LP750-4 Superveloce '15** and no SVJ **(b)** [Samurai Gamers 2022]. Later additions were not checked (GT7 pages render client-side and did not load here).
- No Polyphony statement on the Aventador's data or handling was found.

### 5.3 Forza
- **Not verified in this session.** I expected the 2019 SVJ in Forza Horizon 4 and 5, but the Fandom and Kudosprime pages refused this tool and the search budget was gone. No Turn 10 or Playground statement on it was found.

### 5.4 Lamborghini and sims generally
- Lamborghini Squadra Corse runs ACC esports with its factory drivers **(b)** [excerpt]. No source found on a Lamborghini data hand-over for any road Aventador in any title.

---

## 6. Sources

All accessed 2026-10-27. Publication dates are given where the page showed one.

**Developer and manufacturer statements**
- BMW Group, "Realistic down to the smallest detail: how the virtual version of the BMW M4 GT4 came about", 29 May 2020 (PDF; quotes Dittrich/BMW, Simpson and Reiss/iRacing): https://www.press.bmwgroup.com/usa/article/attachment/T0309090EN_US/451643 (a)
- Kickin' the Tires, "iRacing Expanding to Motorsports Development", S. Eggert, 14 Dec 2021 (Steve Myers): https://kickinthetires.net/?p=10383 (a)
- iRacing, "New Tire Model Debuts on New Chevrolet Impala B", 22 Jun 2011 (Kaemmer): https://www.iracing.com/new-tire-model-debuts-on-new-chevrolet-impala-b/ (a)
- Jalopnik, "Inside Forza Motorsport, Part III: The Physics Of Driving Games", S. Smith, 26 Feb 2010 (Greenawalt): https://jalopnik.com/inside-forza-motorsport-part-iii-the-physics-of-drivi-5480781 (a)
- Jalopnik, "Forza Horizon 2 Developer Says Manufacturer-Provided Data Is 'Garbage'", J. Torchinsky, 9 Jun 2014 (Greenawalt, reported): https://jalopnik.com/forza-horizon-2-developer-says-manufacturer-provided-da-1588344255 (a, reported)
- MCV/Develop, "Forza 5: How McLaren Automotive's data served Turn 10", 27 Nov 2013: https://mcvuk.com/?p=79557 (a)
- Xbox Wire, "How Forza Motorsport 5 is Defining New Generation Racing", 20 Sep 2013: https://news.xbox.com/en-us/2013/09/20/games-forza-5-new-gen-racing/ (a)
- GamingBolt, "Forza Motorsport 5 Features 'Cutting Edge Understanding' of Tire Physics", R. Sinha, 20 Aug 2013: https://gamingbolt.com/forza-motorsport-5-features-cutting-edge-understanding-of-tire-physics-aerodynamics (a)
- Wikipedia, Forza Motorsport 4 (Pirelli tyre data, citing Develop 2011): https://en.wikipedia.org/wiki/Forza_Motorsport_4 (b → a)
- PlayStation Blog, "Origin Story: Kazunori Yamauchi & Shuhei Yoshida...", 13 Oct 2017: https://blog.playstation.com/2017/10/13/origin-story-kazunori-yamauchi-shuhei-yoshida-look-back-at-gran-turismos-inception/ (a)
- GTPlanet, "Dr. Kazunori Yamauchi Gives Lecture on Gran Turismo's Driving Physics & Production", J. Greer, 31 Oct 2017: https://gtplanet.net/dr-kazunori-yamauchi-gives-lecture-gran-turismos-driving-physics-production (a)
- evo, "Gran Turismo creator Kazunori Yamauchi on the challenges of car game development", E. Jupp, 22 Aug 2026: https://www.evo.co.uk/features/209047/gran-turismo-creator-kazunori-yamauchi-on-the-challenges-of-car-game-development (a)
- GTPlanet, "Kazunori Yamauchi Says Tire Physics Remain One of Gran Turismo's Biggest Challenges", J. Greer, 22 Aug 2026: https://www.gtplanet.net/kazunori-yamauchi-says-tire-physics-remain-gran-turismos-biggest-challenge-20260822/ (a)
- GTPlanet, "The Surprisingly Human Process of Adding Concept Cars to Gran Turismo", J. Greer, 21 Sep 2025: https://www.gtplanet.net/the-surprisingly-human-process-of-adding-concept-cars-to-gran-turismo/ (a)
- The Apex by Custodian, interview with Marco Massarutto, 12 Dec 2021: https://apex.custodian.club/marco-massarutto/ (a)
- FIA, "Data the key to Paul Ricard success, both on track and in Assetto Corsa Competizione", 13 Oct 2022 (Vasilakos): https://fia.com/node/43970 (a)
- RAVSim, "Assetto Corsa exclusive first drive", J. Denton, 17 Mar 2012 (Casillo, Vasilakos): https://ravsim.com/2012/03/17/assetto-corsa-exclusive-first-drive/ (a)
- Petrolicious, Aris Vasilakos interview (HTTP 429 on every try; content seen only through search): https://petrolicious.com/articles/how-assetto-corsa-s-lead-designer-digitizes-classic-tracks-and-iconic-cars (a) [excerpt]
- Assetto Corsa forum, "Assetto Corsa v1.7 and Red Pack available", 14 Jul 2016: http://www.assettocorsa.net/forum/index.php?threads/assetto-corsa-v1-7-and-red-pack-available.34325/ (a)
- Reiza, "Automobilista 2 V1.5 Physics Development Update Part 2", via Bsimracing, 25 Jul 2023: https://www.bsimracing.com/automobilista-2-v1-5-physics-development-update-part-2/ (a)
- Tyrepress, "Pirelli brings World Challenge Series, motorsport tech to Project CARS 2 game", 18 Sep 2017: https://tyrepress.com/2017/09/pirelli-brings-world-challenge-series-motorsport-tech-to-project-cars-2-game (a)
- Thumb Culture, EGX 2017 interview with Rod Chong (SMS COO), 5 Oct 2017: https://www.thumbculture.co.uk/?p=3583 (a)
- GTPlanet, "Project CARS 3 Developer Blog Explains New Tire Physics...", A. Evans, 26 Jun 2020: https://www.gtplanet.net/pc3-new-tire-physics-20200626/ (a, reported)
- Studio 397, "rFactor 2 and Goodyear Tyres", 12 Jan 2023: https://www.studio-397.com/?p=15378 (a); Tyrepress coverage, 13 Jan 2023: https://tyrepress.com/2023/01/goodyear-provides-tyre-expertise-to-rfactor-2 (b)
- Traxion, "Zach Griffin on the future of KartKraft", 7 Apr 2021: https://traxion.gg/zach-griffin-on-the-future-of-kartkraft/ (a)
- Jalopnik, "Game Developer Explains Why New Racing Games Suck At Car Damage", A. Ismail, 2 Feb 2023 (anonymous developer): https://jalopnik.com/why-car-damage-sucks-in-racing-games-developer-explains-1850060288 (a, anonymous)

**Balance of performance**
- GTPlanet, GT Sport 1.40 BoP changes, 4 Jul 2019: https://www.gtplanet.net/gran-turismo-sport-1-40-balance-of-performance-bop-changes-detailed/ (b)
- GTPlanet, GT7 daily races, 21 Mar 2022: https://www.gtplanet.net/gran-turismo-7-daily-races-20220321/ (b)
- Traxion, ACC v1.9.2 hotfix BoP, 5 May 2023: https://traxion.gg/assetto-corsa-competizione-hotfix-tweaks-bop-adds-alpine-esports-liveries/ (b)
- Wikipedia, Balance of performance: https://en.wikipedia.org/wiki/Balance_of_performance (b)

**Community, modders, tools**
- Content Manager source code, AcTools.NeuralTyres (TyresMachine.cs, NeuralTyresOptions.cs): https://github.com/gro-ove/actools/tree/master/AcTools.NeuralTyres · https://raw.githubusercontent.com/gro-ove/actools/master/AcTools.NeuralTyres/TyresMachine.cs · https://raw.githubusercontent.com/gro-ove/actools/master/AcTools.NeuralTyres/Data/NeuralTyresOptions.cs (b, code read)
- Bsimracing, RSR Formula 3 mod v1.0, 22 Nov 2015: https://bsimracing.com/?p=58515 (b)
- The Drive, "GT7 Update Finally Puts to Rest a Tire Mystery...", C. Tsui, 24 Jul 2024: https://www.thedrive.com/news/gt7-update-finally-puts-to-rest-a-tire-mystery-thats-haunted-me-for-years (b)
- Steam, "Do Lamborghini's really have that much understeer?", 3–6 Apr 2023: https://steamcommunity.com/app/244210/discussions/0/6142387869098721042 (b)
- Steam, "Sesto Elemento is Terrible..", Dec 2017: https://steamcommunity.com/app/244210/discussions/0/1621724915766762987/?ctp=2 (b)
- Steam, controller thread, 5 Aug 2015 (relayed "65 % stability" suggestion): https://steamcommunity.com/app/244210/discussions/0/541907867768564878 (b, weak)
- Samurai Gamers, GT7 Lamborghini car list, updated 12 May 2022: https://samurai-gamers.com/gran-turismo-7/lamborghini-cars-list/ (b)
- Bsimracing, AC Red Pack preview: Aventador SV, 30 Jun 2016: https://bsimracing.com/assetto-corsa-red-pack-preview-lamborghini-aventador-sv (b)

**Seen only in search summaries [excerpt]**
- Top Gear, "How do cars end up in games" (parts makers, Calspan testing of tyres for FM5): https://www.topgear.com/car-news/gaming/how-do-cars-end-games
- Red Bull, FM7 facts (Greenawalt: test parts, not whole cars): https://redbull.com/se-en/5-facts-forza-motorsport-7-2017-07-11 (the fetched page no longer held the article)
- F1Technical forum (Pirelli curves don't isolate camber and wear, per a quoted interview): https://www.f1technical.net/forum/viewtopic.php?p=497897
- Modland, "Lamborghini Aventador SVJ Gintani F1 1.0" (AC mod; 1,520 kg, 680 whp): https://www.modland.net/assetto-corsa-mods/cars/lamborghini-aventador-svj-gintani-f1.html
- CAR Magazine, Aventador SV review (2015): https://carmagazine.co.uk/car-reviews/lamborghini/lamborghini-aventador-sv-2015-review · Top Gear Aventador first drive: https://www.topgear.com/car-reviews/lamborghini/aventador-coupe-2011/first-drive
- Forza forums (Normal vs Simulation steering, player claims): https://forums.forza.net/t/a-lot-of-new-players/8627 (now redirects)
- Bsimracing / motori.quotidiano.net (Lamborghini Squadra Corse in ACC esports): https://motori.quotidiano.net/?p=348448

**Tried and blocked or empty (no claim drawn from them):** reddit.com and old.reddit.com (refused by the fetch tool), Overtake/RaceDepartment (403), GTPlanet forum threads (403), forza.fandom.com (402), Kudosprime (403), the Kunos forum's tyre-spec and "Answers from the devs" threads (403), gran-turismo.com car list and manual (rendered client-side, empty).
