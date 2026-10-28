--!strict
local Units = require("../Units")

export type World = {
	GRAVITY_MPS2: number,
	GRAVITY: number,
}

-- Real gravity, so spring rates, tyre data and masses enter the model unscaled. Roblox's default
-- of 196.2 studs/s^2 is about 5.6 g at 0.28 m per stud.
local GRAVITY_MPS2 = 9.81

local World: World = table.freeze({
	GRAVITY_MPS2 = GRAVITY_MPS2,
	GRAVITY = Units.metresToStuds(GRAVITY_MPS2),
})

return World
