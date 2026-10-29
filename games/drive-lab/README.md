# Drive Lab

A private driving study: one real car, the Lamborghini Aventador SVJ, modelled the way serious
sims model a car and ported to Roblox, plus an R6 character that walks, runs and drives it.
Nothing here is published. Research and plans: `research_notes/Drive lab/` in the main kit
checkout (`00_PLAN.md`, `11_ROADMAP.md`, reports 01 to 10).

## How it fits together

| Layer | Where | What it does |
|---|---|---|
| Units | `src/shared/Units.luau`, `Config/World.luau` | studs ↔ metres, mass units ↔ kg; real gravity (9.81 m/s² in studs) so car data needs no scaling. The world is `WORLD_SCALE` (1.5) times Roblox's: cars are scaled up at rig time and a stud is 0.28 / 1.5 m, so the physics still sees the real car |
| Physics core | `src/shared/Vehicle/*`, `Config/Cars/SVJ.luau` | pure Luau, Lune-tested: tyres, suspension, engine, 7-speed gearbox, AWD, brakes, ABS/TC/ESC, aero, steering, input help. SI units |
| Car rig | `src/shared/Car/CarRig.luau` | turns the imported model into one mass box with the car's real mass and inertia, everything else welded on massless, wheel mounts, collision shell, seat |
| Runner | `src/shared/Car/VehicleRunner.luau` | each frame: wheel raycasts → physics model → one force and one torque. Runs on the driver's client while driving, on the server while the car stands empty |
| Server cars | `src/server/Services/Cars.luau` | rigs tagged cars, seats drivers, hands over network ownership, keeps driven cars inside a speed envelope, makes seated drivers massless |
| Driving | `src/client/Controllers/Driving.luau` | input → runner; publishes SpeedKmh, Rpm, Gear, G and the rest as attributes for the camera and HUD |
| Test road | `src/server/Services/Track.luau`, `Rules/TrackPath.luau`, `Config/Track.luau` | an endless road laid as terrain ahead of every player and cleared far behind, from a seeded path (straights and bends no tighter than 120 m); asphalt road, grass verges, lane lines; a concrete pad replaces the baseplate |
| Cluster | `Controllers/Cluster`, `Config/Cluster.luau`, `Rules/Cluster.luau` | the SVJ's own cluster face on a screen over the model's static one: rev cells lighting with the revs (red from 8500, flashing on the limiter), gear, speed, drive mode, TC/ABS, a start-up sweep. Made by `tools/assets/cluster_layers.py`, see `docs/pipelines/HERO_CAR.md` §7 |
| Driver arms | `Controllers/DriverArms`, `Rules/ArmIK.luau`, `Config/DriverArms.luau` | while seated, the avatar's blocky arms are hidden and custom arms drawn: hands on the rim at a quarter to three, following the wheel up to 110°, elbows placed by a two-bone reach. Every client draws every driver's arms. Hands: CC0 meshes posed around the SVJ's rim by `tools/blender/hand_grip.py`, tinted with the avatar's arm colour, stored in the place at `ReplicatedStorage.DriveLabAssets.Hands`. Sleeves modelled by `tools/blender/driver_sleeves.py`, with a cuff on each hand along its own axis |
| Street lamps | `Rules/StreetLamps.luau`, `Services/Track` (placing), `Controllers/StreetLights` (lighting) | Victorian double lamps modelled from the owner's photo (`tools/blender/street_lamp.py`), scattered on both verges, lit warm from dusk to dawn with real-height pools of light |
| Roadside | `Rules/Roadside`, `Rules/Scatter`, server `Roadside` (laid by `Services/Track`), `Config/Roadside.luau` | Italian two-lane road furniture modelled from the rules (`tools/blender/roadside_props.py`): white delineator posts about every 50 m (red reflector to your own side's traffic, white to the oncoming), W-beam guardrail stretches whose posts are jittered off the 2 m grid, buried flared terminals, a portal sign gantry about every 1.2 km; patches, tar-sealed cracks, skid marks, stains and drip lines on the asphalt as decals (`tools/assets/roadside_textures.py`). Seeded per road position and irregularly spaced, so nothing strobes; laid and cleared with each chunk. Pipeline: `docs/pipelines/ROADSIDE.md` |
| Reflectors and lamp glints | `Controllers/Reflectors`, `Effects/ReflectorDots`, `Rules/Reflectors`, `Config/Reflectors.luau`; `Effects/LampGlints`, `Rules/LampGlints`, `Config/LampGlints.luau` (driven by `Controllers/StreetLights`) | at night the reflectors light in the driven car's headlights, the nearest as small glow dots so the row of posts recedes as red and white points; each of the 8 nearest lit lamps in view gets a faint level flare (the owner's ChatGPT texture, additive) and, on a wet road, a streak of reflected light on the line from the lamp to the eye, scaled by `Wetness` and none when dry |
| Car lights | `Controllers/CarLights`, `Effects/CarLamps`, `Rules/CarLights.luau`, `Config/CarLights.luau`, `SVJModel.cabinLight` | the SVJ's lamps as the real car's (sources in the config): the light mesh cut into each lamp and its glass into windows and clear lamp covers (`tools/blender/split_lights.py`, `docs/pipelines/HERO_CAR.md` §8). Dark until the ignition is on; Y running lights, dimmed with the headlights and out on the indicating side; one bi-xenon projector per side with its beam (automatic at night or in heavy rain; H cycles auto/on/off), and the high beam on J (a farther beam, the lens brighter; the HUD's light turns blue); seven-cell front indicators and amber rear cells flashing 90 a minute from the moment they are switched on (X / C); Y tail lamps with the headlights, five times brighter as brakes with the high stop strip; clear reversing chevrons; markers and plate lamps; the cabin light in the roof console (L, or hold D-pad down). Each lamp glows brighter by day than at night |
| Exhaust flames | `Effects/ExhaustFlames`, `Config/ExhaustFlames.luau` | each pop of the engine sound fires flames from the two outlets: a blue-orange jet, a fireball and a flash of light, with the Assetto Corsa mod's own textures and outlet positions |
| Rim blur | `Controllers/RimBlur`, `Rules/RimBlur.luau`, `Config/RimBlur.luau` | at speed the rims blur, as Assetto Corsa swaps in blurred rim meshes. Each wheel of the export is split into its rim face (spokes, hub, lip) and the rest (`tools/blender/rim_blur.py`); the face is rendered front-on and averaged over every rotation into a disc's colour, alpha, metalness and roughness (`tools/assets/rim_blur_maps.py`). From 15 to 35 rad/s of wheel spin (about 17 to 41 km/h) each wheel is swapped on this client for the pieces, the sharp face fading out as the blurred disc fades in: the SVJ's ten-spoke rim would look still at 37.7 rad/s at 60 FPS. Spin from the chassis speed and the tyre radius, so every car blurs on every client. Pieces in the place at `ReplicatedStorage.DriveLabAssets.RimBlur` |
| Tyre smoke and air debris | `Controllers/DrivingEffects`, `Effects/TyreSmoke`, `Effects/AirDebris`, `Rules/TyreSmoke.luau`, `Rules/AirDebris.luau`, `Config/TyreSmoke.luau`, `Config/AirDebris.luau` | smoke from a tyre whose contact patch slides past peak grip (combined slip 2.2 to 4.5 over the peak) and fast (2 to 10 m/s), read from the `TyreSlip*`/`TyreSlide*` attributes Driving publishes; it builds as the tread heats, none on a wet road (CarWater's spray takes over) or from a wheel in the air; light-grey puffs lit by the scene, left in the world to rise and hang. From 80 km/h, a few specks of dust, grit and the odd leaf (droplets when wet) at rest in slabs of air beside and above the car's path ahead, which the car's own motion brings past; the wake lifts the odd leaf and chip on a dry road. Textures: the owner's ChatGPT sheets cut by `tools/assets/vfx_cells.py` |
| Controls screen | `Controllers/ControlsHelp`, `Ui/ControlsPanel`, `Rules/ControlsHelp.luau`, `Config/ControlsHelp.luau` | every control grouped (on foot, getting in and out, driving, gearbox and modes, assists, lights, cameras, HUD) with its keyboard and gamepad inputs read from `Config/Controls`, and an (i) whose one plain sentence shows on hover, tap or gamepad selection. K or a tap of B opens it, a button on touch screens; a hint names the key after the first spawn and the first time seated. `tests/ControlsHelp.spec.luau` fails when a control has no row, label or sentence |
| Driving HUD | `Controllers/Hud`, `Rules/Hud.luau`, `Config/Hud.luau` | the owner's ChatGPT design as a frame image, live parts drawn over it: ten rev segments of a thousand rpm (red past 8500, flashing blue there in manual), mode, TC/ABS, A/M and gear, speed, headlight icon, indicators. Bottom centre, bottom right in the cockpit; U cycles full, minimal (smaller), off. Pipeline: `docs/pipelines/DRIVING_HUD.md` |
| Driver assists | `Rules/DriverAssists`, `Config/DriverAssists`, `Config/Cars/SVJ` (`modes`), in `Controllers/Driving`, `Hud`, `Cluster` | ABS, TC and ESC run by the drive mode's thresholds (Strada tightest, Corsa on its line, Sport the slackest, as the SVJ's are); G held 3 s switches ESC and TC off (ABS stays), a press switches them back on, and every new drive starts with ESC on. The cluster lights ESC OFF under the gear and flashes ESC while it acts; the HUD's TC turns red while off. `tools/assists.luau` prints the launches, stops and slides per mode |
| Getting in and out | `Services/CarEntry` (server), `Controllers/CarEntry`, `Controllers/EntryView`, `Rig/ClipPlayer`, `Rules/CarEntry`, `Config/CarEntry`, `Car/CarState`, `Car/DoorMark` | The server is the only writer of each car's entry, door and engine state (attributes on the car); every client derives the same clip, door angle, start-up and revs from it on the server's clock. E at the door: the avatar walks in facing the car and settles on the door mark in at most 0.2 s; the server then shrinks it to the seated size at once, in the same step that seats it, and the entry plays as one continuous sequence (door, sill, slide in, door pulled shut). R starts the car (hands, brake, red flap, START, crank). Held E gets out, ending standing 1.3 studs clear of the body; held while the door is moving, it waits for the door to stop and goes then if still held (the server refuses an exit while the door moves). Seated, L3 is the door only, never the on-foot sprint. Driving stays parked until the engine runs. Clips from the R6 Blender pipeline through the upload guard (`docs/pipelines`); decisions on #8, #9, #39, #40 |
| Weather audio | `Controllers/WeatherAudio`, `Rules/WeatherAudio.luau`, `Config/WeatherAudio.luau` | rain that builds and fades with `RainIntensity` (light loop crossfading to heavy), muffled outside plus roof drumming in the cockpit, distant thunder in heavy rain, tyre spray by speed and `Wetness`. One uploaded pack, each sound a region of it; cut by `tools/audio/cut_weather.py`, previewed by `tools/audio/render_weather_preview.py`. Sources CC0 (BigSoundBank; Mixkit's rain failed Roblox moderation) |
| Road audio | `Controllers/RoadAudio`, `Rules/RoadAudio.luau`, `Config/RoadAudio.luau` | while driving, the wind and the tyres' roar rise with speed: the wind on a square law through a low-pass opening from 500 Hz at 50 km/h to 8 kHz at 350 km/h, the roar with speed^1.5, louder and brighter on concrete and paving, a dull rumble on grass (a ray under the car four times a second); in the cockpit the wind is muffled more than the roar. The engine stays at least 6 dB on top at every speed. Built on the audio API (`AudioFilter`), one uploaded pack, each loop a region of it; cut by `tools/audio/cut_road.py`, previewed by `tools/audio/render_road_preview.py`. Sources CC0 (BigSoundBank 1450 wind, 3097 a car cabin at 90 km/h; a Freesound wind failed Roblox moderation) |
| Motion blur | `Controllers/MotionBlur`, `Rules/MotionBlur.luau`, `Config/MotionBlur.luau`; near blur in `Atmosphere/Optics` | a blur that grows with how fast the camera turns (measured inside the car while driving, so only looking around blurs, never the car's yaw), and in the chase view the road between camera and car blurred from 80 km/h, the car kept sharp. Roblox has no per-pixel motion blur; this is built from BlurEffect and the one DepthOfFieldEffect |
| Camera vibrations | `Rules/CarShake.luau`, `Config/CarShake.luau`, in `Controllers/CarCamera` | fine road vibration rising with speed, engine rocking under throttle at low speed, a rumble on hard launches, a pitch kick on each upshift (dip then squat, harsh in Corsa, soft in Strada); stronger in the cockpit, little in the hood view; smooth noise round the camera's place each frame, never a lag |
| Car cameras | `Controllers/CarCamera`, `Controllers/ChaseView`, `Rules/CarCamera.luau`, `Config/CarCamera.luau` | V cycles chase, cockpit and hood. The chase is Assetto Corsa's: hung 3.3 m behind and 1.2 m above the rear axle, aimed 4 m ahead and 2° up, rigid in yaw, riding the body's pitch, never rolling; its only smoothing is a shift with the g (0.2 m/g back, 0.4 m/g out of a turn, 0.23 s half-life), and an optional yaw spring, off. Field of view 60° chase, 60° cockpit, 70° hood, with no speed term: it widens 18° per g of pull (up to 15°, the cockpit and the hood a quarter of that; 12° per g up to 10° until 2026-10-29), toward the highest pull of the last 0.25 s, so a gear change never makes it breathe. Framing measured on the model at the earlier 12° per g: the car 0.57 frame heights wide cruising, 0.49 at full throttle at 170 km/h (`docs/evidence/camera-chase`); `tools/chase_camera` prints the field of view through the upshifts |
| Character | `Controllers/Locomotion`, `Rules/Sprint.luau`, `HeadLook`, `BodyLean`, `CameraFeel` | walk/run/sprint (Shift held, or L3 toggled on foot), the head following the camera, the lean, the sprint FOV |
| Weather key | `Atmosphere/init` (`stepWeather`), `Atmosphere/WeatherLabel`, `Rules/WeatherCycle.luau`, `Config/Atmosphere.luau` (`WEATHER_KEY`) | the game starts on a clear day; N steps through clear day, rain by day and rain at night, each blended in over 10 s, its name shown for 2.5 s. Overcast is left to the Studio-only developer panel (owner, 2026-10-29: no foggy default) |
| Rain | `Atmosphere/Rain`, `RainEmitters`, `Rules/RainRings`, `Rules/RainStreaks`, `Config/Atmosphere.luau` | two rings of streaks round the camera, about 2–4 m and 4–10 m (in the car views the outer one reaches 6 m further ahead, through the headlights), then only the Atmosphere's haze. Streaks stay where they fall in the world, straight down with a light constant wind lean, whatever the car does, each entering its column at the top and dying at the road; the space round the camera (or the car in the cockpit and hood) reaches ahead as far as the camera travels in a streak's life, so none crosses the lens or the cabin. Lit by the scene per particle; the look sets their colour and, by night, additive blending. Sprites from the owner's rain pack, sized by Size and Squash (measured). Splash crowns and, on a wet road, flat ripples on boxes over the road ahead. Ceilings 100/150/400 per emitter, 400/1000/2000 live |
| Rain on the car and camera | `Atmosphere/CarWater`, `Lens`, `Optics`, `Rules/CarWater`, `LensDrops`, `RainOptics`, `RainHaze`, `Atmosphere/Windshield`, `Rules/WindshieldDrops`, `SVJModel.windshield` | crowns on the bonnet, roof and engine cover, spray and mist off the rear tyres; lens drops (not in the cockpit), a contact blur under 0.35 px, a light far depth of field; Atmosphere density from the rain's real visibility; in the cockpit, drops on the windscreen, bound to the glass in its own plane, clinging then sliding (up the glass past about 46 km/h); `Windshield.wipe` is the hook for wipers |
| Cockpit glazing | `Controllers/CockpitGlazing`, `Config/CockpitGlazing.luau`, `SVJModel.glazing` | in the cockpit view the windows become see-through plastic on this client: Glass draws no particles behind it |

Wiring a new car: a physics config (`Config/Cars/<Car>.luau`), a model binding
(`Config/Cars/<Car>Model.luau`: wheel and caliper part names, seat point), one line in
`Config/Cars/Catalog.luau`, and in Studio the `DriveLabCarSpawn` tag plus a `Car` attribute on
the model.

## Checked numbers

The physics core, offline at 60 FPS (`lune run games/drive-lab/tools/calibrate`):

| | Real SVJ | Ours |
|---|---|---|
| 0–100 km/h | 2.8 s | 2.88 s |
| 0–200 km/h | 8.6 s | 8.49 s |
| 100–0 km/h | 30 m | 30.8 m |
| Top speed | over 350 km/h | 354 km/h |
| Skidpad | 1.10 g | 1.09 g |

The same within 2 % at 30, 60, 120 and 240 FPS, and about 0.23 ms per frame. Calibration
judgements and open gaps are in the commit that added it.

## Controls

| | Keyboard | Gamepad |
|---|---|---|
| Walk / sprint | WASD / hold Shift | stick / click L3 |
| Get in | E at the driver's door | X at the prompt |
| Get out | hold E (0.35 s, near a standstill) | hold B |
| Door | F (at the door outside, or seated) | Y at the prompt, L3 seated |
| Start the engine | R (seated, door shut) | A |
| Throttle / brake | W / S | RT / LT |
| Steer | A / D | left stick |
| Handbrake | Space | X |
| Paddles | E up, Q down (at a standstill Q goes to neutral, then reverse) | RB / LB |
| Auto / manual | T | Y |
| Strada / Sport / Corsa | M | D-pad up |
| ESC and TC off / on | hold G 3 s / press G | hold View |
| Camera view (chase, cockpit, hood) | V | click R3 |
| Look around | hold right mouse button | right stick |
| Cockpit seat | mouse wheel forward/back, Shift + wheel up/down | |
| Headlights (auto, on, off) | H | tap D-pad down (auto, on, high beam, off) |
| High beam on / off | J | a step of the D-pad down cycle above |
| Indicators left / right | X / C | D-pad left / right |
| Cabin light | L | hold D-pad down (no pad button is free while driving) |
| HUD full / minimal / off | U | |
| Controls screen (every control, with an (i) on each) | K | tap B (under 0.25 s; holding B stays the exit) |
| Weather: clear day, rain by day, rain at night | N | |

The controls screen is generated from `Config/Controls` and `Config/ControlsHelp`, and on touch
screens opens from the question-mark button at the top right.

## Running it

Gates from the repo root: `stylua --check games kit tools`, `selene games/drive-lab/src`,
`lune run tools/test/run`, and the luau-lsp check in CI. Sync into the test place with
`tools/studio/dev.luau` (serve the repo on localhost:8765, then
`require(m).sync("games/drive-lab")`; a second sync must write 0). The owner playtests feel
changes: sync, then hand over.

## Owner decisions

| Date | Decision |
|---|---|
| 2026-10-27 | R6 avatars (set in Game Settings). |
| 2026-10-27 | Head follow and body lean are scripts, not part of the animations. |
| 2026-10-27 | Head: looking at yourself must not snap. It uses the sideways sine of the look, the usual R6 approach, and trails the camera slightly. |
| 2026-10-27 | Lean follows velocity and never swings past upright when you let go. The earlier lean followed acceleration and rocked. |
| 2026-10-27 | Walk: no vaulting bob ("bouncing") and no sideways roll ("waddling"); visible stepping, expressive arms, a weighted contact. 12.5 studs/s, one stride a second; feet slide, as in Roblox's own R6 walk. |
| 2026-10-27 | Run: the TikTok reference's hold-and-snap style; sprint 26 studs/s. |
| 2026-10-27 | The run's wind swirl effect is off. |
| 2026-10-27 | Sprint widens the FOV (70 → 80). |
| 2026-10-27 | Feel is judged in the owner's playtest, not by measurements. |
| 2026-10-27 | The car is scaled up so an R6 avatar fits, as a coherent world scale: the physics still sees the real car. 1.5×; the owner found 1.75× the right fit inside but too big outside, so the world stays 1.5× and the seated driver is scaled to 1.5 / 1.75. |
| 2026-10-27 | The body's squat and dive under throttle and braking is the real load transfer; roll in corners is barely visible because an SVJ is very stiff in roll. |
| 2026-10-27 | An endless, generated test road. |
| 2026-10-27 | Walk: the torso turns with the arms (R6 has one block for pelvis and shoulders); turned with the legs, the arms looked reversed. |
| 2026-10-27 | No camera smoothing, on foot or in the car: the views follow the mouse and the car exactly. The one eased motion is the view returning to the front after looking around. |
| 2026-10-27 | The automatic gearbox steps down while you brake (from 300 km/h it is in 4th by 95 km/h), and at full throttle every mode holds each gear past the 8500 rpm redline (8600, Corsa 8650), so the rev counter lights its red before each upshift. |
| 2026-10-27 | The cluster is the real SVJ face, the mod's 512 × 256 texture, kept as the final image and animated (owner's call: "ça suffit comme image finale"). Only the Corsa face exists; the lit cells and the mode name take each mode's colour. |
| 2026-10-27 | Driving, the head stays still: the cockpit view is fixed in the car and the seated character's head faces ahead whatever the camera does. Only the arms move, on the wheel. |
| 2026-10-27 | Custom arms that grip the wheel, one model for every player (no male/female variants), skin colour from the avatar, black sleeves. |
| 2026-10-27 | The engine sound is approved as it is ("j'adore le son"). Off the throttle, Sport and Corsa keep their gear (Strada still shifts up), so a lift at speed pops instead of clunking up to 7th. |
| 2026-10-27 | Street lamps like the owner's photo, a little scattered, with realistic light; solid posts. |
| 2026-10-27 | Car lights: headlights automatic by default (H: auto, on, off), indicators on X and C (the same keys on AZERTY). The other players' cars show only their headlights: their brake and indicator state is not sent to other clients yet. |
| 2026-10-28 | A driving HUD after the racing games, style 1 (clean, GT7-like) first for the owner to test. The cockpit seat is the player's: mouse wheel forward/back, Shift + wheel up/down. |
| 2026-10-28 | The steering wheel sits 2 cm higher on its column so the cluster shows through the rim (the owner asked for about 1 cm up; the sight-line check put the cluster's top edge inside the rim tube, and 2 cm clears it). The HUD's look will be redone with ChatGPT; its layout and placement stay. |
| 2026-10-28 | The HUD is the owner's ChatGPT design, cut into a frame and live parts (`tools/assets/hud_layers.py`); the rev bar fills a segment per thousand rpm. |
| 2026-10-28 | The chase camera after Assetto Corsa's, from the owner's SVJ reference frames: the view widens under acceleration only, holds through a gear change, never widens with speed. Smoothing is allowed on the chase view (the 2026-10-27 rule was for the default camera); what is smoothed is stated in `Config/CarCamera.luau`. |
| 2026-10-28 | The cockpit's field of view narrows to the sims' 56–60° (60° set: from the default seat, 56° put the cluster against the frame's bottom edge); the eye and the seat adjustment stay as the owner set them. |
| 2026-10-27 | Rain, blur and the weather: built here from ChatGPT's atmosphere brief; the car camera is ours too. |
| 2026-10-28 | Car lights after the real SVJ (#41): the Y running light goes out on the side whose indicator flashes; the bumper's side marker stays steady (the EU car); a high beam on its own control (J; on the pad, a step of D-pad down's cycle). |

Asset pipelines (how the walk, the car and the effects were made): `docs/pipelines/`.
