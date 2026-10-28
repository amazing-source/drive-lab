# Import from rbx-game-kit

Drive Lab was started on 2026-10-27 inside the owner's `rbx-game-kit` repository (branch
`feat/drive-lab`, worktree `rbx-game-kit-drivelab`), alongside the game Rob A Car And Escape. On
2026-10-28 the owner decided it should be its own project, so this repository was created from
that branch's commit `135d403` as one import commit. The old repository keeps the full history;
nothing there was rewritten.

What came across: `games/drive-lab/`, the shared `kit/` library and the vendored `packages/`
(copies, owned here from now on), the tools Drive Lab uses (`tools/anim`, `assets`, `atmosphere`,
`audio`, `blender`, `studio`, `test`), the asset pipeline docs (`docs/pipelines/`), the toolchain
and lint configs, and the agent skills `luau-standards` and `review-change`. Rob A Car And
Escape's code, tools and docs stayed behind.

Work that was in progress in the old worktree at the time of the import (roadside props and lamp
glints, wind and road audio with rim blur, tyre smoke and wind debris, car entry and start-up)
lands here as pull requests from the agents building it.

## The 43 imported commits (in `rbx-game-kit`)

| Commit | Date | Subject |
|---|---|---|
| `85340ff` | 2026-10-27 | Drive Lab: project skeleton, real-gravity units and head follow |
| `e8f7ba9` | 2026-10-27 | Drive Lab: body lean, head follow against the torso, and an R6 animation pipeline |
| `20287c5` | 2026-10-27 | Drive Lab: the SVJ's physics core, calibrated offline |
| `c36a11c` | 2026-10-27 | Drive Lab: the car drives in Roblox, plus walk, run and the run's wind-wrap |
| `14c8ed1` | 2026-10-27 | Drive Lab: head stops snapping, walk stops waddling, real-gravity jump |
| `1495d4c` | 2026-10-27 | Drive Lab: lean from velocity with no rebound, and a calmer walk |
| `8f3ebc0` | 2026-10-27 | Drive Lab: walk at Roblox's normal speed, no bob, more expression |
| `ec1ecc4` | 2026-10-27 | Drive Lab: a walk with weight, and the owner's 16-frame run swirl |
| `7101d23` | 2026-10-27 | Drive Lab: a walk that visibly steps, a smoothed on-foot camera, sprint FOV, run effect off |
| `bd41e27` | 2026-10-27 | Docs: asset pipelines and the Drive Lab README |
| `2e4b102` | 2026-10-27 | Format build_keyframes.luau (the CI format gate flagged it) |
| `08b21fb` | 2026-10-27 | Tools: the hero car pipeline scripts docs/pipelines/HERO_CAR.md walks through |
| `db57f60` | 2026-10-27 | Drive Lab: a 1.5x world so an R6 avatar fits the car; walk arms fixed |
| `9b8d8e7` | 2026-10-27 | Drive Lab: world scale 1.75 after the owner sat in the car |
| `f7ad03a` | 2026-10-27 | Drive Lab: lift the SVJ's body off its tyres by the measured overlap |
| `6e905e1` | 2026-10-27 | Drive Lab: an endless test road, and a smaller driver instead of a bigger car |
| `7a3a35f` | 2026-10-27 | Drive Lab: firmer Strada and Sport damping, and a straight test road |
| `eb89117` | 2026-10-27 | Drive Lab: publish shift, limiter, clutch and assist state for the car's sound; FSB5 extractor |
| `2037627` | 2026-10-27 | Drive Lab: driving cameras and a live instrument cluster |
| `5ff7b86` | 2026-10-27 | Drive Lab: the steering wheel turns with the steering |
| `16fdff4` | 2026-10-27 | Brake downshifts, Strada to the red, no camera smoothing |
| `6e1ddc3` | 2026-10-27 | Shift past the redline at full throttle; light red on entry |
| `dd35309` | 2026-10-27 | The real SVJ cluster face, animated |
| `85072ef` | 2026-10-27 | SVJ engine sound from the Assetto Corsa mod's bank |
| `526979e` | 2026-10-27 | Keep the driver's head still |
| `df92b80` | 2026-10-27 | Atmosphere, stage 1: weather presets, wet road, rain |
| `68a8890` | 2026-10-27 | Driver arms on the steering wheel, placeholder geometry |
| `383857c` | 2026-10-27 | Real hands gripping the steering wheel |
| `717312f` | 2026-10-27 | Document the driver hands pipeline |
| `1f6eb02` | 2026-10-28 | Modelled sleeves, wrist cuffs and a cockpit eye that sees the hands |
| `e3f524c` | 2026-10-28 | Offline engine-sound preview: scripted drive to a listening file |
| `4b14554` | 2026-10-28 | Hold the gear on a lift in Sport and Corsa; fix the preview's start-up level |
| `50f9feb` | 2026-10-28 | Victorian street lamps along the road, lit at night |
| `2ae91b6` | 2026-10-28 | Car lights: headlights, brake, indicators, reverse |
| `ca2286b` | 2026-10-28 | Exhaust flames on every pop, from the Assetto Corsa mod's textures |
| `caeb18b` | 2026-10-28 | Driving HUD (clean, GT7-like) and an adjustable cockpit seat |
| `b818f68` | 2026-10-28 | Raise the steering wheel 2 cm so the cluster shows through the rim |
| `cf06752` | 2026-10-28 | Driving HUD from the owner's design: frame image, live parts over it |
| `be90fe7` | 2026-10-28 | Weather audio: rain that builds, cockpit muffling, thunder, tyre spray |
| `b9a734e` | 2026-10-28 | Rain, stage A: streak sheets, splashes, slant with speed, car water, haze, lens |
| `324de9c` | 2026-10-28 | Motion blur: blur on fast camera turns, near blur on the road at speed |
| `3de0562` | 2026-10-28 | Camera vibrations and an acceleration FOV kick |
| `135d403` | 2026-10-28 | Rain, stage A2: the owner's rain pack, lit by the scene, no curtains or slant |
