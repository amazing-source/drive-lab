--!strict
--[[
	Water on the windscreen seen from the cockpit, kept in the pane's own plane so a drop stays
	on the glass however the head turns. The pane is the windscreen's four corners (a slanted
	quadrilateral), flattened onto their best plane; positions are metres from the top-left of
	its bounding rectangle, x toward the driver's right, y down the glass.

	Drops land at a rate set by the rain, the sky over the car and its speed (a moving screen
	sweeps through more rain). Most are beads that cling and fade; some cling a moment, then
	slide, gathering speed slowly: down under gravity when slow, up the glass in the airflow
	when fast. A drop is placed only where all of its sprite lies inside the windscreen.
]]
export type Vector = { x: number, y: number, z: number }
export type Point = { x: number, y: number }
-- The pane: its centre, its axes (right, down, and the normal toward the driver, all unit),
-- its bounding rectangle's size, and the windscreen's corners in pane coordinates.
export type Pane = {
	centre: Vector,
	right: Vector,
	down: Vector,
	normal: Vector,
	width: number,
	height: number,
	polygon: { Point },
}

export type Tuning = {
	-- Drops per second landing on the whole pane in full rain, standing still, and the speed
	-- (km/h) at which twice as many land; never more than maxRate.
	rate: number,
	doubleAt: number,
	maxRate: number,
	exponent: number,
	-- Share of the drops that slide; the others cling until they fade.
	sliding: number,
	-- Seconds a sliding drop clings before it moves, smallest and largest.
	cling: { number },
	-- Slide acceleration (m/s^2, down the glass) from gravity, the airflow's pull up the glass
	-- per (m/s)^2 of speed, and the fastest a drop slides (m/s).
	gravity: number,
	airflow: number,
	maxSlide: number,
	-- Seconds a drop lives, smallest and largest, and the share of it spent fading out.
	life: { number },
	fadeOut: number,
}

export type Drop = {
	x: number,
	y: number,
	radius: number,
	slides: boolean,
	cling: number,
	speed: number,
	age: number,
	life: number,
}

local WindshieldDrops = {}

local function finite(value: number): number
	return if value ~= value or value == math.huge or value == -math.huge then 0 else value
end

local function unit(value: number): number
	return math.clamp(finite(value), 0, 1)
end

local function sub(a: Vector, b: Vector): Vector
	return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }
end

local function dot(a: Vector, b: Vector): number
	return a.x * b.x + a.y * b.y + a.z * b.z
end

local function scale(a: Vector, by: number): Vector
	return { x = a.x * by, y = a.y * by, z = a.z * by }
end

local function cross(a: Vector, b: Vector): Vector
	return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x }
end

local function normalise(a: Vector): Vector
	local length = math.sqrt(dot(a, a))
	return if length > 1e-9 then scale(a, 1 / length) else { x = 0, y = 0, z = 0 }
end

-- The pane through the windscreen's corners, top-left, top-right, bottom-right, bottom-left as
-- the driver sees them, in any right-handed frame; `toward` points from the glass to the driver.
function WindshieldDrops.pane(corners: { Vector }, toward: Vector): Pane
	local topLeft, topRight, bottomRight, bottomLeft = corners[1], corners[2], corners[3], corners[4]
	local right = normalise(sub(sub(topRight, topLeft), scale(sub(bottomLeft, bottomRight), 1)))
	local downRaw = sub(sub(bottomLeft, topLeft), scale(sub(topRight, bottomRight), 1))
	local down = normalise(sub(downRaw, scale(right, dot(downRaw, right))))
	local normal = normalise(cross(right, down))
	if dot(normal, toward) < 0 then
		normal = scale(normal, -1)
	end
	local centre = scale({
		x = topLeft.x + topRight.x + bottomRight.x + bottomLeft.x,
		y = topLeft.y + topRight.y + bottomRight.y + bottomLeft.y,
		z = topLeft.z + topRight.z + bottomRight.z + bottomLeft.z,
	}, 0.25)
	local xs, ys = {}, {}
	for index, corner in corners do
		local offset = sub(corner, centre)
		xs[index], ys[index] = dot(offset, right), dot(offset, down)
	end
	local left, top = math.min(table.unpack(xs)), math.min(table.unpack(ys))
	local polygon = {}
	for index in corners do
		polygon[index] = { x = xs[index] - left, y = ys[index] - top }
	end
	local width, height = math.max(table.unpack(xs)) - left, math.max(table.unpack(ys)) - top
	-- The rectangle's centre, which need not be the corners' average.
	local middle = {
		x = centre.x + right.x * (left + width / 2) + down.x * (top + height / 2),
		y = centre.y + right.y * (left + width / 2) + down.y * (top + height / 2),
		z = centre.z + right.z * (left + width / 2) + down.z * (top + height / 2),
	}
	return {
		centre = middle,
		right = right,
		down = down,
		normal = normal,
		width = width,
		height = height,
		polygon = polygon,
	}
end

-- The pane's point at (x, y): metres from its rectangle's left edge and from its top, in the frame
-- its corners were given in.
function WindshieldDrops.point(pane: Pane, x: number, y: number): Vector
	local across, down = x - pane.width / 2, y - pane.height / 2
	return {
		x = pane.centre.x + pane.right.x * across + pane.down.x * down,
		y = pane.centre.y + pane.right.y * across + pane.down.y * down,
		z = pane.centre.z + pane.right.z * across + pane.down.z * down,
	}
end

-- Whether a circle of `radius` at (x, y) lies wholly inside a convex polygon, its corners in
-- either winding order.
function WindshieldDrops.inside(polygon: { Point }, x: number, y: number, radius: number): boolean
	local count = #polygon
	if count < 3 then
		return false
	end
	local area = 0
	for index = 1, count do
		local a, b = polygon[index], polygon[index % count + 1]
		area += a.x * b.y - b.x * a.y
	end
	local winding = if area >= 0 then 1 else -1
	for index = 1, count do
		local a, b = polygon[index], polygon[index % count + 1]
		local ex, ey = b.x - a.x, b.y - a.y
		local length = math.sqrt(ex * ex + ey * ey)
		if length > 1e-9 then
			-- Signed distance from the edge, positive inward.
			local distance = winding * (ex * (y - a.y) - ey * (x - a.x)) / length
			if distance < radius then
				return false
			end
		end
	end
	return true
end

-- Drops per second landing on the pane.
function WindshieldDrops.landing(
	intensity: number,
	exposure: number,
	speedKmh: number,
	tuning: Tuning
): number
	local sweep = 1 + math.abs(finite(speedKmh)) / math.max(tuning.doubleAt, 1e-6)
	local rate = tuning.rate * unit(intensity) ^ tuning.exponent * unit(exposure) * sweep
	return math.min(rate, tuning.maxRate)
end

-- A sliding drop's acceleration down the glass (m/s^2): gravity, less the airflow's pull up it.
function WindshieldDrops.pull(speedKmh: number, tuning: Tuning): number
	local air = finite(speedKmh) / 3.6
	return tuning.gravity - tuning.airflow * air * air
end

-- Moves a drop on by dt; false once its life is over or it has left the pane's rectangle.
function WindshieldDrops.step(drop: Drop, dt: number, pull: number, height: number, tuning: Tuning): boolean
	local step = math.max(finite(dt), 0)
	drop.age += step
	if drop.slides and drop.age > drop.cling then
		drop.speed = math.clamp(drop.speed + finite(pull) * step, -tuning.maxSlide, tuning.maxSlide)
		drop.y += drop.speed * step
	end
	return drop.age < drop.life and drop.y > -drop.radius and drop.y < height + drop.radius
end

-- A drop's opacity, 0 to 1: full until its fade, then falling to nothing at the end of its life.
function WindshieldDrops.opacity(drop: Drop, tuning: Tuning): number
	if drop.life <= 0 then
		return 0
	end
	local fadeFrom = drop.life * (1 - tuning.fadeOut)
	if drop.age <= fadeFrom then
		return 1
	end
	return unit(1 - (drop.age - fadeFrom) / (drop.life - fadeFrom))
end

return table.freeze(WindshieldDrops)
