--!strict
-- CheckpointService.luau
-- Thin wrapper around Player.RespawnLocation, keyed by level. Checkpoint
-- spawn points are real SpawnLocation instances placed by hand in
-- workspace.CheckpointSpawns (Neutral = true, Enabled = true, LevelId
-- attribute) — Roblox handles height/orientation on respawn itself, no
-- manual CFrame math needed.

local CheckpointService = {}

local checkpointSpawns = workspace:WaitForChild("CheckpointSpawns")

-- Indexed by LevelId attribute (Number) → the SpawnLocation instance.
-- Includes LevelId = 1, so "reset to the start" is just SetFromLevel(1) —
-- no separate hardcoded default needed.
local spawnsByLevel: { [number]: SpawnLocation } = {}

for _, part in ipairs(checkpointSpawns:GetChildren()) do
	if part:IsA("SpawnLocation") then
		local levelId = part:GetAttribute("LevelId")
		if levelId then
			spawnsByLevel[levelId] = part
		else
			warn("[CheckpointService] '" .. part.Name .. "' in CheckpointSpawns has no LevelId attribute — skipped")
		end
	end
end

-- Points the player's respawn at the SpawnLocation registered for levelId.
-- No-op (with a warning) if no part was placed for that level — the player
-- just keeps their previous checkpoint instead of crashing or losing progress.
function CheckpointService.SetFromLevel(player: Player, levelId: number)
	local spawnPart = spawnsByLevel[levelId]
	if not spawnPart then
		warn("[CheckpointService] No CheckpointSpawns SpawnLocation for LevelId", levelId, "- checkpoint not updated for", player.Name)
		return
	end
	player.RespawnLocation = spawnPart
end

-- Back to the level-1 spawn. Used on a player's first join and on a full
-- restart (Replay button) — both should start from the very beginning.
function CheckpointService.Reset(player: Player)
	CheckpointService.SetFromLevel(player, 1)
end

return CheckpointService