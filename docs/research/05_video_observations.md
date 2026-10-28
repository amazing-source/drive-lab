# Reference video: what the reference pack shows

Source: the owner's reference pack (`reference_pack/Roblox_Driving_Reference_Pack`), frames
extracted from "LAMBORGHINI AVENTADOR SVJ | Assetto Corsa"
(https://www.youtube.com/watch?v=NkUW-XmYgq8). Looked at on 2026-10-27: `LOOK_TARGET.jpg`,
`motion/motion_exhaust.jpg` (00:03.20 to 00:05.10, 10 frames/s) and `motion/motion_exit.jpg`
(00:47.50 to 00:49.40, 10 frames/s). No audio, no continuous playback: the full video is on the
owner's other PC. Everything below is what the frames show; anything marked "reading" is an
interpretation to confirm against the video.

## Chase camera

- Low and close: the lens sits about at roof height, slightly above it, so the rear wing, the
  engine cover louvres and the full rear width are readable.
- The car is about 25 to 35 % of the frame width and sits in the lower-middle third.
- Wide field of view with visible barrel-like stretching at the frame edges (tunnel walls and
  road lines bend outward). Reading: a wide FOV plus a stylised lens or post effect; not
  measured.
- The car stays almost fixed in frame from one 0.1 s frame to the next; the scenery carries the
  motion (strong blur on walls and road texture).
- **The car's size in frame changes during the exhaust events.** At 00:47.90 to 00:48.70 and at
  00:04.40 to 00:04.60 the car looks larger and lower than in the frames around them, then shrinks
  back. Reading: the car decelerates (throttle lift or a shift) while the camera follows on a
  damped spring, so the gap closes for a moment. This matches the brief's "camera with its own
  inertia". To confirm on the video, with the throttle state if it can be inferred from sound.

## Exhaust

- **Between events:** both pipes show a steady small orange glow (00:03.20 to 00:04.30,
  00:04.70 onward).
- **Short event, 00:04.40 to 00:04.60 (about 0.2 to 0.3 s):** at 00:04.40 the road under the car
  turns bright cyan and a pink/magenta light strip appears across the rear; at 00:04.50 and
  00:04.60 two large white plumes come out of the pipes; at 00:04.70 it is back to the orange
  glow. The ground light starts one sampled frame before the plumes are visible.
- **Long event, 00:47.90 to 00:49.20 (about 1.3 s):** continuous white plumes from both pipes,
  the ground under the car lit cyan, the pink rear strip lit throughout; it ends at 00:49.30,
  right at the tunnel exit.
- Reading: short event = a gear shift's torque cut; long event = a throttle lift at high rpm
  (overrun). Both coincide with the car closing in on the camera, which fits deceleration. The
  look is the "ReferenceVideo" preset of the brief; a stock SVJ does not prove it produces this.

## Light and materials

- Exterior (00:07, 01:33, 01:44): cold blue light, warm sky; the pink/violet paint turns
  purple-blue; the wet road mirrors the sky with stretched, broken reflections.
- Tunnel (00:23, 00:36): strong warm overhead light; the paint reads copper/orange; panel edges
  and the louvres catch hard highlights.
- Exit (00:49): the switch from warm to cold happens within about 0.2 s of frames, together with
  the exposure change; the car keeps its silhouette readable through it.
- Taillights: thin amber/yellow LED strips at the outer edges; a pink strip lights across the rear
  during the exhaust events (reading: part of the effect, not a stock light function).
- Water: dark streaks and spray behind the rear tyres on the wet road; droplets on the camera lens
  in exterior shots (00:07, 01:44). Reading: a lens-rain effect, so it is presentation, not
  physics.

## Measured on the full video (2026-10-27)

The original MP4 (1:49.13, 1920x1080 at 60 frames/s, AAC stereo 44.1 kHz) was downloaded by the
owner's Chrome to `Downloads\LAMBORGHINI AVENTADOR SVJ _ Assetto Corsa.mp4`. Scripts and outputs
are in `video_analysis/`.

**Exhaust light, frame by frame** (`exhaust_light_timing.py`, mean brightness of two screen
regions, threshold at half the peak above baseline):

| Event | Road light under the car | Plume band at the pipes |
|---|---|---|
| Short | 4.400 to 4.533 s (133 ms), peak 4.450 s | 4.450 to 4.600 s (150 ms), peak 4.517 s |
| Long | 47.817 to 48.733 s (about 0.9 s, one dip at 48.38) | three pulses: 47.850 to 48.000 (150 ms), 48.017 to 48.400 (383 ms), 48.467 to 48.683 (217 ms) |

So the ground light **leads** the visible plume by about 50 ms (3 frames) and ends first, and the
long event is a **train of pulses**, not one steady flame.

**Engine sound** (`engine_order_track.py`, spectrogram `spectrum_0-4kHz.png`): the audio shows
clean harmonic lines at about 457, 914 and 1,830 Hz scale, the pattern of a V12's orders 3, 6 and
12. Taking the strong 600-1,000 Hz line as the firing order (rpm / 10), the engine sits between
about 6,200 and 8,300 rpm for 90 % of the video, so the driver keeps it high in the range.

- **Short event = right after an upshift.** The pitch falls from about 8,330 rpm (3.9 s) to
  6,830 rpm (4.2 s), a ratio of 0.82, then stays flat; the light and plume follow 0.2 to 0.4 s
  later, at 4.40 to 4.60 s.
- **Cross-check with the real gearbox** (`02_aventador_svj_data.md`, Aventador S/SVJ ratios
  3.909 / 2.438 / 1.810 / 1.458 / 1.185 / 0.967 / 0.844): the steps between consecutive gears are
  0.624, 0.742, 0.806, 0.813, 0.816 and 0.873. The measured 0.820 matches the 4-to-5 (0.813) or
  5-to-6 (0.816) step within 1 %, so the game's sound follows the real car's gearing there; the
  shift happened at about 8,330 rpm, below the 8,700 rpm cut. In 5th, 6,830 rpm is about
  213 km/h; in 6th, about 262 km/h.
- **Long event = a throttle lift, no shift.** The pitch drifts down slowly from about 7,250 to
  6,900 rpm across 47.3 to 49.7 s with no step, which fits overrun on a lift.
- The automatic shift detector also logged 13 smaller drops (ratios 0.90 to 0.94). Those are
  smaller than any step between consecutive gears of a real 7-speed (the top-gear step is about
  0.85), so they are **not** confirmed as shifts; the sound may come from an Assetto Corsa sound mod
  rather than a stock car. Not usable for gear ratios; the ratios come from the car's documented
  data (`02_aventador_svj_data.md`).
- This is a game's sound, possibly modded: it is a reference for the feel, not evidence about a
  stock SVJ.

## What the frames do not show

- No cockpit view and no HUD.
- No measurable physics: speeds, slip and suspension travel cannot be read from a chase video.
- The sound track (not available here).
