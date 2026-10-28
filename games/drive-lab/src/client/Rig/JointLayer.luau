--!strict
--[[
	Layers a procedural turn onto one joint of a character, on top of whatever the Animator
	wrote this frame, so animations keep playing underneath. Joints are Motor6Ds on classic rigs
	and kinematic AnimationConstraints on upgraded ones (every spawned avatar on 2026-10-27); both
	expose Transform, and the constraint's C0 is read-only, so Transform is what both accept.
	Apply from RunService.PreSimulation, which runs after the Animator.
]]
export type JointName = "Neck" | "Root"

export type JointLayer = {
	joint: Instance,
	-- The part the joint hangs from (the torso for the neck, the root part for the root).
	parent: BasePart,
	-- Where the joint pivots, in the parent part's space.
	pivot: Vector3,
	read: () -> CFrame,
	write: (CFrame) -> (),
	-- Rotation from the parent part's axes into the frame Transform is expressed in.
	basis: CFrame,
	-- What this layer last wrote, and the turn inside it. When the Animator leaves the joint
	-- alone for a frame, Transform still holds our write; the old turn is taken back out
	-- instead of compounding.
	written: CFrame,
	turn: CFrame,
}

local LOCATIONS: { [JointName]: { [Enum.HumanoidRigType]: { string } } } = {
	Neck = {
		[Enum.HumanoidRigType.R6] = { "Torso", "Neck" },
		[Enum.HumanoidRigType.R15] = { "Head", "Neck" },
	},
	Root = {
		[Enum.HumanoidRigType.R6] = { "HumanoidRootPart", "RootJoint" },
		[Enum.HumanoidRigType.R15] = { "LowerTorso", "Root" },
	},
}

local JointLayer = {}

local function layer(
	joint: Instance,
	parent: BasePart,
	frame: CFrame,
	read: () -> CFrame,
	write: (CFrame) -> ()
): JointLayer
	return {
		joint = joint,
		parent = parent,
		pivot = frame.Position,
		read = read,
		write = write,
		basis = frame.Rotation,
		written = CFrame.identity,
		turn = CFrame.identity,
	}
end

function JointLayer.wrap(joint: Instance): JointLayer?
	if joint:IsA("Motor6D") then
		local parent = joint.Part0
		if parent == nil then
			return nil
		end
		return layer(joint, parent, joint.C0, function()
			return joint.Transform
		end, function(transform: CFrame)
			joint.Transform = transform
		end)
	end
	if joint:IsA("AnimationConstraint") then
		local attachment = joint.Attachment0
		local parent = attachment and attachment.Parent
		if attachment == nil or parent == nil or not parent:IsA("BasePart") then
			return nil
		end
		return layer(joint, parent, attachment.CFrame, function()
			return joint.Transform
		end, function(transform: CFrame)
			joint.Transform = transform
		end)
	end
	return nil
end

function JointLayer.find(character: Model, name: JointName): JointLayer?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local path = humanoid and LOCATIONS[name][humanoid.RigType]
	if path == nil then
		return nil
	end
	local holder = character:FindFirstChild(path[1])
	local joint = holder and holder:FindFirstChild(path[2])
	return if joint then JointLayer.wrap(joint) else nil
end

-- `turn` is expressed in the parent part's axes, about the joint's pivot.
function JointLayer.apply(self: JointLayer, turn: CFrame)
	local animated = self.read()
	if animated == self.written then
		animated = self.turn:Inverse() * animated
	end
	local inJoint = self.basis:Inverse() * turn * self.basis
	local written = inJoint * animated
	self.write(written)
	self.turn, self.written = inJoint, written
end

function JointLayer.alive(self: JointLayer): boolean
	return self.joint.Parent ~= nil and self.parent.Parent ~= nil
end

return JointLayer
