-- Trampoline ring rotation and particle burst on jump.
-- LocalScript — each client renders locally; all clients see the same result.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes      = ReplicatedStorage:WaitForChild("Remotes")
local evTrampoline = remotes:WaitForChild("TrampolineJump")

local CollectionService = game:GetService("CollectionService")
local ROTATION_SPEED = 20 -- degrees per second

local rings = {}

local function registerTrampoline(part)
	if not part:IsA("BasePart") then return end
	local ring = part:FindFirstChild("Ring")
	if ring then
		table.insert(rings, ring)
	end
end

-- Tag-based lookup: works regardless of where in the hierarchy the part lives
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
