--!strict
--[[
	The Boss 302's driver's door: the clips that get the driver in and out through it, baked against its
	cockpit at the driver's scale of 1.15 (Driver.luau) and uploaded through the guard; each door curve
	is the door keyed on the same timeline as the body.
]]
local CarEntry = require("../../CarEntry")
local SVJDoor = require("../SVJ/Door")

local Door: CarEntry.Door = {
	clips = table.freeze({
		OutsideOpen = table.freeze({
			seated = "rbxassetid://100495967519624",
			standing = "rbxassetid://121728057818984",
			duration = 2.8,
			door = table.freeze({
				times = {
					1.3,
					1.7,
					1.9333,
					2.0667,
					2.1333,
					2.1667,
					2.2,
					2.3,
					2.4,
					2.4667,
					2.5,
					2.5333,
					2.6,
					2.6333,
					2.6667,
				},
				values = {
					0,
					0.0672,
					0.126,
					0.1816,
					0.22,
					0.2552,
					0.3126,
					0.5359,
					0.717,
					0.8305,
					0.8796,
					0.9203,
					0.9734,
					0.9923,
					1,
				},
			}),
		}),
		GetIn = table.freeze({
			seated = "rbxassetid://86582047223223",
			duration = 5.6333,
			door = table.freeze({
				times = {
					3.8333,
					3.8667,
					3.9,
					3.9667,
					4.1,
					4.1667,
					4.2,
					4.2667,
					4.4,
					4.5333,
					4.7,
					4.7667,
					4.8333,
				},
				values = {
					1,
					0.9837,
					0.9439,
					0.85,
					0.7101,
					0.62,
					0.55,
					0.4506,
					0.2943,
					0.1693,
					0.049,
					0.0149,
					0,
				},
			}),
		}),
		InsideClose = table.freeze({
			seated = "rbxassetid://82624443151905",
			duration = 1.6,
			door = table.freeze({
				times = {
					0.2667,
					0.3,
					0.3667,
					0.4667,
					0.5,
					0.5667,
					0.7333,
					0.8333,
					0.9333,
					1.0667,
					1.2,
					1.2667,
					1.3333,
				},
				values = {
					1,
					0.995,
					0.961,
					0.88,
					0.847,
					0.756,
					0.502,
					0.369,
					0.2602,
					0.143,
					0.049,
					0.0149,
					0,
				},
			}),
		}),
		InsideOpen = table.freeze({
			seated = "rbxassetid://127313961771594",
			duration = 2.0667,
			door = table.freeze({
				times = { 0.9, 1, 1.1, 1.2333, 1.3, 1.4, 1.5, 1.6667, 1.7, 1.7667, 1.8, 1.8333, 1.8667 },
				values = {
					0,
					0.0175,
					0.0617,
					0.1446,
					0.2148,
					0.3525,
					0.5021,
					0.8102,
					0.8605,
					0.9343,
					0.9666,
					0.9906,
					1,
				},
			}),
		}),
		GetOut = table.freeze({
			seated = "rbxassetid://94003052352127",
			duration = 5.4333,
		}),
		OutsideClose = table.freeze({
			seated = "rbxassetid://116816201694250",
			standing = "rbxassetid://90011979262062",
			duration = 10.2667,
			door = table.freeze({
				times = { 4.3, 4.3667, 4.4667, 4.5333, 4.6, 4.7667, 5, 5.1667, 5.2333, 5.3 },
				values = { 1, 0.9897, 0.9475, 0.9069, 0.8347, 0.6, 0.29, 0.0989, 0.04, 0 },
			}),
		}),
	}),
	seatedPose = "rbxassetid://118946999490439",
	-- Where the clips start and end standing (DriverSeat frame, metres).
	mark = table.freeze({ right = -1, forward = -0.8 }),
	-- OutsideClose's walk ends here; the clip's last 1.57 s is a hold.
	exitEnd = table.freeze({ at = 8.7, right = -1.2791, forward = -0.8 }),
	-- Stand-in until the Boss has its own door sounds: the SVJ's, as the DR458's are.
	sound = SVJDoor.sound,
}

return table.freeze(Door)
