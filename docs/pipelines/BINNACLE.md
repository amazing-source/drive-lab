# Binnacle display

A race car's screen drawn from a design pack delivered as pictures (the DR458's, the owner's
ChatGPT pack): each page's empty design is the background, and everything live is drawn over it
at places measured off the same images. Same route as the [driving HUD](DRIVING_HUD.md), for a
screen with pages, a segmented rpm band and a strip of shift lamps.

## 1. The pack

Kept outside the repo in `drive-lab-assets/dr458/ui_chatgpt_2026-10-30/extracted/`:
- `driving_empty.png`, `chassis_empty.png`, `mechanic_empty.png`, 2048 x 853: the backgrounds,
  every label printed, every value slot empty, the rpm band's segments unlit;
- the `*_filled.png` versions: examples with values, used only to measure where and how big a
  value is printed. They are separate generations, not layers: their pixels differ slightly from
  the empty pages';
- `shift_lights_off.png` and `shift_lights_on.png`, 2048 x 683, eight lamps on transparency. The
  lit strip was generated apart from the unlit one, so its lamps are not exactly where the unlit
  ones are.

## 2. Measure and cut

    python -I tools/assets/binnacle_layers.py <extracted dir> <out dir> [driving=<image id> pages=<image id>]

It prints what it found (counts, the tick numbers' places on the band, every segment's rpm, the
sampled colours) and fails on anything unexpected (a count off, a label it cannot place, a sheet
over 1024). It writes:
- `binnacle_driving.png`: the driving page, one white cell per rpm segment, the TCS and POS pill
  masks, and the eight lamps unlit then lit; `binnacle_pages.png`: the CHASSIS - BODY and
  MECHANIC pages. Pages are stored 1020 wide with a 2-pixel border of their own edge, so a
  sprite read at its edge never picks up its neighbour;
- `binnacle_layout.json` and `BinnacleLayout.luau` (copied to `Config/Cars/DR458/`): every
  place normalised to its page, every sprite's rectangle in its sheet;
- previews: `preview_*_boxes.png` (labels green, value slots orange, segment outlines and their
  rpm), `preview_driving_all_lit.png` (every lit cell over the empty page), `preview_lamps.png`.

How it finds things:
- **Segments** are the dark shapes inside the red band; the band's 59 come out as separate
  shapes because thin red lines part them. The tick numbers are the dark digits above them.
  Each segment's outline is fitted as a quad (worst edge 2.5 px off, at the antialiased corners).
- **A segment's rpm** comes from the printed numbers, not from an even spread: each number is
  projected onto the line through the segments' top edges, and the segments between two numbers
  share the thousand rpm evenly. The design's spacing is uneven (about 3 segments from 2 to 3,
  8.5 from 5 to 6), as on the real screen, where the low range is compressed.
- **A lit segment** is cut from the empty page's own unlit segment: alpha is how far each pixel
  is from the band's red toward the segment's black, inside the segment's shape grown 2 px, so
  the cell has exactly the design's outline and antialiasing. Tinted with the white sampled from
  the filled example.
- **Labels** are the light words of the empty page, matched to the config's labels by their
  rough place. **A value's slot** is centred on its label; its top and height are the capitals of
  the example value in the filled page. The gear's slot spans its frame; a pill's text slot is
  the pill's width.
- **Pills** are cut as white masks of their own shape and tinted live (TCS red when OFF,
  off-white when ON; POS static on its off-white pill).
- **Lamps**: each disc is cut square on its own rim, from both strips. The lit lens is made grey
  (its brightest channel) and tinted live with the rules' colour, so the colours stay in config.

Check the previews before uploading.

## 3. Upload and resolve

    unset ROBLOX_OPEN_CLOUD_API_KEY   # in bash, so the user environment's key is read
    python -I tools/assets/upload_images.py <user id> binnacle_driving.png binnacle_pages.png

Under the same creator as the HUD's images. Resolve each decal to its image id in Studio
(`InsertService:LoadAsset`, the Decal's `Texture`), then rerun the cutter with
`driving=rbxassetid://<id> pages=rbxassetid://<id>` and copy `BinnacleLayout.luau` again.
`Binnacle.spec` fails while a sprite has no uploaded image.

## 4. In game

`Ui/BinnacleView`, built by `Controllers/Binnacle` on the rig's `ClusterScreen`:
- the screen's canvas has the screen's shape (`canvasWidth` x `canvasHeight`, held to the
  binding's `cluster` by the contract). A page is centred at full height (`Rules.fitPage`); the
  sides take the page's edge colour, and the title strip's red across its top on CHASSIS and
  MECHANIC, so the letterbox does not show;
- the lit segments are shown from the first up to `Rules.litSegments`;
- values are texts sized so their capitals fill their slot (`font.capHeight`, `font.capOffset`,
  measured in Studio for the chosen font); TextSize stops at 100, so the gear is scaled up with a
  UIScale;
- the font is Michroma, chosen in a Studio capture against Jura, Sarpanch, Titillium, SciFi and
  Montserrat: it has the design's wide, squared shapes. It has one weight, half as heavy as the
  design's values (stems 0.127 of the cap height against 0.246), so a same-colour UIStroke of
  0.06 of the cap height on each side thickens it. Measured on a capture: capitals 0.542 of the
  TextSize, their middle 0.052 of it below the box's middle;
- each lamp is drawn on its own lens (`ShiftLight_1` to `ShiftLight_8` on the model, face
  `lensFace`), unlit or lit in the colour `Rules.strip` gives.

The specs (`Binnacle.spec`, "The DR458's design layout") hold the mapping: 59 segments side by
side and rising in rpm, each printed mark read between the segments it is printed over, every
value under its own label (or on the pill beside it), slots apart, a lens and two images per lamp,
and every sprite uploaded and on its own part of its sheet.
