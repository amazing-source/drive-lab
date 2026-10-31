# 14 · Game-friendly handling: how racing games help, what Drive Lab did, and the slide assist

Systems agent, issue #158, 2026-10-31. The web research was done by the researcher agent the same
day (web search and fetch only; no game was run). Measurements are offline on `tools/DriveSim`.

## The request, restated

The cars stay realistic but become relatively easy to drive on a keyboard and a gamepad, as racing
games make theirs. One game-feel level dials between the car as it is and a more forgiving one.
The owner has never played racing games, so the choices are researched and proposed, and judged by
the owner in Play.

## 0. Summary

- Racing games put the help between the player's input and the car, or offer it as an opt-in
  assist. They rarely make the car itself grippier (08 §3.2; the exceptions are opt-in, below).
- Drive Lab already had the input layer most of them describe: a steering limit set by the front
  tyres' grip, a turn-in rate that falls with speed, a quicker swing to the other side, and pedal
  ramps within game norms (01 §4).
- Measured, the car was benign in a lift-off and a lane change. It spun in three ways:
  - under a light brake in a held corner;
  - under full throttle in a held corner with its own systems off;
  - when a player counter-steered a big slide on keys, or on a stick with its systems off.
- Built: a slide assist (Gran Turismo's countersteering assistance, in the input layer). There are
  three notches, Realistic, Balanced and Forgiving, with Balanced the default. Realistic is the car
  exactly as it was.

## 1. What racing games do (condensed from the researcher's report)

Tags as in 01 and 08:
- (a) official or developer source;
- (b) community, or read from code;
- (c) inference;
- [excerpt] seen only in a search summary.

### 1.1 Speed-sensitive steering
- **BeamNG 0.26** (a):
  - "The high-speed steering assistant will no longer limit your steering range, but reduce its
    speed instead".
  - A new understeer assistant "controls the amount of steering to maximize lateral cornering
    grip".
- **Edy's Vehicle Physics** `autoSteerLevel` and the **VPP** Steering Limit (a): both keep the
  front's sideways slip near the tyre's peak.
- (c) The common pattern: grip sets the range and speed slows the rate. A plain speed-based lock
  (A-Chassis `SteerDecay`, the PhysX table) is the version that blocks catching a slide. Drive Lab
  already follows the pattern: `InputFilter.steerBounds` and `rateHalvingSpeed`.

### 1.2 Stability and yaw assists
- **Forza Motorsport (2023)** (a, Turn 10's support text relayed by GamingBolt): "The onset of
  oversteer triggers the stability management system to apply braking force to individual
  wheels."
- **GT6 ASM** (a): it "prevents the car from spinning out" and switches off when ABS is off.
- **GT7 1.31** (a): "The amount of intervention when oversteering has been increased".
- A GT6 player found ASM "slowed down the car way too much" (b).
- **Assetto Corsa's stability control:** a community claim that it is an artificial body force
  (b, unconfirmed).
- **Unreal Chaos arcade TorqueControl:** yaw torque and rotation damping (a, no defaults).
- **A-Chassis 1.7.2 ESC** (b, code): a 0.85 g threshold; it splits throttle and brake left and
  right.

### 1.3 Countersteer assists
- **GT6 "Active Steering"** (a): it "automatically corrects steering when the car oversteers and
  the rear slips out". "'mild' … will allow for a certain amount of oversteer"; "'strong' setting
  will correct even minor oversteer".
- **GT7** (a): Weak / Strong / Off.
  - 1.31: "The amount of intervention while oversteering has been reduced". It moved help from
    the steering toward ASM.
  - Since then, Expert has countersteer Off and Intermediate has Weak.
- **GRID Legends** (a): "Counter Steer Assist", in drift mode.
- **AC Advanced Gamepad Assist** (b):
  - countersteer response "below 50%", because higher makes it "easier to overcorrect a slide and
    spin the other way";
  - self-steer damping about equal to its response.
- **A-Chassis** (b, code): the countersteer is added to the player's input only while the input
  is small (13 §1.3).

### 1.4 Grip made more forgiving past the limit
- **VPP** (a): "The default tire setup is very forgiving and allows a good control of the
  vehicle". That means a wider slip at the peak and a floor about 73 % of the peak, against a
  competition tyre whose friction "rapidly drops".
- **Opt-in grip boosts:** GT6 "Skid Recovery Force" (a) and Forza "Friction Assist" (a [excerpt]).
- **The counter-position:** Kunos, Turn 10 and KartKraft keep the car and help in the input layer
  (08 §3.2, §3.5).

### 1.5 Pedals, recovery, keyboard, presets
- **Pedal ramps** read from code: A-Chassis about 0.33 s on and 0.08 s off; PhysX 0.17 s on and
  0.10 s off (b; the times are the researcher's arithmetic). Drive Lab's keyboard: 0.2 / 0.1 s for
  the throttle and 0.12 / 0.08 s for the brake.
- **Recovery help in games:** countersteer assists, per-wheel brakes, opt-in grip, yaw damping,
  and resets (GT7 "Replace Car After Leaving Track", Forza's rewind).
- **Presets:** one selector writes every assist's level, and any manual change flips it to Custom
  (a):
  - GT7: Beginner / Intermediate / Expert;
  - GRID Legends: Easy to Legend, default Easy;
  - F1 22: Amateur to Elite.

### 1.6 Not found (scoped to the researcher's searches)
- Kunos's description of AC's stability control.
- Polyphony's mechanism for ASM or the countersteer assist.
- The contents of Forza's presets (its support site answered 403).
- Driving Empire's or Midnight Racing Tokyo's handling.
- Any developer statement that a tyre curve was flattened for pad players.

## 2. Drive Lab before this change (measured)

- **Tool:** `tools/handling.luau`, on `tools/HandlingScenario`.
- **Drivers:** a keyboard driver (keys of −1, 0 or 1 through `InputHelp.keyboard`), a stick driver
  (proportional, through `InputHelp.gamepad`), and hands off.
- **Rows:**
  - SVJ in Strada with its assists;
  - SVJ in Corsa with ESC off;
  - DR458 in manettino 1;
  - DR458 in manettino OFF.
- **Frame rates:** 30, 60 and 120 FPS.
- **Body slip** is read only above 5 m/s; a stopped car has no direction of travel.

**Fine:**
- **Lift-off** in a held corner: 3 to 11°, never spins.
- **A keyboard lane change** at 120 km/h: 2 to 4°.
- **Turn-in:** the front held at 95 % of its peak, with t90 0.47 to 0.53 s at 100 to 180 km/h.
- **The yaw overshoot at the limit** (17 to 55 % on keys, up to 88 % on a pad at 180 km/h) is the
  chassis itself. A fixed steer ramp with no input layer gives the same overshoot, and 3 to 9 % at
  a quarter of that steer.

**Spins:**
1. **A light brake (0.3) in a held corner at 120 km/h** spins the DR458 in every manettino position
   (48 to 69°), and the SVJ with ESC off (62 to 67°).
   - With the wheel held still at the corner's angle instead of the key held, the DR458 takes only
     15°.
   - Under the key, the steering limit follows the car's rotation into the turn.
2. **Full throttle in a held corner at 60 km/h** spins the SVJ with ESC off and the DR458 in OFF
   (89°). Holding the wheel still does not help: it is the rear tyres' torque.
3. **Counter-steering a 20° slide** (100 km/h, 0.8 rad/s) spins both cars on keys in almost every
   mode, and on a stick whenever the car's own stability control is off. Letting go recovers in
   1.75 to 3.0 s.

   A trace of the DR458 shows why:
   - the countersteer winds on at the keyboard's turn-in rate, which at 100 km/h is 2.7 s per lock;
   - it is still applied when the rear grips again;
   - the yaw rate snaps from +0.56 to −2.6 rad/s;
   - the steering's 0.55 s return is too slow to unwind it.

## 3. The slide assist (`Vehicle/SlideAssist`)

### 3.1 The law

- **Detect a slide** in either of two ways:
  - the rear axle's slip angle passes a share of its peak while it slides more than the front
    (which leaves understeer alone);
  - the yaw rate is off ESC's existing bicycle-model reference (`Electronics.referenceYawRate`) by
    more than a start.

  Each term rises to full over a band, and the larger counts. The share is held and handed back
  over 0.4 s.
- **Steer:** while the share is above zero, the steering target is blended toward the front axle's
  path angle less 0.1 s × the yaw rate, and the wheel moves at 0.35 s per lock (a quick hand)
  instead of the filter's turn-in pace. The front tyres then stop adding rotation, the rear does
  the straightening, and the damping eases off as the rotation stops, instead of whipping the car
  the other way.
- **Stand aside:**
  - at Realistic;
  - below 5 m/s;
  - while the drift button or the handbrake is held, or a drift is fading. Those slides are the
    player's.
- **Scope:** only the steering input changes. The car, its tyres, TC, ABS and ESC are untouched. It
  also acts with the car's own systems off (SVJ ESC off, DR458 OFF): the level is the player's
  setting.

### 3.2 How the law was found

A scratch harness reproduced the tool's numbers exactly, then tried variants in turn.

| Variant | Result |
|---|---|
| Steering bound with the yaw rate capped at the tyre limit | no effect on the three spins |
| Countersteer dosed to 30 % of the peak slip, plus self-align when released | no effect |
| Path-following assist gated on body slip | fixed the spins, but fired in normal cornering (body slip is about −2.5° at speed) and still snapped back on keys, as the gate let go too early |
| Detector on rear-axle saturation or yaw error, with a 0.4 s hold | fixed all three, with turn-in unchanged |
| "Catch only" middle level (assist only when the player releases or counter-steers) | failed: after the snap, a late countersteer key reads as "into" the new rotation, so the assist stood aside exactly when it was needed |
| A 50 % blend of the assist's output | worse than either end; some catches with the hands off spun |

So the notches differ in when the assist acts, not in how much authority it has.

### 3.3 Notches (`Config/GameFeel`, `Config/Cars/<car>/Handling`)

| Notch | Rear-slip start (× its peak) | Yaw-error start (rad/s) | As in GT |
|---|---|---|---|
| Realistic | - | - | Off |
| Balanced (default) | 2 | 0.6 | Weak: the tail may step out |
| Forgiving | 1 | 0.55 | Strong |

- **Shared values,** the same on both cars until the owner's play says otherwise:
  - bands 0.5 and 0.3 rad/s;
  - damping 0.1 s;
  - 0.35 s per lock;
  - ease share 0.15;
  - hold 0.4 s;
  - minimum speed 5 m/s.
- **Forgiving's yaw start** was 0.25 in the plan. In the real implementation that made the assist
  take the steering in a hard keyboard lane change, 0.7 s each way at 120 km/h. It held a share of
  up to 1.0 for 0.3 to 0.85 s and moved the steering by up to 0.18 of lock, though the car was not
  sliding: rear axle at most 73 % of its peak, body slip at most 4°. That was the yaw rate lagging
  a fast steering reversal. The sweep, at 30 / 60 / 120 FPS:

| Forgiving yaw start (rad/s) | Lane change: assist's peak share | Spins | DR458 OFF hands-off catch at 30 FPS |
|---|---|---|---|
| 0.25 | up to 1.0 (3 of 4 rows at 60 FPS) | none | 1.37 s |
| 0.40 | up to 1.0 on the SVJ Corsa ESC off | none | 1.77 s |
| 0.50 | 0.06 once (SVJ Corsa ESC off at 60 FPS) | none | 1.37 s |
| 0.55 | 0 everywhere | none | 1.37 s |
| 0.60 | 0 everywhere | none | 2.40 s (the assist re-triggers on the residual) |

  0.55 was chosen, and the coordinator approved the deviation.

### 3.4 Results

- **Source:** `docs/evidence/handling-assists/handling_{30,60,120}fps.txt`.
- **Ranges** cover the four rows and 30, 60 and 120 FPS. The 30 FPS SVJ Strada full brake is
  frame-rate sensitive at every notch, Realistic included.

| | Realistic | Balanced | Forgiving |
|---|---|---|---|
| Light brake (0.3) in a held corner, 120 km/h | spins (DR458 all, SVJ ESC off) | 8 to 14°, no spin | 7 to 10° |
| Full throttle in a held corner, 60 km/h, systems off | spins | 14 to 21° | 8 to 11° |
| Catch a 20° slide on keys | spins | 0.6 to 1.3 s, at most 9° the other way | 0.6 to 1.4 s, at most 9° |
| Catch on a stick / hands off | spins without ESC / 1.7 to 3.0 s | 0.6 to 1.0 s / 0.6 to 2.0 s | 0.6 to 0.9 s / 0.6 to 1.4 s |
| Turn-in and lane change | - | identical, assist never acts | identical, assist never acts |

### 3.5 What the specs pin

`tests/SlideAssist.spec.luau` and `tests/Handling.spec.luau`; the bounds are in each spec's header.

- **Realistic still spins** in the three cases. This proves the scenarios can fail.
- **Balanced and Forgiving catch them:**
  - light brake: at most 15° and 11°;
  - power: at most 22° and 12°;
  - the catch: within 1.2 s, at most 5° the other way at 60 FPS; within 2.5 s and 10° at 30 and
    120 FPS.
- **Ordering:** Balanced lets the tail out further than Forgiving, and less than Realistic.
- **Normal driving:** Forgiving never acts in turn-in or a lane change, which drive exactly as at
  Realistic.
- **Realistic and the drift button change nothing,** frame for frame. Every existing tool's output
  is byte-identical to main.

## 4. Not done, and why

- **Grip curve.**
  - The tyres keep 78 to 82 % of their peak far past the limit, and slides with the hands off
    recover on both cars.
  - 08's rule keeps the car data-driven.
  - An opt-in grip notch (GT6, Forza) remains possible later.
- **Brake-based stability.** No measured case needed it, it costs speed, and GT7 shows the trade
  either way.
- **Yaw damping at turn-in.** The overshoot is the chassis at its limit and nothing spins. AC-style
  self-steer damping is the lever if the owner finds the car darty at speed.
- **Pedal filtering:** already within game ranges.

## 5. Not verified

- Feel, in Play: the owner's.
- Wet behaviour: every run is at grip 1. The assist reads the surface's mean grip for ESC's
  reference, so on wet it starts earlier; this is not measured.
- Real players' timing: the scripted drivers react instantly.
- The researcher's quotes passed through a summariser and were not compared against raw pages.

## Sources

- GT6 manual, driving options: https://www.gran-turismo.com/us/gt6/manual/howtorace/drivingoption.html
- GT7 update 1.31: https://www.gran-turismo.com/us/gt7/news/00_1462138.html
- GT7 manual [excerpt]: https://gran-turismo.com/us/gt7/manual/drivingoption/03
- Forza Motorsport accessibility (GamingBolt): https://gamingbolt.com/forza-motorsports-accessibility-features-have-been-revealed
- BeamNG v0.26: https://beamng.com/game/news/blog/beamng-drive-v0-26
- VPP tyres: https://vehiclephysics.com/blocks/tires/ ; VPP controller: https://vehiclephysics.com/components/vehicle-controller/
- AC Advanced Gamepad Assist config guide: https://raw.githubusercontent.com/adam10603/AC-Advanced-Gamepad-Assist/main/ConfigGuide.md
- A-Chassis 1.7.2: https://raw.githubusercontent.com/lisphm/A-Chassis/main/Scripts/A-Chassis%20Tune.luau
- PhysX vehicle sample: https://raw.githubusercontent.com/NVIDIAGameWorks/PhysX/4.1/physx/snippets/snippetvehicle4w/SnippetVehicle4W.cpp
- GRID Legends gameplay settings: https://www.ea.com/able/resources/grid/grid-legends/pc/gameplay
- F1 22 assists: https://www.ea.com/able/resources/f1-22/ps5/assists
- Unreal Chaos torque control: https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Plugins/ChaosVehicles/FVehicleTorqueControlConfig
