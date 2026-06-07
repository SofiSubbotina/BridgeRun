-- Client script: drown animation — character sinks underwater,
-- splash on the surface, screen darkens.

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")

local player  = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local evDied  = remotes:WaitForChild("PlayerDied")

local screenGui = Instance.new("ScreenGui")
screenGui.Name            = "DrownOverlay"
screenGui.ResetOnSpawn    = false
screenGui.IgnoreGuiInset  = true
screenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
screenGui.Parent          = player.PlayerGui

local overlay = Instance.new("Frame", screenGui)
overlay.Size                   = UDim2.fromScale(1, 1)
overlay.BackgroundColor3       = Color3.fromRGB(0, 20, 40)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel        = 0

local function spawnSplash(position)
	local part = Instance.new("Part")
	part.Anchored     = true
	part.CanCollide   = false
	part.Transparency = 1
	part.Size         = Vector3.new(1, 1, 1)
	part.CFrame       = CFrame.new(position.X, 0, position.Z)
	part.Parent       = workspace

	local bubbles = Instance.new("ParticleEmitter", part)
	bubbles.Color         = ColorSequence.new(Color3.fromRGB(180, 220, 255))
	bubbles.Size          = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	bubbles.Transparency  = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	bubbles.Lifetime      = NumberRange.new(0.8, 1.4)
	bubbles.Speed         = NumberRange.new(5, 10)
	bubbles.SpreadAngle   = Vector2.new(40, 40)
	bubbles.LightEmission = 0.3
	bubbles.RotSpeed      = NumberRange.new(-45, 45)
	bubbles:Emit(40)

	local splash = Instance.new("ParticleEmitter", part)
	splash.Color         = ColorSequence.new(Color3.fromRGB(200, 230, 255))
	splash.Size          = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	splash.Transparency  = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	splash.Lifetime      = NumberRange.new(0.5, 0.9)
	splash.Speed         = NumberRange.new(10, 18)
	splash.SpreadAngle   = Vector2.new(80, 80)
	splash.LightEmission = 0.2
	splash:Emit(25)

	Debris:AddItem(part, 1.5)
end

local function spawnLaterBubbles(position)
	task.delay(0.4, function()
		local part = Instance.new("Part")
		part.Anchored     = true
		part.CanCollide   = false
		part.Transparency = 1
		part.Size         = Vector3.new(1, 1, 1)
		part.CFrame       = CFrame.new(position.X, 0, position.Z)
		part.Parent       = workspace

		local bubbles = Instance.new("ParticleEmitter", part)
		bubbles.Color         = ColorSequence.new(Color3.fromRGB(180, 220, 255))
		bubbles.Size          = NumberSequence.new(0, 0.9)
		bubbles.Transparency  = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		bubbles.Lifetime      = NumberRange.new(0.6, 1.0)
		bubbles.Speed         = NumberRange.new(4, 8)
		bubbles.SpreadAngle   = Vector2.new(30, 30)
		bubbles:Emit(10)

		Debris:AddItem(part, 1.2)
	end)
end

evDied.OnClientEvent:Connect(function()
	local character = player.Character
	if not character then return end

	local hrp      = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChild("Humanoid")
	if not hrp or not humanoid then return end

	local startPos = hrp.Position
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0

	spawnSplash(startPos)
	spawnLaterBubbles(startPos)

	TweenService:Create(hrp,
		TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = hrp.CFrame * CFrame.new(0, -6, 0) }
	):Play()

	task.delay(0.5, function()
		TweenService:Create(overlay,
			TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 0.3 }
		):Play()
	end)
end)

-- Single connection for the script's lifetime —
-- not recreated on each death to avoid accumulation.
player.CharacterAdded:Connect(function()
	TweenService:Create(overlay,
		TweenInfo.new(0.4),
		{ BackgroundTransparency = 1 }
	):Play()
end)