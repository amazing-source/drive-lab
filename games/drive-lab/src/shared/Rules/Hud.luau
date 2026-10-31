--!strict
--[[
	What the driving HUD shows for a given state: how much of each rev segment is lit, where its
	red zone starts, whether the lit segments flash, and the HUD's display modes. Plain numbers.
]]
local Hud = {}

export type Mode = "Full" | "Minimal" | "Off"

local MODES: { Mode } = { "Full", "Minimal", "Off" }

function Hud.nextMode(mode: Mode): Mode
	local index = table.find(MODES, mode) or 1
	return MODES[index % #MODES + 1]
end

-- Share of rev segment `index` lying below `rpm`, 0 to 1, segment 1 starting at 0 rpm: how much
-- of it the revs light, or, given the redline, where its red zone starts.
function Hud.segmentShare(rpm: number, index: number, perSegment: number): number
	return math.clamp(rpm / perSegment - (index - 1), 0, 1)
end

-- The share of the screen's height a HUD frame of `aspect` (width over height) is given so it is
-- `width` times as wide as a frame of `referenceAspect` given `height`.
function Hud.frameHeight(height: number, width: number, aspect: number, referenceAspect: number): number
	-- The factor first: a frame of the reference's shape at width 1 keeps `height` exactly.
	return height * (width * referenceAspect / aspect)
end

-- The pixel offset holding a frame `margin` in from the screen's edge along one axis, for an anchor
-- of 0 (left or top), 0.5 (centre) or 1 (right or bottom), and between.
function Hud.inset(anchor: number, margin: number): number
	return margin * (1 - 2 * anchor)
end

-- Whether the lit segments flash for the upshift: only in manual, past the shift point, in the
-- lit half of a blink (the automatic shifts by itself, so a flash would be noise).
function Hud.shiftFlash(rpm: number, shiftAt: number, manual: boolean, time: number, hz: number): boolean
	return manual and rpm >= shiftAt and (time * hz) % 1 < 0.5
end

-- Whether the gearbox mode (the car's "GearboxMode") changes gear by hand: manual, with or without
-- the player's clutch.
function Hud.manualGearbox(mode: unknown): boolean
	return mode == "manual" or mode == "manualClutch"
end

-- The drive mode's label, or `launchText` while launch control is armed or launching.
function Hud.modeText(modeName: unknown, launching: boolean, launchText: string): string
	if launching then
		return launchText
	end
	return if typeof(modeName) == "string" then string.upper(modeName) else ""
end

-- Glyph sprites, slanted already: each one's rect { x, y, width, height } in its atlas, its
-- capitals' height with `pad` around them, and the advance from one digit to the next.
export type Glyphs = {
	rects: { [string]: { number } },
	height: number,
	pad: number,
	advance: number,
}

export type Align = "Right" | "Center"

-- Where each character of `text` is drawn from its glyph sprite, { x0, y0, x1, y1 } in the
-- units of `box`, whose height the capitals fill: the run's right edge on the box's (the top of
-- its slanted last glyph) or the run centred in it. A character with no glyph is skipped.
function Hud.glyphBoxes(text: string, glyphs: Glyphs, box: { number }, align: Align): { { number } }
	local scale = (box[4] - box[2]) / glyphs.height
	local pad = glyphs.pad * scale
	local count = #text
	local last = glyphs.rects[string.sub(text, count, count)]
	local width = (count - 1) * glyphs.advance + (if last then last[3] else 0)
	local left = if align == "Right"
		then box[3] + pad - width * scale
		else (box[1] + box[3] - width * scale) / 2
	local boxes = {}
	for index = 1, count do
		local rect = glyphs.rects[string.sub(text, index, index)]
		if rect then
			local x0 = left + (index - 1) * glyphs.advance * scale
			table.insert(boxes, { x0, box[2] - pad, x0 + rect[3] * scale, box[4] + pad })
		end
	end
	return boxes
end

-- How far the slanted run of `text` reaches to the left at its baseline, in the units of `box`:
-- the first glyph's sprite less its padding.
function Hud.glyphRunLeft(text: string, glyphs: Glyphs, box: { number }, align: Align): number
	local boxes = Hud.glyphBoxes(text, glyphs, box, align)
	local scale = (box[4] - box[2]) / glyphs.height
	return if #boxes > 0 then boxes[1][1] + glyphs.pad * scale else box[1]
end

return table.freeze(Hud)
