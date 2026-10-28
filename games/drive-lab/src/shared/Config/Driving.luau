--!strict
local Units = require("../Units")

export type Driving = {
	-- A model tagged with this and carrying a "Car" attribute is rigged when the server starts.
	SPAWN_TAG: string,
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
}

local Driving: Driving = table.freeze({
	SPAWN_TAG = "DriveLabCarSpawn",
	ENTER_DISTANCE = 12,
	MAX_SPEED = Units.metresToStuds(Units.kmhToMps(420)),
	RECLAIM_SECONDS = 0.5,
	DRIVER_SCALE = 1.5 / 1.75,
})

return Driving
