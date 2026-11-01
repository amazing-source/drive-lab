# Asset pipelines

How to make each kind of asset to the same standard every time: the steps, the scripts, the
checks, and what went wrong before so it does not again. Each guide records the owner's
decisions on feel, which numbers alone did not predict.

| Guide | For |
|---|---|
| [R6 animation](R6_ANIMATION.md) | walk, run and any other R6 cycle: rig, keys, foot checks, renders, export, upload |
| [Hero car](HERO_CAR.md) | a downloaded car model to a debadged, PBR-textured, real-scale car in Studio |
| [DR458 checks](DR458.md) | the second car's measured checks: depth fighting, hidden-face clean-up, render diffs, the merged manifest, photo-matched cameras |
| [Flipbook effects](VFX_FLIPBOOK.md) | drawn particle effects fired from animation markers |
| [Driver hands](DRIVER_HANDS.md) | rigged hands posed around a car's steering-wheel rim, tinted per player |
| [Street lamp](STREET_LAMP.md) | a prop modelled from a photo, lit, and scattered along the road |
| [Roadside](ROADSIDE.md) | road furniture modelled from the rules, road-surface decals, their placement, and the night look (reflectors, lamp flares, wet streaks) |
| [Driving HUD](DRIVING_HUD.md) | a HUD design delivered as a picture, cut into a frame and live parts drawn over it |
| [Binnacle display](BINNACLE.md) | a car screen with pages, a segmented rpm band and shift lamps, from a design pack delivered as pictures |

Shared rules:
- **Scripts over hand work.** Every step is a script with its usage in its header, so a result
  can be rebuilt and a change re-run.
- **Check numbers before anyone looks.** Foot contact, triangle counts, alignment, texture
  sizes. Then the owner's playtest judges feel, which only a playtest shows.
- **Working files stay outside the repo** (`Downloads/drive-lab-assets/`); scripts and decisions
  go in.
