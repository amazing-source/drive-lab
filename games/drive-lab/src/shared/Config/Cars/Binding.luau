--!strict
--[[
	How a car's physics config binds to its model in the place: which parts are wheels, which
	follow a wheel's steering and travel without spinning, and where the driver sits. The
	physics never reads this; the rig does.
]]

-- A soft loop pull strap sewn to the door card (Rules/DoorStrap). `top` is where it is sewn with
-- the door shut and `facing` the card's unit normal there, into the cabin (car frame from the
-- centre of mass, metres, before bodyRaise). Hanging, it leans `lean` radians off the card and is
-- never longer than `hang` allows at a door angle (radians, ascending): the trim below a soft
-- strap pushes it short. A closing hand holds it from the door angle `grab` down to shut.
export type DoorStrap = {
	part: string,
	top: { forward: number, right: number, up: number },
	facing: { forward: number, right: number, up: number },
	length: number,
	lean: number,
	grab: number,
	hang: { { angle: number, length: number } },
}

-- A part that turns on a hinge: a pivot from the centre of mass in the car frame (metres, before
-- bodyRaise, like `seat`) and a unit axis in the car frame. A positive turn about the axis by the
-- right-hand rule in the chassis's space (x right, y up, z back) opens it.
export type Hinge = {
	part: string,
	pivot: { forward: number, right: number, up: number },
	axis: { forward: number, right: number, up: number },
}

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
	-- The driver's door (its part names) on a hinge (as Hinge), opening by up to openAngle
	-- radians. Optional: a model without one rigs as before.
	door: {
		parts: { string },
		pivot: { forward: number, right: number, up: number },
		axis: { forward: number, right: number, up: number },
		openAngle: number,
		-- The pull strap on the door card (Rules/DoorStrap), its own part on its own weld, so it
		-- is not in `parts`. Optional.
		strap: DoorStrap?,
	}?,
	-- The cabin controls the start-up works (Config/CarEntry ControlMove), by the name its moves
	-- use: a cover, a switch, a key. Controllers/CarDoor turns them. Optional.
	controls: { [string]: Hinge }?,
	-- The pedals that turn; Controllers/DriverLegs turns them. Optional.
	pedals: { Hinge }?,
	-- The cabin light (Controllers/CarLights): where the lamp in the roof console sits, from the
	-- centre of mass in the car frame (metres, before bodyRaise). Optional.
	cabinLight: { forward: number, right: number, up: number }?,
}

return table.freeze({})
