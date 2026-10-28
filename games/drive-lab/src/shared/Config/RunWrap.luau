--!strict
export type RunWrap = {
	-- The run animation marker the burst fires on: the swap, where arms and legs scissor.
	MARKER: string,
	RUN_ANIMATION: string,
	TEXTURE: string,
	LAYOUT: Enum.ParticleFlipbookLayout,
	LIFETIME: number,
	SIZE: number,
	-- Below the root part, around the legs and lower torso.
	OFFSET: Vector3,
}

local RunWrap: RunWrap = table.freeze({
	MARKER = "Swap",
	RUN_ANIMATION = "rbxassetid://96710237493696",
	-- The owner's 16-frame swirl (vfx/RunWindSwirl_4x4.png): builds, peaks on frames 5 to 8,
	-- then scatters. Real transparency, so it blends normally.
	TEXTURE = "rbxassetid://77537310426565",
	LAYOUT = Enum.ParticleFlipbookLayout.Grid4x4,
	-- One-shot over 16 drawings; fired on the marker, so the peak lands on the swap itself.
	LIFETIME = 0.25,
	SIZE = 6,
	OFFSET = Vector3.new(0, -1.4, 0),
})

return RunWrap
