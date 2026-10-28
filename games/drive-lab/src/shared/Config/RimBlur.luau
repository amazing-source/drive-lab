--!strict
--[[
	The rim blur's tuning and where its pieces are. tools/blender/rim_blur.py splits each of the
	car's wheels into its rim face and the rest (tyre, barrel, brake disc) and builds a disc over
	the face; tools/assets/rim_blur_maps.py renders the face blurred over every rotation into the
	disc's maps. The pieces sit in the place at ReplicatedStorage.DriveLabAssets.RimBlur.<Car>.
	<wheel part name>, each a MeshPart with an Offset attribute (its CFrame from the wheel's centre
	at import scale); each wheel folder carries the wheel's import size as WheelSize.
]]
local RimBlur = require("../Rules/RimBlur")

export type RimBlurConfig = {
	SPIN: RimBlur.Tuning,
	ASSETS_FOLDER: string,
	PIECES: { tyre: string, face: string, disc: string },
	OFFSET_ATTRIBUTE: string,
	WHEEL_SIZE_ATTRIBUTE: string,
	-- How many times the SVJ's rim repeats round, measured on its front-on render, and the frame
	-- rate whose wagon-wheel effect the blur must hide.
	RIM_REPEATS: number,
	FRAME_RATE: number,
	-- Smallest transparency change written, so a steady speed writes nothing.
	STEP: number,
	-- Seconds between tries at a car whose rig or pieces have not streamed in yet.
	RETRY_SECONDS: number,
}

local Config: RimBlurConfig = {
	-- About 17 to 41 km/h on the front tyres (0.322 m), 19 to 44 on the rear (0.346 m). Ends
	-- under 40 rad/s: ten spokes look still at 37.7 rad/s at 60 FPS.
	SPIN = { from = 15, to = 35 },
	ASSETS_FOLDER = "RimBlur",
	PIECES = { tyre = "Tyre", face = "Face", disc = "Disc" },
	OFFSET_ATTRIBUTE = "Offset",
	WHEEL_SIZE_ATTRIBUTE = "WheelSize",
	-- rim_blur.py, 2026-10-28: the coverage round the front and rear rims' mid radius has its
	-- strongest harmonic at 10, and none at 5.
	RIM_REPEATS = 10,
	FRAME_RATE = 60,
	STEP = 0.02,
	RETRY_SECONDS = 1,
}

return table.freeze(Config)
