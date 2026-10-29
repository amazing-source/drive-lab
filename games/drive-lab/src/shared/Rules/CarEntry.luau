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
export type Action = "Enter" | "Exit" | "Door" | "Start" | "Cancel"
export type ApproachPlan = "Settle" | "Straight" | "LineUp"

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

-- A door the local player asked to move from outside: the standing clip to play and how far
-- into it, or finished (the clip has ended, or the server never moved the door: refused).
export type OutsideRequest = { clip: Config.ClipName?, into: number, finished: boolean }

export type Startup = {
	stage: Stage,
	-- Seconds since START was pressed, once it has been.
	sincePress: number?,
	drivable: boolean,
}

local ACTIONS: { [string]: Action } =
	{ Enter = "Enter", Exit = "Exit", Door = "Door", Start = "Start", Cancel = "Cancel" }
local OUTSIDE_CLIPS: { [string]: Config.ClipName } =
	{ OutsideOpen = "OutsideOpen", OutsideClose = "OutsideClose" }

-- The clips of each sequence, from a shut or an open door.
local ENTER_SHUT: { Config.ClipName } = { "OutsideOpen", "GetIn" }
local ENTER_OPEN: { Config.ClipName } = { "GetIn" }
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

-- `lastUntil` ends the last clip early, at that many seconds into it.
local function chain(names: { Config.ClipName }, lastUntil: number?): { Step }
	local steps: { Step } = table.create(#names)
	local start = 0
	for index, name: Config.ClipName in names do
		local duration = Config.CLIPS[name].duration
		if index == #names and lastUntil then
			duration = math.min(duration, lastUntil)
		end
		local step: Step = { clip = name, start = start, duration = duration }
		table.insert(steps, step)
		start += duration
	end
	return steps
end

-- The clips a sequence plays in order; it skips opening a door that is already open. Getting in
-- closes the door within GetIn itself; getting out ends in OutsideClose's stance clear of the car.
function CarEntry.steps(kind: EntryKind, doorOpen: boolean): { Step }
	if kind == "Enter" then
		return chain(if doorOpen then ENTER_OPEN else ENTER_SHUT)
	elseif kind == "Exit" then
		return chain(if doorOpen then EXIT_OPEN else EXIT_SHUT, Config.EXIT_END.at)
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

-- Not while the door moves: the exit starts from the door at rest, shut or open.
function CarEntry.canExit(state: State, now: number, speedKmh: number): boolean
	return CarEntry.phase(state, now) == "Seated"
		and speedKmh <= Config.EXIT_MAX_KMH
		and not midStartup(state, now)
		and CarEntry.doorIdle(state, now)
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

-- `askedAt` is the server time of the request. A motion that started before it (less the clock
-- slack) is someone else's.
function CarEntry.outsideRequest(state: State, now: number, askedAt: number): OutsideRequest
	local clip: Config.ClipName? = OUTSIDE_CLIPS[state.door]
	if clip ~= nil and state.doorAt >= askedAt - Config.REQUEST_SLACK then
		-- Before its start the clip holds its first frame.
		local into = math.max(now - state.doorAt, 0)
		if into < Config.CLIPS[clip].duration then
			return { clip = clip, into = into, finished = false }
		end
		return { clip = nil, into = 0, finished = true }
	end
	return { clip = nil, into = 0, finished = now - askedAt > Config.REFUSED_SECONDS }
end

-- The server time a sequence a client asked for starts: when it asked (the end of its placing on
-- the mark), but never before the state can reach that client, `oneWay` seconds away (at most
-- MAX_ONE_WAY), else the client would show the sequence already under way; at most ENTRY_LEAD
-- after that. The earliest if it asked nothing usable.
function CarEntry.entryStart(now: number, asked: unknown, oneWay: unknown): number
	local delay = 0
	if typeof(oneWay) == "number" and oneWay == oneWay then
		delay = math.clamp(oneWay, 0, Config.MAX_ONE_WAY)
	end
	local earliest = now + delay
	if typeof(asked) ~= "number" or asked ~= asked or math.abs(asked) == math.huge then
		return earliest
	end
	return math.clamp(asked, earliest, earliest + Config.ENTRY_LEAD)
end

-- How the walk reaches the mark from where the body stands: placed on it when already there;
-- straight in from the corridor in front of it, once far enough out to turn clear of the car or
-- already facing it; else round the car to the point in front of it first. `lateral` and
-- `outward` are studs in the mark's frame, outward away from the car; `turn` is how far the
-- body faces off the mark's facing, in radians.
function CarEntry.approachPlan(lateral: number, outward: number, turn: number): ApproachPlan
	local approach = Config.APPROACH
	if math.sqrt(lateral * lateral + outward * outward) <= approach.arrived then
		return "Settle"
	end
	local inCorridor = outward > 0 and math.abs(lateral) <= outward * math.tan(approach.lineUpAngle)
	if inCorridor and (outward >= approach.lineUp or math.abs(turn) <= approach.lineUpAngle) then
		return "Straight"
	end
	return "LineUp"
end

-- Seconds to place the body exactly on the mark from `distance` studs and `turn` radians away.
function CarEntry.settleSeconds(distance: number, turn: number): number
	local approach = Config.APPROACH
	local seconds = math.max(distance / approach.settleSpeed, math.abs(turn) / approach.turnSpeed)
	return math.min(seconds, approach.settleSeconds)
end

-- How far through the settle the body is, 0 to 1, eased at both ends.
function CarEntry.settleShare(elapsed: number, seconds: number): number
	if seconds <= 0 then
		return 1
	end
	local share = math.clamp(elapsed / seconds, 0, 1)
	return share * share * (3 - 2 * share)
end

-- A held exit key gets out once held this long; a shorter tap stays a gear change.
function CarEntry.exitHeld(heldFor: number): boolean
	return heldFor >= Config.EXIT_HOLD_SECONDS
end

-- An exit key held `heldFor` seconds: whether it asks to get out this frame, and whether it has
-- asked by the end of it (`asked` is the previous frame's). It waits for the door to stop, since
-- the server refuses an exit while the door moves. A door seen moving after it asked reached the
-- server first and had the exit refused, so it asks again once the door stops. Once getting out
-- (or still getting in) it asks nothing more.
function CarEntry.heldExit(state: State, now: number, heldFor: number, asked: boolean): (boolean, boolean)
	if CarEntry.phase(state, now) ~= "Seated" then
		return false, true
	elseif not CarEntry.doorIdle(state, now) then
		return false, false
	end
	local ask = not asked and CarEntry.exitHeld(heldFor)
	return ask, asked or ask
end

function CarEntry.parseAction(payload: unknown): Action?
	return if typeof(payload) == "string" then ACTIONS[payload] else nil
end

return table.freeze(CarEntry)
