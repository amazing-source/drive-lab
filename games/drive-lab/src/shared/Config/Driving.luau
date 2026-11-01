--!strict
local Units = require("../Units")

export type Driving = {
	-- A model tagged with this and carrying a "Car" attribute is rigged when the server starts.
	SPAWN_TAG: string,
	-- The road starts at this car's spawn (its "Car" attribute, a Catalog name), whatever other cars
	-- the place holds (Rules/TrackPath.startIndex).
	ROAD_START_CAR: string,
	-- How close a player must be to the driver's door to get in, studs.
	ENTER_DISTANCE: number,
	-- Above this a driven car is out of its envelope: the SVJ tops out near 355 km/h.
	MAX_SPEED: number,
	-- How long the server holds a car after an envelope breach before the driver gets it back.
	RECLAIM_SECONDS: number,
	-- A seated driver is scaled to this. The owner judged a 1.75x car the right fit for a full-
	-- size R6 avatar but too big next to one on foot (2026-10-27): the world stays 1.5x and the
	-- driver shrinks to 1.5 / 1.75 while seated, which gives the same room inside.
	DRIVER_SCALE: number,
	-- A stall the driving client reported (Rules/Stall) that the server has not turned into an
	-- engine stop within STALL_RESEND_SECONDS is reported once more; still running on the server's
	-- record at STALL_RESUME_SECONDS, the client's engine runs again, as the server says it does.
	STALL_RESEND_SECONDS: number,
	STALL_RESUME_SECONDS: number,
}

local Driving: Driving = table.freeze({
	SPAWN_TAG = "DriveLabCarSpawn",
	ROAD_START_CAR = "SVJ",
	ENTER_DISTANCE = 12,
	MAX_SPEED = Units.metresToStuds(Units.kmhToMps(420)),
	RECLAIM_SECONDS = 0.5,
	DRIVER_SCALE = 1.5 / 1.75,
	-- EST: several round trips on a slow connection, and short enough that a car is never left
	-- dead for long.
	STALL_RESEND_SECONDS = 0.5,
	STALL_RESUME_SECONDS = 1.5,
})

return Driving
