--!strict
--[[
	The road's furniture and surface marks (Rules/Roadside places them, the server's Roadside
	lays them with each chunk). Metres, after Italian practice for a two-lane extra-urban road;
	the models are made by tools/blender/roadside_props.py and the mark textures by
	tools/assets/roadside_textures.py, both described in docs/pipelines/ROADSIDE.md.
]]
local Roadside = require("../Rules/Roadside")
local Scatter = require("../Rules/Scatter")

export type MarkLook = { image: string, lift: number, transparency: { min: number, max: number } }

export type Config = {
	DELINEATORS: Scatter.Layout,
	DELINEATOR_SETBACK: number,
	DELINEATOR_CLEARANCE: number,
	GUARDRAILS: Roadside.GuardrailLayout,
	GUARDRAIL_SETBACK: number,
	-- Metres behind the road's start where the barrier across it stands.
	ROAD_END_SETBACK: number,
	GANTRIES: Scatter.Layout,
	MARKS: Roadside.MarkLayout,
	-- By mark kind.
	MARK_LOOKS: { [string]: MarkLook },
	MARK_THICKNESS: number,
	ASSETS: {
		delineator: string,
		sections: { string },
		start: string,
		finish: string,
		gantry: string,
	},
	YIELD_EVERY: number,
}

local MARK_KINDS: { Roadside.MarkSpec } = {
	-- Repair patches, square to the road.
	{
		kind = "Patch",
		weight = 3,
		length = { min = 1.2, max = 4 },
		width = { min = 0.9, max = 2.6 },
		lateral = 0.9,
		yaw = 0.06,
		transverse = 0,
	},
	-- Tar-sealed cracks: most along the road, a third straight across it.
	{
		kind = "Crack",
		weight = 3,
		length = { min = 2.5, max = 7 },
		width = { min = 0.55, max = 0.7 },
		lateral = 1.6,
		yaw = 0.12,
		transverse = 0.35,
	},
	{
		kind = "Stain",
		weight = 2,
		length = { min = 0.7, max = 1.8 },
		width = { min = 0.6, max = 1.5 },
		lateral = 0.5,
		yaw = math.pi,
		transverse = 0,
	},
	-- One car's braking marks, in the wheel paths.
	{
		kind = "Skid",
		weight = 1.2,
		length = { min = 12, max = 32 },
		width = { min = 1.8, max = 2 },
		lateral = 0.35,
		yaw = 0.025,
		transverse = 0,
	},
	-- The oil drips down the middle of a lane, between the wheel paths.
	{
		kind = "Drips",
		weight = 2,
		length = { min = 8, max = 24 },
		width = { min = 0.5, max = 0.8 },
		lateral = 0.2,
		yaw = 0.01,
		transverse = 0,
	},
}

-- Each kind on its own layer (studs above the road), under the lane lines' tops (0.075).
local MARK_LOOKS: { [string]: MarkLook } = {
	Patch = { image = "rbxassetid://135678717771849", lift = 0.02, transparency = { min = 0, max = 0.3 } },
	Drips = { image = "rbxassetid://115321322246085", lift = 0.025, transparency = { min = 0, max = 0.35 } },
	Stain = { image = "rbxassetid://133634426929025", lift = 0.03, transparency = { min = 0, max = 0.3 } },
	Crack = { image = "rbxassetid://89219408251447", lift = 0.035, transparency = { min = 0, max = 0.15 } },
	Skid = { image = "rbxassetid://121884617107405", lift = 0.04, transparency = { min = 0, max = 0.3 } },
}

local Config: Config = table.freeze({
	-- A post at most every 50 m, as the rules ask (DPR 495/1992 art. 173), set by hand so a
	-- little uneven; now and then one is missing.
	DELINEATORS = table.freeze({ spacing = 50, jitter = 0.08, skip = 0.04, start = 60 }),
	-- From the road's edge to a post's centre: at the shoulder's outer edge, 0.9 m from the
	-- edge line.
	DELINEATOR_SETBACK = 0.5,
	-- No post within this of a guardrail's terminal.
	DELINEATOR_CLEARANCE = 6,
	-- One stretch in at most every 450 m a side, 48 to 360 m long, cut to 12 m sections that
	-- alternate between the two section models; buried terminals 4 m long at both ends.
	GUARDRAILS = table.freeze({
		spacing = 450,
		skip = 0.4,
		shortest = 48,
		longest = 360,
		start = 120,
		section = 12,
		variants = 2,
		terminal = 4,
	}),
	-- From the road's edge to the beam's face.
	GUARDRAIL_SETBACK = 0.3,
	-- Behind the road the world ends at the start pad's edge (#69): a line of the same guardrail
	-- closes the road's start across the road and both verges, on the pad's concrete just behind
	-- the first metre of asphalt.
	ROAD_END_SETBACK = 1,
	-- A sign gantry about every 1.2 km, unevenly.
	GANTRIES = table.freeze({ spacing = 900, jitter = 0.35, skip = 0.25, start = 250 }),
	-- About one mark every 30 m a lane. Lanes are 3.5 m: their centres 1.75 m off the middle.
	MARKS = table.freeze({
		lattice = table.freeze({ spacing = 22, jitter = 0.45, skip = 0.25, start = 40 }),
		lane = 1.75,
		kinds = table.freeze(MARK_KINDS),
	}),
	MARK_LOOKS = table.freeze(MARK_LOOKS),
	MARK_THICKNESS = 0.01,
	-- Models kept in the place under ReplicatedStorage.DriveLabAssets.
	ASSETS = table.freeze({
		delineator = "Delineator",
		sections = table.freeze({ "GuardrailA", "GuardrailB" }),
		start = "GuardrailStart",
		finish = "GuardrailEnd",
		gantry = "SignGantry",
	}),
	-- Things laid between yields, so a chunk's furniture reaches clients over a few frames.
	YIELD_EVERY = 40,
})

return Config
