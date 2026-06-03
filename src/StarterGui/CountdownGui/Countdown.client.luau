local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local player           = Players.LocalPlayer
local remotes          = ReplicatedStorage:WaitForChild("Remotes")
local evStartCountdown = remotes:WaitForChild("StartCountdown")
local evPlayerReady    = remotes:WaitForChild("PlayerReady")

local sounds    = workspace:WaitForChild("Sounds")
local screenGui = script.Parent
local label     = screenGui:WaitForChild("CountdownLabel")

local countdownSound = sounds:WaitForChild("CountdownSound")

local CountdownState = require(ReplicatedStorage:WaitForChild("CountdownState"))

local STEP_TIME = 1
local GO_TIME   = 0.6

local function animateLabel(text, color)
	label.Text             = text
	label.TextColor3       = color
	label.TextTransparency = 0
	label.AnchorPoint      = Vector2.new(0.5, 0.5)
	label.Position         = UDim2.new(0.5, 0, 0.4, 0)
	label.Size             = UDim2.new(0, 220, 0, 220)

	TweenService:Create(label,
		TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 130, 0, 130) }
	):Play()

	TweenService:Create(label,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.65),
		{ TextTransparency = 1 }
	):Play()
end

local function runCountdown()
	CountdownState.active = true
	screenGui.Enabled     = true

	countdownSound:Play()

	local steps = {
		{ text = "3", color = Color3.fromRGB(255, 200, 70) },
		{ text = "2", color = Color3.fromRGB(255, 200, 70) },
		{ text = "1", color = Color3.fromRGB(255, 200, 70) },
	}

	for _, step in ipairs(steps) do
		animateLabel(step.text, step.color)
		task.wait(STEP_TIME)
	end

	animateLabel("GO!", Color3.fromRGB(100, 255, 120))
	task.wait(GO_TIME)

	screenGui.Enabled     = false
	CountdownState.active = false

	evPlayerReady:FireServer()
end

evStartCountdown.OnClientEvent:Connect(function()
	runCountdown()
end)

player.CharacterRemoving:Connect(function()
	CountdownState.active = false
	screenGui.Enabled     = false
end)