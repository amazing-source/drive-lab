--!strict
export type Surfaces = {
	GRIP: { [Enum.Material]: number },
	DEFAULT_GRIP: number,
	-- Grip kept on a fully wet surface; Workspace's "Wetness" attribute (0 to 1) blends to it.
	WET_GRIP: number,
}

-- Friction relative to dry asphalt, which the tyre data is measured on.
local Surfaces: Surfaces = table.freeze({
	GRIP = table.freeze({
		[Enum.Material.Asphalt] = 1.0,
		[Enum.Material.Concrete] = 0.95,
		[Enum.Material.SmoothPlastic] = 0.95,
		[Enum.Material.Plastic] = 0.95,
		[Enum.Material.Pavement] = 0.95,
		[Enum.Material.Cobblestone] = 0.8,
		[Enum.Material.Brick] = 0.85,
		[Enum.Material.Ground] = 0.6,
		[Enum.Material.Grass] = 0.55,
		[Enum.Material.LeafyGrass] = 0.55,
		[Enum.Material.Mud] = 0.4,
		[Enum.Material.Sand] = 0.45,
		[Enum.Material.Snow] = 0.3,
		[Enum.Material.Ice] = 0.12,
		[Enum.Material.Glacier] = 0.12,
	}),
	DEFAULT_GRIP = 0.9,
	WET_GRIP = 0.7,
})

return Surfaces
