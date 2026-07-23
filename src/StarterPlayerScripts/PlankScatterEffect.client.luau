-- PlankScatterEffect.client.luau
-- Scatters carried planks on any death (whirlpool, spikes, drowning, etc).
-- Triggered by the WhirlpoolCatch remote, reused as a generic "scatter" signal —
-- name kept for backwards compatibility, not because it's whirlpool-only anymore.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player   = Players.LocalPlayer
local remotes  = ReplicatedStorage:WaitForChild("Remotes")
local evCatch  = remotes:WaitForChild("WhirlpoolCatch")
local template = ReplicatedStorage:WaitForChild("Clones"):WaitForChild("PlankModel")

evCatch.OnClientEvent:Connect(function()
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local planks = {}
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part.Name == template.Name then
			table.insert(planks, part)
		end
	end

	for _, plank in ipairs(planks) do
		for _, w in ipairs(plank:GetChildren()) do
			if w:IsA("WeldConstraint") then w:Destroy() end
		end
		plank.Parent     = workspace 
		game:GetService("Debris"):AddItem(plank, 2)
		plank.Anchored   = false
		plank.CanCollide = true
		plank.AssemblyLinearVelocity = Vector3.new(
			math.random(-25, 25),
			math.random(15, 35),
			math.random(-25, 25)
		)
		plank.AssemblyAngularVelocity = Vector3.new(
			math.random(-10, 10),
			math.random(-10, 10),
			math.random(-10, 10)
		)
	end
end)