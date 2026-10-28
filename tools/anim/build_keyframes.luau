--!strict
--[[
	Turns a pose bake from tools/blender/r6_rig.py into a KeyframeSequence .rbxm: one Keyframe
	per baked frame with linear easing, so the curves authored in Blender play back as authored.
	Usage: lune run tools/anim/build_keyframes <baked.json> <out.rbxm> <name> [--loop]
		[--priority Movement] [--keys <keys.json>] [--rest Neck]
	--keys copies the keys file's markers (name, frame) onto the keyframes as KeyframeMarkers.
	--rest leaves a joint at its rest pose, for joints a script drives (the head follows the
	camera in game).
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Instance, CFrame, Enum = roblox.Instance, roblox.CFrame, roblox.Enum

type Baked = { fps: number, frames: { { time: number, poses: { [string]: { number } } } } }

-- Pose tree for R6: each pose is named after the part a joint moves, carrying that joint's Transform.
local CHILDREN_OF_TORSO = {
	{ part = "Head", joint = "Neck" },
	{ part = "Right Arm", joint = "Right Shoulder" },
	{ part = "Left Arm", joint = "Left Shoulder" },
	{ part = "Right Leg", joint = "Right Hip" },
	{ part = "Left Leg", joint = "Left Hip" },
}

local function cframeOf(values: { number }): any
	return CFrame.new(table.unpack(values))
end

local function pose(name: string, cframe: any, parent: any): any
	local instance = Instance.new("Pose")
	instance.Name = name
	instance.CFrame = cframe
	instance.EasingStyle = Enum.PoseEasingStyle.Linear
	instance.Weight = 1
	instance.Parent = parent
	return instance
end

type Keys = { fps: number, markers: { { name: string, frame: number } }? }

local args = process.args
local inPath, outPath, name = args[1], args[2], args[3]
if inPath == nil or outPath == nil or name == nil then
	error("usage: build_keyframes <baked.json> <out.rbxm> <name> [--loop] [--priority Movement]")
end
local loop = table.find(args, "--loop") ~= nil
local priorityIndex = table.find(args, "--priority")
local priority = if priorityIndex then args[priorityIndex + 1] else "Movement"
local keysIndex = table.find(args, "--keys")
local keys: Keys? = if keysIndex then serde.decode("json", fs.readFile(args[keysIndex + 1])) else nil
local restIndex = table.find(args, "--rest")
local resting = if restIndex then args[restIndex + 1] else nil

local baked: Baked = serde.decode("json", fs.readFile(inPath))
local sequence = Instance.new("KeyframeSequence")
sequence.Name = name
sequence.Loop = loop
sequence.Priority = (Enum.AnimationPriority :: any)[priority]

local markersAt: { [number]: { string } } = {}
for _, marker in if keys and keys.markers then keys.markers else {} do
	local at = math.round(marker.frame / keys.fps * 1000)
	markersAt[at] = markersAt[at] or {}
	table.insert(markersAt[at], marker.name)
end

local placed = 0
for _, frame in baked.frames do
	local keyframe = Instance.new("Keyframe")
	keyframe.Time = frame.time
	local root = pose("HumanoidRootPart", CFrame.new(), keyframe)
	local torso = pose("Torso", cframeOf(frame.poses.RootJoint), root)
	for _, child in CHILDREN_OF_TORSO do
		local cframe = if child.joint == resting then CFrame.new() else cframeOf(frame.poses[child.joint])
		pose(child.part, cframe, torso)
	end
	for _, markerName in markersAt[math.round(frame.time * 1000)] or {} do
		local marker = Instance.new("KeyframeMarker")
		marker.Name = markerName
		marker.Parent = keyframe
		placed += 1
	end
	keyframe.Parent = sequence
end
local wanted = if keys and keys.markers then #keys.markers else 0
assert(placed == wanted, `placed {placed} of {wanted} markers: a marker frame is not a baked frame`)

fs.writeFile(outPath, roblox.serializeModel({ sequence }))
print(
	`{name}: {#baked.frames} keyframes, {placed} markers, loop={loop}, rest={resting or "none"} -> {outPath}`
)
