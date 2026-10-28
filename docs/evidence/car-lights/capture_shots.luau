--!nonstrict
-- The capture list for #41: the same views and states before (main's look, Probe.oldShow) and
-- after (the branch's, Probe.newShow). Views in the chassis frame: right, up, forward (studs).
return {
	views = {
		front34 = { eye = Vector3.new(-12, 3, 24), target = Vector3.new(0, 0.6, 9), fov = 45 },
		frontClose = { eye = Vector3.new(-8.5, 2.2, 19), target = Vector3.new(-3.8, 0.5, 11.5), fov = 40 },
		rear34 = { eye = Vector3.new(-12, 3.5, -26), target = Vector3.new(0, 1.2, -9), fov = 45 },
		rearClose = { eye = Vector3.new(-6.5, 3, -18.5), target = Vector3.new(-2.6, 1.6, -9.8), fov = 40 },
		cockpit = { eye = Vector3.new(-1.93, 2.75, 1.76), target = Vector3.new(-1.2, 2.0, 9), fov = 60 },
	},
	-- name, look, view, old lit, new state
	shots = {
		{ "day_front34_indicatorL", "ClearDay", "front34", { headlights = false, brake = false, reverse = false, left = true, right = false }, { indicator = "Left", indicating = 0.1 } },
		{ "day_frontClose_indicatorL", "ClearDay", "frontClose", { headlights = false, brake = false, reverse = false, left = true, right = false }, { indicator = "Left", indicating = 0.1 } },
		{ "day_frontClose_drl", "ClearDay", "frontClose", { headlights = false, brake = false, reverse = false, left = false, right = false }, {} },
		{ "day_rear34_brake_indicatorL", "ClearDay", "rear34", { headlights = false, brake = true, reverse = false, left = true, right = false }, { brake = 1, indicator = "Left", indicating = 0.1 } },
		{ "day_rearClose_brake", "ClearDay", "rearClose", { headlights = false, brake = true, reverse = false, left = false, right = false }, { brake = 1 } },
		{ "night_front34_headlights_indicatorL", "NightRain", "front34", { headlights = true, brake = false, reverse = false, left = true, right = false }, { night = true, indicator = "Left", indicating = 0.1 } },
		{ "night_frontClose_headlights", "NightRain", "frontClose", { headlights = true, brake = false, reverse = false, left = false, right = false }, { night = true } },
		{ "night_rear34_tail_indicatorL", "NightRain", "rear34", { headlights = true, brake = false, reverse = false, left = true, right = false }, { night = true, indicator = "Left", indicating = 0.1 } },
		{ "night_rear34_brake", "NightRain", "rear34", { headlights = true, brake = true, reverse = false, left = false, right = false }, { night = true, brake = 1 } },
		{ "night_rear34_reverse", "NightRain", "rear34", { headlights = true, brake = false, reverse = true, left = false, right = false }, { night = true, gear = -1 } },
		{ "night_cockpit_cabin_off", "NightRain", "cockpit", { headlights = true, brake = false, reverse = false, left = false, right = false }, { night = true } },
		{ "night_cockpit_cabin_on", "NightRain", "cockpit", nil, { night = true, cabin = true } },
	},
}
