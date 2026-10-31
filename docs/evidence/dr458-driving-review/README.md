# DR458 driving review: offline numbers against the real car

Issue #123. Systems agent, 2026-10-31. Offline only: the DR458's config on `tools/DriveSim` (the
flat test track the calibration specs use), no Studio, no Play. Nothing in the car was changed.

Every simulated number below comes from `lune run games/drive-lab/tools/dr458_review.luau [fps]`
on main 8473fa4; its full output at 30, 60 and 120 FPS is in this folder. The table quotes 60 FPS;
30 and 120 FPS agree within 0.05 s and 0.01 g, and the braking within 0.1 m from 100 km/h and
1.2 m from 200 km/h.

Real figures come from `docs/research/12_dr458_challenge_evo.md` and its sources, with that note's
confidence. Ferrari published few figures for the Challenge, and none for the Evo's performance, so
several rows can only be compared with the road 458 or with an upper bound. A blank real figure is
a gap, never filled here.

## Results

| Measure | DriveSim | Real figure | Source, confidence | Difference |
|---|---|---|---|---|
| 0-100 km/h | 3.01 s in position 1 (2: 2.93 s, OFF: 3.02 s) | under 3.4 s | [MR] likely (no source named on the page); the road 458 is also "under 3.4 seconds" [F09] | Inside the bound, 0.39 s under it. A bound, not a value. |
| 0-200 km/h | 8.84 s in position 1 (2: 8.77 s, OFF: 8.85 s) | none for the Challenge | - | No comparison. The road 458's 10.4 s appears only in search summaries (a magazine test), so it is not used. |
| Top speed | 301.6 km/h in 7th at 8,289 rpm, drag-limited | none from Ferrari | 12 §1.10: unverified "nearly 200 mph" (Daytona) and "210 mph" (a dealer) | 20 to 36 km/h under the unverified claims. The road 458 is "in excess of 325 km/h" [F09], with less drag than the Evo's wing. |
| Gear tops (manual, at the limiter) | 74.9, 105.7, 141.3, 178.3, 223.4, 274.7 km/h for 1st to 6th; 7th never reaches its limiter | 75.6, 106.8, 142.8, 180.5, 226.0, 277.1 km/h from the ratios at 9,200 rpm | road ratios and 5.14 final drive, 12 §1.2, likely for the road car; 9,200 rpm limiter unknown | -0.9 to -1.2 %, the drive slip of the rear tyres. |
| Shift points (game automatic, full throttle) | 9,079 to 9,100 rpm, at 71.6, 102.6, 138.4, 175.5, 220.9, 271.7 km/h | the real car is shifted on its paddles; redline 9,000 rpm | 12 §1.1, likely | The automatic holds each gear 100 rpm past the redline, as its config says it should. |
| 100-0 km/h | 26.8 m with ABS (mean 1.47 g, peak 1.66 g); 28.6 m without | none for the Challenge | - | The road 458 stops in 32.5 m [F09], on road tyres and heavier (dry 1,380 kg against 1,218 kg); the DR458 is 5.7 m shorter. |
| 200-0 km/h | 99.8 m with ABS (mean 1.58 g, peak 1.99 g); 107.0 m without | none | 12 §1.10: "stops suddenly even from 220 km/h" [HFO], likely | No number to compare. |
| Lateral, low speed | 1.48 g on a 40 m skidpad (about 87 km/h); 1.52 g at 100 km/h | "up to 1.6G" | [FB10], documented, for the 2010 458 Challenge, not the Evo | 5 to 7 % under, as the config intends ("about 1.5 g at skidpad speed"). |
| Lateral, high speed | 1.67 g at 200 km/h (185 kg of downforce); 1.76 g at 250 km/h (286 kg) | "up to 1.6G" | as above | 5 % over at 200 km/h, 10 % over at 250 km/h. The Evo adds a GT-style wing and splitter [B16], unquantified, so it may well exceed the 2010 car's figure. |

The lateral rows hold a constant speed in one gear and wind the steering on slowly (ISO 4138's
constant-speed method), assists off, as `DriveSim.skidpad` runs; the 40 m row is that skidpad. The
best grip came at a steering input of 0.18, 0.11 and 0.09, well before each run ended (at full lock
or on speed loss), so each figure is a plateau, not a run cut short.
Braking starts in the gear the car would be in (3rd at 100 km/h, 5th at 200 km/h), and the pedal
goes down at exactly that speed. `DriveSim.brake` on main 8473fa4, which the calibration specs use,
coasted 0.5 s in gear first and pressed at 95.4 km/h on a "100 km/h" run: 24.4 m, from that lower
speed (#128, fixed in #134; the tool still prints that old method for comparison). An earlier draft
of this report quoted that 24.4 m as a 100-0 figure; it was wrong.

## Traction control and the manettino

Each position runs the systems `Config/Cars/DR458/Assists` gives it: TC on in 1 and 2, off in OFF;
ABS on in all three; no ESC.

| Run | 1 | 2 | OFF |
|---|---|---|---|
| 0-50 km/h from the brake | 1.45 s | 1.37 s | 1.53 s |
| Rear slip ratio over the first 3 s, mean / peak | 0.063 / 0.63 | 0.055 / 0.59 | 1.34 / 4.7 |
| Share of those frames TC acts | 50 % | 56 % | 0 % |
| 2nd gear from 50 km/h, 1.5 s flat out: rear slip mean | 0.036, TC never acts | the same | the same |
| Steady 0.86 g turn at 60 km/h in 2nd, then full throttle with the steering held: peak body slip | 7.4° | 2.3° | 89.5° (a spin) |

What this shows, within these runs:

- **The order is right where the car is near its limit.** In a corner, 2 holds the tail to about
  2°, 1 lets it step out about 7°, and OFF spins when the steering is held (a driver would
  counter-steer; this run does not). That matches "progressively higher levels of control system
  intervention" [FB10].
- **In a straight line on dry slicks, TC matters only in 1st.** From 50 km/h in 2nd the rear tyres
  never pass 0.06 slip, in every position.
- **OFF's wheelspin costs almost nothing.** It spins the rears at a mean slip ratio of 1.34 and is
  only 0.08 s slower to 50 km/h and 0.01 s to 100 km/h. The reason is the slick's curve in the
  config: past its peak it keeps 0.78 of the peak drive at a slip ratio of 1, and 0.82 of the peak
  cornering force at 45° of slip angle (curve table in the tool output). One first-hand source says
  a professional is as fast on OFF as on 1 [HFO], which points the same way, but no source gives the
  real cost of wheelspin on these tyres.
- **Position 2 launches quickest in the dry.** Its TC threshold (0.08) sits exactly on the slick's
  peak slip (0.08), while 1's (0.12) sits past it, so 2 is the better slip controller on a dry
  launch (0.08 s to 100 km/h) even though it intervenes more. Real dry-launch behaviour per
  position is not published.

## What I would change, and why (not changed)

Physics changes need the owner's Play test, so none of these is made. In order of evidence:

1. **Nothing in the straight-line set.** 0-100 is inside the only bound, the gear tops follow the
   ratios within 1.2 %, and the shift points are the configured ones. No sourced number contradicts
   any of them.
2. **Braking: no change from this review; it depends on #128.** From a true 100 km/h the DR458
   stops in 26.8 m at a mean 1.47 g, under the "about 1.6 g on slicks" its calibration spec
   estimates (24.5 m ± 2, measured from 95.4 km/h). No sourced figure exists for the Challenge,
   so this is a gap against an estimate, not against the car. #134 fixes `DriveSim.brake` and
   measures the same 26.81 m; the choice is the owner's.
3. **Keep the high-speed lateral grip, unless the owner finds the car too planted at speed.** It is
   5 to 10 % over the only documented figure, but that figure is for the car without the Evo's aero.
   If the owner wants less, the lever is the estimated downforce (`aero.liftArea` 1.0), not the
   tyres, which are right at low speed.
4. **Top speed is the softest number.** Both levers are estimates: drag area 0.85 m² and the
   downforce, whose load also raises rolling resistance. Inferred from the config: at 301.6 km/h
   aerodynamic drag is about 81 % of the resistance and rolling resistance about 19 %. The
   unverified claims sit higher, and a lower downforce would raise the top speed and lower the
   high-speed lateral grip together, which moves both checks toward their references. Not worth
   changing without a sourced Evo top speed or drag figure.
5. **Position 2's TC threshold, low priority.** If 2 should be the cautious setting in every
   condition, its slip threshold would sit under the slick's peak (below 0.08) and 1's at or just
   past it. The effect on a dry launch is 0.08 s. A spec would pin it: "2's dry launch is no quicker
   than 1's, and 2's body slip in the power step stays under 1's".
6. **The slick's post-peak fall-off, held for the drift decision.** The curve keeps 77 to 82 % of
   its peak far past the limit, which is the bottom of the generic road-tyre range note 01
   estimates (75 to 90 %, "road tyres fall less than slicks", an inference there), and note 01
   cites Assetto Corsa EVO's slicks dropping harder past the limit. A lower sliding share would
   make wheelspin and slides cost more,
   and slides snappier. That is exactly the knob a drift mechanic leans on, so it belongs to the
   drift plan (#124), not to a separate change now.

## Checking the tool

The tool reads the car's config and changes nothing. To show its numbers come from the car and
not from the tool, two deliberate breaks of the config were run and restored
(`mutation_run.txt`): a 4.5 final drive in place of 5.14 raised every gear's speed by 14.3 % (14.2 %
predicted), and a lateral peak friction of 1.50 in place of 1.73 cut the skidpad's grip by 11.5 %
(13 % predicted; load sensitivity and the balance absorb part of the cut). With the file restored,
the output is identical to `tool_output_60fps.txt`.

## Not verified

- Feel, in Play. These are offline runs on a flat, uniform-grip track, a plane with massless wheels;
  the Roblox glue was not run.
- Any real Challenge or Evo figure for 0-200 km/h, top speed, braking distances, downforce, drag,
  tyre curves or TC calibrations: none was found (12, gaps). The road 458's 0-200 km/h of 10.4 s
  was seen only in search summaries.
- The power-step spin in OFF is open loop: the steering is held, so it shows that full throttle at
  0.86 g breaks the rear loose, not that a driver could not catch it.
- Wet behaviour: every run is at grip 1.

## Sources

- [F09] Ferrari 458 Italia release, 28 July 2009, reprinted at
  https://www.automotiveaddicts.com/5830/ferrari-officially-announces-the-458-italia (fetched
  2026-10-31: "0-100 km/h acceleration in under 3.4 seconds and a maximum speed in excess of
  325 km/h"; "100-0 km/h braking distance to a mere 32.5 metres"; dry weight 1,380 kg).
- [MR] https://mitorosso.com/458-challenge/ (fetched 2026-10-31: "Less than 3,4 sec." for 0-100 km/h,
  "up to 1.6G"; no 0-200, top speed or braking; the table names no source).
- [FB10], [HFO], [B16]: as listed in `docs/research/12_dr458_challenge_evo.md`.
