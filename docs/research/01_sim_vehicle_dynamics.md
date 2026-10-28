# 01 — How serious driving sims model and tune a car (for a Roblox port)

Date: 2026-10-27. Reference car: Lamborghini Aventador SVJ (AWD with an electronically controlled centre coupling, NA V12, 7-speed single-clutch ISR, four-wheel steering, active aero).
Scope: modelling and tuning *methods* only. The car's own numbers belong to the car-data note; Roblox APIs belong to the engine note. Where this note needs a number from either, it says so.

**Evidence tags used everywhere below**

- **(a)** documented by the developer (official docs, patch notes, developer posts or interviews).
- **(b)** explained by a credible community or engineering source (modding docs, textbooks relayed by courses, engineering forums, reputable press).
- **(c)** my own inference or calculation. Every (c) number shows its inputs so it can be checked.
- **[excerpt]** after a source in section 6 means I saw that claim only in a search-result summary, not on the page itself (the page was blocked or not fetched). Treat those as weaker.

---

## 1. One-page summary: the recommended model for a Roblox port

Constraints that drive every choice (c): our players use keyboard or gamepad (no force feedback), Luau CPU budget is small, Roblox physics steps at 240 Hz by default while our scripts run about once per frame (Roblox doc, and the brief; the engine note must confirm how script-set forces are held across the 240 Hz substeps). Most serious sims run their physics at 333–2000 Hz (table in section 5). So the port has to buy stability with technique, not with tick rate.

| Subsystem | Recommended model | Why (evidence) |
|---|---|---|
| **Integration architecture** | Chassis = one Roblox rigid body integrated by the engine. Our script runs a fixed internal loop each frame (start at 8 substeps ≈ 480 Hz) for the fast states only: wheel spin, tyre slip states, drivetrain friction elements. Stiff springs that act on parts go into engine constraints so the 240 Hz solver integrates them. Low speed falls back to a "sticky" static-friction mode. | Wheel spin is the stiffest state of the car: its equivalent mass is about 10 kg against 750 kg per axle for the chassis (c, section 5). Vehicle Physics Pro runs 50 Hz rigid-body steps with 2–8 internal substeps (a). PhysX recommends nested substeps for the stiffest parts and a sticky mode at low speed (a). |
| **Tyre, steady state** | One analytic pure-slip curve per direction, shaped by designer knobs: peak μ, slip at peak, fall-off to sliding μ (implemented as a simplified Magic Formula, B C D E). Load sensitivity as a power law around a reference load (μ falls as load rises). No 30-coefficient Pacejka. | AC's author aimed for a physics-based tyre with very few parameters, built from a "base slip curve" (a). AC exposes peak μ at a reference load plus load-sensitivity exponents (FZ0, DY_REF, LS_EXPY) and fall-off knobs (FALLOFF_LEVEL, FALLOFF_SPEED) (b). We have no Pacejka data for the SVJ's tyre, and Edy's guide warns that unguided full-MF values produce arbitrary curves (b). |
| **Tyre, combined slip** | Normalise slip ratio and slip angle by their own peak slips, combine them into one magnitude, run that through the curve, split the force back by direction (Beckman's "combination grip"), then clamp to a friction ellipse. | Beckman, written for simulator builders (b). PhysX does linear forces then a load × friction limit (a). Cheap, and it keeps the pure-slip curves exact (b). |
| **Tyre, transient and low speed** | Slip angle (and slip ratio) as **state variables with a relaxation length** (about 0.15–0.45 m), updated with an exact exponential step. Velocity floor in the slip denominators. Below a few km/h, blend into a clamped spring-damper "bristle" (or a sticky constraint) so a parked car does not creep or jitter. | This is the CarSim workaround: a relaxation state plus a speed floor (b, paper describing it). At standstill the relaxation state becomes a lateral tyre spring, which is physically correct because relaxation length = cornering stiffness / lateral stiffness (b). PhysX uses slip-denominator floors and a sticky mode (a). |
| **Contact** | 3–5 rays (or a shapecast) per wheel, averaged, not one ray. | ACC uses a 5-point patch to stop the "rail kerb" effect (a). Forza went from 1 point at 60 Hz to 8 points at 360 Hz (a). CSP adds lateral and longitudinal rays to AC (b). |
| **Suspension** | Per corner: wheel rate from a target ride frequency, two-slope damper (slow and fast, bump and rebound), progressive bump stop as a lookup table, anti-roll bar as an equal and opposite force pair, static camber and toe plus a camber-gain curve. Massless or light wheel. | AC's damper is 4–5 linear values (bump, rebound, fast bump, fast rebound, threshold) and ACC moved to full curves from manufacturer data (a). Bump stops matter: ACC 1.9 capped their travel at 20–30 mm (a). A massless wheel removes the ~14 Hz wheel-hop mode, the stiffest suspension mode (c). |
| **Drivetrain** | A tree of rotating inertias (engine, gearbox, centre coupling, axle diffs, wheels) linked by gear ratios and **friction elements** (clutch, LSD clutch packs, centre coupling), each with a torque capacity. Solve friction elements with an implicit (locked or slipping) step inside the substep loop. | BeamNG's powertrain is a modular device tree in Lua (a). Its diff types are open, LSD (locking from input torque), viscous (locking from speed difference) and locked (b). AMS2 calls its driveline a physical model of masses, frictions and stiffnesses (a). |
| **Gearbox (ISR)** | Shift = torque cut, clutch open, neutral for the shift time, then clutch re-engages with slip (that slip makes the single-clutch "kick"). Separate up and down shift times, downshift blip. | AC stores CHANGE_UP_TIME, CHANGE_DN_TIME and AUTO_CUTOFF_TIME (b). In PhysX the car is in neutral for the switch time (a). |
| **AWD (Haldex-like)** | Centre coupling = clutch whose torque capacity a small controller sets from front/rear speed difference, throttle and speed. Front open diff; rear LSD with preload plus power and coast ramps. | Same friction-element machinery. LSD semantics from AC (POWER, COAST, PRELOAD) and BeamNG (lsdPreload, lsdLockCoef, viscousCoef) (b). The real control law belongs to the car-data note. |
| **Brakes and electronics** | Brake torque per wheel with front share. ABS = slip-ratio threshold with a pump rate. TC = two stages (torque reduction, then cut) with a slip threshold and a minimum speed. ESC = yaw-rate error against a bicycle-model reference, braking single wheels. All switchable. | AC electronics: SLIP_RATIO_LIMIT, RATE_HZ, MIN_SPEED_KMH (b). ACC TC: ignition retard then cut, and a yaw-acceleration check (a). |
| **Aero** | Downforce and drag from CL·A and CD·A with a front/rear balance. Optional ride-height map later. Active aero as a state machine with an actuation delay. | GT builds aero maps from CFD and wind tunnel, as a function of ride height (a). CSP gives AC 2D ride-height maps and force delays (b). |
| **Steering** | Wheel → rack ratio (can vary with speed) → Ackermann → road-wheel angles; rear steer = gain(speed) × front angle with an actuator lag. | VPP and PhysX both expose Ackermann accuracy as a 0..1 blend (a). The 4WS gain curve is car data. |
| **Keyboard and gamepad** | Rate-limited steering (return to centre faster than turn-in), a **dynamic steering limit that targets the front axle's peak slip angle**, a light self-steer (caster) assist with damping, speed-sensitive rate, throttle and brake ramps, and audio and rumble cues tied to slip relative to its peak. | Implemented by AC's Advanced Gamepad Assist (b), BeamNG's understeer and oversteer reduction assistants (b), VPP's Steering Limit aid (a), Forza's "Normal" steering (a: several layered systems), GT7 countersteer assistance (a). |

**What to leave out of v1 (c):** tyre thermal and wear models, pressure effects, 3D carcass flex, aero yaw and roll maps, driveline torsional compliance. Each costs CPU and tuning time, and a road car driven on a road course stays mostly inside its tyre window. Add a 1-node or 2-node thermal model only if a gameplay reason appears.

**Single biggest lesson across all sims (a, b):** matching lap times is the easy part. Polyphony said its lap times matched reality around 2007, and that making the car *feel* right was the hard task (a). Validate numbers first, then tune feel with the few knobs listed in section 3.4.

---

## 2. Per-subsystem detail

### 2.1 Tyres

#### What the studied sims do

**Assetto Corsa (Kunos)**
- Philosophy (a): Stefano Casillo described the goal as physics-based formulas that can be tuned with very few parameters. AC, netKar Pro and Ferrari Virtual Academy all start from a "base" slip curve and adapt it into a "slip profile". AC added carcass and tread dynamics where the older two used a steady-state adaptation. He said they moved away from that particular Pacejka model.
- Rate and solver (b): CSP's documentation says AC runs at 333 Hz and that its solver is ODE (Open Dynamics Engine). CSP computes sidewall deflection directly from forces ("deterministic") rather than simulating it, because 333 Hz is too low to simulate it. That trick matters for us: **when the tick rate is too low for a stiff state, solve it quasi-statically instead of integrating it** (c).
- v1.3 (2015) rework (b, press relaying the notes [excerpt]): speed sensitivity, combined grip, load sensitivity, rolling resistance, and separate surface and core heating.
- `tyres.ini` parameter names (b, from a university team's AC mod with inline comments; I list names and roles only, no values):
  - Geometry and inertia: WIDTH, RADIUS, RIM_RADIUS, ANGULAR_INERTIA (rim + tyre + brake disc).
  - Vertical: RATE (tyre spring), DAMP (tyre damping, commented as roughly 200–1400 N·s/m).
  - Grip: DX_REF and DY_REF (peak μ at the reference load), FZ0 (reference load), LS_EXPX and LS_EXPY (load-sensitivity exponents), FRICTION_LIMIT_ANGLE (very likely the slip angle at peak: inference by a community answer), XMU, CX_MULT, FALLOFF_LEVEL and FALLOFF_SPEED (post-peak drop and how fast it comes), COMBINED_FACTOR, BRAKE_DX_MOD, SPEED_SENSITIVITY, RELAXATION_LENGTH.
  - Camber: CAMBER_GAIN, DCAMBER_0 and DCAMBER_1 (grip multiplier quadratic in camber).
  - Flex and pressure: FLEX, FLEX_GAIN, PRESSURE_STATIC, PRESSURE_IDEAL, plus gains of pressure on spring rate, flex, rolling resistance and footprint.
  - Rolling resistance: ROLLING_RESISTANCE_0 (constant), _1 (velocity squared), _SLIP (slip-dependent).
  - Thermal blocks: surface, patch and core transfer coefficients, FRICTION_K, ROLLING_K, PERFORMANCE_CURVE (temperature → grip), graining and blistering gains.
- The exact formula linking DY_REF, FZ0 and LS_EXPY is not officially documented. The community describes it as μ falling as load rises above FZ0 (b). My reading (c): μ(Fz) ≈ DY_REF · (Fz/FZ0)^(LS_EXPY − 1), so force ∝ Fz^LS_EXPY. Treat this as a hypothesis.
- CSP extensions show what vanilla AC lacks (b): rolling radius is constant in Kunos physics (CSP adds a load-dependent one); load-sensitivity lookup tables are cubic-smoothed; temperature-dependent fall-off; Maxwell hysteresis damping on the sidewall; extra contact rays, doubled at low speed.
- **AC EVO 0.9 (2025)** reworked the racing slicks (b, BoxThisLap relaying test driver Nils Naujoks plus official patch notes): peak grip at a *lower* slip angle, a stronger drop past the limit, lateral and longitudinal forces combined more coherently, and the contact patch's load distribution shifting the grip peak with camber, load, speed and temperature. Observed effect: more understeer if the driver over-steers past the peak, and traction control mattering more. That is a direct demonstration of the **two feel knobs that matter most: peak slip and fall-off.**

**Assetto Corsa Competizione**
- v1.0.7 (2019) (a, relayed by press): a five-point contact patch (two points at the leading edge, one in the middle, two at the trailing edge), 3D flex, tyres that "climb gradually" over kerbs, and a profile that lowers as it flexes, so ride height drops in corners.
- Aris Vasilakos (Kunos head of vehicle R&D at the time) on the reworked model (a, forum repost of his post [excerpt]): 3D flex of footprint and sidewalls with per-axis rates that depend on pressure and temperature. Pressure, heat and wear change the tyre's *behaviour*, not just a grip multiplier. Water is a film with a depth.
- Interview (a, Italian press): grip depends on slip angle, slip ratio, stiffness, damping and lateral and longitudinal flex, all live. Three thermal areas: surface, carcass, inner air. Usable roughly 40–130 °C, best 70–90 °C. Built with Pirelli telemetry.
- v1.8 (2022) (a, press relaying notes): physics rate 333 → 400 Hz; core and surface flash temperature; heat spread across the tread by camber; new tyre flex; a new viscoelastic rubber friction model [excerpt].
- v1.9 (a, Aris on stream, relayed by Traxion): pressure, flex and alignment are linked. Lower pressure = more flex = the car pivots better in slow corners; higher pressure = more support in fast corners. Force feedback reports pressure through steering effort.

**BeamNG.drive**
- The tyre is part of the soft body: a hub, a ring of tread nodes, and radial, tread, periphery and reinforcement beams, plus a pressure model (a). Friction is applied per node.
- Grip parameters (a, official docs): frictionCoef and slidingFrictionCoef (rolling vs sliding multipliers on the ground's friction); noLoadCoef → fullLoadCoef with loadSensitivitySlope (μ falls with load; the load is per node, not per wheel); stribeckVelMult and stribeckExponent (default 1.75) shape the static-to-sliding transition by slip *velocity*; treadCoef (tread pattern against ground roughness); softnessCoef (compound behaviour over time).
- Tyre development blog (a): combined slip "emerges" from directional node friction instead of being mixed from curves. Real tyre data was hard to find, so a Pacejka '96 curve served only as a visual guide. They accept noisy measured curves because the model is physical. They note real rubber friction depends on speed (viscoelastic): higher grip at very low speed, sliding friction falling at high slip velocity. They also note that most simulators ignore this.

**Gran Turismo 7 (Polyphony)**
- Tyre model statements are high level (a): Yamauchi calls tyres the hardest simulation and says the contact patch under heat, wear and surface is the open problem; graining is "something that we just don't have yet" (2026 interview via GTPlanet).
- Update 1.31 (2023, official notes): low-speed and kerb stability improved, tyre heating and wear optimised (a). Update 1.49 (2024): a new suspension physics model and a new tyre calculation model, for more natural weight shift (a, notes quoted by press [excerpt]). Update 1.71 (via GTPlanet): slip behaviour, rolling resistance, heating, wear and grip loss revised (b).

**Forza Motorsport (2023)**
- Tyre contact: 8 points per tyre at 360 Hz, against 1 point at 60 Hz before. Turn 10 marketed it as "48x" (8 × 6) (a, creative director Chris Esaki relayed by GTPlanet and GamingBolt). Grip falls off more smoothly at extreme temperature, making overdriving more predictable (a, relayed). Placement of the 8 points is not public.
- I found no Turn 10 document on how the tyre model is validated against real data. **Unknown.**

**Other useful data points**
- iRacing (a): Dave Kaemmer described curve-fitted tyre models as hard to trust outside the tested range and data-hungry. Their model starts from how the contact patch generates grip and deforms. It needs fewer inputs, measurable without a tyre test machine. Behaviours such as sliding-to-stop time and burnouts came out right without per-behaviour tuning.
- Automobilista 2 (a, Reiza post relayed by bSimRacing): SETA tyre model with a finite-element carcass, a swappable tread and contact-patch model, and a heat-transfer model. Tread friction, lift and drag coefficients were tuned to real-car data.

#### Theory in our own words

- **Slip definitions (b):** slip ratio κ = (ω·R_e − v_x) / |v_x| (0 = free rolling, −1 = locked, positive when driving). Slip angle α = atan(v_y / |v_x|) in the tyre frame. Both divide by |v_x|, so both blow up as speed goes to zero. Explicit sims add a floor to the denominator, sized to the time step (b, Wikipedia). MathWorks floors it at 1 m/s by default, with a smooth blend (a).
- **Simplified Magic Formula (a, MathWorks):** F = Fz · D · sin(C · atan(B·s − E·(B·s − atan(B·s)))). Slope at zero = B·C·D·Fz (the slip stiffness). Commonly copied dry-asphalt constants: B = 10, C = 1.9, D = 1, E = 0.97. Pitfalls (c, my calculation from that formula):
  - Those constants put the peak at s ≈ 0.18 (slip ratio), or about 10° if s is slip angle in radians. That is late for a performance road tyre. Raise B to move the peak earlier.
  - C sets how far the force falls: at very large slip (with E < 1) the force tends to sin(C·π/2) × peak. E close to 1 delays the drop. With the constants above, a locked wheel (κ = 1) still gives about 0.92 × peak.
- **Full Pacejka '94 (b, Edy):** about 14 longitudinal and 18 lateral coefficients. Typical ranges: b0 (shape) 1.4–1.8, b2 (peak μ × 1000) 900–1700, a0 1.2–1.8, a3 (cornering stiffness) 500–2000. Fz in kN. Edy's advice: get the car working with **flat friction first**, then add the curve.
- **Brush / Fiala model (b, arXiv paper):** below the saturation slip, lateral force is a cubic in θ·tanα with θ = Cα / (3μFz). The tyre saturates at α_sl = atan(3μFz / Cα), then F = μFz. Physically grounded, only two parameters per direction (Cα and μ), and combined slip comes out of the theory. A good option if a designer-knob curve feels too arbitrary (c).
- **Load sensitivity (b):** μ falls as load rises. Peak force grows roughly as Fz^0.7–0.9 (Wikipedia flags that range as needing a citation). An RCVD example tyre: peak Fy/Fz 1.10 / 1.08 / 0.97 at 900 / 1350 / 1800 lbf, with peak slip angle rising 5.6° → 6.0° → 6.7°. **This is what makes anti-roll-bar balance work:** more roll stiffness on an axle means more load transfer on that axle, which means less total grip there (c, the standard reasoning; PhysX states the resulting rule of thumb, see 2.2).
- **Friction circle (b, Beckman part 7):** combine braking or driving with cornering by Pythagoras, not by adding. Normalised by load, the limit is about the same for light and heavy cars. A badly balanced car has an egg-shaped budget, not a circle.
- **Combined slip (b, Beckman part 25):** divide κ by κ_peak and α by α_peak, combine the two into one magnitude ρ, compute the total force from the curve at ρ, then split it back by κ/ρ and α/ρ. Built so that pure slip reproduces each original curve. Pacejka's MF uses weighting functions G_xα and G_yκ instead (b, TNO), which are more accurate but need data we don't have.
- **Relaxation length (b):** the distance a tyre rolls before lateral force reaches about 63% of its steady value. It equals cornering stiffness divided by lateral stiffness. Pacejka's rule of thumb: about the wheel radius at nominal load. Measured 0.12–0.45 m, rising with speed and load. Camber thrust has almost none.
- **Low speed (b):** CarSim's documented compromise:
  1. a slip-angle *state* κ_f with dκ/dt = (v_y − κ·|v_x|) / L_y, so tanα = κ;
  2. a lower bound on |v_x| in the denominators.

  Bernard & Clover (SAE 950311) made both slips state variables for low and high speed (b, abstract only). PhysX adds a "sticky tyre" mode that swaps the tyre forces for velocity constraints after the wheel has been slow for a set time (a). Marco Monster used separate low-speed (pure geometry) and high-speed (slip) models, and warned that the blend between them needs care (b).

#### Typical values for a road supercar tyre (to be replaced by car-data numbers where they exist)

| Quantity | Range | Tag |
|---|---|---|
| Peak lateral μ, dry, ultra-high-performance road tyre | ~1.0–1.2 | (c); the RCVD example tyre above is 0.97–1.10 (b) |
| Slip angle at peak | 6–10° for production tyres; performance tyres toward the low end | (b) Wikipedia; (c) for "low end" |
| Slip ratio at peak | ~0.06–0.15 | (b) Marco Monster quotes about 6% for traction; (c) for the range |
| Post-peak lateral fall-off at large slip | 75–90% of peak (road tyres fall less than slicks) | (c); AC EVO slicks fall harder (b) |
| Load-sensitivity exponent (force ∝ Fz^n) | n ≈ 0.7–0.9 | (b), with a citation flag |
| Relaxation length | 0.12–0.45 m | (b) |
| Cornering stiffness per tyre | ~60–110 kN/rad (1,000–2,000 N/deg) | (c): B·C·D·Fz with BCD ≈ 15–25 and Fz ≈ 4–4.5 kN |
| Wheel + tyre + disc spin inertia | ~1.0–1.6 kg·m² per corner | (c), unverified; ask the car-data note |

#### Pitfalls
- Copying generic MF constants (see above) gives a late, soft peak and a car that feels like it is on snow tyres (c).
- Using one ray per wheel makes kerbs and bumps "rail" the car: ACC and Forza both moved to multi-point contact for exactly this reason (a).
- A load-sensitivity exponent of 1 (classic Coulomb friction) removes the anti-roll-bar balance knob entirely (c).
- An instantaneous slip angle with no relaxation produces turn-in that is too sharp and makes lateral force noisy at low speed (b, c).

### 2.2 Suspension

#### What the studied sims do
- **AC** (b): double wishbone and MacPherson strut geometry from hardpoints. Key `suspensions.ini` names:
  - ROD_LENGTH (push-rod length, used to set ride height; positive raises it);
  - BUMPSTOP_UP and BUMPSTOP_DN (metres from design position to each bump stop);
  - PACKER_RANGE (total travel before the packers);
  - BUMP_STOP_RATE (bump-stop spring rate; "keep it pretty high" per a guide);
  - damper bump, rebound, fast bump and fast rebound with thresholds;
  - HUB_MASS, STATIC_CAMBER, TOE_OUT.

  Kunos' own description of AC's damper: 4–5 linear values. ACC replaced them with full bump and rebound curves imported from manufacturers (a). AC's original bump stops often caused sudden load transfer and grip loss; ACC made their stiffness adjustable (a).
- **CSP for AC** (b): `DAMPER_LUTS` (speed in m/s → force in N, separate slow and fast bump and rebound tables), progressive spring fix, motion-ratio tables, bump-stop tables starting at 0|0, stacked bump rubbers, heave springs (packer as third spring, bump stop as bump rubber), ARB stiffness in N/m with motion ratios. COSMIC suspension builds arbitrary linkages from rigid bodies and joints. It warns that AC's relatively low physics rate makes stiff, complex linkages hard for the solver, and tuning ODE's ERP and CFM helps.
- **ACC 1.9** (a): bump-stop compression capped at about 20–30 mm (before that, soft springs riding unlimited bump stops gave a low, low-drag car). Slow-speed damping response changed; fast damping reworked for kerbs and bumps. Aris: bump stops, springs and dampers must be tuned together to control bouncing.
- **GT7** (a): 1.31 adjusted suspension geometry calculations (braking stability, traction) and damping over bumps and kerbs. 1.49 introduced a new suspension model, and the patch caused bouncing and launching on extreme setups that Polyphony said it was investigating (b, press).
- **AMS2** (a): geometry from manufacturer CAD where available; wheel rates, heave frequencies and critical damping ratios computed with an internal calculator; the floor plane comes from the undertray and collision mesh; ride height and aero are tuned together.
- **BeamNG** (a): springs are beams with stiffness and no damping, dampers are beams with damping and no stiffness, arms are very stiff beams with light damping. Example values: spring 40,000, damper 4,500, arm 8,000,000 / 125.
- **PhysX** (a): suspension raycast per wheel. Recommends at least 5 updates per spring period ("alpha > 5"). Damping ratio 0.8–1.2 as a starting point. More rear ARB reduces understeer; more front ARB reduces oversteer. A tyre-load filter cuts load noise at large time steps. **Caution:** PhysX says a family car's springs have a natural frequency "between 5 and 10" oscillations per second. Automotive references put passenger-car ride frequency at 0.5–1.5 Hz (OptimumG). PhysX's number is game-oriented or wrong; do not use it (c).

#### Model in our own words (recommended)
- Wheel rate from ride frequency (b, OptimumG): k_wheel = m_corner · (2π·f)². Spring rate = k_wheel / MR², with MR = wheel travel / spring travel convention as documented. The rear is often 10–20% stiffer for a "flat ride" (b).
- Damper: force = piecewise linear in shaft speed. Slow slope up to a knee (~0.05–0.1 m/s, (c)), then a shallower fast slope. Separate bump and rebound. Rebound is often stiffer than bump; a 3:1 rebound:bump ratio was historically called optimal (b, Woods & Jawad via forum [excerpt]).
- Bump stop: force = lookup table of compression past the gap (progressive), with a finite cap on stiffness (see numerics).
- ARB: force on each side = k_arb · (x_left − x_right), applied equal and opposite (c, standard).
- Camber and toe: static values plus a camber-gain curve versus travel. Feed camber to the tyre only if the tyre has a camber term. AC's grip-vs-camber is a quadratic multiplier, peaking near −3.3° for one GT2 tyre in a community analysis (b).
- Geometry anti-dive and anti-squat: approximate by applying a fraction of the longitudinal tyre force at a virtual pivot instead of at the ground (c). Optional.

#### Typical values for a road supercar
| Quantity | Range | Tag |
|---|---|---|
| Ride frequency | 0.5–1.5 Hz passenger car; 1.5–2.0 Hz sedan race car or moderate-downforce formula car; 3–5+ Hz high-downforce race car | (b) OptimumG |
| SVJ-class road supercar ride frequency | ~1.5–2.2 Hz, rear 10–20% higher | (c) |
| Body damping ratio | 0.2–0.4 comfort; ~0.45 road-holding optimum for a compact car (Milliken via forum); 0.5–0.7 non-aero race cars | (b), all relayed by forums [excerpt]; treat as a range, not a target |
| Bump-stop gap | 10–30 mm of usable rubber travel | (c), informed by ACC's 20–30 mm cap (a) |
| Unsprung mass per corner | 35–55 kg | (c) |

#### Pitfalls
- A car that rides on its bump stops in steady cornering feels "pointy then snappy". ACC removed that exploit on purpose (a).
- If damper force is computed in script and held for a whole 60 Hz frame against a light wheel, the wheel will jitter (c, section 5). Either make the wheel massless or let an engine constraint integrate the spring and damper.

### 2.3 Drivetrain (engine, clutch, gearbox, differentials, AWD)

#### What the studied sims do
- **AC engine** (b): torque lookup table versus rpm (`power.lut`); [ENGINE_DATA] INERTIA, LIMITER, MINIMUM; [COAST_REF] RPM, TORQUE, NON_LINEARITY. The last set defines engine-braking torque at a reference rpm and how it ramps (0 = linear, 1 = fully exponential). Turbo blocks [TURBO_n].
- **AC gearbox** (b): CHANGE_UP_TIME and CHANGE_DN_TIME in ms (a race-car example: 240 and 260 ms), AUTO_CUTOFF_TIME (an ignition cut on upshift), SUPPORTS_SHIFTER, VALID_SHIFT_RPM_WINDOW. [AUTOCLUTCH] USE_ON_CHANGES and FORCED_ON.
- **AC differential** (b): POWER (locking under power), COAST (locking off throttle), PRELOAD (Nm). Community descriptions: power affects corner exit, coast affects corner entry, higher values push toward understeer, preload is the torque difference needed before the diff starts to slip. **AC's AWD/centre-diff key names were not verified.** I could not find them documented, so I do not list them.
- **BeamNG** (a for the structure, b for the parameters): engines, clutches, gearboxes, shafts and differentials are devices in a modular tree defined in JBeam and run in Lua. Differential types: open, lsd (cross torque depends on input torque), viscous (cross torque depends on output speed difference), locked; a diff can toggle between types. Community-documented parameters: lsdPreload in Nm (clutch-type diffs about 50–250, Torsen about 0), lsdLockCoef (on throttle), lsdRevLockCoef (coast, defaults to the lock coefficient), viscousCoef in Nm per rad/s. One modder reports some of these were inactive in their build; another reports lsdRevLockCoef had no effect.
- **PhysX** (a): torque split ratios that sum to 1; a limited-slip "bias" around 1.3 to start, with the target set just under the bias to avoid oscillation; gear switch time spent in neutral (keep it well below the auto-box latency); clutch strength around 10; engine damping 0.25–3 (0 can be unstable); engine inertia about 1 to start; "best possible" clutch solver for 4-wheel cars.
- **AMS2** (a): engine, clutch, gearbox, differential, driveshafts and wheel bearings modelled and tuned to reproduce power at the wheels. A fix gave the diff steady locking torque under braking, trail braking and sustained throttle, especially at high preload.
- **GT** (a): several thousand parameters per car feeding one shared physics model; AWD, four-wheel steering and hybrids handled per car. Yamauchi: drivetrain electronics differ widely between manufacturers.

#### Model in our own words (recommended)
- **Engine:** T_engine(rpm, throttle) = throttle · T_full(rpm) + (1 − throttle) · T_coast(rpm), where T_coast is negative (engine braking). Inertia I_e. Rev limiter as a cut with hysteresis. Idle as a simple governor (c).
- **Friction element** (clutch, LSD pack, centre coupling): it carries any torque up to a capacity T_cap while locked; when slipping, it carries T_cap · sign(Δω) (c, standard). Capacity:
  - clutch: pedal × max;
  - LSD: preload + k_power · max(T_in, 0) on power, preload + k_coast · max(−T_in, 0) on coast (matches AC and BeamNG semantics, (b));
  - viscous: k_visc · |Δω| (b);
  - Haldex-like coupling: a controller output (c).
- **Solving:** at each substep, either (1) test whether each friction element can stay locked (merge the inertias, compute the required torque, compare with capacity), or (2) a penalty T = clamp(k · Δω, ±T_cap) integrated implicitly. Option (1) is exact and cheap for a fixed AWD topology with 3–4 elements (c). Either way, never integrate a stiff penalty explicitly at 60 Hz.
- **Gearbox (ISR):** shift sequence (c):
  1. Cut the engine torque.
  2. Open the clutch.
  3. Hold neutral for t_shift.
  4. Set the new ratio.
  5. Close the clutch over t_engage.

  The slip during step 5 drags the engine inertia to the new speed, which is the single-clutch "head nod". Downshift = blip the throttle toward the target rpm, then engage. Up and down times plus the cut time are the three knobs AC exposes (b). Get the real ISR timings from the car-data note.
- **Driveline efficiency:** constant loss per stage. Marco Monster guessed 70% overall and called it a guess (b). Modern figures are higher; use the car-data note, or calibrate against measured acceleration (c).

#### Pitfalls
- Integrating wheel and engine speeds with a one-step lag couples badly. Marco Monster used previous-step values to break the loop (b); a PhysX forum case found the engine and wheel speeds overshooting each substep until the step was shortened (b).
- A stiff LSD or coupling penalty at a low rate chatters (c). PhysX itself sets the target below the bias to avoid oscillation (a).
- Too long a shift time in an automatic can make it hunt between neutral and first (a, PhysX).

### 2.4 Brakes and electronics

- **AC** (b): brakes.ini [DATA] MAX_TORQUE (Nm), FRONT_SHARE, HANDBRAKE_TORQUE. electronics.ini [ABS] and [TRACTION_CONTROL] with SLIP_RATIO_LIMIT, CURVE, PRESENT, ACTIVE, RATE_HZ (the actuator refresh rate, per the comment), and for TC also MIN_SPEED_KMH. Example values: ABS 0.12 at 250 Hz, TC 0.22 at 100 Hz with a 40 km/h cut-off. These are one modder's values.
- **ACC** (a): TC works in two steps (ignition retard, then ignition cut) for smoother slide onset, and watches yaw acceleration like a gyro, checking whether the driver is controlling the yaw before cutting power (v1.0.7). TC logic also accounts for engine and drivetrain vibration (v0.3).
- **GT7** (a): TCS levels, ABS tuned for full-brake stability, Active Stability Management (more intervention on oversteer), Countersteering Assistance (reduced in 1.31, and default Off in the Expert preset).
- **Model (c):**
  - ABS per wheel: if κ < −κ_abs, release pressure; reapply at the pump rate.
  - TC on driven wheels: if κ > κ_tc, first reduce torque, then cut.
  - ESC: reference yaw rate r_ref = v·δ / (L · (1 + v²/v_ch²)), clamped to |r_ref| ≤ μ·g/v. Brake the outer front on oversteer and the inner rear on understeer, in proportion to the yaw-rate error.
  - Run all three inside the substep loop but update their outputs at their own rate (e.g. 50–250 Hz) so they "pulse" like real systems.

  Typical thresholds: ABS κ ≈ 0.08–0.15, TC κ ≈ 0.08–0.2 (c, informed by the AC example above).
- **Pitfalls (c):** an ABS that acts every substep with no hysteresis buzzes. A TC with no minimum speed traps the car at standstill: one AC modder reported a car that could not move with TC on (b).

### 2.5 Aerodynamics

- **AC** (b): wings as elements with POSITION (from the CG), CHORD and SPAN (area), ANGLE, LUT_AOA_CL and LUT_AOA_CD (coefficient vs angle of attack), LUT_GH_CL and LUT_GH_CD (multiplier vs ground height), CL_GAIN and CD_GAIN, YAW_CL_GAIN, and damage zones. Active elements come from [DYNAMIC_CONTROLLER] blocks with WING, COMBINATOR, INPUT, LUT, FILTER, UP_LIMIT and DOWN_LIMIT (names from the CSP aero page; the LaFerrari uses one, per a modder).
- **CSP** (b): full aero maps. 2D lookup tables of CL·A, CD·A and balance against front and rear ride height; 1D multipliers for yaw, roll, steer and speed; FRONT_FORCE_DELAY, REAR_FORCE_DELAY and DRAG_FORCE_DELAY to lag the forces.
- **GT** (a): aero maps from CFD plus wind tunnel. Example: drag is lowest at minimum ride height, front downforce peaks near 80 mm and drops below that. Update 1.31 made downforce and drag depend on ride height.
- **Model (c):** F_down = ½·ρ·v²·(CL·A), split front and rear by a balance value (optionally a function of pitch). F_drag = ½·ρ·v²·(CD·A), applied at the centre of pressure. Active aero = a state machine (low drag / high downforce / per-side vectoring) driven by speed, throttle, brake and steering, with a first-order actuator lag of about 0.1–0.5 s. The SVJ's ALA logic and coefficients are for the car-data note.
- **Calibration:** CD·A from top speed and the coast-down curve (section 3). CL·A from high-speed skidpad grip or published downforce at speed (car data).
- **Pitfall:** one modder raised CL_GAIN and CD_GAIN to 6.0 and later reverted them as an "aero gain issue". Gains are fine-tuning, not a substitute for correct area and coefficients (b).

### 2.6 Steering, mass and the rest of the chassis

- **Ackermann** (a): VPP places an Ackermann reference point (at the rear axle = true Ackermann; ahead = more; behind = less). PhysX uses an accuracy factor from 0 (none) to 1 (ideal).
- **Steering ratio:** CSP made it a setup item and then dropped support because it broke AI and animations (b). In our port, keep the rack ratio separate from the input filter so the visual steering wheel stays truthful (c).
- **Four-wheel steering (c):** δ_rear = g(v) · δ_front, opposite phase below a crossover speed (tighter turns), same phase above (stability), with a 50–150 ms actuator lag. The g(v) curve is car data.
- **Mass and inertia (c):** yaw inertia matters as much as tyre grip for turn-in. Many games use the bounding-box inertia of the collision mesh, which is wrong for a mid-engined car. Set the inertia tensor explicitly from mass distribution: a mid-engine car has a low yaw inertia relative to m·a·b, which makes it quick to rotate. CG height: VPP suggests estimating it from the balance angle on two wheels when it is not published (a).
- **Rolling resistance:** a constant term plus a speed term (AC ROLLING_RESISTANCE_0 / _1 / _SLIP (b); VPP constant, linear or pressure-based (a)). A raycast car does not get engine contact friction, so it needs explicit rolling resistance (b, Roblox DevForum).

### 2.7 BeamNG: what makes it credible and what transfers to a rigid-body game

What makes it credible (a/b): 2000 Hz physics (a); mass lives in the nodes, so inertia, unsprung mass and flex come from the structure, not from tuned numbers; the tyre is a pressurised node-and-beam body, so load response, relaxation and combined slip emerge; drivetrain devices are physical inertias with friction.

What does **not** transfer: the node-beam solver itself. BeamNG's own docs say stiff beams on light nodes vibrate or explode, and fix it with heavier nodes or softer beams (a). That only works at 2000 Hz.

What **does** transfer (c, each grounded in the doc cited in 2.1 and 2.3):
1. Per-contact load sensitivity with a no-load μ above 1 and a full-load μ below it, plus a slope (simple, designer-friendly).
2. Static-to-sliding friction transition by slip *velocity* (Stribeck), which is well defined at zero speed. VPP's tyre curve also uses slip velocity in m/s: adherent μ 0.95 below 0.5 m/s, peak 1.1 at 1.5 m/s, limit 0.8 (a). **Use a slip-velocity formulation at low speed and slip ratio and angle at speed.**
3. The powertrain as a device tree in script, which ports directly to Luau.
4. Wheels and hubs as real masses with explicit inertia, even when the contact is a raycast.
5. The habit of measuring the virtual tyre on a virtual test rig and comparing it with a reference curve.

---

## 3. Tuning and balancing methodology

### 3.1 What the developers say they do
- **GT / Polyphony** (a): a cycle of simulation, real-car data collection and refinement, with driver feedback defining how each car behaves. Matching real lap times was achieved years ago; feel was the harder job. About eight months per car (graphics plus physics). Yamauchi test-drives every car at the end as a final check. When a car's data and specifications go into the model, it has to behave like the real car.
- **AMS2 / Reiza** (a): start each new car from a baseline built on a similar car; collect data from manufacturers or other sources; test on several tracks; check with spectral analysis of tread movement and traction-circle analysis; tune force feedback per car.
- **Kunos** (a): ACC damper curves imported from manufacturers; tyre work with Pirelli telemetry; fuel use checked against a team's real telemetry from three tracks for the Porsche Cup car (press [excerpt]). Aris: they kept unrealistic setups (extreme negative toe) possible but made them physically penalised, because blocking them would hide the physics engine's limits (a).
- **iRacing** (a): prefer inputs you can measure, and let behaviour emerge. Distrust a model that only matches the data it was fitted to.
- **VPP** (a): gather mass and CG, driveline, wheels and suspension, then use measured behaviour as tyre targets: peak μ from best braking or acceleration without lock; sliding μ from locked-wheel braking distance; slip points from the maximum steer angle without sliding at a given speed; drag from top speed; downforce and lateral μ from maximum speed on a known-radius curve and maximum lateral g. Start from default tyre values and adjust.

### 3.2 Recommended workflow: data first, then feel (c, synthesising the above)
1. **Static and kinematic:** mass, weight split, CG height, inertia, wheelbase, track, ride heights, steering lock, turning circle, gear ratios. Test: car at rest on the flat with exact corner loads, and a turning circle at walking pace.
2. **Straight line:** engine curve, driveline losses, drag, rolling resistance, gear shifts, launch. Targets: 0–100, 0–200, 100–0, top speed, and the gear/rpm plot.
3. **Steady-state lateral:** tyre peak μ, load sensitivity, roll-stiffness split, aero balance. Targets: skidpad max g, understeer gradient, roll gradient.
4. **Transient:** relaxation length, damping, yaw inertia, steering ratio. Targets: step-steer response times and overshoot, lane-change speed.
5. **Electronics:** ABS, TC, ESC thresholds against the braking and launch targets.
6. **Feel pass on keyboard and gamepad** (section 4), with the physics frozen. Change the input layer, not the car, unless a measured target is violated.
7. **Regression:** each target becomes an automated test that runs on every physics change (fits this repo's practice: a test must be able to fail).

### 3.3 Measurable targets and how to measure them on a test bench

The bench is a flat, grippy test place with a scripted "robot driver" giving open-loop inputs and a fixed-rate logger (≥60 Hz) writing CSV. Every metric below is computed by a script, never read off a HUD by eye (c). Real values for the SVJ come from the car-data note. "Typical" columns are for sanity checks only.

| Target | Bench procedure | Calibrates | Typical road-supercar range (c unless tagged) |
|---|---|---|---|
| 0–100 km/h, 0–200 km/h, 0–300 km/h | Launch control or full-throttle launch, log time vs speed; run both directions, average | Engine curve, driveline loss, launch traction, shift time | Car data |
| In-gear 80–120 km/h | Fixed gear, full throttle | Engine curve without shift effects | Car data |
| Gear/rpm plot | Full-throttle run, log rpm and speed per gear; check speed at limiter = r·ω_limit / (gear · final drive) | Ratios, rolling radius, limiter | Must match within 1% (c) |
| Top speed | Long straight to steady state; also drag-limited vs rev-limited check | CD·A, power at top-speed rpm | Car data |
| Coast-down curve | From ~120 km/h to 15 km/h in neutral; fit F = F0 + F1·v + F2·v² | Rolling resistance (F0, F1), drag (F2) | SAE J2263 range is about 115 → 15 km/h, both directions (b) |
| Braking 100–0 and 200–0 | Full brake, ABS on and off; log distance and peak decel | Brake torque, bias, tyre peak and sliding μ, ABS | Car data; ABS-on ≈ 1.1–1.3 g peak for a road supercar (c) |
| Constant-radius skidpad | Fixed radius circle (e.g. 40 m or 100 m), speed ramp; a = v²/r at the limit; both directions averaged | Peak lateral grip, balance | ≈1.0–1.15 g without aero help (c). Method: (b) Wikipedia; ISO 4138 (b) |
| Understeer gradient K | Same ramp; plot road-wheel steer vs a_y; slope of δ − L/R against a_y (deg/g) | Roll-stiffness split, load sensitivity, tyre peak slips | Small positive for a road car (c). Definition: (b) |
| Characteristic speed | v_ch² = 57.3·L·g / K (K in deg/g) | Same as K | (b), course formula |
| Roll gradient | Roll angle vs a_y on the skidpad (deg/g) | Springs, ARBs, roll centres | ~1–2 deg/g for a stiff road supercar (c) |
| Step steer | At 80 and 120 km/h, a fast steer step to a level that gives ~0.4 g; measure yaw-rate response time (to 90%), peak response time, overshoot, yaw gain | Relaxation length, damping, yaw inertia, steering ratio | ISO 7401 defines these metrics (b) |
| Double lane change | Cone layout per ISO 3888-1; highest clean entry speed with a scripted path-following driver | Combined transient behaviour, ESC | (b) |
| Slalom | Fixed cone spacing, max average speed | Transient + yaw inertia | (c) |
| Braking in a turn | Brake at fixed decel from a steady corner; measure yaw-rate change | Brake bias, coast diff, ABS | (c) |
| Lap time on a known track | Only after everything above; compare with the real car on the same track | Global sanity | GT: easy to hit (a). Don't tune to lap time first (c) |
| Low-speed and rest checks | Park on a 10–20% slope with the handbrake; idle in gear against the brakes; crawl at 1 km/h with full lock | Low-speed tyre blend, sticky mode, clutch | No creep, no jitter, no sideways drift (c) |
| Numerical health | Log the peak-to-peak oscillation of wheel speed and suspension travel at rest and at 250 km/h | Substep count, low-speed fixes | Below sensor noise (c) |

### 3.4 The knobs that matter most for "feel", ranked (c, with the sim evidence that motivates each)
1. **Tyre slip at peak and the fall-off after it.** AC EVO 0.9 changed exactly these, and drivers immediately felt more understeer if they over-steered (b). Edy's gripRange and drift parameters, AC's FALLOFF_LEVEL and FALLOFF_SPEED, and the drift-tyre community all treat this as the slide-character knob (b).
2. **Load sensitivity × roll-stiffness split (ARBs).** This sets steady-state balance (b, c).
3. **Relaxation length and yaw inertia.** These set turn-in latency and how "alive" the car feels (b, c).
4. **Damping**, bump vs rebound and slow vs fast: body control over kerbs and through direction changes (a: ACC 1.9).
5. **Steering ratio and its speed dependence**, plus the input filter (section 4).
6. **Diff power, coast and preload:** entry stability and exit rotation (b).
7. **Aero balance at speed** (c).
8. **Electronics thresholds:** how much the car lets the player slide before it intervenes (a: GT7 retuned its assist levels in 1.31).

---

## 4. Keyboard and gamepad input practices in sims (no force feedback)

The core problem: a keyboard is binary (b, BeamNG keyboard guide), and a stick has far less travel than a wheel and no force feedback (c), so the player cannot feel the front tyres saturate. Every sim surveyed adds a layer between the device and the steering rack.

**Practices, with who documents them**

1. **Steering rate limiting (slew rate).**
   - ACC "steer speed" and "steer filter" (b, community guides).
   - AC Advanced Gamepad Assist "Steering rate": recommends about 30–60%; keyboards need a lower rate than sticks; the setting also acts as smoothing (b).
   - BeamNG's keyboard and pad filters also slow the steering rate (b, forum).
   - (c) Use separate turn-in and return-to-centre rates; return is faster.
2. **Speed sensitivity.**
   - ACC "speed sensitivity" 0–100%: high values make steering less sensitive at speed (b).
   - BeamNG's older "limit steering at speed" filter reduced and slowed steering whatever the slide angle, which made catching slides at speed hard. This is the classic failure of a plain speed-based lock (b).
   - AC assist "steering rate at speed": negative values slow steering at speed (b).
3. **Dynamic steering limit that targets the front tyres' peak slip.** This is the key technique.
   - VPP documents a "Steering Limit" aid that keeps sideways slip near the peak (a).
   - BeamNG's "understeer reduction assistant" (0.26+) is described the same way by the author of a related mod (b).
   - AC Advanced Gamepad Assist: "Target slip angle" as % of the front tyres' peak (most cars feel best at 90–100%), plus a "Dynamic steering limit" that reduces steering when the car is oversteering and the player turns in (b).
   - Forza's "Normal" steering is officially several systems layered together; "Simulation" turns them off (a, support page [excerpt]). Forum posts relay that some layers change inputs and others change dynamics such as yaw inertia (b [excerpt]).
   - **How to compute it (c, bicycle model):** front slip angle α_f ≈ δ − (β + a·r/v), where β = body sideslip, r = yaw rate, a = CG-to-front-axle distance. So the steering that puts the front at a target slip is δ_target = α_target + β + a·r/v. Clamp the player's request to ±δ_target. The β and r terms automatically open up countersteer during a slide. That avoids BeamNG's old problem.
4. **Self-steer (caster) assist with damping.**
   - AC assist: "Response" (strength of self-centring against oversteer, strongest when the input is released), "Max angle" (cap, the author uses about 90°), "Damping" (stops the self-steer overshooting; rule of thumb ≈ Response) (b).
   - "Countersteer response" sets how hard the player can countersteer; keep it under 50% or overcorrections spin the car the other way (b).
   - BeamNG "oversteer reduction assistant" (b). GT7 "Countersteering assistance", which Polyphony *reduced* in 1.31 and set to Off in the Expert preset (a). This is evidence that too much self-steer reads as the game driving for you.
5. **Stick shaping.** Gamma about 140% (less sensitive near centre) and the smallest deadzone that does not drift, as AC assist defaults (b). ACC community presets use gamma 3–3.5 on a different scale (b). GT7 1.31 retuned its stick and directional-button steering algorithm (a, no details given).
6. **Throttle and brake for keyboards (c).** Attack and release ramps (e.g. 0.15–0.3 s to full throttle, faster release), and let TC and ABS do the pedal modulation a binary key cannot. VPP exposes pedal ranges and nonlinear bias for devices (a).
7. **Replace force feedback with other channels.**
   - ACC reworked its skid and scrub sound logic and tyre-sound spatialisation (a, v0.3), and exposes tyre scrub to telemetry tools (b, forum).
   - AC assist offers controller rumble (b).
   - (c) Drive tyre-squeal volume and pitch from normalised slip (slip / slip at peak), starting at ~0.7 of peak so players hear the limit before they pass it; add rumble on the front axle for understeer and on the rear for oversteer.
8. **Disable the input layers for wheel users.** BeamNG advises turning the assistants off with a force-feedback wheel because the wheel misbehaves (b). Forza reportedly disables its input layers whenever a wheel is used (b [excerpt]).
9. **Expose presets, not 12 sliders.** GT7 ships assist presets; its 1.31 notes name Intermediate and Expert (a). ACC and AC setups vary widely per player (b). (c) Ship 2–3 presets and keep sliders in an advanced panel.

**Starting values to try (c, derived from the AC assist defaults and community presets above):** target slip 95% of peak, steering rate 45% (keyboard 30%), return rate 2× turn-in, self-steer response 30% with equal damping, max self-steer 30–90°, countersteer response 30%, stick gamma 1.4, deadzone 8–12%.

---

## 5. Numerical stability notes

### 5.1 What rates the sims use

| Sim | Physics or tyre rate | Tag |
|---|---|---|
| BeamNG.drive | 2000 Hz | (a) |
| Live for Speed | 100 Hz in the long-standing public build; 1000 Hz in the new multithreaded engine | (a) relayed by press; one forum post claims 2000 Hz adaptive for vehicle dynamics (unverified) |
| Assetto Corsa | 333 Hz, ODE solver | (b) CSP docs |
| ACC | 333 Hz → 400 Hz in v1.8 | (a) relayed by press |
| Forza Motorsport (2023) | Tyre model at 360 Hz (was 60 Hz) | (a) relayed |
| rFactor 2 | 400 Hz force-feedback and steering sample rate (often assumed to be the physics rate) | (b) forum; not confirmed as the physics rate |
| iRacing | Conflicting: articles say physics at 60 Hz with 360 Hz FFB, a forum says 360 Hz physics | **Unknown**; not used here |
| Unity + VPP | 50 Hz rigid body + 2–8 internal substeps (max ~20; AWD at least 2) | (a) |
| PhysX vehicles | Substep groups, nested, so the stiffest parts get the smallest steps | (a) |
| Roblox | 240 Hz default; "Adaptive" mode puts assemblies on 60/120/240 Hz islands; fast and complex assemblies stay at 240 Hz | (a); the localised page suggests fixed 240 Hz for racing games |

**Pattern:** the sims that run slowly (Unity + VPP, PhysX at game rates) all substep the vehicle internally. None of them integrates tyres at 60 Hz without help.

### 5.2 Where the stiffness is: back-of-envelope (c, all inputs shown)

Inputs: wheel spin inertia I = 1.2 kg·m², rolling radius R = 0.35 m, rear wheel load Fz = 4,500 N, slip stiffness C_κ = B·C·D·Fz ≈ 19 · 4,500 ≈ 85,500 N per unit slip (MathWorks dry constants), front-axle cornering stiffness ≈ 150,000 N/rad, front-axle mass ≈ 750 kg.

1. **Wheel spin is the stiffest state.** In the linear tyre region, the slip decays with time constant τ = I·v / (R²·C_κ) ≈ 1.15e-4 · v seconds (v in m/s). Explicit Euler is stable only if dt < 2τ, so the car is stable only above v > dt / 2.3e-4:
   - at 60 Hz: above **72 m/s (260 km/h)**;
   - at 240 Hz: above **18 m/s (65 km/h)**;
   - at 1000 Hz: above **4.3 m/s**.

   The wheel behaves like a 10 kg mass (I/R² ≈ 9.8 kg) pressed against a very stiff tyre. This is why every sim has a low-speed fix, and why the ABCM paper calls the wheel system stiffer as the car slows or nears lock-up (b).
2. **Chassis lateral is much softer.** Lateral velocity relaxes with τ_y = m_axle·v / C_axle ≈ 0.005 · v s. Explicit is unstable only below **1.7 m/s at 60 Hz** and **0.4 m/s at 240 Hz**. This is the parking-lot jitter: real, but confined to near-standstill.
3. **Relaxation-length tyre at standstill.** It becomes a lateral spring k = C_α/σ ≈ 75,000 / 0.3 ≈ 250 kN/m per tyre. On the axle mass that is about 4 Hz, which is stable for semi-implicit Euler at any rate above ~26 Hz (ω·dt < 2, (b)). It needs damping, or it rings at 4 Hz. CSP added sidewall hysteresis damping for this kind of reason (b).
4. **Suspension.** Body modes are 1.5–2.5 Hz (trivial). The wheel-hop mode with 50 kg unsprung, a 300 kN/m tyre and a 63 kN/m wheel rate is ≈ 14 Hz. PhysX's "5 updates per period" rule then needs ≥ 70 Hz, so 240 Hz is fine and 60 Hz with a held force is not. A massless or raycast wheel removes this mode entirely (at the cost of wheel-hop realism).
5. **Bump stops.** A 5 MN/m bump stop on 50 kg gives ω ≈ 316 rad/s and needs dt < 6 ms (symplectic): borderline at 240 Hz. Cap the bump-stop stiffness in the lookup table, or let an engine constraint handle it.

### 5.3 Standard tricks (with who uses them)

1. **Internal substeps for the fast states** (wheel spin, slip states, drivetrain friction, ABS/TC), e.g. 8–16 per 60 Hz frame. VPP (a), PhysX substep groups (a). Cost: 4 wheels × a few dozen operations × 16 substeps is small in Luau (c, to be profiled).
2. **Implicit (backward-Euler) wheel spin in the linear region** (c, standard): with F_x ≈ C_κ·(ω·R − v)/v_d,
   ω_{n+1} = [ω_n + (dt/I)·(T_net + R·C_κ·v/v_d)] / [1 + dt·R²·C_κ/(I·v_d)].
   Unconditionally stable for the linear part; the saturated part is force-bounded. The arXiv paper shows that switching the lateral states to backward Euler removes the low-speed singularity in a single-track model (b).
3. **Exact exponential update for relaxation states** (c): for slip state z with dz/dt = v_y − |v_x|·z/σ,
   z_{n+1} = z_n·e^(−|v_x|·dt/σ) + (v_y·σ/|v_x|)·(1 − e^(−|v_x|·dt/σ)),
   with the limit z_n + v_y·dt as v_x → 0. Then clamp z so the force never exceeds μ·Fz.
4. **Velocity floors in slip denominators**, sized to the step: MathWorks 1 m/s default with a smooth blend (a); PhysX min slip denominators, larger for larger steps (a); Wikipedia: an epsilon tied to step size (b).
5. **Low-speed static friction / sticky mode.** PhysX replaces tyre forces with velocity constraints after a time below a threshold speed (a). (c) In Roblox, a stiff, damped, force-clamped anchor per contact patch does the same job.
6. **Never let a friction torque reverse a velocity inside one step.** Brakes and clutches: clamp the torque so ω does not cross zero (or cross the other shaft's speed) in one step; Marco Monster cuts the brake force at zero speed so the car does not reverse (b).
7. **Load filtering.** PhysX filters tyre load to stop load noise turning into force noise at large steps (a). (c) A 10–20 ms low-pass on Fz is enough.
8. **Quasi-static solves for states that are too stiff to integrate** (CSP's deterministic sidewall deflection at 333 Hz) (b).
9. **Raise inertia only as a last resort.** PhysX notes a larger wheel inertia stabilises low-speed wheel rotation (a), but it changes the car's acceleration and lock-up feel (c).
10. **Visual blend at low speed.** PhysX blends the displayed wheel rotation toward the rolling speed below a threshold, purely for looks (a).

### 5.4 Roblox implications (c; the engine note must confirm the API facts)

- If our script computes tyre forces once per frame and applies them through a force object, the 240 Hz solver sees a force held constant for 4 worldsteps. For the chassis this is an explicit 60 Hz update: acceptable above walking pace per 5.2-2, but it needs the low-speed sticky mode.
- **Wheel spin must not be integrated by the Roblox solver against a scripted tyre force.** Keep ω as script state, integrated in our substep loop (or implicitly), and only *render* the wheel.
- Put suspension springs and dampers either in engine constraints (integrated at 240 Hz) with a massless or light wheel, or compute them in script on a massless wheel. Do not hang a 50 kg wheel on a scripted spring.
- Set Workspace physics to fixed 240 Hz rather than Adaptive for the vehicle (the Roblox doc suggests this for racing games; the engine note should verify it on our place).
- The alternative used by many Roblox chassis (physical cylinder wheels with hinge motors and engine contact friction) gives Coulomb friction with no slip curve. It cannot produce the peak/fall-off behaviour that section 3.4 ranks as the top feel knob (c).

---

## 6. Sources

All accessed 2026-10-27. **[excerpt]** = seen only in a search-result summary (page blocked or not fetched); treat as weaker.

**Assetto Corsa / CSP**
- Casillo on the AC tyre model (2012 article + 2013 comment): https://ravsim.com/2012/05/09/assetto-corsa/
- CSP tyre physics wiki (333 Hz, deterministic sidewall, FALLOFF curves, rays): https://github-wiki-see.page/m/ac-custom-shaders-patch/acc-extension-config/wiki/Cars-%E2%80%93-Tyre-Physics
- CSP COSMIC suspension (ODE solver, low rate, joints, coilovers): https://cup.acstuff.club/docs/csp/cars/cosmic-suspension
- CSP suspension extensions (damper LUTs, bump stops, ARBs): https://cup.acstuff.club/docs/csp/cars/suspension
- CSP aerodynamics (aero maps, dynamic controllers, force delays): https://cup.acstuff.club/docs/csp/cars/aerodynamics
- CSP enabling extended physics: https://cup.acstuff.club/docs/csp/cars/enabling-extended-physics
- University of Melbourne team's AC mod, tyres.ini parameter names and comments: https://gitlab.eng.unimelb.edu.au/fwongkwok/mur-assettocorsa/-/commit/07ff084ffe1200666d41062774d16e39b08243f7.diff
- Same repo, aero.ini parameter names: https://gitlab.eng.unimelb.edu.au/fwongkwok/mur-assettocorsa/-/commit/ec0e3777416a3a0504b35bc2b03c17d2b19d7fc3.diff
- Camber vs grip analysis (community): https://github.com/neilser/camber-extravaganza
- Gearbox keys (CHANGE_UP_TIME etc.) [excerpt]: https://www.gtplanet.net/forum/threads/assetto-corsa-pc-mods-general-discussion.307899/post-11681390
- Autoclutch keys [excerpt]: https://steamcommunity.com/app/244210/discussions/0/1319961868330278539
- Electronics.ini ABS/TC keys [excerpt]: https://www.gtplanet.net/forum/threads/assetto-corsa-pc-mods-general-discussion.307899/post-14052117
- Engine COAST_REF keys [excerpt]: https://pastebin.com/innEQfwb
- brakes.ini keys [excerpt]: https://www.gtplanet.net/forum/threads/assetto-corsa-pc-mods-general-discussion.307899/post-13100034
- Suspension keys (ROD_LENGTH, BUMPSTOP, PACKER_RANGE) [excerpt]: https://www.overtake.gg/threads/suspension-travel-basic-position.210503/ and https://get-good.net/index.php/Pikes_Peak:_Race_to_the_Clouds_2022/Car_Guide
- Aero LUT format [excerpt]: https://www.gtplanet.net/forum/threads/assetto-corsa-pc-mods-general-discussion.307899/post-13369480
- Active wing via DYNAMIC_CONTROLLER [excerpt]: https://www.overtake.gg/threads/how-to-create-a-wing-animation-in-assetto-corsa.237307/
- Drift tyre generator on FALLOFF_LEVEL [excerpt]: https://overtake.gg/downloads/drift-tire-generator-for-assetto-corsa-beta.73319/update/129742
- Differential power/coast/preload descriptions [excerpt]: https://www.overtake.gg/threads/setup-differential.98455/
- AC v1.3 tyre model rework [excerpt]: https://isrtv.com/assetto-corsa-dream-pack-2-and-update-1-3-out-now/
- AC EVO 0.9 tyre model: https://boxthislap.org/assetto-corsa-evo-0-9-tyre-model/
- AC Advanced Gamepad Assist (README + config guide): https://github.com/adam10603/AC-Advanced-Gamepad-Assist and https://github.com/adam10603/AC-Advanced-Gamepad-Assist/blob/main/ConfigGuide.md

**Assetto Corsa Competizione**
- v1.0.7 five-point tyre, two-stage TC, yaw logic: https://www.onlineracedriver.com/2019/08/12/assetto-corsa-competizione-update-v-1-0-7-released/
- v0.3 notes (skid/scrub sound logic, TC vibration): https://assettocorsa.gg/assetto-corsa-competizione-0-3-early-access-release-and-patch-notes/
- Aris on suspension (damper curves vs AC's linear values, bump stops): https://www.automoto.it/news/assetto-corsa-competizione-parliamo-di-sospensioni.html
- Aris on tyre physics (flex, three thermal areas, Pirelli telemetry): https://www.automoto.it/news/assetto-corsa-competizione-novita-sulla-fisica-delle-gomme.html
- v1.8, 333 → 400 Hz and tyre overhaul: https://gtplanet.net/acc-console-update-18-20220916
- v1.8 viscoelastic friction model [excerpt]: https://www.overtake.gg/news/assetto-corsa-competizione-v1-8-update.308/?full=1
- v1.9 suspension and FFB (Aris): https://traxion.gg/assetto-corsa-competizione-version-1-9-receives-suspension-and-force-feedback-changes/
- v1.9 tyre revision (Aris): https://traxion.gg/revised-tyre-model-set-for-assetto-corsa-competizione-version-1-9/
- Aris post on 3D flex [excerpt]: https://forum.adrenaline.com.br/threads/assetto-corsa-competizione.628658/page-10
- ACC controller settings explained [excerpt]: https://coachdaveacademy.com/tutorials/ultimate-assetto-corsa-competizione-controller-settings

**BeamNG.drive**
- Physics overview: https://beamng.com/game/about/physics
- Architecture (2000 Hz): https://documentation.beamng.com/beamng_tech/architecture/
- JBeam intro: https://documentation.beamng.com/modding/vehicle/intro_jbeam/
- Pressure wheels (friction, load sensitivity, Stribeck): https://documentation.beamng.com/modding/vehicle/sections/wheels/
- Tyre development blog part 2: https://beamng.com/game/news/blog/a-look-at-tire-development-in-beamng-part-2
- Differential types [excerpt]: https://wiki.beamng.com/Differential
- Powertrain device tree [excerpt]: https://wiki.beamng.com/Powertrain
- LSD/viscous parameter ranges (community) [excerpt]: https://discourse.automationgame.com/t/undriveable-car-at-high-speed-on-beamng/25911?page=2
- Assistants (understeer/oversteer reduction) [excerpt]: https://beamng.com/posts/1543337
- Advanced Steering mod: https://www.beamng.com/threads/arcade-steering-mod.85494
- Keyboard filter guide [excerpt]: https://www.dedoimedo.com/games/beamng-keyboard-mouse-driving.html

**Gran Turismo 7**
- Update 1.31 physics and assist notes (official): https://www.gran-turismo.com/us/gt7/news/00_1462138.html
- 1.31 coverage: https://www.gtplanet.net/?p=124442
- Yamauchi lecture (lap times vs feel, aero maps, workflow): https://gtplanet.net/dr-kazunori-yamauchi-gives-lecture-gran-turismos-driving-physics-production
- Yamauchi 2026 on tyres and validation: https://www.gtplanet.net/kazunori-yamauchi-says-tire-physics-remain-gran-turismos-biggest-challenge-20260822/
- Update 1.49 new suspension and tyre models [excerpt]: https://www.pushsquare.com/news/2024/07/the-huge-gran-turismo-7-1-49-update-drops-on-ps5-ps4-today

**Forza Motorsport**
- 8 contact points, 360 Hz (Esaki): https://www.gtplanet.net/forza-motorsport-new-tire-model-20210528/
- "48x" comparison: https://gamingbolt.com/forza-motorsports-48x-improved-tire-physics-showcased-in-new-comparison-clip
- Normal vs Simulation steering (official support page) [excerpt]: https://support.forza.net/hc/en-us/articles/360012736414-FM7-Wheel-Setup-and-Tuning

**Other sims**
- iRacing new tyre model (Kaemmer): https://www.iracing.com/new-tire-model-debuts-on-new-chevrolet-impala-b/
- AMS2 v1.5 physics update (Reiza): https://www.bsimracing.com/automobilista-2-v1-5-physics-development-update-part-2/
- LFS 100 Hz → 1000 Hz: https://www.bsimracing.com/live-for-speed-20th-anniversary-progress-report/
- rF2 / LFS rate claims (forum) [excerpt]: https://www.overtake.gg/threads/what-rate-do-physics-run-at-1000hz-500.159380/

**Game-physics references**
- Marco Monster, Car Physics for Games (mirror): https://asawicki.info/Mirror/Car%20Physics%20for%20Games/Car%20Physics%20for%20Games.html
- Beckman, Physics of Racing part 7 (traction budget): https://cygnus-supra.duckdns.org/Supra/Library/PhysicsOfRacing/physics_of_racing_07.html
- Beckman part 24 (combination slip): https://cygnus-supra.duckdns.org/Supra/Library/PhysicsOfRacing/physics_of_racing_24.html
- Beckman part 25 (combination grip): https://cygnus-supra.duckdns.org/Supra/Library/PhysicsOfRacing/physics_of_racing_25.html
- Edy, Pacejka '94 parameters explained: https://www.edy.es/dev/docs/pacejka-94-parameters-explained-a-comprehensive-guide/
- Edy's old Vehicle Physics wiki (grip, gripRange, drift) [excerpt]: https://vehiclephysics.repositoryhosting.com/trac/vehiclephysics_edys-vehicle-physics/wiki/CarControl?format=txt
- Vehicle Physics Pro, tyres: https://vehiclephysics.com/blocks/tires/
- VPP, steering: https://vehiclephysics.com/blocks/steering/
- VPP, substeps and timestep: https://vehiclephysics.com/advanced/misc-topics-explained/
- VPP, configuring realistic vehicles: https://vehiclephysics.com/advanced/configuring-realistic-vehicles/
- VPP, vehicle input: https://vehiclephysics.com/components/vehicle-input/
- NVIDIA PhysX 5.4.1 vehicles guide: https://nvidia-omniverse.github.io/PhysX/physx/5.4.1/docs/Vehicles.html
- Unity WheelFrictionCurve [excerpt]: https://docs.unity.cn/2020.1/Documentation/ScriptReference/WheelFrictionCurve.html
- Jolt friction curve defaults via jME forum [excerpt]: https://hub.jmonkeyengine.org/t/jolt-vehicle-tuning-guide/49569
- Roblox raycast car rolling resistance [excerpt]: https://devforum.roblox.com/t/raycast-vehicle-friction/1239471

**Vehicle-dynamics references**
- MathWorks Magic Formula block (equation, constants, low-speed floor): https://www.mathworks.com/help/sdl/ref/tireroadinteractionmagicformula.html
- Slip (vehicle dynamics): https://en.wikipedia.org/wiki/Slip_(vehicle_dynamics)
- Tire load sensitivity (incl. RCVD table): https://en.wikipedia.org/wiki/Tire_load_sensitivity
- Relaxation length: https://en.wikipedia.org/wiki/Relaxation_length
- Understeer and oversteer (gradient definition, ISO 4138 methods): https://en.wikipedia.org/wiki/Understeer_and_oversteer
- Skidpad: https://en.wikipedia.org/wiki/Skidpad
- Semi-implicit Euler: https://en.wikipedia.org/wiki/Semi-implicit_Euler_method
- Low-speed singularity and CarSim's compromise (Zhan et al., 2024): https://arxiv.org/pdf/2411.17334
- Brush/Fiala formula (Ribeiro et al.) [excerpt]: https://arxiv.org/pdf/1908.00452
- Bernard & Clover, SAE 950311 (abstract) [excerpt]: https://saemobilus.sae.org/papers/tire-modeling-low-speed-high-speed-calculations-950311
- TNO, combined-slip weighting functions [excerpt]: https://resolver.tno.nl/uuid:59cde3f4-793f-49b2-8bc7-121f3404aeb7
- Wheel dynamics stiffness at low speed (ABCM 2007) [excerpt]: https://www.abcm.org.br/anais/diname/2007/PDF/DIN07-0149.pdf
- OptimumG Tech Tip, Springs & Dampers part 1 (copy hosted on lfs.net): https://lfs.net/attachment/32094
- Damping ratio ranges (forum relaying Gillespie / Milliken) [excerpt]: https://www.eng-tips.com/viewthread.cfm?qid=366598
- ISO 4138:2021 catalogue [excerpt]: https://iteh.es/catalog/standards/iso/d98b7944-45f2-477d-80f3-cba545998a68/iso-4138-2021
- ISO 7401:2011 catalogue [excerpt]: https://iteh.es/catalog/standards/iso/a1f9fdfd-8c82-4209-8d6a-f5dc0717bf00/iso-7401-2011
- ISO 3888-1:2018 preview [excerpt]: https://webstore.ansi.org/preview-pages/ISO/preview_ISO+3888-1-2018.pdf
- Steady-state steer formula (Linköping TSFS02 lesson 7) [excerpt]: https://www.fs.isy.liu.se/Edu/Courses/TSFS02/Lektioner/TSFS02-Lesson7.pdf
- SAE J2263 coast-down scope [excerpt]: https://online.standard.no/en/sae-j2263-3

**Roblox**
- Adaptive timestepping (240 Hz default, 60/120/240 islands): https://create.roblox.com/docs/physics/adaptive-timestepping

**Not found or not verifiable (flagged so nobody cites them as fact):**
- Official Kunos documentation of the tyres.ini formulas.
- AC's AWD/centre-diff key names.
- Turn 10's tyre validation process.
- iRacing's true physics tick rate.
- The racer.nl documentation.
- Toyful Games' raycast write-up.
