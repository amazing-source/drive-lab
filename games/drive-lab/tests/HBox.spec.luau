--!strict
--[[
	The H box (Vehicle/Gearbox with kind "manual", Vehicle/HBox) on the Boss 302's gearbox, one
	substep at a time: the shift follows its plan and engages at the gate, the throttle the driver
	gives, refusals, the player's clutch and the stall, retargets and queues, and the limbs.
]]
local Boss302 = require("../src/shared/Config/Cars/Boss302/Physics")
local Engine = require("../src/shared/Vehicle/Engine")
local Gearbox = require("../src/shared/Vehicle/Gearbox")
local HBox = require("../src/shared/Vehicle/HBox")
local ShiftPlan = require("../src/shared/Vehicle/ShiftPlan")
local T = require("../../../tools/test/T")
local Types = require("../src/shared/Config/Cars/Types")

local describe, it, expect = T.describe, T.it, T.expect

local config, engine = Boss302.gearbox, Boss302.engine
local MANUAL = config.manual :: Types.ManualGearboxConfig
local RPM = Engine.RAD_PER_RPM
local STEP = 0.001

local function context(overrides: { [string]: any }?): Gearbox.Context
	local base: Gearbox.Context = {
		engineSpeed = 3000 * RPM,
		outputSpeed = 3000 * RPM / config.ratios[2],
		engineTorque = 300,
		groundSpeed = 15,
		throttle = 0.3,
		brake = 0,
		mode = Boss302.modes.Normal,
		gearboxMode = "manual",
		holdGear = false,
		clutchPedal = 0,
	}
	if overrides then
		for key, value in overrides do
			(base :: any)[key] = value
		end
	end
	return base
end

local function engaged(gear: number): Gearbox.GearboxState
	local state = Gearbox.newState()
	state.gear, state.target, state.autoClutch, state.launching = gear, gear, 1, false
	return state
end

-- Runs substeps until no plan is left, calling `each` after every one.
local function runPlan(
	state: Gearbox.GearboxState,
	ctx: Gearbox.Context,
	each: ((boolean, number, number) -> ())?
)
	local elapsed = 0
	while (state.hbox.plan ~= nil or Gearbox.isShifting(state)) and elapsed < 3 do
		local cut, blip, share = Gearbox.update(config, engine, state, ctx, STEP)
		if each then
			each(cut, blip, share)
		end
		elapsed += STEP
	end
end

describe("H box shifts", function()
	it("engages the new gear on the substep the lever reaches its gate, through the ISR's phases", function()
		local state = engaged(2)
		local ctx = context()
		Gearbox.request(config, engine, state, true, false, ctx)
		local plan = state.hbox.plan :: ShiftPlan.Plan
		expect(plan.from).toBe(2)
		expect(plan.to).toBe(3)
		local phases: { string } = {}
		local engagedAt, neutralCapacity, outOfGearAt = math.huge, 0, math.huge
		runPlan(state, ctx, function()
			if phases[#phases] ~= state.phase then
				table.insert(phases, state.phase)
				if state.phase == "neutral" then
					outOfGearAt = state.hbox.time
				end
			end
			if state.gear == 3 and engagedAt == math.huge then
				engagedAt = state.hbox.time
			end
			if state.phase == "neutral" then
				neutralCapacity = math.max(neutralCapacity, Gearbox.clutchCapacity(config, state))
			end
		end)
		expect(table.concat(phases, " ")).toBe("opening neutral closing engaged")
		-- Out of gear (the ratio drops) as the lever starts to leave its gate, not when it reaches the rail.
		expect(outOfGearAt >= plan.clutchDown and outOfGearAt < plan.clutchDown + STEP).toBe(true)
		expect(engagedAt >= plan.gateIn and engagedAt < plan.gateIn + STEP).toBe(true)
		local column, row = ShiftPlan.lever(plan, MANUAL.gates, engagedAt)
		expect(column).toBe(MANUAL.gates[3].column)
		expect(row).toBe(MANUAL.gates[3].row)
		expect(neutralCapacity).toBe(0)
		expect(state.gear).toBe(3)
	end)

	it(
		"keeps the driver on the throttle through the reach, off it until the gate, then feeds it in",
		function()
			local state = engaged(2)
			local ctx = context()
			Gearbox.request(config, engine, state, true, false, ctx)
			local plan = state.hbox.plan :: ShiftPlan.Plan
			local reachOk, offOk, feedOk, lastShare, firstShare = true, true, true, 0, nil :: number?
			runPlan(state, ctx, function(cut, blip, share)
				local t = state.hbox.time
				if state.hbox.plan == nil then
					return
				end
				if t < plan.pressStart then
					reachOk = reachOk and not cut and share == 1
				elseif t < plan.gateIn then
					offOk = offOk and cut and blip == 0
				elseif t < plan.clutchUp then
					feedOk = feedOk and not cut and share >= lastShare and share <= 1
					firstShare = firstShare or share
					lastShare = share
				end
			end)
			expect(reachOk).toBe(true)
			expect(offOk).toBe(true)
			expect(feedOk).toBe(true)
			expect((firstShare :: number) < 0.05).toBe(true)
			expect(lastShare > 0.95).toBe(true)
			local cut, blip, share = Gearbox.update(config, engine, state, ctx, STEP)
			expect(cut).toBe(false)
			expect(blip).toBe(0)
			expect(share).toBe(1)
		end
	)

	it("leaves the throttle to the player when the clutch is theirs", function()
		local state = engaged(2)
		local ctx = context({ gearboxMode = "manualClutch", clutchPedal = 1 })
		Gearbox.request(config, engine, state, true, false, ctx)
		expect(state.hbox.plan ~= nil).toBe(true)
		local untouched = true
		runPlan(state, ctx, function(cut, blip, share)
			untouched = untouched and not cut and blip == 0 and share == 1
		end)
		expect(untouched).toBe(true)
		expect(state.gear).toBe(3)
	end)

	it(
		"blips the automatic's own downshifts toward the lower gear, never E and Q's without rev-matching",
		function()
			local low = 1500 * RPM
			for _, case in { { "auto", true }, { "manual", false } } do
				local state = engaged(3)
				local ctx = context({
					gearboxMode = case[1],
					engineSpeed = low,
					outputSpeed = 3000 * RPM / config.ratios[3],
				})
				Gearbox.request(config, engine, state, false, true, ctx)
				local plan = state.hbox.plan :: ShiftPlan.Plan
				expect(plan.to).toBe(2)
				local blipped = false
				runPlan(state, ctx, function(_, blip)
					blipped = blipped or blip > 0
				end)
				expect(blipped).toBe(case[2])
			end
		end
	)

	it("refuses a downshift that would over-rev, and says so", function()
		local high = engaged(3)
		Gearbox.request(
			config,
			engine,
			high,
			false,
			true,
			context({ outputSpeed = 6000 * RPM / config.ratios[3] })
		)
		expect(high.hbox.plan).toBe(nil)
		expect(high.hbox.refusal).toBe("overRev")
		local fine = engaged(3)
		Gearbox.request(
			config,
			engine,
			fine,
			false,
			true,
			context({ outputSpeed = 4000 * RPM / config.ratios[3] })
		)
		expect((fine.hbox.plan :: ShiftPlan.Plan).to).toBe(2)
		expect(fine.hbox.refusal).toBe(nil)
	end)

	it("with the player's clutch, moves the lever only with the pedal past the bite point", function()
		local up = engaged(2)
		Gearbox.request(
			config,
			engine,
			up,
			true,
			false,
			context({ gearboxMode = "manualClutch", clutchPedal = 0.5 })
		)
		expect(up.hbox.plan).toBe(nil)
		expect(up.hbox.refusal).toBe("clutchUp")
		local down = engaged(2)
		local pressed = context({ gearboxMode = "manualClutch", clutchPedal = MANUAL.bitePoint })
		Gearbox.request(config, engine, down, true, false, pressed)
		expect((down.hbox.plan :: ShiftPlan.Plan).to).toBe(3)
	end)

	it("goes 1, N, R only near a standstill, each move through a plan", function()
		local state = engaged(1)
		local rolling = context({ groundSpeed = 5 })
		Gearbox.request(config, engine, state, false, true, rolling)
		expect(state.hbox.plan).toBe(nil)
		local stopped = context({ groundSpeed = 0, outputSpeed = 0 })
		Gearbox.request(config, engine, state, false, true, stopped)
		runPlan(state, stopped)
		expect(state.gear).toBe(0)
		Gearbox.request(config, engine, state, false, true, stopped)
		local plan = state.hbox.plan :: ShiftPlan.Plan
		expect(plan.knobDown).toBe(true)
		runPlan(state, stopped)
		expect(state.gear).toBe(-1)
		expect(Gearbox.select(config, state, 1, 0)).toBe(true)
		expect(state.gear).toBe(-1)
		runPlan(state, stopped)
		expect(state.gear).toBe(1)
	end)
end)

describe("H box retargets and queues", function()
	it("retargets a shift still short of its gate from the lever's place", function()
		local state = engaged(2)
		local ctx = context()
		Gearbox.request(config, engine, state, true, false, ctx)
		local first = state.hbox.plan :: ShiftPlan.Plan
		while state.hbox.time < (first.leverOut + first.across) / 2 do
			Gearbox.update(config, engine, state, ctx, STEP)
		end
		local column, row = ShiftPlan.lever(first, MANUAL.gates, state.hbox.time)
		Gearbox.request(config, engine, state, true, false, ctx)
		local second = state.hbox.plan :: ShiftPlan.Plan
		expect(second.from).toBe(2)
		expect(second.to).toBe(4)
		expect(second.startColumn).toBeNear(column, 1e-9)
		expect(second.startRow).toBeNear(row, 1e-9)
		expect(state.gear).toBe(2)
		runPlan(state, ctx)
		expect(state.gear).toBe(4)
	end)

	it("queues a shift asked for once the gear has engaged, and runs it after", function()
		local state = engaged(2)
		local ctx = context({ outputSpeed = 2500 * RPM / config.ratios[2] })
		Gearbox.request(config, engine, state, true, false, ctx)
		local first = state.hbox.plan :: ShiftPlan.Plan
		while state.hbox.time < first.gateIn do
			Gearbox.update(config, engine, state, ctx, STEP)
		end
		Gearbox.request(config, engine, state, true, false, ctx)
		expect(state.hbox.plan).toBe(first)
		expect(state.hbox.queued).toBe(4)
		while state.hbox.plan == first do
			Gearbox.update(config, engine, state, ctx, STEP)
		end
		expect(state.gear).toBe(3)
		expect((state.hbox.plan :: ShiftPlan.Plan).from).toBe(3)
		expect((state.hbox.plan :: ShiftPlan.Plan).to).toBe(4)
	end)
end)

describe("H box clutch and stall", function()
	it("bites from the bite point up and holds fully a bite width higher", function()
		expect(HBox.engagement(MANUAL, 1)).toBe(0)
		expect(HBox.engagement(MANUAL, MANUAL.bitePoint)).toBe(0)
		expect(HBox.engagement(MANUAL, MANUAL.bitePoint - MANUAL.biteWidth / 2)).toBeNear(0.5, 1e-12)
		expect(HBox.engagement(MANUAL, MANUAL.bitePoint - MANUAL.biteWidth)).toBe(1)
		expect(HBox.pedalFor(MANUAL, 0.5)).toBeNear(MANUAL.bitePoint - MANUAL.biteWidth / 2, 1e-12)
	end)

	it("stalls under its stall speed only with the player's clutch biting in gear", function()
		local low = 300 * RPM
		local own = engaged(1)
		Gearbox.update(
			config,
			engine,
			own,
			context({ gearboxMode = "manualClutch", engineSpeed = low }),
			STEP
		)
		expect(Gearbox.stalled(own)).toBe(true)
		local pressed = engaged(1)
		local down = context({ gearboxMode = "manualClutch", engineSpeed = low, clutchPedal = 1 })
		Gearbox.update(config, engine, pressed, down, STEP)
		expect(Gearbox.stalled(pressed)).toBe(false)
		local neutral = engaged(0)
		Gearbox.update(
			config,
			engine,
			neutral,
			context({ gearboxMode = "manualClutch", engineSpeed = low }),
			STEP
		)
		expect(Gearbox.stalled(neutral)).toBe(false)
		for _, mode in { "auto", "manual" } do
			local automatic = engaged(1)
			for _ = 1, 100 do
				Gearbox.update(
					config,
					engine,
					automatic,
					context({ gearboxMode = mode, engineSpeed = low }),
					STEP
				)
			end
			expect(Gearbox.stalled(automatic)).toBe(false)
		end
	end)

	it(
		"restarts only in neutral or with the pedal down, and clears a stall when the clutch is not the player's",
		function()
			local state = engaged(1)
			Gearbox.update(
				config,
				engine,
				state,
				context({ gearboxMode = "manualClutch", engineSpeed = 300 * RPM }),
				STEP
			)
			expect(Gearbox.restart(config, state, 0)).toBe(false)
			expect(Gearbox.restart(config, state, 1)).toBe(true)
			expect(Gearbox.stalled(state)).toBe(false)
			Gearbox.update(
				config,
				engine,
				state,
				context({ gearboxMode = "manualClutch", engineSpeed = 300 * RPM }),
				STEP
			)
			expect(Gearbox.stalled(state)).toBe(true)
			Gearbox.update(
				config,
				engine,
				state,
				context({ gearboxMode = "manual", engineSpeed = 300 * RPM }),
				STEP
			)
			expect(Gearbox.stalled(state)).toBe(false)
		end
	)
end)

describe("H box limbs", function()
	it(
		"brings the hand to the knob by the end of the reach, holds it for the linger, then lets go",
		function()
			local state = engaged(2)
			local ctx = context()
			Gearbox.request(config, engine, state, true, false, ctx)
			local plan = state.hbox.plan :: ShiftPlan.Plan
			while state.hbox.time < plan.reachEnd - STEP / 2 do
				Gearbox.update(config, engine, state, ctx, STEP)
			end
			expect(state.hbox.handAt).toBeNear(1, 2 * STEP / MANUAL.timing.reach)
			runPlan(state, ctx)
			local lingered = 0
			while state.hbox.handAt >= 1 and lingered < 5 do
				Gearbox.update(config, engine, state, ctx, STEP)
				lingered += STEP
			end
			expect(lingered).toBeNear(MANUAL.timing.linger, 2 * STEP)
			local released = 0
			while state.hbox.handAt > 0 and released < 5 do
				Gearbox.update(config, engine, state, ctx, STEP)
				released += STEP
			end
			expect(released).toBeNear(MANUAL.timing.release, 2 * STEP)
		end
	)

	it("readies the hand at full throttle near the upshift point below top gear, never in top", function()
		local near = Boss302.modes.Normal.upshiftRpm.full * 0.9 * RPM
		for _, case in { { 3, true }, { #config.ratios, false } } do
			local state = engaged(case[1])
			local ctx = context({
				gearboxMode = "manual",
				throttle = 1,
				engineSpeed = near,
				outputSpeed = near / config.ratios[case[1]],
			})
			for _ = 1, 400 do
				Gearbox.update(config, engine, state, ctx, STEP)
			end
			expect(state.hbox.handAt == 1).toBe(case[2])
		end
	end)
end)

describe("H box made easy", function()
	it(
		"in manual, drops in one shift to the gear that keeps the engine at idle once the car slows under it",
		function()
			local idle = engine.idleRpm * RPM
			for _, case in { { 600, 4 }, { 400, 2 }, { 0, 1 } } do
				local state = engaged(5)
				local slow = context({ engineSpeed = idle, outputSpeed = case[1] * RPM / config.ratios[5] })
				Gearbox.update(config, engine, state, slow, STEP)
				expect((state.hbox.plan :: ShiftPlan.Plan).to).toBe(case[2])
			end
			local held = engaged(5)
			Gearbox.update(
				config,
				engine,
				held,
				context({ outputSpeed = 800 * RPM / config.ratios[5] }),
				STEP
			)
			expect(held.hbox.plan).toBe(nil)
			local own = engaged(5)
			local stopped = context({ gearboxMode = "manualClutch", clutchPedal = 1, outputSpeed = 0 })
			Gearbox.update(config, engine, own, stopped, STEP)
			expect(own.hbox.plan).toBe(nil)
		end
	)

	it("drives the clutch mode as manual on a car that does not offer the player's clutch", function()
		local manual = table.clone(MANUAL)
		manual.playerClutch = false
		local offered = table.clone(config)
		offered.manual = manual
		local state = engaged(2)
		local ctx = context({ gearboxMode = "manualClutch", clutchPedal = 0, engineSpeed = 300 * RPM })
		Gearbox.request(offered, engine, state, true, false, ctx)
		expect(state.hbox.refusal).toBe(nil)
		expect((state.hbox.plan :: ShiftPlan.Plan).to).toBe(3)
		local cutSeen = false
		while state.hbox.plan ~= nil do
			local cut = Gearbox.update(offered, engine, state, ctx, STEP)
			cutSeen = cutSeen or cut
		end
		expect(cutSeen).toBe(true)
		expect(Gearbox.stalled(state)).toBe(false)
	end)
end)
