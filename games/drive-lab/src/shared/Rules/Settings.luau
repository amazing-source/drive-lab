--!strict
--[[
	The player's settings in plain Luau: the checks a settings list must pass, and a store holding
	each setting's chosen option for the session, which tells its listeners when one changes.
]]
export type Setting = {
	id: string,
	label: string,
	-- The (i)'s sentence.
	text: string,
	options: { string },
	default: string,
}

export type Listener = (id: string, value: string) -> ()

export type Store = {
	list: { Setting },
	values: { [string]: string },
	listeners: { Listener },
}

local Settings = {}

-- Everything wrong with a settings list, as sentences; empty when it is sound.
function Settings.problems(list: { Setting }): { string }
	local found: { string } = {}
	local seen: { [string]: boolean } = {}
	for index, setting in list do
		local name = if setting.id ~= "" then setting.id else `setting {index}`
		if setting.id == "" then
			table.insert(found, `{name} has no id`)
		elseif seen[setting.id] then
			table.insert(found, `{name} is listed twice`)
		end
		seen[setting.id] = true
		if setting.label == "" or setting.text == "" then
			table.insert(found, `{name} needs a label and a sentence`)
		end
		if #setting.options < 2 then
			table.insert(found, `{name} needs at least two options`)
		end
		local options: { [string]: boolean } = {}
		for _, option in setting.options do
			if options[option] then
				table.insert(found, `{name} lists {option} twice`)
			end
			options[option] = true
		end
		if not options[setting.default] then
			table.insert(found, `{name}'s default {setting.default} is not one of its options`)
		end
	end
	return found
end

-- A store with every setting at its default.
function Settings.new(list: { Setting }): Store
	local values: { [string]: string } = {}
	for _, setting in list do
		values[setting.id] = setting.default
	end
	return { list = list, values = values, listeners = {} }
end

local function find(store: Store, id: string): Setting?
	for _, setting in store.list do
		if setting.id == id then
			return setting
		end
	end
	return nil
end

-- The chosen option of setting `id`, or nil for an unknown setting.
function Settings.get(store: Store, id: string): string?
	return store.values[id]
end

-- Chooses `value` for setting `id`; false, and nothing changes, for an unknown setting or an
-- option it does not have. Listeners hear of a change only.
function Settings.set(store: Store, id: string, value: string): boolean
	local setting = find(store, id)
	if setting == nil or not table.find(setting.options, value) then
		return false
	end
	if store.values[id] ~= value then
		store.values[id] = value
		for _, listener in store.listeners do
			listener(id, value)
		end
	end
	return true
end

-- Calls `listener` on every change; returns the function that stops it.
function Settings.listen(store: Store, listener: Listener): () -> ()
	table.insert(store.listeners, listener)
	return function()
		local index = table.find(store.listeners, listener)
		if index then
			table.remove(store.listeners, index)
		end
	end
end

return table.freeze(Settings)
