# Driving HUD

A HUD drawn as one image (the owner's, from ChatGPT) and brought to life in game: the static
frame stays an image, and everything that moves is drawn over it at boxes measured off the same
image. The same route fits any HUD or dashboard design delivered as a picture.

## 1. Cut the design

    python -I tools/assets/hud_layers.py <design.png> <out dir>

The design of 2026-10-28 is a Lamborghini-style frame, 2172 × 724 with a transparent background:
a 10-segment rev bar (0–9, `RPM x1000`), the mode (`CORSA`) under a Y mark, TC and ABS with
underlines, the gear in a hexagon with `M` above it, the speed with `km/h`, a headlight icon.
The script writes:
- `hud_frame.png`: the frame with every rev segment turned to the unlit grey and every live
  readout erased: the mode, TC, ABS and their lines, `M`, the gear, the speed, the light icon.
  The rev numbers, `RPM x1000`, `km/h`, the Y and the flags stay. Cropped to what is drawn and
  brought to 1024 wide, Roblox's limit, here rather than by the upload.
- `hud_parts.png`: white masks the game tints: the first, a middle and the last rev segment,
  and the light icon.
- `hud_layout.json`: every box in the cropped frame's pixels (segments, each readout's glyph
  outline, the indicator spots) and each part's rectangle in the atlas.

How it finds things, and what went wrong on the way:
- Segments are the bright shapes in the bar's band. Segments 8 and 9 are unlit in the design,
  so they take the middle shape moved along by the bar's own spacing.
- A segment's box, cut square, carried a sliver of its slanted neighbour: each mask is kept to
  its own connected shape, grown 2 px for the antialiased edge.
- Readouts outside the hexagon are erased by blending each column between the rows above and
  below. Inside the hexagon that blend smeared the yellow edge into a vertical streak, so the
  gear and `M` are keyed out by colour instead (white text and its near-black outline replaced
  by the black around it). The digit's outline is 2–3 levels off the black: leave it and the
  erased `4` still shows as a ghost.
- The light icon's mask needs a brightness ramp as well as a colour one, or its dark square
  comes along.
- Each readout's box is what its erasing changed, so it is the glyphs' outline: live text is
  sized to its capitals.

Check the previews before uploading: the frame over a grey background (clean transparent
edges), and the hexagon close up (no streak, no ghost digit).

## 2. Upload and resolve

    python -I tools/assets/upload_images.py <user id> hud_frame.png hud_parts.png

Then resolve each decal to its image id (`InsertService:LoadAsset`, read the Decal's `Texture`),
and put the ids and the layout's numbers in `Config/Hud.luau`.

## 3. In game

`Controllers/Hud` builds the frame as an ImageLabel kept to the frame's aspect, and over it:
- the ten segments, each an ImageLabel on the parts atlas with a UIGradient: its transparency
  makes the hard edge of a partial segment (a segment is a thousand rpm and fills as a needle
  would), its colour turns red where the redline falls (8500: half of segment 9). In manual the
  lit segments and the gear flash blue past the redline.
- texts sized so their capitals fill their box: Montserrat's capitals are 0.59 of the TextSize
  (measured in Studio with a probe label). TextSize stops at 100, so the gear and the speed are
  set smaller and scaled up with a UIScale. Montserrat Heavy Italic for the digits, SemiBold for
  the labels. The italic leans past its box, so the speed's right edge sits 24 px in from the
  design's, or it touches `km/h`.
- TC and ABS (text and line) grey, yellow while they act; the light icon green with the
  headlights, grey without; the indicators (not in the design) as green arrows either side of
  the icon, shown only while they blink.

Checked in edit mode, no playtest: the controller built into StarterGui with readouts set on a
stand-in model (8650 rpm in manual, then 6400 in automatic in the cockpit placement), captured,
then removed.
