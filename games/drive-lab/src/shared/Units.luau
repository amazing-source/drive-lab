--!strict
--[[
	The one conversion between the vehicle model, which works in SI units, and the engine,
	which works in studs and Roblox mass units. Roblox documents 1 stud = 0.28 m and
	1 mass unit = 21.952 kg (create.roblox.com/docs/physics/units); force and torque units follow
	from those two.

	Drive Lab's world is WORLD_SCALE times Roblox's: a real-scale car is too narrow for an R6
	avatar (4 studs wide with its arms) to sit in (owner, 2026-10-27). Cars are scaled up by it
	and a stud is shorter by it, so the physics still sees the real car, real gravity included,
	and only its size next to the avatar changes. The mass unit keeps Roblox's value: only the
	ratio of force to mass times acceleration matters to the engine.
]]
local Units = {}

Units.WORLD_SCALE = 1.5
Units.METRES_PER_STUD = 0.28 / Units.WORLD_SCALE
Units.KG_PER_MASS_UNIT = 21.952
Units.NEWTONS_PER_FORCE_UNIT = Units.KG_PER_MASS_UNIT * Units.METRES_PER_STUD
Units.NEWTON_METRES_PER_TORQUE_UNIT = Units.NEWTONS_PER_FORCE_UNIT * Units.METRES_PER_STUD

function Units.studsToMetres(studs: number): number
	return studs * Units.METRES_PER_STUD
end

function Units.metresToStuds(metres: number): number
	return metres / Units.METRES_PER_STUD
end

function Units.kgToMass(kg: number): number
	return kg / Units.KG_PER_MASS_UNIT
end

function Units.massToKg(mass: number): number
	return mass * Units.KG_PER_MASS_UNIT
end

function Units.newtonsToForce(newtons: number): number
	return newtons / Units.NEWTONS_PER_FORCE_UNIT
end

function Units.forceToNewtons(force: number): number
	return force * Units.NEWTONS_PER_FORCE_UNIT
end

function Units.newtonMetresToTorque(newtonMetres: number): number
	return newtonMetres / Units.NEWTON_METRES_PER_TORQUE_UNIT
end

function Units.torqueToNewtonMetres(torque: number): number
	return torque * Units.NEWTON_METRES_PER_TORQUE_UNIT
end

function Units.kmhToMps(kmh: number): number
	return kmh / 3.6
end

function Units.mpsToKmh(mps: number): number
	return mps * 3.6
end

return Units
