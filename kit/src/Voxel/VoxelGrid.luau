--!strict
--[[
	Sparse voxel grid with a greedy mesher. Pure Luau, so it runs under Lune tests and in
	Studio alike. Models are authored as data (fill, carve, paint) and greedy() merges
	same-key neighbours into the fewest boxes before they become Parts.
]]

export type Box = {
	x1: number,
	y1: number,
	z1: number,
	x2: number,
	y2: number,
	z2: number,
	key: string,
}

local OFFSET = 512
local SPAN = 1024

local function pack(x: number, y: number, z: number): number
	return ((x + OFFSET) * SPAN + (y + OFFSET)) * SPAN + (z + OFFSET)
end

local function unpack(index: number): (number, number, number)
	local z = index % SPAN
	local rest = (index - z) // SPAN
	local y = rest % SPAN
	local x = (rest - y) // SPAN
	return x - OFFSET, y - OFFSET, z - OFFSET
end

local function ordered(a: number, b: number): (number, number)
	if a <= b then
		return a, b
	end
	return b, a
end

local VoxelGrid = {}
VoxelGrid.__index = VoxelGrid

export type VoxelGrid = typeof(setmetatable({} :: { cells: { [number]: string } }, VoxelGrid))

function VoxelGrid.new(): VoxelGrid
	return setmetatable({ cells = {} }, VoxelGrid)
end

local function write(cells: { [number]: string }, index: number, key: string?)
	if key then
		cells[index] = key
	else
		cells[index] = nil
	end
end

function VoxelGrid.set(self: VoxelGrid, x: number, y: number, z: number, key: string?)
	write(self.cells, pack(x, y, z), key)
end

function VoxelGrid.get(self: VoxelGrid, x: number, y: number, z: number): string?
	return self.cells[pack(x, y, z)]
end

function VoxelGrid.fill(
	self: VoxelGrid,
	xa: number,
	xb: number,
	ya: number,
	yb: number,
	za: number,
	zb: number,
	key: string?
)
	local x1, x2 = ordered(xa, xb)
	local y1, y2 = ordered(ya, yb)
	local z1, z2 = ordered(za, zb)
	for x = x1, x2 do
		for y = y1, y2 do
			for z = z1, z2 do
				write(self.cells, pack(x, y, z), key)
			end
		end
	end
end

function VoxelGrid.paint(
	self: VoxelGrid,
	xa: number,
	xb: number,
	ya: number,
	yb: number,
	za: number,
	zb: number,
	key: string,
	only: string?
)
	local x1, x2 = ordered(xa, xb)
	local y1, y2 = ordered(ya, yb)
	local z1, z2 = ordered(za, zb)
	for x = x1, x2 do
		for y = y1, y2 do
			for z = z1, z2 do
				local index = pack(x, y, z)
				local current = self.cells[index]
				if current and (only == nil or current == only) then
					self.cells[index] = key
				end
			end
		end
	end
end

function VoxelGrid.top(self: VoxelGrid, x: number, z: number, yMin: number, yMax: number): number?
	for y = yMax, yMin, -1 do
		if self.cells[pack(x, y, z)] then
			return y
		end
	end
	return nil
end

function VoxelGrid.count(self: VoxelGrid): number
	local total = 0
	for _ in self.cells do
		total += 1
	end
	return total
end

function VoxelGrid.bounds(self: VoxelGrid): (number, number, number, number, number, number)
	local x1, y1, z1 = math.huge, math.huge, math.huge
	local x2, y2, z2 = -math.huge, -math.huge, -math.huge
	for index in self.cells do
		local x, y, z = unpack(index)
		x1, y1, z1 = math.min(x1, x), math.min(y1, y), math.min(z1, z)
		x2, y2, z2 = math.max(x2, x), math.max(y2, y), math.max(z2, z)
	end
	return x1, x2, y1, y2, z1, z2
end

local function canGrowX(
	grid: VoxelGrid,
	used: { [number]: true },
	x: number,
	y: number,
	z: number,
	key: string
): boolean
	local index = pack(x, y, z)
	return grid.cells[index] == key and not used[index]
end

local function rowFree(
	grid: VoxelGrid,
	used: { [number]: true },
	x1: number,
	x2: number,
	y: number,
	z: number,
	key: string
): boolean
	for x = x1, x2 do
		if not canGrowX(grid, used, x, y, z, key) then
			return false
		end
	end
	return true
end

local function slabFree(grid: VoxelGrid, used: { [number]: true }, box: Box, z: number): boolean
	for y = box.y1, box.y2 do
		if not rowFree(grid, used, box.x1, box.x2, y, z, box.key) then
			return false
		end
	end
	return true
end

function VoxelGrid.greedy(self: VoxelGrid): { Box }
	local boxes: { Box } = {}
	if next(self.cells) == nil then
		return boxes
	end
	local minX, maxX, minY, maxY, minZ, maxZ = self:bounds()
	local used: { [number]: true } = {}
	local covered = 0

	for z = minZ, maxZ do
		for y = minY, maxY do
			for x = minX, maxX do
				local key = self.cells[pack(x, y, z)]
				if key == nil or used[pack(x, y, z)] then
					continue
				end
				local box: Box = { x1 = x, y1 = y, z1 = z, x2 = x, y2 = y, z2 = z, key = key }
				while box.x2 < maxX and canGrowX(self, used, box.x2 + 1, y, z, key) do
					box.x2 += 1
				end
				while box.y2 < maxY and rowFree(self, used, box.x1, box.x2, box.y2 + 1, z, key) do
					box.y2 += 1
				end
				while box.z2 < maxZ and slabFree(self, used, box, box.z2 + 1) do
					box.z2 += 1
				end
				for bz = box.z1, box.z2 do
					for by = box.y1, box.y2 do
						for bx = box.x1, box.x2 do
							used[pack(bx, by, bz)] = true
						end
					end
				end
				covered += (box.x2 - box.x1 + 1) * (box.y2 - box.y1 + 1) * (box.z2 - box.z1 + 1)
				table.insert(boxes, box)
			end
		end
	end

	assert(covered == self:count(), `greedy mesh covered {covered} of {self:count()} voxels`)
	return boxes
end

return VoxelGrid
