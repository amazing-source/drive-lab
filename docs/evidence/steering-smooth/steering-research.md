# Keyboard and mouse steering: research for Drive Lab

Researcher agent, 2026-10-29. Web search and fetch only: no browser, no login-walled pages, no
game was run. This is a research-only task with no repository edits, so no issue, branch or PR was
opened.

**Confidence key.** *Documented*: read on the primary page, in official docs or in source code.
*Likely*: a forum post, a third-party guide, or a search-result snippet of a page I could not open.
*Unknown*: not found. *Inferred*: my own calculation or reasoning, not a source.

**Method caveat.** WebFetch returns a summary written by a smaller model, not the raw page. The code
excerpts below (A-Chassis, Content Manager, PhysX, Advanced Steering) came back as quoted lines, but I
did not diff them against the raw files.

## Summary

- Most titles use the shape Drive Lab already uses: a **constant rate**, with separate rates for
  steering out and for returning. NVIDIA's PhysX vehicle sample uses exactly Drive Lab's numbers:
  rise 2.5/s, fall 5.0/s. A-Chassis adds an ease-out near the target. None of the big sims
  documents an ease-in for keyboard. Mods that try to make keyboard steering feel analog do add one:
  a ramp, or a rate that grows the longer the key is held.
- Drive Lab's 0.4 s to full lock at a standstill means about **950 to 1,170 °/s at the steering
  wheel** (inferred, for 2.1 to 2.6 turns lock to lock). That is faster than NHTSA's 720 °/s robot
  rate for the fishhook test. A real parking-effort test turns the wheel at 60 to 90 °/s.
- Speed sensitivity has two parts: the **maximum angle** and the **turn rate**. For the angle, LFS
  ("stabilised"), BeamNG and two well-known mods all cap it from tyre slip or grip. Drive Lab's
  peak-slip clamp already does this.
- Mouse steering is a niche that works: LFS and A-Chassis have it, and AC added it. It is worth an
  opt-in toggle, after the keyboard fix.

---

## 1. How known titles filter keyboard (digital) steering

### Assetto Corsa (AC)

| Item | Value | Source | Confidence |
|---|---|---|---|
| `[KEYBOARD] STEERING_SPEED` | 1.75 | Content Manager reads controls.ini with this fallback default: [ControlsSettings.cs](https://raw.githubusercontent.com/gro-ove/actools/master/AcManager.Tools/Helpers/AcSettings/ControlsSettings.cs) | Documented as CM's default; that it equals AC's shipped default is *likely* |
| `STEERING_OPPOSITE_DIRECTION_SPEED` ("opposite lock speed") | 2.5 | same | same |
| `STEER_RESET_SPEED` ("return rate") | 1.8 | same | same |
| `MOUSE_STEER` / `MOUSE_SPEED` | false / 0.1 | same | same |
| Units of these speeds | not stated | none | *Unknown*. If they are full lock per second: 0.57 s to lock, 0.40 s when crossing to the other side, 0.56 s back to centre (*inferred*) |
| Gamepad `[X360]`: `STEER_SPEED`, `STEER_GAMMA`, `STEER_FILTER`, `SPEED_SENSITIVITY`, `STEER_DEADZONE` | 0.2, 2.0, 0.7, 0.2, 0.0 | same file | Same as above |
| Is keyboard steering speed sensitive? | CM has no keyboard speed-sensitivity key; `SPEED_SENSITIVITY` is in the gamepad section only | same file | Keyboard behaviour *unknown* |
| Gamma above 1 makes the centre less sensitive | — | [Steam thread, 2014](https://steamcommunity.com/app/244210/discussions/0/35222218807679850), [Steam thread, 2017](https://steamcommunity.com/app/244210/discussions/0/144513524084190989) | *Likely* |
| Filter shape | not documented | — | *Unknown* |

What a modder says. The AC Advanced Gamepad Assist mod by adam10603 explains its "Steering rate"
setting: "A lower rate applies more smoothing to your steering input, but going too low can feel
unresponsive." The author recommends 30 to 60 %. Other settings are "Steering rate at speed",
"Target slip angle" (most cars feel best at 90 to 100 %) and keyboard input that "will have a bit
more smoothing compared to controller steering". On first run the mod sets gamma 140 % and deadzone
12 % ([README](https://github.com/adam10603/AC-Advanced-Gamepad-Assist),
[ConfigGuide](https://raw.githubusercontent.com/adam10603/AC-Advanced-Gamepad-Assist/main/ConfigGuide.md)).
*Documented* for the mod.

### Assetto Corsa Competizione (ACC)

- The controller sliders are Steer Gamma (1 to 3), Steer Filter (0 to 100 %, lower is more
  immediate), Speed Sensitivity (higher means less sensitive at speed), Steer Speed, Deadzone and
  Steer Assist. Source: [Coach Dave Academy](https://coachdaveacademy.com/tutorials/ultimate-assetto-corsa-competizione-controller-settings). *Likely* (third-party guide).
- Coach Dave's suggested values: gamma 3.0, steer speed 70 %, speed sensitivity 70 %, deadzone 2 %,
  filter 10 %. Steam users vary widely: gamma 2.2 to 3, filter around 80 %, speed sensitivity 20
  to 50 %. *Likely*.
- ACC's shipped defaults: *unknown*. Whether these sliders apply to the keyboard: *unknown*.

### BeamNG.drive

- **Filters.** Each binding has a filter: Automatic (the default), Key (smooth), Key (fast),
  Gamepad, or Wheel (direct). A BeamNG staff reply says the old "drift" filter was renamed Key
  (fast) and that the key filters are meant for keyboard steering. Per a forum post, Automatic picks
  slower steering for road cars and quicker steering for race and drift cars. Sources:
  [forum thread](https://www.beamng.com/threads/remove-the-slower-pad-and-keyboard-steering-when-using-a-filter.83377),
  [troubleshooting PDF](https://documentation.beamng.com/support/hardware/steering_wheel_common_problems/Input_troubleshooting_guide.pdf).
  *Likely*.
- **Smoother shape.** BeamNG documents a `temporal` smoother as "linear temporal smoothing" with
  `inRate`, `outRate` and a separate `autoCenterRate`. It is a constant-rate limiter with its own
  return-to-centre rate. There is also an `exponential` smoother
  ([electrics docs](https://documentation.beamng.com/modding/vehicle/sections/electrics/)).
  *Documented* for vehicle electrics. That keyboard steering uses the temporal smoother is *likely*:
  the Advanced Steering mod creates `smootherKBD` and `smootherPAD` with
  `newTemporalSmoothing(10, 10, nil, 0)`, "copied from the original"
  ([source](https://raw.githubusercontent.com/adam10603/BeamNG-Advanced-Steering/release/lua/vehicle/extensions/auto/advancedSteering/advancedSteering.lua)).
  An older forum excerpt instead gives `(3, 3, 1000, 0)` for keyboard. The stock values and their
  units are *unknown*, and the two sources conflict.
- **Key (smooth)** scales steering speed and input authority to 70 %, per the Advanced Steering
  [ConfigGuide](https://raw.githubusercontent.com/adam10603/BeamNG-Advanced-Steering/main/ConfigGuide.md)
  and source. *Likely* for stock behaviour.
- **Driving assistants (0.26 and later).** Understeer reduction, oversteer reduction, "slower
  steering at high speed", and "limit steering at high speed" (with "Limit max angle to", "Start at"
  and "Stop at"). The new limit "retains full countersteering range according to the sliding
  angle"; the old one slowed and limited steering whatever the slide angle, which made
  countersteering hard. Understeer reduction turns itself off on loose surfaces (stated by BeamNG
  programmer stenyak). Source: [forum thread, 2023](https://beamng.com/posts/1543337). *Likely*.
- The speed-based limit was off by default in 2018
  ([Steam](https://steamcommunity.com/app/284160/discussions/0/2592234299531419960)). *Likely*, may
  be out of date.
- One guide author found that "a linear drop in response from 15–250 km/h gives good results"
  ([dedoimedo](https://www.dedoimedo.com/games/beamng-keyboard-mouse-driving.html)). *Likely*, one
  person's view.

### Live for Speed (LFS)

From the LFS manual, [Options/Controls](https://en.lfsmanual.net/wiki/Options/Controls). *Documented*
unless marked.

- Three modes: "Keyboard - no help" (key presses go straight to wheel movement); "Keyboard -
  stabilised", which "limits the movement of the wheel depending on the amount of grip the tyres
  have" and adds automatic counter-steering; and "Mouse steer".
- **Steer rate**: how fast the wheel turns while a steer key is held. "Higher values will make the
  car more responsive but less stable." No numeric default is given.
- **Return rate**: how fast the wheel turns back on release. The manual says it is usually 50 to
  75 % of the steer rate, so **the return is slower than the steer**, the opposite of Drive Lab
  today.
- **Fast steer multiplier**: default 2.00, applied while a "Steer Fast" key is held. **Slow steer
  multiplier**: default 0.50. The manual adds: "the keyboard steering is automatically speed
  sensitive".
- **Limit multiplier** (stabilised mode): 1.0 limits the wheel to the tyres' available grip. Above
  1 allows more turn (and understeer); below 1 is easier but slower.
- A 2004 command sheet lists `/speedreduce` (total steer reduction, 0 to 1) and `/reducehalf` (the
  speed in m/s at which half of that reduction applies)
  ([Scribd](https://www.scribd.com/document/373547020/Lfs-Keys-Commands)). *Likely*, may be out of
  date.

### rFactor 2 (and Le Mans Ultimate, on the same engine)

- "Steering rate" affects digital inputs (keyboard and gamepad buttons) only. "Speed sensitive
  steering" reduces lock as speed rises. "Steer ratio speed" is a low-speed override, around 20,
  that forum users say makes steering "extra sensitive" under about 20 km/h. Sources:
  [Granite Devices forum](https://community.granitedevices.com/t/rfactor-2-and-simucube-2/2975?page=27),
  [RaceSimCentral 2014](https://community.racesimcentral.net/goto/post?id=21971),
  [RaceSimCentral 2014](https://community.racesimcentral.net/goto/post?id=22355). *Likely*.
- One user's LMU gamepad file, ported from rF2's gamepad.json, shows Steering Rate Factor 0.5,
  Steering Return Rate Multiplier 1, Steering Speed Sensitivity 0.65, Steering Snap Factor 0.5,
  Steering Aggression 0.1 and Sensitivity Type 2
  ([Steam, 2024](https://steamcommunity.com/app/2399420/discussions/0/4348858679320667370)).
  *Likely*. These are one user's values, not the defaults.
- rF2's defaults and filter shape: *unknown*. Studio 397 pages were not reachable.

### Forza, Gran Turismo 7, GTA V (descriptions only)

- **Forza.** Official support text says "multiple systems layered together create Normal steering"
  and that Simulation turns them off. Players describe Normal as capping full lock by speed.
  Sources: [FH5 wheel setup (snippet; the page returned 403)](https://support.forza.net/hc/en-us/articles/4409761195923-FH5-Wheel-Setup-and-Tuning),
  [forum](https://forums.forza.net/t/gamepad-steering-fairy-or-normal/11757). *Likely*. Numbers:
  *unknown*.
- **GT7.** The manual says controller steering sensitivity "adjusts the steering speed and
  response speed of the front tyres" to stick input. Its wording on which direction is faster
  contradicts itself. There is also a Countersteer Assistance option. Source:
  [GT7 manual (snippet; the page is script-rendered)](https://www.gran-turismo.com/gb/gt7/manual/drivingoption/04).
  *Likely*. Numbers: *unknown*.
- **GTA V.** No documentation found (*unknown*). Players install
  [Smooth Driving V](https://www.gta5-mods.com/scripts/smooth-driving-v-lieutenant-dan) to smooth
  keyboard steering, and a request for it describes stock cars turning "very nervously" on keyboard.
  *Likely*.

### Roblox A-Chassis

**Open-source A-Chassis 1.7** ([lisphm/A-Chassis](https://github.com/lisphm/A-Chassis);
[Tune](https://raw.githubusercontent.com/lisphm/A-Chassis/main/Scripts/A-Chassis%20Tune.luau),
[Drive](https://raw.githubusercontent.com/lisphm/A-Chassis/main/Scripts/Drive.luau)). *Documented*
in source.

| Tune | Default | Comment in source |
|---|---|---|
| SteerRatio / LockToLock | 18/1 / 2.6 | rack ratio; turns lock to lock |
| SteerInner / SteerOuter | 39 / 36 | degrees |
| SteerSpeed / ReturnSpeed | .05 / .1 | "increment per tick" (the comment says degrees, but the value is a fraction of full lock) |
| ContlrSteerSpeed / ContlrReturnSpeed | 0 / 0 | 0 means use the keyboard values |
| MSteerUsesContlr | true | mouse uses the controller settings |
| SteerDecay / MinSteer | 260 / 25 % | max angle falls with speed to a 25 % floor (comment: km/h) |
| SteerSpeedDecay / MinSteerSpeed | 260 / 60 % | turn rate falls with speed to a 60 % floor |
| SteerSmoothing | 3 | "the lower, the smoother the steering will arrive at max angle" |
| MSteerExp | 1 | mouse exponent |
| Peripherals: MSteerWidth / MSteerDZone / ControlLDZone / ControlRDZone | 67 % / 10 % / 5 % / 5 % | screen width, deadzones |

How it runs (source, read through the fetch summary):

- Steering runs at a fixed 60 Hz (`dt * 60`), with keyboard target −1, 0 or 1.
- Each step is `rate * |error|^(1/SteerSmoothing)`. It starts at full speed and slows near the
  target, so it eases out but does not ease in.
- ReturnSpeed applies while moving back toward centre from the current side; SteerSpeed applies
  otherwise.
- The rate scales with `1 - min(v/SteerSpeedDecay, 0.4)` and the angle with
  `1 - min(v/SteerDecay, 0.75)`.
- Gamepad input uses the controller rates. Per the summary it skips the speed scaling of the rate.
- An optional auto counter-steer uses lateral velocity.

*Inferred* from those formulas: at a standstill the default goes from centre to full lock in about
**0.50 s** and returns in about **0.25 s**. That is close to Drive Lab's 0.4 s and 0.2 s.

**The older A-Chassis Tune most games copied** (posted on the DevForum, version not stated): SteerSpeed .05,
ReturnSpeed .1, SteerDecay 320 ("in SPS", studs per second), MinSteer 10 %, MSteerExp 1,
MSteerWidth 67, MSteerDZone 10, controller deadzones 5
([DevForum](https://devforum.roblox.com/t/vehicle-a-chassis-tune/1324988)). *Likely*. The tick rate
of that older script is *unknown*.

### Engine defaults (for reference)

- **NVIDIA PhysX vehicle sample.** Key and pad smoothing for steer: rise 2.5/s, fall 5.0/s, the
  same as Drive Lab today. The steer-versus-speed table allows 0.75 of lock from 0 to 5, 0.125 at 30
  and 0.1 at 120 (forward speed, m/s in a metre-scaled scene)
  ([SnippetVehicle4W.cpp](https://raw.githubusercontent.com/NVIDIAGameWorks/PhysX/4.1/physx/snippets/snippetvehicle4w/SnippetVehicle4W.cpp),
  [API: rise rate when the key is 1, fall rate when 0](https://archive.docs.nvidia.com/gameworks/content/gameworkslibrary/physx/apireference/files/structPxVehicleKeySmoothingData.html)).
  *Documented*.
- **Unity Input Manager.** Sensitivity is the speed in units per second toward the target, Gravity
  the speed back to neutral, and Snap jumps to 0 when the opposite key is pressed
  ([manual](https://docs.unity3d.com/cn/2022.3/Manual/class-InputManager.html)). *Documented*.
  Horizontal is usually 3 / 3 / Snap on in project files. *Likely*.

---

## 2. Filter shapes and their trade-offs

| Shape | How the wheel moves | Who uses it | Good | Bad |
|---|---|---|---|---|
| **Constant rate** (first-order rate limit) | Jumps to full speed, stops dead at the target | PhysX sample, Unity Input Manager, BeamNG `temporal` (*likely*), A-Chassis (plus ease-out), Drive Lab | Time to lock is exact and easy to tune | Abrupt start and stop. A short tap gives a large angle: a 100 ms tap at 2.5/s is 25 % of lock (*inferred*) |
| **Exponential** (first-order lag) | Fastest at the start, slows as it nears the target, never quite arrives | BeamNG has an `exponential` smoother (documented, for electrics); Advanced Steering moves "a fraction of the remaining distance" per frame (*likely*); AC/ACC "filter" may be this (*unknown*) | Soft landing | Still jumps at the start. Daniel Holden: a damper "will immediately switch to moving in the opposite direction if the goal changes direction" ([Spring-It-On](https://theorangeduck.com/page/spring-roll-call)). Lag grows with the angle |
| **Second order** (critically damped, or rate-capped with acceleration) | Speeds up, cruises, slows into the target | No big sim documents it for keyboard (*unknown*). Close relatives: a mod that ramps steering linearly over 500 ms ([FS19 Keyboard Steering](https://www.kingmods.net/en/fs19/mods/7411/keyboard-steering_1)); ETS2 non-linearity, which per one player "makes the wheel increasingly faster to turn as I keep the keyboard button down" ([Steam](https://steamcommunity.com/app/227300/discussions/0/1489992080514403127)); [Arma Reforger Smooth Keyboard Steering](https://reforger.armaplatform.com/workshop/D547D086C9009204-SmoothKeyboardSteering), where speed grows with angle (5 %, then 10 %, then 20 %) | Smooth at both ends. Short taps give small, precise angles. Holden: a critically damped spring "returns to the goal as fast as possible without extra oscillation"; his "velocity spring" tracks "an intermediate target that moves toward the goal at that fixed velocity", which is a rate cap plus smoothing | One more parameter. A little lag on reversals. Needs a rate cap, or a long hold feels like nothing happens and then a rush |

**What players and modders say** (all *likely*, opinion):

- BeamNG players dislike filters that also slow the steering
  ([thread](https://www.beamng.com/threads/remove-the-slower-pad-and-keyboard-steering-when-using-a-filter.83377)).
  They ask for a gentler auto-centre, "similar to what ETS2 and ATS do"
  ([thread](https://www.beamng.com/posts/1243592/)).
- An ETS2 player finds an instant return to neutral on release jerky at highway speed
  ([thread](https://steamcommunity.com/app/227300/discussions/0/1489992080514403127)).
- The AC Advanced Gamepad Assist author: more smoothing helps, but too much "can feel
  unresponsive".
- Modders who rebuilt pad and keyboard steering (BeamNG and AC Advanced Steering / Gamepad Assist)
  converge on the same recipe: cap the angle at the tyre's peak slip, and let a self-steer
  (caster-like) force bring the wheel back instead of a fixed return rate
  ([Explanation.md](https://raw.githubusercontent.com/adam10603/BeamNG-Advanced-Steering/main/Explanation.md)).

**Return to centre** (each *documented* in its source unless marked):

| Title | Return compared with steer |
|---|---|
| PhysX sample | 2× faster (5.0 against 2.5) |
| A-Chassis | 2× faster (.1 against .05), with ease-out |
| AC (CM defaults) | about the same (1.8 against 1.75), but faster when steering to the other side (2.5) |
| LFS manual | **slower**: 50 to 75 % of the steer rate |
| Unity | the same by default, plus Snap |
| BeamNG | its own `autoCenterRate` |
| FS19 keyboard mod | centring force "proportional to road speed", and "no steering back force when stationary" |
| ETS2 (forum observation) | no return on release when stopped; slow return at low speed, much faster at speed |

**Speed sensitivity.** Two separate knobs.

- **Max angle against speed:** A-Chassis SteerDecay and MinSteer; the PhysX table; rF2, AC gamepad
  and ACC "speed sensitivity"; Forza Normal (*likely*); BeamNG "limit steering at high speed". LFS
  stabilised mode and both adam10603 mods cap from grip or slip instead, which is what Drive Lab's
  clamp does.
- **Turn rate against speed:** A-Chassis SteerSpeedDecay (to 60 %); BeamNG "slower steering at high
  speed"; AC Advanced Gamepad Assist "Steering rate at speed", either direction.
- The BeamNG Advanced Steering source makes the rate **faster** with speed,
  `steeringSpeed * (airspeed/200 + 1)`. With "relative steering speed" on, it also multiplies by
  `540 / steeringWheelLock`, which sets the rate at the steering wheel, as a hand would (*likely*,
  source via summary).
- BeamNG's newer limit keeps the full countersteer range by slide angle (*likely*). That is the
  main trap of a speed-only limit: you cannot catch a slide at speed.

---

## 3. Mouse steering

| Title | How it works | Parameters | Source | Confidence |
|---|---|---|---|---|
| A-Chassis 1.7 | **Absolute** horizontal cursor position. `mST = (mouse.X - screenW/2) / (screenW*MSteerWidth/200)`; inside the deadzone the target is 0; outside it is rescaled to 0..1, raised to `MSteerExp`, and given its sign. With `MSteerUsesContlr`, the mouse uses the controller rates | Width 67 % of the screen, deadzone 10 %, exponent 1 | [Drive.luau](https://raw.githubusercontent.com/lisphm/A-Chassis/main/Scripts/Drive.luau), [Tune](https://raw.githubusercontent.com/lisphm/A-Chassis/main/Scripts/A-Chassis%20Tune.luau) | Documented |
| LFS | A "Mouse steer" mode; steering can also be mapped to the Mouse X axis | "Steer centre reduction": 0 is linear, 1 fully non-linear, **0.4 to 0.6 recommended** | [LFS manual](https://en.lfsmanual.net/wiki/Options/Controls); players say LFS "takes its mouse speed from Windows" ([search snippets of lfs.net posts](https://www.lfs.net/forum/post/209596)) | Mode and centre reduction documented. Absolute or relative: *unknown*, probably cursor position |
| AC | With mouse steering on, "the mouse gets locked in the center of the steering wheel" and moving left or right turns it. That reads as **relative** (movement accumulates). Ctrl+M toggles it | `MOUSE_STEER`, `MOUSE_SPEED` 0.1 | [CM source](https://raw.githubusercontent.com/gro-ove/actools/master/AcManager.Tools/Helpers/AcSettings/ControlsSettings.cs); 2015 Steam post (search snippet) | Keys documented; mechanics *likely* |
| BeamNG | Mouse can be bound; one guide advises a filter and "values > 1" for linearity | — | [dedoimedo](https://www.dedoimedo.com/games/beamng-keyboard-mouse-driving.html) | Likely |

**What players say** (*likely*, all opinion):

- For: "the second best control method for any hardcore racer… the precision of a wheel without
  the wheel", and "quite a few World Records were set… with a mouse on Live For Speed" (unverified
  against the LFS hotlap charts). Both from the [AC Steam thread, 2013](https://steamcommunity.com/app/244210/discussions/0/666827315235960431).
- Against: in the same thread, "mouse is for fps not racing". Another reply says most LFS records
  are wheel times.
- Roblox: a DevForum commenter found mouse steering "very useful for long turns"
  ([thread](https://devforum.roblox.com/t/physics-based-vehicle-simulation-game/2685401)).
- ETS2: a player notes you cannot take your hand off the mouse
  ([Steam](https://steamcommunity.com/app/227300/discussions/0/1489992080514403127)).

**Worth offering on PC?** *Inferred*: yes, as an opt-in toggle. It gives keyboard players an
analog steering input, and holding a steady arc is where keyboards are worst. The cost on Roblox is
the camera: absolute mode needs a free cursor, and relative mode needs a locked cursor. Either way
the mouse cannot also orbit the camera while steering.

---

## 4. The real car at a standstill

**What limits the turn rate:**

- **Tyre scrub (bore torque).** When the car is stationary, the tyre's bore torque "is the largest
  part of the steering power demand at the rack during parking manoeuvres"
  ([TU Dresden / SAE abstract](https://fis.tu-dresden.de/portal/en/publications/simulation-of-the-steering-system-power-demand-during-the-concept-phase-focusing-on-tire-modelling-at-standstill(ff55d48f-a02a-4db1-a7be-d8430f5a1a0d).html)).
  *Documented* (abstract).
- **Hydraulic assist at idle.** A pump is "typically sized to provide maximum rated flow required
  to dry park a vehicle at engine idle". Parking next to a curb needs "high pump pressures at high
  steering wheel speed" (patent background, via
  [search results](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/4420290)).
  *Likely*. Turning faster than the pump can feed makes the assist drop out for a moment ("pump
  catch") and the effort jump. Forum and engineering talk, *likely*.
- **The SVJ** has hydraulic power steering with LDS variable ratio and LRS rear-wheel steering
  ([Lamborghini](https://lamborghini.com/en-en/history/aventador-svj); hydraulic per a spec-site
  snippet). The rear steer reduces the steering-wheel angle needed at low speed. *Documented* for
  LDS and LRS; hydraulic is *likely*. So pump catch applies to the SVJ (*inferred*).
- **The hand.** Hand-over-hand or shuffle technique, and the effort above, set the pace. No
  measured distribution of parking hand speed was found (gap).
- **No self-centring when stopped.** Caster and trail need rolling. A real wheel left at lock stays
  there at a standstill. *Likely*: this is basic physics, but my only sources are game mods that
  copy it (FS19, ETS2, BeamNG Advanced Steering's "Photo mode").

**Measured or specified hand-wheel rates:**

| Rate | What it is | Source | Confidence |
|---|---|---|---|
| 60 to 90 °/s (10 to 15 r/min) | Parking-effort test input at 10 km/h, centre to lock; target below 4.5 N·m | [Li et al., AMEE 2017, p.133](https://download.atlantis-press.com/article/25883937.pdf) | Documented (a test input, not a maximum) |
| 300 °/s | Example threshold to flag an evasive manoeuvre | [US9410617](https://patents.google.com/patent/US9410617) | Documented (an example value) |
| 720 °/s | NHTSA fishhook robot rate, "within those observed" from human drivers on a short course | [NHTSA slides](https://www.nhtsa.gov/sites/nhtsa.gov/files/forkenbrock_0.pdf) (search snippet; the PDF returned 403) | Likely |
| 1,819 °/s | Single peak in an NHTSA double lane change | NHTSA DOT HS 809 875, Forkenbrock and Elsasser 2005 (search snippet) | Likely |

**Lock to lock.** For the SVJ: *unknown*. A generic Aventador listing says 2.1 turns, unconfirmed.
A-Chassis uses 2.6 as its template. The EPS test car in Li et al. reaches about ±540°, roughly 3
turns, read off their figure XIII.

**Typical time to full lock** (*inferred*). Centre to lock is half of lock to lock: 2.1 to 2.6
turns gives 380 to 470°. A brisk human parking turn somewhere between the 90 °/s test rate and the
720 °/s robot rate, say 400 to 600 °/s, gives **about 0.7 to 1.2 s**. Drive Lab's 0.4 s needs
950 to 1,170 °/s, faster than the robot.

---

## Recommendation for Drive Lab

These are starting points for the coordinator. Feel is the owner's to judge in Play. Every number
below is *inferred*, and the source it leans on is named.

**1. Filter shape: a rate-capped second-order filter.** The wheel speeds up, cruises at a capped
rate, and slows into the target. This is Holden's "velocity spring" idea, also known as a
trapezoidal profile. Reasons: it removes the abrupt start and stop the owner reports, and it makes
short taps give small angles (*inferred*: a 100 ms tap peaks near 9 % of lock with the values below,
against 25 % today). It keeps the exact time to lock that a constant rate gives. The ramp mods
(FS19 500 ms ramp, ETS2 non-linearity, Arma bands) all aim at this.

Sketch, per frame, all in normalised steer from −1 to 1:

    err   = target - pos
    vStop = sign(err) * sqrt(2 * accel * |err|)     -- fastest speed that can still stop at target
    vWant = clamp(vStop, -vMax, vMax)
    vel   = vel + clamp(vWant - vel, -accel*dt, accel*dt)
    pos   = pos + vel*dt                            -- snap to target when |err| and |vel| are tiny

Tuning is simple. With `vMax = 1 / (T_lock - T_ease)` and `accel = vMax / T_ease`, centre to full
lock takes exactly `T_lock` (*inferred*, from the kinematics).

**2. Keyboard starting values**

| Quantity | Start at | Today | Tied to |
|---|---|---|---|
| Time to full lock, 0 to 5 m/s | **0.9 s** (range 0.8 to 1.0) | 0.4 s | About 420 to 520 °/s at the wheel for 2.1 to 2.6 turns, a brisk human rate under the 720 °/s robot (§4). A-Chassis 0.50 s and PhysX 0.40 s are the arcade end |
| Ease time (speed-up and slow-down) | **0.15 s** | 0 | FS19 mod ramps over 500 ms; A-Chassis eases out only; Holden on damper discontinuity |
| Rate against speed | Keep today's curve (half at 25 m/s), applied to the new base | half at 25 m/s | A-Chassis rate floor 60 %; one BeamNG guide's linear drop from 15 to 250 km/h. The owner's complaint was low speed, so the decided high-speed behaviour stays |
| Steering toward the other side | **1.4×** the steer rate, at all speeds | — | AC default: opposite lock 2.5 against steer 1.75 = 1.43; LFS fast-steer ×2; BeamNG keeps the countersteer range |
| Return to centre, 0 to 2 m/s | **0.9 s** (no faster than the steer). Optional "hold at standstill" for realism | 0.2 s | LFS: return 50 to 75 % of steer; FS19 mod and ETS2: no centring when stopped; real cars do not self-centre when stationary (§4) |
| Return to centre, 15 m/s and up | **0.4 s**, blended linearly between 2 and 15 m/s | 0.2 s | Return grows with road speed (FS19 mod, ETS2, caster). The ETS2 complaint about jerky returns argues against going faster |
| Max angle | Keep the peak-slip clamp above 5 m/s, applied to the filter's target, not its output | as today | LFS stabilised (limit ×1.0), BeamNG limit, both adam10603 mods target peak slip |

Optional, for realism: express the keyboard rate as **hand-wheel °/s** (for example 500 °/s) and
convert it with the SVJ's centre-to-lock wheel angle once that is known. This is BeamNG Advanced
Steering's "relative steering speed" (`540 / steeringWheelLock`) idea.

**3. Gamepad starting values**

| Quantity | Start at | Tied to |
|---|---|---|
| Target | Stick X after deadzone **8 %**, response gamma **1.5** | Deadzones: A-Chassis 5 %, AC 0, AC Gamepad Assist 12 %. Gamma: AC default 2.0, Gamepad Assist 1.4, Coach Dave 3.0 for ACC |
| Same second-order filter | T_lock **0.5 s** at 0 to 5 m/s, ease **0.08 s** | The thumb already smooths. Gamepad Assist warns that too slow feels unresponsive. A-Chassis uses the same rates as keyboard unless set |
| Speed curve, slip clamp, other-side ×1.4 | Same as keyboard | As above |
| Return | Follows the stick (no extra auto-centre) | The stick's spring is the return |

**4. Mouse steering: add it as an opt-in PC toggle, after the keyboard change.** Use A-Chassis-style
absolute cursor position.

- Width **65 %** of the screen (A-Chassis 67 %).
- Deadzone **4 %**: A-Chassis's 10 % is a wide dead band. LFS uses a non-linear centre instead.
- Exponent **1.4** (LFS recommends centre reduction 0.4 to 0.6; a BeamNG guide prefers values
  above 1).
- Run it through the gamepad filter values (A-Chassis `MSteerUsesContlr = true`).
- Show a small marker for the steer position.
- Risk: it conflicts with mouse camera orbit, so it needs a camera rule. That is a design choice for
  the owner.

**5. Checks for the owner's Play session**

- **Tap:** a short A or D press should nudge the car without a jolt.
- **Hold at a standstill:** full lock should take about a second, with no snap at either end.
- **Release when stopped:** the wheel should return gently.
- **Catch a slide at speed:** the 1.4× other-side rate should be enough. If not, raise it before
  touching anything else.

## Not verified, and gaps

- No game was run. Every behaviour is from docs, source, or other people's posts.
- The quoted code and lines came through WebFetch's summariser, not raw downloads I diffed.
- **Units unknown:** AC keyboard speed values, BeamNG stock smoother values (two sources disagree),
  and LFS steer and return rates (no numeric default in the manual).
- **Defaults unknown:** ACC and rF2 shipped defaults; whether ACC's sliders apply to keyboard; how
  Forza, GT7 and GTA V filter keyboard steering.
- **SVJ:** lock-to-lock and steering ratio not found. That the SVJ is hydraulic rests on a spec-site
  snippet.
- No measured distribution of human hand-wheel speed when parking was found. The 0.7 to 1.2 s
  figure is my inference between documented bounds.
- Pages blocked or login-walled, so only search snippets were used: overtake.gg, gamedev.net,
  simracingsetup.com, gameskinny.com, lfs.net forum, forza.net support and forums, the NHTSA PDFs,
  and the GT7 manual (script-rendered).
- The recommended numbers are untested starting points.
