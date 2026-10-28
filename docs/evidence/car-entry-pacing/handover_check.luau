-- Edit-mode check for #40 (run with this branch synced): the body's hand-overs at both ends of
-- the sequences, the instant scale change, and what shows at the exit's end when the clip stops.
-- Rigs a copy of the car (offset, anchored), uses R6 dummies, destroys everything.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local CarRig = require(RS.Shared.Car.CarRig)
local Catalog = require(RS.Shared.Config.Cars.Catalog)
local Config = require(RS.Shared.Config.CarEntry)
local DoorMark = require(RS.Shared.Car.DoorMark)
local Driving = require(RS.Shared.Config.Driving)
local Movement = require(RS.Shared.Config.Movement)

local S = Driving.DRIVER_SCALE
local PARTS = { "Torso", "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg" }
local made = {}
local res = { hand_overs = {}, scale = {}, exit_end_tracks = {} }

local function corners(part: BasePart): { Vector3 }
	local out, h = {}, part.Size / 2
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(out, part.CFrame:PointToWorldSpace(Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)))
			end
		end
	end
	return out
end

local function snapshot(d: Model): { [string]: { Vector3 } }
	local out = {}
	for _, name in PARTS do
		out[name] = corners(d:FindFirstChild(name) :: BasePart)
	end
	return out
end

local function largest(a, b): (number, string)
	local worst, at = 0, ""
	for name, list in a do
		for i, p in list do
			local e = (p - b[name][i]).Magnitude
			if e > worst then
				worst, at = e, name
			end
		end
	end
	return worst, at
end

local function dummy(scale: number): (Model, Humanoid, Animator, BasePart)
	local d = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	d.Archivable = false
	d.Name = "_PacingCheckDummy"
	d.Parent = workspace
	table.insert(made, d)
	d:ScaleTo(scale)
	local h = d:FindFirstChildOfClass("Humanoid") :: Humanoid
	local animator = h:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = h
	return d, h, animator :: Animator, d:FindFirstChild("HumanoidRootPart") :: BasePart
end

local function placeRoot(d: Model, root: BasePart, frame: CFrame)
	d:PivotTo(frame * root.CFrame:ToObjectSpace(d:GetPivot()))
end

local function track(animator: Animator, id: string, priority: Enum.AnimationPriority): AnimationTrack
	local a = Instance.new("Animation")
	a.AnimationId = id
	local t = animator:LoadAnimation(a)
	t.Priority = priority
	local waited = 0
	while t.Length == 0 and waited < 10 do
		task.wait(0.1)
		waited += 0.1
	end
	return t
end

local function pose(animator: Animator, t: AnimationTrack, at: number)
	t:Play(0)
	t:AdjustSpeed(0)
	t.TimePosition = at
	animator:StepAnimations(0)
	task.wait()
	animator:StepAnimations(0)
end

local ok, err = pcall(function()
	local copy = workspace.CarImport:Clone()
	for _, tag in copy:GetTags() do
		copy:RemoveTag(tag)
	end
	copy.Name = "_PacingCheckCar"
	copy.Archivable = false
	copy.Parent = workspace
	table.insert(made, copy)
	copy:PivotTo(workspace.CarImport:GetPivot() + Vector3.new(100, 0, 0))
	local entry = Catalog[copy:GetAttribute("Car")]
	local rig = CarRig.build(copy, entry.physics, entry.model)
	for _, p in copy:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
		end
	end
	local seat = rig.seat
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { copy }
	-- The ground, read before any dummy exists (a ray from the mark would hit a body posed there).
	local mark, exitSpot = DoorMark.frame(seat), DoorMark.exitFrame(seat)
	local function groundAt(spot: CFrame): number
		local hit = workspace:Raycast(spot.Position + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), params)
		return hit and hit.Position.Y or 0
	end
	local grounds = { mark = groundAt(mark), exit = groundAt(exitSpot) }
	res.grounds = grounds
	local function standing(spot: CFrame, ground: number, scale: number): CFrame
		return spot.Rotation + Vector3.new(spot.Position.X, ground + 3 * scale, spot.Position.Z)
	end
	local function seated(): (Model, Humanoid, Animator)
		for _, w in seat:GetChildren() do
			if w:IsA("Weld") and w.Name == "SeatWeld" then
				w:Destroy()
			end
		end
		local d, h, animator = dummy(S)
		d:PivotTo(seat.CFrame + Vector3.new(0, 4, 0))
		seat:Sit(h)
		local waited = 0
		while h.SeatPart ~= seat and waited < 2 do
			task.wait(0.05)
			waited += 0.05
		end
		return d, h, animator
	end
	local function rest(spot: CFrame, ground: number, scale: number): (Model, { [string]: { Vector3 } })
		local d, _, _, root = dummy(scale)
		for _, p in d:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = true
			end
		end
		placeRoot(d, root, standing(spot, ground, scale))
		return d, snapshot(d)
	end

	-- Hand-overs: the clip's frame where the root changes hands against the body standing at
	-- rest where the client (entry) or the server (exit) puts the root.
	local cases = {
		{ name = "entry start, door shut: OutsideOpen t=0 vs standing on the mark", clip = "OutsideOpen", at = 0, spot = mark, ground = grounds.mark },
		{ name = "entry start, door open: GetIn t=0 vs standing on the mark", clip = "GetIn", at = 0, spot = mark, ground = grounds.mark },
		{ name = "exit end BEFORE: OutsideClose last frame vs standing on the mark", clip = "OutsideClose", at = Config.CLIPS.OutsideClose.duration - 1 / 60, spot = mark, ground = grounds.mark },
		{ name = "exit end AFTER: OutsideClose EXIT_END.at vs standing at EXIT_END", clip = "OutsideClose", at = Config.EXIT_END.at, spot = exitSpot, ground = grounds.exit },
	}
	for _, case in cases do
		local d, h, animator = seated()
		local t = track(animator, Config.CLIPS[case.clip].seated, Enum.AnimationPriority.Action)
		pose(animator, t, case.at)
		local clipPose = snapshot(d)
		local standingBody, standingPose = rest(case.spot, case.ground, S)
		local worst, part = largest(clipPose, standingPose)
		table.insert(res.hand_overs, { case = case.name, seated = h.SeatPart == seat, largestCornerGap = worst, part = part })
		t:Stop(0)
		d:Destroy()
		standingBody:Destroy()
	end

	-- The exit's end as the server and the client make it: the clip held at EXIT_END.at with
	-- Locomotion's sit under it; the server unseats and puts the root at EXIT_END; the client stops
	-- the clip with no fade; Locomotion then fades sit out and idle in. The control run has sit
	-- already stopped when the clip stops. Driver scale throughout, to isolate the pose.
	for _, sitFirst in { false, true } do
		local d, h, animator = seated()
		local root = d:FindFirstChild("HumanoidRootPart") :: BasePart
		local sit = track(animator, Movement.ANIMATIONS.sit.id, Movement.ANIMATIONS.sit.priority)
		local idle = track(animator, Movement.ANIMATIONS.idle.id, Movement.ANIMATIONS.idle.priority)
		sit.Looped = true
		sit:Play(0)
		local clip = track(animator, Config.CLIPS.OutsideClose.seated, Enum.AnimationPriority.Action)
		pose(animator, clip, Config.EXIT_END.at)
		local held = snapshot(d)
		for _, w in seat:GetChildren() do
			if w:IsA("Weld") and w.Name == "SeatWeld" then
				w:Destroy()
			end
		end
		h.Sit = false
		root.Anchored = true
		placeRoot(d, root, standing(exitSpot, grounds.exit, S))
		if sitFirst then
			sit:Stop(0)
		end
		clip:Stop(0)
		animator:StepAnimations(1 / 60)
		local gap1, part1 = largest(snapshot(d), held)
		local label = if sitFirst then "control: sit stopped first" else "as built"
		table.insert(res.exit_end_tracks, { run = label, frame = "first frame after the clip stops", largestCornerGap = gap1, part = part1 })
		sit:Stop(Movement.FADE)
		idle:Play(Movement.FADE)
		for step = 1, 12 do
			animator:StepAnimations(1 / 60)
			if step % 3 == 0 then
				local gap, part = largest(snapshot(d), held)
				table.insert(res.exit_end_tracks, { run = label, frame = `+{step}/60 s`, largestCornerGap = gap, part = part, sitWeight = sit.WeightCurrent, idleWeight = idle.WeightCurrent })
			end
		end
		d:Destroy()
	end

	-- The instant scale change with the feet kept (the server's setScale) on a body on the mark.
	for _, pair in { { 1, S }, { S, 1 } } do
		local from, to = pair[1], pair[2]
		local d, _, _, root = dummy(from)
		for _, p in d:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = true
			end
		end
		placeRoot(d, root, standing(mark, grounds.mark, from))
		local function feet(): number
			local lowest = math.huge
			for _, name in { "Right Leg", "Left Leg" } do
				for _, p in corners(d:FindFirstChild(name) :: BasePart) do
					lowest = math.min(lowest, p.Y)
				end
			end
			return lowest
		end
		local before, rootBefore = feet(), root.Position
		local footing = root.Position.Y - 3 * d:GetScale()
		d:ScaleTo(to)
		local afterScaleTo = feet()
		placeRoot(d, root, root.CFrame + Vector3.new(0, footing + 3 * to - root.Position.Y, 0))
		table.insert(res.scale, {
			from = from,
			to = to,
			feetBefore = before,
			feetAfterScaleToAlone = afterScaleTo,
			feetAfterSetScale = feet(),
			rootMovedAcross = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(rootBefore.X, 0, rootBefore.Z)).Magnitude,
		})
		d:Destroy()
	end
end)
for _, x in made do
	if x.Parent then
		x:Destroy()
	end
end
for _, w in workspace.CarImport:GetDescendants() do
	if w.Name == "SeatWeld" then
		res.strayWeld = true
	end
end
local left = 0
for _, c in workspace:GetChildren() do
	if string.sub(c.Name, 1, 12) == "_PacingCheck" then
		left += 1
	end
end
res.ok, res.err, res.leftover = ok, if ok then nil else tostring(err), left
return HttpService:JSONEncode(res)
