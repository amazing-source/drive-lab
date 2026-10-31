# 13 · Drifting on Space: research, Drive Lab today, and a balancing plan

Systems agent, 2026-10-31, issue #124. **Plan only: nothing is implemented until the owner's go.**
Web research by a researcher agent (web search and fetch only), then offline measurements on
`tools/DriveSim` by me. No Studio, no Play, no uploads.

Evidence tags, as in note 01: **(a)** a developer or manufacturer statement (including a kit's own
published source code); **(b)** a credible community, modding or press source; **(c)** my
inference, with the reasoning given; **[excerpt]** seen only in a search-result summary. Every
Drive Lab number is a measurement from `tools/drift_baseline.luau` or `tools/drift_candidate.luau`
(outputs in `docs/evidence/drift-plan/`), or a cited line of code.

## The request, restated

The owner wants to drift by holding Space, with a tyre sound and whatever else a convincing drift
needs. Their direction (2026-10-31):

- **Game-style, not a sim.** Realism is welcome, but the game must stay playable on a keyboard and a
  gamepad.
- **One shared mechanism for every car**, the SVJ included: hold Space to drift through corners.
- **It must work with traction control on.** The plan decides how the drift treats TC and the other
  assists.
- **The effort goes into balancing:** the entry, the rear grip cut and how it scales, the angle hold,
  the speed cost, the exit without a snap, keyboard and pad control, and which numbers are per car.

## 0. Summary and recommendation

**Recommendation: option B, an assisted drift.** One shared rule, `Rules/Drift`, with a small
per-car profile. Holding Space above 30 km/h with some steering engages it. While engaged:

- the player's steering picks a **target drift angle**;
- the assist points the **front wheels** along the front axle's own path, as the existing
  dynamic steering limit already does;
- the **rear tyres' grip** follows the target angle, in a band;
- the **engine torque fades** past the target, as Ferrari's side-slip control reads the angle;
- **TC stays on, relaxed**; **ESC stands aside**;
- the SVJ sends **at most 10 % of its torque forward**.

On release, the target drops to zero and the engagement fades over 0.5 s, so the assist steers out
of the drift. Below 30 km/h, or with the wheel straight, Space stays the handbrake it is today.

Measured offline on a candidate of this law, on both cars, at 50, 80 and 130 km/h, with the
keyboard's extremes included (full steer, full throttle):

- held angle 16.6° to 28.6°; peak at most 32.6° with TC on (33.5° for the SVJ and 36.4° for the
  DR458 with TC switched off);
- after the release, at most 0.6° of slip the other way, in all but one run (8.8°: DR458, 50 km/h,
  full steer, light throttle); settled under 3° in 0.30 to 1.37 s;
- a light throttle costs 2.4 to 10.3 km/h per second; full throttle loses at most 0.7 km/h per
  second, and mostly gains speed.

The candidate reads the car once a frame. At 30 FPS it loses the TC-off case (48° to 51° held), so
the implementation must run the law's fast parts inside the model's substep loop, as TC and ESC
already run. That is the main risk, and a frame-rate spec pins it.

Per-car numbers are few: the **maximum angle**, which the steering lock bounds (SVJ 25°, DR458 28°);
the **front torque share** while drifting (SVJ 0.10; the DR458 is rear-drive); and optionally the
**hold share**, a looseness knob (0.85 for both). Everything else is shared (§5.11).

The **sound** is a new tyre-audio rule driven by the slip the cars already publish (`TyreSlip*`,
`TyreSlide*`): an onset squeal at the limit and a sustained skid layer, from a CC0 recording first
(BigSoundBank #500) or the Assetto Corsa banks if the owner prefers. **Smoke already responds** to
the drift (rear share up to 1.0) and needs no change. The **camera** gets an optional blend toward
the direction of travel.

Work: four PRs (§10). The rule and its specs come first, with no runtime change. Then the wiring,
with a functional Play check. The tyre audio runs in parallel. The camera blend comes last.

## 1. How games implement drifting (research)

Condensed from the researcher's report; sources at the end.

### 1.1 Initiation

- **Real techniques** (b, Wikipedia): clutch kick ("the clutch is rapidly disengaged and
  re-engaged"), power-over ("applying excessive throttle to induce oversteer"), Scandinavian flick or
  lift-off oversteer (weight transfer), and the handbrake turn. A dual-clutch car has no clutch pedal.
  A Porsche PDK can imitate a clutch kick by pulling both paddles, then flooring it (b, The Drive,
  2019). (c) The DR458 therefore has handbrake, power-over, feint and lift-off entries, but no true
  clutch kick.
- **Need for Speed Unbound** offers Drift Entry options Off, Brake Tap, Gas Tap and Gas Or Brake Tap
  (b, TheGamer 2022). EA's guide says a throttle tap "means you're sacrificing less speed" (a)
  [excerpt].
- **NFS Heat** (Ghost Games, "Under the Hood: The Handling Model", 2019) (a) [excerpt]: extreme drift
  tuning lets the car "enter into a drift just by steering"; "stabbing the throttle while steering
  hard" breaks grip.
- **Inertial Drift** (Level 91, 2019) (a): each car has its own initiation trait. A slide can be
  "immediate when you push the right stick", or start only on lift-off or braking.
- **Factokyo Drift** (a Factorio mod; small source, low weight) (b): the handbrake on Space "keeps
  traction broken for exactly as long as you hold it". Below a 25 km/h minimum, "the handbrake only
  brakes".
- **Roblox:** Driving Empire uses the handbrake (Space or B) plus steering (b) [excerpt]. In Drift
  Paradise, the handbrake is P and the clutch is LeftShift (b). A-Chassis is detailed in 1.3.

### 1.2 What changes in the physics

- **Combined slip.** A locked or spinning tyre spends its grip along the wheel and loses lateral grip:
  the friction circle (b, Beckman, in note 01 §2.1). Drive Lab's tyre combines slips that way
  (`Vehicle/Tyre.luau`, `combinedForces`).
- **Post-peak fall-off.** The fall-off decides whether a slide can be held. The DR458's slicks keep
  0.78 of their peak drive at a slip ratio of 1, and 0.82 of their peak cornering force at 45° of
  slip angle (#127, measured). That is gentle, so a slide, once caught, is cheap to hold.
- **Handbrake against the engine.** A Bosch patent for an electronic drift handbrake (US10933855B2)
  (a) may send "a signal that disengages a clutch of an engine", "to prevent the engine stall". Ford's
  Focus RS drift stick opens the differential clutches as it locks the rear (b) [excerpt].
- **Limited-slip differentials:** clutch-type, two-way diffs are preferred for drifting, and welded
  diffs are the budget option (b, Wikipedia).
- **Drift modes on real cars relax the electronics; they do not switch them off:**
  - Lamborghini Huracán EVO RWD's P-TCS "delivers torque to the wheels even when the car is realigning
    after drifting" (a) [excerpt].
  - Ferrari's Side Slip Control "calculates the side-slip angle, comparing it with reference data",
    then manages torque and the E-Diff (a) [excerpt].
  - AMG E63 S Drift Mode: "drive occurs only at the rear" (a) [excerpt].
  - Focus RS: up to 70 % of the torque to the rear (b) [excerpt].

### 1.3 Assists and arcade drift, with their knobs

- **A-Chassis 1.7.2** (Roblox, open source, read from its code) (a). Countersteer is on by default:
  - `CSAmt = 100` (percent "at a full perpendicular slide");
  - `CSSteerThresh = 10` (it acts only while the player's steer is under 10 %);
  - `CSSpeedThresh = 10` km/h.

  The amount is the lateral velocity over the speed, times `CSAmt`, added to the player's steer.
  Its TCS defaults (threshold 10 km/h of slip, gradient 10, floor 4 % torque) would choke a power-over
  drift, so the TCS must stand aside. `PBrakeForce = 1000`, all rear.
- **Rocket League's powerslide**, reverse-engineered by RocketSim (b): the input is smoothed with a
  rise rate of 5/s and a fall rate of 2/s (about 0.2 s on, 0.5 s off, (c)). Lateral friction goes to
  ×0.1 and longitudinal to ×0.5 to ×0.9, on every wheel.
- **Unreal Chaos vehicles** (a, API docs): `SideSlipModifier`, `SkidThreshold`, `SlipThreshold`,
  `MaxHandBrakeTorque`, and an arcade `TargetRotationControl` ("direct control of vehicle rotation
  via torque force"). The docs publish no defaults.
- **Forza:**
  - Forza's Normal steering is "multiple systems layered together" that influence "the yaw inertia
    of the car" (a) [excerpt].
  - Forza Motorsport's drift parts give "up to 60 degrees of tunable Steering Angle" (a, 2024).
  - No official Forza Horizon countersteer assist was found.
- **CarX:** players report its steering assist "tries to keep the car at a certain angle" and
  "allows absolutely NO slide in the front wheels" (b). No developer definition was found.
- **GT7** Countersteering Assistance: Off, Weak or Strong (a) [excerpt].
- **BeamNG:** its limiter "retains full countersteering range according to the sliding angle" (b,
  2023).
- (c) **The categories.** A-Chassis and BeamNG are counter-steer assists. CarX and Unreal's rotation
  control are angle-hold assists. Rocket League and NFS Heat's extreme tunes are grip scaling (arcade).
  Inertial Drift and Forza's Simulation steering are pure physics with per-car traits.

### 1.4 Speed cost and exit

- **Speed cost:** Mario Kart's manuals say "Drift around sharp corners without reducing speed!"
  (b, MK8). NFS keeps speed with a throttle-tap entry and a weaker handbrake (b) [excerpt]. Factokyo
  fades the handbrake's braking "as a slide develops" (b). Rocket League cuts longitudinal friction
  (b).
- **Exit:** Rocket League releases grip more slowly than it removes it (2/s against 5/s) (b). P-TCS
  keeps torque through the realignment (a) [excerpt]. No source gives an exit blend time or angle
  threshold.

### 1.5 Keyboard and gamepad, and per-car values

- A-Chassis's countersteer acts only once the player releases the key, which suits a binary
  keyboard (c). CarX's assist reportedly stays on with keys even when set off (b). Inertial Drift
  separates the steering and angle sticks (a).
- **Per car:** Inertial Drift gives each car "its own distinct control scheme" (a). NFS has a per-car
  Grip-Drift slider set by the parts (b). The Sega squeal patent applies per-vehicle coefficients (a).
  Rocket League's powerslide constants look shared (c).

### 1.6 Sound, smoke, camera, scoring

- **Squeal** (a, Sega patent US8078300B2): three loops (quiet, loud, "aggressive") cross-fade by slip
  angle. As tyre load rises, "the volume … increases and the pitch … decreases".
- **A-Chassis's squeal** (a): stress = rim-speed slip, eased. Volume is stress³ × 1.4, pitch is
  1.6 − 0.5 × stress, smoke is stress¹⁰ × 100. Pad rumble comes from slip.
- **Torque3D** plays a looping `squealSound` whose volume follows how much the wheels slip (a).
- **Licensable recordings:**
  - BigSoundBank #500 "Tire squeal": "CC0 (public domain)", "Attribution isn't required" (a).
  - Freesound CC0 candidates (audible-edge 71736 to 71739 and 71741; 76806; 614627; 850041); confirm
    each sound's page.
- **Camera:** Forza Motorsport's Drift Camera applies to in-car and follow cameras (a, 2024). Forza
  Horizon's cockpit drift camera has Sensitivity and Range settings (b).
- **Scoring:** Forza Motorsport uses "speed, angle, and duration", and a drift is banked by stopping
  without breaking it (a, 2024). No CarX or Forza Horizon formula was found.

## 2. Drive Lab today

### 2.1 What Space does

- `Config/Controls.luau`: `HANDBRAKE = { Space, ButtonX }`. `Controllers/Driving.luau` reads it as 0
  or 1.
- `Vehicle/Brakes.luau` adds `handbrake × handbrakeTorque` on the rear wheels only, outside the ABS
  (SVJ 2,500 Nm, DR458 1,800 Nm).
- The input filter ramps it like the brake.

Measured (`drift_baseline.luau`): each car in a steady 0.5 g right-hand turn at 80 km/h, in a fixed
gear, its first drive mode with its own assists.

| Event | SVJ | DR458 |
|---|---|---|
| Space held 1 s, steering held | rear locked (slip ratio −1), spins (body slip past 90°), 69 km/h lost in 3 s; ESC acting 46 % of the time | rear locked, spins, 71 km/h lost |
| Space 0.5 s, then full throttle | 9.6° of body slip at most, then straight | 2.0° at most |
| Engine during the pull | clutch opens; the engine falls to 914 to 948 rpm | 0.5 s run: the clutch **stays closed** while the handbrake drags the engine from 5,177 to 2,029 rpm |

The automatic clutch only opens once its input falls under its creep speed (`Gearbox.updateClutch`),
so a pull in gear first fights the engine's inertia through the gearbox. The Bosch patent's clutch
disengage exists for exactly this.

### 2.2 The tyres at a locked rear and large slip angles

- **A locked rear loses its lateral grip,** as it should: the combined slip gives the force to the
  locked direction, which is why both cars spin.
- **Past the peak, the curve falls gently** (0.78 to 0.82 of the peak), so a slide is holdable once
  caught.
- **A rear grip cut alone, with the steering held, has a sharp edge:**
  - SVJ with its assists off: stable at ×0.8, spinning at ×0.65. With ESC on, it holds ×0.65 by
    braking 100 % of the time.
  - DR458: stable at ×0.65, spinning at ×0.5.

  So no fixed cut gives a holdable drift by itself.

### 2.3 Assists, steering, driveline

- **ESC:** the SVJ's ESC (on in Strada) brakes the outer front against the very yaw a drift needs (on
  100 % of the time in the cut runs). The DR458 has none (`Cars/DR458/Assists`).
- **TC** cuts at a slip of 0.08 to 0.18 depending on the mode. The DR458's OFF switches it off.
- **Steering lock bounds the drift angle.** To hold a body slip angle, the front wheels must point
  near the front axle's path. The DR458's road wheels stop at 31.3°, and the SVJ's at 30°. The SVJ's
  ratio also rises from 10:1 to 18:1 with speed, so a full input gives it less angle at speed. (c)
  Real drift cars add lock for this reason (Forza's 60° drift parts).
- **Steering geometry already exists:** `InputFilter.steerBounds` already computes the front axle's
  path angle and clamps the steering to it plus a target slip ("a slide shifts both bounds, which
  opens countersteer by itself").
- **The SVJ's front share comes from its drive mode** (`frontShareDrive`): Strada 0.40, Sport 0.07,
  Corsa 0.20.

### 2.4 What is missing, per car

| | SVJ (AWD, ESC, 4WS) | DR458 (RWD, slicks, TC, no ESC) |
|---|---|---|
| Entry | the handbrake locks the rear and spins; no way to hold an angle | the same; power-over spins in OFF (#127, open loop) |
| Holding an angle | ESC fights it; 40 % of the torque goes forward in Strada | TC fights it in 1 and 2 |
| Countersteer | lock 30°, less at speed | lock 31.3° |
| Sound | no tyre sound at all | the same |
| Smoke | slip-driven already | the same |
| Camera | yaw rigid to the body | the same |

## 3. Options

| | A. Realistic | B. Assisted (recommended) | C. Arcade |
|---|---|---|---|
| Idea | Space stays a true handbrake; it breaks the rear loose, the driver catches it | Space engages a drift rule that holds the angle the steering asks for, through tyre forces | Space cuts rear grip hard and a yaw controller sets the rotation |
| What changes | clutch opened while the handbrake is held; TC relaxed while it is held; squeal | `Rules/Drift`, a per-car profile, a Drift drive mode, a hook in the model's substep loop; squeal; camera blend | a rear grip scale near ×0.1 to ×0.3; a yaw torque toward a target rotation (Unreal-style); speed kept artificially |
| Feel risk | measured: a 1 s pull spins both cars; a short pull plus throttle gives 2° to 10°. Hard on a keyboard, against the owner's "playable" | the car's physics untouched; the assist only when Space is held; a frame-rate risk if done per frame (measured) | a non-physical force acts on the car: it contradicts note 08's "help goes in the input layer", and fights the tyre model |
| Per car | none needed | max angle, front share, hold share | the yaw targets |
| Proving specs | handbrake lock, clutch open, no stall | §5.12 | yaw target tracking, speed kept |
| Sound | squeal | squeal + skid | squeal + skid |
| Agents and PRs | systems (1), audio (1) | systems (2), audio (1), camera (1) | systems (2), audio (1), camera (1) |

Why not A alone: the owner asked for a playable, shared mechanism with TC on. The baseline shows a
true handbrake spins or barely rotates. Why not C: a yaw torque makes the car's own physics a
passenger, and a fixed grip cut already spins (§2.2). B keeps every force a tyre force, and puts the
help where note 08 says it belongs: between the player and the car, active only while Space is held.

## 4. Method

`tools/drift_candidate.luau` runs a candidate of the law in DriveSim. It reaches the car only through
inputs the model already has:

- the rear wheels' surface grip (`DriveSim.wheelGrip`, the multiplier `VehicleRunner` fills from the
  road);
- the steering;
- the throttle;
- the assist flags;
- a cloned Drift drive mode.

**The scripted run:** straight at 50, 80 or 130 km/h in a fixed gear. At 1 s, the steering goes to
0, 0.4 or 1 over 0.3 s, Space goes down, and the throttle goes to 0.3 or 1. At 4 s, both are
released and the throttle holds the speed.

**Earlier candidates spun in every run.** These exploration runs are recorded in the work notes, not
in a committed tool:

- a fixed rear cut of 0.4 to 0.6 with A-Chassis countersteer;
- the grip share as a controller alone;
- that controller plus a torque fade.

Each failed for a reason the next one fixed. The last failure is the steering lock (§2.3).

## 5. The balancing model (option B)

### 5.1 Space, the gate and the engagement

- Space held, speed of at least `minKmh` (30), and |steer| of at least `steerGate` (0.25), or a body
  slip already over 5°: **engage**.
- The engagement `e` rises to 1 over `riseTime` (0.25 s) and falls to 0 over `fallTime` (0.5 s): the
  RocketSim powerslide rates (5/s on, 2/s off).
- **Space below 30 km/h, or with the wheel straight and no slide, applies the handbrake as today.**
  Parking, a low-speed handbrake turn and a straight-line handbrake keep working. Once engaged, the
  handbrake torque is released: the drift replaces the lock (measured: a held lock spins).
- Measured: entry takes 0.40 to 0.67 s to 10° of body slip. Space with the wheel centred never
  engages.

### 5.2 The target angle comes from the steering

`target = minAngle + (maxAngle − minAngle) × clamp((steer × direction − steerGate) / (1 − steerGate), 0, 1)`.
The direction is the turn the drift started in.

| Steering | Target |
|---|---|
| Centred | `minAngle`, 15° |
| Full toward the turn | the car's `maxAngle` |
| Toward the other side (past the gate) | 0 |
| Space released | 0 |

On a keyboard: hold the key for a deep drift, release it for a shallow one, press the other way to
straighten. On a pad the stick doses the angle. Measured: steer 0.4 (target 17° to 17.6°) held 16.6°
to 19.0°; full steer (target 25° or 28°) held 23.3° to 27.7°.

### 5.3 The steering assist

While engaged, the front wheels point along the front axle's own path,
`atan((v_right + a × yaw rate) / v_forward)` (the geometry of `InputFilter.steerBounds`), plus a slip
toward the turn:

- `frontSlip` (0.6) of the front's peak slip angle at the target;
- less 1 (`steerGain`) for every 10° over the target;
- less 1 for every 100°/s the angle is growing.

The front then pulls the car round while the rear slides. Over the target, the front lets the nose
back out.

The steering blends from the player's to the assisted angle with `e`. It must act **after** the input
filter: the keyboard's ramp (1.3 s to full lock, slower at speed) would otherwise slow the very
correction that holds the angle. The DriveSim runs used the direct input help, which stands for that.

### 5.4 The rear grip share

`share = holdShare + angleGain × (angle − target) / max(target, 5°) + rateGain × angle rate`,
clamped to `[floorShare, 1]`. The rear grip is then `1 − e × (1 − share)`. Starting values: hold 0.85,
floor 0.45, angle gain 0.8, rate gain 0.01 per °/s.

It enters through the per-wheel surface grip the model already takes (`WheelContact.grip`), so the
tyre model itself is unchanged. Above the target the rear gets its grip back, which is what stops a
spin.

Measured: without the cut, a light throttle never drifts (0.7° to 2.3°), and full throttle needs 0.80
to 1.02 s to enter. The cut is what lets Space work without flooring the throttle.

### 5.5 TC, ESC and ABS while drifting

- **TC stays on, relaxed.** While engaged, the car runs its Drift mode: its current mode with
  `tcSlipRatio` raised to 0.3, a real-car pattern (P-TCS, Ferrari SSC, §1.2). TC still stops a
  burnout past 30 % slip.
- **Torque fade past the target**, a side-slip control: the throttle's share is
  `1 − e × clamp((angle − target) / 10°, 0, 1)`. A keyboard's full W cannot over-rotate the car.
  Measured: full throttle and full steer held 25.1° (SVJ) and 27.5° (DR458) at 80 km/h.
- **ESC stands aside** while engaged, and returns when `e` falls under 0.05. It brakes against the
  yaw the drift needs: on 100 % of the time in the baseline's cut runs.
- **ABS is unchanged:** the brake pedal is not part of the drift.
- **The DR458's manettino OFF** has TC off, and the drift still works. Measured at 60 FPS: 28.6° held,
  36.4° at peak. At 30 FPS it does not (§5.10).

### 5.6 All-wheel drive

While engaged, the SVJ sends at most `frontShare` (0.10) of its torque forward, near its own Sport
mode's 0.07. That follows the real AWD drift-mode pattern (AMG, Focus RS, §1.2). Measured on the SVJ
with this cap: the same bounded angles as the rear-drive DR458 (§5.9).

### 5.7 The speed cost

The throttle decides it. Measured at 80 km/h:

- throttle 0.3: the drift costs 4.4 to 8.4 km/h per second;
- full throttle: it gains 2.2 to 11.5 km/h per second. Across all three speeds, the worst
  full-throttle run loses 0.7 km/h per second (DR458, 50 km/h, full steer).

Game-style, the drift keeps momentum when the player stays on the throttle. Nothing adds speed that
the engine does not make.

### 5.8 The exit

On release, the target drops to 0 while `e` fades over 0.5 s. The assist steers out of the drift,
and the rear gets its grip back as the angle shrinks.

Measured: at most 0.6° of slip the other way, in all runs but one. That run (DR458, 50 km/h, full
steer, throttle 0.3) snapped 8.8° the other way; the implementation's specs must catch it (§5.12).
Settle time to under 3°: 0.30 to 1.37 s. The snapping run crossed 3° at 0.05 s, then slid the other
way.

### 5.9 Measured candidate results (60 FPS)

From `docs/evidence/drift-plan/drift_candidate_60fps.txt`:

| Car, km/h, steer, throttle | Entry s | Held ° | Peak ° | km/h lost per s | Snap ° | Settle s |
|---|---|---|---|---|---|---|
| SVJ 50, 1.0, 1.0 | 0.45 | 24.6 | 30.4 | −4.5 | 0.4 | 0.93 |
| SVJ 80, 0.4, 0.3 | 0.57 | 17.2 | 20.9 | 4.4 | 0.1 | 0.50 |
| SVJ 80, 1.0, 1.0 | 0.42 | 25.1 | 30.4 | −5.5 | 0.0 | 0.93 |
| SVJ 130, 1.0, 1.0 | 0.43 | 25.4 | 30.1 | −6.1 | 0.0 | 1.37 |
| DR458 50, 1.0, 0.3 | 0.55 | 23.5 | 32.6 | 9.3 | **8.8** | 0.05 |
| DR458 80, 0.4, 0.3 | 0.58 | 17.8 | 21.1 | 5.6 | 0.0 | 0.55 |
| DR458 80, 1.0, 1.0 | 0.40 | 27.5 | 32.3 | −2.2 | 0.0 | 0.67 |
| DR458 130, 1.0, 1.0 | 0.40 | 27.7 | 31.8 | −1.8 | 0.0 | 0.90 |
| DR458 80, 1.0, 1.0, TC off | 0.40 | 28.6 | 36.4 | −8.5 | 0.0 | 0.92 |

### 5.10 Frame rate: the law belongs in the substep loop

At 120 FPS the candidate matches 60 FPS: TC off, 25.6° (SVJ) and 28.4° (DR458) held. At 30 FPS, held
angles agree within 1.5° in all but one run (3.8°: DR458, 50 km/h, full steer, light throttle), and
peaks are 1.4° to 2.8° higher. **Two cases diverge:**

- With TC off, 51.3° and 48.4° held, 56.9° and 59.0° at peak.
- Without the grip cut at full throttle, 10.8° and 10.5° held, against 19.2° and 24.0°.

The candidate reads the car once a frame, and at 30 FPS its 33 ms lag is too slow for a fast yaw at
full throttle. The fix is architectural: the torque fade and the grip share run inside
`Model.step`'s substeps, at a fixed rate, as `Electronics` runs TC and ESC at their own rates. Then
DriveSim and Roblox run the same law at any frame rate. The frame-rate spec in §5.12 is the
acceptance.

### 5.11 Parameters: per car and shared

Per car, one `drift` profile in `Config/Cars/<car>/`:

| Parameter | SVJ | DR458 | Why |
|---|---|---|---|
| `maxAngle` | 25° | 28° | bounded by the lock (SVJ 30° and 18:1 at speed; DR458 31.3°) |
| `frontShare` | 0.10 | (rear drive) | the AWD drift-mode pattern; the SVJ's own Sport mode is 0.07 |
| `holdShare` | 0.85 | 0.85 | a looseness knob: lower is looser |
| `tcSlip` | 0.3 | 0.3 | relaxed TC in the Drift mode |

Shared, in `Config/Drift.luau`:

| Parameter | Value | Source |
|---|---|---|
| `minKmh` | 30 | Factokyo 25, A-Chassis countersteer 10 (§1.1, §1.3) |
| `steerGate` | 0.25 | A-Chassis's 10 % gate, raised so a keyboard tap does not engage |
| `riseTime`, `fallTime` | 0.25 s, 0.5 s | RocketSim 5/s and 2/s |
| `minAngle` | 15° | measured |
| `floorShare` | 0.45 | measured: the spin edge of a fixed cut lies above it |
| `angleGain`, `rateGain` | 0.8, 0.01 per °/s | measured |
| `torqueBand` | 10° | measured |
| `frontSlip`, `steerGain` | 0.6 of peak, 1 per 10° and per 100°/s | measured |

### 5.12 The specs that would pin each rule

All are written in the implementation PRs. Each is shown failing on a deliberate break before it is
trusted.

1. **Gate.** Space below 30 km/h, or with |steer| under 0.25 and no slide, brakes the rear exactly as
   today and never cuts grip. Above both, `e` reaches 1 in 0.25 s.
2. **Release.** `e` reaches 0 in 0.5 s. TC's threshold and ESC are back when `e` is under 0.05.
3. **Target mapping:** centred 15°, full toward the turn `maxAngle`, the other way 0.
4. **Bounded angle.** At 50, 80 and 130 km/h, steer 0.4 and 1, throttle 0.3 and 1, on both cars:
   peak no more than `maxAngle` + 8°, held within 4° of the target, never a spin.
5. **Exit.** No more than 3° the other way after the release, and under 3° within 1.5 s. Today's
   candidate fails this once (8.8°), so this spec drives a fix: for example a slower `fallTime` at low
   speed, or the target easing to 0.
6. **Speed.** At throttle 0.3, no more than 11 km/h lost per second; at full throttle, no more
   than 1 km/h lost per second (measured worst: 10.3 and 0.7).
7. **TC on stays on.** While engaged with TC enabled, the rear slip ratio stays near the Drift mode's
   0.3, and well above it with TC off.
8. **AWD.** The SVJ's front share is at most 0.10 while engaged, and back to its mode's after.
9. **Frame rate.** Specs 4 to 6 hold at 30, 60 and 120 FPS. The per-frame candidate fails this with
   TC off at 30 FPS; the substep law must pass it.
10. **Keyboard.** With `InputHelp.keyboard`, a held key and full W give spec 4's bounds.
11. **No drift, no change.** With Space never held, every calibration spec and the tools' outputs are
    unchanged.

## 6. Sound: squeal and skid tied to slip

No tyre sound exists today. A search over `games/drive-lab/src` for squeal, skid, screech, scrub,
tyre noise and tire found only a comment in `Vehicle/Interface.luau` ("For squeal and rumble") and
the roadside skid-mark decals.

**A new pure rule, `Rules/TyreAudio`, plus a controller.** It reads the per-tyre attributes Driving
already publishes for the smoke (`TyreSlipFL..RR`: combined slip over the slip of peak grip;
`TyreSlideFL..RR`: m/s the patch slides). It plays two looped layers per axle, front and rear:

- **Onset squeal:** normalised slip from 0.8 to 1.5, times an ease of the slide from 1 to 4 m/s.
  Players hear the limit just before they pass it, as note 01 §4 point 7 suggests ("starting at ~0.7
  of peak").
- **Sustained skid:** slip from 1.5 to 4, and slide from 3 to 12 m/s. In the measured drifts the rear
  ran at 2.9 to 6.3 times peak slip (8.8 with TC off) and 4.8 to 20.4 m/s, so this layer carries the
  drift.
- **Pitch** rises a little with slide speed and drops as load rises (Sega). Volume falls with
  wetness, as the smoke's `dryShare` does. A cap on the total keeps the cost bounded.

**Sourcing, with the owner's choice:**

1. **BigSoundBank #500 "Tire squeal"** (CC0, 30 s, 48 kHz): the cleanest licence. Cut an onset loop
   and a sustained loop from it.
2. **Freesound CC0** candidates (§1.6), each checked on its own page.
3. **The Assetto Corsa banks**, which the owner used for the DR458 engine pack (#98). The
   recordings are Kunos's, so per the owner's rule (quality over licence, provenance recorded,
   third-party assets never in the public repo) they stay outside the repository.

One upload packs both loops, as the road pack does. Audio uploads are rationed (100 per 30 days),
and Roblox's moderation once rejected a Freesound wind for the road pack, so a fallback recording
should be ready. The audio agent builds this, and it is useful even without the drift: it squeals at
the grip limit in ordinary cornering too.

## 7. Smoke

`Rules/TyreSmoke` already makes smoke from the slip past the limit (thresholds: slip 2.2 to 4.5,
slide 2 to 10 m/s). Across the measured drifts the rear smoke share was 0.17 to 1.00: lowest at a
small angle and a light throttle (0.17 to 0.56), and 0.83 to 1.00 in 13 of the 18 runs at full
steer or full throttle. **No change is proposed.** The Play check
confirms the look; it is the VFX agent's to retune if the owner wants more or less.

## 8. Camera

The chase camera's yaw is rigid to the body (`Config/CarCamera.luau`, yaw spring off). In a 25° drift
the camera therefore looks 25° away from where the car is going.

Proposal: while engaged, blend the chase camera's yaw toward the direction of travel by a share of
the body slip (start at 0.4: the camera looks 10° toward the path at 25°), in and out at the
engagement's rates. This is the role of Forza's drift camera (§1.6). It belongs to the camera agent,
after the drift is wired, with an edit-mode capture and the owner's Play.

## 9. Scoring

Not proposed now. Forza's "speed, angle, and duration" (§1.6) would read the published drift angle
and speed later, if the owner wants a game mode.

## 10. Plan of work

1. **Systems, PR 1: the rule, offline.**
   - `Rules/Drift.luau`, pure: gate, engagement, target, steering assist, grip share, torque fade.
   - `Config/Drift.luau`, the per-car `drift` profiles, and the Types change.
   - A DriveSim drift scenario, and specs 1 to 11 with mutation proofs.
   - No runtime wiring: zero risk to the current feel.
2. **Systems, PR 2: the wiring.**
   - `DriverInput` gains `drift` (Space).
   - The model runs the law in its substeps and releases the handbrake once engaged.
   - The rear grip enters through `WheelContact.grip`, the steering assist after the input filter.
   - The per-car Drift mode; ESC suspended; the SVJ's front share capped.
   - Driving publishes `DriftActive` and `DriftAngle`.
   - A functional Play session on both cars before the PR (CLAUDE.md: a runtime flow is run end to
     end); the owner's feel test after the merge.
3. **Audio, PR 3: the tyre squeal**, in parallel with PR 1. It needs the owner's pick of recording
   (§6) and one upload.
4. **Camera, PR 4: the drift blend**, after PR 2.

**Risks:**

- **Frame rate** (§5.10): the substep law and spec 9 are the mitigation.
- **The exit snap at low speed** (spec 5).
- **The keyboard's ramp:** the assist must act after the input filter (spec 10).
- **Feel:** the starting values are a candidate's, and the owner judges them in Play.
- **The SVJ's four-wheel steering** was left on in every run. Its rear steer at speed may change the
  drift's feel; that has not been isolated.

## 11. Not verified

- Feel, in Play, on any car. All runs are offline: a flat plane, uniform grip, massless wheels.
- The candidate law at frame rates other than 30, 60 and 120 FPS, on wet roads, on other surfaces, or
  in left-hand corners. The law is symmetric, but left-hand runs were not made.
- The keyboard's input filter with the assist: the runs used the direct input help (§5.3).
- The automatic gearbox during a drift: every run held one gear in manual. With the rear spinning,
  the automatic may upshift on wheel-driven rpm mid-drift; the implementation's specs should run in
  auto too.
- The hold share's effect: both cars use 0.85, and the committed runs do not vary it, so its role as
  a looseness knob is a proposal.
- The handbrake-release-once-engaged behaviour, and opening the clutch for a low-speed handbrake: not
  measured, proposed.
- Every [excerpt] source, the Freesound licences one by one, and the Rocket League values, which are
  reverse-engineered rather than published.
- The squeal mapping and the camera blend: proposals with starting values, not measured.

## Sources

Gathered 2026-10-31 by the researcher agent; dates as shown on the pages.

- A-Chassis 1.7.2 (MPL-2.0): https://raw.githubusercontent.com/lisphm/A-Chassis/main/Scripts/A-Chassis%20Tune.luau
  and https://raw.githubusercontent.com/lisphm/A-Chassis/main/Scripts/Drive.luau (a)
- RocketSim (Rust port 0.2.4), constants and wheel friction:
  https://docs.rs/crate/rocketsim/latest/source/src/sim/consts.rs (b)
- Unreal Chaos vehicles: https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Plugins/ChaosVehicles/UChaosVehicleWheel
  and https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/ChaosVehiclesCore/FTargetRotationControlConfig (a)
- NFS Unbound drift methods, TheGamer, 2022-12-07: https://www.thegamer.com/need-for-speed-unbound-drift-methods-guide/ (b)
- NFS Heat, "Under the Hood: The Handling Model", EA Answers, 2019 (403 to fetch):
  https://answers.ea.com/t5/General-Discussion/Under-the-Hood-The-Handling-Model/m-p/8177780 (a) [excerpt]
- NFS eGuide, handling tuning: https://primagames.com/eguides/need-for-speed-eguide/in-the-garage/handling-tuning (b) [excerpt]
- Inertial Drift interview, 2019-12-25: https://gamingbolt.com/inertial-drift-interview-twin-stick-drifts (a)
- Factokyo Drift changelog: https://mods.factorio.com/mod/factokyo-drift/changelog (b)
- Mario Kart drift (manual quotes): https://www.mariowiki.com/Drift (b)
- Forza Motorsport Update 13, 2024-10-14: https://forza.net/news/forza-motorsport-update-13 (a)
- Forza Horizon 4 wheel setup and tuning: https://support.forza.net/hc/en-us/articles/360002007867-FH4-Wheel-Setup-and-Tuning (a) [excerpt]
- CarX Drift Racing Online Steam discussions:
  https://steamcommunity.com/app/635260/discussions/0/1470841715932979916 and
  https://steamcommunity.com/app/635260/discussions/0/1699416432409283571 (b)
- BeamNG forum, 2023-01-04: https://beamng.com/posts/1543337 (b; stenyak's reply (a))
- Lamborghini Huracán EVO RWD release, 2020: https://media.lamborghini.com/English/aktuelles/new-lamborghini-hurac-n-evo-rear-wheel-drive--the-driver-in-total-control-of-sheer-driving-fun/s/93171e07-a80f-405f-b5ed-ffb1ca4bddf3 (a) [excerpt]
- Ferrari, E-Diff and Side Slip Control: https://www.ferrari.com/magazine/articles/great-ferrari-innovations-the-e-diff-and-slide-slip-control (a) [excerpt]
- Bosch drift-mode electronic handbrake, US10933855B2: https://patents.google.com/patent/US10933855B2/en (a)
- Porsche PDK clutch kick, The Drive, 2019-09-29: https://www.thedrive.com/news/30044/heres-how-to-clutch-kick-a-pdk-automatic-equipped-porsche-911-gt3-rs (b)
- Drifting (motorsport), Wikipedia: https://en.wikipedia.org/wiki/Drifting_(motorsport) (b)
- Sega tyre squeal patent, US8078300B2: https://patents.google.com/patent/US8078300B2/en (a)
- Torque3D WheeledVehicleData: https://reference.torque3d.org/scripting/class/classwheeledvehicledata (a)
- BigSoundBank #500 "Tire squeal": https://bigsoundbank.com/tire-squeal-s0500.html (a)
- Freesound CC0 tyre squeal search: https://freesound.org/search/?q=tire+squeal&f=license%3A%22Creative+Commons+0%22 (b)
- Roblox DevForum on friction: https://devforum.roblox.com/t/more-advanced-friction/958572 [excerpt] and
  https://devforum.roblox.com/t/how-to-make-a-car-drift/1183217 (b)
- Drive Lab: note 01 (§2.1, §4), note 08 (§0, §3.2), #127 (the slicks' curve).

**Searched, not found** (the researcher's list):

- Ghost Games and Criterion primary pages (403, 404 or gated): so every NFS developer quote here is
  [excerpt].
- CarX's own assist definitions and scoring.
- Forza Horizon's official assist definitions and scoring.
- Unity drift-kit documentation (NWH, Realistic Car Controller, Edy's).
- Assetto Corsa's FMOD skid event names.
- A GDC talk on layered squeal.
- A credible source on drift-exit snap.
- Parameters of Roblox drift games beyond A-Chassis.
