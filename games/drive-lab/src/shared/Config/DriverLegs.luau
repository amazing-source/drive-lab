--!strict
--[[
	The driver's legs, drawn in place of the avatar's blocky ones while seated, and the shape of
	a car's footwell they work in (its entry's driver.footwell). Unlike the arms the legs are real
	length, in metres: the feet sit on the car's real pedals, which are 0.85 m ahead of the hips in
	the SVJ, three times an R6 leg. Points are in the driver's seat frame (the DriverSeat part:
	x right, y up, z back), measured on the car's interior mesh (tools/blender/footwell.py prints
	them). The trousers and shoes are meshes kept in the place at
	ReplicatedStorage.DriveLabAssets.Legs.
]]
export type Point = { x: number, y: number, z: number }

-- A pedal turns about the seat's x axis through `hinge`, by `travel` radians at a full press (the
-- sign that moves its face toward the nose). `heel` and `ball` are where the sole meets the pedal,
-- or the floor, at rest.
export type Pedal = {
	part: string,
	hinge: Point,
	travel: number,
	heel: Point,
	ball: Point,
}

-- One car's footwell: the pedals the right foot works, the footrest the left foot rests on, the
-- clutch it moves onto in a car that has one, and the point each knee bends toward: the knee stays
-- in the plane through the hip, the ankle and this point.
export type Footwell = {
	throttle: Pedal,
	brake: Pedal,
	clutch: Pedal?,
	footrest: { heel: Point, ball: Point },
	kneeToward: { right: Point, left: Point },
}

export type DriverLegs = {
	THIGH: number,
	SHIN: number,
	-- The hip joint in the R6 torso's own space, studs at character scale 1 (with PELVIS_CENTRE,
	-- the points not in metres).
	HIP: Point,
	-- The trousers' seat: cloth from inside the torso's bottom and the thighs down into the bucket,
	-- shaped to the car's cushion (tools/blender/seat_fill.py): its box centre in the torso's
	-- space (studs at character scale 1). Its mesh is modelled for Driving.DRIVER_SCALE.
	PELVIS_CENTRE: Point,
	-- The shoe: the ankle joint from where the sole meets the floor under the heel, along the
	-- sole toward the toes and up off it.
	ANKLE_ALONG: number,
	ANKLE_UP: number,
	-- Seconds the right foot takes between the pedals, and how far the ball of the foot lifts on
	-- the way, the heel staying on the floor.
	SWITCH_SECONDS: number,
	SWITCH_LIFT: number,
	-- A brake readout above this moves the right foot onto the brake.
	BRAKE_THRESHOLD: number,
	-- The cloth ball filling the knee, metres across.
	KNEE_SIZE: number,
	-- How far the shin's sleeve runs past the ankle joint, so its hem covers the shoe's collar.
	HEM_OVERHANG: number,
	-- The right shoe mesh's centre (where Roblox puts the imported MeshPart) in the shoe's frame:
	-- origin at the ankle, x to the car's right, y up out of the instep, z from the toes to the
	-- heel; the left shoe mirrors x.
	SHOE_CENTRE: Point,
	-- 0 to 255, red, green, blue (no Color3 here, so Lune can load the file).
	TROUSER_RGB: { number },
}

local DriverLegs: DriverLegs = table.freeze({
	-- Long enough that the right foot floors the throttle with the knee still bent (at 96 % of the
	-- leg's reach from the R6's hips).
	THIGH = 0.46,
	SHIN = 0.45,
	-- At the torso's bottom edge, where the resting hands can still reach the thighs: Roblox's
	-- upright sit holds the torso's bottom about 37 cm above the SVJ's cushion at the hips, and
	-- the thighs 15 to 19 cm above its front edge (measured on the cabin mesh). Hips low enough to
	-- lay the thighs on the cushion put them out of the R6 arms' reach; the trousers' seat fills
	-- the room down to the cushion instead.
	HIP = table.freeze({ x = 0.5, y = -1.05, z = 0.05 }),
	PELVIS_CENTRE = table.freeze({ x = 0, y = -2.1129, z = -0.75 }),
	ANKLE_ALONG = 0.075,
	ANKLE_UP = 0.085,
	SWITCH_SECONDS = 0.18,
	SWITCH_LIFT = 0.035,
	BRAKE_THRESHOLD = 0.02,
	KNEE_SIZE = 0.12,
	HEM_OVERHANG = 0.03,
	SHOE_CENTRE = table.freeze({ x = 0, y = 0.028, z = -0.0675 }),
	TROUSER_RGB = table.freeze({ 34, 35, 40 }),
})

return DriverLegs
