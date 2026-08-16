--!strict
-- PlankScatterEffect.client.luau
-- Scatters carried planks on any death (whirlpool, spikes, drowning, etc).
-- Triggered by the WhirlpoolCatch remote, reused as a generic "scatter" signal —
-- name kept for backwards compatibility, not because it's whirlpool-only anymore.
-- Fires for EVERY client (server uses FireAllClients), so this also plays the
-- effect for other players' characters, not just the local one. Which Parts
-- belong to which player is resolved via PlankVisualsRegistry, not by reading
-- Character children directly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")

local Registry = require(script.Parent:WaitForChild("Modules"):WaitForChild("PlankVisualsRegistry"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local evCatch = remotes:WaitForChild("WhirlpoolCatch")

evCatch.OnClientEvent:Connect(function(userId: number)
	local planks = Registry.GetPlanks(userId)

	for _, plank in ipairs(planks) do
		if not plank or not plank.Parent then continue end

		for _, w in ipairs(plank:GetChildren()) do
			if w:IsA("WeldConstraint") then w:Destroy() end
		end

		plank.Parent     = workspace
		Debris:AddItem(plank, 2)
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