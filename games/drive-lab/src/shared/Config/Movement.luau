--!strict
export type Animation = { id: string, priority: Enum.AnimationPriority }

export type Movement = {
	-- studs/s. Walking a little under Roblox's normal 16 (owner, 2026-10-27); the feet slide, as in
	-- Roblox's own R6 walk. The run keeps its feet planted at 22 and plays faster above it.
	WALK_SPEED: number,
	SPRINT_SPEED: number,
	SPRINT_KEYS: { Enum.KeyCode },
	-- studs/s each animation was authored for; it plays at ground speed / pace.
	WALK_PACE: number,
	RUN_PACE: number,
	-- studs. Roblox's default jump assumes its default gravity; under real gravity it would
	-- throw a character 36 studs (10 m) up. About 55 cm, a standing jump.
	JUMP_HEIGHT: number,
	-- Above this ground speed the run plays instead of the walk.
	RUN_THRESHOLD: number,
	FADE: number,
	-- Keyed idle, walk, run, jump, fall, climb, sit.
	ANIMATIONS: { [string]: Animation },
}

local WALK_SPEED, SPRINT_SPEED = 12.5, 26

local Movement: Movement = table.freeze({
	WALK_SPEED = WALK_SPEED,
	SPRINT_SPEED = SPRINT_SPEED,
	SPRINT_KEYS = { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3 },
	WALK_PACE = 12.5,
	RUN_PACE = 22,
	JUMP_HEIGHT = 2,
	RUN_THRESHOLD = (WALK_SPEED + SPRINT_SPEED) / 2,
	FADE = 0.18,
	ANIMATIONS = table.freeze({
		-- Ours, from tools/anim (walk_keys.py, run_keys.py).
		walk = { id = "rbxassetid://117025230807317", priority = Enum.AnimationPriority.Movement },
		run = { id = "rbxassetid://96710237493696", priority = Enum.AnimationPriority.Movement },
		-- Roblox's own R6 set, which plays in any experience.
		idle = { id = "rbxassetid://180435571", priority = Enum.AnimationPriority.Idle },
		jump = { id = "rbxassetid://125750702", priority = Enum.AnimationPriority.Movement },
		fall = { id = "rbxassetid://180436148", priority = Enum.AnimationPriority.Movement },
		climb = { id = "rbxassetid://180436334", priority = Enum.AnimationPriority.Movement },
		sit = { id = "rbxassetid://178130996", priority = Enum.AnimationPriority.Movement },
	}),
})

return Movement
