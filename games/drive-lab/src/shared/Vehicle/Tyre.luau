--!strict
--[[
	The tyre (01 §1 and §2.1). Pure slip is a simplified Magic Formula per direction, placed by
	designer knobs (peak friction, slip at peak, sliding share) rather than raw B, C, D, E.
	Friction falls as load rises (a power law around a reference load). Combined slip follows
	Beckman: both slips are normalised by their peak, run through the curves at the combined
	magnitude and split back by direction, which keeps each pure-slip curve exact and the
	result inside the friction ellipse.

	Slip is not instantaneous. Each direction carries a contact-patch deflection that relaxes
	over a relaxation length, updated with its exact exponential, so the slips stay defined at
	a standstill: there the deflection is a carcass spring, damped at walking pace, and a
	parked car neither creeps nor jitters (01 §2.1 low speed, §5.3 points 3 and 5). The wheel's
	spin couples to the longitudinal force through `stiffness`, which the driveline treats
	implicitly.
]]
local Types = require("../Config/Cars/Types")

export type Curve = { b: number, c: number, e: number, peakSlip: number }

export type Tyre = {
	radius: number,
	x: Curve,
	y: Curve,
	muX: number,
	muY: number,
	referenceLoad: number,
	loadExponent: number,
	relaxationX: number,
	relaxationY: number,
	peakTanY: number,
	dampingX: number,
	dampingY: number,
	rollingResistance: number,
	rollingResistancePerSpeed: number,
}

-- Per-wheel state. The deflections persist between substeps; the rest is what `prepare`
-- hands to the driveline solve and to the step's result.
export type TyreState = {
	deflectionX: number,
	deflectionY: number,
	-- Peak force each way at this frame's load and grip (0 when airborne).
	peakX: number,
	peakY: number,
	-- Longitudinal force at the deflection the current spin would give, its slope against the
	-- end-of-substep spin (N per rad/s), and the most the patch can carry along x.
	forceX: number,
	stiffness: number,
	limitX: number,
	forceY: number,
	slipRatio: number,
	slipAngle: number,
	combinedSlip: number,
}

local Tyre = {}

-- The Magic Formula shape with D = 1: force over peak force at `slip`.
function Tyre.shape(curve: Curve, slip: number): number
	local bs = curve.b * slip
	local phi = bs - curve.e * (bs - math.atan(bs))
	return math.sin(curve.c * math.atan(phi))
end

function Tyre.shapeSlope(curve: Curve, slip: number): number
	local b, e = curve.b, curve.e
	local bs = b * slip
	local phi = bs - e * (bs - math.atan(bs))
	local dPhi = b * (1 - e) + e * b / (1 + bs * bs)
	return math.cos(curve.c * math.atan(phi)) * curve.c / (1 + phi * phi) * dPhi
end

-- C from the sliding share (the curve tends to sin(C·π/2) of its peak), then B so that the
-- peak, where C·atan(φ) = π/2, falls at `peakSlip`. (1 − E)·z + E·atan(z) rises
-- monotonically in z = B·peakSlip for E < 1, so Newton converges from z = tan(π/2C).
local function solveCurve(peakSlip: number, slidingRatio: number, curvature: number): Curve
	local c = 2 - 2 * math.asin(slidingRatio) / math.pi
	local target = math.tan(math.pi / (2 * c))
	local z = target
	for _ = 1, 40 do
		local residual = (1 - curvature) * z + curvature * math.atan(z) - target
		z -= residual / ((1 - curvature) + curvature / (1 + z * z))
	end
	return table.freeze({ b = z / peakSlip, c = c, e = curvature, peakSlip = peakSlip })
end

-- `cornerMass` sizes the walking-pace damping: a share of critical for the carcass spring
-- (slip stiffness over relaxation length) carrying that corner.
function Tyre.prepare(config: Types.TyreConfig, cornerMass: number): Tyre
	local x = solveCurve(config.slipRatioAtPeak, config.slidingRatioX, config.curvatureX)
	local y = solveCurve(config.slipAngleAtPeak, config.slidingRatioY, config.curvatureY)
	local springX = config.peakMuX * config.referenceLoad * x.b * x.c / config.relaxationLengthX
	local springY = config.peakMuY * config.referenceLoad * y.b * y.c / config.relaxationLengthY
	return table.freeze({
		radius = config.radius,
		x = x,
		y = y,
		muX = config.peakMuX,
		muY = config.peakMuY,
		referenceLoad = config.referenceLoad,
		loadExponent = config.loadSensitivity - 1,
		relaxationX = config.relaxationLengthX,
		relaxationY = config.relaxationLengthY,
		peakTanY = math.tan(config.slipAngleAtPeak),
		dampingX = 2 * config.carcassDampingRatio * math.sqrt(springX * cornerMass),
		dampingY = 2 * config.carcassDampingRatio * math.sqrt(springY * cornerMass),
		rollingResistance = config.rollingResistance,
		rollingResistancePerSpeed = config.rollingResistancePerSpeed,
	})
end

function Tyre.newState(): TyreState
	return {
		deflectionX = 0,
		deflectionY = 0,
		peakX = 0,
		peakY = 0,
		forceX = 0,
		stiffness = 0,
		limitX = 0,
		forceY = 0,
		slipRatio = 0,
		slipAngle = 0,
		combinedSlip = 0,
	}
end

-- Friction multiplier from load sensitivity. The load is floored at a tenth of the reference
-- so friction stays finite as a wheel unloads.
function Tyre.frictionScale(tyre: Tyre, load: number): number
	return (math.max(load, 0.1 * tyre.referenceLoad) / tyre.referenceLoad) ^ tyre.loadExponent
end

-- Combined slip for peak forces `peakX` and `peakY` (N): forces in the wheel frame (x forward,
-- y right) and ∂Fx/∂κ, never negative, so the implicit solve sees a damper and past the peak
-- the force is left explicit. A positive slip angle means the patch slides right, so the
-- force points left.
local function combinedForces(
	tyre: Tyre,
	slipRatio: number,
	slipAngle: number,
	peakX: number,
	peakY: number
): (number, number, number)
	local slipAtPeakX, slipAtPeakY = tyre.x.peakSlip, tyre.y.peakSlip
	local sx, sy = slipRatio / slipAtPeakX, slipAngle / slipAtPeakY
	local rho = math.sqrt(sx * sx + sy * sy)
	if rho < 1e-9 then
		return 0, 0, peakX * Tyre.shapeSlope(tyre.x, 0)
	end
	local ux, uy = sx / rho, sy / rho
	local gx = peakX * Tyre.shape(tyre.x, rho * slipAtPeakX)
	local gy = peakY * Tyre.shape(tyre.y, rho * slipAtPeakY)
	local slopeX = math.max(0, peakX * Tyre.shapeSlope(tyre.x, rho * slipAtPeakX))
	local dFx = gx / rho * uy * uy / slipAtPeakX + slopeX * ux * ux
	return ux * gx, -uy * gy, dFx
end

-- Peak force along x and y (N) at `load` on a surface of friction multiplier `grip`.
function Tyre.peakForces(tyre: Tyre, load: number, grip: number): (number, number)
	if load <= 0 then
		return 0, 0
	end
	local scale = grip * Tyre.frictionScale(tyre, load) * load
	return tyre.muX * scale, tyre.muY * scale
end

function Tyre.combined(
	tyre: Tyre,
	slipRatio: number,
	slipAngle: number,
	load: number,
	grip: number
): (number, number, number)
	if load <= 0 then
		return 0, 0, 0
	end
	local peakX, peakY = Tyre.peakForces(tyre, load, grip)
	return combinedForces(tyre, slipRatio, slipAngle, peakX, peakY)
end

-- Sets the frame's load and grip. Load changes once per frame, so the load-sensitivity power
-- law is evaluated here rather than every substep.
function Tyre.setLoad(tyre: Tyre, state: TyreState, load: number, grip: number)
	state.peakX, state.peakY = Tyre.peakForces(tyre, load, grip)
end

-- Exact update of d(deflection)/dt = slipVelocity − (speed/length)·deflection over `dt` with
-- both inputs held. Returns the new deflection and its gain on the slip velocity.
function Tyre.relax(
	deflection: number,
	slipVelocity: number,
	speed: number,
	length: number,
	dt: number
): (number, number)
	local rate = speed / length
	if rate * dt < 1e-6 then
		return deflection + slipVelocity * dt, dt
	end
	local decay = math.exp(-rate * dt)
	local gain = (1 - decay) / rate
	return deflection * decay + slipVelocity * gain, gain
end

-- A sliding patch cannot store more deflection than the peak, or than the slip it is being
-- dragged at (relative to a floored speed). Above the floor speed the steady deflection is
-- always inside this, so it only bites near a standstill.
local function slideLimit(
	slipVelocity: number,
	speed: number,
	length: number,
	peak: number,
	floor: number
): number
	return length * math.max(peak, math.abs(slipVelocity) / math.max(speed, floor))
end

-- Sets up one substep. `forwardSpeed` and `rightSpeed` are the patch velocity in the wheel
-- frame, `spin` the wheel's current speed. The lateral deflection is committed here; the
-- longitudinal one waits for the solved spin in `finish`.
function Tyre.prepareSubstep(
	tyre: Tyre,
	state: TyreState,
	forwardSpeed: number,
	rightSpeed: number,
	spin: number,
	simulation: Types.SimulationConfig,
	dt: number
)
	local peakX, peakY = state.peakX, state.peakY
	if peakX <= 0 then
		state.deflectionX, state.deflectionY = 0, 0
		state.forceX, state.forceY, state.stiffness, state.limitX = 0, 0, 0, 0
		state.slipRatio, state.slipAngle, state.combinedSlip = 0, 0, 0
		return
	end
	local speed = math.abs(forwardSpeed)
	local floor = simulation.slipSpeedFloor
	local slipX = spin * tyre.radius - forwardSpeed
	local deflectionX, gainX = Tyre.relax(state.deflectionX, slipX, speed, tyre.relaxationX, dt)
	local limitDeflectionX = slideLimit(slipX, speed, tyre.relaxationX, tyre.x.peakSlip, floor)
	deflectionX = math.clamp(deflectionX, -limitDeflectionX, limitDeflectionX)
	local deflectionY = Tyre.relax(state.deflectionY, rightSpeed, speed, tyre.relaxationY, dt)
	local limitDeflectionY = slideLimit(rightSpeed, speed, tyre.relaxationY, tyre.peakTanY, floor)
	deflectionY = math.clamp(deflectionY, -limitDeflectionY, limitDeflectionY)
	state.deflectionY = deflectionY

	local slipRatio = deflectionX / tyre.relaxationX
	local slipAngle = math.atan(deflectionY / tyre.relaxationY)
	local forceX, forceY, slopeX = combinedForces(tyre, slipRatio, slipAngle, peakX, peakY)

	local fade = math.max(0, 1 - speed / simulation.lowSpeedFade)
	local dampingX = tyre.dampingX * fade
	forceX += dampingX * slipX
	forceY -= tyre.dampingY * fade * rightSpeed

	forceY = math.clamp(forceY, -peakY, peakY)
	local usedY = forceY / peakY
	local limitX = peakX * math.sqrt(math.max(0, 1 - usedY * usedY))

	state.forceX = math.clamp(forceX, -limitX, limitX)
	state.forceY = forceY
	state.limitX = limitX
	state.stiffness = (slopeX / tyre.relaxationX * gainX + dampingX) * tyre.radius
	state.slipRatio = slipRatio
	state.slipAngle = slipAngle
	local sx, sy = slipRatio / tyre.x.peakSlip, slipAngle / tyre.y.peakSlip
	state.combinedSlip = math.sqrt(sx * sx + sy * sy)
end

-- Commits the longitudinal deflection once the driveline has solved the wheel's spin.
function Tyre.finishSubstep(
	tyre: Tyre,
	state: TyreState,
	forwardSpeed: number,
	spin: number,
	simulation: Types.SimulationConfig,
	dt: number
)
	if state.peakX <= 0 then
		return
	end
	local speed = math.abs(forwardSpeed)
	local slipX = spin * tyre.radius - forwardSpeed
	local deflection = Tyre.relax(state.deflectionX, slipX, speed, tyre.relaxationX, dt)
	local limit = slideLimit(slipX, speed, tyre.relaxationX, tyre.x.peakSlip, simulation.slipSpeedFloor)
	state.deflectionX = math.clamp(deflection, -limit, limit)
end

-- Rolling resistance as a torque resisting the wheel's spin: the patch's pressure centre sits
-- ahead of the axle, so the drag reaches the car through the tyre's own slip.
function Tyre.rollingResistanceTorque(tyre: Tyre, load: number, speed: number): number
	return math.max(load, 0)
		* (tyre.rollingResistance + tyre.rollingResistancePerSpeed * math.abs(speed))
		* tyre.radius
end

return table.freeze(Tyre)
