--!strict
--[[
	Runs the flames effect (Effects/ExhaustFlames) in Lune on a stand-in Boss 302 as the rig leaves it,
	a model whose PrimaryPart is its chassis. The client module is run from its file with Lune's
	engine datatypes and instances; ParticleEmitter:Emit, an engine method Lune lacks, counts what it
	is asked to emit; Lighting and task.delay are plain stand-ins. Lune's CFrame.lookAt mirrors the
	direction's z (toward +Z it returns the identity, which looks toward -Z), so the effect gets the
	engine's lookAt built from fromMatrix, checked first against its definition.
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Binding = require("../src/shared/Config/Cars/Binding")
local CarLights = require("../src/shared/Config/CarLights")
local Catalog = require("../src/shared/Config/Cars/Catalog")
local Lamps = require("../src/shared/Rules/CarLights")
local Rules = require("../src/shared/Rules/ExhaustFlames")
local T = require("../../../tools/test/T")
local Units = require("../src/shared/Units")

local describe, it, expect = T.describe, T.it, T.expect

local ROOT = "games/drive-lab/src/"

-- The engine's CFrame.lookAt: looking along at -> target, the right vector level with `up`.
local function lookAt(at: any, target: any, up: any?): any
	local look = (target - at).Unit
	local right = look:Cross(up or roblox.Vector3.new(0, 1, 0)).Unit
	return roblox.CFrame.fromMatrix(at, right, right:Cross(look), -look)
end

local DATATYPES = {
	CFrame = setmetatable({ lookAt = lookAt }, { __index = roblox.CFrame }),
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	Enum = roblox.Enum,
	Instance = roblox.Instance,
	NumberRange = roblox.NumberRange,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	Vector2 = roblox.Vector2,
	Vector3 = roblox.Vector3,
}

local emitted: { [any]: number } = {}
roblox.implementMethod("ParticleEmitter", "Emit", function(emitter: any, count: number)
	emitted[emitter] = (emitted[emitter] or 0) + count
end)

local function run(path: string, globals: { [string]: any }): any
	local environment = table.clone(DATATYPES) :: { [string]: any }
	for name, value in globals do
		environment[name] = value
	end
	return luau.load(fs.readFile(ROOT .. path), { debugName = path, environment = environment })()
end

local Config = run("shared/Config/ExhaustFlames.luau", {})

type Delayed = { seconds: number, callback: () -> () }

-- A fresh copy of the effect, with the delays it asks for.
local function effect(): (any, { Delayed })
	local delayed: { Delayed } = {}
	local services = {
		Lighting = { Brightness = 0 },
		ReplicatedStorage = {
			Shared = {
				Config = { Cars = { Binding = Binding }, CarLights = CarLights, ExhaustFlames = Config },
				Rules = { CarLights = Lamps, ExhaustFlames = Rules },
				Units = Units,
			},
		},
	}
	local Effects = run("client/Effects/ExhaustFlames.luau", {
		game = {
			GetService = function(_self: any, name: string): any
				return assert((services :: any)[name], `no stand-in for {name}`)
			end,
		},
		require = function(module: any): any
			return module
		end,
		task = {
			delay = function(seconds: number, callback: () -> ())
				table.insert(delayed, { seconds = seconds, callback = callback })
			end,
		},
	})
	return Effects, delayed
end

local function standInBoss(): (any, any)
	local model = roblox.Instance.new("Model")
	local chassis = roblox.Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.CFrame = roblox.CFrame.new(12, 3, -40) * roblox.CFrame.Angles(0, math.rad(30), 0)
	chassis.Parent = model
	model.PrimaryPart = chassis
	return model, chassis
end

local function outletsOn(chassis: any): { any }
	local found = {}
	for _, child in chassis:GetChildren() do
		if child:IsA("Attachment") and child.Name == "ExhaustOutlet" then
			table.insert(found, child)
		end
	end
	return found
end

local function childrenOf(attachment: any, className: string): { any }
	local found = {}
	for _, child in attachment:GetChildren() do
		if child:IsA(className) then
			table.insert(found, child)
		end
	end
	return found
end

local function never(): number
	error("drew a number")
end

describe("The engine's lookAt in Lune", function()
	it("looks along the direction given, square and level, where Lune's own does not", function()
		local at = roblox.Vector3.new(1, 2, 3)
		local toward = roblox.Vector3.new(0, 0, 1)
		expect(roblox.CFrame.lookAt(at, at + toward).LookVector:Dot(toward)).toBeNear(-1, 1e-6)
		for _, way in { toward, roblox.Vector3.new(0, 0.17, 0.98), roblox.Vector3.new(-1, 0.3, 0.2) } do
			local frame = lookAt(at, at + way)
			expect(frame.LookVector:Dot(way.Unit)).toBeNear(1, 1e-6)
			expect(frame.RightVector.Y).toBeNear(0, 1e-6)
			expect(frame.RightVector:Dot(frame.UpVector)).toBeNear(0, 1e-6)
			expect((frame.Position - at).Magnitude).toBeNear(0, 1e-6)
		end
	end)
end)

describe("ExhaustFlames drawn on the Boss 302", function()
	local entry = Catalog.cars.Boss302
	local outlets = entry.model.exhaustOutlets or {}

	it("mounts a jet, a fireball and a flash at each of its two outlets, on the chassis", function()
		local Effects = effect()
		local model, chassis = standInBoss()
		Effects.burst(model, entry.model, 1, entry.flames)
		local mounted = outletsOn(chassis)
		expect(#outlets).toBe(2)
		expect(#mounted).toBe(2)
		local studs = Units.metresToStuds(1)
		for _, spec in outlets do
			local at = roblox.Vector3.new(
				spec.centre.right,
				spec.centre.up + entry.model.bodyRaise,
				-spec.centre.forward
			) * studs
			local matched = 0
			for _, attachment in mounted do
				if (attachment.CFrame.Position - at).Magnitude < 1e-3 then
					matched += 1
					local emitters = childrenOf(attachment, "ParticleEmitter")
					expect(#emitters).toBe(2)
					expect(#childrenOf(attachment, "PointLight")).toBe(1)
					for _, emitter in emitters do
						expect(emitter.EmissionDirection).toBe(roblox.Enum.NormalId.Front)
					end
				end
			end
			expect(matched).toBe(1)
		end
	end)

	it("points every outlet back out of the car and a little up, wherever the car stands", function()
		local Effects = effect()
		local model, chassis = standInBoss()
		Effects.burst(model, entry.model, 1, entry.flames)
		local frame = chassis.CFrame
		local back = (-frame.LookVector + frame.UpVector * Config.RISE).Unit
		for _, attachment in outletsOn(chassis) do
			local look = (frame * attachment.CFrame).LookVector
			expect(look:Dot(back) > math.cos(math.rad(1))).toBe(true)
		end
	end)

	it(
		"fires a full-strength pop from both outlets in every mode: three jets, two fireballs, a flash",
		function()
			for _, mode in entry.physics.modeOrder do
				local Effects, delayed = effect()
				local model, chassis = standInBoss()
				local share = Rules.share(entry.flames, mode, "Downshift", 1, never)
				assert(share, `a full pop in {mode} throws a flame`)
				Effects.burst(model, entry.model, share, entry.flames)
				local mounted = outletsOn(chassis)
				expect(#mounted).toBe(2)
				for _, attachment in mounted do
					for _, emitter in childrenOf(attachment, "ParticleEmitter") do
						local expected = if emitter.Texture == Config.JET_TEXTURE then 3 else 2
						expect(emitted[emitter]).toBe(expected)
					end
					expect(childrenOf(attachment, "PointLight")[1].Enabled).toBe(true)
				end
				expect(#delayed).toBe(2)
				for _, pending in delayed do
					expect(pending.seconds).toBe(Config.FLASH.seconds)
					pending.callback()
				end
				for _, attachment in mounted do
					expect(childrenOf(attachment, "PointLight")[1].Enabled).toBe(false)
				end
			end
		end
	)

	it("keeps the same two outlets for the car's later pops", function()
		local Effects = effect()
		local model, chassis = standInBoss()
		Effects.burst(model, entry.model, 1, entry.flames)
		local first = outletsOn(chassis)
		Effects.burst(model, entry.model, 0, entry.flames)
		local again = outletsOn(chassis)
		expect(#again).toBe(2)
		expect(table.find(first, again[1]) ~= nil and table.find(first, again[2]) ~= nil).toBe(true)
	end)
end)
