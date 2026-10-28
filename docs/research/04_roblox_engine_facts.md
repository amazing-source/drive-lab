# 04: Roblox engine facts that decide the vehicle architecture

Researched 2026-10-27 using web search and the official docs only. Nothing here was run in Studio.
Per the house rule, a doc read is a hypothesis and a runtime test is evidence. Section 9 lists the
Studio tests that turn the load-bearing claims into evidence before phase 3.

Scope: the engine facts only. Vehicle dynamics theory is in `01`, the car data in `02` and the 3D
model in `03`.

**Tags used below**
- **[DOC]** official create.roblox.com page, read 2026-10-27
- **[ANN]** Roblox staff DevForum announcement (date given)
- **[COMM]** community post, not official
- **[INF]** my inference from the sources, not stated by them
- **[TEST]** must be checked in Studio before we rely on it
- **[BETA] / [ROLLOUT] / [NEW]** status flags

---

## Architecture decisions this implies (one page)

1. **Units: SI inside the model, converted at the Roblox boundary.** One stud is 0.28 m and one
   RMU is 21.952 kg [DOC units]. Car data arrives in SI, so the model stays in SI and one module
   converts to studs and Rowtons. **Gravity has to be a decision.** The default is 196.2 studs/s²,
   which is 54.9 m/s², about 5.6 g. The docs give 35 studs/s² as "realistic" [DOC units].
   With the default, real spring rates sag 5.6 times too far and tyre grip (μ·Fz) lets the car
   corner 5.6 times harder than the real one. My recommendation: keep `Workspace.Gravity` as it is
   for the rest of the game and add an upward compensation force of m·(g_world − g_car) to the car
   only, with `g_car` a tunable that defaults to 9.81 m/s². The alternative is to change world
   gravity and retune every character jump. That is the owner's call.

2. **Loop: the driver's client, in `RunService.PreSimulation`, once per frame, with internal
   sub-steps.** Scripts cannot run once per physics substep:
   - `PreSimulation` fires once per frame, and the solver "may step multiple times per frame"
     [DOC RunService].
   - The new fixed-rate `BindToSimulation` tops out at 60 Hz and needs `UseFixedSimulation`,
     which is still opt-in [ANN 2026-04-29].

   So the model takes the frame's `deltaTimeSim` and splits it into n = ceil(dt/h_max) equal
   sub-steps of about 1 ms. Inside them it integrates its own stiff states: wheel spin, engine,
   clutch, differential and tyre relaxation. It then writes one frame-average force and torque.
   Equal division of `dt` (rather than a carried accumulator) keeps model time equal to engine
   time every frame. Visual wheels update in `PreRender`. Server guards run in
   `PostSimulation`/`Heartbeat`.

3. **Forces: one `VectorForce` (World, at the centre of mass) plus one `Torque` (World), written
   every frame.** The per-wheel contact forces are summed into a net force and a net torque about
   `AssemblyCenterOfMass`.
   - A constraint force is held constant over all the solver substeps of the frame, so motion is
     smooth [DOC VectorForce: "constant force"].
   - An impulse is front-loaded once per frame.
   - Two property writes per frame are cheaper than moving four attachments.
   - Clamp `dt` against hitches. Zero both forces when the model is not running, because a
     constraint force persists if the script stops.
   - Optional, needs [TEST]: a force-limited `LinearVelocity` (Line mode, target 0, `MaxForce` =
     μ·Fz) for static grip at very low speed, because the solver handles it inside its own
     substeps.

4. **Contacts: one cast per wheel per frame, from the suspension top mount.**
   - Start with `Raycast`; move to a wheel-radius `Spherecast` for kerbs and gaps.
   - Shape casts ignore anything they start inside [DOC WorldRoot], so the origin must sit inside
     the car's own (excluded) hull.
   - `RaycastParams`: exclude the car and the characters, and set `RespectCanCollide = true` so
     decorative non-colliding parts are not treated as road.
   - Collision hull: one simple box or hull part whose underside clears the road at static ride
     height. Native collision then only catches bottoming-out, walls and crashes.
   - Visual wheels: `CanCollide`, `CanQuery` and `CanTouch` all false, and either `Massless` or
     client-local anchored parts placed with `BulkMoveTo`.
   - Set `Workspace.PhysicsSteppingMethod = Fixed` (240 Hz for everything). `Default` currently
     resolves to `Adaptive` [DOC enum], and the docs name racing games as the case for Fixed
     [DOC adaptive timestepping].

5. **Network: client-owned car with server plausibility guards now. Keep the model core
   host-agnostic so it can move to Server Authority later.**
   - The server calls `SetNetworkOwner(driver)` when the seat's `Occupant` changes, as the docs
     example does [DOC network ownership].
   - On exit, keep ownership with the last driver until the car is at rest, then hand it back.
     Ownership changes "may result in jittery physics" [DOC].
   - Server Authority went to full release on 2026-07-09 [ANN] and is the long-term answer to
     cheating. But:
     - it requires `NextGenerationReplication` (still Beta), `StreamingEnabled`, deferred signals
       and InputActions for every input, which means a whole-game conversion;
     - staff report drift in constraints and BodyMovers from position and velocity quantisation
       [ANN 2026-05-08];
     - a staff comment suggests collision-heavy racing with server-authoritative cars may need 20
       or fewer players [ANN thread 2026-04-30];
     - vehicle entry with auto-prediction was a known crash at Client Beta [ANN 2026-04-30].

   Write `Model.step(state, input, contacts, h)` as a pure function. It then runs unchanged in
   `PreSimulation` today, in `BindToSimulation(Hz60)` later, and offline in Lune for tests.

Why this set: it is the only combination that is supported today on every platform, gives the
driver zero input latency, and keeps the stiff tyre and wheel physics stable at 30 FPS (see the
numbers in 2.6). Nothing in it depends on a beta.

---

## 1. Units

### 1.1 Official conversions [DOC units]

The physics engine "does not use unit conversions" internally. These are Roblox's convention.

| Quantity | Roblox | Metric | Exact factor (derived from the two base units) |
|---|---|---|---|
| Length | 1 stud | 0.28 m | 1 m = 3.5714 studs |
| Mass | 1 RMU | 21.952 kg | 1 kg = 0.045554 RMU |
| Time | 1 s | 1 s | n/a |
| Force | 1 Rowton (= RMU·stud/s²) | 6.14656 N | 1 N = 0.16269 Rowton (doc: 0.163) |
| Torque | 1 Rowton·stud | 1.72104 N·m | 1 N·m = 0.58105 (doc: 0.581) |
| Spring stiffness | 1 Rowton/stud (= RMU/s²) | 21.952 N/m | 1 N/m = 0.045554 (doc: 0.0456) |
| Damping | 1 RMU/s | 21.952 N·s/m | 1 N·s/m = 0.045554 (doc: 0.0456) |
| Velocity | 1 stud/s | 0.28 m/s | 1 m/s = 3.5714 studs/s (doc: 3.57) |
| Density | 1 RMU/stud³ | 1000 kg/m³ (water) | doc: water = 1 RMU/stud³ |
| Moment of inertia | 1 RMU·stud² | 1.72104 kg·m² | [INF] derived |
| Pressure | 1290 RMU/(stud·s²) | 1 atm | doc |

- **Gravity** [DOC units, Workspace]: default 196.2 studs/s² (54.936 m/s²). "Realistic" is
  35 studs/s² (9.8 m/s²; exactly 9.80665/0.28 = 35.02). `Workspace.Gravity` has Simulation
  Access and can be set from scripts (the docs sample sets it).
- **Physical limits** [DOC units, PhysicalProperties]: density 0.0001 to 100 RMU/stud³, friction
  0 to 2, elasticity 0 to 1, FrictionWeight and ElasticityWeight 0 to 100. Out-of-range values
  are clamped. Friction between two parts is a weighted average:
  (Fa·Wa + Fb·Wb)/(Wa + Wb).
- `Workspace.AirDensity` is in RMU/stud³ and is set for Y = 0 [DOC Workspace].

### 1.2 Worked example: an illustrative 1,600 kg car (not SVJ data; see `02`)

| Item | SI | Roblox |
|---|---|---|
| Mass | 1,600 kg | 72.89 RMU |
| Weight at real g | 15,691 N | 2,553 Rowtons (at 35.02 studs/s²) |
| Weight at default g | 87,898 N | 14,301 Rowtons (at 196.2 studs/s²) |
| Spring, one corner | 40 kN/m | 1,822 Rowton/stud |
| Damper, one corner | 4,000 N·s/m | 182.2 RMU/s |
| Engine torque | 700 N·m | 406.7 Rowton·stud |
| 300 km/h | 83.3 m/s | 297.6 studs/s |
| Static sag, 400 kg corner, 40 kN/m | 9.8 cm at 9.81 m/s² | 0.35 stud; **1.96 studs (55 cm) at default gravity** |

What this implies:
- Natural frequencies do not change with units (√(k/m) gives the same 10 rad/s in both systems),
  because time is in seconds in both.
- Anything multiplied by g changes: static sag, tyre load, μ·Fz grip and braking capacity. That
  is why decision 1 above is about gravity and not about units.

### 1.3 Mass is set through density

`AssemblyMass` is the sum of the parts' masses [DOC assemblies]. The BasePart text calls `Mass`
"read-only". You get a target mass by choosing `CustomPhysicalProperties.Density` = target mass /
hull volume. Example: 72.89 RMU over a 16 × 4 × 7 stud box (448 stud³) gives density 0.163, well
inside 0.0001 to 100.

Default materials would make a car-sized assembly far too heavy [INF]. For example, plastic's
0.7 over the same box gives 314 RMU, about 6,900 kg. So:
- every visual part is `Massless`;
- one hull part carries the mass.

`Massless` only takes effect if the part is welded to a part that has mass, and it is ignored on
the assembly's root part [DOC BasePart].

**Root part.** The root is chosen by these rules, in order:
1. anchored parts;
2. non-massless parts;
3. higher `RootPriority`, an integer from −127 to 127;
4. size, with bonuses for Seat and VehicleSeat [DOC assemblies, BasePart].

So set the hull's `RootPriority` high, or the VehicleSeat may become the root.

**Inertia.** I found no property to set an inertia tensor in the BasePart reference I read; it
comes from part geometry and density [INF, TEST]. Shape the hull or add mass parts to tune yaw
and pitch inertia.

**Seated character.** The SeatWeld joins the character to the car's assembly [DOC Seat], so
sitting changes `AssemblyMass` and `AssemblyCenterOfMass` [INF, TEST T5]. Read both every frame
rather than caching the spec mass, or make the character Massless while seated.

---

## 2. The simulation loop

### 2.1 Frame order [DOC RunService, task scheduler]

| Step | Event | Notes |
|---|---|---|
| 1 | `PreRender` (client only) | Before the frame is drawn. `deltaTimeRender`. Rendering waits for handlers. Replaces `RenderStepped`. `BindToRenderStep` gives ordered priorities (client only). |
| 2 | render | n/a |
| 3 | `PreAnimation` | After rendering, before physics. `deltaTimeSim`. |
| 4 | animation step | n/a |
| 5 | `PreSimulation` | "before the physics simulation"; "useful for adjusting velocity or forces just before they apply". `deltaTimeSim` is "the time the frame will step physics, ignoring throttling", which can differ from real frame time at low frame rates. Replaces `Stepped`. |
| 6 | physics | Solver at 240 Hz. "the simulation may step multiple times per frame". |
| 7 | `PostSimulation` | After physics. `deltaTimeSim`. "final tweaks to simulation results". |
| 8 | `Heartbeat` | Most scripts and `task` resumptions run here. Replication follows. |

- **`Stepped` and `RenderStepped`.** The API text says they are superseded by `PreSimulation`
  and `PreRender`. The class page summary does not tag them Deprecated. Use the new ones.
- **Task scheduler guidance** [DOC]: set physics inputs in `PreSimulation` and read results in
  `PostSimulation`. It also warns that `Heartbeat` script execution differs with
  `Workspace.SignalBehavior` (Deferred vs Immediate). [TEST T1] checks that a force written in
  `PreSimulation` lands in the same frame's physics.

### 2.2 Physics step rates

- The solver runs at 240 Hz [DOC adaptive timestepping; ANN Maximum Framerate 2024-05-30].
- `Workspace.PhysicsSteppingMethod` [DOC Workspace, enum]. It is Studio-only, "cannot be set
  through developer-facing Luau":
  - `Fixed`: every assembly at 240 Hz, "Best for stability and accuracy".
  - `Adaptive`: each assembly at 240, 120 or 60 Hz, depending on how hard it is to solve. The
    docs say high speed, high acceleration and complex mechanisms go to 240 Hz, and these
    criteria "may change". Up to 2.5× faster physics.
  - `Default`: "Currently resolves to `Adaptive`".
- Assemblies connected by constraints or contact take the highest rate among them [DOC]. The
  docs explicitly suggest `Fixed` for "racing games".
- `PhysicsSettings.AreTimestepsShown` visualises the rate per assembly [DOC PhysicsSettings].
- **Steps per frame** [INF]: 240 Hz at a 60 FPS client is about 4 solver steps per frame. At
  30 FPS it is about 8. Above 240 FPS the client does not get more physics; the framerate
  setting notes "known issues above 240Hz" [ANN 2024-05-30].
- **Server rate.** The server is not expected to run above 60 FPS [ANN 2024-05-30].
  `GetRealPhysicsFPS` is described against limits of "usually 65 or 70" [DOC Workspace]. I did
  not find an official sentence stating the server rate directly.
- **Client frame rates.** The in-game Maximum Framerate setting offers Default (60), 60, 120,
  144 and 240 on Windows [ANN 2024-05-30]. Mobile is capped at 60 [COMM feature request]. The
  model must hold from about 20 FPS to 240 FPS.

### 2.3 Fixed-step callbacks: `BindToSimulation` [NEW, ROLLOUT]

- `RunService:BindToSimulation(fn, frequency: Enum.StepFrequency, priority)` returns an
  `RBXScriptConnection` [DOC RunService].
  - Frequencies: Hz60, Hz30 (the default), Hz15, Hz10, Hz5, Hz1. Nothing above 60 Hz [DOC
    StepFrequency].
  - Its `deltaTime` is "the simulation-time interval represented by the invocation".
  - It "is available only when `Workspace.UseFixedSimulation` is enabled".
  - Callbacks "can be replayed during client resimulation".
  - Reading or writing unsynchronised properties raises an error. Only Simulation Access
    properties may be written.
  - `BindToAnimation` is the same idea, run before Animators [DOC].
- The StepFrequency page states "The Roblox simulation pipeline runs at 60 Hz" [DOC]. [INF]:
  that is the script tick of fixed simulation; the solver underneath stays at 240 Hz.
- **`UseFixedSimulation`** [DOC Workspace, ANN 2026-04-29]:
  - A `RolloutState` that is not scriptable.
  - It enables `BindToSimulation` and moves character-controller updates and joint transforms to
    a fixed rate. `time()` then returns the fixed step time.
  - Rollout, as of the 2026-04-29 post: opt-in ("`Default` is set to `Disabled`"). No date for
    opt-out or for always-on.
  - Community reports: Motor6D transform issues, FPS drops, and animations looking choppy on
    high-refresh screens because they are locked to 60 Hz [COMM replies in the same thread].
- **Not documented** [TEST T7]: whether a 60 Hz binding runs several times in one slow frame to
  catch up. A DevForum guide claims the default is Hz60; the official docs say Hz30.

Conclusion: no documented API runs a script once per 240 Hz solver substep. The RunService event
list is complete (Heartbeat, RenderStepped, PreRender, PreAnimation, PreSimulation,
PostSimulation, Stepped, Rollback, Misprediction) [DOC], and the fixed callbacks top out at
60 Hz.

### 2.4 Parallel Luau [DOC multithreading]

- How it works: Actors, `task.desynchronize()` / `task.synchronize()` and `ConnectParallel`.
- `Raycast`, `Spherecast`, `Blockcast` and `GetPartBoundsInBox` are thread-Safe [DOC WorldRoot].
  `Shapecast` is Unsafe.
- Writes to the data model must happen in the serial phase; `VectorForce.Force` is "ReadSafe".
- For one car with four casts this is not worth it [INF]. Keep it in mind for AI traffic later.
- Native code generation (`--!native`) is documented for server-side scripts only [DOC native
  code gen], so it will not speed up the driver's LocalScript.

### 2.5 Running the model at a stable rate when scripts run per frame

Recommended shape [INF]. Luau sketch, driver's client only:

```lua
RunService.PreSimulation:Connect(function(dtSim)
    local dt = math.min(dtSim, MAX_FRAME_DT)           -- clamp hitches (e.g. 1/15 s)
    local body = readBody(root)                        -- CFrame, AssemblyLinearVelocity,
                                                       -- AssemblyAngularVelocity, AssemblyMass,
                                                       -- AssemblyCenterOfMass
    local contacts = castWheels(body)                  -- one cast per wheel, at the frame's pose
    local n = math.ceil(dt / H_MAX)                    -- H_MAX about 1/1000 s
    local h = dt / n
    local fSum, tSum = Vector3.zero, Vector3.zero
    for _ = 1, n do
        local f, t = Model.step(state, input, body, contacts, h)
        fSum += f * h
        tSum += t * h
        body = Model.predictBody(body, f, t, h)        -- optional: cheap in-frame prediction
    end
    vectorForce.Force = fSum / dt + gravityCompensation
    torque.Torque = tSum / dt
end)
```

- **Equal division (`h = dt/n`) instead of an accumulator.** The engine advances exactly
  `deltaTimeSim` this frame. An accumulator leaves a remainder, so model time and engine time
  drift apart by up to one `h`.
- **The accumulator's advantage** is bit-identical results for a given `h`. Use a fixed-`h`
  accumulator in the offline Lune harness, where determinism matters more than sync.

**What sub-stepping can achieve**
- Stable integration of the model's own stiff states at about 1 kHz, whatever the frame rate:
  wheel spin, engine rpm, clutch slip, differential, tyre relaxation, ABS and TC.
- A frame-average output force that already contains the within-frame response of those states.

**What it cannot achieve**
- It cannot change the force within a frame. The engine holds `VectorForce.Force` constant over
  all its substeps.
- It cannot see new geometry within a frame. Casts are made at the frame's start pose unless you
  re-cast at predicted poses, which costs more casts.
- It cannot react to collisions the engine resolves inside the frame.
- The body's own motion (chassis velocity, and so contact slip velocity) is integrated by the
  engine. The model only predicts it within the frame. So the chassis-side coupling still has a
  one-frame delay.

### 2.6 Why the stiff parts must be internal: illustrative numbers [INF; theory belongs to `01`]

| Loop | Rough stability limit (explicit) | At 30 FPS (33 ms) | At 240 Hz | At 1 kHz |
|---|---|---|---|---|
| Suspension, 400 kg corner, k = 40 kN/m, c = 4 kN·s/m | ω·dt ≲ 2 and c·dt/m ≲ 2 | 0.33 and 0.33: fine | fine | fine |
| Tyre lateral at 2 m/s, C_α about 150 kN/rad (assumed) | (C_α/v)·dt/m ≲ 2 | **6.2: oscillates** | 0.78 | 0.19 |
| Wheel spin, I = 1.5 kg·m², C_x = 200 kN/slip, r = 0.35 m, v = 10 m/s | h < 2τ, with τ = I·v/(C_x·r²) = 0.6 ms | **unstable** | **unstable** | ok (h = 1 ms < 1.2 ms) |

- The suspension is safe at per-frame rate.
- Low-speed tyre forces are not safe at per-frame rate. That needs one of these:
  - relaxation-length tyre states;
  - a force cap so that one frame cannot reverse the slip velocity, |F| ≤ m_eff·|v_slip|/dt;
  - the solver-side `LinearVelocity` friction of decision 3.
- Wheel spin needs about 1 kHz sub-steps or an implicit update. The engine's own 240 Hz would not
  be enough even if scripts could run per substep.

---

## 3. Applying forces

| API | What it does | Fit for per-wheel forces |
|---|---|---|
| `VectorForce` [DOC] | Constant force. `RelativeTo` = Attachment0 (default), World or Attachment1. `ApplyAtCenterOfMass` true applies at the assembly's centre of mass; false applies at Attachment0, and "torque will be applied as well". `Force`, `RelativeTo` and `ApplyAtCenterOfMass` have Simulation Access. | **Recommended.** One at the centre of mass (World) carrying the summed force plus gravity compensation. |
| `Torque` [DOC] | Constant torque "from its center of mass". Same `RelativeTo` options. | **Recommended**, paired with the above, for Σ(r × F). |
| `LinearVelocity` [DOC] | Solver drives toward a target velocity in Vector, Line or Plane mode. `ForceLimitsEnabled`, `ForceLimitMode` (Magnitude/PerAxis), `MaxForce`, `RelativeTo` (World by default), `ReactionForceEnabled`. Application point not stated. | Optional: implicit static friction at low speed (Line mode, target 0, `MaxForce` = μ·Fz). [TEST T4] for the application point. |
| `AngularVelocity`, `AlignOrientation`, `AlignPosition`, `LineForce` [DOC mover constraints] | Solver-driven targets. | Not for tyres. `AlignOrientation` could serve as an optional air-control or anti-flip assist. |
| Legacy `BodyForce`, `BodyThrust`, `BodyVelocity`, `BodyGyro`… | Deprecated; replacements are mapped on the mover constraints page [DOC]. | Do not use. Older chassis such as A-Chassis use them (section 6). |
| `BasePart:ApplyImpulse`, `ApplyImpulseAtPosition`, `ApplyAngularImpulse` [DOC] | "instant force impulse to this part's assembly", optionally at a world position. Simulation Access. | Workable (impulse = F·dt per frame) but front-loaded. Must run on the owner. |
| `AssemblyLinearVelocity` / `AssemblyAngularVelocity` [DOC] | Settable, but "may lead to unrealistic motion". For server-owned parts, only server writes take effect. | Only for resets and teleports. |
| `AssemblyMass`, `AssemblyCenterOfMass`, `AssemblyRootPart` [DOC] | Mass sum (infinite if anchored), centre of mass, root. Read every frame. | Inputs to the model. |
| `GetVelocityAtPosition` [DOC] | Velocity of the assembly at a point. One tutorial author says it "never works" for them [COMM]. | Compute v + ω × (p − CoM) ourselves and compare once [TEST T10]. |
| `CustomPhysicalProperties`, `Massless`, `RootPriority` | See 1.3. | n/a |

**A constraint force held over substeps vs an impulse once per frame** [INF from the docs' "constant
force" and "instant impulse"]:
- **Same total.** A force F held for a frame gives impulse F·dtSim, spread evenly over the
  solver's 4 to 8 substeps. `ApplyImpulse(F·dt)` gives the same total momentum, all at the start
  of the frame.
- **Position differs.** Position after the frame differs by about ½·(F/m)·dt². That is
  negligible at 60 FPS and visible at 20 FPS for large forces such as a bump hit.
- **On a skipped frame or a hitch**, a constraint force keeps acting (stale) and an impulse
  simply does not happen. So with `VectorForce`, clamp `dt`, and zero the force when the driver
  leaves, the script errors or ownership changes.
- **Sharing with the solver.** Constraint forces sit inside the solver alongside contacts and
  joints. An impulse is applied to velocity before the solver runs. Both are "explicit" with
  respect to the frame-rate model.
- **Ownership.** Both act only where the assembly is simulated, which is on the owner.
  - For server-owned parts, client calls "have no effect" [DOC].
  - For client-owned (automatic ownership) parts, the docs say either side can write velocities
    or impulses. Whether a server write actually sticks on a car the client is simulating is
    [TEST T6].
- **Community warning** [COMM raycast-suspensions 2024-08-06]: "Normally you would use ApplyImpulse
  for one-time things like jumps." This is consistent with choosing `VectorForce`.

Aerodynamics: `Workspace.FluidForces` / `BasePart.EnableFluidForces` compute aero on parts
[DOC Workspace, BasePart]. Keep them off on the car and compute downforce and drag in the model.
The 2024 racing template reported flings "with the aerodynamics beta enabled" [ANN 2024-01-23].

---

## 4. Contacts

### 4.1 Cast APIs [DOC WorldRoot; ANN 2023-05-05]

| API | Signature | Limits | Thread safety |
|---|---|---|---|
| `Raycast` | `(origin, direction, params?)` | direction ≤ 15,000 studs | Safe |
| `Spherecast` | `(position, radius, direction, params?)` | radius ≤ 256, distance ≤ 1024 studs | Safe |
| `Blockcast` | `(cframe, size, direction, params?)` | size ≤ 512, distance ≤ 1024 studs | Safe |
| `Shapecast` | `(part, direction, params?, cframeOverride?, sizeOverride?)` | distance ≤ 1024; not Terrain; the cast part is always excluded | Unsafe |

- Spherecast and Blockcast shipped on 2023-05-05 [ANN "Introducing Shapecasts"]: "Performance is
  close to a raycast for a 0,0,0 size shapecast", and cost grows with shape size and cast length.
- `Shapecast` (casting a real part's geometry) is in the reference with no beta tag. I did not
  find its release announcement.
- **All three shape casts "do not detect" parts they start inside** [DOC]. Start the wheel cast
  inside the car's excluded hull, never at the wheel centre near the road.
- **`RaycastParams`** [DOC]:
  - `ExcludeInstances` / `IncludeInstances` are the newer filter fields; `FilterType` and
    `FilterDescendantsInstances` are marked superseded by them;
  - `CollisionGroup`: casts ignore parts in groups that do not collide with it;
  - `RespectCanCollide`: use the hit part's CanCollide instead of its CanQuery;
  - `IgnoreWater`;
  - `BruteForceAllSlow`: not for live games.
  - **[NEW]** `Margin` and `SizeGradient` are listed on the reference page without descriptions.
    The Markdown copy says a non-zero `Margin` makes a ray behave as a sphere cast. Do not rely on
    either until it is announced.
- **`RaycastResult`** [DOC]: `Instance`, `Position`, `Normal` ("of the intersected face"),
  `Material` (the part's Material; on Terrain it "can vary depending on terrain data") and
  `Distance`. For shape casts, whether `Distance` is the centre's sweep distance or the hit
  point's distance is [TEST T3].
- **Cost.** No official per-cast cost is published. Measure it with a `debug.profilebegin` label
  in the MicroProfiler [TEST T8]. Four to eight casts per frame on one client is not expected to
  matter [INF].

### 4.2 Avoid double application with native collisions

- **Visual wheels and trim:**
  - `CanCollide = false`, `CanQuery = false`, `CanTouch = false`, and `Massless`;
  - `CanQuery` defaults on, and casts use it unless `RespectCanCollide` is set [DOC RaycastParams,
    BasePart].
  - Better [INF]: client-local wheel parts that are not in the assembly at all, moved in
    `PreRender` with `WorldRoot:BulkMoveTo` (`FireCFrameChanged` mode) [DOC]. This keeps them out
    of mass, centre-of-mass and joint updates. Client-created instances are exempt from streaming
    out [DOC streaming].
- **Collision hull** [INF]:
  - one simple part, using the Box or Hull collision fidelity class [DOC collisions], whose
    underside sits above the road at static ride height by a margin;
  - native contact then only handles bottoming-out, walls and crashes;
  - give it low friction with a high `FrictionWeight` so that scraping does not act as a brake.
    This is a tuning choice.
- **Collision groups** [DOC collisions, PhysicsService]:
  - `RegisterCollisionGroup` and `CollisionGroupSetCollidable` (the old PhysicsService
    create/remove methods are superseded by WorldRoot methods);
  - at most 32 groups;
  - register them in one server script;
  - `NoCollisionConstraint` handles single part pairs.
- **The wheel-cast filter** excludes the car's model and all characters. Use `CollisionGroup` on
  the params if the world has non-road layers (triggers, invisible walls).
- **Streaming.** On a client, casts and physics only see streamed-in geometry. "Client-side physics
  simulation … only occurs in streamed areas" [DOC streaming]. A wheel cast into an un-streamed
  area returns nothing, and the wheel drops [INF]. Size `StreamingMinRadius` against top speed,
  and treat a sudden "no ground under all four wheels at speed" as a streaming gap, not a jump.
  Assemblies stream in whole, with their constraints [DOC].

---

## 5. Network

### 5.1 Network ownership [DOC network-ownership, BasePart, client-server]

- By default, unanchored parts are owned by the server or by a nearby client, chosen
  automatically. Anchored parts are always server-owned.
- `SetNetworkOwner(player | nil)` is a server-side call that applies to "this and all connected
  parts". Related calls: `SetNetworkOwnershipAuto()`, `GetNetworkOwner()` and
  `CanSetNetworkOwnership()`. All are tagged Simulation Access.
- **Seats.** Under automatic rules, whoever sits first owns the whole vehicle. The docs'
  passenger example shows a passenger owning the car the driver steers. Their fix: on
  `VehicleSeat` `Occupant` change, `SetNetworkOwner(driver)`; when empty,
  `SetNetworkOwnershipAuto()`.
- **Why it matters:** without driver ownership, "The driver will have to wait several network
  cycles before their input is recognized." Use manual changes "conservatively since it may
  result in jittery physics interactions".
- **Security:** "Roblox cannot verify physics calculations when a client has ownership". Clients
  can teleport owned parts.
- **What the client can and cannot set:**
  - The owner simulates and sends CFrame and velocity. Constraint property writes on the client
    affect its own simulation, and their result replicates through physics.
  - The client cannot change ownership; that is server-side.
  - Client property and attribute writes in general do not replicate to the server. Owned
    assemblies are the exception [COMM, consistent with DOC client-server: other clients receive
    "updates about the assembly's position and movement from the owning client or server"].
  - So driver telemetry such as steering angle and rpm must go through a remote. Use
    `UnreliableRemoteEvent`: no ordering, no resend, dropped above 1000 bytes, about 500 sends/s
    per client shared across remotes [DOC]. The server then sets attributes that every client
    reads.
- **Other players' view.** They see the car through server relay with interpolation. **The
  interpolation delay and send rate are not officially documented.** Community figures (about
  20 Hz) are unverified [COMM].
  - `Workspace.ImprovedPhysicsReplication` [ANN 2026-06-09] is rolling out a new backend (Instance
    State Replication) with "eventual consistency", so the last update of a part at rest is
    always delivered.
  - Status at the 2026-07-14 update: global rollout started 2026-06-15, with a temporary
    "Disabled" opt-out kept until bugs are fixed [ROLLOUT].
  - Collisions between two client-owned cars resolve against each other's delayed copy [INF], so
    crash outcomes can differ per screen.
- **Seat mechanics** [DOC Seat, VehicleSeat]:
  - touching the seat creates a `SeatWeld`; `Humanoid.SeatPart` is set; `Seat:Sit(humanoid)`
    forces a sit;
  - jumping exits, as does destroying the SeatWeld;
  - re-sitting the same seat has a cooldown of about 3 s, which the docs say may change;
  - `VehicleSeat` exposes `ThrottleFloat`, `SteerFloat`, `MaxSpeed`, `Torque` and `TurnSpeed`
    and drives hinge motors itself. We only want it as a seat plus an input source (or not at
    all; see 5.3), with `MaxSpeed` and `Torque` set so that it drives nothing.

### 5.2 Server Authority: status and fit [ANN; DOC server-authority]

**Timeline**
- Early Access (2025).
- Studio Beta, 2025-12-09: "Seat/Vehicle Seat logic still uses client-authoritative remote
  events".
- Client Beta, 2026-04-30: vehicle entry with auto-prediction "may crash"; staff suggest 20 or
  fewer players for collision-heavy racing with server-authoritative cars.
- Tech deep dive, 2026-05-08: in the Racing template, velocity micro-mispredictions; drift in
  some BodyMovers and Constraints; resimulation cost up to 6.25× at 100 ms latency.
- **Full release, 2026-07-09**: opt-in, "isn't the right decision for all games", and
  client-authoritative physics stays the default.

**How it works**
- Set `Workspace.AuthorityMode = Server`. That turns on `NextGenerationReplication` (still
  **Beta**), `PlayerScriptsUseInputActionSystem`, `SignalBehavior = Deferred`,
  `StreamingEnabled` and `UseFixedSimulation`.
- Core logic goes in `BindToSimulation` and runs on both client and server. Inputs go through
  InputActions. State syncs through attributes:
  - 64 attributes per instance;
  - names and string values up to 50 characters;
  - a mismatch triggers rollback and resimulation.
- `RunService.Rollback` and `Misprediction` events, `IsResimulating`, and
  `SetPredictionMode`/`GetPredictionStatus` exist [DOC RunService].
- Remote events are not on the shared timeline.
- Server CPU rises.

**Fit [INF]**
- It would make the car cheat-proof with no input lag.
- But it forces a whole-game conversion of Rob A Car And Escape (every input to InputActions,
  deferred signals, a beta replication mode).
- Our model would be capped at a 60 Hz script tick (fine with internal sub-steps) and is exposed
  to the constraint-drift caveat.

Not for the first prototype. Keep `Model.step` pure so the move stays possible.

### 5.3 Enter, exit, reset and owner loss without teleport or jitter (design, [INF] + [TEST T6, T9])

- **Enter.** The server sees `Occupant` change, checks it is the allowed driver, then calls
  `SetNetworkOwner(player)` and tells the client to start the model loop.
  - Either the client runs the loop only while `GetNetworkOwner` is itself, or it waits for an
    "ownership granted" remote.
  - Before ownership arrives, keep the force at zero, so two writers never fight.
- **Exit.** The client zeroes its throttle and brakes to hold. The server keeps ownership with the
  last driver while they are in the game, until speed is below a threshold for about 1 s, then
  calls `SetNetworkOwner(nil)` and optionally anchors or sleeps the car. Handing over a moving car
  is what produces the snap.
- **Reset or death while seated.** The SeatWeld goes and `Occupant` becomes nil, so this is the
  same path as Exit.
- **Owner leaves the game.** In `PlayerRemoving`, the server calls `SetNetworkOwner(nil)`
  explicitly and applies server-side brakes. What the engine does on its own here is [TEST].
- **Respawn or teleport of the car.** Have the owner do it (`PivotTo` plus zeroed velocities on
  the client), or take ownership to the server first. A server `PivotTo` on a client-simulated
  car may be overwritten by the owner's next update [TEST T6].
- **Server guards** in `PostSimulation`/`Heartbeat`, reading the replicated state:
  - speed above the car's top speed plus margin;
  - |Δv|/Δt above a physical bound (about 3 g, or more for crashes);
  - position jump not explained by velocity;
  - airtime or height without a ramp;
  - inside walls.

  On a violation: `SetNetworkOwner(nil)`, restore the last valid pose, and re-grant after a
  cooldown. Log counts, never player data.

---

## 6. Existing Roblox vehicle systems, to learn from

**A-Chassis (Novena and forks)** [COMM tune thread 2021-07-01, search snippets]
- Architecture:
  - constraint and body-mover based, with real wheel parts and native friction;
  - one big `Tune` module: weight brick, centre-of-gravity height, unsprung density, suspension
    stiffness/damping/anti-roll/travel/wishbone, steering, an engine torque curve shaped in
    Desmos, transmission modes and ratios, ABS/TC, controls.
- The tune's "spring visible / coil count" fields match `SpringConstraint` visuals, so the
  suspension is constraint springs [INF].
- One forum answer says wheels are driven by `BodyAngularVelocity` and steered by `BodyGyro`
  [COMM snippet]. Both are deprecated movers.
- Units: SPS (studs per second) and pounds, with a weight scaling of 1/50.
- Its suspension "works only with PGSPhysicsSolverEnabled".
- Lessons: a single readable tune table and a torque curve with named parameters are worth
  copying. The tyre behaviour is Roblox part friction, which is what we are replacing.

**Roblox Racing template (2024)** [ANN 2024-01-23]
- An "endorsed dune buggy", "tuned by adjusting various attributes on its components".
- Known flings with the aerodynamics beta.
- The newer Server Authority racing template is linked from the docs, but its car architecture
  is not described [DOC server-authority].

**"In Depth Scripted Car Physics"** [COMM 2025-09-03], the closest open raycast design:
- a downward ray per wheel with `RespectCanCollide` and an exclude filter;
- a world-relative `VectorForce` per wheel, updated in `Heartbeat`;
- spring force kx − cv along the body's up vector;
- welded non-colliding wheels moved through `Weld.C0`;
- later, about 10 rays in an arc per wheel for wheel shape.

Its pitfalls are worth keeping:
- an unbounded ray length flings the car off ramps, so limit the ray to rest length plus radius;
- sign errors in the spring direction;
- C0 rotation accumulating each frame;
- world-space vs local-space offsets;
- the author does not trust `GetVelocityAtPosition`;
- the author says it does not apply to Server Authority games.

Our differences: `PreSimulation` instead of `Heartbeat`, summed force and torque, SI units and
sub-stepping.

**Other DevForum failure modes** [COMM]
- Suspension script running on the server while the client owns the car, which desyncs
  (2024-08-06 thread).
- One shared mutable table across all cars of a type: "all vehicles share the same … table"
  (2025-12-08). Clone per-car state and `table.freeze` shared tuning.
- Missing `dt`, arbitrary force clamps, no mass scaling (2024-08-06).
- Lift along world Y instead of the surface normal (search snippet).
- Jailbreak is described by a community poster as raycasts at each corner plus body movers
  [COMM snippet, unverified].

---

## 7. Rendering and audio facts for a car

### 7.1 Materials and lights

- **`SurfaceAppearance`** [DOC]:
  - writable at runtime: `Color`, `AlphaMode`, `EmissiveStrength`, `EmissiveTint`;
  - PluginSecurity only: `ColorMap`, `NormalMap`, `RoughnessMap`, `MetalnessMap`;
  - `EmissiveMaskContent`: edit time or `AssetService` creation only.
  - "most SurfaceAppearance properties cannot be modified by scripts".
  - Emissive maps: Studio Beta on 2025-10-30, then "Emissive Masks are Now Live for Published
    Experiences" (update dated 2026-02-12) [ANN].
  - Brake lights, DRLs and the pink rear strip in the reference: animate `EmissiveStrength` and
    `EmissiveTint`. Paint: `Color` [TEST how it tints `ColorMap`]. Swapping maps means
    pre-built `SurfaceAppearance` instances [INF].
- **Lights** [DOC light sources, Lighting]:
  - `PointLight`, `SpotLight` (Angle up to 180) and `SurfaceLight`, each with `Shadows`.
  - Maximum `Range` "is always 120 studs" (about 34 m, short for headlights at speed).
  - No documented count limit; measure performance.
  - Lighting is now `LightingStyle` (Realistic/Soft) plus `PrioritizeLightingQuality`;
    `Technology` is deprecated [DOC; ANN Unified Lighting fully live, 2025-07-23 per the forum
    listing]. Not changeable at runtime [COMM].

### 7.2 Effects (Codex owns these; facts only)

- **`Trail`** [DOC]:
  - segments between two attachments each frame;
  - `Lifetime` from 0.01 to 20 s; `MinLength`, `MaxLength`, `WidthScale`;
  - `FaceCamera = false` follows the attachments' plane; `TextureMode Static` is recommended for
    "stamped" marks such as tyre tracks;
  - `Clear()`.
  - That gives skid marks [INF].
- **`Beam`** [DOC]: Bézier between two attachments; `Segments` defaults to 10; `Width0/1`,
  `TextureSpeed`, `LightEmission` (additive), `LightInfluence`, `Brightness` up to 10,000.
- **`ParticleEmitter`** [DOC]: `Emit(n)`, `Rate`, `Lifetime`, `Speed`, `Drag`,
  `VelocityInheritance` from 0 to 1, `LockedToPart`, shapes Box/Sphere/Cylinder/Disc, flipbooks
  up to 8×8 frames at a maximum of 30 fps.
- **Post-processing** [DOC]: `BloomEffect`, `BlurEffect`, `ColorCorrectionEffect`,
  `ColorGradingEffect` (`TonemapperPreset` Default/Retro), `DepthOfFieldEffect`,
  `SunRaysEffect`.
  - `BlurEffect` is a full-screen blur with one `Size`; only one is active (the largest).
  - **There is no motion-blur instance** in the docs. The DevForum shows only years-old feature
    requests [COMM]. Speed feel has to come from FOV, camera inertia and VFX.

### 7.3 Audio: the new Audio API [DOC audio objects/effects; ANN]

- **Status**:
  - Beta on 2024-02-22.
  - "exited Studio Beta", 2024-09-10. That post also added `AudioFilter` and `Volume` on
    `AudioPlayer`.
  - AudioLimiter and AngleAttenuation (Beta) arrived in a December 2024 follow-up [search
    listing].
  - The current reference pages carry no beta tags.
- **Graph**:
  - Sources: `AudioPlayer`, `AudioDeviceInput`.
  - Effects: `AudioEqualizer` (3 bands), `AudioFilter` (1 band: Lowpass/Highpass xdB, Peak,
    Low/HighShelf, Bandpass, Notch; `Frequency` 20 to 22,000 Hz; `Q` 0.1 to 10; `Gain` −30 to
    +30 dB), `AudioCompressor`, `AudioDistortion`, `AudioPitchShifter`, `AudioFader`,
    `AudioReverb`, `AudioEcho`, `AudioChorus`, `AudioFlanger`, `AudioTremolo`, `AudioAnalyzer`.
  - Spatial: `AudioEmitter` and `AudioListener`.
  - Output: `AudioDeviceOutput`.
  - Connections: `Wire` (`SourceInstance` → `TargetInstance`).
  - I found no `AudioCrossfader`; do not assume one.
- **`AudioPlayer`**:
  - `PlaybackSpeed` from 0 to 20 "directly control[s] its perceived pitch"; there is no
    separate pitch property;
  - `Looping`, `LoopRegion`, `PlaybackRegion`, `Volume` 0 to 10, `TimePosition`, `IsReady`;
  - `Play(atTime?)` and `Stop(atTime?)` schedule against the mixer clock, so layers can start
    phase-aligned.
- **`AudioEmitter`**:
  - silent unless parented to an Attachment, Camera or PVInstance;
  - `SetDistanceAttenuation` takes a curve of up to 400 points; `SetAngleAttenuation` sets
    directional exhaust/intake falloff;
  - `AcousticSimulationEnabled` gives occlusion, diffraction and reverb, and the listener must
    also enable it;
  - `GetAudibilityFor(listener)`.
  - **No Doppler** is mentioned anywhere I read. If wanted, compute it into `PlaybackSpeed`.
- **Layered engine pattern** [INF]:
  - one looping `AudioPlayer` per recorded rpm sample, for on-load and off-load;
  - `PlaybackSpeed` = rpm / sample rpm;
  - per-layer `Volume` crossfade, then `AudioFader` per group, then `AudioFilter`/`AudioEqualizer`
    (interior vs exterior), then `AudioEmitter` on the engine and exhaust attachments;
  - camera `AudioListener` → `AudioDeviceOutput`.
  - It runs locally on every client from replicated rpm and throttle (see 5.1). Legacy `Sound`
    still exists but has no graph.

---

## 8. Studio testing affordances

- **Frame-rate caps:**
  - The in-game Maximum Framerate setting (60/120/144/240, Windows) [ANN 2024-05-30]. One user
    says it "works in studio" [COMM].
  - There is no official Studio cap below 60. The 2024-06-24 feature request has no staff reply.
    Its workarounds [COMM, unverified]: edit `FramerateCap` in
    `%LOCALAPPDATA%\Roblox\GlobalBasicSettings_13_Studio`, or a LocalScript busy-wait on
    `os.clock()` to throttle frames.
  - The busy-wait is scriptable and repeatable, so use it for 20 and 30 FPS tests.
  - Better still [INF]: run `Model.step` offline in Lune at any `dt` sequence (constant, jittery,
    hitch). That is where FPS-independence is proven, and Studio only confirms it.
- **MicroProfiler** [DOC]:
  - Ctrl+F6 per the MicroProfiler page; some Roblox pages list Ctrl+Alt+F6.
  - Custom labels with `debug.profilebegin`/`debug.profileend`.
  - Dumps go to `%LOCALAPPDATA%\Roblox\logs`.
  - The server profiler works only from the desktop client (Ctrl+F9 → MicroProfiler → Server, up
    to 60 frames), not from Studio.
- **Script Profiler** [DOC]: client or server, sampling at 1 kHz (default) or 10 kHz; 1, 5 or 10
  minute or manual sessions; `ScriptProfilerService` for code.
- **Physics visualisation** [DOC PhysicsSettings; ANN Visualization Modes 2024-08-14]:
  - contact points; owners (`AreOwnersShown`); assemblies; mechanisms; awake parts;
  - `AreTimestepsShown` (the solver rate per assembly) and solver islands;
  - centre of mass shown;
  - constraint forces and torques, contact forces, gravity forces and net forces drawn for
    selected assemblies, with magnitudes;
  - decomposition geometry.
  - The visualisation-modes menu sits top-right of the viewport.
- **Network** [DOC network simulator; ANN 2026-06-02; ANN 2026-09-09]:
  - inbound and outbound latency 0 to 1000 ms, jitter, and packet loss 0 to 0.5%;
  - presets (Ideal Fiber 8 ms by default; set it to 0 for a clean baseline), saveable custom
    profiles, `NetworkSettings` from scripts;
  - applies to Studio playtests with a client.
  - The Device Simulator toolbar left beta on 2026-10-16 and does **not** simulate device CPU or
    GPU.
  - A bug report says the new settings cause constant rollbacks under Server Authority [COMM].
- **Diagnostics in code:** `Workspace:GetRealPhysicsFPS()`, `GetPhysicsThrottling()` (0 to 100)
  and `GetNumAwakeParts()` [DOC Workspace].

---

## 9. Studio tests that settle the load-bearing claims (bench place, never the Rob A Car place)

Each test can fail; that is the point.

| # | Claim | Test | Fails if |
|---|---|---|---|
| T1 | A force written in `PreSimulation` acts in the same frame | Set a known F on a free body; in `PostSimulation` compare Δv with F·dtSim/m | The measured Δv is off by more than 1%, or one frame late |
| T2 | `Fixed` stepping gives 240 Hz for the car | `AreTimestepsShown`, plus Δt sampling | Any rate other than 240 Hz shows |
| T3 | `Spherecast` `Distance`/`Position`/`Normal` semantics at edges and kerbs | Cast at known geometry | The values do not match the hand calculation |
| T4 | `LinearVelocity` (Line, `MaxForce`) acts at the attachment, not the centre of mass | Off-centre attachment on a free body, look for induced spin | No torque appears |
| T5 | Sitting changes `AssemblyMass` and the centre of mass | Read both before and after sitting | No change, which means there is no need to compensate |
| T6 | A server `PivotTo` or velocity write sticks on a client-owned car | Two-client test with the Network Simulator at 100 ms | The car snaps back |
| T7 | `BindToSimulation(Hz60)` catches up at 20 FPS | Count calls per second with `UseFixedSimulation` on | Fewer than 60 calls per second |
| T8 | Cast cost | MicroProfiler label around 8 casts | Over 0.2 ms per frame |
| T9 | Ownership handover at rest vs at speed | Exit at 0 and at 30 m/s, watch on a second client | A visible snap at rest |
| T10 | `GetVelocityAtPosition` equals v + ω × r | Compare both on a spinning body | They differ by more than 0.1% |

---

## Sources (all read 2026-10-27)

### Official documentation, create.roblox.com

- Units: https://create.roblox.com/docs/physics/units
- Adaptive timestepping: https://create.roblox.com/docs/physics/adaptive-timestepping
- PhysicsSteppingMethod enum: https://create.roblox.com/docs/reference/engine/enums/PhysicsSteppingMethod
- RunService: https://create.roblox.com/docs/reference/engine/classes/RunService
- StepFrequency enum: https://create.roblox.com/docs/reference/engine/enums/StepFrequency
- Task scheduler: https://create.roblox.com/docs/studio/microprofiler/task-scheduler
- Workspace: https://create.roblox.com/docs/reference/engine/classes/Workspace
- WorldRoot (Raycast, Spherecast, Blockcast, Shapecast, BulkMoveTo): https://create.roblox.com/docs/reference/engine/classes/WorldRoot
- RaycastParams: https://create.roblox.com/docs/reference/engine/datatypes/RaycastParams
- RaycastResult: https://create.roblox.com/docs/reference/engine/datatypes/RaycastResult
- BasePart: https://create.roblox.com/docs/reference/engine/classes/BasePart
- PhysicalProperties: https://create.roblox.com/docs/reference/engine/datatypes/PhysicalProperties
- Assemblies: https://create.roblox.com/docs/physics/assemblies
- Mover constraints: https://create.roblox.com/docs/physics/mover-constraints
- VectorForce: https://create.roblox.com/docs/reference/engine/classes/VectorForce
- Torque: https://create.roblox.com/docs/reference/engine/classes/Torque
- LinearVelocity: https://create.roblox.com/docs/reference/engine/classes/LinearVelocity
- Collisions: https://create.roblox.com/docs/workspace/collisions
- PhysicsService: https://create.roblox.com/docs/reference/engine/classes/PhysicsService
- Multithreading: https://create.roblox.com/docs/scripting/multithreading
- Native code generation: https://create.roblox.com/docs/luau/native-code-gen
- Network ownership: https://create.roblox.com/docs/physics/network-ownership
- Client-server runtime: https://create.roblox.com/docs/projects/client-server
- Server authority: https://create.roblox.com/docs/projects/server-authority
- Seat: https://create.roblox.com/docs/reference/engine/classes/Seat
- VehicleSeat: https://create.roblox.com/docs/reference/engine/classes/VehicleSeat
- UnreliableRemoteEvent: https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent
- Streaming: https://create.roblox.com/docs/workspace/streaming
- SurfaceAppearance: https://create.roblox.com/docs/reference/engine/classes/SurfaceAppearance
- Lighting: https://create.roblox.com/docs/reference/engine/classes/Lighting
- Technology enum: https://create.roblox.com/docs/reference/engine/enums/Technology
- Light sources: https://create.roblox.com/docs/effects/light-sources
- Post-processing: https://create.roblox.com/docs/environment/post-processing-effects
- BlurEffect: https://create.roblox.com/docs/reference/engine/classes/BlurEffect
- Beam: https://create.roblox.com/docs/reference/engine/classes/Beam
- Trail: https://create.roblox.com/docs/reference/engine/classes/Trail
- ParticleEmitter: https://create.roblox.com/docs/reference/engine/classes/ParticleEmitter
- Audio objects: https://create.roblox.com/docs/audio/objects
- Audio effects: https://create.roblox.com/docs/audio/effects
- AudioPlayer: https://create.roblox.com/docs/reference/engine/classes/AudioPlayer
- AudioEmitter: https://create.roblox.com/docs/reference/engine/classes/AudioEmitter
- AudioFilter: https://create.roblox.com/docs/reference/engine/classes/AudioFilter
- MicroProfiler: https://create.roblox.com/docs/studio/microprofiler
- Script Profiler: https://create.roblox.com/docs/studio/optimization/scriptprofiler
- PhysicsSettings: https://create.roblox.com/docs/reference/engine/classes/PhysicsSettings
- Network simulator: https://create.roblox.com/docs/studio/network-simulator

### Roblox staff announcements on the DevForum (post date)

- 2023-05-05, Introducing Shapecasts: https://devforum.roblox.com/t/introducing-shapecasts/2320655
- 2024-01-23, New Studio Racing Template: https://devforum.roblox.com/t/new-studio-racing-template/2805745
- 2024-02-22, New Audio API [Beta]: https://devforum.roblox.com/t/new-audio-api-beta-elevate-sound-and-voice-in-your-experiences/2848873
- 2024-05-30, Introducing the Maximum Framerate setting: https://devforum.roblox.com/t/introducing-the-maximum-framerate-setting/2995965
- 2024-08-14, Introducing Studio Visualization Modes: https://devforum.roblox.com/t/introducing-studio-visualization-modes/3118441
- 2024-09-10, Roblox Audio API Exits Beta: https://devforum.roblox.com/t/roblox-audio-api-exits-beta-enhanced-sound-controls-now-available/3153454
- 2025-07-23 (date from the forum listing, page not opened), Unified Lighting fully live: https://devforum.roblox.com/t/let-there-be-unified-light-unified-lighting-is-fully-live/3401512
- 2025-10-30 (updated 2026-02-12), Emissives: https://devforum.roblox.com/t/on-hold-emissives/4034414
- 2025-12-09, [Studio Beta] Server Authority: https://devforum.roblox.com/t/studio-beta-build-fair-responsive-games-with-server-authority/4139157
- 2026-04-29, [Full Release] BindToSimulation & Rolling out UseFixedSimulation: https://devforum.roblox.com/t/full-release-bindtosimulation-rolling-out-usefixedsimulation/4605516
- 2026-04-30, [Client Beta] Server Authority: https://devforum.roblox.com/t/client-beta-publish-test-your-server-authoritative-experiences/4606949
- 2026-05-08, Server Authority tech deep dive: https://devforum.roblox.com/t/server-authority-tech-deep-dive-engineering-insights/4624565
- 2026-06-02, Expanding Network Simulation in Studio: https://devforum.roblox.com/t/expanding-network-simulation-in-studio/4665487
- 2026-06-09 (updates to 2026-07-14), Upcoming Improvements to Physics Replication: https://devforum.roblox.com/t/upcoming-improvements-to-physics-replication/4675512
- 2026-07-09, [Full Release] Server Authority: https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993
- 2026-09-09 (updated 2026-10-16), Device Simulator toolbar and Network Simulator: https://devforum.roblox.com/t/studio-beta-new-device-simulator-toolbar-and-network-simulator/4861695

### Community posts (not official; used for pitfalls only)

- 2021-07-01, Vehicle A-Chassis Tune: https://devforum.roblox.com/t/vehicle-a-chassis-tune/1324988
- A-Chassis wheels on BodyAngularVelocity/BodyGyro (search snippet only): https://devforum.roblox.com/t/trying-to-get-a-part-to-spin-at-rate-of-cars-speed-a-chassis/582837
- Jailbreak-style rig (search snippet only): https://devforum.roblox.com/t/car-suspension-scripted/92283
- 2024-06-24, Allow for 30 FPS caps in Studio: https://devforum.roblox.com/t/allow-for-30-fps-caps-in-studio/3037244
- 2024-08-06, Raycast suspensions: https://devforum.roblox.com/t/raycast-suspensions/3105353
- 2025-09-03, In Depth Scripted Car Physics: https://devforum.roblox.com/t/in-depth-scripted-car-physics/3915628
- 2025-12-08, Raycast Vehicle Suspension Problem: https://devforum.roblox.com/t/raycast-vehicle-suspension-problem/4136810
