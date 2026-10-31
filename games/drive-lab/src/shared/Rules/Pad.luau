--!strict
--[[
	The all-asphalt test area: where the paving goes and where its painted lines run, in metres
	in the first car spawn's frame (along its heading, and to its right). The paving is cut into
	overlapping tiles (Rules/Circuit.tiles) so no seam leaves a groove; every line keeps clear of
	the run-off round the edge.
]]
local Circuit = require("./Circuit")

-- From the first car spawn: paving behind it, ahead of it and to each side; the run-off inside
-- every edge.
export type Area = { behind: number, ahead: number, side: number, runOff: number }

export type Paving = { tile: number, overlap: number }

-- diameter in metres, centred along and across from the first car spawn.
export type Circle = { diameter: number, along: number, across: number }

-- A line `across` from the spawn, from `from` to `to` along it, with a cross mark `mark` long
-- every `every` metres.
export type Straight = { across: number, from: number, to: number, every: number, mark: number }

export type Markings = {
	-- A line's width, the longest chord drawing a circle, the longest single part.
	width: number,
	chord: number,
	longest: number,
	circles: { Circle },
	straight: Straight,
}

export type Fill = { alongFrom: number, alongTo: number, acrossFrom: number, acrossTo: number }

export type StripeKind = "Circle" | "Straight" | "Mark" | "Edge"
-- A painted line's centre, its length, and its heading (radians from the along axis towards the
-- right).
export type Stripe = { kind: StripeKind, along: number, across: number, length: number, yaw: number }

export type Bounds = Fill

local Pad = {}

-- The paved rectangle.
function Pad.bounds(area: Area): Bounds
	return { alongFrom = -area.behind, alongTo = area.ahead, acrossFrom = -area.side, acrossTo = area.side }
end

-- Inside the run-off: where the lines may run.
function Pad.inner(area: Area): Bounds
	local outer = Pad.bounds(area)
	return {
		alongFrom = outer.alongFrom + area.runOff,
		alongTo = outer.alongTo - area.runOff,
		acrossFrom = outer.acrossFrom + area.runOff,
		acrossTo = outer.acrossTo - area.runOff,
	}
end

-- The asphalt fills that pave the whole rectangle.
function Pad.fills(area: Area, paving: Paving): { Fill }
	local outer = Pad.bounds(area)
	local fills = {}
	for _, alongTile in Circuit.tiles(outer.alongFrom, outer.alongTo, paving.tile, paving.overlap) do
		for _, acrossTile in Circuit.tiles(outer.acrossFrom, outer.acrossTo, paving.tile, paving.overlap) do
			table.insert(fills, {
				alongFrom = alongTile.from,
				alongTo = alongTile.to,
				acrossFrom = acrossTile.from,
				acrossTo = acrossTile.to,
			})
		end
	end
	return fills
end

-- A point in the spawn's frame: metres along its heading and to its right.
export type Point = { along: number, across: number }

-- A straight line between two points, in parts no longer than `longest`, each `extend` longer.
local function line(
	stripes: { Stripe },
	kind: StripeKind,
	from: Point,
	to: Point,
	longest: number,
	extend: number
)
	local dAlong, dAcross = to.along - from.along, to.across - from.across
	local length = math.sqrt(dAlong ^ 2 + dAcross ^ 2)
	local pieces = math.max(1, math.ceil(length / longest - 1e-9))
	local yaw = math.atan2(dAcross, dAlong)
	for index = 1, pieces do
		local share = (index - 0.5) / pieces
		table.insert(stripes, {
			kind = kind,
			along = from.along + dAlong * share,
			across = from.across + dAcross * share,
			length = length / pieces + extend,
			yaw = yaw,
		})
	end
end

local function circle(stripes: { Stripe }, spec: Circle, markings: Markings)
	local radius = spec.diameter / 2
	local count = math.max(8, math.ceil(2 * math.pi * radius / markings.chord))
	local step = 2 * math.pi / count
	for index = 0, count - 1 do
		local middle = (index + 0.5) * step
		local reach = radius * math.cos(step / 2)
		table.insert(stripes, {
			kind = "Circle",
			along = spec.along + reach * math.cos(middle),
			across = spec.across + reach * math.sin(middle),
			-- The chord, and a line's width more so neighbours meet on the outside of the bend.
			length = 2 * radius * math.sin(step / 2) + markings.width,
			yaw = math.atan2(math.cos(middle), -math.sin(middle)),
		})
	end
end

-- Every painted line: the circles, the straight and its cross marks, and the run-off's edge.
function Pad.stripes(area: Area, markings: Markings): { Stripe }
	local stripes = {}
	for _, spec in markings.circles do
		circle(stripes, spec, markings)
	end
	local straight = markings.straight
	line(
		stripes,
		"Straight",
		{ along = straight.from, across = straight.across },
		{ along = straight.to, across = straight.across },
		markings.longest,
		0
	)
	local at = straight.from
	while at <= straight.to + 1e-9 do
		local half = straight.mark / 2
		line(
			stripes,
			"Mark",
			{ along = at, across = straight.across - half },
			{ along = at, across = straight.across + half },
			markings.longest,
			0
		)
		at += straight.every
	end
	local inner = Pad.inner(area)
	local corners: { Point } = {
		{ along = inner.alongFrom, across = inner.acrossFrom },
		{ along = inner.alongTo, across = inner.acrossFrom },
		{ along = inner.alongTo, across = inner.acrossTo },
		{ along = inner.alongFrom, across = inner.acrossTo },
	}
	for index, corner in corners do
		line(stripes, "Edge", corner, corners[index % 4 + 1], markings.longest, markings.width)
	end
	return stripes
end

-- A stripe's two ends.
function Pad.ends(stripe: Stripe): (Point, Point)
	local dAlong, dAcross = math.cos(stripe.yaw) * stripe.length / 2, math.sin(stripe.yaw) * stripe.length / 2
	return { along = stripe.along - dAlong, across = stripe.across - dAcross }, {
		along = stripe.along + dAlong,
		across = stripe.across + dAcross,
	}
end

return table.freeze(Pad)
