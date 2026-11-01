--!strict
--[[
	The Boss 302's driver's door. Until its own entry and exit clips are baked and uploaded, the
	prompt seats the driver straight in and stands them out at `exitEnd` (`direct`), and the DR458's
	clips and seated pose stand in for opening and shutting the door from the seat. Its own mark is
	the one its clips are being authored from.
]]
local CarEntry = require("../../CarEntry")
local DR458Door = require("../DR458/Door")
local SVJDoor = require("../SVJ/Door")

local Door: CarEntry.Door = {
	direct = true,
	clips = DR458Door.clips,
	seatedPose = DR458Door.seatedPose,
	-- Where the Boss's clips start and end standing (DriverSeat frame, metres).
	mark = table.freeze({ right = -1, forward = -0.8 }),
	-- Getting out stands the driver 1.5 studs further out than the mark, as on the DR458.
	exitEnd = table.freeze({ at = DR458Door.exitEnd.at, right = -1.28, forward = -0.8 }),
	-- Stand-in until the Boss has its own door sounds: the SVJ's, as the DR458's are.
	sound = SVJDoor.sound,
}

return table.freeze(Door)
