--!strict
--[[
	Runs the driving HUD's controller in Lune, for the specs: the client modules and the shared
	ones that touch the engine as they load are run from their files with Lune's engine datatypes
	and plain stand-ins for the instances and services they use; a stand-in car carries the
	attributes a spec sets; `dump` writes out every property the HUD set, child by child. A
	GuiObject's AbsoluteSize is laid out from its Size on a stand-in screen, an aspect-ratio
	constraint fitting it within that size, and a script listening to it hears each change.
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local ROOT = "games/drive-lab/src"
-- Shared modules that call the engine as they load; every client module does too.
local ENGINE_MODULES = { "shared/Config/Hud", "shared/Config/Controls", "shared/Car/CarRig" }
local NOW = 1000
local SCREEN = roblox.Vector2.new(1920, 1080)
-- A GuiObject's Size until one is set, as the engine's.
local DEFAULT_SIZE = roblox.UDim2.fromOffset(100, 100)
local LAYOUT_PROPERTIES = { Size = true, AspectRatio = true, Parent = true }

type State = {
	className: string,
	props: { [string]: any },
	children: { any },
	parent: any,
	attributes: { [string]: any },
	listeners: { [string]: { () -> () } },
	laidOut: any,
}

local states: { [any]: State } = setmetatable({}, { __mode = "k" }) :: any
-- The screen the stand-in GUI is laid out on, and the instances whose AbsoluteSize is listened to.
local screen = SCREEN
local watched: { any } = {}

local function absoluteSize(object: any): any
	local state = states[object]
	if state.className == "ScreenGui" or state.className == "PlayerGui" then
		return screen
	end
	local within = if state.parent then absoluteSize(state.parent) else screen
	local size = state.props.Size or DEFAULT_SIZE
	local width = size.X.Scale * within.X + size.X.Offset
	local height = size.Y.Scale * within.Y + size.Y.Offset
	for _, child in state.children do
		local constraint = states[child]
		if constraint.className == "UIAspectRatioConstraint" then
			-- The engine's FitWithinMaxSize: the largest box of its shape inside the size given.
			local aspect = constraint.props.AspectRatio or 1
			width = math.min(width, height * aspect)
			height = width / aspect
		end
	end
	return roblox.Vector2.new(width, height)
end

local function relayout()
	for _, object in watched do
		local state = states[object]
		local now = absoluteSize(object)
		if now ~= state.laidOut then
			state.laidOut = now
			for _, callback in state.listeners.AbsoluteSize do
				callback()
			end
		end
	end
end

local METHODS = {
	GetPropertyChangedSignal = function(self: any, name: string)
		return {
			Connect = function(_signal: any, callback: () -> ())
				local state = states[self]
				state.listeners[name] = state.listeners[name] or {}
				table.insert(state.listeners[name], callback)
				if name == "AbsoluteSize" and not table.find(watched, self) then
					state.laidOut = absoluteSize(self)
					table.insert(watched, self)
				end
				return { Disconnect = function() end }
			end,
		}
	end,
	GetAttribute = function(self: any, name: string): any
		return states[self].attributes[name]
	end,
	SetAttribute = function(self: any, name: string, value: any)
		states[self].attributes[name] = value
	end,
	IsA = function(self: any, className: string): boolean
		return states[self].className == className
	end,
	FindFirstChildOfClass = function(self: any, className: string): any
		for _, child in states[self].children do
			if states[child].className == className then
				return child
			end
		end
		return nil
	end,
	WaitForChild = function(self: any, name: string): any
		for _, child in states[self].children do
			if states[child].props.Name == name then
				return child
			end
		end
		error(`no child {name}`)
	end,
}

local function new(className: string): any
	local state: State = {
		className = className,
		props = { Name = className },
		children = {},
		parent = nil,
		attributes = {},
		listeners = {},
		laidOut = nil,
	}
	local object
	object = setmetatable({}, {
		__index = function(_, key: string): any
			if key == "ClassName" then
				return className
			elseif key == "Parent" then
				return state.parent
			elseif (METHODS :: any)[key] then
				return (METHODS :: any)[key]
			elseif key == "AbsoluteSize" then
				return absoluteSize(object)
			end
			return state.props[key]
		end,
		__newindex = function(self: any, key: string, value: any)
			if key == "Parent" then
				local old = state.parent
				if old then
					local siblings = states[old].children
					table.remove(siblings, table.find(siblings, self) :: number)
				end
				state.parent = value
				if value then
					table.insert(states[value].children, self)
				end
			else
				state.props[key] = value
			end
			if LAYOUT_PROPERTIES[key] then
				relayout()
			end
		end,
	})
	states[object] = state
	return object
end

local function show(value: any): string
	if type(value) == "number" then
		return string.format("%.10g", value)
	elseif type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function dirname(path: string): string
	return string.match(path, "^(.*)/[^/]+$") or ""
end

local function normalise(path: string): string
	local parts: { string } = {}
	for part in string.gmatch(path, "[^/]+") do
		if part == ".." then
			table.remove(parts)
		elseif part ~= "." then
			table.insert(parts, part)
		end
	end
	return table.concat(parts, "/")
end

local Harness = {}

export type Run = {
	-- The stand-in car: its attributes are the readouts the HUD reads.
	car: any,
	camera: any,
	playerGui: any,
	setClock: (number) -> (),
	sit: (boolean) -> (),
	-- The screen's size in pixels; the GUI is laid out again on it.
	setScreen: (any) -> (),
	-- Builds the HUD of the car `entry` under the player's gui as `name`, with the run's modules.
	buildView: (any, string) -> any,
	-- One Heartbeat of `dt` seconds.
	step: (number) -> (),
	pressHudKey: () -> (),
}

-- Starts the HUD controller with a seated driver and a car of `carName` running, as long after its
-- start-up as a drive. The client modules come from `clientRoot` (a folder holding `client/`, such
-- as another commit's `src`), the repo's own by default; the shared ones always from the repo.
function Harness.start(carName: string, clientRoot: string?): Run
	local clock = 0
	screen = SCREEN
	watched = {}
	local cache: { [string]: any } = {}
	local refs: { [any]: string } = {}
	local refByPath: { [string]: any } = {}

	local function ref(path: string): any
		local existing = refByPath[path]
		if existing then
			return existing
		end
		local object = setmetatable({}, {
			__index = function(_, key: string): any
				return if key == "Parent" then ref(dirname(path)) else ref(`{path}/{key}`)
			end,
		})
		refs[object] = path
		refByPath[path] = object
		return object
	end

	local playerGui = new("PlayerGui")
	playerGui.Name = "PlayerGui"
	local car = new("Model")
	local seat = new("VehicleSeat")
	seat.Parent = car
	local character = new("Model")
	local humanoid = new("Humanoid")
	humanoid.Parent = character
	humanoid.SeatPart = seat
	local player = new("Player")
	player.Character = character
	playerGui.Parent = player
	local camera = new("Camera")
	local heartbeat: ((number) -> ())? = nil
	local input: ((any, boolean) -> ())? = nil

	local services: { [string]: any } = {
		CollectionService = {
			HasTag = function(_self: any, object: any): boolean
				return object == car
			end,
		},
		Players = { LocalPlayer = player },
		ReplicatedStorage = { Shared = ref("shared") },
		RunService = {
			Heartbeat = {
				Connect = function(_self: any, callback: (number) -> ())
					heartbeat = callback
				end,
			},
		},
		TweenService = {
			-- The tween's end, at once.
			Create = function(_self: any, object: any, _info: any, goal: { [string]: any })
				return {
					Play = function()
						for key, value in goal do
							object[key] = value
						end
					end,
				}
			end,
		},
		UserInputService = {
			InputBegan = {
				Connect = function(_self: any, callback: (any, boolean) -> ())
					input = callback
				end,
			},
		},
		Workspace = {
			CurrentCamera = camera,
			GetServerTimeNow = function()
				return NOW
			end,
		},
	}
	local game = {
		GetService = function(_self: any, name: string): any
			return assert(services[name], `no stand-in for {name}`)
		end,
	}
	local clockOs = setmetatable({
		clock = function(): number
			return clock
		end,
	}, { __index = os })

	local load: (string) -> any
	local function requirer(modulePath: string): (any) -> any
		return function(target: any): any
			if type(target) == "string" then
				local base = if string.sub(target, 1, 6) == "@self/"
					then `{modulePath}/{string.sub(target, 7)}`
					else `{dirname(modulePath)}/{target}`
				return load(normalise(base))
			end
			local path = refs[target]
			assert(path, "require of an unknown instance")
			return load(path)
		end
	end

	load = function(path: string): any
		if cache[path] ~= nil then
			return cache[path]
		end
		local result
		if string.sub(path, 1, 7) == "client/" or table.find(ENGINE_MODULES, path) then
			local root = if string.sub(path, 1, 7) == "client/" then clientRoot or ROOT else ROOT
			local source = `{root}/{path}.luau`
			if not fs.isFile(source) then
				source = `{root}/{path}/init.luau`
			end
			local chunk = luau.load(fs.readFile(source), {
				debugName = source,
				environment = {
					game = game,
					script = ref(path),
					require = requirer(path),
					Instance = { new = new },
					UDim2 = roblox.UDim2,
					UDim = roblox.UDim,
					Vector2 = roblox.Vector2,
					Color3 = roblox.Color3,
					ColorSequence = roblox.ColorSequence,
					ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
					NumberSequence = roblox.NumberSequence,
					NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
					Font = roblox.Font,
					Enum = roblox.Enum,
					TweenInfo = {
						new = function(time: number)
							return { Time = time }
						end,
					},
					os = clockOs,
				},
			})
			result = chunk()
		else
			result = (require :: any)(`../src/{path}`)
		end
		cache[path] = result
		return result
	end

	car:SetAttribute("Car", carName)
	car:SetAttribute("Entry", "Enter")
	car:SetAttribute("EntryAt", 0)
	car:SetAttribute("Engine", "On")
	car:SetAttribute("EngineAt", 0)

	local controller = load("client/Controllers/Hud")
	controller.start()
	local run: Run
	run = {
		car = car,
		camera = camera,
		playerGui = playerGui,
		setClock = function(value: number)
			clock = value
		end,
		sit = function(seated: boolean)
			humanoid.SeatPart = if seated then seat else nil
		end,
		setScreen = function(size: any)
			screen = size
			relayout()
		end,
		buildView = function(entry: any, name: string): any
			local look = load("client/Ui/HudLook").of(entry)
			load("client/Ui/HudView").build(playerGui, look, name)
			return Harness.gui(run, name)
		end,
		step = function(dt: number)
			(assert(heartbeat, "the controller connected no Heartbeat"))(dt)
		end,
		pressHudKey = function()
			(assert(input, "the controller connected no input"))({ KeyCode = roblox.Enum.KeyCode.U }, false)
		end,
	}
	return run
end

export type Frame = {
	view: string,
	clock: number,
	attributes: { [string]: any },
	pressHudKey: boolean?,
	seated: boolean?,
}

-- A drive through the HUD's states: the chase view in automatic with TC acting and the dipped
-- beam, the cockpit in manual past the redline with the assists off and the high beam (the flash
-- lit, then dark, then launch armed), the minimal mode in neutral at rest, then out of the seat.
Harness.SCENARIO = table.freeze({
	{
		view = "Chase",
		clock = 0,
		attributes = {
			GearboxMode = "automatic",
			Gear = 3,
			Rpm = 6400,
			SpeedKmh = 148.4,
			DrivingMode = "Sport",
			TcActive = true,
			HeadlightsOn = true,
			IndicatorLeft = true,
		},
	},
	{
		view = "Cockpit",
		clock = 2.1,
		attributes = {
			GearboxMode = "manual",
			Gear = 4,
			Rpm = 8650,
			SpeedKmh = 212.6,
			EscOff = true,
			TcActive = false,
			HighBeamOn = true,
			IndicatorLeft = false,
			IndicatorRight = true,
		},
	},
	{ view = "Cockpit", clock = 2.3, attributes = { Launch = "Armed", DrivingMode = "Corsa" } },
	{
		view = "Chase",
		clock = 2.5,
		pressHudKey = true,
		attributes = { Launch = false, Gear = 0, Rpm = 900, SpeedKmh = 0, EscOff = false, HighBeamOn = false },
	},
	{ view = "Chase", clock = 2.6, seated = false, attributes = {} },
} :: { Frame })

-- Sets the frame's readouts on the car and view, then runs one Heartbeat.
function Harness.playFrame(run: Run, frame: Frame)
	for key, value in frame.attributes do
		run.car:SetAttribute(key, if value == false then nil else value)
	end
	run.camera:SetAttribute("DriveLabView", frame.view)
	run.setClock(frame.clock)
	if frame.pressHudKey then
		run.pressHudKey()
	end
	if frame.seated == false then
		run.sit(false)
	end
	run.step(1)
end

-- The HUD named `name` written out after the controller starts and after each frame of the
-- scenario.
function Harness.play(run: Run, name: string): { string }
	local dumps = { Harness.dump(Harness.gui(run, name)) }
	for _, frame in Harness.SCENARIO do
		Harness.playFrame(run, frame)
		table.insert(dumps, Harness.dump(Harness.gui(run, name)))
	end
	return dumps
end

export type Node = { className: string, props: { [string]: any }, children: { Node } }

-- `root` and its descendants as plain tables: class, the properties set, children in order.
function Harness.tree(root: any): Node
	local state = states[root]
	local children: { Node } = {}
	for _, child in state.children do
		table.insert(children, Harness.tree(child))
	end
	return { className = state.className, props = table.clone(state.props), children = children }
end

-- Where the engine would lay `object` out, in pixels.
function Harness.absoluteSize(object: any): any
	return absoluteSize(object)
end

-- The frame image of the HUD named `name`.
function Harness.frame(run: Run, name: string): any
	return states[Harness.gui(run, name)].children[1]
end

-- The HUD the controller built under the player's gui by the name `name`.
function Harness.gui(run: Run, name: string): any
	for _, child in states[run.playerGui].children do
		if states[child].props.Name == name then
			return child
		end
	end
	return nil
end

-- Every property set on `root` and its descendants, one line per instance in child order.
function Harness.dump(root: any): string
	local lines: { string } = {}
	local function walk(object: any, path: string)
		local state = states[object]
		local keys: { string } = {}
		for key in state.props do
			table.insert(keys, key)
		end
		table.sort(keys)
		local parts: { string } = {}
		for _, key in keys do
			table.insert(parts, `{key}={show(state.props[key])}`)
		end
		table.insert(lines, `{path} {state.className} {table.concat(parts, " ")}`)
		for index, child in state.children do
			walk(child, `{path}/{index}`)
		end
	end
	walk(root, states[root].props.Name)
	return table.concat(lines, "\n")
end

return Harness
