-- AnalyticsAdmin.server.luau
-- Exposes session analytics to the GUI, restricted to the developer's UserId.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AnalyticsService = require(ServerScriptService.MainGame.Services.AnalyticsService)
local DevConfig = require(ReplicatedStorage.DevConfig)

local function isAdmin(player)
	for _, id in ipairs(DevConfig.ADMIN_USER_IDS) do
		if player.UserId == id then return true end
	end
	return false
end

local remoteFunc = ReplicatedStorage.Remotes:WaitForChild("GetAnalytics")

remoteFunc.OnServerInvoke = function(player)
	if not isAdmin(player) then return {} end
	return AnalyticsService.ListSessions()
end