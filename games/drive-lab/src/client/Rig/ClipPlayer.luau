--!strict
--[[
	Plays at most one clip on a character and keeps it in step with a clock the caller owns:
	each frame the caller names the clip and how far into it the pose should be, and the track
	follows, held on its last frame once it ends. Where the server's time decides a pose (the
	car's door moves with the hand), a track left to run from whenever it started would drift.
]]
export type ClipPlayer = {
	animator: Animator,
	tracks: { [string]: AnimationTrack },
	playing: AnimationTrack?,
	playingId: string?,
}

-- Seconds a track may drift from its clock before it is moved back.
local DRIFT = 0.08
local LAST_FRAME = 1 / 60

local ClipPlayer = {}

function ClipPlayer.new(animator: Animator): ClipPlayer
	return { animator = animator, tracks = {}, playing = nil, playingId = nil }
end

local function load(self: ClipPlayer, id: string, looped: boolean): AnimationTrack
	local existing = self.tracks[id]
	if existing then
		return existing
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local track = self.animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = looped
	self.tracks[id] = track
	return track
end

-- Loads clips ahead of their first use: a clip played before its asset has loaded has no length
-- and no pose for its first frames (measured: a seated body shown in the seat for a frame, 5.6
-- studs from where the clip puts it). `looped` names the ids that play as loops.
function ClipPlayer.preload(self: ClipPlayer, ids: { string }, looped: { [string]: boolean })
	for _, id in ids do
		if id ~= "" then
			load(self, id, looped[id] == true)
		end
	end
end

-- An empty or nil `id` stops the clip. `into` nil plays a loop left to run on its own. `holdAt`
-- holds the clip at that time instead of its last frame (a sequence ending it early).
function ClipPlayer.set(self: ClipPlayer, id: string?, into: number?, fade: number, holdAt: number?)
	if id == nil or id == "" then
		if self.playing then
			self.playing:Stop(fade)
		end
		self.playing, self.playingId = nil, nil
		return
	end
	local track = load(self, id, into == nil)
	if self.playingId ~= id then
		if self.playing then
			self.playing:Stop(fade)
		end
		track:Play(fade)
		self.playing, self.playingId = track, id
	elseif not track.IsPlaying then
		track:Play(0)
	end
	local length = track.Length
	if into == nil or length <= 0 then
		return
	end
	local hold = math.min(holdAt or length, length - LAST_FRAME)
	local holding = into >= hold
	local target = if holding then hold else into
	track:AdjustSpeed(if holding then 0 else 1)
	if holding or math.abs(track.TimePosition - target) > DRIFT then
		track.TimePosition = target
	end
end

-- Stops every clip at once, those still fading out included.
function ClipPlayer.stopAll(self: ClipPlayer)
	for _, track in self.tracks do
		track:Stop(0)
	end
	self.playing, self.playingId = nil, nil
end

function ClipPlayer.destroy(self: ClipPlayer)
	for _, track in self.tracks do
		track:Stop(0)
		track:Destroy()
	end
	table.clear(self.tracks)
	self.playing, self.playingId = nil, nil
end

return ClipPlayer
