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

-- One car's rims (its entry's rimBlur): the wheel spin over which the sharp face fades into
-- the blurred disc, and how many times the rim repeats round, measured on its front-on render.
export type Rims = { spin: RimBlur.Tuning, repeats: number }

export type RimBlurConfig = {
	ASSETS_FOLDER: string,
	PIECES: { tyre: string, face: string, disc: string },
	OFFSET_ATTRIBUTE: string,
	WHEEL_SIZE_ATTRIBUTE: string,
	-- The frame rate whose wagon-wheel effect the blur must hide.
	FRAME_RATE: number,
	-- Smallest transparency change written, so a steady speed writes nothing.
	STEP: number,
	-- Seconds between tries at a car whose rig or pieces have not streamed in yet.
	RETRY_SECONDS: number,
}

local Config: RimBlurConfig = {
	ASSETS_FOLDER = "RimBlur",
	PIECES = { tyre = "Tyre", face = "Face", disc = "Disc" },
	OFFSET_ATTRIBUTE = "Offset",
	WHEEL_SIZE_ATTRIBUTE = "WheelSize",
	FRAME_RATE = 60,
	STEP = 0.02,
	RETRY_SECONDS = 1,
}

return table.freeze(Config)
