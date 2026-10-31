--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Isolate = require(ReplicatedStorage.Kit.Isolate)
local Log = require(ReplicatedStorage.Kit.Log)

local Controllers = script.Parent.Controllers
local log = Log.scope("Boot")

local START_ORDER = {
	Controllers.HeadLook,
	Controllers.BodyLean,
	Controllers.Driving,
	Controllers.CarEntry,
	Controllers.Locomotion,
	Controllers.CameraFeel,
	Controllers.CarAudio,
	Controllers.CarCamera,
	Controllers.CockpitGlazing,
	Controllers.CarDoor,
	Controllers.Cluster,
	Controllers.Binnacle,
	Controllers.DriverArms,
	Controllers.DriverLegs,
	Controllers.StreetLights,
	Controllers.CarLights,
	Controllers.CarSwitches,
	Controllers.CarWiper,
	Controllers.RimBlur,
	Controllers.Reflectors,
	Controllers.Hud,
	Controllers.ControlsHelp,
	script.Parent.Atmosphere,
	Controllers.WeatherAudio,
	Controllers.RoadAudio,
	Controllers.TyreAudio,
	Controllers.MotionBlur,
	Controllers.DrivingEffects,
	-- Controllers.RunWrap is off: the owner rejected the run's wind swirl (2026-10-27).
}

-- The game gives no tools, and Roblox's backpack would keep the number keys for its hotbar: the
-- DR458's rain light is on the key printed 1 (Config/Controls).
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

-- Each controller starts in isolation, so one that throws or yields cannot stop the others.
for _, module in START_ORDER do
	local outcome, problem = Isolate.run(function()
		local controller = require(module) :: { start: () -> () }
		controller.start()
	end)
	if outcome == "failed" then
		log.error(`{module.Name} failed to start: {problem}`)
	elseif outcome == "yielded" then
		log.warn(`{module.Name}.start yielded; the rest start without waiting for it`)
	end
end
