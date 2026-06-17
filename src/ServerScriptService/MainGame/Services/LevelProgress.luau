-- LevelProgress.luau
-- Single source of truth for player progression through levels.
-- Used by LevelEnds (advance progress) and level-gated obstacles
-- (access checks via HasAccess).

local LevelProgress = {}

local progress = {} -- progress[userId] = currently unlocked level number

-- Initialise a new player at level 1.
function LevelProgress.Init(player)
	progress[player.UserId] = 1
end

-- Clean up when the player leaves.
function LevelProgress.Cleanup(player)
	progress[player.UserId] = nil
end

-- Returns the player's current unlocked level (defaults to 1).
function LevelProgress.Get(player)
	return progress[player.UserId] or 1
end

-- Returns true if the player has access to objects belonging to levelId.
function LevelProgress.HasAccess(player, levelId)
	return LevelProgress.Get(player) >= levelId
end

-- Advances progress if the player is currently on levelId.
-- Returns true if progress advanced, false if the check failed
-- (player hasn't reached this level yet, or already past it).
function LevelProgress.TryAdvance(player, levelId)
	if progress[player.UserId] == levelId then
		progress[player.UserId] = levelId + 1
		return true
	end
	return false
end

return LevelProgress