-- LevelEnds.server.luau
-- Invisible trigger parts placed at the end of each level segment.
-- Each part must have a numeric "LevelId" attribute marking which
-- level it completes. On touch, advances the player's progress and
-- notifies the client to reveal the next level's content.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local remotes         = ReplicatedStorage:WaitForChild("Remotes")
local evLevelUnlocked = remotes:WaitForChild("LevelUnlocked")

local LevelProgress = require(ServerScriptService.MainGame.Services.LevelProgress)
local BonusService = require(ServerScriptService.MainGame.Services.BonusService)

-- Folder containing invisible trigger parts, each with a
-- numeric "LevelId" attribute marking which level they end.
local levelEnds = workspace:WaitForChild("LevelEnds")

Players.PlayerAdded:Connect(function(player)
	LevelProgress.Init(player)
end)

Players.PlayerRemoving:Connect(function(player)
	LevelProgress.Cleanup(player)
end)

local function setupLevelEnd(part)
	if not part:IsA("BasePart") then return end

	local levelId = part:GetAttribute("LevelId")
	if not levelId then return end

	part.Touched:Connect(function(hit)
		local character = hit.Parent
		local player     = Players:GetPlayerFromCharacter(character)
		if not player then return end

		if LevelProgress.TryAdvance(player, levelId) then
			evLevelUnlocked:FireClient(player, levelId + 1)
			task.delay(0.1, function()
				BonusService.ResetDebounce(player)
		end)
	end
end)
end

for _, part in ipairs(levelEnds:GetChildren()) do
	setupLevelEnd(part)
end