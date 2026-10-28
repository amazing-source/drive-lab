--!strict
--[[
	Everything about getting in, getting out, the door and the start-up that follows from the
	car's replicated state and the server's clock: which clip plays, how open the door is,
	where the start-up is, what the instruments show, and what a request may do now. The
	server and every client call the same functions, so they agree without more messages.
]]
local Config = require("../Config/CarEntry")

export type EntryKind = "None" | "Enter" | "Exit"
export type Phase = "Outside" | "Entering" | "Seated" | "Exiting"
export type EngineState = "Off" | "On"
export type Stage = "Off" | "Reaching" | "Cranking" | "Running"
export type Action = "Enter" | "Exit" | "Door" | "Start"

export type State = {
	-- The last sequence the server started, and when (server time).
	entry: EntryKind,
	entryAt: number,
	-- The door stood open when that sequence began, so it skipped the clip that opens it.
	entryDoorOpen: boolean,
	door: Config.DoorMotion,
	doorAt: number,
	engine: EngineState,
	engineAt: number,
}

export type Step = { clip: Config.ClipName, start: number, duration: number }

export type Startup = {
	stage: Stage,
	-- Seconds since START was pressed, once it has been.
	sincePress: number?,
	drivable: boolean,
}

local ACTIONS: { [string]: Action } = { Enter = "Enter", Exit = "Exit", Door = "Door", Start = "Start" }
-- The clips of each sequence, from a shut or an open door.
local ENTER_SHUT: { Config.ClipName } = { "OutsideOpen", "GetIn", "InsideClose" }
local ENTER_OPEN: { Config.ClipName } = { "GetIn", "InsideClose" }
local EXIT_SHUT: { Config.ClipName } = { "InsideOpen", "GetOut", "OutsideClose" }
local EXIT_OPEN: { Config.ClipName } = { "GetOut", "OutsideClose" }

local CarEntry = {}

function CarEntry.sample(curve: Config.Curve, t: number): number
	local times, values = curve.times, curve.values
	if t <= times[1] then
		return values[1]
	end
	for index = 2, #times do
		if t < times[index] then
			local share = (t - times[index - 1]) / (times[index] - times[index - 1])
			return values[index - 1] + (values[index] - values[index - 1]) * share
		end
	end
	return values[#values]
end

local function chain(names: { Config.ClipName }): { Step }
	local steps: { Step } = table.create(#names)
	local start = 0
	for _, name: Config.ClipName in names do
		local duration = Config.CLIPS[name].duration
		local step: Step = { clip = name, start = start, duration = duration }
		table.insert(steps, step)
		start += duration
	end
	return steps
end

-- The clips a sequence plays in order; it skips opening a door that is already open.
function CarEntry.steps(kind: EntryKind, doorOpen: boolean): { Step }
	if kind == "Enter" then
		return chain(if doorOpen then ENTER_OPEN else ENTER_SHUT)
	elseif kind == "Exit" then
		return chain(if doorOpen then EXIT_OPEN else EXIT_SHUT)
	end
	return {}
end

function CarEntry.length(steps: { Step }): number
	local last = steps[#steps]
	return if last then last.start + last.duration else 0
end

-- The step playing `elapsed` seconds into a sequence and the time into it, held at the last
-- step's end once the sequence is over.
function CarEntry.stepAt(steps: { Step }, elapsed: number): (Step?, number)
	for _, step in steps do
		if elapsed < step.start + step.duration then
			return step, math.max(elapsed - step.start, 0)
		end
	end
	local last = steps[#steps]
	return last, if last then last.duration else 0
end

function CarEntry.phase(state: State, now: number): Phase
	if state.entry == "None" then
		return "Outside"
	end
	local running = now - state.entryAt < CarEntry.length(CarEntry.steps(state.entry, state.entryDoorOpen))
	if state.entry == "Enter" then
		return if running then "Entering" else "Seated"
	end
	return "Exiting"
end

function CarEntry.motionOpenness(motion: Config.DoorMotion, t: number): number
	if motion == "Closed" then
		return 0
	elseif motion == "Open" then
		return 1
	end
	local curve = Config.CLIPS[motion].door
	assert(curve, `{motion} does not move the door`)
	return CarEntry.sample(curve, t)
end

local function sequenceOpenness(state: State, elapsed: number): number?
	local steps = CarEntry.steps(state.entry, state.entryDoorOpen)
	if elapsed >= CarEntry.length(steps) then
		return nil
	end
	local openness = if state.entryDoorOpen then 1 else 0
	for _, step in steps do
		local curve = Config.CLIPS[step.clip].door
		if curve and elapsed >= step.start then
			openness = CarEntry.sample(curve, elapsed - step.start)
		end
	end
	return openness
end

-- 0 shut to 1 fully open. A running sequence drives the door; otherwise its own motion does.
function CarEntry.doorOpenness(state: State, now: number): number
	if state.entry ~= "None" then
		local during = sequenceOpenness(state, now - state.entryAt)
		if during then
			return during
		end
	end
	return CarEntry.motionOpenness(state.door, now - state.doorAt)
end

-- The door is at rest: no sequence runs and its last motion has finished.
function CarEntry.doorIdle(state: State, now: number): boolean
	local phase = CarEntry.phase(state, now)
	if phase == "Entering" or phase == "Exiting" then
		return false
	end
	if state.door == "Closed" or state.door == "Open" then
		return true
	end
	return now - state.doorAt >= Config.CLIPS[state.door].duration
end

function CarEntry.doorClosed(state: State, now: number): boolean
	return CarEntry.doorIdle(state, now) and CarEntry.doorOpenness(state, now) <= 0
end

-- The rest the door settles at when a sequence is cut short (the driver left or died).
function CarEntry.nearestRest(state: State, now: number): Config.DoorMotion
	return if CarEntry.doorOpenness(state, now) >= 0.5 then "Open" else "Closed"
end

function CarEntry.startup(state: State, now: number): Startup
	if state.engine == "Off" then
		return { stage = "Off", sincePress = nil, drivable = false }
	end
	local t = now - state.engineAt
	local settings = Config.STARTUP
	local drivable = t >= settings.drivableAt
	if t < settings.pressAt then
		return { stage = "Reaching", sincePress = nil, drivable = drivable }
	end
	local sincePress = t - settings.pressAt
	return {
		stage = if sincePress < settings.catchAfter then "Cranking" else "Running",
		sincePress = sincePress,
		drivable = drivable,
	}
end

-- The revs the instruments show: none before START, the start-up's own revs while it runs
-- (never below what the engine turns once it drives), then the engine's.
function CarEntry.shownRpm(state: State, now: number, engineRpm: number): number
	local startup = CarEntry.startup(state, now)
	local sincePress = startup.sincePress
	if sincePress == nil then
		return 0
	end
	local curve = Config.STARTUP.rpm
	if sincePress >= curve.times[#curve.times] then
		return engineRpm
	end
	local settling = CarEntry.sample(curve, sincePress)
	return if startup.drivable then math.max(engineRpm, settling) else settling
end

-- How far the START flap is lifted, 0 to 1: the right hand lifts it before the press and lets
-- it fall after.
function CarEntry.flapOpenness(state: State, now: number): number
	if state.engine == "Off" then
		return 0
	end
	local t = now - state.engineAt
	local settings = Config.STARTUP
	local move = settings.flapMove
	if t < settings.flapDownAt then
		return math.clamp((t - (settings.flapUpAt - move)) / move, 0, 1)
	end
	return math.clamp(1 - (t - settings.flapDownAt) / move, 0, 1)
end

-- The brake the right foot holds while the car starts, until driving unlocks; nil otherwise.
function CarEntry.startupBrake(state: State, now: number): number?
	local startup = CarEntry.startup(state, now)
	if startup.stage == "Off" or startup.drivable then
		return nil
	end
	return Config.STARTUP.brake
end

function CarEntry.drivable(state: State, now: number): boolean
	return CarEntry.phase(state, now) == "Seated"
		and CarEntry.startup(state, now).drivable
		and CarEntry.doorClosed(state, now)
end

local function midStartup(state: State, now: number): boolean
	local stage = CarEntry.startup(state, now).stage
	return stage == "Reaching" or stage == "Cranking"
end

function CarEntry.canEnter(state: State, now: number): boolean
	return CarEntry.phase(state, now) == "Outside" and CarEntry.doorIdle(state, now)
end

function CarEntry.canExit(state: State, now: number, speedKmh: number): boolean
	return CarEntry.phase(state, now) == "Seated"
		and speedKmh <= Config.EXIT_MAX_KMH
		and not midStartup(state, now)
end

function CarEntry.canStart(state: State, now: number): boolean
	return CarEntry.phase(state, now) == "Seated"
		and state.engine == "Off"
		and CarEntry.doorClosed(state, now)
end

-- From inside the seated driver may move the door; from outside, anyone at the mark while
-- nobody is in a sequence.
function CarEntry.canMoveDoor(state: State, now: number, speedKmh: number, inside: boolean): boolean
	local phase = CarEntry.phase(state, now)
	if inside then
		return phase == "Seated"
			and speedKmh <= Config.DOOR_MAX_KMH
			and not midStartup(state, now)
			and CarEntry.doorIdle(state, now)
	end
	return phase == "Outside" and CarEntry.doorIdle(state, now)
end

-- The clip that moves the door from where it rests, from inside or outside.
function CarEntry.doorClip(state: State, now: number, inside: boolean): Config.ClipName
	local open = CarEntry.doorOpenness(state, now) >= 0.5
	if inside then
		return if open then "InsideClose" else "InsideOpen"
	end
	return if open then "OutsideClose" else "OutsideOpen"
end

-- The body's scale `elapsed` seconds into a change from `from` to `to`, eased at both ends.
function CarEntry.scale(from: number, to: number, elapsed: number): number
	local share = math.clamp(elapsed / Config.SCALE_SECONDS, 0, 1)
	return from + (to - from) * share * share * (3 - 2 * share)
end

function CarEntry.parseAction(payload: unknown): Action?
	return if typeof(payload) == "string" then ACTIONS[payload] else nil
end

return table.freeze(CarEntry)
