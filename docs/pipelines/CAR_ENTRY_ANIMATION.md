# Car entry animation pipeline

How the Drive Lab driver gets in and out of the SVJ and works its scissor door, so the next car
(or the next pass on this one) comes out at the same quality without rediscovering anything.
It builds on the R6 pipeline (`R6_ANIMATION.md`): same rig, same bake, same export. What is new
is the car around the body, one continuous timeline per direction, the door keyed on the same
timeline as the hand that moves it, and a scripted contact check that has been shown failing.

```
SEAT_WELD.json (Studio)  REST_POSE.json (hands)  HANDOFF (door)  car.glb
          \                    |                     |             /
           car_entry_prep.py ──► scene.npz (car, sill, door on its hinge, in the authoring frame)
                                   │
           car_entry_keys.py ──► entry/exit/seated .keys.json (+ .fk.json, the solver's own bake)
                                   │
  car_entry_scene.py build/bake ──► .blend ──► .baked.json ──► car_entry_check.py (contacts, feet)
                                   │                       └─► car_entry_scene.py render (review)
           car_entry_export.py ──► per clip: .seated.json, .standing.json, .door.json, .seatparts.json
                                   │
        build_keyframes (Lune) ──► .rbxm ──► upload_images.py ──► Config/CarEntry.luau
```

## 1. References: how this car is really entered

Researched 2026-10-28 with web search and fetch only. Video frames are YouTube's public
storyboard sheets (the scrubbing previews), which give one frame every 1 to 10 seconds, so
timestamps are to that precision; the videos themselves were not watched.

| Source | What it shows |
|---|---|
| Canadian Auto Review, SVJ (canadianautoreview.ca/review-2019-lamborghini-aventador-lp770-4-svj) | "the easiest way of ingress was to take a seat on the overly large door sill" then "gyrate your upper body ... and gracefully fall inside"; passengers "bumped their poor heads ... trying to duck under the doors"; no door handle inside, "a white leather pull strap in its place" |
| evo, SVJ review (evo.co.uk/lamborghini/aventador-sv/21728/...) | "Theatre begins from the moment you lift the door", "Up goes the scissor door", "having just pulled down the scissor door": lifted from outside, pulled down from inside |
| Top Gear, Aventador S interior (via search snippet; the page answers 403 to fetch) | "the doors swing up, you step over the broad sill and then lower yourself in, down and down" |
| "How to Open Aventador SVJ Door" short (youtube.com/watch?v=1KVbDCXzyCY), storyboard every 1 s | about 0:08 to 0:11, fingers go into the recess at the door's upper rear, where the door meets the side intake, and lift; 0:12 to 0:15 the open door and the wide sill with its plate |
| Royalty Exotic Cars, "How to: Lamborghini Aventador" (youtube.com/watch?v=MBGYW9DLz8M), storyboard every 2 s | about 0:18 a hand in the recess on the door's flank, 0:20 the door lifted from that edge, 0:26 seated with the legs forward in the footwell over the sill plate |
| Owner anecdote collected by search (several forum results) | slide in backwards, bottom onto the seat, then swing the legs in; the reverse to get out |
| GTA V clip dictionaries (game patch v1734 dump, alexguirre.github.io/animations-list, js/animations.js) | `veh@low@front_ds@enter_exit` splits entry into `d_open_out`, `get_in`, `d_close_in`, and exit into `get_out`, `d_close_out` (plus `d_open_out_high`, `d_close_out_no_door`); the scissor-door Infernus has its own `veh@low@infernus@ds@enter_exit` with only `d_close_out`: the low-car clips serve, except closing a door that stands up high. Our six clips are the same split |
| GTA wiki, Infernus (gta.wiki/w/Infernus) | GTA IV's Infernus doors "self-closing, relying on gravity to fall shut", "a unique opening and closing animation" |
| GTA V Online, all butterfly/scissor-door cars (youtube.com/watch?v=tTTGtD1ciD8), storyboard every 5 s | about 0:30 to 0:45, a walk to a scissor-door car, the door raised, the character entering under it |
| Unity tip on driver entry (discussions.unity.com/t/.../704242) | walk to a marker beside the door, snap the rotation, one clip covers open, sit and close, with events driving the door clip so the two stay in step: the same idea as our door curves on the server's clock |

Searched and not found: a source giving an ingress duration (ours are set by the motion, not
copied); an owner's-manual description of the outside release; game references for Test Drive
Unlimited, Mafia, Watch Dogs, Cyberpunk 2077 or Driver at the level of the motion (search returned
only acquisition guides and reviews).

What this body changes (measured, section 2): at the driver's scale the sill top is below the
standing hip and the inner wall up to it, and Roblox's upright sit, which the cockpit eye is tuned
to, floats about 2 studs above the cushion. So the real technique is kept (perch on the sill,
swing the legs, then in), but "fall inside" becomes a hoist: both hands push the body up and in.

## 2. Frames, scale and the seat

Measured in Studio edit mode, never a playtest: rig a copy of `workspace.CarImport` with
`CarRig.build`, seat an R6 from `CreateHumanoidModelFromDescription` scaled with
`Model:ScaleTo(Driving.DRIVER_SCALE)` through `Seat:Sit`, play Roblox's R6 sit (178130996) with
`Animator:StepAnimations`, read, destroy everything. The result is
`drive-lab-assets/driver/SEAT_WELD.json`; every number below comes from it.

| | Seat frame (the DriverSeat part: +X right, +Y up, -Z forward), studs of the 1.5x world |
|---|---|
| SeatWeld | a Weld, DriverSeat to HumanoidRootPart: C0 (0, 0.2, 0), C1 (0, -1.357, 0), both turned -90° about X, so the root sits at (0, 1.557, 0), unturned |
| Seated torso (Roblox sit) | centre (0, 1.557, 0), upright; head centre (0, 2.843, 0); shoulders (±0.857, 1.986, 0); hips (±0.857, 0.700, 0); legs and arms horizontal |
| Ground | y = -2.030 (the wheels' contact patches) |
| Collision shell (Hull) | x -4.055 to 8.126, z -13.02 to 13.44, from y -0.316 up |
| Cushion, backrest | the cushion's top near y -1.3, the backrest at z +1.0 to 1.5: the sit floats 2.0 studs (0.37 m) above the cushion. The cockpit eye is tuned to that head, so it stays (lead's decision); the alternative, the body on the cushion with the eye compensated, is the owner's call |
| Sill (agent B) | top about y -0.8, from the cabin wall at x -1.77 (its top y -0.1) to the lip at x -3.05 (lip top about y -0.65) |

**Animation translation scales with the character.** On a dummy scaled to 0.857, a clip that moves
the Torso pose 1 stud moved it 0.857 (the Animator wrote Transform (0, 0, 0.857)); the scale-1
control moved 1.0. So clips are authored in scale-1 studs and play right at any scale.

**The authoring frame.** Everything is authored at scale 1 in r6_rig's RobloxSpace with the
standing root at the door mark at (0, 3, 0) facing -Z, and the car divided by the driver's scale
about it (`car_entry_prep.py`). Car forward is -X, into the car -Z, the ground y = 0. The picture
is the same as the 0.857 body beside the real car, and translations come out in the units the
Animator wants.

**The mark** (`Config.MARK`, metres from the seat in the car frame) is where the standing root
waits, facing the seat: outside the collision shell with the torso's half depth (0.43 studs) and
a margin, so a standing door clip never pushes the torso into the shell. The torso and head
collide with the shell; R6 arms and legs do not, which is why a standing hand may reach the door.

**The root jumps at the clip boundaries.** For the whole sequence the root is welded to the seat,
so each seated clip is the authored motion re-expressed against the seated root:
`T_seated = C0^-1 · R_seat^-1 · R_mark · C0 · T_mark` for RootJoint only
(`car_entry_export.py`). The first frame of OutsideOpen and GetIn and the last of OutsideClose are
the idle stance at the mark, so the moment the root moves between the mark and the seat shows
nothing.

**Getting out ends before OutsideClose does** (#40). After the door shuts, OutsideClose walks
back in to the mark, where the car's collision box is 0.659 studs in front of the root: a body
standing there clears it only while facing the car, and turning away pushes the torso into it.
So the exit sequence stops at a frame of that walk back where the body stands as at rest, far
enough out (`Config.EXIT_END`: the time into the clip, and where the server puts the root, in
metres like `MARK`); opening or shutting the door from outside still plays the whole clip.
Re-run after any re-bake of the exit timeline and paste its line over `EXIT_END`:

    python tools/anim/car_entry_exit_end.py <exit.baked.json> --mark <right,forward>

For the SVJ it picks frame 271 (3.433 s): every part within 0.093 studs of the rest pose, 1.132
studs further out than the mark, clear of the box at any heading.

## 3. One continuous timeline per direction

Timelines cut into clips at fixed frames (30 fps), so consecutive clips meet on the same pose by
construction and the door never jumps between them:

| Timeline | Clips |
|---|---|
| entry | OutsideOpen, GetIn (GetIn ends seated with the door shut: it carries the close) |
| exit | InsideOpen, GetOut, OutsideClose |
| close | InsideClose (the door key while seated with the door up) |
| seated | SeatedPose (one second of the pose GetIn and InsideClose end on, exported looped) |

`tools/anim/car_entry_keys.py` writes them by **beats**, not by joint angles
(`tools/anim/beat_tracks.py`):

- A body is a set of tracks: the pelvis point, the torso's turn (lean, yaw, roll, body-relative,
  so a lean stays a lean at any heading), the neck, a target per limb, the door's openness. Each
  track has a few beats; a monotone cubic runs between them (no overshoot, continuous speed).
- Every frame, each rigid limb is aimed at its target (`tools/anim/r6_fk.py`, the same chain as
  `r6_rig.py`, checked against Blender's bake to 1.6e-7 studs at key frames): the palm to a hand
  target, the sole to a foot target. A box foot stands on its corner, so a foot target on the
  ground is lifted until the lowest corner touches.
- **Support legs.** While a foot is planted, the pelvis height is solved, not authored: the hips
  sit exactly where the straight planted legs stand on their corners. Sitting back onto the sill,
  the hips swing on that arc about the feet, so the feet neither dig nor slide. An R6 leg cannot
  lift its foot straight up; a step hikes the stepping hip (a few degrees of torso roll) and swings
  the leg.
- **The body is solved before its targets.** The planted legs' pelvis heights come first; every
  target that rides the body (a hanging hand, a hand finding a surface, the strap) is then read
  off that solved body, so a contact hand sees the shoulder it will really have.
- **Riding.** A beat may be a function of the frame: a hand on the door rides a door point
  carried by the door's own track, so hand and door are one motion.
- **Holding a moving point: solve every frame.** An R6 arm has no elbow, so a hand holds a point
  only while the shoulder is exactly 1.44 studs from it. Interpolating a few solved beats does not
  keep that (between two beats the arm went 0.127 studs into the door), so for each frame of a
  hold `tools/anim/car_entry_hold.py` moves the pelvis and the torso's lean and roll as little as
  it can off the authored path and off its own previous frame, with the palm on the point and the
  arm, head and torso clear of the door at that frame and of the car. Its table goes into the keys
  as one beat per frame (`GETIN_RIDE`, `INSIDE_OPEN_PUSH`). Re-run it whenever the door beats or
  the pose around the span change.
- **Pushing on the car: `Car.on_surface`.** A hand that pushes on the sill, the cabin wall or the
  lip goes, each frame, to the point of the car's surface nearest its authored target where the
  arm's end face lands (1.58 studs from the solved shoulder) and the whole arm gets there clear of
  the car (pressing in at most 0.1). Where no surface is in reach the hand reaches toward the
  target instead, and the frame is logged out of reach: the keys print, per contact, the frames
  that touch.
- Keys every 2 frames, every frame inside contact spans (hands on the release, the bar, the sill,
  the wall, the door's edge, the strap; the bottom on the lip), Bezier with auto-clamped handles
  in Blender. RootJoint is keyed as quaternions: the torso turns 270 degrees on the way in and
  leans at a 90-degree yaw, where an XYZ Euler locks.

The choreography follows section 1. Getting in: a look over the shoulder, two pivot steps to
turn the back to the car (each foot rises before it travels), the hips arc back onto the sill's
lip about the planted feet, the hands find the sill behind, a push lifts the bottom clear of the
lip, the body turns on it while the legs come up over the lip; then the hoist with the door (#9):
the left hand leaves the lip and reaches up and out for the door, which starts down on its own as
the arm nears full stretch and meets the hand at half open; the hand holds the door card's lower
inner edge beside the strap while the body sinks and slides in over the wall, leaning away so its
weight draws the door down; at 30 degrees the hand takes the strap sewn on that edge and pulls
the door shut while the body settles into Roblox's sit, leaning toward the door at the end so the
strap stays within its 25 cm. GetIn ends seated with the door shut, the hands on the thighs where
`REST_POSE.json` puts the custom hands and the legs toward the pedals along the custom thighs, so
the swap to the custom limbs (phase "Seated") is quiet.
Getting out is not the entry played backwards. InsideOpen: the body leans forward and toward the
door (about 32 degrees forward, 6 of yaw, 4 of roll; the pelvis stays in the seat), the left hand
hooks the slotted bar at the top of the door card and pulls it as the release (the model names no
release; this is our reading), pushes the door up to 6 percent, and the struts carry it. GetOut:
the hands reach for the cabin wall and the lip (from the seat both are out of an R6 arm's reach,
since Roblox's sit floats over this car's cushion) and push once the body is close enough, the
body lifts and turns left, the feet reach the ground before the bottom touches the lip, a push
off stands it up, short steps turn it to the car.

## 4. Door curves

The door is keyed on the same timeline as the hand (an empty's X location, 0 shut to 1 open,
Bezier like every key); the hinge object is then keyed every frame from it, so the door mesh in
every render is the curve. `car_entry_export.py` writes each moving clip's curve as
`{times, values}` (seconds from the clip's start), trimmed of the held ends (the runtime holds
past either end) and thinned to the fewest points a linear curve needs within 0.004. Ends are exact
rests, which `tests/CarEntry.spec.luau` checks: an opening clip runs 0 to 1, a closing one 1 to 0.
In game the angle is openness times the open angle, linear (agent B's `Rules/Hinge`).

### What this body cannot do with this door (measured, decided on #9)

- **An R6 arm has no elbow:** the palm is always 1.44 studs (scale 1; 1.23 game studs) from the
  shoulder joint. It reaches a point only on that sphere, never inside it, which is why a strap is
  held where that sphere meets the strap's line (`strap_grab`), not at its end.
- **The open door is out of reach.** At 90.8 degrees its lowest point is 4.64 game studs above the
  ground and a standing hand tops out at 4.2. From the seat the door is reachable only below about
  37 degrees (the 25 cm strap). So a close starts with the door coming down on its own as the arm
  reaches full stretch for it, and the hand takes it as soon as it can. Getting in, at half open
  from the top of the hoist, on the door card's lower inner edge, ridden down to 30 degrees; then
  the strap. Seated (InsideClose), on the strap at 30 degrees. Both pull to shut with contact; the
  strap is taken at the same openness, 30/90.8, in both, which is the strap runtime's rule for
  drawing it held. Outside, on its lower front corner, with a gap of 10 cm at the moment the door
  starts (arm straight up, torso rolled 18 degrees, a toe rise: a kneeless R6 can do no more).
- **The seated body floats.** Roblox's sit (seat height T, #8) holds the hips 2 studs above this
  car's cushion, so from the seat no hand reaches the cushion, the cabin wall or the lip. Hands
  that push there do so only once the body has moved close enough (`Car.on_surface`).
- **Opening is honest:** a press on the release, a lift of the first 3 percent, then the struts.
- **The door sweeps out:** between 30 and 60 percent open its lower edge swings out to about 0.8
  game studs outboard of the mark at torso height, so OutsideOpen steps back out of its way and
  OutsideClose stands ahead of the door's front, out of its path.
- **The collision shell** (CarRig's Hull, the mirrors' width) is 1.2 game studs outboard of the
  door skin; reaching the release takes the torso about 0.8 into it. During a standing door clip
  the client anchors the root at the mark (the lead's runtime), and the clip's root never moves.
- **Steps must lift before they travel.** A rigid R6 leg lifts its foot only by swinging or by
  hiking its hip. A side step hikes the stepping hip (torso roll) from its first frame to its
  last, lifts the foot almost straight up before it moves across, and sets it down almost straight
  down; no step is longer than a rigid leg can make without dragging (the walk out of the door's
  sweep is two pairs of short steps, not one long one). The owner's "feet slide" decision is about
  the walk cycle at 12.5 studs/s, not these steps: here a grounded foot that moves is a failure.

## 5. Checks

`tools/anim/car_entry_check.py` runs on Blender's bake (the solver's own bake for quick passes):

- every R6 part's box (the head as its ~1.25-stud mesh) against a cloud of points sampled over
  every car triangle (0.05 studs apart), the door posed at that frame's openness, and the ground;
  a point's depth is how far it is past the box's nearest face;
- failures above 0.04 studs (authoring units) except where `allow.json` names an intended contact
  (part, surface, frames, depth): hands on the release, the bar, the sill, the wall, the lip, the
  door's edge and the strap; the bottom on the lip. Hand contacts are 0.15 deep at most, the door's
  edge and the strap 0.12; every allowance is listed in the PR, and none is widened to pass;
- **contacts that must touch:** an `allow.json` entry with `"touch": 0.1` fails ("float") on any
  frame where the end of the part (the hand: the quarter of the arm toward its end) is farther
  than 0.1 from those surfaces. A penetration check alone passes a hand pushing on air; this is
  the half that catches it. Shown failing on the first agent's clips: hands "on" the lip and the
  cabin wall floated up to 1.0 stud;
- each sole's slide while it is within 0.025 of the ground, measured at the sole's centre so a foot
  turning on the spot is not a slide; more than 0.6 studs/s fails.

**Named contacts decided on 2026-10-28** (each at its measured depth, rounded up to the next
0.001, written by `car_entry_allow.py`; studs at scale 1):

| Contact | Where | Depth | Why it is not avoidable | Decided by |
|---|---|---|---|---|
| Thighs resting on the cabin wall's top while sliding over it | GetIn f186-202, GetOut f66-92 | 0.253 in, 0.398 out | a rigid R6 thigh hinged at its top edge reaches about a stud below the hip, and the hips cross the wall barely above its top (seat height T and the #9 edge hold put them there) | coordinator, on captures at the worst frames |
| Thighs over the sill's lip and edge (one allowance, entry and exit) | GetIn f160-184, GetOut f88-118 | 0.149 | the same rigid thigh while the legs swing over the lip | lead (rigid-thigh class); the first agent's 0.22 tightened |
| Upper arm resting on the door card while reaching the release bar | InsideOpen f6-11 | 0.094 (measured) | leaning in to the bar puts the upper arm on the card | lead |

It exits 1 on any failure, and with `--json` records what it checked (SHA-256 of the bake, the
scene and the allow list, the frame range, any mutation, pass or fail). **Shown failing on
purpose:** the bake with the body lowered by 10 cm while it sits on the sill turns it red on the
sill and the ground, and green again without the mutation.

`tools/anim/car_entry_preview.py` draws orthographic previews of a bake against the car without
Blender, for quick iterations; the review renders come from Blender (section 6).

## 6. Renders

    blender -b <entry.blend> -P tools/blender/car_entry_scene.py -- render <dir> --cams side,entry,eye,door --stretch 4 --res 480 --step 2

Workbench, the car's real meshes with flat colours, the door moving with its curve. `side` is
outside ahead of the door, low; `game` is a fixed third person behind the mark; `top` from above;
`eye` rides the animated head as `EntryView` does in first person (CFrame (0, 0.1, -0.35) in the
head, vertical FOV 70), the head hidden. `entry` and `leave` are `EntryView`'s third person: a
fixed offset from the head, kept from the sequence's start, looking at it (entering from behind
the player, leaving from the car view's place behind the car). `door` is a standing eye at the
door mark looking into the opening, the view of someone waiting at the door. `--stretch 4`
remaps time so each frame is rendered four times slower (quarter speed, the sub-frames
interpolated by Blender), `--step 2` keeps every other one; at 15 fps the result plays at
quarter speed. Read every contact sheet before going on.

## 7. Export, upload, wiring

    python tools/anim/car_entry_check.py <baked.json> <scene.npz> --allow <allow.json> --json <check.json>
    python tools/anim/car_entry_export.py <baked.json> <scene.npz> <export_dir>
    python -I tools/anim/car_entry_upload.py 2746107833 <export_dir>=<check.json> [...] --ids <ids.json>
    python tools/anim/car_entry_config.py <clips.json> <ids.json> --mark <right,forward>

**The upload refuses a timeline that did not pass.** `car_entry_upload.py` builds and uploads a
timeline's clips only when a check record says that exact bake (by SHA-256, with the same scene)
passed over every frame, unmutated, and every file of the export is unchanged since. Otherwise it
prints why and uploads nothing. The only way past is `--override "<the owner's decision>"`,
appended with its reasons to `upload_overrides.log` next to the export. It builds with
`build_keyframes` (seated variants at Action priority, standing ones with `--rest Neck`,
SeatedPose looped) and uploads through `upload_images.py`, which reads the key from the user
environment and never prints it.

The standing variants leave the neck at rest: on foot `HeadLook` turns the head with the camera
on top of whatever the clip does. Seated, `HeadLook` holds the head ahead, so the seated clips
keep their own looks (at the release, the sill, the strap). Paste the printed `CLIPS`,
`SEATED_POSE` and `MARK` over the old fields in `Config/CarEntry.luau`; nothing else in it is this
pipeline's.

## 8. Studio verification

`tools/anim/car_entry_studio_check.py` writes an edit-mode Luau check: rig a copy of the car, seat
an R6 dummy at the driver's scale (or stand it at the mark), play each uploaded clip with
`Animator:StepAnimations` at five times, and compare every part with Blender's
(`<Clip>.seatparts.json`). Then captures from third person and from the cockpit eye, and
everything is destroyed. Run it only in edit mode (`get_studio_mode` says `stop`), under the
`.studio-lock`, and confirm afterwards that nothing named `_EntryCheck*` is left.

## 9. Building the next car's entry the same way

1. Measure the seat (`SEAT_WELD.json`) and pick the door's contact points on its own mesh
   (`door_points.json`, rig metres): the outside release, the inside release, the edge the hand
   takes getting in, the strap's anchor, the lower corner taken from outside.
2. `car_entry_prep.py` builds the scene in the authoring frame; `car_entry_keys.py` authors by
   beats; for every span where a hand holds a moving door point, run `car_entry_hold.py` and paste
   its table; hands that push on the car use `Car.on_surface`.
3. Iterate on the solver's own bake (`car_entry_keys.py` writes `*.fk.json`) with
   `car_entry_check.py`; read the keys' hold and reach reports: a contact that cannot be reached
   is listed, never claimed.
4. Bake in Blender, check that bake (green, or each remaining item decided and named in the allow
   list), render at quarter speed and read every sheet, export, upload through the guard, wire the
   config, and play the uploaded clips in Studio against Blender's parts.
