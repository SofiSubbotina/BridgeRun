-- TrampolineEffects.luau
-- Trampoline ring rotation and particle burst on jump.
-- Moved as-is from the old MapEffects.client.luau — logic unchanged,
-- just relocated under MapEffectsManager/Effects.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local TrampolineEffects = {}

local ROTATION_SPEED = 20 -- degrees per second

local rings = {}

local function registerTrampoline(part)
	if not part:IsA("BasePart") then return end
	local ring = part:FindFirstChild("Ring")
	if ring then
		table.insert(rings, ring)
	end
end

function TrampolineEffects.Start()
	local remotes      = ReplicatedStorage:WaitForChild("Remotes")
	local evTrampoline = remotes:WaitForChild("TrampolineJump")

	for _, part in ipairs(CollectionService:GetTagged("Trampoline")) do
		registerTrampoline(part)
	end
	CollectionService:GetInstanceAddedSignal("Trampoline"):Connect(registerTrampoline)

	RunService.RenderStepped:Connect(function(dt)
		for _, ring in ipairs(rings) do
			if ring and ring.Parent then
				ring.CFrame = ring.CFrame * CFrame.Angles(
					math.rad(ROTATION_SPEED * dt),
					0,
					0
				)
			end
		end
	end)

	evTrampoline.OnClientEvent:Connect(function(jumperId)
		local otherPlayer = Players:GetPlayerByUserId(jumperId)
		if not otherPlayer then return end
		local char = otherPlayer.Character
		if not char then return end
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then return end

		local closest     = nil
		local closestDist = math.huge

		for _, part in ipairs(CollectionService:GetTagged("Trampoline")) do
			if part:IsA("BasePart") then
				local dist = (part.Position - root.Position).Magnitude
				if dist < closestDist then
					closestDist = dist
					closest     = part
				end
			end
		end

		if not closest then return end
		local particles = closest:FindFirstChild("JumpParticles")
		if particles then
			particles:Emit(80)
		end
	end)
end

return TrampolineEffects