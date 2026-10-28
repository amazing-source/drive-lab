# Flipbook effect pipeline

Drawn effects (smears, wind wraps, impacts) as ParticleEmitter flipbooks, fired from animation
markers so they land on the exact frame at any playback speed.

## 1. The sheet

Roblox flipbooks need a **square power-of-two texture, at most 1024** (`Grid2x2`, `Grid4x4` or
`Grid8x8`, frames read left to right, top to bottom). Two kinds of art:

| Art | Use it with |
|---|---|
| White on transparent (real alpha) | `LightEmission = 0`, `LightInfluence = 0` |
| White on black, no alpha | `LightEmission = 1` (additive: the black vanishes) |

`python -I tools/assets/flipbook_atlas.py <in.png> <out.png>` resizes a transparent sheet to 1024,
cuts the faint haze image generators leave around strokes, and whitens fully transparent texels
so filtering never pulls a dark fringe in. Its `_preview.png` composites on grey: chat apps and
image viewers show the colour of invisible pixels, which makes a clean sheet look like noise.

## 2. Upload

`python -I tools/assets/upload_images.py <user id> <sheet.png>`, then in Studio
`InsertService:LoadAsset(decalId)` gives the image id the emitter needs.

## 3. Emitter and timing

One emitter per character, on an Attachment under the root part, made on each client:
- `Rate = 0`, `Enabled = false`, `Emit(1)` per burst;
- `FlipbookMode = OneShot`, which spreads all frames over `Lifetime` (`FlipbookFramerate` does
  nothing in OneShot);
- `LockedToPart = true`, `Speed = 0`, `Orientation = FacingCameraWorldUp`.

Fire it from a KeyframeMarker. `Animator.AnimationPlayed` hands every track as it starts,
including other players' (their animations replicate), so every client sees every burst with
no remote. Hook each track once: a track object is reused every time it plays again. Put the
marker where the effect's **peak** should be, and pick `Lifetime` so the sheet's peak frames
land there.

A billboard is flat. An effect that must wrap behind and in front of a body needs front and back
layers or a curved ribbon.

## Drive Lab record

The run's wind swirl (`Controllers/RunWrap`, `Config/RunWrap`) works. The owner rejected it on
2026-10-27 and it is out of the client start order; the code stays for a later effect. Two sheets
were tried:
- ChatGPT's 2×2 additive draft;
- the owner's 4×4 transparent swirl, `drive-lab-assets/vfx/RunWindSwirl_4x4.png`, peaking on
  frames 5 to 8 and fired 0.25 s from the run's `Swap` marker.
