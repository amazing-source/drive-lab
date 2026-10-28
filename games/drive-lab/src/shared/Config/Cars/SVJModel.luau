--!strict
--[[
	How the SVJ's physics config binds to its model in the place: which parts are wheels, which
	follow a wheel's steering and travel without spinning, and where the driver sits. The
	physics never reads this; the rig does.
]]
export type CarModel = {
	-- Part names, in Vehicle/Geometry's wheel order: front left, front right, rear left, rear right.
	wheels: { string },
	-- Parts that steer and travel with a wheel but do not spin.
	calipers: { { string } },
	-- The steering wheel: its pivot sits on the column with +Z toward the driver.
	steeringWheel: string,
	-- Metres the steering wheel is raised along the car's up at rig time, as a driver sets the
	-- column so the instruments show through the rim.
	steeringWheelLift: number,
	-- The driver's hip point from the centre of mass, car frame (forward, right, up), metres.
	seat: { forward: number, right: number, up: number },
	-- The collision shell starts this high above the ground, so the body meets walls and other
	-- cars but only the suspension meets the road.
	hullClearance: number,
	-- Metres the bodywork is lifted off the wheels at rig time, where a model sits its body
	-- too low over its tyres.
	bodyRaise: number,
	-- The instrument cluster's screen, from the centre of mass in the car frame (metres), its
	-- size, and how far its top leans away from the driver. A live display is mounted there.
	cluster: { forward: number, right: number, up: number, width: number, height: number, tilt: number },
	-- The window glass (windscreen, side and rear windows), which the cockpit view swaps for a
	-- see-through plastic: Roblox draws no particles behind Glass, so rain outside vanished.
	glazing: { string },
	-- The windscreen's corners as the driver sees them (top left, top right, bottom right,
	-- bottom left), from the centre of mass in the car frame, metres: where the cockpit view
	-- draws the water on the glass (Atmosphere/Windshield).
	windshield: { { forward: number, right: number, up: number } },
	-- The driver's door (its part names) and the START flap, each on a hinge: a pivot from the
	-- centre of mass in the car frame (metres, before bodyRaise, like `seat`) and a unit axis in
	-- the car frame. A positive turn about the axis by the right-hand rule in the chassis's space
	-- (x right, y up, z back) opens it; the door by up to openAngle radians. Optional: a model
	-- without them rigs as before.
	door: {
		parts: { string },
		pivot: { forward: number, right: number, up: number },
		axis: { forward: number, right: number, up: number },
		openAngle: number,
	}?,
	flap: {
		part: string,
		pivot: { forward: number, right: number, up: number },
		axis: { forward: number, right: number, up: number },
	}?,
}

local SVJModel: CarModel = table.freeze({
	wheels = table.freeze({ "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR" }),
	calipers = table.freeze({
		table.freeze({ "Caliper_FL" }),
		table.freeze({ "Caliper_FR" }),
		table.freeze({ "Caliper_RL", "Caliper_RL2" }),
		table.freeze({ "Caliper_RR", "Caliper_RR2" }),
	}),
	steeringWheel = "SteeringWheel",
	-- From the cockpit eye the rim's top crossed the top of the cluster (the owner asked for it
	-- up, 2026-10-28): the sight line to the cluster's top edge meets the wheel 0.95 studs above
	-- its centre, inside the rim tube (0.83-0.96); 2 cm clears it.
	steeringWheelLift = 0.02,
	-- EST: left-hand drive, hip about 1.2 m behind the front axle and 0.30 m off the ground;
	-- tuned against the cockpit in Studio.
	seat = table.freeze({ forward = 0.34, right = -0.38, up = -0.15 }),
	hullClearance = 0.32,
	-- tools/blender/wheel_clearance.py on the export: the body cut 7.3 cm into the front tyres and
	-- 7.5 cm into the rear (2026-10-27), which no real car does. Plus 1 cm of air.
	bodyRaise = 0.085,
	-- Measured on the cockpit mesh (part Interior_InteriorA_Material_3, 2026-10-27): a flat
	-- 1.150 x 0.465-stud face at import scale, its normal tilted 6.4 degrees up.
	cluster = table.freeze({
		forward = 0.938,
		right = -0.376,
		up = 0.216,
		width = 0.322,
		height = 0.130,
		tilt = math.rad(6.4),
	}),
	-- Two meshes, the outer and inner faces of every window (the model's own red and orange
	-- light lenses are Glass too and stay so).
	glazing = table.freeze({
		"Window_Window_Material_1",
		"WindowInside_Window_Material_1",
		"DoorGlass",
		"DoorGlassInside",
	}),
	-- Measured on the outer glass mesh (Window_Window_Material_1, read with an EditableMesh,
	-- 2026-10-28): the vertices within 3.5 cm of the screen's plane, its four extremes. The SVJ's
	-- screen is long and raked: 1.28 m from the roof down to the cowl, 1.21 m wide at the top and
	-- 1.66 m at the base.
	windshield = table.freeze({
		table.freeze({ forward = 0.003, right = -0.605, up = 0.492 }),
		table.freeze({ forward = 0.003, right = 0.605, up = 0.492 }),
		table.freeze({ forward = 1.253, right = 0.831, up = 0.228 }),
		table.freeze({ forward = 1.253, right = -0.831, up = 0.228 }),
	}),
	-- Fitted by tools/blender/hero_car_door_hinge.py (2026-10-28; drive-lab-assets/door/HANDOFF.json):
	-- the pivot sits at the front quarter window's tip by the A-pillar's foot, the axis turned
	-- 18 degrees about up and tilted 30 degrees down outboard, so the door clears the fender and
	-- swings out as it rises. Open, it stands 14 degrees outboard with its length 1.5 degrees
	-- rearward of vertical, as photographed (Commons: Tuner tom, front; Axion23, rear three-quarter).
	door = table.freeze({
		parts = table.freeze({
			"DoorPaint",
			"DoorCarbon",
			"DoorTrim",
			"DoorInterior",
			"DoorGlass",
			"DoorGlassInside",
			"DoorBase",
		}),
		pivot = table.freeze({ forward = 1.419, right = -0.9, up = 0.2386 }),
		axis = table.freeze({ forward = 0.26762, right = -0.82364, up = -0.5 }),
		openAngle = math.rad(90.8),
	}),
	-- Hinged on its front edge, across the car; the rear edge, with the finger notch, lifts
	-- (Lamborghini's console photograph shows the notch at the rear).
	flap = table.freeze({
		part = "StartFlap",
		pivot = table.freeze({ forward = 0.6318, right = 0, up = 0.017 }),
		axis = table.freeze({ forward = 0, right = -1, up = 0 }),
	}),
})

return SVJModel
