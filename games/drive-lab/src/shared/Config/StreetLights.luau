--!strict
--[[
	How the street lamps light, on each client. Each lamp carries one downlight between its
	lanterns (the pool on the road: a SpotLight at full range, 60 studs, which at the lamp's
	3.9 m height reaches about 11 m out) and a small glow in each lantern; their brightness,
	colour and range are set on the lamp model itself (ReplicatedStorage.DriveLabAssets).
]]
export type StreetLights = {
	DUSK: number,
	DAWN: number,
	SWITCH_SPREAD: number,
	LIT_DISTANCE: number,
	SHADOW_LAMPS: number,
	BULB_ON: Color3,
	BULB_OFF: Color3,
	UPDATE_INTERVAL: number,
}

local StreetLights: StreetLights = table.freeze({
	-- Lit from dusk to dawn, hours of Lighting.ClockTime (the weather presets set it).
	DUSK = 18,
	DAWN = 6.5,
	-- Seconds over which the lamps come on or go off, each at its own moment.
	SWITCH_SPREAD = 2.5,
	-- Metres from the camera beyond which a lamp's lights stay off: light past this is a dot
	-- the road's own lamps nearer in already cover.
	LIT_DISTANCE = 250,
	-- Only the nearest few downlights cast shadows; every shadowed light costs a pass.
	SHADOW_LAMPS = 6,
	-- The candle-bulb, warm when lit (about 3000 K) and dull wax when not.
	BULB_ON = Color3.fromRGB(255, 190, 120),
	BULB_OFF = Color3.fromRGB(232, 222, 200),
	UPDATE_INTERVAL = 0.25,
})

return StreetLights
