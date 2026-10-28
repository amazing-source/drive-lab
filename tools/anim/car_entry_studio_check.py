"""
Writes the edit-mode Studio check for the uploaded car-entry clips: a Luau snippet (run with the
MCP execute_luau tool, never in a playtest) that rigs a copy of workspace.CarImport, seats an R6
dummy at Driving.DRIVER_SCALE (or stands it at the door mark for a standing clip), plays each clip
with Animator:StepAnimations to chosen times, and compares every part's CFrame in the seat's frame
with Blender's (<Clip>.seatparts.json from car_entry_export.py). Everything it makes is destroyed.

  python car_entry_studio_check.py <export_dir> <ids.json> <out.luau> [--times 0,0.5,1,...]

ids.json: {"<Clip>": {"seated": "rbxassetid://...", "standing": "..."}, ...}
"""
import argparse
import json
import os
import sys

LUAU = r"""
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local CarRig = require(RS.Shared.Car.CarRig)
local Catalog = require(RS.Shared.Config.Cars.Catalog)
local Driving = require(RS.Shared.Config.Driving)
local Units = require(RS.Shared.Units)

local CASES = HttpService:JSONDecode([==[__CASES__]==])
local made = {}
local results = {}

local function dummy(scale)
	local d = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	d.Archivable = false
	d.Name = "_EntryCheckDummy"
	d.Parent = workspace
	table.insert(made, d)
	d:ScaleTo(scale)
	local h = d:FindFirstChildOfClass("Humanoid")
	if h:FindFirstChildOfClass("Animator") == nil then
		Instance.new("Animator").Parent = h
	end
	return d, h, h:FindFirstChildOfClass("Animator")
end

local ok, err = pcall(function()
	local copy = workspace.CarImport:Clone()
	for _, tag in copy:GetTags() do
		copy:RemoveTag(tag)
	end
	copy.Name = "_EntryCheckCar"
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
	for _, case in CASES do
		local d, h, animator = dummy(Driving.DRIVER_SCALE)
		local root = d:FindFirstChild("HumanoidRootPart") :: BasePart
		if case.variant == "seated" then
			d:PivotTo(seat.CFrame + Vector3.new(0, 4, 0))
			seat:Sit(h)
			task.wait(0.2)
		else
			-- Standing at the mark, on the ground, as DoorMark.frame and the server's standingFrame
			-- put it, from the clip's own MARK (the place may hold an older one).
			local offset = Vector3.new(Units.metresToStuds(case.mark[1]), 0, -Units.metresToStuds(case.mark[2]))
			local at = seat.CFrame:PointToWorldSpace(offset)
			local toward = seat.Position - at
			local mark = CFrame.lookAt(at, at + Vector3.new(toward.X, 0, toward.Z))
			local ground = seat.Position.Y + case.groundInSeat
			root.Anchored = true
			d:PivotTo(mark.Rotation + Vector3.new(mark.Position.X, ground + 3 * Driving.DRIVER_SCALE, mark.Position.Z))
		end
		local animation = Instance.new("Animation")
		animation.AnimationId = case.id
		local track = animator:LoadAnimation(animation)
		local waited = 0
		while track.Length == 0 and waited < 10 do
			task.wait(0.1)
			waited += 0.1
		end
		track:Play(0)
		track:AdjustSpeed(0)
		local worst, sum, n = 0, 0, 0
		local rows = {}
		for _, sample in case.samples do
			track.TimePosition = sample.time
			animator:StepAnimations(0)
			task.wait()
			animator:StepAnimations(0)
			local frameWorst = 0
			for name, values in sample.parts do
				local part = d:FindFirstChild(name)
				if part and name ~= "HumanoidRootPart" then
					local got = seat.CFrame:PointToObjectSpace(part.Position)
					local want = Vector3.new(values[1], values[2], values[3])
					local e = (got - want).Magnitude
					frameWorst = math.max(frameWorst, e)
					sum += e
					n += 1
				end
			end
			worst = math.max(worst, frameWorst)
			table.insert(rows, string.format("%.2f:%.4f", sample.time, frameWorst))
		end
		track:Stop(0)
		table.insert(results, {
			clip = case.clip,
			variant = case.variant,
			length = track.Length,
			worst = worst,
			mean = if n > 0 then sum / n else 0,
			rows = table.concat(rows, " "),
		})
		d:Destroy()
	end
end)
for _, x in made do
	if x.Parent then
		x:Destroy()
	end
end
local left = 0
for _, c in workspace:GetChildren() do
	if string.sub(c.Name, 1, 11) == "_EntryCheck" then
		left += 1
	end
end
return HttpService:JSONEncode({ ok = ok, err = if ok then nil else tostring(err), results = results, leftover = left })
"""


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("export_dir")
    parser.add_argument("ids")
    parser.add_argument("out")
    parser.add_argument("--times", default="0,0.25,0.5,0.75,1.0")
    parser.add_argument("--ground", type=float, required=True, help="ground y in the seat frame")
    parser.add_argument("--mark", required=True, help="Config.MARK right,forward (metres)")
    args = parser.parse_args(argv)
    ids = json.load(open(args.ids, encoding="utf-8"))
    fractions = [float(v) for v in args.times.split(",")]
    cases = []
    for clip, variants in ids.items():
        if clip.startswith("_"):
            continue  # car_entry_upload.py's record of the bake each clip came from
        found = [os.path.join(root, f"{clip}.seatparts.json") for root, _, files in os.walk(args.export_dir) if f"{clip}.seatparts.json" in files]
        if not found:
            continue
        data = json.load(open(found[0], encoding="utf-8"))
        frames = data["frames"]
        duration = frames[-1]["time"]
        picks = sorted({min(len(frames) - 1, round(f * (len(frames) - 1))) for f in fractions})
        for variant, asset in variants.items():
            samples = []
            for k in picks:
                t = frames[k]["time"]
                # The last frame is held a frame early (ClipPlayer): sample just inside the end.
                t = min(t, duration - 1 / 60)
                parts = {name: v[0:3] for name, v in frames[k]["parts"].items()}
                samples.append({"time": round(t, 4), "parts": parts})
            mark = [float(v) for v in args.mark.split(",")]
            cases.append(
                {"clip": clip, "variant": variant, "id": asset, "samples": samples, "groundInSeat": args.ground, "mark": mark}
            )
    with open(args.out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(LUAU.replace("__CASES__", json.dumps(cases)))
    print(f"{len(cases)} cases -> {args.out}")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
