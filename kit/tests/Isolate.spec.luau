--!strict
local Isolate = require("../src/Isolate")
local T = require("../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

describe("Isolate", function()
	it("runs a function to completion with its arguments", function()
		local seen = 0
		local outcome, problem = Isolate.run(function(a: number, b: number)
			seen = a + b
		end, 2, 3)
		expect(outcome).toBe("finished")
		expect(problem).toBe(nil)
		expect(seen).toBe(5)
	end)

	it("contains an error and reports it with a traceback, so the caller carries on", function()
		local outcome, problem = Isolate.run(function()
			error("boom")
		end)
		expect(outcome).toBe("failed")
		expect(string.find(problem or "", "boom", 1, true) ~= nil).toBe(true)
		expect(string.find(problem or "", "stack traceback", 1, true) ~= nil).toBe(true)
	end)

	it("returns at once when the function yields, leaving it to finish on its own", function()
		local resumed = false
		local outcome = Isolate.run(function()
			coroutine.yield()
			resumed = true
		end)
		expect(outcome).toBe("yielded")
		expect(resumed).toBe(false)
	end)

	it("keeps a sequence going past a step that fails or yields", function()
		local finished: { string } = {}
		local steps: { [string]: () -> () } = {
			a = function()
				table.insert(finished, "a")
			end,
			b = function()
				error("b broke")
			end,
			c = function()
				coroutine.yield()
			end,
			d = function()
				table.insert(finished, "d")
			end,
		}
		for _, name in { "a", "b", "c", "d" } do
			Isolate.run(steps[name])
		end
		expect(table.concat(finished, ",")).toBe("a,d")
	end)
end)
