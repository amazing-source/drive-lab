# Drive Lab roadmap

Written 2026-10-27, after the car import. Each step ends with something checkable. "Agent" means
a sub-agent I brief and review; every change still gets two adversarial breakers before merging.
"ChatGPT" means the owner asks ChatGPT for something only it can give (watching a video, feel
descriptions, concept images). "Codex" is the UI/VFX/camera partner named in the brief.

## Open question for the owner

- **Who does rain, spray, blur, post-processing, HUD and the presentation camera?** The brief
  gives them to Codex; on 2026-10-27 the owner asked me to work on rain, blurry vision and
  camera work. Until the owner says otherwise: I build the camera rig and the effects plumbing
  (states, attachments, a wetness value, a clean interface), and leave the final look to whoever
  the owner names.

## Defaults I am applying (the owner can overrule any of them)

- **Gravity:** this place's `Workspace.Gravity` = 35 studs/s^2 (9.8 m/s^2 at 0.28 m per stud),
  so real spring, tyre and mass data work unscaled. Set in one config value.
- **R6 avatars**, at the owner's request (Game Settings, Avatar). First-person hands are built for
  R6 arms.
- **Gearbox:** automatic by default, paddles for manual shifts, as on the real car (no clutch
  pedal).

## Status (2026-10-27, evening)

- Phase A done on `feat/drive-lab` (not committed yet): project, `Units`, `Config/World`
  (gravity), CI extended (lint, types, build for drive-lab; the Lune tests already run every
  game), Studio sync through `tools/studio/dev.luau` (second pass writes 0).
- Phase B1 handed to an agent (pure physics modules + offline DriveSim + calibration specs).
- Phase C2 head-follow done and checked on a live client: head turns toward the camera,
  stops at the neck limits, angles replicate through the server. Other players' easing not yet
  tested (needs a 2-player test).
- Found: every spawned avatar runs on kinematic AnimationConstraints, not Motor6Ds, and their
  C0 is read-only. All procedural motion (head, walk cycle, hands) writes `Transform` in
  PreSimulation.
- R6 cannot be set by script (`StarterPlayer.GameSettingsAvatar` is locked to Roblox's own
  code): it is one click in Game Settings, Avatar.

## Phase A: project and pipeline

1. `games/drive-lab` in rbx-game-kit on branch `feat/drive-lab`: Rojo project, `src/server`,
   `src/client`, `src/shared`, a `Config/Cars/SVJ` module holding the real data
   (`02_aventador_svj_data.md`).
2. CI: the kit's existing workflow (stylua, selene, Lune tests, rojo build) extended to the new
   game. Light, no new tooling.
3. Studio sync into the test place, the way the release worktree already does it (packed
   sourcemap + scripted sync, second pass must write 0).

## Phase B: the car drives (physics core)

1. Pure, Lune-tested modules (agent): units, tyre (slip, load sensitivity, combined slip,
   relaxation length, low-speed handling), suspension (spring, bump/rebound damping, bump stops,
   anti-roll bars), engine (torque curve, inertia, limiter, engine braking), 7-speed gearbox with
   the 3.52 effective final drive and torque-cut shifts, AWD coupling and rear LSD, brakes with
   bias, ABS/TC/ESC acting on physical quantities, aero (drag from the EPA CdA, downforce),
   steering (speed-sensitive, rear-wheel steering), wheel spin integrated in sub-steps.
2. Engine glue (me): per-wheel casts, forces summed into one VectorForce and one Torque at the
   centre of mass, driver-owned physics with server plausibility checks, the seat, telemetry v1.
3. Calibration against the measured targets: 0-100 km/h 2.8 s, 100-0 km/h 30 m, top speed
   in 7th near 7,970 rpm, skidpad, rest without drift, 30/60/120 FPS consistency.

## Phase C: the player (R6)

1. R6 avatars; realistic walk, run and sprint. Creator Store R6 packs only carry `Animation`
   objects pointing at other creators' uploads, which do not play in our experience. Proposed
   instead: a procedural gait driven by real gait data (hip and shoulder swing, torso bob and
   lean as functions of the stride phase), stride phase from distance travelled so feet never
   slide, walk/run/sprint blended by speed, run on every client for every character from its
   replicated velocity, so nothing to upload and nothing to replicate. Owner to choose.
2. Head follows the camera (neck rotation, replicated to others at a throttled rate).
3. Enter/exit the car, seated pose; first-person hands on the wheel (R6 arms, IK to grip points
   on the rim that turn with the wheel), skin colour from the avatar, the player's shirt or plain
   sleeves.

## Phase D: the car comes alive

1. Steering wheel cut out on its axis; paddles; wipers; doors if needed.
2. Lights system (low/high beams, DRL, brake, reverse, indicators) driving emissive strength and
   light objects; cockpit screens as surfaces fed by telemetry.
3. Engine audio: Assetto Corsa sound bank decoded (owner supplies the file) or Creator Store
   placeholders, layered by rpm and load, interior/exterior filtering.

## Phase E: look and atmosphere

1. Test world: a long straight, a skidpad, a braking zone, bumps, a wet strip (a test bench,
   not a map).
2. Camera rig: chase (damped follow, the reference's low/close framing), hood, cockpit with head
   movement, free look; all motion parameters exposed.
3. Rain, spray, wet look (paint, tyres, droplets), light blur where Roblox allows it, lighting
   presets matching the reference (tunnel warm, exterior cold). Owner of the final look: see the
   open question.

## When to ask ChatGPT

- After Phase B's first drive: describe the feel versus the reference video (the brief's FEEL
  section), so the calibration has a second opinion.
- Phase D/E: concept images if we need custom UI art or a texture we cannot source; icon sets.
- Any time a reference video needs watching with sound.
