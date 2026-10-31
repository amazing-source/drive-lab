--!strict
--[[
	Which pops throw a flame and how much (Effects/ExhaustFlames draws it, Controllers/CarAudio
	fires it with each pop), and where it goes: along the outlet's own axis, tilted up by the car's
	rise. Vectors are in the chassis's space, Roblox's: x right, y up, z toward the back.
]]
local ExhaustPops = require("./ExhaustPops")

export type Vector = { x: number, y: number, z: number }
export type CarPoint = { forward: number, right: number, up: number }

-- Chance that a pop throws a flame, by what made it (ExhaustPops Kind).
export type KindChances = { Lift: number, Downshift: number, Upshift: number }

-- How one car's pops throw flame (its entry's flames). A car without it throws a flame, jet and
-- fireball together, with every pop.
export type CarFlames = {
	-- Keyed by every one of the car's drive modes (Config/Cars/Contract checks it).
	chance: { [string]: KindChances },
	-- A pop quieter than this share of the pack's loudest throws none.
	minStrength: number,
	-- The flame's share (0 to 1) from which an orange fireball, and its flash of light, joins the jet.
	fireballFrom: number,
	-- Upward share added to each outlet's own axis.
	rise: number,
	-- Brightness by day as a share of the night's: a flame that shows in a tunnel is faint in sun.
	dayShare: number,
}

local ExhaustFlames = {}

-- The flame a pop of `strength` (0 to 1) throws, 0 to 1, or nil for none. A car without its own
-- flames throws one with every pop, as strong as the pop, and draws nothing.
function ExhaustFlames.share(
	flames: CarFlames?,
	mode: string,
	kind: ExhaustPops.Kind,
	strength: number,
	draw: () -> number
): number?
	local share = math.clamp(strength, 0, 1)
	if flames == nil then
		return share
	end
	local chances = flames.chance[mode]
	if chances == nil or share < flames.minStrength then
		return nil
	end
	return if draw() < chances[kind] then share else nil
end

-- Fireballs beside the jet: none below `from`, one from it, two over the upper half of the rest.
function ExhaustFlames.fireballs(share: number, from: number): number
	if share < from then
		return 0
	end
	return if share > (from + 1) / 2 then 2 else 1
end

-- The unit direction a flame leaves an outlet whose axis (car frame) is `axis`.
function ExhaustFlames.direction(axis: CarPoint, rise: number): Vector
	local length = math.sqrt(axis.forward ^ 2 + axis.right ^ 2 + axis.up ^ 2)
	assert(length > 0, "an exhaust outlet needs an axis")
	local x, y, z = axis.right / length, axis.up / length + rise, -axis.forward / length
	local size = math.sqrt(x * x + y * y + z * z)
	return { x = x / size, y = y / size, z = z / size }
end

-- How bright a flame is drawn, as a share of its night brightness, at `daylight` (0 night to 1 day).
function ExhaustFlames.visibility(daylight: number, dayShare: number): number
	return dayShare + (1 - dayShare) * (1 - math.clamp(daylight, 0, 1))
end

return table.freeze(ExhaustFlames)
