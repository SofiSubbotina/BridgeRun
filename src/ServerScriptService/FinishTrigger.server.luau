-- FinishTrigger.luau
-- Detects when a player touches the finish part and handles end-of-run logic.
-- Uses PeekElapsed to check time before committing the finish,
-- avoiding a race condition where Finish() is called too early.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local remotes   = ReplicatedStorage:WaitForChild("Remotes")
local evFinish  = remotes:WaitForChild("PlayerFinished")
local evRestart = remotes:WaitForChild("PlayerRestart")
local evUpdate  = remotes:WaitForChild("PlankUpdate")
local evSound   = remotes:WaitForChild("PlaySound")

local PlankService       = require(ServerScriptService.MainGame.Services.PlankService)
local BridgeService      = require(ServerScriptService.MainGame.Services.BridgeService)
local LeaderboardService = require(ServerScriptService.MainGame.Services.LeaderboardService)
local CharacterLock = require(ServerScriptService.MainGame.Services.CharacterLock)
local AnalyticsService = require(ServerScriptService.MainGame.Services.AnalyticsService)
local LevelProgress      = require(ServerScriptService.MainGame.Services.LevelProgress)
local CheckpointService  = require(ServerScriptService.MainGame.Services.CheckpointService)

local finish = workspace:WaitForChild("Finish"):WaitForChild("FinishPart")

local CONFIG = {
	MIN_FINISH_TIME  = 45,  -- runs faster than this are ignored (anti-cheat)
	FINISH_COOLDOWN  = 15,  -- seconds before the finished flag resets
	RESTART_COOLDOWN = 3,   -- prevents restart button spam
}

local finished        = {}
local restartDebounce = {}

finish.Touched:Connect(function(hit)
	local character = hit.Parent
	local player    = Players:GetPlayerFromCharacter(character)
	if not player then return end
	if finished[player.UserId] then return end

	local peeked = LeaderboardService.PeekElapsed(player)
	if not peeked or peeked < CONFIG.MIN_FINISH_TIME then
		return
	end

	finished[player.UserId] = true

	local elapsed, bestTime, attempts = LeaderboardService.Finish(player)
	if not elapsed then
		finished[player.UserId] = nil
		return
	end

	AnalyticsService.RecordFinish(player, elapsed)

	CharacterLock.Freeze(character, true)

	PlankService.Reset(player)
	evUpdate:FireClient(player, 0)
	BridgeService.Cleanup(player)
	evSound:FireClient(player, "FinishSound")
	evFinish:FireClient(player, elapsed, bestTime, attempts)

	task.delay(CONFIG.FINISH_COOLDOWN, function()
		finished[player.UserId] = nil
	end)
end)

evRestart.OnServerEvent:Connect(function(player)
	if restartDebounce[player.UserId] then return end
	restartDebounce[player.UserId] = true

	local character = player.Character
	if character then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then root.Anchored = false end
	end

	-- Replay after finishing is a genuine full restart, not a checkpoint
	-- respawn: back to level 1 and the default spawn.
	LevelProgress.Reset(player)
	CheckpointService.Reset(player)

	LeaderboardService.NewRun(player)
	player:LoadCharacterAsync()

	task.delay(CONFIG.RESTART_COOLDOWN, function()
		restartDebounce[player.UserId] = nil
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	finished[player.UserId]        = nil
	restartDebounce[player.UserId] = nil
end)