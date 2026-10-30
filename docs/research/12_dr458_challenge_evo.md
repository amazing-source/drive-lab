# Ferrari 458 Challenge Evoluzione (Dream Racing car): research for Drive Lab

Researcher agent, 2026-10-30. Web search and fetch only: no browser automation, no login pages.
No repository was edited. Read-only reads: `drive-lab/CLAUDE.md`, `docs/engineering/AGENTIC_WORKFLOW.md`,
and `dr458-modeling-pipeline/references/` plus its `docs/REFERENCES_AND_RIGHTS.md` and `docs/SPECIFICATION_LEDGER.md`.

## How to read this

- **documented**: stated in a Ferrari document or release, a Ferrari Challenge regulation, or directly
  visible in a reference photo (the photo is named).
- **likely**: one non-factory source (a driver report, a forum, a dealer), or a road-458 fact that probably
  carries over to the Challenge, or a strong inference. The reason is given each time.
- **unknown**: no source found. A gap, left empty, never filled from game conventions.
- Lines starting **Inferred:** are my own computation or reasoning, not a source.
- Photo names are relative to
  `references/2015_challenge_evoluzione/` in the DR458 modelling pipeline repository (`dr458-modeling-pipeline`).
  That photo car is a 2015 Evo sold on Cars & Bids. It is **not** the Dream Racing car, whose exact cockpit
  is unknown (see the gaps list).
- Short source tags are expanded in the Sources list at the end.

## Local reference status

- `458italia_manual.pdf` is a **Git LFS pointer** (133 bytes; target size 20,471,957 bytes). Its content is
  not on this machine. I did not read it.
- `ferrari_challenge_2016.pdf` is a **Git LFS pointer** (132 bytes; target 4,865,996 bytes). I downloaded the
  public copy named in `REFERENCES_AND_RIGHTS.md`. Its SHA-256 (`b3e825c6...c475`) equals the pointer's oid,
  so it is byte-identical to the repository file. I read all 35 pages; the spec sheet is PDF page 14
  (printed pages 24-25). Tag **[B16]**.
- Photos: when I first listed them, 102 of the 131 photo files were LFS pointers (49 exterior, 13 interior,
  all 23 mechanical, all 17 other). At 17:36-17:37 local time another process replaced them with the real
  images (file times show it). I did not run `git lfs`. All 131 were real images when I made my contact sheets.

## Corrections to the brief

These come from the photos and sources below. They change what gets built.

1. **LEFT and RIGHT are the turn signals, not display pages.** They are the two yellow buttons on the wheel
   grips. **SCROLL** is the button that changes display pages. (photo `interior/010`; [HFO])
2. **There is no screen on the steering wheel.** The display sits in the dash binnacle behind the wheel.
   (photos `interior/010`, `011`)
3. **No separate neutral paddle is visible.** There are two long paddles, DOWN on the left, UP on the right.
   On the road 458, neutral is selected by pulling both together. (photo `interior/010`; forum sources)
4. **The centre switch panel has no extinguisher and no master switch.** It carries the ignition toggle
   under a red guard, ENGINE START, LIGHT, RAIN LIGHT, AC ON/OFF and an AC FAN dial (0-3). The master key,
   the extinguisher button and the reverse button are on the centre tunnel. (photos `interior/013`, `015`)
5. **The manettino is OFF / 1 / 2.** OFF switches traction control off. Positions 1 and 2 add progressively
   more intervention. It selects ABS/EBD, E-Diff and F1-Trac calibrations. It does not change power. ([FB10])
6. **The pit-lane limit is 60 km/h.** ([R14S] Art. 14.5; [HFO])

---

## 1. Specifications

Where Ferrari published nothing for the Evo, the 458 Challenge figure is given and marked as such. The
2016 brochure [B16] describes the Evo and gives the same mechanical sheet as the 2010 car.

### 1.1 Engine

| Item | Value | Source | Confidence |
|---|---|---|---|
| Type | F136 90-degree V8, 4,499 cm3, bore 94 mm x stroke 81 mm (3.7 x 3.2 in), compression 12.5:1 | [B16] p.14; [MR] | documented |
| Tune | "strictly in production tune", as the 458 Italia | [FB10] | documented |
| Peak power | 570 CV (419 kW, 562 hp) at 9,000 rpm | [B16]; [FB10] | documented |
| Peak torque | 540 Nm at 6,000 rpm | [B16]; [FB10] | documented |
| Torque spread | Road 458: "over 80 per cent" of 540 Nm (at least 432 Nm) available from 3,250 rpm. Same engine tune, so it should carry over. | [F09] (Ferrari 2009 release) | likely |
| Torque at 9,000 rpm | Inferred: about 445 Nm (419.2 kW / (9,000 rpm x 2 pi / 60)) | computed | inferred |
| Full torque curve | Not published | - | unknown |
| Redline | 9,000 rpm. It is the power peak, and Wikipedia and The Drive call it the redline. | [WP]; [DRIVE] | likely |
| Limiter rpm | No source. The 9,200 rpm in the old specification ledger is user-supplied and unverified. | - | unknown |
| Idle rpm | No source | - | unknown |

### 1.2 Gearbox

| Item | Value | Source | Confidence |
|---|---|---|---|
| Type | 7-speed dual-clutch "F1" gearbox, electrically actuated. The brochure words it "7-Speed sequential gearbox electrically actuated". | [B16]; [FB10] | documented |
| Challenge ratios | Ferrari changed "the gear ratios and calibration" against the road car "to guarantee higher torque at lower revs". No source I could reach gives the numbers. | [FB10]; [FJ10] | documented that they changed; values unknown |
| Road 458 ratios (baseline only) | 1st 3.08, 2nd 2.18 (2.19 in one source), 3rd 1.63, 4th 1.29, 5th 1.03, 6th 0.84, 7th 0.69, final drive 5.14 | [WP] (table, no citation); germancarforum thread | likely for the road car; **not** the Challenge |
| Ledger's "overall reductions" 15.81 / 11.14 / 8.29 / 6.55 / 5.24 / 4.28 / 3.52 | From a December 2010 product note on Scribd, which is login-walled. Not verified. | - | unknown |
| Final drive (Challenge) | Not published | - | unknown |
| Shift times | Not published for the 458 Challenge. Context only: Wikipedia gives 60 ms for the F430 Challenge, its predecessor. | [WP-F430] | unknown |
| Neutral | Road 458: pull both paddles together | FerrariChat post; Starr Luxury Cars page (both via search) | likely for the road car; unknown for the Challenge |
| Reverse | A round "R" button at the front of the centre tunnel | photos `interior/014`, `015`; [HFO] | documented |

Inferred: road ratios with a 0.345 m rear tyre radius give these speeds. They are a starting point only;
the Challenge ratios are shorter by an unknown amount.

| Gear | Road ratio | Overall | km/h at 9,000 rpm | rpm at 60 km/h |
|---|---|---|---|---|
| 1 | 3.08 | 15.83 | 73.9 | 7,303 |
| 2 | 2.18 | 11.21 | 104.5 | 5,169 |
| 3 | 1.63 | 8.38 | 139.7 | 3,865 |
| 4 | 1.29 | 6.63 | 176.5 | 3,059 |
| 5 | 1.03 | 5.29 | 221.1 | 2,442 |
| 6 | 0.84 | 4.32 | 271.1 | 1,992 |
| 7 | 0.69 | 3.55 | 330.1 | 1,636 |

### 1.3 Mass

| Item | Value | Source | Confidence |
|---|---|---|---|
| Dry weight | 1,218 kg (2,815.4 lb) | [B16]; [MR] | documented |
| Race minimum weight | 1,383 kg, **with** the driver in racing kit (helmet and HANS), **without** fuel, other fluids at standard levels. Ballast kit if under. | [R14T] Art. 3 | documented |
| Kerb mass | Not published. Inferred: about 1,290-1,300 kg without driver and fuel, if driver plus kit weigh 85-95 kg. | - | unknown (estimate inferred) |
| Fuel tank | 113 L. Inferred: about 84 kg full at 0.745 kg/L. | [B16] | documented (capacity) |
| Weight distribution | 42 % front / 58 % rear | [MR] (no source given); road 458 release says "58 per cent over the rear axle" [F09] | likely |
| Other weights seen | 1,245 kg and 1,277 kg in two YouTube descriptions, with no source | - | not used |

### 1.4 Aero

| Item | Value | Source | Confidence |
|---|---|---|---|
| Evo changes | GT-style rear wing; new front splitter; a better-designed underbody. These "allowed the Ferrari engineers to fit stiffer front springs and improve the braking system". | [B16] p.14 | documented |
| Evo bodywork | GT3-style front bumper with a carbon splitter; a large rear wing "mounted solidly to the chassis"; only the bodywork changed against the 458 Challenge | [GC] (pro driver, February 2014) | likely |
| Kit origin | Front bumper and splitter, rear bumper, diffuser and spoiler derived from the 458 GT3 | [RMS] | likely |
| Kit status | Required on every 2014 Challenge car; sold as a kit for existing cars | [AG13] | documented (Ferrari quoted) |
| Downforce figure | None published by Ferrari or anyone I found | - | unknown |
| Successor comparison | The 488 Challenge's bumper is +7 % efficient and its bigger wing +9 %, both against the 458 Challenge EVO | Ferrari 488 Challenge page, seen in search summary only (the page renders empty to fetch) | likely |
| Wing adjustment | Each endplate has two lettered hole rows: A, C, E, G, I, M and B, D, F, H, L, N (12 holes) | photo `exterior/044`, `032` | documented |
| Wing position rule | Wing 13 +/- 5 mm below the top of the roof; rear edge at wing centre 1,675 +/- 5 mm from a body reference | [R14T] Art. 11 | documented |
| Splitter rule | 40 +/- 5 mm ahead of the front bumper; 1,150 +/- 2 mm from the front axle | [R14T] Art. 11 | documented |
| Ride heights in the rule | Front 86 mm (master point to ground), splitter 65 mm, rear 118 mm | [R14T] Art. 3 | documented (I read them as minimums; the full wording was not shown) |

### 1.5 Tyres and wheels

| Item | Value | Source | Confidence |
|---|---|---|---|
| Sizes | Pirelli 255/650 R19 front on 9 x 19 in; 305/690 R19 rear on 11 x 19 in | [B16]; [R14T] Art. 7; [MIQ] (front) | documented |
| Slick and rain | Same sizes; slick coded "DH", rain coded "WS" | [R14T] Art. 7 | documented |
| Per event | 8 slicks (4 front, 4 rear) and 4 rain tyres | [R14S] Art. 13.1 | documented |
| Rims | Centre-nut 19 in forged rims | [FB10] | documented |
| Radius | Inferred: about 0.325 m front and 0.345 m rear. The second number of race-tyre notation is the overall diameter in mm. | notation | likely |
| Camber limit | No more than -4.7 deg front, -3.7 deg rear | [R14T] Art. 8 | likely (the fetched layout was ambiguous about which value is front) |
| Pressures, compounds, force curves | Not found | - | unknown |

### 1.6 Brakes

| Item | Value | Source | Confidence |
|---|---|---|---|
| Discs | Carbon-ceramic. Front 398 x 38 mm, rear 380 x 34 mm. | [B16]; [MR] | documented |
| System | Brembo CCM2 (first seen on the 599XX), with ABS | [FB10]; [FJ10] | documented |
| Front calipers | Aluminium monobloc, 6-piston | [MIQ] | likely |
| Rear calipers | Not found | - | unknown |
| Fluid | Brembo Racing LCF 600 plus | [R14T] Art. 15 | documented |
| Evo change | "improve the braking system", no detail | [B16] | documented |

### 1.7 Steering

| Item | Value | Source | Confidence |
|---|---|---|---|
| Ratio | Road 458: 11.5:1 | [WP], citing Car and Driver | likely for the road car; unknown for the Challenge |
| Lock to lock | Road 458: 2.0 turns | Autocar and Auto Express (via search summary, not fetched) | likely for the road car |
| Road-wheel lock | Inferred: about +/- 31 deg (360 deg / 11.5) if both road figures apply | computed | inferred |
| Challenge wheel | "No restriction on type and dimensions", may be fitted with spacers; the wheel is detachable | [R14T] Art. 12; [HFO] | documented (rule); likely (detachable) |

### 1.8 Suspension

| Item | Value | Source | Confidence |
|---|---|---|---|
| Set-up | "steel uniball joints, stiffer springs, single-rate alloy dampers" | [FB10] | documented |
| Ride height | Lowered 50 mm against the road car (December 2010 release). The July 2010 release said 30 mm. | [FB10]; [FJ10] | documented, with a conflict between releases |
| Evo | Stiffer front springs | [B16] | documented |
| Rear anti-roll bar | The only part that may be removed | [R14T] Art. 8 | documented |
| Conflicting claims | MotoIQ mentions "SCM2 magnetorheological dampers"; an owner's video description says MagneRide was replaced by coil-overs. Ferrari's own wording (single-rate dampers) wins. | [MIQ]; [ATN] | conflict noted |
| Spring, damper and bar rates | Not found | - | unknown |

### 1.9 Electronics

| Item | Value | Source | Confidence |
|---|---|---|---|
| Manettino positions | OFF (traction control deactivated), 1, 2. Positions 1 and 2 have "progressively higher levels of control system intervention", chosen by track grip. | [FB10] (two reprints); photo `interior/010` | documented |
| What it selects | ABS/EBD, E-Diff and F1-Trac calibrations | [FB10] | documented |
| Use in practice | 2 for new or worn tyres and rain; Ferrari engineers told the author a professional is as fast on OFF or 1 | [HFO] | likely |
| Early naming | The July 2010 debut release used WET, DRY and CT-OFF. The production wording (December 2010) and the photo car use OFF, 1, 2. | [FJ10]; [FB10] | documented (history) |
| ABS modes | Two configurations, "low grip" and "high performance for dry surfaces" (July 2010 wording) | [FJ10] | likely |
| Does OFF disable ABS? | No source says it does. OFF is described as traction control off only. | - | unknown |
| E-Diff | E-Diff (E-Diff3 in [MR]), fully integrated with F1-Trac | [FB10]; [MR] | documented |
| Data and display | Magneti Marelli race instrument cluster with data logging | [ATN] (owner's description) | likely |
| Fault flags on the display | ABS FAIL, TCS FAIL, EDIFF FAIL, BRAKE FAIL | photo `interior/004` | documented |

### 1.10 Performance

| Item | Value | Source | Confidence |
|---|---|---|---|
| Fiorano lap | 1'16.5" for the 458 Challenge (not the Evo), 2 s faster than the F430 Challenge | [FB10]; [WP] | documented |
| Lateral grip | "up to 1.6G" | [FB10] | documented |
| 0-100 km/h | Under 3.4 s | [MR] | likely |
| Top speed | No Ferrari figure. Unverified claims: "nearly 200 mph" at Daytona (Motor Authority), "210 mph" (a dealer). | search results | unknown |
| Gearing limit | Inferred: about 330 km/h in 7th at 9,000 rpm with road ratios. A gearing ceiling, not a top speed; drag with the Evo wing will cap it lower. | computed | inferred |
| Braking feel | "stops suddenly even from 220 km/h" | [HFO] | likely |
| Evo lap times | None from an official source | - | unknown |

### Implications for Drive Lab

- The engine has three anchor points: at least 432 Nm from 3,250 rpm, 540 Nm at 6,000 rpm, about
  445 Nm at 9,000 rpm. Everything between them is a tunable estimate and should be labelled so.
- Run the car at **1,383 kg with the driver**, plus fuel (0 to about 84 kg). The dry 1,218 kg is not a
  running mass. Use 42/58 front/rear and mark it likely.
- The Challenge gear ratios are not public. Start from the road ratios with a 5.14 final drive, expose them
  as tunables, and never call them factory Challenge values. Do not multiply the ledger's "overall
  reductions" by a final drive.
- Tyre radii 0.325 m front and 0.345 m rear; discs 398 mm front and 380 mm rear. Drive Lab configs are in
  metres, so these go in as is.
- The manettino changes intervention only (traction control, and the ABS and E-Diff calibrations). It must
  not add power or grip, which matches the ledger's rule.
- Treat 9,000 rpm as the redline. The limiter rpm is a tunable and stays on the not-verified list.
- No downforce numbers exist. The downforce coefficient is an estimate. If the wing angle is exposed, the
  real car has 12 holes, A to N.
- Steering 11.5:1 and 2 turns lock to lock are road-car values; expose them.

---

## 2. Cockpit controls

The photo car is left-hand drive (photos `interior/001`, `002`).

### 2.1 Steering wheel (photos `interior/010`, `001`)

| Position | Label (colour) | What it does | Source | Confidence |
|---|---|---|---|---|
| Upper-left pod | FLASH (red) | Headlight flash, high beam | [HFO] | likely (label documented by photo) |
| Upper-left pod | PIT (blue) | Pit-lane limiter. Press once in 2nd gear below 60 km/h; after that, the throttle holds 60 km/h. | [HFO] | likely (one first-hand source) |
| Upper-right pod | SCROLL (blue) | Changes the dash display page | [HFO] | likely |
| Upper-right pod | RADIO (red) | Push-to-talk to the pit crew | [HFO] | likely |
| Left grip | yellow button, labelled LEFT | Left turn signal | [HFO]; photo | likely |
| Right grip | yellow button, labelled RIGHT | Right turn signal | [HFO]; photo | likely |
| Lower-left pod | WATER (red) | Windscreen washer | [HFO] | likely |
| Lower-left pod | WIPER (blue) | Front wiper (the car has one wiper arm, photo `interior/032`) | [HFO] | likely |
| Lower-right | Rotary manettino, OFF / 1 / 2, lever knob with a red tip | See 1.9 | [FB10]; photo | documented |
| Rim | Suede, red marker at 12 o'clock | - | photo | documented |
| Behind the wheel | Two long paddles mounted on the column: left marked DOWN, right marked UP | Downshift / upshift; "slightly longer than the road car's" | photo; [HFO] | documented (labels); likely (column-fixed, as on the road 458) |
| Neutral | No third paddle visible | Road 458: both paddles pulled together | forum sources | likely for the road car; unknown for the Challenge |
| Hub | Quick-release; a coiled cable runs from the wheel to the column | The wheel is detachable | [HFO]; photos `interior/001`, `024` | likely / documented |

### 2.2 Centre switch panel (photo `interior/013`; also `017`, `024`, `002`)

A carbon box hung below the centre of the dash, with yellow labels and a green LED beside each toggle.

| Position | Control | What it does | Source | Confidence |
|---|---|---|---|---|
| Top left | Toggle under a red flip-up guard (no label on this car) | IGNITION | [HFO] ("IGNITION switch with cover") | likely |
| Below it | Red push button "ENGINE START" | Starts the engine | photo; [HFO] | documented |
| Top centre | "LIGHT" toggle + green LED | Headlights | photo; [HFO] | documented (label); likely (function) |
| Bottom centre | "RAIN LIGHT" toggle + green LED | Rear rain light | photo; [HFO] | documented (label) |
| Top right | "AC ON / OFF" toggle + green LED | Air conditioning on/off | photo; [HFO] | documented |
| Bottom right | "AC FAN" rotary 0 / 1 / 2 / 3, blue knob | Blower speed | photo; [HFO] | documented |

The brief's fire-extinguisher and master-switch controls are not on this panel; they are on the tunnel.
The only "fan" control is the AC fan.

### 2.3 Centre tunnel (photos `interior/014`, `015`, `016`, `017`)

| Position | Control | What it does | Source | Confidence |
|---|---|---|---|---|
| Front of tunnel | Round button marked "R" on a carbon wedge | Reverse | photo; [HFO] ("reverse button below the centre console") | documented (label); likely (function) |
| Middle | Red removable key | Battery master switch (the rule requires a battery circuit breaker) | photo; [R14T] Art. 16 | likely (identification) |
| Rear, under an "E" sticker | Red push button in a recess | Fires the extinguisher system. An SPA Design FireSense controller sits behind the seat (photo `mechanical/006`), so it is electrically fired. | photos | likely |
| Tunnel side | Motorola two-way radio | Radio (permitted by [R14S] Art. 15.2) | photo | documented |
| Outside the car | "externally wired power cut-off lever" | External cut-off | [HFO] | likely; location not found in the photos |

### 2.4 Dash display and its pages (photos `interior/011`, `004`, `012`)

The display sits in the binnacle under a row of 8 LEDs. Its firmware line reads `DDU3_v35F458_09`.
Three pages are visible in the photo set. SCROLL changes pages ([HFO]). Whether more pages exist is unknown.

| Page | Fields seen (exact labels) | Confidence |
|---|---|---|
| Driving page (`011`) | rpm bar along the top, marked 2 to 9 (x1000 rpm), red fill; `TCS` [OFF]; `POS` [OFF]; large `GEAR` letter (N); `SPEED`; `OIL P`; `P FUEL`; `WATER T`; `OIL T`; a blue box with "R" at bottom left | documented (photo) |
| CHASSIS - BODY (`004`) | `ABS FAIL`, `TCS FAIL`, `EDIFF FAIL`, `BRAKE FAIL`, `FRONT DISK` (32), `REAR DISK` (30), `BRAKE OIL`, `PAD WEAR`, `ODOMETER` (16208), `MANETTINO` (0), `DDU FIRMWARE` | documented (photo) |
| MECHANIC (`012`) | `RPM`, `FUEL %`, `CHECK`, `V_BATT`, `T_WATER`, `ANGLE`, `TOIL ENGINE`, `P_OIL`, `P CARTER`, `TOIL GEAR`, `P_FUEL` | documented (photo) |

Unknown: what `POS` and the blue "R" box mean, the unit of FRONT/REAR DISK, and whether `ANGLE` is steering angle.

### 2.5 Start-up procedure

No published Ferrari start procedure for the 458 Challenge was reachable (no public manual; Corse Clienti
documentation is not online). The controls and their places are documented; **the order below is my
inference** from the switch layout, one driver report and road-458 practice.

| Step | Action | Confidence |
|---|---|---|
| 1 | Turn the red master key on the tunnel to ON | likely (the key is documented; that it comes first is inferred) |
| 2 | Lift the red guard and switch IGNITION on | likely ([HFO] + photo) |
| 3 | Wait for the display to finish its start-up | unknown (road-458 owners wait for the dash lights) |
| 4 | Hold the brake pedal | unknown (road-458 practice; not confirmed for the Challenge) |
| 5 | Press ENGINE START, below the ignition toggle | likely ([HFO] + photo) |
| 6 | With the brake held, pull UP for 1st; press R on the tunnel for reverse | likely (labels documented; the brake condition is inferred) |
| 7 | Set the manettino; LIGHT and RAIN LIGHT as needed | documented (the controls exist) |
| 8 | Pit lane: PIT in 2nd below 60 km/h | likely ([HFO]) |
| Stop | IGNITION off, then the master key. Rule: the engine is switched off at once at any pit stop. | inferred order; documented rule ([R14S] Art. 19.2) |

### Implications for Drive Lab

- Build to the corrected list: the yellow buttons are the indicators, SCROLL pages the dash display, the
  screen is in the binnacle, there are two paddles only, and the master key and extinguisher are on the
  tunnel.
- For the animator (left-hand drive): wheel buttons are thumb presses from the grips. The switch panel,
  the tunnel controls (R, master key, extinguisher) and the AC dial are right-hand reaches.
- Drive Lab's car already publishes readouts as attributes. Candidates for this car: ignition, master
  switch, manettino position (OFF/1/2), pit limiter, lights, rain light, AC on, AC fan (0-3), indicator
  left/right, wiper, washer, display page, radio push-to-talk.
- The PIT arming conditions (2nd gear, under 60 km/h) come from one source. Keep them as config values.
- The start order is inferred. If the owner wants it exact, it needs a Challenge driver's briefing or a
  Corse Clienti document, which I could not reach.

---

## 3. What the driver sees and hears

### 3.1 Shift lights

| Item | Value | Source | Confidence |
|---|---|---|---|
| Layout | 8 LEDs in a carbon strip on top of the display housing: one at each end, six close together in the middle | photos `interior/004`, `011`, `012` | documented |
| Colours | The rev LEDs go "quickly from green to red zone" | [HFO] | likely |
| Per-LED colours and rpm thresholds | Not found for the 458 Challenge | - | unknown |
| Analogy (successor car) | On the 488 Challenge wheel (same 1 + 6 + 1 layout): middle six = revs; left = blue fault light; right = white pit-limiter light; both steady when on; hazard lights flash while the limiter is on | [FC488] (forum, 2019) | unknown for the 458 |

### 3.2 Rain light

| Item | Value | Source | Confidence |
|---|---|---|---|
| Switch | RAIN LIGHT toggle with a green LED on the centre panel | photo `interior/013` | documented |
| Where it is on the car | Not identified in the photos or any source. The lettered plates on the wing endplates are the wing adjuster, not lights. | - | unknown |
| Flash pattern | Not found | - | unknown |

### 3.3 Pit limiter

| Item | Value | Source | Confidence |
|---|---|---|---|
| Limit | 60 km/h: "Car speeds must never exceed 60 km/h at any time in the pit-lane" (Europe, 2014) | [R14S] Art. 14.5 | documented |
| Behaviour | Press PIT in 2nd gear below 60 km/h; the throttle then holds 60 km/h | [HFO] | likely |
| Indicator | Not found for the 458. On the 488: white LED, a cluster warning, flashing hazards. | [FC488] | unknown |
| North America limit | Not found | - | unknown |

### 3.4 Sound

| Item | Value | Source | Confidence |
|---|---|---|---|
| Engine | 90-degree V8 with a flat-plane crank: even firing that alternates banks, often described as two inline-fours | forum summaries via search (not fetched) | likely |
| Firing frequency | Inferred: 4 firing pulses per crank turn, so frequency = rpm / 15 Hz: 600 Hz at 9,000 rpm, 400 Hz at 6,000 rpm, about 67 Hz at 1,000 rpm | physics | inferred |
| Exhaust exit | Two large round tailpipes, centred low in the rear valance (the road car has three outlets) | photos `exterior/035`, `036`; `REFERENCE_SOURCES.txt` note | documented |
| Loudness | FF Corse sells a 458 Challenge twin silencer rated "under 105 dB" for track days. Inferred: the factory exhaust is loud enough that one is sold; its level is unknown. Forum reports put track limits at 90-105 dB. | FF Corse page (via search; now 404); forum | likely |
| Downshifts | Many recordings are titled "loud downshifts". That the gearbox blips the throttle on downshifts is road-458 behaviour; not documented here. | video titles (not listened to) | likely |
| Pops and bangs | No written source on when it pops or bangs | - | unknown: listen to the recordings in section 4 |
| Brakes glowing | Several recordings are titled "glowing brakes" (Monza, hard braking) | video titles (not watched) | likely |

### Implications for Drive Lab

- Shift lights: model 8 LEDs (1 + 6 + 1). Green-to-red for the middle six is likely. Which rpm lights
  which LED, and the end-LED colours, are gaps; keep them in config.
- Pit limiter: 60 km/h. The arming rules come from one source, and the indicator is unknown.
- Rain light: the switch is real, but its position on the body is unknown. Ask the owner or find a
  photo of the Dream Racing car before modelling it.
- Sound: the firing frequency gives the pitch at each rpm. Pops and bangs need listening, not invention.

---

## 4. Sound sources

I read each video's length, date and description from its public watch page. **I did not listen to any
of them.** The content column comes from the title and the description only. Captions were not available
to fetch. All are copyrighted YouTube uploads, for reference listening only: not to rip, not to upload to
Roblox.

### 4.1 Exterior recordings

| Video | URL | Length | Recorded | Content (from title/description) | Car |
|---|---|---|---|---|---|
| NM2255, "Ferrari 458 Challenge Exhaust Note - Start, Accelerations and Downshifts!!" | https://www.youtube.com/watch?v=uljtss1i7yM | 3:53 | uploaded 2010-10-18 | start-up, revving, accelerations, fly-bys, loud downshifts | 458 Challenge |
| NM2255, "2014 Ferrari 458 Challenge Evolution Exhaust Note" | https://www.youtube.com/watch?v=81jC6moJEeE | 2:03 | uploaded 2013-12-30, Monza | on track, exhaust note | Evo |
| 19Bozzy92, "Ferrari 458 Challenge Evo 2014 Sound On Track" | https://www.youtube.com/watch?v=WQ0DSkVF5W4 | 5:41 | Monza collective test, March 2014; Canon DM-100 mic | on track, several Evos | Evo |
| 19Bozzy92, "Ferrari 458 Challenge Evoluzione Sound & INSANE Glowing Brakes" | https://www.youtube.com/watch?v=NG2QymJIrAI | 3:12 | Monza test, 2016 | on track, braking | Evo |
| A8C100, "2014 Ferrari 458 Challenge EVO - Glowing Brakes & Pure V8 Sound!!" | https://www.youtube.com/watch?v=i7bknohg9hw | 2:22 | Monza, 2014 season opener | racing, hard braking | Evo |
| Belgian-Motorsport, "Ferrari 458 challenge EVO - V8 sounds at Hockenheim 2016" | https://www.youtube.com/watch?v=IY6D5WrnEws | 6:19 | Hockenheim, 9-11 Sept 2016; Rode VideoMic Pro | keywords list idle and revs | Evo |
| Jamboolio, "Ferrari 458 Challenge EVO - Epic V8 Sounds and Racing on Track" | https://www.youtube.com/watch?v=PsIThYJr4W4 | 3:34 | Hungaroring, Ferrari Racing Days 2015 | pack racing | Evo |
| cvdzijden, "Ferrari 458 Challenge Sound & Downshifts!!" | https://www.youtube.com/watch?v=-Q9qfIg-hpE | 3:36 | Spa track day, May 2011 | fly-bys, downshifts | 458 Challenge |
| 19Bozzy92, "Ferrari 458 Challenge Sound On Hillclimb - Accelerations & Downshifts!" | https://www.youtube.com/watch?v=PHhZam0IGyY | 5:40 (search listing) | hillclimb | accelerations, downshifts | 458 Challenge |

### 4.2 Start-up and idle

| Video | URL | Length | Content | Car |
|---|---|---|---|---|
| AutoTechNick, "Ferrari 458 Challenge Car Start Up Sequence" | https://www.youtube.com/watch?v=aWDnHxQb7Ng | 0:21 | driver's-eye cockpit view of a start-up | 458 Challenge |
| Richard Fain, "Ferrari 458 Challenge Race Car - Start-up & Exhaust Sound" | https://www.youtube.com/watch?v=q6JcKDXkjXQ | 2:32 | start-up, exhaust | 458 Challenge |
| ExoticCarspotters, "Ferrari 458 Challenge - Start Up, Loud Revs !" | https://www.youtube.com/watch?v=BtkH7uSe5QE | 5:17 | start-up, revs, loading onto a trailer (Antwerp) | 458 Challenge |

### 4.3 Onboard

| Video | URL | Length | Content | Car |
|---|---|---|---|---|
| "On board - Ferrari 458 Challenge EVO in Sepang 2014" | https://www.youtube.com/watch?v=LG03EHDjefE | 2:29 | onboard, driver Paul van Lohenhout; credited "(c) Ferrari S.p.A." in the description (a re-upload) | Evo |
| Jiri Linhart, "Ferrari 458 Challenge Evo - Hot Lap - Velocita" | https://www.youtube.com/watch?v=mZiJxDOrv9Y | 2:19 | full lap, Autodrom Most, driver Dan Zelinsky | Evo |
| BTGDale, "Pistonheads test: Ferrari 458 Challenge EVO at Dubai Autodrome" | https://www.youtube.com/watch?v=DwzzGnoDHAw | 3:10 | magazine test; onboard/exterior mix unknown | Evo |
| Charlie Ferer, "First Drive in my New FERRARI 458 CHALLENGE EVO Racecar!" | https://www.youtube.com/watch?v=8ZNt79Ht9l8 | 11:13 | first drive of a road-titled Evo, about 4,000 miles; start-up and cockpit likely but not verified | Evo |
| Misha Charoudin, "Ferrari 458 Challenge Goes FULL SEND! // Nurburgring" | https://www.youtube.com/watch?v=pVXSUxzoevk | 18:13 | chapters: 0:00 intro/specs, 2:52 lap 1, 10:09 lap 2, 16:46 impressions; set-up by a tuner, may be modified | 458 Challenge |
| Alexander Koreiba, "ONBOARD FERRARI 458 CHALLENGE AT COTA" | https://www.youtube.com/watch?v=dudVKAlhGQw | 2:28 | onboard, Circuit of the Americas, used tyres | 458 Challenge |

### 4.4 Official Ferrari videos

| Video | URL | Length | Content |
|---|---|---|---|
| Ferrari, "The new 458 Challenge" | https://www.youtube.com/watch?v=N5OcMtK4JeM | 4:07 | Valencia launch, December 2010; test drivers De Simone and Mediani |
| Ferrari, "Marc Gene introduces the 458 Challenge EVO" | https://www.youtube.com/watch?v=Lz7n9fK0qtw | 1:38 | Evo walk-round: brakes and the new wing |

### 4.5 Licensable library (road car)

No library of the 458 Challenge exists that I found. The nearest: **Pole Position, "Ferrari 458 2013"** on
Sonniss, https://sonniss.com/sound-effects/ferrari-458-2013/ . It is the road 458 (same F136 engine, road
exhaust): 197 files, 14.2 GB, 96 kHz / 24-bit. The page lists engine, exhaust and interior microphones
plus four exterior positions, 29 channels and 10 synchronised takes, at US$249, "royalty free forever".
Game use is not stated on the page; read the licence before buying.

### Implications for Drive Lab

- These are references for listening, not assets. Anything that ships needs a licence, and the owner
  decides any purchase. Drive Lab's audio uploads are rationed (100 per 30 days).
- Best references for the sound designer: start-up (`aWDnHxQb7Ng`, `uljtss1i7yM`), Evo on track
  (`81jC6moJEeE`, `WQ0DSkVF5W4`), Evo onboard (`LG03EHDjefE`, `mZiJxDOrv9Y`).
- None of this has been listened to. Idle rpm, downshift blips and pops must be confirmed by ear.

---

## 5. Cockpit inventory checklist (3D artist)

Every item below is visible in the named local photo unless the row says otherwise. Left-hand drive.

| # | Object | What the photo shows | Local photo(s) | Confidence |
|---|---|---|---|---|
| 1 | Roll cage | Main hoop behind the seat; tubes along both A-pillars; roof cross and diagonal tubes; several door bars on the driver side; rear tubes to the bulkhead; some padding | `interior/003`, `005`, `006`, `020`, `021`, `022`, `023`, `026` | documented |
| 2 | Driver seat | Sabelt Titan Carbonio XL, FIA 8855-1999, red cloth, prancing horse, harness slots | `interior/007`, `020`; label `other/008` | documented |
| 3 | Harness | Sabelt, red webbing with yellow "Sabelt" labels; the rule requires 6 points | `interior/007`, `020`; `mechanical/006`; [R14T] Art. 16 | documented |
| 4 | Window net | Black mesh across the driver's door opening, yellow straps to the cage. RM Sotheby's says US cars had nets in place of Lexan side windows. | `interior/005`, `028` | documented (photo); likely (US reason) |
| 5 | Passenger side | No passenger seat on this car; the cool-shirt box and the extinguisher sit there. RM's 2013 car had a removable passenger seat, so this varies. | `interior/003`, `002` | documented for this car; unknown for Dream Racing |
| 6 | Cool-shirt box | White "COOLSHIRT" cooler with a handle and latches; "DUAL FLOW CONTROLLER" plate (WATER / AIR); black insulated hoses | `interior/001`, `003`, `008`, `009`, `016` | documented |
| 7 | Extinguisher bottle | Red cylinder on the passenger floor | `interior/002`, `008`, `009`, `015`, `016`, `017` | documented |
| 8 | Extinguisher button | Red push button in a recess at the rear of the tunnel, under an "E" sticker | `interior/015`, `016`, `017` | documented |
| 9 | Extinguisher controller | Red SPA Design "FireSense" box (battery check, system check) behind the seat | `mechanical/006` | documented |
| 10 | Master switch | Red removable key on the tunnel | `interior/015`, `017`, `002` | documented (object) |
| 11 | Reverse button | Round "R" button on a carbon wedge, front of the tunnel | `interior/014`, `015` | documented |
| 12 | Radio | Motorola mobile radio on the side of the tunnel; a "Racing Radios" interface box behind the seat | `interior/015`, `017`; `mechanical/006` | documented |
| 13 | Centre switch panel | Carbon box with 4 toggles, a guarded toggle, ENGINE START, the AC FAN dial, yellow labels, green LEDs | `interior/013`, `017`, `024`, `002` | documented |
| 14 | Steering wheel | Suede rim, red 12 o'clock marker, black plate with 8 buttons and the manettino, yellow Ferrari badge | `interior/010`, `001` | documented |
| 15 | Paddles | Two long paddles behind the wheel, "DOWN" left, "UP" right | `interior/010` | documented |
| 16 | Steering column | Column shroud; quick-release hub; coiled cable from the wheel | `interior/001`, `002`, `024` | documented |
| 17 | Dash binnacle | Carbon housing with the 8-LED strip, colour display, "458 Challenge" script and a horse | `interior/004`, `010`, `011`, `012` | documented |
| 18 | Dashboard | Alcantara top and lower panel with red stitching; road-car air vents left of the binnacle and in the centre | `interior/002`, `018` | documented |
| 19 | Diagnostic panel | Passenger-side lower dash: a 16-pin OBD socket and a round 4-pin motorsport connector. The rule requires a working OBD socket. | `interior/018`; [R14T] Art. 5 | documented |
| 20 | Data logger | No separate box visible. Logging is in the Magneti Marelli cluster and ECU per an owner's description. Inferred: the dash connector is the download point. | [ATN] | likely / unknown position |
| 21 | Rear-view mirror | Top centre of the windscreen | `interior/002` | documented |
| 22 | Door card | Carbon-fibre panel with a moulded pull recess and a small wire loop | `interior/019`, `027`, `028`, `029`, `030`, `031` | documented |
| 23 | Sill | Sill and door-opening edge | `interior/026` | documented |
| 24 | Floor | Black diamond tread-plate panels; driver footwell | `interior/024`, `014`, `015`, `025` | documented |
| 25 | Pedals | Two pedals with drilled alloy pads: wide brake on the left, narrower floor-hinged throttle on the right; no clutch | `interior/024` | documented |
| 26 | Air ducts | Silver flexible hose along the passenger A-pillar with a perforated metal end at the top; black corrugated hoses to the cooler and the rear bulkhead | `interior/001`, `002`, `003`, `008`, `009`, `020` | documented (objects); function unknown |
| 27 | Wiring | Exposed looms under the dash and in the passenger footwell | `interior/002`, `024` | documented |
| 28 | Battery | On the passenger floor, held by two steel straps, red positive cable | `interior/025`, `002` | documented |
| 29 | Rear bulkhead | Black panels behind the seat with cage tubes and hoses | `interior/020` | documented |
| 30 | Sensor module | Bosch module (label 0 265 005 616) behind the seat; function not identified | `mechanical/006` | documented (object); function unknown |
| 31 | Glazing | Windscreen etched "Saint-Gobain Sekurit Only for race" and Isoclima; Lexan side windows per Ferrari | `other/001`, `002`, `003`; [FB10] | documented |
| 32 | Two webbing straps | Black straps with buckles and red pull tabs hanging from the dash either side of the switch panel | `interior/013`, `017`, `002` | documented (objects); function unknown |

### Implications for Drive Lab

- The local set covers every item the brief lists except a visible data logger and the rain light.
- The photo car is not the Dream Racing car. Its passenger side (cooler and extinguisher, no seat) and
  its window net may differ on the Dream Racing car. Confirm with the owner's screenshot or a Dream Racing
  photo before modelling the passenger side.
- The wheel and panel labels are legible at full resolution in `interior/010` and `013`. Model the labels
  from those.

---

## Not verified and gaps

- The Challenge gear ratios, final drive, shift times, limiter rpm, idle rpm, full torque curve.
- Downforce numbers for the Evo kit; drag; the centre of mass height.
- Steering ratio and lock for the Challenge (road-car values only); rear caliper pistons; damper, spring
  and bar rates; tyre force data and pressures.
- Top speed and any official Evo lap time.
- The start-up order (inferred) and whether the brake must be held to start.
- Neutral selection on the Challenge (the road car uses both paddles).
- Shift-light colours per LED and their rpm thresholds; the end-LED meanings (only a 488 analogy).
- The pit limiter's indicator, and the North American pit-lane limit.
- The rain light's position and flash pattern.
- The meaning of `POS`, the blue "R" box and the DISK values on the display.
- When the car pops or bangs. None of the recordings were listened to.
- The Dream Racing car's own configuration (passenger seat, net, display firmware).
- Not reachable by fetch: Scribd (login), Eurospares parts diagrams (anti-bot challenge), Cars & Bids,
  lapmeta, the FerrariChat 488 thread through the fetch tool (read with plain curl instead), ferrari.com
  pages (they render empty), YouTube captions.
- The two-turn lock-to-lock figure, the flat-plane crank and the 488 aero percentages come from search
  summaries; I did not open those pages.

## Sources

- **[B16]** Ferrari, "Attivita, modelli, programmi" 2016 Ferrari Challenge brochure, PDF p.14:
  https://seehuusenjuhl.dk/lemans2016/FERRARI-CHALLENGE-BROCHURE.pdf (byte-identical to the repository's
  `ferrari_challenge_2016.pdf`).
- **[R14S]** / **[R14T]** Ferrari Challenge Trofeo Pirelli, Europe 2014, sporting and technical regulations
  (technical part admits "458 Challenge EVO", ref. 4716/14), mirror:
  https://doczz.net/doc/4330410/regolamento-sportivo-e-tecnico---corse-clienti
- **[FB10]** Ferrari release, Bologna, 2 December 2010, reprinted at
  https://www.theautochannel.com/news/2010/12/03/509340.html and https://mitorosso.com/458-challenge/
- **[FJ10]** Ferrari release, Maranello, 14 July 2010, reprinted at https://mitorosso.com/458-challenge/
- **[MR]** Mitorosso specification table (no source named): https://mitorosso.com/458-challenge/
- **[F09]** Ferrari 458 Italia release, 28 July 2009, reprinted at
  https://www.automotiveaddicts.com/5830/ferrari-officially-announces-the-458-italia
- **[HFO]** Hideki Francis Onda, driving report, 2 December 2010, reposted at
  https://teamspeed.com/forums/458-430-360/51289-ferrari-458-challenge-driven-reviewed.html
- **[GC]** Guy Cosmo, "Driving the 2014 Ferrari 458 Challenge EVO", 5 February 2014:
  https://www.guycosmo.com/blog/2014/2/5/driving-the-2014-ferrari-458-challenge-evo
- **[RMS]** RM Sotheby's, 2013 458 Challenge Evoluzione lot:
  https://rmsothebys.com/auctions/mo15/lots/r157-2013-ferrari-458-challenge-evoluzione
- **[AG13]** AutoGuide, November 2013:
  https://www.autoguide.com/auto-news/2013/11/ferrari-458-challenge-evoluzione-gets-upgraded-available-in-coming-weeks.html
- **[MIQ]** MotoIQ, Scuderia Algar 2011 Ferrari Challenge team:
  https://motoiq.com/scuderia-algar-sierra-sierra-enterprises-2011-ferrari-challenge-team/4/
- **[WP]** Wikipedia, Ferrari 458: https://en.wikipedia.org/wiki/Ferrari_458 ; **[WP-F430]**
  https://en.wikipedia.org/wiki/Ferrari_F430_Challenge
- **[DRIVE]** The Drive, 27 April 2017:
  https://www.thedrive.com/watch-this/9765/sound-comparison-ferrari-458-challenge-vs-488-gt3
- **[ATN]** AutoTechNick video description: https://www.youtube.com/watch?v=aWDnHxQb7Ng
- **[FC488]** FerrariChat, "488 Challenge Steering wheels", posts of 2 July 2019:
  https://www.ferrarichat.com/forum/threads/488-challenge-steering-wheels.601651/
- Sonniss / Pole Position, Ferrari 458 2013: https://sonniss.com/sound-effects/ferrari-458-2013/
- Local photos: Cars & Bids 2015 458 Challenge Evoluzione listing, archived at
  `references/2015_challenge_evoluzione/` in the DR458 modelling pipeline repository (`dr458-modeling-pipeline`).
