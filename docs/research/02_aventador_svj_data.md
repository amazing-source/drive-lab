# 02 · Lamborghini Aventador SVJ (LP 770-4 coupé): mechanical data

Research date and access date for every source: **2026-10-27**. Web search and web fetch only. No game files were opened.

## How to read this file

Every value has a status code:

| Code | Meaning |
|---|---|
| **OEM** | Lamborghini, for the SVJ coupé |
| **OEM-S** | Lamborghini, for the **Aventador S** (the same platform). The SVJ value is not published separately, so the S value is carried over. Flagged each time. |
| **REG** | Filed by the manufacturer with a regulator (US EPA test-car list) |
| **TEST** | Measured by a named outlet. "via X" means the number was read on a third-party page, not on the outlet's own page. |
| **PRESS** | Reported by the press, not measured |
| **DATA** | Specialist data site that does not name its source |
| **DER** | Calculated here from sourced values. The method is given in the notes. |
| **EST** | Estimated here. The method is given in the notes. Treat as a starting value for calibration. |

Source numbers `[n]` point to section 3.

**Access limits that shape this file.** Car and Driver and MotorTrend block this research tool, so their numbers appear only second-hand (via Wikipedia, 0-60specs and FastestLaps). Autocar and CAR Magazine are paywalled, and some FastestLaps test pages need a login. Values only visible on login pages were not used. The old Lamborghini media site (media.lamborghini.com) now redirects to lamborghini.com, so the SVJ coupé press release is quoted through faithful reproductions (Motor1, CompleteCar, GTspirit). The official Aventador S press kit PDF was still online.

### Five things to know before using the numbers

1. **The 2.867 final drive cannot be the whole reduction.** Lamborghini publishes "final drive (rear – front) 2.867 – 3.273" [2]. With the real tyre sizes, the EPA engine-speed ratio (36.6 rpm per mph in 7th [3]) only works with an overall rear reduction of about **3.52** after the gearbox. The same 3.52 also follows from the front axle ratio and the front/rear tyre sizes (§2.5). **Use 3.52 in the simulation.** With 2.867 the car would be geared about 23 % too long.
2. **Dry weight is not simulation weight.** 1,525 kg dry [1] against about 1,770 kg with fluids, measured by MotorTrend [9]. The simulation mass is **1,845 kg** (§2.2).
3. **Aerodynamics: only relative figures are official** (+40 % downforce and −1 % drag compared with the SV). Absolute values here come from a coast-down calculation using EPA data (CdA ≤ 0.68–0.74 m²) and from one unverified press claim (350 kg at 300 km/h). The front/rear downforce split is unknown.
4. **No published torque curve exists that could be traced.** The curve in §2.4 is a shape fitted to two official anchor points. It is **not** digitised from a chart.
5. **Centre-of-gravity height and moments of inertia are estimates** from a lumped-mass model (§2.3). Together with the tyre grip level, they are the most uncertain inputs.

---

## 1. Master table

### 1.1 Dimensions

| # | Parameter | Value (SI) | Other units | Status | Source | Note |
|---|---|---|---|---|---|---|
| D1 | Overall length | 4.943 m | 194.6 in | OEM | [1] | Aventador S: 4.797 m [2]. The SVJ bumpers are longer. |
| D2 | Width without mirrors | 2.098 m | 82.6 in | OEM | [1] | |
| D3 | Width with mirrors | 2.273 m | 89.5 in | OEM | [1] | |
| D4 | Height | 1.136 m | 44.7 in | OEM | [1] | |
| D5 | Wheelbase | 2.700 m | 106.3 in | OEM | [1] | |
| D6 | Front track | 1.720 m | 67.7 in | OEM-S, DATA | [2] [16] [7] | km77 says the SVJ track is the same as the S/SV [10]. Lambocars prints "11720" (a typo) [7]. |
| D7 | Rear track | 1.680 m | 66.1 in | OEM-S, DATA | [2] [16] [7] | |
| D8 | Ground clearance | 0.115 m ± 0.002 | 4.5 in | OEM-S, DATA | [2] [7] | The front lift raises the front to 0.155 m [2] |
| D9 | Total overhang (front + rear) | 2.243 m | — | DER | D1 − D5 | |
| D10 | Front / rear overhang split | ≈ 1.12 / 1.12 m (± 0.10) | — | EST | Side frame from the official 360° viewer [1] | Measured on a perspective image and scaled to D9. Low confidence. |
| D11 | Fuel tank | 85 L | 22.5 US gal | OEM-S, DATA | [2] [7] | Engine oil 13 L, coolant 25 L [2] |

### 1.2 Mass

| # | Parameter | Value | Status | Source | Note |
|---|---|---|---|---|---|
| M1 | Dry weight | 1,525 kg (3,362 lb) | OEM | [1] | km77 explains "dry" as without fluids [10] |
| M2 | Weight distribution front / rear | 43 % / 57 % | OEM | [1] | Dry basis. With a driver it stays at about 43.4/56.6 (DER). |
| M3 | Weight-to-power ratio | 1.98 kg/CV | OEM | [1] | Computed on the dry weight |
| M4 | Kerb weight with fluids (US car) | 1,770 kg (3,902 lb) | TEST via Wikipedia | [9] (cites MotorTrend's first test) | Cross-check: the EPA puts this car in the 4,250 lb test-weight class (curb + 300 lb = 4,202 lb) [3] |
| M5 | EU-style kerb weight, no driver | ≈ 1,680 kg | DER | [9] [11] | The LP700-4 weighs 1,731 kg with fluids [9], and the SVJ is "50 kilo" lighter than a standard Aventador [11] |
| M6 | Weight FastestLaps uses for SVJ tests | 1,718 kg | DATA | [17] | Origin not stated |
| M7 | **Simulation mass (running order + driver)** | **1,845 kg** | DER/EST | M4 + 75 kg | Matches the state of the MotorTrend test car. Lighter option: 1,755 kg (M5 + 75). |

### 1.3 Centre of gravity and inertia (whole vehicle, about its CG)

| # | Parameter | Value | Range | Status | Note |
|---|---|---|---|---|---|
| I1 | CG distance behind the front axle | 1.539 m | — | DER | From M2: 0.57 × wheelbase |
| I2 | CG height | **0.44 m** | 0.41–0.47 | EST | Lumped-mass model, §2.3 |
| I3 | Yaw inertia Izz | **2,700 kg·m²** | 2,350–3,100 | EST | Dynamic index 0.83. Yaw radius of gyration = 0.45 × wheelbase. |
| I4 | Pitch inertia Iyy | **2,300 kg·m²** | 2,000–2,650 | EST | |
| I5 | Roll inertia Ixx | **620 kg·m²** | 540–660 | EST | |
| I6 | Engine rotating inertia (crank, flywheel, clutch) | **0.15 kg·m²** | 0.10–0.22 | EST | §2.4. The SVJ flywheel was lightened [11]. |
| I7 | Wheel + tyre + disc inertia, front / rear | 1.5 / 2.2 kg·m² | ± 25 % | EST | §2.6 |

### 1.4 Engine

| # | Parameter | Value | Status | Source | Note |
|---|---|---|---|---|---|
| E1 | Type | V12, 60°, multi-point injection, dry sump | OEM | [1] | The EPA lists the SVJ engine code as **L541** (L539 for the Aventador S) [3] |
| E2 | Displacement | 6,498 cm³ | OEM | [1] | |
| E3 | Bore × stroke | 95.0 × 76.4 mm | OEM | [1] | |
| E4 | Compression ratio | 11.8 ± 0.2 : 1 | OEM | [1] | |
| E5 | Maximum power | 566 kW (770 CV, 759 hp) at 8,500 rpm | OEM | [1] | The EPA rated it 760 hp [3] |
| E6 | Maximum torque | 720 Nm (531 lb-ft) at 6,750 rpm | OEM | [1] | Brake mean effective pressure 13.9 bar (DER) |
| E7 | Torque at maximum power | 636 Nm at 8,500 rpm | DER | E5 | |
| E8 | Measured power / torque (one test) | 773 PS at 8,170 rpm; 709 Nm at 6,680 rpm | DATA | [17] | "Tested power" on FastestLaps; the outlet is not named |
| E9 | Red line / fuel cut-off | **8,700 rpm** | PRESS | [10] [11] [12] | km77: fuel cut at 8,700. Auto Bild says 9,000 [13] (outlier). The Aventador S officially reaches 8,500 [2]. |
| E10 | Idle speed | ≈ 950 rpm warm (≈ 1,200 cold) | EST | — | Not published anywhere found. Calibrate from onboard footage. |
| E11 | Torque curve | table in §2.4 | EST | — | Fitted to E5 and E6 plus press descriptions. Not digitised. |
| E12 | Engine mass (L539) | 235 kg | OEM (LP700-4, as reported) | [26] | |
| E13 | SVJ engine changes | titanium intake valves, new intake runners and head ducts, lighter flywheel | PRESS | [4] [11] | |

### 1.5 Transmission and all-wheel drive

| # | Parameter | Value | Status | Source | Note |
|---|---|---|---|---|---|
| T1 | Gearbox | ISR 7-speed automated single-clutch (Graziano). Shift character depends on the drive mode. | OEM | [1] [9] | 70 kg [27] |
| T2 | Ratios, gears 1–7 | 3.909 / 2.438 / 1.810 / 1.458 / 1.185 / 0.967 / 0.844 | OEM-S, DATA | [2] [7] | Same as the S. The EPA N/V ratio is identical for the S and the SVJ [3]. |
| T3 | Reverse | 2.929 | OEM-S | [2] | |
| T4 | Published final drive (rear – front) | 2.867 – 3.273 | OEM-S, REG | [2] [3] | The EPA "axle ratio" is 2.87 |
| T5 | **Effective overall rear reduction after the gearbox** | **3.52** (3.45–3.61) | DER | [2] [3] | §2.5. Use this value. |
| T6 | Engine speed per road speed in 7th (N/V) | 36.6 rpm/mph (22.7 rpm per km/h) | REG | [3] | |
| T7 | Clutch | dry twin-plate, Ø 235 mm | OEM-S | [2] | |
| T8 | Shift time | "up to 50 ms" (fastest mode) | OEM-S | [2] | No per-mode times are published. Working values in §2.5 are EST. |
| T9 | All-wheel drive | Haldex generation IV coupling | OEM | [1] | |
| T10 | Torque split by mode (S) | Strada 40/60 F/R; Sport up to 10/90; Corsa up to 20/80 | OEM-S | [2] | |
| T11 | SVJ split | 3 % more torque can go to the rear than on the SV ("up to 93 %" rear) | PRESS | [4] [5] | |
| T12 | Rear differential | mechanical self-locking (limited-slip) | DATA | [8] | Locking ratio not published |
| T13 | Front differential | open, managed by ESC braking | PRESS | seen only in a search summary of LP700-4 material; source page not opened | Low confidence |

### 1.6 Tyres and wheels

| # | Parameter | Value | Status | Source | Note |
|---|---|---|---|---|---|
| W1 | Front tyre | Pirelli P Zero Corsa 255/30 ZR20 92Y | OEM | [1] | Load index 92 = 630 kg |
| W2 | Rear tyre | Pirelli P Zero Corsa 355/25 ZR21 107Y | OEM | [1] | Load index 107 = 975 kg |
| W3 | Optional tyre | Pirelli P Zero Trofeo R (fitted for the Nürburgring lap) | OEM/PRESS | [4] [19] | |
| W4 | Front rim | 9J × 20, ET 32.2 | OEM | [1] | |
| W5 | Rear rim | 13J × 21, ET 66.7 | OEM | [1] | |
| W6 | Front nominal diameter / free radius | 661.0 mm / 330.5 mm | DER | W1 | |
| W7 | Rear nominal diameter / free radius | 710.9 mm / 355.4 mm | DER, DATA | W2, [20] | A retailer lists 27.99 in = 711 mm |
| W8 | Rear revolutions per mile | 721 (circumference 2.232 m) | DATA | [21] | Retailer listing, likely computed rather than measured |
| W9 | Dynamic rolling radius, front / rear | ≈ 0.322 m / **0.346 m** | DER/EST | §2.5 | The rear value is consistent with the EPA N/V ratio |
| W10 | Tyre character | developed for the SVJ, "higher vertical stiffness" | PRESS | [4] | |

### 1.7 Brakes

| # | Parameter | Value | Status | Source |
|---|---|---|---|---|
| B1 | Front discs | carbon-ceramic, Ø 400 × 38 mm, 6-piston calipers | OEM | [1] |
| B2 | Rear discs | carbon-ceramic, Ø 380 × 38 mm, 4-piston calipers | OEM | [1] |
| B3 | System | dual hydraulic circuit, vacuum booster; ESC with integrated ABS and traction control | OEM | [1] |
| B4 | ABS unit | Bosch 8.0 (Aventador S) | OEM-S | [2] |
| B5 | Brake bias | not published. Working value 62 % front static; the ideal at 1.3 g is ≈ 64–65 % front | EST | §2.7 |

### 1.8 Suspension and steering

| # | Parameter | Value | Status | Source |
|---|---|---|---|---|
| S1 | Layout | aluminium double wishbones front and rear; pushrod-operated horizontal springs and dampers | OEM | [1] |
| S2 | Dampers | magnetorheological (Lamborghini's "LMS"), recalibrated for the SVJ | OEM/PRESS | [1] [4] |
| S3 | SVJ changes vs the SV | anti-roll bars 50 % stiffer; damping-force range +15 % | PRESS | [4] [5] |
| S4 | Spring rates, damping, roll stiffness | not published. Starting values in §2.8. | EST | — |
| S5 | Steering | hydraulic power assistance; Lamborghini Dynamic Steering (variable ratio) | OEM | [1] |
| S6 | Steering ratio | 10:1 – 18:1 (variable) | OEM-S, PRESS | [2] [10] |
| S7 | Turns lock to lock | 2.1 – 2.4 | OEM-S, PRESS | [2] [10] |
| S8 | Steering wheel diameter | 358 mm | OEM-S | [2] |
| S9 | Turning circle | 11.5 m (average; it varies with the rear steer) | OEM-S, DATA | [2] [7] |
| S10 | Rear-wheel steering | two electromechanical actuators, reaction in 5 ms | OEM-S | [2] |
| S11 | Rear steer angle | up to 3.0° opposite to the fronts (low speed); up to 1.5° same direction (high speed) | PRESS (Aventador S) | [15] |
| S12 | Phase switch speed | ≈ 78–84 mph (125–135 km/h), depending on measured yaw | PRESS (Aventador S) | [15] |

### 1.9 Aerodynamics

| # | Parameter | Value | Status | Source |
|---|---|---|---|---|
| A1 | System | ALA 2.0: electrically actuated flaps in the front splitter and in the engine cover. The **wing itself is fixed.** | OEM/PRESS | [1] [4] |
| A2 | Actuation time | < 500 ms | OEM | [6] [4] |
| A3 | Downforce vs the SV | +40 % on both axles. 70 % of the gain comes from the upper body, 30 % from the underbody. | OEM via press | [4] [5] [6] |
| A4 | Drag vs the SV | Cd −1 % | OEM via press | [4] [5] |
| A5 | Aero-vectoring | left and right wing channels; extra downforce on the inside rear wheel; active above 71 km/h | PRESS | [4] [14] |
| A6 | Cd × frontal area (CdA) from EPA coast-down | ≤ 0.68–0.74 m² | DER | [3], §2.10 |
| A7 | Cd / frontal area | 0.35 / 1.96 m² (CdA 0.686) | DATA | [16] |
| A8 | Downforce, absolute | ≈ 350 kg at 300 km/h (lift coefficient × area ≈ 0.82 m²) | PRESS, unverified | [22] |

### 1.10 Performance

| # | Item | Value | Status | Source | Conditions / note |
|---|---|---|---|---|---|
| P1 | 0–100 km/h | 2.8 s | OEM | [1] | Roadster: 2.9 s [6] |
| P2 | 0–200 km/h | 8.6 s | OEM via press | [4] [5] | |
| P3 | 0–300 km/h | 24.0 s | PRESS | [10] | |
| P4 | 0–60 mph | 2.5 s | TEST via [18] [17] | MotorTrend | US test car, 1,770 kg [9] |
| P5 | Quarter mile | 10.3 s at 136.4 mph (219.5 km/h) | TEST via [17] [18] | MotorTrend | |
| P6 | 0–100 mph | 5.6 s | TEST via [17] | MotorTrend | |
| P7 | 100–0 km/h | 30 m | OEM | [1] | Roadster: 31 m [6]. Mean deceleration 1.31 g (DER). |
| P8 | 60–0 mph | ≈ 28.0 m (91.8 ft) | DER | from P7 | No measured figure was accessible |
| P9 | Top speed | > 350 km/h (217 mph) | OEM | [1] | Reached in 7th at ≈ 7,970 rpm (DER, §2.5) |
| P10 | Skidpad lateral g | no verified figure; working value 1.10 g | EST | — | FastestLaps lists 1.10 g with no visible source [17] |
| P11 | MotorTrend figure-eight | 22.5 s | TEST via [17] | MotorTrend | |
| P12 | Nürburgring Nordschleife | 6:44.97 (20.6 km) | OEM via [19] | [19] [9] | Marco Mapelli, July 2018, optional Trofeo R tyres, timed by Remak with VBOX |
| P13 | Hockenheim GP circuit | 1:47.3, peak 276 km/h | TEST via [17] | sport auto (Germany) | Trofeo R tyres, air 11 °C |
| P14 | Autocar dry handling track | 1:05.2 | TEST via [17] | Autocar | air 13 °C |

---

## 2. Notes by section

### 2.1 Dimensions

All exterior dimensions come from Lamborghini's own SVJ page [1]. The full specification list sits in the page's embedded data even though the visible page shows only four numbers. Lamborghini lists no track or ground clearance for the SVJ. The Aventador S press kit gives 1,720 / 1,680 mm tracks and 115 ± 2 mm ground clearance, with the front able to lift to 155 mm [2]. km77 states that the SVJ keeps the same track widths as the S and SV, and that the extra body width (about 6 cm) is bodywork [10]. Lambocars and FichaCompleta both list 1,720 / 1,680 for the SVJ [7] [16].

**Overhangs are not published.** The total, 2.243 m, follows from length minus wheelbase. The split was read off a side frame of Lamborghini's 360° exterior viewer [1]: wheel centres and bumper ends were measured, then rescaled to the 2.243 m total. The image has perspective, so treat ±0.1 m as the real accuracy. It matters only for the collision box and approach angles.

### 2.2 Mass and the simulation mass

- **Dry weight, 1,525 kg** [1]. It excludes fluids [10] and is quoted on the lightest specification. It is the basis of the official weight-to-power ratio (1.98 kg/CV).
- **Kerb weight measured with fluids, 1,770 kg** (US car). Wikipedia cites MotorTrend's first test for it [9]. The MotorTrend page could not be opened here, so this is second-hand. Independent check: the EPA test-car list puts SVJ test configurations in the 4,250 lb and 4,500 lb equivalent test-weight classes [3]. EPA test weight = curb + 300 lb. 1,770 kg (3,902 lb) + 300 lb = 4,202 lb, which falls in the 4,250 lb class (4,126–4,375 lb). The figure is consistent.
- **CAR Magazine** (paywalled; text seen in search results only) told readers to add about 100 kg to the dry figure to get the kerb weight [33]. That would give about 1,625 kg, a lower bound.
- **Derived EU-style kerb weight ≈ 1,680 kg.** The LP700-4 weighed 1,731 kg with fluids (EU) [9], and TopGear NL says the SVJ is about 50 kg lighter than a standard Aventador [11].

**Simulation mass: 1,845 kg** = 1,770 kg measured kerb + 75 kg driver (the EU convention). This is the state in which MotorTrend recorded 0–60 mph in 2.5 s (car, driver and instruments), so the calibration targets in §2.15 stay consistent. For a light car (EU kerb, half tank), use about 1,755 kg. Do not use 1,525 kg: it leaves out fuel, oil, coolant, battery and options.

**Weight distribution** stays at 43 / 57 with a driver. The driver sits ahead of the CG, at about 1.2 m behind the front axle, so the front share moves only to about 43.4 %.

### 2.3 Centre of gravity height and moments of inertia (estimates)

**Neither value is published, and no measured CG height for a comparable supercar was found online.** The NHTSA inertia database (SAE 1999-01-1336) and the SAE 950356 estimation method exist but are paywalled [25].

**Method.** A lumped-mass model with 18 components. Sourced masses are used where they exist: engine 235 kg [26], ISR gearbox 70 kg [27], carbon monocoque with aluminium frames 229.5 kg [26], fuel 85 L × 0.745 kg/L, driver 75 kg. Each component gets a box self-inertia, ×1.5 for thin shells (body, tub), and the totals use the parallel-axis theorem about the vehicle CG [24].

Axes: x is measured rearward from the front axle, z up from the ground.

| Component | Mass (kg) | x (m) | z (m) | Box l × w × h (m) | Basis |
|---|---|---|---|---|---|
| Engine with ancillaries and oil | 300 | 2.05 | 0.43 | 0.90 × 0.80 × 0.60 | 235 kg bare engine [26] + estimate |
| ISR gearbox with oil (central tunnel) | 73 | 1.25 | 0.33 | 0.6 × 0.3 × 0.3 | 70 kg [27] |
| Monocoque with aluminium frames (shell) | 229.5 | 1.35 | 0.42 | 3.6 × 1.8 × 0.9 | [26] |
| Body, glass, bumpers, wing (shell) | 190 | 1.35 | 0.62 | 4.9 × 2.0 × 1.0 | EST |
| Interior, HVAC, electrics, battery | 200 | 1.05 | 0.50 | 1.8 × 1.6 × 0.8 | EST |
| Side radiators with coolant | 70 | 2.15 | 0.45 | 0.6 × 1.9 × 0.5 | EST |
| Exhaust (high, rear) | 40 | 2.95 | 0.60 | 0.5 × 0.9 × 0.4 | EST |
| Unsprung, front (each of 2) | 48 | 0.00 | 0.33 | wheel-sized | EST |
| Unsprung, rear (each of 2) | 55 | 2.70 | 0.355 | wheel-sized | EST |
| Front differential, Haldex, shafts | 40 | 0.10 | 0.30 | 0.4 × 1.4 × 0.25 | EST |
| Rear differential and shafts | 50 | 2.60 | 0.33 | 0.4 × 1.4 × 0.25 | EST |
| Front suspension (sprung parts) and steering | 55 | 0.00 | 0.45 | 0.5 × 1.5 × 0.4 | EST |
| Rear suspension (sprung parts) and rear-steer actuators | 60 | 2.70 | 0.45 | 0.5 × 1.5 × 0.4 | EST |
| Fuel, 85 L full | 63 | 0.60 | 0.35 | 0.5 × 1.0 × 0.3 | tank [2] |
| Driver (left-hand drive, y = +0.35 m) | 75 | 1.20 | 0.48 | 0.6 × 0.45 × 0.7 | EST |
| Unallocated (options, lift system, ALA, wiring) | 193.5 | 1.90 (solved) | 0.45 | 2.5 × 1.6 × 0.6 | x solved so that the distribution is 43/57 |

The fuel tank position (ahead of the cockpit) is an assumption, not verified.

| Result | Value | Sensitivity tested |
|---|---|---|
| CG height | **0.444 m** | all heights −30 mm → 0.414 m; heavy items +40 mm → 0.468 m |
| Izz (yaw) | **2,720 kg·m²** | shells as solid boxes → 2,344; more mass spread out → 3,104 |
| Iyy (pitch) | **2,307 kg·m²** | 1,978 – 2,662 |
| Ixx (roll) | **616 kg·m²** | 538 – 663 |
| Yaw radius of gyration | 1.21 m = 0.45 × wheelbase | A forum rule of thumb from measured data says about 45 % of wheelbase [37] (weak source; agrees) |
| Dynamic index Izz/(m·a·b) | 0.83 | Below 1, as expected for a mid-engine car |
| Uniform-box upper bound | Izz 4,433, Iyy 3,955, Ixx 875 | The real car concentrates mass between the axles, so it sits well below these |

These are **whole-vehicle values** (wheels included). If the engine models wheels as separate bodies, subtract each wheel's own inertia and its mass × distance² before applying the values to the chassis.

### 2.4 Engine

**Sourced:** 566 kW (770 CV) at 8,500 rpm and 720 Nm at 6,750 rpm [1]; bore and stroke, compression ratio, dry sump [1]. The SVJ changes are titanium intake valves, new intake runners and head ducts [4], and a lighter flywheel "to improve throttle response" (paraphrase of [11]).

**Rev limit.** km77 says fuel is cut at 8,700 rpm [10]. TopGear NL [11] and Canadian Auto Review [12] give an 8,700 rpm red line. Auto Bild says 9,000 [13]; take that as the end of the tachometer scale, not the cut. **Use 8,700 rpm.** For comparison, the Aventador S officially reaches 8,500 rpm [2].

**Torque curve: an estimate, not a digitised chart.** Searches for a Lamborghini chart or a published SVJ dyno plot found nothing that could be traced; a CarWow dyno figure (809 hp at the crank) showed up only in an uncited search summary. The curve below is constrained by:
- the official 720 Nm at 6,750 rpm and 636 Nm at 8,500 rpm, the latter derived from 566 kW, with the power peak placed at 8,500 rpm;
- Autocar's description (paywalled, seen through search) that the SVJ makes more torque than the SV at and below 5,500 rpm, with a flatter curve after the peak [34]; the SV makes 690 Nm at 5,500 rpm;
- the unattributed measured peaks on FastestLaps: 709 Nm at 6,680 rpm and 773 PS at 8,170 rpm [17].

Below 4,000 rpm the shape is typical of a naturally aspirated engine with no source: **low confidence**.

| rpm | Torque (Nm) | Power (kW) | Power (CV) | Confidence |
|---|---|---|---|---|
| 1,000 | 400 | 41.9 | 57 | low |
| 1,500 | 450 | 70.7 | 96 | low |
| 2,000 | 500 | 104.7 | 142 | low |
| 2,500 | 545 | 142.7 | 194 | low |
| 3,000 | 580 | 182.2 | 248 | low |
| 3,500 | 610 | 223.6 | 304 | low |
| 4,000 | 635 | 266.0 | 362 | low–medium |
| 4,500 | 655 | 308.7 | 420 | medium |
| 5,000 | 675 | 353.4 | 481 | medium |
| 5,500 | 693 | 399.1 | 543 | medium (≥ SV's 690) |
| 6,000 | 708 | 444.8 | 605 | medium |
| 6,500 | 717 | 488.0 | 664 | medium–high |
| **6,750** | **720** | 508.9 | 692 | **sourced** |
| 7,000 | 719 | 527.1 | 717 | medium–high |
| 7,500 | 700 | 549.8 | 747 | medium |
| 8,000 | 665 | 557.1 | 757 | medium |
| 8,250 | 652 | 563.3 | 766 | medium |
| **8,500** | **636** | **566.1** | **770** | **sourced (derived from power)** |
| 8,700 | 612 | 557.6 | 758 | medium (fuel cut) |

With linear interpolation, the maximum power of this table falls exactly at 8,500 rpm (checked).

**Closed-throttle engine braking (estimate).** 1 bar of mean effective pressure on this engine equals 51.7 Nm. Assume 2 bar of friction and pumping loss near idle, rising to about 4 bar at 8,500 rpm. That is a drag of about 100 Nm at low rpm rising to about 210 Nm. Calibrate from coast-down in gear.

**Engine inertia ≈ 0.15 kg·m² (range 0.10–0.22).** Method: Ubysz (2010) measured and computed engine inertias of 0.125–0.25 kg·m² for production engines with 11–18 kg flywheels. He found that the flywheel and clutch carry 80–85 % of the total [23]. The SVJ has a lightened flywheel [11] and a 235 mm dry twin-plate clutch [2], estimated at 0.10–0.12 kg·m² for that pack. Add about 0.03–0.05 for the twelve-cylinder crank train, rods and accessories. **Calibrate** from the free-rev rate in neutral (blip footage) or from the rev-matched downshift times in the captures (`05_video_observations.md`).

### 2.5 Transmission and all-wheel drive

**Ratios.** The gear ratios are in the official Aventador S kit [2] and repeated for the SVJ by Lambocars [7]. The EPA lists the same axle ratio (2.87) and the same N/V (36.6) for the 2020 Aventador S and the SVJ [3], so the gearing is the same.

**Why the effective final drive is 3.52 and not 2.867.** Three independent checks:
1. **EPA N/V.** The EPA lists 36.6 engine rpm per mph in 7th [3]. Overall ratio = N/V × r ÷ 4.269. With r = 0.340–0.355 m, the overall 7th-gear ratio is 2.92–3.05, so the reduction after the gearbox is **3.45–3.61**. With 2.867, N/V would be 29.9, not 36.6.
2. **Front axle ratio and tyre sizes.** The front differential is listed at 3.273 [2]. For the front and rear wheels to turn at the same road speed from one gearbox output, the rear reduction must be 3.273 × (710.9 / 661.0) = **3.520**. That is 2.867 × 1.228, which suggests an extra reduction of about 1.23 in the rear path (perhaps transfer gears). That location is a **hypothesis, not verified**; the overall number is what matters.
3. **Lambocars' maximum speed per gear** (76 / 121 / 163 / 203 / 249 / 286 / 350 km/h [7]) fits gearing of about 3.6 at about 8,000 rpm, apart from 6th. It does not fit 2.867.

With r = 0.346 m and a reduction of 3.52, the rear dynamic radius comes out at 97.4 % of the free radius, which is normal for a low-profile tyre at its load.

| Gear | Ratio | Overall ratio (×3.52) | km/h per 1,000 rpm | km/h at 8,500 | km/h at 8,700 (cut) |
|---|---|---|---|---|---|
| 1 | 3.909 | 13.76 | 9.48 | 80.6 | 82.5 |
| 2 | 2.438 | 8.58 | 15.20 | 129.2 | 132.2 |
| 3 | 1.810 | 6.37 | 20.47 | 174.0 | 178.1 |
| 4 | 1.458 | 5.13 | 25.42 | 216.0 | 221.1 |
| 5 | 1.185 | 4.17 | 31.27 | 265.8 | 272.1 |
| 6 | 0.967 | 3.40 | 38.32 | 325.7 | 333.4 |
| 7 | 0.844 | 2.97 | 43.91 | 373.2 (drag-limited) | — |
| R | 2.929 | 10.31 | 12.65 | — | — |

Consequences: 0–100 km/h needs one upshift; 350 km/h in 7th comes at about **7,970 rpm**; 100 km/h in 7th is about 2,280 rpm. **Calibrate** with onboard footage (rpm against speed) and check the 1→2 shift point near 82 km/h.

**Shift times.** The only official figure is "up to 50 milliseconds" [2], the best case (Corsa). For the SVJ the shift logic was reprogrammed for faster shifts [11]. Reviewers describe the Strada automatic as slow, lurching shifts [12]. **Working values (EST):** Strada ≈ 200–250 ms with a clear torque cut; Sport ≈ 100 ms; Corsa ≈ 50–60 ms with a sharp jolt on upshift. A single-clutch box cuts torque completely during the shift; reviewers stress the push in the back on upshifts. Calibrate the cut duration from audio and video of the shifts.

**AWD.** Haldex generation IV [1], an electronically controlled multi-plate coupling to the front axle. The Aventador S kit gives the split per mode [2]:
- Strada 60/40 rear/front as standard;
- Sport up to 90 % rear, with less torque sent forward on lift-off to allow oversteer;
- Corsa a maximum 80/20 rear/front for neutral handling.

For the SVJ, 3 % more torque can go rearward than on the SV [4]; CompleteCar reports up to 93 % rear [5]. Rear differential: mechanical self-locking [8], locking ratio not published (start at about 25 % drive / 45 % coast and calibrate on corner-exit traction). Front differential: open, with brake-based control (low confidence).

### 2.6 Tyres and wheels

The sizes, load and speed indices and the rims are official [1]. The diameters are computed: front 661.0 mm, rear 710.9 mm. A retailer lists the rear at 27.99 in (711 mm) [20] and 721 revolutions per mile [21]. The P Zero Corsa was developed for the SVJ with higher vertical stiffness; the P Zero Trofeo R is optional [4]. The Nürburgring lap ran on Trofeo R [19]. **No tyre force data (Pacejka coefficients, cornering stiffness) is published** for this tyre.

**Wheel inertia (EST):**
- tyre as a ring between bead and tread: front 11 kg, rear 15 kg;
- forged rim: 11 kg front, 13.5 kg rear, radius of gyration about 0.19–0.20 m;
- carbon-ceramic disc with its bell: about 6 kg front, 5.5 kg rear.

Result: about 1.5 kg·m² front and 2.2 kg·m² rear per corner. The component masses are not sourced (±25 %).

### 2.7 Brakes

The disc sizes and piston counts are official [1]. The 100–0 km/h distance of 30 m means a mean deceleration of 12.86 m/s² (1.31 g). The roadster claim of 31 m is 1.27 g [6]. **Bias is not published.** With CG 0.444 m, wheelbase 2.70 m and 43 % static front weight, the ideal front share at 1.31 g is 0.43 + (0.444 / 2.70) × 1.31 ≈ **0.65**. A hydraulic bias of about 62 % front, with ABS and electronic brake distribution trimming, is a reasonable start; rear aero load lowers the ideal front share at speed. Owners and drivers reported the car wriggling under hard braking [32]; this is anecdotal.

### 2.8 Suspension (no published rates)

Sourced:
- pushrod double wishbones with horizontal springs and magnetorheological dampers [1];
- anti-roll bars 50 % stiffer than the SV and a damping-force range 15 % wider [4] [5];
- revised kinematics and new rear springs came with the four-wheel steering on the S [2].

**Starting values (EST)** for the 1,845 kg simulation mass: sprung corner mass about 349 kg front and 471 kg rear (after 48 / 55 kg unsprung).

| Ride frequency F / R | Wheel rate front | Wheel rate rear |
|---|---|---|
| 1.7 / 1.9 Hz (Strada) | 39.8 kN/m | 67.1 kN/m |
| 1.9 / 2.1 Hz (Corsa) | 49.7 kN/m | 82.0 kN/m |

Critical damping at 1.8 / 2.0 Hz is about 7.9 / 11.8 kN·s/m per corner. Use about 0.3 of critical in Strada and about 0.6–0.7 in Corsa; that gives the magnetorheological range and the "high damping force" Corsa described in [2]. Roll stiffness: take a front roll-stiffness share slightly above the 43 % front weight share (about 48–52 %) to start with mild understeer. Calibrate to a roll gradient of about 0.8–1.0°/g. All of these are tuning targets, not data.

### 2.9 Steering and rear-wheel steering

**Steering.** Hydraulic assistance [1] with three power-assistance curves chosen by drive mode [2]. Lamborghini Dynamic Steering gives a speed-dependent ratio [1] between 10:1 and 18:1, 2.1 to 2.4 turns lock to lock [2] [10], and a 358 mm wheel [2]. That the ratio is quickest at low speed is the usual design intent, an **assumption**. For the SVJ the assistance was rebalanced and the dynamic steering recalibrated [4]; Lambocars says the steering is significantly stiffer than the SV's [19]. Turning circle: 11.5 m, an average that varies with the rear steer [2].

**Rear-wheel steering.** Two actuators reacting in 5 ms [2]. At low speed the rears steer opposite to the fronts, which virtually shortens the wheelbase; at higher speed they steer with the fronts, which virtually lengthens it [2]. Evo gives, for the Aventador S: up to 3.0° opposite and up to 1.5° in phase, switching between about 78 and 84 mph depending on yaw [15]. The SVJ system was re-engineered to work with the higher aero load [4] [5]; **SVJ-specific angles and thresholds are not published**, so use the S values. A virtual wheelbase change of about −500 / +700 mm appears only in a forum quote and could not be verified. Not used.

### 2.10 Aerodynamics

**What actually moves (ALA 2.0).** Electric motors open or close flaps in the **front splitter** and on the **engine cover** [4] [1]. Lamborghini's technical list calls the rear spoiler fixed, with the ALA system built in [1]. **The wing does not change angle.**
- **ALA off** (high downforce): all flaps closed, and the wing works as a conventional fixed wing [4] [6].
- **ALA on** (low drag): the front flaps open and route air through an inner channel and the underbody vortex generators. The rear flaps let air up the wing's central pylon and out of slots under the wing, which stalls it and cuts drag [4] [14].
- **Aero-vectoring:** the wing channel is split left and right. In a right turn the right deck flap closes and the left one opens, adding downforce on the inside rear wheel. It works above 71 km/h [14]. Inside-wheel loading is said to be 30 % better than the first ALA system [4] [11].
- Flaps move in under 500 ms [6] [4].

**Relative figures (official, via press):** downforce +40 % on both axles compared with the SV; 70 % of the gain from the upper body and 30 % from the underbody [4]. Drag coefficient −1 % compared with the SV [4] [5]. IEEE Spectrum says +30 % instead [14]; the +40 % comes from Lamborghini's own releases.

**Drag from regulatory coast-down data (DER).** The EPA road-load coefficients for the SVJ test car [3]:

| Configuration | Constant force | Linear term | Quadratic term | CdA upper bound (ρ = 1.167–1.204) |
|---|---|---|---|---|
| 4,500 lb test weight | 255.0 N | 7.57 N per m/s | 0.4301 N/(m/s)² | 0.714–0.737 m² |
| 4,250 lb test weight | 237.0 N | 8.14 N per m/s | 0.4107 N/(m/s)² | 0.682–0.704 m² |

The quadratic term also absorbs some speed-squared tyre and driveline losses, so these are **upper bounds** on the aero CdA. The ALA state during the coast-down is unknown. The 4,500 lb coefficients are identical to the 2020 Aventador S entry [3], so they may be carried over. Power check: the 4,500 lb road load needs 492 kW at 350 km/h, below 566 kW at the crank after drivetrain losses. The claimed top speed is therefore consistent. FichaCompleta's Cd 0.35 × 1.96 m² = 0.686 m² [16] falls in the same range.

**Downforce, absolute (low confidence).** Torque (Singapore) wrote about 350 kg at 300 km/h [22]; the page blocks this tool, so the figure is seen only through search. That is a lift coefficient × area of about 0.82 m². FastestLaps' own estimates (156 kg at 200, 352 kg at 300 km/h [17]) give the same coefficient and are probably derived from the same claim. **The front/rear split is not published.** "+40 % on both axles" suggests the balance stayed near the SV's. Start at 40/60 front/rear with ALA off. With ALA on, cut rear downforce and drag (try −30 % rear downforce and −5–8 % CdA), then calibrate.

### 2.11 Performance (official vs instrumented)

| Item | Official | Instrumented | Conditions |
|---|---|---|---|
| 0–100 km/h | 2.8 s [1] | — | |
| 0–60 mph | — | 2.5 s, MotorTrend via [18] [17] | US test car, 1,770 kg with fluids [9] |
| Quarter mile | — | 10.3 s at 136.4 mph, MotorTrend via [17] [18] | |
| 0–100 mph | — | 5.6 s, MotorTrend via [17] | |
| 0–200 km/h | 8.6 s [4] | best 8.2 s in FastestLaps' aggregate, outlet not named [17] | |
| 100–0 km/h | 30 m [1] | — | 60–0 mph ≈ 28.0 m derived |
| Top speed | > 350 km/h [1] | — | 351 km/h on TopGear NL [11] |
| Nordschleife | 6:44.97 [19] | — | Factory driver, July 2018, Trofeo R, Remak/VBOX timing [19] |
| Hockenheim GP | — | 1:47.3, sport auto via [17] | Trofeo R, 11 °C air, 1,035 mbar |
| Autocar handling track | — | 1:05.2 via [17] | 13 °C |
| MotorTrend figure-eight | — | 22.5 s via [17] | |

Not obtained: Car and Driver's instrumented figures (site not accessible), measured 60–0 / 70–0 braking, and skidpad g. FastestLaps shows 60–0 and 100–0 tests only to logged-in users; not used.

### 2.12 Driving modes (ANIMA: Strada, Sport, Corsa, Ego)

From the Aventador S kit [2] (the SVJ keeps the same structure, retuned for the ALA [6] [4]). The modes act on traction (engine, gearbox, all-wheel drive), steering (rear steer, dynamic steering, power assistance) and suspension (dampers):

| Mode | Gearbox | Steering | Dampers | ESC / traction | AWD split | Exhaust |
|---|---|---|---|---|---|---|
| **Strada** | comfort shifts, automatic available | most assistance (inf.) | smoothed, progressive damping | full | 40/60 F/R | valve opens latest (inf.) |
| **Sport** | faster shifts, higher shift points [31] | sportier (inf.) | firmer (inf.) | allows oversteer and slides | up to 90 % rear (SVJ: about 93 %) | between the two (inf.) |
| **Corsa** | fastest shifts (about 50 ms), launch control [31] | more opposite-phase rear steer at the limit | highest damping force | least intrusive | up to 80/20 R/F, more neutral | valve opens earliest [12] |
| **Ego** | the driver picks traction, steering and suspension, each set to Strada, Sport or Corsa | | | | | |

"(inf.)" marks an ordering inferred from the mode logic; no source gives it. The exhaust valve opens at a mode-dependent rpm, and earlier in Corsa [12]. ESC can also be switched off.

### 2.13 Exhaust

**Layout.** A new, lightweight exhaust with less backpressure, mounted high and close to the engine [4]. The roadster release describes it as a high-mounted, lightweight, naked pipe [6]. CompleteCar describes it as "mounted high and centrally" [5]; South African CAR magazine (seen through search) as two large pipes exiting halfway up the rear panel. Wikipedia says titanium is used to save weight [9]. **Two large central outlets** (the S had three).

**Pops and flames on the production car: yes, documented by several reviewers of stock press cars.**
- Canadian Auto Review describes "the artillery salvo of pops and bangs on overrun" and says the car can "spit fire if you even ask it nicely" [12].
- Auto Bild describes a fireball-like effect on throttle blips [13].
- Top Gear UK (page blocked, text seen through search) reports "a lick of blue flame" and pops, crackles and bangs on up- and downshifts [35].

Large repeated flames in online videos are often from straight-pipe aftermarket exhausts [36]. **For the simulation:** overrun pops on lift-off and downshifts in Sport and Corsa, and an occasional short blue flame on hard downshifts. No continuous flame.

### 2.14 Instrument cluster and cockpit (UI reference)

**What is documented:**
- **A single TFT digital cluster** under a carbon hood, with a different screen layout ("Kombi" graphics) for STRADA, SPORT and CORSA, combined with EGO. Pressing EGO opens pop-up screens to pick the settings [2]. The display changes design as you scroll through the modes [15].
- **The SVJ adds live ALA status** on the TFT [6] [4].
- The Corsa screen centres on the rev counter, shift timing and the front/rear torque split. This comes from u-car.com.tw's review of the Aventador S, seen through search; the page blocks this tool [38].
- The cluster shows speed, rpm, gear, drive mode and navigation; the roadster variant can show lap times and g-forces [7] (dealer and fan-site level).
- Ergonomics: the large column-fixed paddles and the wheel spokes partly hide the display [12]. Optional telemetry records lap times [2].
- The drive-mode selector is a strip of four buttons on the centre tunnel (STRADA, SPORT, CORSA, with EGO below), next to the red flip-up start-button guard. Seen on the two official images linked below.

**Image references (links only; check the licence before reuse):**
- Lamborghini SVJ page, with the 3D interior viewer: https://www.lamborghini.com/en-en/history/aventador-svj
- Official drive-mode selector render: https://www.lamborghini.com/sites/it-en/files/DAM/lamborghini/facelift_2019/model_detail/aventador/svj/driving_dynamics/Aventador%20SVJ%20DrivingModes.jpg
- Official centre-console photo (mode buttons lit, start guard): https://www.lamborghini.com/sites/it-en/files/DAM/lamborghini/facelift_2019/model_detail/aventador/svj/2021/03_19/aventador_svj_s4.jpg
- Spy shot of the SVJ cluster showing the "SVJ" name (Instagram, via The Drive): https://www.instagram.com/p/BfTwwrIl8hN and https://www.thedrive.com/news/18596/lamborghinis-new-aventador-variant-to-be-called-the-svj
- Aventador S Roadster cockpit, CC BY-SA 4.0, Alexander Migl. Shows the cluster hood, column paddles and centre screen; the cluster itself is barely visible: https://commons.wikimedia.org/wiki/File:Lamborghini_Aventador_S_Roadster_Cockpit_IMG_0711.jpg
- Official pre-owned SVJ pages with dealer interior photos: https://preowned.lamborghini.com/models/aventador-svj
- u-car.com.tw Aventador S and SVJ articles with cluster photos per mode (blocked to this tool, not viewed): https://news.u-car.com.tw/news/article/34087 · https://news.u-car.com.tw/news/article/43209

No screenshot of each mode's layout was obtained. For exact layouts, take frames from onboard videos (see `07_visual_references.md`).

### 2.15 Gaps, the most uncertain estimates, and how to calibrate them

**Not published at all.** For each, the closest documented alternative:

| Field | Closest documented alternative |
|---|---|
| SVJ track, ground clearance, ratios, steering ratio, shift time | Aventador S official kit [2]; km77 confirms the SVJ shares several of these [10] |
| Torque curve | Two official anchors, an unattributed measured peak pair [17], and Autocar's description |
| Spring and damper rates, roll stiffness | Only relative SVJ changes vs the SV (+50 % anti-roll bars, +15 % damping range) |
| Absolute downforce and its split | One unverified press figure (350 kg at 300 km/h) |
| Rear-steer angles and switch speed for the SVJ | Aventador S values from evo [15] |
| Brake bias, differential locking, idle speed | None; estimated |

**Ranking of uncertainty (most uncertain first), with the calibration that fixes each:**

1. **Tyre grip and its fall-off with load** (no data). Calibrate peak friction against 0–60 mph 2.5 s and 0–100 km/h 2.8 s (launch traction with all-wheel drive), 100–0 km/h in 30 m (≈1.31 g mean, so a tyre peak of about 1.35–1.45 with ABS), and a steady-state skidpad of about 1.05–1.15 g.
2. **Aero downforce and its front/rear split** (§2.10). Calibrate with high-speed cornering balance in the captures and the Hockenheim peak of 276 km/h [17]. Keep drag fixed to the EPA-derived CdA and check that 350 km/h is reached in 7th near 7,970 rpm.
3. **CG height and inertias** (§2.3). Calibrate yaw inertia from the yaw-rate response time to a steering step (onboard and overhead footage), and CG height from roll and pitch angles under 1 g, with the suspension rates.
4. **Torque curve below 5,000 rpm.** Calibrate with in-gear rolling acceleration times: 80–120 km/h in 5th, 6th and 7th appears on FastestLaps as 4.0 / 4.9 / 6.1 s, outlet not named [17]. The quarter-mile trap speed of 136.4 mph checks the top end.
5. **Shift times per mode and engine inertia.** Calibrate from audio and video: the length of the rpm drop at upshift, and the free-rev rate.
6. **Suspension rates and damping.** Calibrate the ride frequency on the bench bumps and a roll gradient of about 0.8–1.0°/g.

Solid enough to hard-code now: dimensions, dry weight and distribution, the engine peak values, gear ratios with the effective final drive of 3.52, tyre sizes, brake hardware, and the 0–100, 0–200, 100–0 and top-speed claims.

---

## 3. Sources (all accessed 2026-10-27)

| # | Source | URL | Used for | Access note |
|---|---|---|---|---|
| [1] | Lamborghini, Aventador SVJ model page (technical specifications embedded in the page data; 360° viewer frames) | https://www.lamborghini.com/en-en/history/aventador-svj | dimensions, weight, distribution, engine, brakes, tyres, rims, gearbox, AWD, suspension, steering type, performance, ALA description | OEM |
| [2] | Lamborghini press release and technical data, Aventador S (Dec 2016), PDF from the Lamborghini media site's file host | https://cdn.uc.assets.prezly.com/18eee838-d268-4b92-b7c0-be97ac4884dc/-/inline/no/EN.pdf | tracks, ground clearance, ratios, final drives, clutch, steering ratio and turns, turning circle, ABS, rear-steer behaviour, mode splits, 50 ms, TFT modes, capacities | OEM (Aventador S) |
| [3] | US EPA, "Data on Cars used for Testing Fuel Economy": MY2019 file (also MY2020–2022) | https://www.epa.gov/compliance-and-fuel-economy-data/data-cars-used-testing-fuel-economy · https://www.epa.gov/sites/default/files/2020-10/19tstcar-2020-10-02.xlsx | N/V 36.6, axle 2.87, test-weight classes, road-load coefficients, engine code L541, 760 hp | REG (manufacturer-submitted) |
| [4] | Motor1, "Lamborghini Aventador SVJ Is A 770-HP Track Monster" (press-release text) | https://www.motor1.com/news/263420/lamborghini-aventador-svj-supercar/ | ALA 2.0 mechanism, < 500 ms, +40 %/−1 %, 70/30, aero-vectoring, engine changes, exhaust, anti-roll bars, damping, torque split, tyres, 0–200, 30 m | press release via press |
| [5] | CompleteCar.ie, "Lamborghini unveils demented Aventador SVJ" | https://www.completecar.ie/car-news/article/8461/Lamborghini-unveils-demented-Aventador-SVJ | +40 %/−1 %, anti-roll bars +50 %, damping +15 %, up to 93 % rear, exhaust high and central | press |
| [6] | Lamborghini press release, Aventador SVJ Roadster (Geneva 2019); original URL now redirects, mirror used | https://media.lamborghini.com/english/models/automobili-lamborghini-launches-the-aventador-svj-roadster--at-geneva-motor-show-2019--exclusive-ope/s/347a6f41-bcd0-44f5-89b5-ba72eb9ecd4f · mirror: https://lambocars.com/the-official-press-release-of-aventador-svj-roadster/ | ALA on/off logic, < 500 ms, TFT with live ALA status, exhaust description, roadster figures | OEM via mirror |
| [7] | Lambocars, "Lamborghini Aventador SVJ Specs & Performance" | https://lambocars.com/aventador-svj-specs-performance/ | tracks, ground clearance, ratios, speeds per gear, capacities, turning circle | DATA (fan site) |
| [8] | Lambocars, "Aventador SVJ Roadster – Specs & Performance" | https://www.lambocars.com/lamborghini-aventador-svj-roadster-specs-performance/ | rear mechanical self-locking differential | DATA |
| [9] | Wikipedia, "Lamborghini Aventador" | https://en.wikipedia.org/wiki/Lamborghini_Aventador | 1,770 kg with fluids (cites MotorTrend), LP700-4 1,731 kg, Graziano ISR, Nürburgring context, titanium exhaust | secondary |
| [10] | km77, Lamborghini Aventador Coupé SVJ, general information | https://www.km77.com/coches/lamborghini/aventador/2012/coupe/svj/informacion?amp=1 | fuel cut at 8,700 rpm, steering 10:1–18:1 and 2.1–2.4 turns, same track as S/SV, 0–300 in 24.0 s, dry = without fluids | PRESS |
| [11] | TopGear Nederland, "Lamborghini Aventador SVJ (2018)", 5 Jan 2019 | https://topgear.nl/wallpaper/lamborghini-aventador-svj-2 | lighter flywheel, red line 8,700, two front flaps, inside wheel +30 %, 50 kg lighter, 351 km/h | PRESS |
| [12] | Canadian Auto Review, "Review: 2019 Lamborghini Aventador LP770-4 SVJ" (C. Chan, 5 Feb 2020) | https://canadianautoreview.ca/review-2019-lamborghini-aventador-lp770-4-svj | exhaust valve per mode, pops on overrun, fire, 8,700 red line, cluster ergonomics, shift character | PRESS |
| [13] | Auto Bild, "Lamborghini Aventador SVJ: Test" (G. Kacher, 11 Oct 2018) | https://www.autobild.de/artikel/lamborghini-aventador-svj-test-14154871.html | 9,000 limit claim (outlier), fireball on throttle blips | PRESS |
| [14] | IEEE Spectrum, "2019's Top 10 Tech Cars: Lamborghini Aventador SVJ" | https://spectrum.ieee.org/2019s-top-10-tech-cars-lamborghini-aventador-svj | ALA flow path (pylon, slots under the wing), aero-vectoring above 71 km/h | PRESS |
| [15] | evo, "Lamborghini Aventador S review" (S. Sutcliffe) | https://evo.co.uk/lamborghini/aventador-s | rear steer 3.0° / 1.5°, switch at 78–84 mph, cluster changes per mode | PRESS (Aventador S) |
| [16] | FichaCompleta, Aventador LP700-4 vs SVJ comparison | https://www.fichacompleta.com.br/en/carros/comparativo/aventador-lp-700-4-6-5-v12-2017-vs-aventador-svj-770-4-6-5-v12-2021 | Cd 0.35, frontal area 1.96 m², tracks | DATA |
| [17] | FastestLaps, SVJ model page and public test pages (quarter mile, figure-eight, Hockenheim, Autocar track, 0–100 mph, 0–200 km/h) | https://fastestlaps.com/models/lamborghini-aventador-svj · https://fastestlaps.com/tests/zfu184l9ocd2 · https://fastestlaps.com/tests/9sjp3jt8bb3d · https://fastestlaps.com/tests/7fsngh20d3up · https://fastestlaps.com/tests/bz2agg20rouo · https://fastestlaps.com/tests/mflhgfl1cbra · https://fastestlaps.com/tests/l0nlu8nuza4v | MotorTrend and sport auto figures second-hand, measured power/torque peaks, in-gear times, downforce estimates | DATA. Pages needing a login were not used. |
| [18] | 0-60specs, 2019 Lamborghini Aventador SVJ | https://www.0-60specs.com/2019-lamborghini-aventador-svj | MotorTrend 0–60 2.5 s, quarter 10.3 s at 136.4 mph | DATA |
| [19] | Lambocars, "Aventador SVJ sets new record on the Ring" (26–27 July 2018 release text) | https://lambocars.com/aventador-svj-sets-new-record-on-the-ring/ | 6:44.97, 20.6 km, Mapelli, Trofeo R, Remak/VBOX, steering stiffer than the SV | OEM via mirror |
| [20] | Kal Tire, Pirelli P Zero Corsa 355/25R21 listing | https://www.kaltire.com/en/tires/pzero-corsa-pzc4/297892.html | overall diameter 27.99 in | DATA (retailer) |
| [21] | ThreePiece.us, Pirelli P Zero Corsa 355/25ZR21 listing | https://www.threepiece.us/pirelli-p-zero-corsa-pzc4-355-25zr21xl-107-y-2813600/ | 721 revolutions per mile | DATA (retailer) |
| [22] | Torque (Singapore), SVJ article | https://www.torque.com.sg/?p=58683 | 350 kg at 300 km/h | blocked to this tool; seen only through search. Unverified. |
| [23] | A. Ubysz, "Problems of rotational mass in passenger vehicles", Transport Problems 5(1), 2010 | https://delibra.bg.polsl.pl//Content/27480/BCPS_31096_-_Problems-of-rotation_0000.pdf | measured engine inertia 0.125–0.25 kg·m²; flywheel and clutch = 80–85 % | open-access paper |
| [24] | Wikipedia, "Parallel axis theorem" and "List of moments of inertia" | https://en.wikipedia.org/wiki/Parallel_axis_theorem · https://en.wikipedia.org/wiki/List_of_moments_of_inertia | method for the lumped-mass inertia | method reference |
| [25] | SAE 950356 (Bixel et al., CG and inertia estimation); SAE 1999-01-1336 (Heydinger et al., NHTSA measured inertias) | https://saemobilus.sae.org/content/950356 · https://saemobilus.sae.org/content/1999-01-1336 | named for later refinement; not read (paywalled) | abstract pages only |
| [26] | Supercars.net, "2012 Lamborghini Aventador LP 700-4" | https://www.supercars.net/blog/2012-lamborghini-aventador-lp-700-4 | engine 235 kg, monocoque with frames 229.5 kg | press-kit text via press |
| [27] | Autocar India, "Lamborghini Aventador revealed" | https://www.autocarindia.com/car-news-amp/lamborghini-aventador-revealed-270342 | ISR 70 kg, tub 147.5 kg, pushrod layout | PRESS |
| [28] | GTspirit, "Lamborghini Aventador SVJ officially revealed" (24 Aug 2018) | https://gtspirit.com/2018/08/24/lamborghini-aventador-svj-officially-revealed/ | dry 1,525 kg, 0–200 8.6 s, modes, titanium valve | PRESS |
| [29] | The Drive, "Lamborghini's new Aventador variant to be called the SVJ" (19 Feb 2018) | https://www.thedrive.com/news/18596/lamborghinis-new-aventador-variant-to-be-called-the-svj | cluster spy shot reference | PRESS |
| [30] | Wikimedia Commons, Aventador S Roadster cockpit (CC BY-SA 4.0) | https://commons.wikimedia.org/wiki/File:Lamborghini_Aventador_S_Roadster_Cockpit_IMG_0711.jpg | cockpit layout reference | image |
| [31] | The Globe and Mail, Aventador review ("The fastest way to spend $485,000") | https://www.theglobeandmail.com/amp/globe-drive/reviews/new-cars/the-fastest-way-to-spend-485000/article9712892/ | Sport: higher shift points and shorter shifts; Corsa includes launch control; 50 ms | PRESS (LP700-4); seen through search |
| [32] | The Brake Report, "Aventador SVJ Braking System Questioned" | https://thebrakereport.com/aventador-svj-braking-system-questioned/ | anecdotal braking-stability complaints | PRESS |
| [33] | CAR Magazine, "Lamborghini Aventador SVJ review" | https://carmagazine.co.uk/car-reviews/lamborghini/aventador-svj | "add ~100 kg" for kerb | paywalled; seen through search |
| [34] | Autocar, Aventador SVJ review | https://autocar.co.uk/node/87820 | torque above the SV's up to 5,500 rpm, flatter after the peak | paywalled; seen through search |
| [35] | Top Gear UK, LP 770-4 first drive | https://www.topgear.com/car-reviews/lamborghini/lp-770-4-superveloce-jota-2dr-isr/first-drive | blue flame, pops, crackles and bangs | blocked to this tool; seen through search |
| [36] | Motor1, SVJ with an aftermarket "F1" exhaust on the Autobahn; duPont Registry on straight-pipe SVJs | https://www.motor1.com/news/700007/lamborghini-aventador-svj-with-f1-exhaust-on-autobahn-video/ · https://news.dupontregistry.com/blogs/lamborghini-news/watch-this-lamborghini-aventador-svj-scream-down-the-autobahn-at-193mph | big flames in videos are often aftermarket | PRESS |
| [37] | Eng-Tips forum, "Dynamic index / Yaw axis" | https://www.eng-tips.com/threads/dynamic-index-yaw-axis.459040 | yaw radius of gyration ≈ 45 % of wheelbase (rule of thumb) | forum, weak |
| [38] | u-car.com.tw, Aventador S and SVJ reviews | https://news.u-car.com.tw/news/article/34087 · https://news.u-car.com.tw/news/article/43209 | Corsa screen content | blocked to this tool; seen through search |

The derived numbers (lumped-mass inertia, gearing, road load, torque table) were computed with short Python scripts in this session's temporary scratchpad, which will not persist. Every input and output is written in §2, so each number can be recomputed from this file.
