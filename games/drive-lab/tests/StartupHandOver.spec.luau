--!strict
local Boss302 = require("../src/shared/Config/Cars/Boss302/Audio")
local DR458 = require("../src/shared/Config/Cars/DR458/Audio")
local StartupHandOver = require("../src/shared/Rules/StartupHandOver")
local SVJ = require("../src/shared/Config/Cars/SVJ/Audio")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local DT = 1 / 60
local IDLE_RPM = 950

local SETTINGS: StartupHandOver.Settings = {
	region = { from = 2, to = 7 },
	handOver = 4,
	abortRpm = 1400,
	abortHalfLife = 0.08,
}

local OWN: StartupHandOver.Own = { from = 0.5, handOver = 3, to = 3.5 }

-- A start-up Sound made at the press, as the engine plays it: its playhead waits at `from` until
-- it loads, `loadsAt` seconds after the press, then runs; at `to` it is removed, and a removed
-- Sound reads as neither playing nor loaded.
type Sound = { from: number, to: number, loadsAt: number }

type Run = { times: { number }, shares: { number }, gains: { number? }, seeks: { number? } }

local function run(
	state: StartupHandOver.State,
	sound: Sound,
	seconds: number,
	rpm: ((number) -> number)?
): Run
	local result: Run = { times = {}, shares = {}, gains = {}, seeks = {} }
	local position = sound.from
	for index = 1, math.round(seconds / DT) + 1 do
		local now = (index - 1) * DT
		local loaded = now >= sound.loadsAt
		local present = position < sound.to
		local share, gain, seek = StartupHandOver.step(
			state,
			{ playing = present, loaded = loaded and present, position = position },
			if rpm then rpm(now) else IDLE_RPM,
			now,
			DT
		)
		result.times[index] = now
		result.shares[index] = share
		result.gains[index] = gain
		result.seeks[index] = seek
		position = seek or position
		if loaded then
			position += DT
		end
	end
	return result
end

-- The lowest share from the first frame the loops play in full; nil if they never do.
local function lowestAfterFull(shares: { number }): number?
	local lowest: number? = nil
	for _, share in shares do
		if lowest then
			lowest = math.min(lowest, share)
		elseif share >= 1 - 1e-9 then
			lowest = share
		end
	end
	return lowest
end

describe("StartupHandOver", function()
	it("keeps the loops silent, then hands over at equal power through the region's fade-out", function()
		local state = StartupHandOver.new(SETTINGS, nil, 0, 0)
		local result = run(state, { from = 2, to = 7, loadsAt = 0 }, 4.9)
		local length = SETTINGS.region.to - SETTINGS.region.from
		for index, now in result.times do
			local share = result.shares[index]
			if now <= SETTINGS.handOver then
				expect(share).toBe(0)
			else
				local progress = (now - SETTINGS.handOver) / (length - SETTINGS.handOver)
				expect(share).toBeNear(math.sin(progress * math.pi / 2), 1e-9)
			end
			expect(result.gains[index]).toBe(nil)
		end
	end)

	it("holds the loops in full once the region has played to its end and its Sound is gone", function()
		local state = StartupHandOver.new(SETTINGS, nil, 0, 0)
		local result = run(state, { from = 2, to = 7, loadsAt = 0 }, 6)
		expect(lowestAfterFull(result.shares) :: number).toBeNear(1, 1e-6)
		expect(state.done).toBe(true)
	end)

	it("holds the idle loop's level at every car's region end", function()
		for _, pack in { SVJ, DR458, Boss302 } do
			local region = pack.startup.region
			local state = StartupHandOver.new(pack.startup, nil, 0, 0)
			local result =
				run(state, { from = region.from, to = region.to, loadsAt = 0 }, region.to - region.from + 1)
			expect(lowestAfterFull(result.shares) :: number).toBeNear(1, 1e-6)
		end
	end)

	it("holds the loops in full once the car's own sound has played to its end and is gone", function()
		local state = StartupHandOver.new(SETTINGS, OWN, 0, 0)
		local result = run(state, { from = OWN.from, to = OWN.to, loadsAt = 0 }, 4)
		expect(lowestAfterFull(result.shares) :: number).toBeNear(1, 1e-6)
		expect(state.done).toBe(true)
	end)

	it("catches the car's own sound up with the press on its first loaded frame, then hands over", function()
		local state = StartupHandOver.new(SETTINGS, OWN, 0, 0)
		local result = run(state, { from = OWN.from, to = OWN.to, loadsAt = 0.4 }, 2.7)
		local seeks = 0
		for index, now in result.times do
			local seek = result.seeks[index]
			if now < 0.4 then
				expect(result.shares[index]).toBe(0)
			elseif seek then
				seeks += 1
				expect(seek).toBeNear(OWN.from + now, 1e-9)
			end
		end
		expect(seeks).toBe(1)
		-- Caught up, its hand-over begins 2.5 s after the press; left behind, 2.9 s after.
		expect(result.shares[#result.shares] > 0).toBeTruthy()
	end)

	it("hands over from silence with the abort half-life when the start-up never loads", function()
		local state = StartupHandOver.new(SETTINGS, nil, 0, 0)
		local result = run(state, { from = 2, to = 7, loadsAt = math.huge }, 3.7)
		local first: number? = nil
		for index, now in result.times do
			if now <= 3 then
				expect(result.shares[index]).toBe(0)
			elseif first == nil then
				first = index
			end
		end
		local step = 1 - 0.5 ^ (DT / SETTINGS.abortHalfLife)
		expect(result.shares[first :: number]).toBeNear(step, 1e-9)
		expect(result.gains[first :: number]).toBeNear(1 - step, 1e-9)
		expect(state.done).toBe(true)
	end)

	it("hands over quickly once the revs pass abortRpm, the start-up fading as the loops rise", function()
		local state = StartupHandOver.new(SETTINGS, nil, 0, 0)
		local result = run(state, { from = 2, to = 7, loadsAt = 0 }, 1.8, function(now: number): number
			return if now >= 1 then 3000 else IDLE_RPM
		end)
		local share, gain = 0, 1
		for index, now in result.times do
			if now < 1 then
				expect(result.shares[index]).toBe(0)
			elseif result.gains[index] ~= nil then
				expect(result.shares[index] > share).toBeTruthy()
				expect((result.gains[index] :: number) < gain).toBeTruthy()
				share, gain = result.shares[index], result.gains[index] :: number
			else
				expect(result.shares[index]).toBe(1)
			end
		end
		expect(state.done).toBe(true)
		expect(result.shares[#result.shares]).toBe(1)
	end)
end)
