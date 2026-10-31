--!strict
--[[
	Which of a seated driver's hand meshes show for a shape (Rig/StartupHands): the grip and its
	cuff, a start-up shape (Rest, Point, Pinch) with the posed hands' wrist cuff, or one of the
	car's gesture meshes with the cuff it was made with. A mesh the place lacks is stood in for:
	Pinch by Point; a gesture mesh by the grip it was posed from (a "Thumb" mesh) or by Point; any
	posed shape by the grip when the place has no start-up shapes at all. Plain values, so Lune can
	test it.
]]
export type Cuff = "Grip" | "Wrist"

export type Have = {
	-- The place has the Rest, Point and wrist cuff meshes, and the Pinch one.
	startupShapes: boolean,
	pinch: boolean,
	-- The gesture meshes the place has for this side, each with its cuff.
	gestures: { [string]: Cuff },
}

export type Shown = {
	-- The shape actually drawn after stand-ins.
	shape: string,
	grip: boolean,
	gripCuff: boolean,
	wristCuff: boolean,
	-- The start-up shape or gesture mesh drawn, nil when the grip is.
	mesh: string?,
}

local STARTUP = table.freeze({ Rest = true, Point = true, Pinch = true })

local HandShapes = {}

function HandShapes.drawn(shape: string, have: Have): string
	if shape == "Pinch" then
		return if have.pinch then shape else "Point"
	end
	if shape == "Grip" or STARTUP[shape] or have.gestures[shape] then
		return shape
	end
	return if string.find(shape, "Thumb", 1, true) then "Grip" else "Point"
end

function HandShapes.shown(shape: string, have: Have): Shown
	local drawn = HandShapes.drawn(shape, have)
	local cuff = have.gestures[drawn]
	if cuff then
		local wrist = cuff == "Wrist" and have.startupShapes
		return { shape = drawn, grip = false, gripCuff = not wrist, wristCuff = wrist, mesh = drawn }
	end
	if drawn ~= "Grip" and have.startupShapes then
		return { shape = drawn, grip = false, gripCuff = false, wristCuff = true, mesh = drawn }
	end
	return { shape = drawn, grip = true, gripCuff = true, wristCuff = false, mesh = nil }
end

return table.freeze(HandShapes)
