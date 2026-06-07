local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")
local Players           = game:GetService("Players")

local bonusEffect = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BonusEffect")
local sounds      = workspace:WaitForChild("Sounds")

local function showFloatingText(root, text, color)
	if not root then return end
	local part = Instance.new("Part")
	part.Anchored     = true
	part.CanCollide   = false
	part.Transparency = 1
	part.Size         = Vector3.new(1, 1, 1)
	part.CFrame       = CFrame.new(root.Position + Vector3.new(0, 4, 0))
	part.Parent       = workspace

	local bb = Instance.new("BillboardGui", part)
	bb.Size        = UDim2.new(0, 200, 0, 80)
	bb.StudsOffset = Vector3.new(0, 2, 0)
	bb.AlwaysOnTop = true

	local label = Instance.new("TextLabel", bb)
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text                   = text
	label.TextColor3             = color
	label.TextScaled             = true
	label.Font                   = Enum.Font.GothamBold

	TweenService:Create(part,
		TweenInfo.new(0.8, Enum.EasingStyle.Quad),
		{ CFrame = CFrame.new(root.Position + Vector3.new(0, 8, 0)) }
	):Play()
	TweenService:Create(label,
		TweenInfo.new(0.8),
		{ TextTransparency = 1 }
	):Play()
	Debris:AddItem(part, 1)
end

local function spawnParticles(root, color)
	if not root then return end
	local part = Instance.new("Part")
	part.Anchored     = true
	part.CanCollide   = false
	part.Transparency = 1
	part.Size         = Vector3.new(1, 1, 1)
	part.CFrame       = CFrame.new(root.Position)
	part.Parent       = workspace

	local emitter = Instance.new("ParticleEmitter", part)
	emitter.Color         = ColorSequence.new(color)
	emitter.Size          = NumberSequence.new(0.3)
	emitter.Lifetime      = NumberRange.new(0.4, 0.8)
	emitter.Speed         = NumberRange.new(8, 14)
	emitter.SpreadAngle   = Vector2.new(60, 60)
	emitter.LightEmission = 0.5
	emitter:Emit(12)
	Debris:AddItem(part, 1)
end

bonusEffect.OnClientEvent:Connect(function(bonusType, text, soundName)
	local character = Players.LocalPlayer.Character
	local root      = character and character:FindFirstChild("HumanoidRootPart")

	if bonusType == "bonus" then
		showFloatingText(root, text, Color3.fromRGB(52, 255, 29))
		spawnParticles(root, Color3.fromRGB(52, 255, 29))
	elseif bonusType == "penalty" then
		showFloatingText(root, text, Color3.fromRGB(255, 0, 0))
		spawnParticles(root, Color3.fromRGB(255, 80, 80))
	end

	local sound = sounds:FindFirstChild(soundName)
	if sound then sound:Play() end
end)