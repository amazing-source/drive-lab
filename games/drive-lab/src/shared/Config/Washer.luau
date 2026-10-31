--!strict
--[[
	The washer's fluid (Atmosphere/Windshield, Effects/WasherJets): the drops its jets throw on the
	windscreen, seen from the cockpit, and the jets themselves seen from outside. Plain numbers and
	{ r, g, b } colours so Lune can load it. Art seeds, not measurements: no source gives a 458's
	jets, so they aim where road cars' do, at the screen's middle on either side.
]]
export type Rgb = { r: number, g: number, b: number }

export type Glass = {
	-- Where each jet lands: its centre as shares of the pane's width and height (from the
	-- top left as the driver sees it), and its spread (metres).
	zones: { { x: number, y: number, radius: number } },
	-- Drops landing per second across the jets while the washer runs, and the most on the glass.
	rate: number,
	pool: number,
	-- A drop's width (metres, smallest and largest), its opacity at most, and its life (seconds)
	-- if no wipe clears it first.
	width: { number },
	opacity: number,
	life: { number },
}

export type Jets = {
	texture: string,
	color: Rgb,
	-- Particles a second per jet, their speed (studs a second), size (studs) and life (seconds).
	rate: number,
	speed: number,
	size: { number },
	lifetime: { number },
	transparency: { number },
	-- Degrees the jet fans out.
	spread: number,
}

export type Washer = { GLASS: Glass, JETS: Jets }

local Washer: Washer = table.freeze({
	GLASS = table.freeze({
		zones = table.freeze({
			table.freeze({ x = 0.36, y = 0.55, radius = 0.12 }),
			table.freeze({ x = 0.64, y = 0.55, radius = 0.12 }),
		}),
		rate = 60,
		pool = 40,
		width = table.freeze({ 0.008, 0.016 }),
		opacity = 0.35,
		life = table.freeze({ 6, 10 }),
	}),
	JETS = table.freeze({
		-- The rain pack's tyre-spray puff (Config/CarWater SPRAY), drawn small and fast.
		texture = "rbxassetid://120423533825678",
		color = table.freeze({ r = 200, g = 225, b = 255 }),
		rate = 120,
		speed = 14,
		size = table.freeze({ 0.03, 0.06 }),
		lifetime = table.freeze({ 0.12, 0.2 }),
		transparency = table.freeze({ 0.3, 0.8 }),
		spread = 4,
	}),
})

return Washer
