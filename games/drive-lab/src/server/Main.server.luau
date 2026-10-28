--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local Isolate = require(ReplicatedStorage.Kit.Isolate)
local Log = require(ReplicatedStorage.Kit.Log)
local Movement = require(ReplicatedStorage.Shared.Config.Movement)
local World = require(ReplicatedStorage.Shared.Config.World)

local Services = script.Parent.Services
local log = Log.scope("Boot")

local START_ORDER = {
	Services.HeadLook,
	-- Before Cars: the road and pad must be under the car when it is rigged.
	Services.Track,
	Services.Cars,
	-- After Cars: it takes over the cars Cars has rigged.
	Services.CarEntry,
}

Workspace.Gravity = World.GRAVITY
StarterPlayer.CharacterUseJumpPower = false
StarterPlayer.CharacterJumpHeight = Movement.JUMP_HEIGHT

-- Each service starts in isolation, so one that throws or yields cannot stop the others.
for _, module in START_ORDER do
	local outcome, problem = Isolate.run(function()
		local service = require(module) :: { start: () -> () }
		service.start()
	end)
	if outcome == "failed" then
		log.error(`{module.Name} failed to start: {problem}`)
	elseif outcome == "yielded" then
		log.warn(`{module.Name}.start yielded; the rest start without waiting for it`)
	end
end
