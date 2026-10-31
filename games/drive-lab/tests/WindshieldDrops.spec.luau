--!strict
local T = require("../../../tools/test/T")
local WindshieldDrops = require("../src/shared/Rules/WindshieldDrops")

local describe, it, expect = T.describe, T.it, T.expect

local TUNING: WindshieldDrops.Tuning = {
	rate = 6,
	doubleAt = 60,
	maxRate = 30,
	exponent = 1.15,
	sliding = 0.3,
	cling = { 0.3, 1.5 },
	gravity = 0.05,
	airflow = 0.0003,
	maxSlide = 0.25,
	life = { 2, 5 },
	fadeOut = 0.3,
}

-- A windscreen 1.4 m wide at the bottom, 1.1 m at the top, 0.7 m down its slope, leaning back
-- 60 degrees from upright, in a frame with X right, Y up, Z toward the back of the car.
local LEAN = math.rad(60)
local function corner(x: number, down: number): WindshieldDrops.Vector
	return { x = x, y = 1.2 - down * math.cos(LEAN), z = -0.3 - down * math.sin(LEAN) }
end
local CORNERS = { corner(-0.55, 0), corner(0.55, 0), corner(0.7, 0.7), corner(-0.7, 0.7) }

describe("WindshieldDrops", function()
	it("flattens the windscreen onto its plane with the driver on the normal's side", function()
		local pane = WindshieldDrops.pane(CORNERS, { x = 0, y = 0, z = 1 })
		expect(pane.width).toBeNear(1.4, 1e-9)
		expect(pane.height).toBeNear(0.7, 1e-9)
		expect(pane.right.x).toBeNear(1, 1e-9)
		-- Down the glass is down and forward, away from the driver.
		expect(pane.down.y < 0 and pane.down.z < 0).toBe(true)
		expect(pane.normal.z > 0).toBe(true)
		-- The trapezoid in pane coordinates: top edge inset 0.15 m each side.
		expect(pane.polygon[1].x).toBeNear(0.15, 1e-9)
		expect(pane.polygon[1].y).toBeNear(0, 1e-9)
		expect(pane.polygon[3].x).toBeNear(1.4, 1e-9)
		expect(pane.polygon[3].y).toBeNear(0.7, 1e-9)
		-- The rectangle's centre is on the glass between the edges' midpoints.
		expect(pane.centre.x).toBeNear(0, 1e-9)
		expect(pane.centre.y).toBeNear(1.2 - 0.35 * math.cos(LEAN), 1e-9)
	end)

	it("takes each corner's pane coordinates back to the corner itself", function()
		local pane = WindshieldDrops.pane(CORNERS, { x = 0, y = 0, z = 1 })
		for index, corner in CORNERS do
			local at = pane.polygon[index]
			local point = WindshieldDrops.point(pane, at.x, at.y)
			expect(point.x).toBeNear(corner.x, 1e-9)
			expect(point.y).toBeNear(corner.y, 1e-9)
			expect(point.z).toBeNear(corner.z, 1e-9)
		end
	end)

	it("places a drop only where all of its sprite lies inside the slanted windscreen", function()
		local polygon = WindshieldDrops.pane(CORNERS, { x = 0, y = 0, z = 1 }).polygon
		expect(WindshieldDrops.inside(polygon, 0.7, 0.35, 0.05)).toBe(true)
		-- Inside the bounding rectangle but outside the slanted side near the top.
		expect(WindshieldDrops.inside(polygon, 0.05, 0.05, 0.01)).toBe(false)
		-- The centre inside, but the sprite crossing the slanted edge.
		expect(WindshieldDrops.inside(polygon, 0.2, 0.1, 0.01)).toBe(true)
		expect(WindshieldDrops.inside(polygon, 0.2, 0.1, 0.1)).toBe(false)
		-- Either winding order.
		local reversed = { polygon[4], polygon[3], polygon[2], polygon[1] }
		expect(WindshieldDrops.inside(reversed, 0.7, 0.35, 0.05)).toBe(true)
		expect(WindshieldDrops.inside(reversed, 0.05, 0.05, 0.01)).toBe(false)
	end)

	it("lands more drops in harder rain and at speed, none when dry or sheltered, within the cap", function()
		expect(WindshieldDrops.landing(0, 1, 100, TUNING)).toBe(0)
		expect(WindshieldDrops.landing(1, 0, 100, TUNING)).toBe(0)
		expect(WindshieldDrops.landing(1, 1, 0, TUNING)).toBeNear(6, 1e-9)
		expect(WindshieldDrops.landing(1, 1, 60, TUNING)).toBeNear(12, 1e-9)
		expect(WindshieldDrops.landing(1, 1, -60, TUNING)).toBeNear(12, 1e-9)
		expect(WindshieldDrops.landing(1, 1, 1e6, TUNING)).toBe(30)
		expect(WindshieldDrops.landing(0 / 0, 1, 0, TUNING)).toBe(0)
	end)

	it("lets a drop cling, then slide down when slow and up the glass when fast", function()
		expect(WindshieldDrops.pull(0, TUNING) > 0).toBe(true)
		expect(WindshieldDrops.pull(150, TUNING) < 0).toBe(true)
		local drop: WindshieldDrops.Drop =
			{ x = 0.5, y = 0.3, radius = 0.01, slides = true, cling = 0.5, speed = 0, age = 0, life = 10 }
		WindshieldDrops.step(drop, 0.4, WindshieldDrops.pull(0, TUNING), 0.7, TUNING)
		expect(drop.y).toBe(0.3)
		for _ = 1, 60 do
			WindshieldDrops.step(drop, 1 / 60, WindshieldDrops.pull(0, TUNING), 0.7, TUNING)
		end
		expect(drop.y > 0.3).toBe(true)
		local fast: WindshieldDrops.Drop =
			{ x = 0.5, y = 0.3, radius = 0.01, slides = true, cling = 0, speed = 0, age = 0, life = 10 }
		for _ = 1, 60 do
			WindshieldDrops.step(fast, 1 / 60, WindshieldDrops.pull(150, TUNING), 0.7, TUNING)
		end
		expect(fast.y < 0.3).toBe(true)
		expect(math.abs(fast.speed) <= TUNING.maxSlide).toBe(true)
		local bead: WindshieldDrops.Drop =
			{ x = 0.5, y = 0.3, radius = 0.01, slides = false, cling = 0, speed = 0, age = 0, life = 10 }
		WindshieldDrops.step(bead, 3, WindshieldDrops.pull(150, TUNING), 0.7, TUNING)
		expect(bead.y).toBe(0.3)
	end)

	it("fades a drop out over the end of its life and ends it there or off the glass", function()
		local drop: WindshieldDrops.Drop =
			{ x = 0.5, y = 0.3, radius = 0.01, slides = false, cling = 0, speed = 0, age = 0, life = 4 }
		expect(WindshieldDrops.opacity(drop, TUNING)).toBe(1)
		drop.age = 4 * 0.7 + 0.6
		expect(WindshieldDrops.opacity(drop, TUNING)).toBeNear(0.5, 1e-9)
		expect(WindshieldDrops.step(drop, 0.1, 0, 0.7, TUNING)).toBe(true)
		expect(WindshieldDrops.step(drop, 1, 0, 0.7, TUNING)).toBe(false)
		local leaving: WindshieldDrops.Drop =
			{ x = 0.5, y = 0.71, radius = 0.005, slides = true, cling = 0, speed = 0.2, age = 0, life = 4 }
		expect(WindshieldDrops.step(leaving, 0.1, 0.05, 0.7, TUNING)).toBe(false)
	end)
end)
