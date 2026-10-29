--!strict
--[[
	When the exhaust pops, and so throws flame (Effects/ExhaustFlames fires with every pop): a
	train on the overrun after a lift or a downshift with the throttle closed, and one crack as an
	upshift engages under load. Each starts by a chance set per drive mode.

	An upshift is known only once its gear engages: the shift's cut looks the same both ways.
	The random draws come in as a function, so a spec can fix them.
]]
local CarAudioEvents = require("./CarAudioEvents")
local Types = require("../Config/Cars/Types")

export type ByMode = { Strada: number, Sport: number, Corsa: number }
export type Range = { from: number, to: number }

export type Tuning = {
	-- Chance that each event pops.
	liftChance: ByMode,
	upshiftChance: ByMode,
	downshiftChance: ByMode,
	-- Seconds a train lasts after a lift and after a downshift, and between its pops.
	liftTrain: Range,
	downshiftTrain: Range,
	gap: Range,
	-- An upshift cracks from this rpm and this throttle. A train needs the overrun at minRpm or
	-- more and the throttle at closedThrottle or less, and stops as soon as either fails.
	upshiftMinRpm: number,
	upshiftMinThrottle: number,
	minRpm: number,
	closedThrottle: number,
}

export type State = {
	tuning: Tuning,
	trainUntil: number,
	nextPop: number,
}

local ExhaustPops = {}

function ExhaustPops.forMode(values: ByMode, mode: Types.DrivingMode): number
	return if mode == "Corsa" then values.Corsa elseif mode == "Sport" then values.Sport else values.Strada
end

function ExhaustPops.new(tuning: Tuning): State
	return { tuning = tuning, trainUntil = 0, nextPop = 0 }
end

local function between(range: Range, draw: () -> number): number
	return range.from + (range.to - range.from) * draw()
end

-- Whether the exhaust pops this frame. `now` is in seconds; `draw` returns 0 to 1.
function ExhaustPops.step(
	state: State,
	events: CarAudioEvents.Events,
	car: CarAudioEvents.Readout,
	mode: Types.DrivingMode,
	now: number,
	draw: () -> number
): boolean
	local tuning = state.tuning
	local crack = events.gear == "Up"
		and car.rpm >= tuning.upshiftMinRpm
		and car.throttle >= tuning.upshiftMinThrottle
		and draw() < ExhaustPops.forMode(tuning.upshiftChance, mode)
	if car.throttle > tuning.closedThrottle or car.rpm < tuning.minRpm then
		state.trainUntil = 0
		return crack
	end
	local train: Range? = nil
	if events.lift and draw() < ExhaustPops.forMode(tuning.liftChance, mode) then
		train = tuning.liftTrain
	elseif events.gear == "Down" and draw() < ExhaustPops.forMode(tuning.downshiftChance, mode) then
		train = tuning.downshiftTrain
	end
	if train then
		state.trainUntil = now + between(train, draw)
		state.nextPop = now
	end
	if now < state.trainUntil and now >= state.nextPop then
		state.nextPop = now + between(tuning.gap, draw)
		return true
	end
	return crack
end

return table.freeze(ExhaustPops)
