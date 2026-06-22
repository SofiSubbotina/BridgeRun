-- LevelVisibility.client.luau
-- Hides geometry and GUI belonging to levels the local player hasn't reached,
-- and reveals it once the server fires LevelUnlocked.
-- Also handles parts that stream in after this script starts (StreamingEnabled).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes         = ReplicatedStorage:WaitForChild("Remotes")
local evLevelUnlocked = remotes:WaitForChild("LevelUnlocked")

local levels         = workspace:WaitForChild("Levels")
local unlockedLevels = { [1] = true } -- level 1 is always visible

-- Extracts the level number from a folder named "Level1", "Level2", etc.
local function getLevelId(name)
	return tonumber(name:match("^Level(%d+)$"))
end

-- Hides or reveals a single instance.
-- BaseParts use LocalTransparencyModifier (per-client, non-destructive).
-- GUI objects use Enabled so their layout is also suppressed.
local function applyVisibility(part, visible)
	if part:IsA("BasePart") then
		part.LocalTransparencyModifier = visible and 0 or 1
	elseif part:IsA("SurfaceGui") or part:IsA("BillboardGui") then
		part.Enabled = visible
		elseif part:IsA("Decal") or part:IsA("Texture") then
		part.Transparency = visible and 0 or 1
	end
end

local function applyLevelVisibility(levelFolder, visible)
	for _, part in ipairs(levelFolder:GetDescendants()) do
		applyVisibility(part, visible)
	end
end

-- Apply visibility to all level folders on start
for _, child in ipairs(levels:GetChildren()) do
	local levelId = getLevelId(child.Name)
	if levelId then
		local visible = unlockedLevels[levelId] == true
		applyLevelVisibility(child, visible)

		-- Re-apply as parts stream in later (StreamingEnabled)
		child.DescendantAdded:Connect(function(part)
			applyVisibility(part, unlockedLevels[levelId] == true)
		end)
	end
end

-- Reveal a level's content when the server unlocks it
evLevelUnlocked.OnClientEvent:Connect(function(levelId)
	unlockedLevels[levelId] = true
	local levelFolder = levels:FindFirstChild("Level" .. levelId)
	if levelFolder then
		applyLevelVisibility(levelFolder, true)
	end
end)