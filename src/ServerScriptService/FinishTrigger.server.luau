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

local finish = workspace:WaitForChild("Finish"):WaitForChild("FinishPart")

local CONFIG = {
	MIN_FINISH_TIME  = 45,  -- меньше этого времени финиш не засчитывается
	FINISH_COOLDOWN  = 15,  -- секунд до сброса флага finished
	RESTART_COOLDOWN = 3,   -- защита от спама кнопки рестарта
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

	local humanoid = character:FindFirstChild("Humanoid")
	local root     = character:FindFirstChild("HumanoidRootPart")

	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end
	if root then
		root.AssemblyLinearVelocity  = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.Anchored = true
	end

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
	LeaderboardService.NewRun(player)
	player:LoadCharacter()

	task.delay(CONFIG.RESTART_COOLDOWN, function()
		restartDebounce[player.UserId] = nil
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	finished[player.UserId]        = nil
	restartDebounce[player.UserId] = nil
end)