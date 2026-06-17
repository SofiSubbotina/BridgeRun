-- LevelVisibility.client.luau
-- Hides content belonging to levels the local player hasn't reached yet,
-- and reveals it once the server signals unlock.
-- Handles parts that stream in after this script starts (StreamingEnabled).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes         = ReplicatedStorage:WaitForChild("Remotes")
local evLevelUnlocked = remotes:WaitForChild("LevelUnlocked")

-- Folder containing Level1Content, Level2Content, etc.
local levels = workspace:WaitForChild("Levels")

local unlockedLevels = { [1] = true } -- level 1 is always visible

-- Extracts the level number from a folder name like "Level2Content".
local function getLevelId(name)
	return tonumber(name:match("^Level(%d+)Content$"))
end

local function applyVisibility(part, levelId)
	part.LocalTransparencyModifier = unlockedLevels[levelId] and 0 or 1
end

-- Apply visibility to all level folders on start.
for _, child in ipairs(levels:GetChildren()) do
	local levelId = getLevelId(child.Name)
	if levelId then
		-- Apply to parts already streamed in.
		for _, part in ipairs(child:GetDescendants()) do
			if part:IsA("BasePart") then
				applyVisibility(part, levelId)
			end
		end

		-- Apply to parts that stream in later (StreamingEnabled).
		child.DescendantAdded:Connect(function(part)
			if part:IsA("BasePart") then
				applyVisibility(part, levelId)
			end
		end)
	end
end

-- Reveal content when the server signals a new level is unlocked.
evLevelUnlocked.OnClientEvent:Connect(function(levelId)
	unlockedLevels[levelId] = true

	local content = levels:FindFirstChild("Level" .. levelId .. "Content")
	if content then
		for _, part in ipairs(content:GetDescendants()) do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 0
			end
		end
	end
end)