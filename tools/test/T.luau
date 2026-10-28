--!strict
--[[
	A minimal test harness for Lune. Specs call describe/it/expect; run.luau requires every
	spec, prints failures and exits non-zero if any test failed, so CI can gate on it.
]]

type Expectation = {
	toBe: (expected: unknown) -> (),
	toBeNear: (expected: number, tolerance: number) -> (),
	toBeTruthy: () -> (),
	toThrow: () -> (),
}

local results = { passed = 0, failed = 0, failures = {} :: { string } }
local suite = ""

local T = {}

function T.describe(name: string, body: () -> ())
	local previous = suite
	suite = if previous == "" then name else `{previous} > {name}`
	body()
	suite = previous
end

function T.it(name: string, body: () -> ())
	local ok, err = pcall(body)
	if ok then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, `{suite} > {name}: {err}`)
	end
end

function T.expect(actual: unknown): Expectation
	return {
		toBe = function(expected: unknown)
			if actual ~= expected then
				error(`expected {expected}, got {actual}`, 2)
			end
		end,
		toBeNear = function(expected: number, tolerance: number)
			if typeof(actual) ~= "number" or math.abs(actual - expected) > tolerance then
				error(`expected {expected} within {tolerance}, got {actual}`, 2)
			end
		end,
		toBeTruthy = function()
			if not actual then
				error(`expected a truthy value, got {actual}`, 2)
			end
		end,
		toThrow = function()
			if typeof(actual) ~= "function" then
				error("toThrow needs a function", 2)
			end
			local ok = pcall(actual :: () -> ())
			if ok then
				error("expected the function to throw", 2)
			end
		end,
	}
end

function T.results(): typeof(results)
	return results
end

return T
