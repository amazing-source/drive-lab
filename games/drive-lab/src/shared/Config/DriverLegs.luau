--!strict
--[[
	The driver's legs, drawn in place of the avatar's blocky ones while seated, and the SVJ's
	footwell they work in. Unlike the arms the legs are real length, in metres: the feet sit on
	the car's real pedals, which are 0.85 m ahead of the hips, three times an R6 leg. Points are
	in the driver's seat frame (the DriverSeat part: x right, y up, z back), measured on the car's
	interior mesh (tools/blender/footwell.py prints them). The trousers and shoes are meshes
	kept in the place at ReplicatedStorage.DriveLabAssets.Legs.
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

export type DriverLegs = {
	THIGH: number,
	SHIN: number,
	-- The hip joint in the R6 torso's own space, studs at character scale 1 (with PELVIS_CENTRE,
	-- the points not in metres).
	HIP: Point,
	-- The point each knee bends toward, in the seat frame: the knee stays in the plane through the
	-- hip, the ankle and this point.
	KNEE_TOWARD: { right: Point, left: Point },
	-- The trousers' seat, a cloth block under the torso that the thighs grow out of, filling the
	-- room between the R6's torso and the cushion: its centre in the torso's space (studs at
	-- character scale 1). Its mesh is modelled for Driving.DRIVER_SCALE.
	PELVIS_CENTRE: Point,
	-- The shoe: the ankle joint from where the sole meets the floor under the heel, along the
	-- sole toward the toes and up off it.
	ANKLE_ALONG: number,
	ANKLE_UP: number,
	THROTTLE: Pedal,
	BRAKE: Pedal,
	-- The left foot's rest on the footrest, which does not move.
	FOOTREST: { heel: Point, ball: Point },
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
	-- upright sit holds the torso's bottom 13 to 22 cm above the bucket's cushion (measured in
	-- Studio). Hips low enough to lay the thighs on the cushion put them out of the R6 arms'
	-- reach; the pelvis below fills the room down to the cushion instead.
	HIP = table.freeze({ x = 0.5, y = -1.05, z = 0.05 }),
	-- The right knee rides the gap between the steering column and the centre console, below the
	-- dash; the left leans out toward the door, where there is room. Fitted against the cabin
	-- (tools/blender/leg_clearance.py): the right leg touches the console and the column (at most
	-- 0.6 cm into them on a pedal, 1.0 cm at worst crossing between them; 0.5 cm clear under full
	-- braking), as a real driver's knee rests on the tunnel; bent straight out instead, the knee
	-- sat 5 cm inside the console. The left clears everything by 5 cm.
	KNEE_TOWARD = table.freeze({
		right = table.freeze({ x = 0.17, y = 0.15, z = -0.4 }),
		left = table.freeze({ x = -0.58, y = 0.62, z = 0.008 }),
	}),
	PELVIS_CENTRE = table.freeze({ x = 0, y = -1.564, z = -0.281 }),
	ANKLE_ALONG = 0.075,
	ANKLE_UP = 0.085,
	-- Measured on the SVJ's interior mesh (tools/blender/footwell.py): an organ throttle hinged on
	-- the floor, the foot lying on its plate with the heel at the hinge; a brake hanging from
	-- under the dash, the heel on the floor behind it; a fixed footrest. 16 and 12 degrees of
	-- travel: 7 and 4.5 cm at the ball of the foot.
	THROTTLE = table.freeze({
		part = "Pedal_Throttle",
		hinge = table.freeze({ x = 0.1761, y = -0.2364, z = -0.8354 }),
		travel = -math.rad(16),
		heel = table.freeze({ x = 0.1761, y = -0.2275, z = -0.8354 }),
		ball = table.freeze({ x = 0.2044, y = -0.0482, z = -0.924 }),
	}),
	BRAKE = table.freeze({
		part = "Pedal_Brake",
		hinge = table.freeze({ x = 0.0304, y = 0.0956, z = -0.9992 }),
		travel = math.rad(12),
		heel = table.freeze({ x = 0.0308, y = -0.2334, z = -0.794 }),
		ball = table.freeze({ x = 0.0308, y = -0.0486, z = -0.8705 }),
	}),
	FOOTREST = table.freeze({
		heel = table.freeze({ x = -0.1012, y = -0.2352, z = -0.8776 }),
		ball = table.freeze({ x = -0.1012, y = -0.0519, z = -0.9575 }),
	}),
	SWITCH_SECONDS = 0.18,
	SWITCH_LIFT = 0.035,
	BRAKE_THRESHOLD = 0.02,
	KNEE_SIZE = 0.12,
	HEM_OVERHANG = 0.03,
	SHOE_CENTRE = table.freeze({ x = 0, y = 0.028, z = -0.0675 }),
	TROUSER_RGB = table.freeze({ 34, 35, 40 }),
})

return DriverLegs
