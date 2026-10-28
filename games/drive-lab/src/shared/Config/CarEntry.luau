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
	-- Getting out ends `at` seconds into OutsideClose, before its last steps back in to the mark:
	-- there its walk back passes a stance with the feet together, facing the car, clear of the
	-- car's collision box at any heading. The root is put there (metres, as MARK), facing as at
	-- the mark. Opening or shutting the door from outside still plays the whole clip.
	EXIT_END: { at: number, right: number, forward: number },
	-- The walk to the mark, in studs, radians and seconds. Unless it already stands in the
	-- corridor straight out from the mark (`lineUpAngle` either side, at least `lineUp` out), the
	-- body walks round the car's collision box grown by `margin` (Rules/ApproachPath) to `lineUp`
	-- studs in front of the mark, turns there to face the car, clear of it, and walks straight in.
	-- It turns from one waypoint to the next within `pass` of it; it is stopped on a point within
	-- `arrived`; a leg that has not closed in by `progress` for `stallSeconds` is blocked, and
	-- the walk tries again from where it stands, `tries` times in all. Stopped within `reach` of
	-- the mark, it is placed exactly: moved and turned at `settleSpeed` and `turnSpeed`, eased,
	-- over at most `settleSeconds`.
	APPROACH: {
		lineUp: number,
		lineUpAngle: number,
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
	-- From the Blender pipeline (docs/pipelines/CAR_ENTRY_ANIMATION.md, 2026-10-28): authored at
	-- Driving.DRIVER_SCALE against the cut door, a key on every frame, contact-checked (contacts
	-- that must touch, the decided ones named in docs/evidence/car-entry-anim/allow_*.json) and
	-- uploaded through the guard; each door curve is the door keyed on the same timeline as the hand.
	-- GetIn carries the close (#9): the hand rides the door's lower inner edge from half open, then
	-- the strap from 30 degrees; InsideClose takes the strap at 30 degrees.
	CLIPS = table.freeze({
		OutsideOpen = table.freeze({
			seated = "rbxassetid://105348915995074",
			standing = "rbxassetid://116794100117562",
			duration = 3.333,
			door = table.freeze({
				times = { 0.967, 1.3, 1.5, 1.667, 1.867, 2.033, 2.133, 2.333, 2.533, 2.7, 2.8, 2.933 },
				values = { 0, 0.035, 0.089, 0.153, 0.258, 0.374, 0.459, 0.66, 0.834, 0.94, 0.98, 1 },
			}),
		}),
		GetIn = table.freeze({
			seated = "rbxassetid://88140349551789",
			duration = 4.267,
			door = table.freeze({
				times = {
					2.533,
					2.567,
					2.6,
					2.667,
					2.7,
					2.8,
					2.833,
					2.867,
					2.933,
					3.133,
					3.267,
					3.333,
					3.5,
					3.6,
					3.667,
					3.733,
				},
				values = {
					1,
					0.988,
					0.957,
					0.87,
					0.812,
					0.604,
					0.542,
					0.5,
					0.465,
					0.372,
					0.33,
					0.287,
					0.139,
					0.054,
					0.015,
					0,
				},
			}),
		}),
		InsideClose = table.freeze({
			seated = "rbxassetid://86043343714462",
			duration = 1.8,
			door = table.freeze({
				times = { 0.267, 0.3, 0.367, 0.467, 0.5, 0.567, 0.7, 0.833, 0.967, 1.067, 1.233, 1.3, 1.333 },
				values = { 1, 0.995, 0.961, 0.88, 0.847, 0.756, 0.55, 0.369, 0.228, 0.143, 0.031, 0.004, 0 },
			}),
		}),
		InsideOpen = table.freeze({
			seated = "rbxassetid://93977108041759",
			duration = 1.6,
			door = table.freeze({
				times = { 0.5, 0.767, 0.833, 0.9, 1, 1.067, 1.233, 1.367, 1.433, 1.5, 1.533, 1.567 },
				values = { 0, 0.05, 0.076, 0.134, 0.25, 0.347, 0.649, 0.844, 0.922, 0.973, 0.992, 1 },
			}),
		}),
		GetOut = table.freeze({
			seated = "rbxassetid://82829724490644",
			duration = 4,
		}),
		OutsideClose = table.freeze({
			seated = "rbxassetid://112948852391762",
			standing = "rbxassetid://116154715049025",
			duration = 4.6,
			door = table.freeze({
				times = { 1.933, 2.067, 2.133, 2.167, 2.233, 2.4, 2.7, 2.733, 2.8, 2.833 },
				values = { 1, 0.986, 0.97, 0.955, 0.897, 0.697, 0.254, 0.2, 0.039, 0 },
			}),
		}),
	}),
	SEATED_POSE = "rbxassetid://77930295624365",
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
	MARK = table.freeze({ right = -0.88, forward = 0 }),
	-- OutsideClose's bake frame 271, from tools/anim/car_entry_exit_end.py: the torso at standing
	-- height, every part within 0.093 studs of the rest pose, 1.132 studs further out than the
	-- mark (docs/evidence/car-entry-pacing/).
	EXIT_END = table.freeze({ at = 3.433, right = -1.0913, forward = 0.5492 }),
	-- Measured in Play (2026-10-28): Humanoid:MoveTo stops 0.76 to 0.92 studs short of its
	-- target, and its own turn leaves 36 degrees of a half turn after 0.3 s. On the mark at full
	-- size the torso clears the collision box by 0.16 studs facing the car and touches it turned
	-- 10 degrees, so the body turns only clear of the car, or held.
	APPROACH = table.freeze({
		lineUp = 1.5,
		lineUpAngle = math.rad(10),
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
	ARRIVAL_WAIT = 1.5,
	EXIT_MAX_KMH = 3,
	DOOR_MAX_KMH = 5,
	EXIT_HOLD_SECONDS = 0.35,
}

return table.freeze(CarEntry)
