--!strict
--[[
	Water drops on the camera's lens in the views that have one (on foot, chase, hood; the
	cockpit looks through the windscreen instead). New drops land with the rain and faster
	with speed, none under a roof; they gather toward the edges and leave the centre of the
	view clear, slide slowly down, and drain away once the rain stops reaching the lens.
	Positions are shares of the screen: x right, y down, 0 to 1.
]]
export type View = "OnFoot" | "Chase" | "Hood" | "Cockpit"

export type Tuning = {
	-- New drops per second in full rain, the camera still and under open sky.
	rate: number,
	exponent: number,
	-- Extra rate per 100 km/h of speed: driving into rain wets the lens faster.
	speedGain: number,
	-- Radius of the clear centre, as a share of half the screen's height and width.
	clear: number,
	-- Above 0 pushes drops toward the screen's edges.
	edgeBias: number,
	-- Kept this far from the screen's edges, as a share of the screen.
	margin: number,
	-- Seconds a drop stays while rain still reaches the lens, shortest and longest.
	life: { number },
	-- Seconds to appear and to fade at the end of its life.
	fadeIn: number,
	fadeOut: number,
	-- How fast a drop slides down, in screen heights per second, while wet and once draining.
	slide: number,
	drain: number,
	-- How much faster a drop ages once the lens is out of the rain.
	drainAge: number,
	-- A drop's size as a share of the screen's height, smallest and largest.
	size: { number },
}

export type Drop = { x: number, y: number, size: number, age: number, life: number }

local LensDrops = {}

local function unit(value: number): number
	if value ~= value then
		return 0
	end
	return math.clamp(value, 0, 1)
end

-- New drops per second.
function LensDrops.rate(
	intensity: number,
	exposure: number,
	view: View,
	speedKmh: number,
	tuning: Tuning
): number
	if view == "Cockpit" then
		return 0
	end
	local speed = math.abs(speedKmh)
	local boost = if speed ~= speed or speed == math.huge then 0 else speed / 100 * tuning.speedGain
	return tuning.rate * unit(intensity) ^ tuning.exponent * unit(exposure) * (1 + boost)
end

-- A landing point outside the clear centre and inside the margins, from two uniform numbers
-- in [0, 1): one picks the direction, the other the distance out from the centre, biased
-- toward the edge.
function LensDrops.place(direction: number, distance: number, tuning: Tuning): (number, number)
	local angle = unit(direction) * 2 * math.pi
	local dx, dy = math.cos(angle), math.sin(angle)
	-- Distance to the screen's edge along this direction, in half-screen units.
	local edge = 1 / math.max(math.abs(dx), math.abs(dy))
	local reach = (1 - 2 * tuning.margin) * edge
	local inner = math.min(tuning.clear, reach)
	local share = unit(distance) ^ (1 / (1 + math.max(tuning.edgeBias, 0)))
	local radius = inner + (reach - inner) * share
	return 0.5 + 0.5 * dx * radius, 0.5 + 0.5 * dy * radius
end

function LensDrops.new(direction: number, distance: number, size: number, life: number, tuning: Tuning): Drop
	local x, y = LensDrops.place(direction, distance, tuning)
	return {
		x = x,
		y = y,
		size = tuning.size[1] + (tuning.size[2] - tuning.size[1]) * unit(size),
		age = 0,
		life = tuning.life[1] + (tuning.life[2] - tuning.life[1]) * unit(life),
	}
end

-- Moves a drop on by dt; `wet` is whether rain still reaches the lens. Returns whether it is
-- still on the lens.
function LensDrops.step(drop: Drop, dt: number, wet: boolean, tuning: Tuning): boolean
	local elapsed = if dt ~= dt or dt < 0 then 0 else dt
	drop.age += elapsed * (if wet then 1 else tuning.drainAge)
	drop.y += elapsed * (if wet then tuning.slide else tuning.drain)
	return drop.age < drop.life and drop.y - drop.size / 2 < 1
end

-- How visible a drop is: 0 to 1, fading in when it lands and out at the end of its life.
function LensDrops.opacity(drop: Drop, tuning: Tuning): number
	local rise = if tuning.fadeIn > 0 then drop.age / tuning.fadeIn else 1
	local fall = if tuning.fadeOut > 0 then (drop.life - drop.age) / tuning.fadeOut else 1
	return unit(math.min(rise, fall, 1))
end

return table.freeze(LensDrops)
