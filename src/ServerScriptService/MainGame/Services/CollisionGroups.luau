-- CollisionGroups.luau
-- Creates collision groups for level geometry and player characters.
-- A player at Stage N cannot collide with geometry from Level(N+1) and above.
-- Call Init on character spawn and AdvanceStage when a LevelEnd is passed.

local CollisionGroups = {}

local PhysicsService = game:GetService("PhysicsService")

local MAX_LEVELS = 5

local function geoGroup(i)   return "Level" .. i .. "Geo" end
local function stageGroup(i) return "PlayerStage" .. i    end

for i = 1, MAX_LEVELS do
	PhysicsService:RegisterCollisionGroup(geoGroup(i))
	PhysicsService:RegisterCollisionGroup(stageGroup(i))
end

for stage = 1, MAX_LEVELS do
	for level = 1, MAX_LEVELS do
		PhysicsService:CollisionGroupSetCollidable(
			stageGroup(stage),
			geoGroup(level),
			level <= stage
		)
	end
end

local levels = workspace:WaitForChild("Levels")
for i = 1, MAX_LEVELS do
	local folder = levels:FindFirstChild("Level" .. i)
	if folder then
		for _, part in ipairs(folder:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CollisionGroup = geoGroup(i)
			end
		end
	end
end

local function applyStage(character, stage)
	local group = stageGroup(math.clamp(stage, 1, MAX_LEVELS))
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end

function CollisionGroups.Init(player, character)
	local LevelProgress = require(script.Parent.LevelProgress)
	applyStage(character, LevelProgress.Get(player))
end

function CollisionGroups.AdvanceStage(player, newLevel)
	local character = player.Character
	if not character then return end
	applyStage(character, newLevel)
end

return CollisionGroups