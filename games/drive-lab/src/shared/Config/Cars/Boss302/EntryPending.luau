--!strict
--[[
	What the Boss 302's car entry (its Contract entry, init.luau) still needs before the car can
	join the catalog: each item names the piece and whose it is.
]]
return {
	"door: the entry and exit clips, their door curves, the seated pose and the exit stance (entry animator)",
	"driver: the start-up's hand paths with the key turn and the lean (StartupPaths, key-start animator)",
	"driver: the shift hand (Shift.luau, shift-hand animator)",
	"driver: the hand-over from the entry's hands to the drawn ones (entry animator)",
	"display: the cluster face (gauge cluster work)",
	"audio: the sound pack (Audio.luau, audio)",
	"the entry module itself (init.luau), once the pieces above exist",
}
