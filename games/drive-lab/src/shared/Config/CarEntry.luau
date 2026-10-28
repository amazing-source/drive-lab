--!strict
--[[
	Getting in and out of a car, its driver's door, and starting it. The server is the only
	writer of this state: attributes on the car model, so every client (late joiners too)
	derives the same door angle, body animation and start-up from the same server times
	(Rules/CarEntry). Clip ids, durations and door curves come from the Blender pipeline
	(docs/pipelines/CAR_ENTRY.md); an empty id plays the timings with no body animation.
]]

export type ClipName = "OutsideOpen" | "GetIn" | "InsideClose" | "InsideOpen" | "GetOut" | "OutsideClose"

-- "Closed" and "Open" are rests; a clip name is the door moving with that clip, from its door
-- attribute's time.
export type DoorMotion = "Closed" | "Open" | ClipName

-- Samples over a clip's time, linear between them, held past either end.
export type Curve = { times: { number }, values: { number } }

export type Clip = {
	-- Played with the character's root welded to the driver's seat.
	seated: string,
	-- The same motion with the root standing at the door mark (outside clips only): opening or
	-- shutting the door without getting in.
	standing: string?,
	duration: number,
	-- How open the door is over the clip, 0 shut to 1 fully open; nil if the clip leaves it.
	door: Curve?,
}

export type Startup = {
	-- Seconds after the start key: the right hand reaches the flap, lifts it, presses START
	-- (the starter turns from here), lets the flap down, and both hands are on the wheel.
	flapUpAt: number,
	pressAt: number,
	flapDownAt: number,
	wheelAt: number,
	-- Driving unlocks this long after the key.
	drivableAt: number,
	-- From the press: the starter cranks, the engine catches and flares, then a fast idle
	-- settles. The revs the instruments show over that time.
	catchAfter: number,
	rpm: Curve,
	-- How far the flap opens (radians) and how long it takes to lift or fall; how hard the right
	-- foot holds the brake from the key until driving unlocks (0 to 1).
	flapAngle: number,
	flapMove: number,
	brake: number,
}

export type CarEntry = {
	ATTRIBUTES: {
		ENTRY: string,
		ENTRY_AT: string,
		ENTRY_DOOR_OPEN: string,
		DOOR: string,
		DOOR_AT: string,
		ENGINE: string,
		ENGINE_AT: string,
		RESERVED_BY: string,
		RESERVED_AT: string,
	},
	CLIPS: { [ClipName]: Clip },
	-- The looped seated pose the entry ends in and the exit starts from.
	SEATED_POSE: string,
	STARTUP: Startup,
	-- Where the character stands to use the door, from the driver's seat in the car frame
	-- (metres, right and forward), facing the seat.
	MARK: { right: number, forward: number },
	-- Studs: how close to the mark the server accepts a character, and how close it must be
	-- to the door to be offered the prompts.
	MARK_TOLERANCE: number,
	PROMPT_DISTANCE: number,
	-- Seconds a prompt holds the seat or the door for the player walking to the mark.
	RESERVE_SECONDS: number,
	-- Seconds the client walks toward the mark before giving up.
	APPROACH_SECONDS: number,
	-- Seconds a request waits for the server to act before it counts as refused, and the clock
	-- skew allowed between the client's request time and the server's start of the motion.
	REFUSED_SECONDS: number,
	REQUEST_SLACK: number,
	-- Seconds over which the body changes between its own size and the seated size.
	SCALE_SECONDS: number,
	-- Speeds (km/h) at or below which one may get out, or open or shut the door from inside.
	EXIT_MAX_KMH: number,
	DOOR_MAX_KMH: number,
	-- Seconds the exit key is held to get out; a tap stays a gear change.
	EXIT_HOLD_SECONDS: number,
}

local CarEntry: CarEntry = {
	ATTRIBUTES = table.freeze({
		ENTRY = "Entry",
		ENTRY_AT = "EntryAt",
		ENTRY_DOOR_OPEN = "EntryDoorOpen",
		DOOR = "Door",
		DOOR_AT = "DoorAt",
		ENGINE = "Engine",
		ENGINE_AT = "EngineAt",
		RESERVED_BY = "ReservedBy",
		RESERVED_AT = "ReservedAt",
	}),
	-- EST until the Blender pipeline delivers: timings for a 1.5x world and a driver at
	-- Driving.DRIVER_SCALE, door curves eased between the moments a hand moves it.
	CLIPS = table.freeze({
		OutsideOpen = table.freeze({
			seated = "",
			standing = "",
			duration = 2.2,
			door = table.freeze({ times = { 0.7, 1.0, 1.6, 2.0 }, values = { 0, 0.08, 0.75, 1 } }),
		}),
		GetIn = table.freeze({ seated = "", duration = 3.6 }),
		InsideClose = table.freeze({
			seated = "",
			duration = 1.6,
			door = table.freeze({ times = { 0.4, 0.9, 1.3 }, values = { 1, 0.45, 0 } }),
		}),
		InsideOpen = table.freeze({
			seated = "",
			duration = 1.4,
			door = table.freeze({ times = { 0.3, 0.5, 1.1 }, values = { 0, 0.1, 1 } }),
		}),
		GetOut = table.freeze({ seated = "", duration = 3.4 }),
		OutsideClose = table.freeze({
			seated = "",
			standing = "",
			duration = 1.8,
			door = table.freeze({ times = { 0.4, 0.9, 1.4 }, values = { 1, 0.5, 0 } }),
		}),
	}),
	SEATED_POSE = "",
	STARTUP = table.freeze({
		flapUpAt = 1.0,
		pressAt = 1.5,
		flapDownAt = 2.1,
		wheelAt = 2.9,
		drivableAt = 3.1,
		-- Measured on the start-up recording the engine sound plays (Assetto Corsa mod,
		-- 13_Avent_Startup_Race_Adaptive_Idle.wav): about 0.7 s of starter, the catch at 0.75 s,
		-- the flare at its loudest and highest 1.25 to 1.5 s, loud until 3.2 s, a fast idle
		-- about 1.17 times the idle's pitch settling to idle by 10 s. Revs from the 950 rpm idle
		-- and that pitch ratio (the flare's line is 1.9 times the idle's).
		catchAfter = 0.75,
		rpm = table.freeze({
			times = { 0, 0.7, 0.8, 1.0, 1.3, 1.6, 2.2, 3.2, 3.6, 6.0, 8.0, 10.0 },
			values = { 250, 250, 700, 1400, 1800, 1750, 1500, 1250, 1120, 1080, 1020, 950 },
		}),
		flapAngle = math.rad(70),
		flapMove = 0.25,
		brake = 0.6,
	}),
	MARK = table.freeze({ right = -0.92, forward = 0 }),
	MARK_TOLERANCE = 2,
	PROMPT_DISTANCE = 6,
	RESERVE_SECONDS = 4,
	APPROACH_SECONDS = 3,
	REFUSED_SECONDS = 1.5,
	REQUEST_SLACK = 1,
	SCALE_SECONDS = 0.8,
	EXIT_MAX_KMH = 3,
	DOOR_MAX_KMH = 5,
	EXIT_HOLD_SECONDS = 0.6,
}

return table.freeze(CarEntry)
