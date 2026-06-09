-- HudGui.client.luau
-- Displays the local player's current plank count.
-- Filters PlankUpdate by UserId since it fires for all players.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local remotes  = ReplicatedStorage:WaitForChild("Remotes")
local evUpdate = remotes:WaitForChild("PlankUpdate")

local hudFrame  = script.Parent:WaitForChild("HudFrame")
local countLabel = hudFrame:WaitForChild("Count")

countLabel.Text = "0"

evUpdate.OnClientEvent:Connect(function(userId, count)
	if userId ~= Players.LocalPlayer.UserId then return end
	countLabel.Text = tostring(count)
	TweenService:Create(countLabel,
		TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ TextTransparency = 0 }
	):Play()
end)