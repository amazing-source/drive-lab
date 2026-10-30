--!strict
--[[
	Getting in and out of a car, its driver's door, and starting it. The server is the only
	writer of this state: attributes on the car model, so every client (late joiners too)
	derives the same door angle, body animation and start-up from the same server times
	(Rules/CarEntry). Each car's clips, door curves and start-up are its own (the Door and
	Startup of its catalog entry), from the Blender pipeline (docs/pipelines/CAR_ENTRY.md); an
	empty clip id plays the timings with no body animation.
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

-- A cabin control the start-up turns on its hinge (the model binding's `controls`, by name):
-- it reaches `angle` radians `at` seconds after the start key, taking `move` seconds, and turns
-- back from `back` seconds after the key; with no `back` it holds until the engine is off.
export type ControlMove = { control: string, angle: number, move: number, at: number, back: number? }

-- A car's start, as a sequence from the start key: the cabin controls the driver works, the
-- START press, the engine catching, the hands back on the wheel, driving unlocked.
export type Startup = {
	moves: { ControlMove },
	-- Seconds after the start key: START is pressed (the starter turns from here), both hands
	-- are on the wheel, driving unlocks.
	pressAt: number,
	wheelAt: number,
	drivableAt: number,
	-- From the press: the starter cranks, the engine catches and flares, then a fast idle
	-- settles. The revs the instruments show over that time.
	catchAfter: number,
	rpm: Curve,
	-- How hard the right foot holds the brake from the key until driving unlocks (0 to 1).
	brake: number,
}

export type Region = { from: number, to: number }

-- The door's latch as it starts to open and its shut as it closes: regions of one uploaded
-- sound, each starting at its sound's onset.
export type DoorSound = {
	id: string,
	latch: Region,
	shut: Region,
	-- Seconds ahead of the door's own timeline the sounds are started: the shut's thump peaks
	-- this long into its region, so it lands as the door closes, and the latch clicks just before
	-- the door moves.
	lead: number,
	volume: number,
	-- Studs: full volume within the minimum, silent past the maximum.
	rollOff: Region,
}

-- One car's door: the clips that get the driver in and out through it, and its sounds.
export type Door = {
	clips: { [ClipName]: Clip },
	-- The looped seated pose the entry ends in and the exit starts from.
	seatedPose: string,
	-- Where the character stands to use the door, from the driver's seat in the car frame
	-- (metres, right and forward), facing the seat.
	mark: { right: number, forward: number },
	-- Getting out ends `at` seconds into OutsideClose, before its last steps back in to the mark:
	-- there its walk back passes a stance with the feet together, facing the car, clear of the
	-- car's collision box at any heading. The root is put there (metres, as `mark`), facing as at
	-- the mark. Opening or shutting the door from outside still plays the whole clip.
	exitEnd: { at: number, right: number, forward: number },
	sound: DoorSound,
}

-- What the entry rules need of a car; a catalog entry is one.
export type Car = { door: Door, startup: Startup }

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
	-- The walk to the mark, in studs, radians and seconds. Unless it already stands in the
	-- corridor straight out from the mark (`lineUpAngle` either side, at least `lineUp` out), the
	-- body walks round the car's collision box grown by `margin` (Rules/ApproachPath) to `lineUp`
	-- studs in front of the mark, turns there to face the car, clear of it, and walks straight in
	-- to `short` studs in front of the mark, never to the mark itself: a walk that overshoots it
	-- presses the torso into the car's box, and the server, which moves the parked car, pushes the
	-- car away. It turns from one waypoint to the next within `pass` of it; it is stopped on a point within
	-- `arrived`; a leg that has not closed in by `progress` for `stallSeconds` is blocked, and
	-- the walk tries again from where it stands, `tries` times in all. Stopped within `reach` of
	-- the mark, it is placed exactly: moved and turned at `settleSpeed` and `turnSpeed`, eased,
	-- over at most `settleSeconds`.
	APPROACH: {
		lineUp: number,
		lineUpAngle: number,
		short: number,
		margin: number,
		pass: number,
		arrived: number,
		progress: number,
		stallSeconds: number,
		tries: number,
		reach: number,
		settleSpeed: number,
		turnSpeed: number,
		settleSeconds: number,
	},
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
	-- Seconds ahead of the server's clock an entry may be asked to start: the client asks as its
	-- settle at the mark begins, for the moment it ends, so the round trip runs alongside it.
	ENTRY_LEAD: number,
	-- Seconds: the longest delay to a client a sequence's start waits for, and the margin added to
	-- twice a client's measured one-way delay. On the poor network profile a start that allowed
	-- only the measured delay and 0.1 s still reached the client late 2 times in 10 door clips
	-- from outside, which then began 0.6 to 0.8 studs under way (measured in Play).
	MAX_ONE_WAY: number,
	LATENCY_MARGIN: number,
	-- Seconds the server waits for its own copy of the body to reach the mark (it lags the
	-- client's by the network) before it refuses a request from outside.
	ARRIVAL_WAIT: number,
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
	-- Measured in Play (2026-10-28): Humanoid:MoveTo stops 0.76 to 0.92 studs short of its
	-- target, and its own turn leaves 36 degrees of a half turn after 0.3 s. On the mark at full
	-- size the torso clears the collision box by 0.16 studs facing the car and touches it turned
	-- 10 degrees, so the body turns only clear of the car, or held.
	APPROACH = table.freeze({
		lineUp = 1.5,
		lineUpAngle = math.rad(10),
		short = 0.9,
		margin = 0.75,
		pass = 0.5,
		arrived = 0.25,
		progress = 0.1,
		stallSeconds = 0.4,
		tries = 2,
		reach = 2,
		settleSpeed = 12.5,
		turnSpeed = math.rad(600),
		settleSeconds = 0.2,
	}),
	MARK_TOLERANCE = 2,
	PROMPT_DISTANCE = 6,
	RESERVE_SECONDS = 6,
	APPROACH_SECONDS = 3,
	REFUSED_SECONDS = 3,
	REQUEST_SLACK = 1,
	ENTRY_LEAD = 0.3,
	MAX_ONE_WAY = 0.5,
	LATENCY_MARGIN = 0.1,
	ARRIVAL_WAIT = 1.5,
	EXIT_MAX_KMH = 3,
	DOOR_MAX_KMH = 5,
	EXIT_HOLD_SECONDS = 0.35,
}

return table.freeze(CarEntry)
