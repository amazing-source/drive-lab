# Driving HUD

A HUD drawn as one image (the owner's, from ChatGPT) and brought to life in game: the static
frame stays an image, and everything that moves is drawn over it at boxes measured off the same
image. The same route fits any HUD or dashboard design delivered as a picture.

Two routes cut a design, by how it is delivered: one painted image (the SVJ's, §1), or a pair of
pixel-aligned exports, the frame alone and the frame with example values, with their cut-out
regions (the DR458's, §4). Each car shows its own HUD when its Contract entry has one (§5); the
SVJ has none and shows the global HUD of `Config/Hud`.

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

## 4. A design delivered as a pair (the DR458's)

    python -I tools/assets/hud_pair_layers.py <static.png> <full.png> <regions.json> <out dir>         --font <Sarpanch-Bold.ttf> --height 205 --width 0.627 --bars 0.03 --gap 0.06

The DR458's pack of 2026-10-31 is two 2172 × 724 exports with a transparent background, the
static one with every live part left out, and `cutout_regions.json` ([x, y, w, h] for the ten
segments, the mode pictogram and value, TC, ABS, A, the gear, the speed, the headlight, the
indicators). The script refuses a pair that does not line up: the same size and alpha, drawn ink
(the full export against the static one) only inside a region, and every lit segment
pixel-identical, since one mask then serves all ten. It writes:
- `hud_frame.png`: the static export cropped to what is drawn, brought to 1024 wide.
- `hud_parts.png`: white masks with 2 px of padding (the pack's boxes are tight to the ink): the
  segment, the mode pictogram, the headlight, the two indicator arrows (unlit grey in the design,
  so drawn at all times in game) and, with `--font`, the glyphs 0-9, N and R.
- `hud_layout.json`: the boxes in the frame's pixels, the glyph outlines of the live texts (TC and
  ABS split from their lines at the empty rows between), the atlas rectangles, the glyph metrics.
- `recomposed.png` (the parts laid back over the frame in their drawn colours, which must come
  within 40 levels of the full export: 10.8 on the DR458's), `frame_on_grey.png`,
  `glyphs_preview.png`.

The glyphs exist because the design's gear and speed are slanted and neither squared face Roblox
ships (Michroma, Sarpanch) has an italic, nor can a TextLabel be skewed. Each glyph is set in the
given face at four times its size, narrowed to `--width` of its own width (three digits have to fit
between the gear's hexagon and `km/h`), its horizontal bars thickened by `--bars` of its height,
slanted, and brought down. The slant is measured, not given: a line fitted to the half-coverage
crossings of both sides of the drawn speed and gear, from 45% to 80% of their height (clear of a
rounded corner and of the 1's flag); the DR458's are 0.190 and 0.180, so 0.185, about 10.5
degrees (the rev segments are 0.406, not the digits' slant). The digits share one cell, the widest
digit's, so the speed does not shift as it changes. The owner chose the size from a comparison
against the drawn digits (205 px of three heights).

Upload the two images (§2) and put the image ids, the boxes and the metrics in the car's `Hud`.

## 5. A car's own HUD

A car's Contract entry may carry `hud`, a `Config/HudDesign` (plain data, so Lune loads it).
`Contract.define` checks it at load: uploaded images, ten segments, every box inside the frame,
every mask inside the atlas and drawn at its own size, every glyph there, tabular digits, three
speed digits within their box (whose left edge is the hexagon's clearance) and every gear within
the hexagon's inner edges at the drawn digit's lowest row. `Ui/HudLook` makes a look of it (or of
`Config/Hud` for a car without one), `Ui/HudView` draws it, one view per look built at start, and
`Controllers/Hud` shows the driven car's. Without `glyphs` the gear and speed fall back to upright
text in the design's digit face, at the `texts` boxes. A face's capitals are a share of its
TextSize and their middle sits below the label's: Michroma 0.542 and 0.052 (measured in Studio for
the binnacle); Sarpanch Bold 0.457 and 0.03, predicted from its metrics by the ratio that holds for
Michroma and Montserrat (within 3%), not yet measured in Studio.

Every HUD is as wide on screen as the global HUD in the same view, times its design's `width`
(1 when left out): `HudView.place` gives its frame the height that width needs, from the frame's
shape (`Rules/Hud.frameHeight`), and its aspect-ratio constraint does the rest. The DR458's 3 : 1
design at the SVJ's height came out at 69% of the SVJ's 4.36 : 1 width; at the SVJ's width it is
1.45 times as tall, its panel fully opaque, so it hides about 1.8 times the road the SVJ's does
(`docs/evidence/hud-dr458-width/coverage.txt`).

Where it sits is `Config/Hud`'s, for every car: `ANCHOR` in the chase and hood views and
`COCKPIT_ANCHOR` in the cockpit (both bottom right since #194), held `MARGIN` pixels in from the
edges it is anchored to (`Rules/Hud.inset`); `HEIGHT` 0.13 and `COCKPIT_HEIGHT` 0.11 of the
screen for the global HUD. Bottom right leaves the car and the road ahead clear in the chase view
(`docs/evidence/hud-bottom-right/coverage.txt`). The controls screen's touch button is at the top
right; Roblox's touch jump button, at the bottom right, shows only while the Jumping state is
enabled (its `TouchJump` module), which `Controllers/CarEntry` turns off in the car.
`frameTransparency` fades the whole frame image, lettering included, and is 0 unless set; a panel
that fades alone would take a frame exported with a see-through fill and uploaded again.

`tests/HudHarness.luau` runs the controller in Lune with stand-ins for the instances and services
and writes out every property the HUD sets. It lays a GuiObject out as the engine does for this
HUD: its Size on a stand-in screen, an aspect-ratio constraint fitting it within that size, and a
script listening to its AbsoluteSize hears each change, so text refits when the frame grows.
`tests/CarHud.spec.luau` compares the SVJ's HUD, frame by frame, with a recording of main's client
(`tests/fixtures/hud_svj_dump.txt`); checks the DR458's glyph runs, red zone, masks and fonts; and
lays both HUDs out on four screens in every view and mode and finds the DR458's as wide as the
SVJ's. A change meant to alter the SVJ's HUD re-records the fixture:

    lune run games/drive-lab/tests/record_hud_fixture.luau [<folder holding client/>]

from the repo's own client by default, or from another commit's exported `src` (for example
`git archive origin/main games/drive-lab/src/client`), and its diff is read before it is committed.
What the harness cannot see: fonts as Roblox draws them, images loading, anything but this HUD's
layout.

