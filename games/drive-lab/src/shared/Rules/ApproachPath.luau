--!strict
--[[
	The way to walk from where a player stands to a point beside a car without walking through
	it: the shortest path from the start to the goal that keeps the root out of a rectangle (the
	car's collision box grown by the body's half-depth and a margin), turning only at that
	rectangle's corners pushed a little further out. Flat, in the box's own frame (studs, the box
	centred on the origin), so it runs anywhere, Lune included.
]]

export type Point = { x: number, z: number }

-- Corners sit this much further out than the rectangle, so a path around them never grazes it.
local CORNER_SLACK = 0.25
-- A segment counts as crossing the rectangle only if it passes this far inside it.
local INSIDE = 1e-4

local ApproachPath = {}

local function length(a: Point, b: Point): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end

-- Whether the segment a-b passes through the rectangle |x| < hx, |z| < hz (Liang-Barsky clip).
function ApproachPath.crosses(a: Point, b: Point, hx: number, hz: number): boolean
	local x0, z0 = a.x, a.z
	local dx, dz = b.x - a.x, b.z - a.z
	local enter, leave = 0, 1
	local limitX, limitZ = hx - INSIDE, hz - INSIDE
	local edges = {
		{ -dx, x0 + limitX },
		{ dx, limitX - x0 },
		{ -dz, z0 + limitZ },
		{ dz, limitZ - z0 },
	}
	for _, edge in edges do
		local p, q = edge[1], edge[2]
		if p == 0 then
			if q < 0 then
				return false
			end
		else
			local t = q / p
			if p < 0 then
				enter = math.max(enter, t)
			else
				leave = math.min(leave, t)
			end
			if enter > leave then
				return false
			end
		end
	end
	return leave - enter > 1e-9
end

-- A start inside the rectangle (a body hugging the car within the margin) first steps out
-- through the nearest side.
local function stepOut(start: Point, hx: number, hz: number): Point?
	local outX, outZ = hx - math.abs(start.x), hz - math.abs(start.z)
	if outX <= 0 or outZ <= 0 then
		return nil
	end
	if outX < outZ then
		return { x = (if start.x < 0 then -1 else 1) * (hx + CORNER_SLACK), z = start.z }
	end
	return { x = start.x, z = (if start.z < 0 then -1 else 1) * (hz + CORNER_SLACK) }
end

-- The waypoints after `start`, ending at `goal`: straight there when nothing is in the way,
-- else round the rectangle's nearer corners.
function ApproachPath.find(start: Point, goal: Point, hx: number, hz: number): { Point }
	local out = stepOut(start, hx, hz)
	if out then
		local rest = ApproachPath.find(out, goal, hx, hz)
		table.insert(rest, 1, out)
		return rest
	end
	local cx, cz = hx + CORNER_SLACK, hz + CORNER_SLACK
	local nodes: { Point } = {
		start,
		goal,
		{ x = cx, z = cz },
		{ x = -cx, z = cz },
		{ x = -cx, z = -cz },
		{ x = cx, z = -cz },
	}
	local count = #nodes
	local distance: { number } = table.create(count, math.huge)
	local previous: { number } = table.create(count, 0)
	local done: { boolean } = table.create(count, false)
	distance[1] = 0
	for _ = 1, count do
		local current, best = 0, math.huge
		for index = 1, count do
			if not done[index] and distance[index] < best then
				current, best = index, distance[index]
			end
		end
		if current == 0 or current == 2 then
			break
		end
		done[current] = true
		for index = 1, count do
			if not done[index] and not ApproachPath.crosses(nodes[current], nodes[index], hx, hz) then
				local through = distance[current] + length(nodes[current], nodes[index])
				if through < distance[index] then
					distance[index], previous[index] = through, current
				end
			end
		end
	end
	if distance[2] == math.huge then
		return { goal }
	end
	local path: { Point } = {}
	local index = 2
	while index ~= 1 do
		table.insert(path, 1, nodes[index])
		index = previous[index]
	end
	return path
end

return table.freeze(ApproachPath)
