local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local remotes   = ReplicatedStorage:WaitForChild("Remotes")
local evFinish  = remotes:WaitForChild("PlayerFinished")
local evRestart = remotes:WaitForChild("PlayerRestart")

local screenGui     = script.Parent
local card          = screenGui:WaitForChild("Card")
local timeLabel     = card:WaitForChild("TimeLabel")
local recordLabel   = card:WaitForChild("RecordLabel")
local attemptsLabel = card:WaitForChild("AttemptsLabel")
local replayBtn     = card:WaitForChild("ReplayButton")

local function formatTime(seconds)
	if not seconds then return "--:--" end
	local minutes = math.floor(seconds / 60)
	local secs    = seconds % 60
	if minutes > 0 then
		return string.format("%d:%05.2f min", minutes, secs)
	else
		return string.format("%.2f sec", secs)
	end
end

local function showFinishScreen(elapsed, bestTime, attempts)
	screenGui.Enabled  = true
	timeLabel.Text     = "Time: " .. formatTime(elapsed)
	attemptsLabel.Text = "Attempts: " .. tostring(attempts)

	if bestTime and math.abs(elapsed - bestTime) < 0.01 then
		recordLabel.Text       = "🏆 New Record!"
		recordLabel.TextColor3 = Color3.fromRGB(255, 200, 70)
	else
		recordLabel.Text       = "Record: " .. formatTime(bestTime)
		recordLabel.TextColor3 = Color3.fromRGB(100, 255, 120)
	end

	card.Position = UDim2.new(0.5, 0, 1.5, 0)
	TweenService:Create(card,
		TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0.5, 0) }
	):Play()
end

replayBtn.MouseEnter:Connect(function()
	TweenService:Create(replayBtn,
		TweenInfo.new(0.15),
		{ BackgroundColor3 = Color3.fromRGB(255, 220, 100) }
	):Play()
end)

replayBtn.MouseLeave:Connect(function()
	TweenService:Create(replayBtn,
		TweenInfo.new(0.15),
		{ BackgroundColor3 = Color3.fromRGB(255, 200, 70) }
	):Play()
end)

replayBtn.MouseButton1Click:Connect(function()
	replayBtn.Active   = false
	timeLabel.Text     = "Loading..."
	recordLabel.Text   = ""
	attemptsLabel.Text = ""
	evRestart:FireServer()
end)

evFinish.OnClientEvent:Connect(function(elapsed, bestTime, attempts)
	if not elapsed then return end
	replayBtn.Active = true
	showFinishScreen(elapsed, bestTime, attempts)
end)

player.CharacterAdded:Connect(function()
	screenGui.Enabled = false
	replayBtn.Active  = true
end)