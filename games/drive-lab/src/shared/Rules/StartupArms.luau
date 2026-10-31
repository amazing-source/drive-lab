--!strict
--[[
	Where the driver's hands are while the car starts: the wrist's frame along a path keyed in
	Blender against the console, the START flap and the wheel (tools/blender/startup_paths.py),
	and which posed hand mesh shows. Keys are in the driver's seat frame (x right, y up, z back,
	studs); a frame's z axis runs from the wrist up the forearm and its y axis out of the back of
	the hand. Plain numbers, so Lune can test it.
]]
local Config = require("../Config/DriverStartup")

export type Vector = { x: number, y: number, z: number }
-- A unit quaternion.
export type Rotation = { w: number, x: number, y: number, z: number }
export type Pose = { position: Vector, rotation: Rotation }
export type Hand = {
	pose: Pose,
	shape: Config.Shape,
	-- 0 to 1: how far the pose has been bent toward the hand's live grip on the wheel.
	toGrip: number,
}

local StartupArms = {}

local function vector(key: Config.Key): Vector
	return { x = key[2], y = key[3], z = key[4] }
end

local function rotation(key: Config.Key): Rotation
	return { w = key[5], x = key[6], y = key[7], z = key[8] }
end

local function normalise(q: Rotation): Rotation
	local length = math.sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z)
	return { w = q.w / length, x = q.x / length, y = q.y / length, z = q.z / length }
end

function StartupArms.multiply(a: Rotation, b: Rotation): Rotation
	return {
		w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
		x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
		y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
		z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
	}
end

local function inverse(q: Rotation): Rotation
	return { w = q.w, x = -q.x, y = -q.y, z = -q.z }
end

-- The shorter way round, so a hand never spins the long way between two keys.
function StartupArms.slerp(a: Rotation, b: Rotation, share: number): Rotation
	local dot = a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z
	local sign = if dot < 0 then -1 else 1
	dot *= sign
	if dot > 0.9995 then
		return normalise({
			w = a.w + (sign * b.w - a.w) * share,
			x = a.x + (sign * b.x - a.x) * share,
			y = a.y + (sign * b.y - a.y) * share,
			z = a.z + (sign * b.z - a.z) * share,
		})
	end
	local angle = math.acos(dot)
	local from = math.sin((1 - share) * angle) / math.sin(angle)
	local to = sign * math.sin(share * angle) / math.sin(angle)
	return {
		w = a.w * from + b.w * to,
		x = a.x * from + b.x * to,
		y = a.y * from + b.y * to,
		z = a.z * from + b.z * to,
	}
end

-- Velocity at a key for a cubic through it: the slope from its neighbours, one-sided at the ends.
local function slope(keys: { Config.Key }, index: number, axis: number): number
	local before = keys[math.max(index - 1, 1)]
	local after = keys[math.min(index + 1, #keys)]
	local span = after[1] - before[1]
	return if span > 0 then (after[axis] - before[axis]) / span else 0
end

-- The pose `t` seconds along the keys: positions on a cubic through every key (Catmull-Rom
-- slopes, so the speed carries through each key), rotations turning at an even rate between
-- keys. Held at the first and last key outside them.
function StartupArms.sample(keys: { Config.Key }, t: number): Pose
	local first, last = keys[1], keys[#keys]
	if t <= first[1] then
		return { position = vector(first), rotation = rotation(first) }
	elseif t >= last[1] then
		return { position = vector(last), rotation = rotation(last) }
	end
	local index = 1
	while keys[index + 1][1] <= t do
		index += 1
	end
	local a, b = keys[index], keys[index + 1]
	local span = b[1] - a[1]
	local s = (t - a[1]) / span
	local s2, s3 = s * s, s * s * s
	local h00, h10 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s
	local h01, h11 = -2 * s3 + 3 * s2, s3 - s2
	local axes = table.create(3)
	for axis = 2, 4 do
		axes[axis - 1] = h00 * a[axis]
			+ h10 * span * slope(keys, index, axis)
			+ h01 * b[axis]
			+ h11 * span * slope(keys, index + 1, axis)
	end
	return {
		position = { x = axes[1], y = axes[2], z = axes[3] },
		rotation = StartupArms.slerp(rotation(a), rotation(b), s),
	}
end

-- Moves `pose` by `share` of the change that carries `from` onto `to`: the path keeps its shape
-- and ends on the live grip even if the wheel's rest position has moved since the keys were made.
function StartupArms.retarget(pose: Pose, from: Pose, to: Pose, share: number): Pose
	local turn = StartupArms.slerp(
		{ w = 1, x = 0, y = 0, z = 0 },
		StartupArms.multiply(to.rotation, inverse(from.rotation)),
		share
	)
	return {
		position = {
			x = pose.position.x + (to.position.x - from.position.x) * share,
			y = pose.position.y + (to.position.y - from.position.y) * share,
			z = pose.position.z + (to.position.z - from.position.z) * share,
		},
		rotation = StartupArms.multiply(turn, pose.rotation),
	}
end

function StartupArms.shape(track: Config.Track, t: number): Config.Shape
	local shape: Config.Shape = track.shapes[1].shape
	for _, change in track.shapes do
		if t >= change.at then
			shape = change.shape
		end
	end
	return shape
end

-- The hand `sinceKey` seconds after the start key (nil: the engine is off, the hand rests), or
-- nil once it holds the wheel and the steering grip takes over.
function StartupArms.hand(track: Config.Track, sinceKey: number?): Hand?
	local keys = track.keys
	if sinceKey == nil then
		return { pose = StartupArms.sample(keys, keys[1][1]), shape = track.shapes[1].shape, toGrip = 0 }
	end
	local finish = keys[#keys][1]
	if sinceKey >= finish then
		return nil
	end
	local share = math.clamp((sinceKey - track.gripFrom) / (finish - track.gripFrom), 0, 1)
	return {
		pose = StartupArms.sample(keys, sinceKey),
		shape = StartupArms.shape(track, sinceKey),
		toGrip = share * share * (3 - 2 * share),
	}
end

-- A point given in the wrist's frame (such as the index's tip), in the seat frame.
function StartupArms.apply(pose: Pose, offset: Vector): Vector
	local q, p = pose.rotation, pose.position
	-- v + 2w(u x v) + 2u x (u x v), u the quaternion's vector part.
	local ux, uy, uz = q.x, q.y, q.z
	local cx = uy * offset.z - uz * offset.y
	local cy = uz * offset.x - ux * offset.z
	local cz = ux * offset.y - uy * offset.x
	return {
		x = p.x + offset.x + 2 * (q.w * cx + uy * cz - uz * cy),
		y = p.y + offset.y + 2 * (q.w * cy + uz * cx - ux * cz),
		z = p.z + offset.z + 2 * (q.w * cz + ux * cy - uy * cx),
	}
end

-- Between two poses, eased: `share` 0 is `from`, 1 is `to`; the position runs straight and the
-- rotation turns the shorter way. The drawn hands' blend at the hand-over with the body's arms.
function StartupArms.settle(from: Pose, to: Pose, share: number): Pose
	local u = math.clamp(share, 0, 1)
	u = u * u * (3 - 2 * u)
	local a, b = from.position, to.position
	return {
		position = { x = a.x + (b.x - a.x) * u, y = a.y + (b.y - a.y) * u, z = a.z + (b.z - a.z) * u },
		rotation = StartupArms.slerp(from.rotation, to.rotation, u),
	}
end

-- The track's last key: where the keys put the hand on the wheel.
function StartupArms.finalPose(track: Config.Track): Pose
	local last = track.keys[#track.keys]
	return { position = vector(last), rotation = rotation(last) }
end

return table.freeze(StartupArms)
