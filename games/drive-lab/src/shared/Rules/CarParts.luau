--!strict
--[[
	Which piece of a car model rides which. A model binding names parts; a part exported in several
	materials is several pieces, one named after the part and the others carrying the part's name
	in their "Part" attribute (docs/pipelines/HERO_CAR.md). A piece rides the piece its binding's
	`parents` names, else the part it was exported from; anything else rides the body.
]]

-- A piece of the model by its name, and the part it was exported from, if any.
export type Piece = { name: string, part: string? }

local CarParts = {}

-- The attribute a piece carries its part's name in.
CarParts.PART_ATTRIBUTE = "Part"

-- The piece each piece rides, by name. A carrier the model does not have, or a chain of carriers
-- that loops, leaves the piece on the body: a ring of welds holds nothing to the car.
function CarParts.carriers(pieces: { Piece }, parents: { [string]: string }?): { [string]: string }
	local present: { [string]: boolean } = {}
	for _, piece in pieces do
		present[piece.name] = true
	end
	local carriers: { [string]: string } = {}
	for _, piece in pieces do
		local target = if parents then parents[piece.name] else nil
		if target == nil and piece.part ~= nil and piece.part ~= piece.name then
			target = piece.part
		end
		if target ~= nil and target ~= piece.name and present[target] then
			carriers[piece.name] = target
		end
	end
	local looped: { string } = {}
	for name in carriers do
		local current = carriers[name]
		for _ = 1, #pieces do
			if current == nil then
				break
			elseif current == name then
				table.insert(looped, name)
				break
			end
			current = carriers[current]
		end
	end
	for _, name in looped do
		carriers[name] = nil
	end
	return carriers
end

-- The piece at the end of `name`'s chain of carriers: itself when it rides the body.
function CarParts.root(carriers: { [string]: string }, name: string): string
	local current = name
	while carriers[current] do
		current = carriers[current]
	end
	return current
end

return table.freeze(CarParts)
