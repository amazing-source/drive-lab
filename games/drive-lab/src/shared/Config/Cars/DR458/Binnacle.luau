--!strict
--[[
	The DR458's binnacle display (Config/Binnacle), from docs/research/12_dr458_challenge_evo.md
	§2.4 and §3.1, drawn from the owner's design pack (BinnacleLayout, docs/pipelines/BINNACLE.md).
	The three pages and their labels are the ones photographed on a 458 Challenge Evo (documented);
	every value Drive Lab does not simulate shows "--". The shift lights' layout is documented
	(1 + 6 + 1); their colours and thresholds are not, so these are estimates. The end lamps' jobs
	follow the 488 Challenge (unknown for the 458).
]]
local Binnacle = require("../../Binnacle")
local Cluster = require("../../Cluster")
local Layout = require("./BinnacleLayout")

local function rgb(r: number, g: number, b: number)
	return table.freeze({ r = r, g = g, b = b })
end

local function field(
	label: string,
	reading: Binnacle.Reading,
	text: string?,
	pill: { [string]: Cluster.Rgb }?
): Binnacle.Field
	return table.freeze({ label = label, reading = reading, text = text, pill = pill })
end

local pills = assert(Layout.pages.driving.pills, "the driving page has its pills")
local RED_PILL, WHITE_PILL = pills.TCS.rgb, pills.POS.rgb

local Screen: Binnacle.Screen = table.freeze({
	-- EST: Binnacle_Screen's shape on the DR458 model.
	canvasWidth = 1083,
	canvasHeight = 425,
	brightness = 1.6,
	background = rgb(6, 7, 8),
	font = table.freeze({
		family = "rbxasset://fonts/families/Michroma.json",
		weight = "Regular" :: "Regular",
		capHeight = 0.7,
		capOffset = 0,
	}),
	valueRgb = Layout.valueRgb,
	pillTextRgb = Layout.pillTextRgb,
	-- Documented (photo `011`): an rpm band marked 2 to 9 x 1,000 rpm.
	barFromRpm = 2000,
	barToRpm = 9000,
	barMarks = table.freeze({ 2, 3, 4, 5, 6, 7, 8, 9 }),
	-- Likely, §1.1: the power peak, called the redline.
	redlineRpm = 9000,
	pages = table.freeze({
		table.freeze({
			-- Photo `011`. What POS and the blue R box mean is unknown: shown as photographed.
			title = "",
			art = Layout.pages.driving,
			fields = table.freeze({
				field("GEAR", "gear"),
				field("SPEED", "speed"),
				field("TCS", "tcs", nil, table.freeze({ OFF = RED_PILL, ON = WHITE_PILL })),
				field("POS", "static", "OFF", table.freeze({ OFF = WHITE_PILL })),
				field("OIL P", "none"),
				field("P FUEL", "none"),
				field("WATER T", "none"),
				field("OIL T", "none"),
			}),
		}),
		table.freeze({
			-- Photo `004`. The fault flags show "--": Drive Lab has no faults.
			title = "CHASSIS - BODY",
			art = Layout.pages.chassis,
			fields = table.freeze({
				field("ABS FAIL", "none"),
				field("TCS FAIL", "none"),
				field("EDIFF FAIL", "none"),
				field("BRAKE FAIL", "none"),
				field("FRONT DISK", "none"),
				field("REAR DISK", "none"),
				field("BRAKE OIL", "none"),
				field("PAD WEAR", "none"),
				field("ODOMETER", "none"),
				field("MANETTINO", "manettino"),
				field("DDU FIRMWARE", "static", "DDU3_v35F458_09"),
			}),
		}),
		table.freeze({
			-- Photo `012`. Whether ANGLE is the steering angle is unknown.
			title = "MECHANIC",
			art = Layout.pages.mechanic,
			fields = table.freeze({
				field("RPM", "rpm"),
				field("FUEL %", "none"),
				field("CHECK", "none"),
				field("V_BATT", "none"),
				field("T_WATER", "none"),
				field("ANGLE", "none"),
				field("TOIL ENGINE", "none"),
				field("P_OIL", "none"),
				field("P CARTER", "none"),
				field("TOIL GEAR", "none"),
				field("P_FUEL", "none"),
			}),
		}),
	}),
	-- Unknown for the 458: the 488 Challenge's strip has a blue fault light on the left and a white
	-- pit-limiter light on the right, both steady.
	leftLamp = table.freeze({ rgb = rgb(40, 110, 255), shows = "fault" :: "fault" }),
	rightLamp = table.freeze({ rgb = rgb(245, 245, 245), shows = "pitLimiter" :: "pitLimiter" }),
	-- EST: "quickly from green to red" (§3.1, likely); thresholds and colours are not published.
	revLights = table.freeze({
		fromRpm = 6500,
		toRpm = 8750,
		colours = table.freeze({
			rgb(40, 220, 60),
			rgb(40, 220, 60),
			rgb(255, 200, 30),
			rgb(255, 200, 30),
			rgb(235, 30, 30),
			rgb(235, 30, 30),
		}),
		flashRpm = 9000,
		flashHz = 8,
	}),
	lenses = table.freeze({
		"ShiftLight_1",
		"ShiftLight_2",
		"ShiftLight_3",
		"ShiftLight_4",
		"ShiftLight_5",
		"ShiftLight_6",
		"ShiftLight_7",
		"ShiftLight_8",
	}),
	lensFace = "Back" :: "Back",
	lamps = Layout.lamps,
})

return Screen
