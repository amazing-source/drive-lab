--!strict
--[[
	The camera optics rain brings, kept light so the car stays sharp (the brief: a global blur
	blurs the car too). A brief blur of at most a third of a pixel when drops hit the lens,
	fading in a fraction of a second, and a very light far depth of field in the rain: a broad
	sharp range, focused on the car in the chase view. Neither in the cockpit, which looks
	through the windscreen rather than a lens. The same depth of field carries the speed's near
	blur in the chase view (Rules/MotionBlur).
]]
export type View = "OnFoot" | "Chase" | "Hood" | "Cockpit"

export type Blur = {
	-- The most the contact blur may reach (pixels), what one landing drop adds, and its
	-- half-life (s).
	max: number,
	perDrop: number,
	halfLife: number,
}

export type Focus = {
	-- Far blur intensity in full rain.
	far: number,
	-- Studs kept sharp either side of the focus, at least.
	radius: number,
	-- Focus distance (studs) in the views without a car to focus on.
	hood: number,
	onFoot: number,
	-- Studs kept sharp beyond the car's own half-length in the chase view; `nearMargin` while
	-- the speed blurs the road before the car, so the blur reaches close to its tail.
	margin: number,
	nearMargin: number,
}

export type DepthOfField = { enabled: boolean, distance: number, radius: number, far: number, near: number }

local RainOptics = {}

local function unit(value: number): number
	if value ~= value then
		return 0
	end
	return math.clamp(value, 0, 1)
end

-- The contact blur after `drops` new drops land on the lens.
function RainOptics.contact(pulse: number, drops: number, blur: Blur): number
	local added = if drops ~= drops or drops < 0 then 0 else drops * blur.perDrop
	return math.clamp((if pulse ~= pulse then 0 else pulse) + added, 0, blur.max)
end

-- The contact blur after dt seconds of fading.
function RainOptics.decay(pulse: number, dt: number, blur: Blur): number
	if pulse ~= pulse or dt ~= dt or dt <= 0 then
		return if pulse ~= pulse then 0 else pulse
	end
	return pulse * 0.5 ^ (dt / blur.halfLife)
end

-- The BlurEffect size to show: none in the cockpit, never past the cap.
function RainOptics.blurSize(view: View, pulse: number, blur: Blur): number
	if view == "Cockpit" or pulse ~= pulse then
		return 0
	end
	return math.clamp(pulse, 0, blur.max)
end

-- The one depth of field for a view: the rain's light far blur, and the speed's near blur
-- (`near`, from Rules/MotionBlur), which only the chase view takes: it blurs the road between
-- the camera and the car, so the sharp range then hugs the car. carDistance is the camera's
-- distance to the car's centre and carLength its length (studs); both matter only in the
-- chase view.
function RainOptics.depthOfField(
	view: View,
	intensity: number,
	near: number,
	carDistance: number?,
	carLength: number,
	focus: Focus
): DepthOfField
	local far = focus.far * unit(intensity)
	local chase = view == "Chase" and carDistance ~= nil and carDistance == carDistance
	local speed = if chase then unit(near) else 0
	if view == "Cockpit" or (far <= 0 and speed <= 0) then
		return { enabled = false, distance = 0, radius = 0, far = 0, near = 0 }
	end
	if chase then
		local radius = if speed > 0
			then carLength / 2 + focus.nearMargin
			else math.max(focus.radius, carLength / 2 + focus.margin)
		return {
			enabled = true,
			distance = math.max(carDistance :: number, 0),
			radius = radius,
			far = far,
			near = speed,
		}
	end
	local distance = if view == "Hood" then focus.hood else focus.onFoot
	return { enabled = true, distance = distance, radius = focus.radius, far = far, near = 0 }
end

return table.freeze(RainOptics)
