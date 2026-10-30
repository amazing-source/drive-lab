--!strict
--[[
	The controls screen's content (Config/ControlsHelp), checked and laid out without the engine:
	which rows a car shows, which inputs a row shows, everything that would leave a control
	unexplained, the columns. Keys arrive by their KeyCode names, so Lune can test it against the
	real Config/Controls; the label a player's own keyboard prints on a key arrives as a layout.
]]
export type Row = {
	label: string,
	-- One plain sentence; {NAME} quotes a number from the help's values.
	text: string,
	-- Config/Controls entries this row explains: their keys are shown, keyboard and gamepad apart.
	controls: { string },
	-- Config/Controls entries another row explains whose keys this row shows too, for another
	-- use of them (reverse is the brake held at a standstill).
	keysOf: { string }?,
	-- Inputs bound outside Config/Controls (Roblox's defaults, the prompts, the mouse, the
	-- triggers and sticks Driving reads itself), shown after the controls' own keys.
	keyboard: { string }?,
	gamepad: { string }?,
	-- A word before the keys, as "Hold" or "Tap".
	keyboardGesture: string?,
	gamepadGesture: string?,
	-- The cars (Config/Cars/Catalog names) this row is for; every car's when absent.
	cars: { string }?,
	-- A feature the car must have for the row to show (Config/Cars/Contract.features).
	requires: string?,
}

export type Group = { title: string, rows: { Row } }

export type Help = {
	groups: { Group },
	-- Display names of keys whose KeyCode name is not what a player reads on the key.
	keyNames: { [string]: string },
	-- Numbers the texts quote, read from the configs that own them.
	values: { [string]: number },
	maxLabelLength: number,
	maxTextLength: number,
}

-- Every key list a row may explain, by name, each key by its KeyCode name.
export type Bindings = { [string]: { string } }

export type Shown = { gesture: string?, keys: { string } }

-- What the player's keyboard prints on a key, by KeyCode name: AZERTY prints Z on W.
export type Layout = { [string]: string }

local GAMEPAD_PREFIXES = { "Button", "DPad", "Thumbstick" }

local NONE: { string } = table.freeze({})

local ControlsHelp = {}

function ControlsHelp.isGamepadKey(name: string): boolean
	for _, prefix in GAMEPAD_PREFIXES do
		if string.sub(name, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

-- A key as the player reads it: the label their keyboard prints, when it prints one, or the key's
-- display name.
function ControlsHelp.keyLabel(name: string, keyNames: { [string]: string }, layout: Layout?): string
	local printed = layout and layout[name]
	if printed and string.match(printed, "^%S+$") then
		return string.upper(printed)
	end
	return keyNames[name] or name
end

local function add(list: { string }, keyNames: { [string]: string }, layout: Layout?, name: string)
	local shown = ControlsHelp.keyLabel(name, keyNames, layout)
	if not table.find(list, shown) then
		table.insert(list, shown)
	end
end

-- What a row shows on each side: its controls' keys and the keys it borrows, then the inputs it
-- declares itself.
function ControlsHelp.inputs(
	row: Row,
	bindings: Bindings,
	keyNames: { [string]: string },
	layout: Layout?
): (Shown, Shown)
	local keyboard: { string } = {}
	local gamepad: { string } = {}
	for _, list in { row.controls, row.keysOf or NONE } do
		for _, control in list do
			for _, key in bindings[control] or NONE do
				local gamepadKey = ControlsHelp.isGamepadKey(key)
				add(
					if gamepadKey then gamepad else keyboard,
					keyNames,
					if gamepadKey then nil else layout,
					key
				)
			end
		end
	end
	for _, name in row.keyboard or NONE do
		add(keyboard, keyNames, layout, name)
	end
	for _, name in row.gamepad or NONE do
		add(gamepad, keyNames, nil, name)
	end
	return { gesture = row.keyboardGesture, keys = keyboard }, { gesture = row.gamepadGesture, keys = gamepad }
end

-- A number as a sentence quotes it: 3, 0.6, 0.35.
function ControlsHelp.number(value: number): string
	local text = string.format("%.2f", value)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text
end

function ControlsHelp.formatted(values: { [string]: number }): { [string]: string }
	local texts: { [string]: string } = {}
	for name, value in values do
		texts[name] = ControlsHelp.number(value)
	end
	return texts
end

-- Replaces each {NAME} with its value; one with no value is left as it is.
function ControlsHelp.fill(text: string, values: { [string]: string }): string
	local filled = string.gsub(text, "{([%w_]+)}", function(name: string): string
		return values[name] or `\{{name}\}`
	end)
	return filled
end

local function blank(text: string): boolean
	return string.match(text, "%S") == nil
end

local function textProblems(text: string, help: Help): { string }
	if blank(text) then
		return { "is missing" }
	end
	local found: { string } = {}
	for name in string.gmatch(text, "{([%w_]+)}") do
		if help.values[name] == nil then
			table.insert(found, `quotes {name}, which no config fills`)
		end
	end
	local filled = ControlsHelp.fill(text, ControlsHelp.formatted(help.values))
	if string.match(filled, "^%u") == nil then
		table.insert(found, "does not start with a capital letter")
	end
	if string.sub(filled, -1) ~= "." then
		table.insert(found, "does not end with a full stop")
	end
	if string.find(filled, "[%.!?]%s") then
		table.insert(found, "is more than one sentence")
	end
	if (utf8.len(filled) or #filled) > help.maxTextLength then
		table.insert(found, `is longer than {help.maxTextLength} characters`)
	end
	return found
end

local function rowProblems(
	row: Row,
	title: string,
	help: Help,
	bindings: Bindings,
	covered: { [string]: string }
): { string }
	local found: { string } = {}
	local name = if blank(row.label) then `a row in "{title}"` else row.label
	if blank(row.label) then
		table.insert(found, `{name} has no label`)
	elseif (utf8.len(row.label) or #row.label) > help.maxLabelLength then
		table.insert(found, `{name}: the label is longer than {help.maxLabelLength} characters`)
	end
	for _, problem in textProblems(row.text, help) do
		table.insert(found, `{name}: the explanation {problem}`)
	end
	for _, control in row.controls do
		if bindings[control] == nil then
			table.insert(found, `{name} explains {control}, which is not a control`)
		elseif covered[control] ~= nil then
			table.insert(found, `{control} is explained twice, by {covered[control]} and {name}`)
		else
			covered[control] = name
		end
	end
	for _, control in row.keysOf or NONE do
		if bindings[control] == nil then
			table.insert(found, `{name} shows the keys of {control}, which is not a control`)
		end
	end
	local keyboard, gamepad = ControlsHelp.inputs(row, bindings, help.keyNames)
	if #keyboard.keys == 0 and #gamepad.keys == 0 then
		table.insert(found, `{name} shows no input`)
	end
	return found
end

-- Everything that would leave a control unexplained or a row wrong, sorted; empty when the
-- screen is complete.
function ControlsHelp.problems(help: Help, bindings: Bindings): { string }
	local found: { string } = {}
	local covered: { [string]: string } = {}
	for _, group in help.groups do
		if blank(group.title) or #group.rows == 0 then
			table.insert(found, `a group "{group.title}" has no title or no rows`)
		end
		for _, row in group.rows do
			for _, problem in rowProblems(row, group.title, help, bindings, covered) do
				table.insert(found, problem)
			end
		end
	end
	for control, keys in bindings do
		if covered[control] == nil then
			table.insert(found, `{control} has no row: no label and no explanation`)
		end
		for _, key in keys do
			if #key > 1 and help.keyNames[key] == nil then
				table.insert(found, `{key} ({control}) has no display name`)
			end
		end
	end
	table.sort(found)
	return found
end

-- The screen for one car: the rows for it whose feature it has and whose controls it has, the
-- bindings without the controls it lacks (`needs` names the feature each such control needs), and
-- the help's values with the car's own over them.
function ControlsHelp.forCar(
	help: Help,
	bindings: Bindings,
	car: string,
	features: { [string]: boolean },
	needs: { [string]: string },
	values: { [string]: number }
): (Help, Bindings)
	local carBindings: Bindings = {}
	for control, keys in bindings do
		local need = needs[control]
		if need == nil or features[need] then
			carBindings[control] = keys
		end
	end
	local groups: { Group } = {}
	for _, group in help.groups do
		local rows: { Row } = {}
		for _, row in group.rows do
			local forCar = row.cars == nil or table.find(row.cars, car) ~= nil
			local hasFeature = row.requires == nil or features[row.requires] == true
			local hasControls = true
			for _, control in row.controls do
				hasControls = hasControls and carBindings[control] ~= nil
			end
			if forCar and hasFeature and hasControls then
				table.insert(rows, row)
			end
		end
		if #rows > 0 then
			table.insert(groups, { title = group.title, rows = rows })
		end
	end
	local merged = table.clone(help.values)
	for name, value in values do
		merged[name] = value
	end
	return {
		groups = groups,
		keyNames = help.keyNames,
		values = merged,
		maxLabelLength = help.maxLabelLength,
		maxTextLength = help.maxTextLength,
	},
		carBindings
end

-- The other controls that share each of `control`'s keys.
function ControlsHelp.sharedKeys(bindings: Bindings, control: string): { [string]: { string } }
	local shared: { [string]: { string } } = {}
	for _, key in bindings[control] or NONE do
		for other, keys in bindings do
			if other ~= control and table.find(keys, key) then
				shared[key] = shared[key] or {}
				table.insert(shared[key], other)
			end
		end
	end
	return shared
end

-- Splits the groups, in order, into `count` columns whose tallest is as short as it can be.
function ControlsHelp.columns(heights: { number }, count: number): { { number } }
	local total = #heights
	local columns = math.clamp(count, 1, math.max(total, 1))
	local before = table.create(total + 1, 0)
	for index, height in heights do
		before[index + 1] = before[index] + height
	end
	-- tallest[k][i]: the least tallest column holding the first i groups in k columns; start[k][i]
	-- the group that opens its last column.
	local tallest: { { number } } = { {} }
	local start: { { number } } = { {} }
	for i = 0, total do
		tallest[1][i + 1] = before[i + 1]
		start[1][i + 1] = 1
	end
	for k = 2, columns do
		tallest[k], start[k] = {}, {}
		for i = 0, total do
			local best, cut = math.huge, i + 1
			for j = 0, i do
				local height = math.max(tallest[k - 1][j + 1], before[i + 1] - before[j + 1])
				if height < best then
					best, cut = height, j + 1
				end
			end
			tallest[k][i + 1], start[k][i + 1] = best, cut
		end
	end
	local result: { { number } } = table.create(columns)
	local last = total
	for k = columns, 1, -1 do
		local first = start[k][last + 1]
		local column: { number } = {}
		for index = first, last do
			table.insert(column, index)
		end
		result[k] = column
		last = first - 1
	end
	return result
end

function ControlsHelp.columnCount(width: number, columnWidth: number, maxColumns: number): number
	return math.clamp(math.floor(width / columnWidth), 1, maxColumns)
end

-- A press of the controls button counts when released within `limit` seconds, so a longer hold
-- of the same button stays another control's (B's hold gets out of the car).
function ControlsHelp.isTap(heldSeconds: number, limit: number): boolean
	return heldSeconds >= 0 and heldSeconds <= limit
end

return ControlsHelp
