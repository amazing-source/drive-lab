--!strict
--[[
	Drag and downforce from CdA and ClA (01 §2.5), with the downforce split front and rear, and
	ALA 2.0 as the one moving part (02 §2.10): on a straight at full throttle the flaps open,
	stalling the wing to cut drag and rear downforce; braking or cornering closes them. The
	flaps follow their target with a first-order actuator lag.

	Downforce acts on the chassis, not on the tyres: the suspension carries it to the ground,
	as it does on the real car.
]]
local Types = require("../Config/Cars/Types")

export type AeroState = {
	-- 0 = flaps closed (high downforce), 1 = open (low drag).
	alaOpen: number,
}

export type AeroForces = {
	drag: number,
	downforceFront: number,
	downforceRear: number,
}

local Aero = {}

function Aero.newState(): AeroState
	return { alaOpen = 0 }
end

function Aero.alaTarget(
	config: Types.AeroConfig,
	speed: number,
	throttle: number,
	brake: number,
	lateral: number
): number
	local straight = math.abs(lateral) < config.alaMaxLateral
	return if speed > config.alaMinSpeed
			and throttle >= config.alaMinThrottle
			and brake <= 0
			and straight
		then 1
		else 0
end

-- Moves the flaps toward their target over `dt` (exact for the first-order lag, so the same at
-- any frame rate) and returns the forces at `speed` (m/s through the air).
function Aero.update(
	config: Types.AeroConfig,
	state: AeroState,
	speed: number,
	target: number,
	dt: number,
	forces: AeroForces
)
	state.alaOpen = target + (state.alaOpen - target) * math.exp(-dt / config.alaTime)
	local open = state.alaOpen
	local pressure = 0.5 * config.airDensity * speed * speed
	local dragArea = config.dragArea * (1 - open * (1 - config.alaDragFactor))
	local rearShare = (1 - config.frontBalance) * (1 - open * (1 - config.alaRearLiftFactor))
	forces.drag = pressure * dragArea
	forces.downforceFront = pressure * config.liftArea * config.frontBalance
	forces.downforceRear = pressure * config.liftArea * rearShare
end

return table.freeze(Aero)
