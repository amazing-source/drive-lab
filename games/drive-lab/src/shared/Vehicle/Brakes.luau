--!strict
--[[
	Brake torque per wheel (01 §2.4, AC's MAX_TORQUE / FRONT_SHARE / HANDBRAKE_TORQUE). The
	torque is a capacity, not a force: the driveline applies it as friction toward a stopped
	wheel, so a brake can lock a wheel but never spin it backwards.
]]
local Geometry = require("./Geometry")
local Types = require("../Config/Cars/Types")

export type Brakes = {
	frontTorque: number,
	rearTorque: number,
	handbrakeTorque: number,
}

local Brakes = {}

function Brakes.prepare(config: Types.BrakesConfig): Brakes
	return table.freeze({
		frontTorque = config.maxTorque * config.frontShare / 2,
		rearTorque = config.maxTorque * (1 - config.frontShare) / 2,
		handbrakeTorque = config.handbrakeTorque,
	})
end

-- Hydraulic torque on `wheel`: the pedal's share of that axle's maximum plus the stability
-- control's request, both scaled by the ABS pressure factor. The handbrake is mechanical on the
-- rear wheels, so ABS does not modulate it.
function Brakes.torque(
	brakes: Brakes,
	wheel: number,
	pedal: number,
	handbrake: number,
	absFactor: number,
	stabilityTorque: number
): number
	local front = Geometry.isFront(wheel)
	local hydraulic = (pedal * (if front then brakes.frontTorque else brakes.rearTorque) + stabilityTorque)
		* absFactor
	return if front then hydraulic else hydraulic + handbrake * brakes.handbrakeTorque
end

return table.freeze(Brakes)
