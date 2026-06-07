local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")

local remotes   = ReplicatedStorage:WaitForChild("Remotes")
local evSound   = remotes:WaitForChild("PlaySound")
local evCollect = remotes:WaitForChild("PlankCollected")

local sounds = workspace:WaitForChild("Sounds")

-- PlaceSound cooldown: the sound is 0.6s long but planks are placed every ~0.12s.
-- Without throttling the sound stacks on itself and turns into noise.
local PLACE_COOLDOWN = 0.2
local lastPlace      = 0

-- Clone the sound so it can play multiple times simultaneously.
-- Used for short one-shot sounds that don't need throttling.
local function playClone(soundName)
	local sound = sounds:FindFirstChild(soundName)
	if not sound then
		warn("[SoundClient] Sound not found:", soundName)
		return
	end
	local clone = sound:Clone()
	clone.Parent = workspace
	clone:Play()
	Debris:AddItem(clone, clone.TimeLength + 0.5)
end

evSound.OnClientEvent:Connect(function(soundName)
	if soundName == "PlaceSound" then
		local now = tick()
		if now - lastPlace >= PLACE_COOLDOWN then
			lastPlace = now
			sounds.PlaceSound:Play()
		end
	else
		playClone(soundName)
	end
end)

evCollect.OnClientEvent:Connect(function()
	playClone("CollectSound")
end)