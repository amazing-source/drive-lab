--!strict
--[[
	The SVJ's slide assist (Vehicle/SlideAssist, docs/research/14_game_handling.md): game help, not
	car data, so nothing here is OEM. The same values as the DR458's until the owner's play says
	otherwise.
]]
local Types = require("../Types")

local Handling: Types.SlideAssistProfile = {
	rearSlipBand = 0.5,
	yawErrorBand = 0.3,
	-- About a tenth of a second of yaw: enough to stop a catch whipping the car the other way, small
	-- beside the path angle it steers to.
	yawDamping = 0.1,
	-- A quick human hand on a wheel; the keyboard filter's turn-in at 100 km/h is about 2.7 s.
	steerTime = 0.35,
	steerEaseShare = 0.15,
	holdTime = 0.4,
	minSpeed = 5,
	notches = {
		-- Gran Turismo's "Weak": the tail may step out until the rear is twice past its peak.
		Balanced = { rearSlipStart = 2, yawErrorStart = 0.6 },
		-- Its "Strong": the assist takes over as soon as the rear passes its peak. The yaw start stays
		-- above the yaw a hard keyboard lane change leaves behind the steering, which is no slide.
		Forgiving = { rearSlipStart = 1, yawErrorStart = 0.55 },
	},
}

return Handling
