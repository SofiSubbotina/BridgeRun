-- MainGame.server.luau
-- Manages player lifecycle: character setup, bridge walking,
-- plank pickup, drowning, and cleanup on death or disconnect.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlankService       = require(script.Services.PlankService)
local BridgeService      = require(script.Services.BridgeService)
local BonusService       = require(script.Services.BonusService)
local LeaderboardService = require(script.Services.LeaderboardService)
local CharacterLock      = require(script.Services.CharacterLock)
local CollisionGroups = require(script.Services.CollisionGroups)

local remotes          = ReplicatedStorage:WaitForChild("Remotes")
local evUpdate         = remotes:WaitForChild("PlankUpdate")
local evCollect        = remotes:WaitForChild("PlankCollected")
local evDied           = remotes:WaitForChild("PlayerDied")
local evSound          = remotes:WaitForChild("PlaySound")
local evSpawnPlanks    = remotes:WaitForChild("SpawnPersonalPlanks")
local evPickup         = remotes:WaitForChild("PlankPickedUp")
local evReady          = remotes:WaitForChild("ClientReady")
local evPlayerReady    = remotes:WaitForChild("PlayerReady")
local evStartCountdown = remotes:WaitForChild("StartCountdown")

-- Plank amounts keyed by template name, used to validate pickup events.
-- PlanksTemplate is organised into per-level sub-folders (Level1, Level2, …).
local planksTemplate = ReplicatedStorage
	:WaitForChild("Clones")
	:WaitForChild("PlanksTemplate")

local templateData = {}
for _, levelFolder in ipairs(planksTemplate:GetChildren()) do
	for _, part in ipairs(levelFolder:GetChildren()) do
		templateData[part.Name] = part:GetAttribute("Planks") or 1
	end
end

local CONFIG = {
	WALK_SPEED         = 18,
	JUMP_POWER         = 25,
	DROWN_DELAY        = 1.5,  -- seconds before humanoid health is set to 0
	CLEANUP_DELAY      = 3,    -- seconds before bridge cleanup after death
	HEARTBEAT_INTERVAL = 0.05, -- minimum seconds between water checks per player
	PICKUP_COOLDOWN    = 0.3,  -- minimum seconds between plank pickup events
}

local playerStatus   = {} -- "frozen" | "alive" | "dead"
local lastStep       = {}
local pickupDebounce = {}

local function syncPlanks(player)
	evUpdate:FireAllClients(player.UserId, PlankService.Get(player))
end

local function handleDrown(player, character, humanoid, conn)
	playerStatus[player.UserId] = "dead"

	BridgeService.DrownPlayer(player)
	evDied:FireClient(player)
	evSound:FireClient(player, "DrownSound")
	LeaderboardService.AddAttempt(player)

	task.delay(CONFIG.DROWN_DELAY, function()
		if humanoid.Health > 0 then humanoid.Health = 0 end
	end)

	task.delay(CONFIG.CLEANUP_DELAY, function()
		BridgeService.Cleanup(player)
	end)

	conn:Disconnect()
end

local function setupCharacter(player, character)
	PlankService.Init(player)

	local root     = character:WaitForChild("HumanoidRootPart")
	local humanoid = character:WaitForChild("Humanoid")

	BridgeService.FullCleanup(player)
	BridgeService.Init(player, root)
	syncPlanks(player)

	local dying = false

	BonusService.Init(player, character, function()
		syncPlanks(player)
	end)

	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not character.Parent or humanoid.Health <= 0 then
			conn:Disconnect()
			return
		end
		if dying then return end
		if playerStatus[player.UserId] ~= "alive" then return end

		local now = tick()
		if now - (lastStep[player.UserId] or 0) < CONFIG.HEARTBEAT_INTERVAL then return end
		lastStep[player.UserId] = now

		if BridgeService.IsOnWater(root, character) then
			local ok = BridgeService.PlacePlank(player, root)
			if ok then
				evSound:FireClient(player, "PlaceSound")
				syncPlanks(player)
			else
				dying = true
				handleDrown(player, character, humanoid, conn)
			end
		else
			BridgeService.ResetStep(player)
		end
	end)
end

-- Fire spawn planks to client once it signals ready.
evReady.OnServerEvent:Connect(function(player)
	if playerStatus[player.UserId] == "frozen"
		or playerStatus[player.UserId] == "alive" then
		evSpawnPlanks:FireClient(player)
	end
end)

-- Unfreeze player after countdown finishes.
evPlayerReady.OnServerEvent:Connect(function(player)
	if playerStatus[player.UserId] ~= "frozen" then return end
	local character = player.Character
	if not character then return end

	playerStatus[player.UserId] = "alive"
	CharacterLock.Unfreeze(character, CONFIG.WALK_SPEED, CONFIG.JUMP_POWER)
	LeaderboardService.Init(player)
end)

Players.PlayerAdded:Connect(function(player)
	-- Listen for plank pickup events from this player.
	local pickupConn = evPickup.OnServerEvent:Connect(function(plr, partName)
		if plr ~= player then return end
		if playerStatus[player.UserId] ~= "alive" then return end

		local now = tick()
		if now - (pickupDebounce[player.UserId] or 0) < CONFIG.PICKUP_COOLDOWN then return end
		pickupDebounce[player.UserId] = now

		if type(partName) ~= "string" then return end
		local amount = templateData[partName]
		if not amount then return end

		PlankService.Add(player, amount)
		syncPlanks(player)
		evCollect:FireClient(player, amount)
	end)

	local firstSpawn = true
	player.CharacterAdded:Connect(function(char)
		if not char.Parent then
			char.AncestryChanged:Wait()
		end

		if firstSpawn then
			-- First spawn: freeze and show countdown.
			firstSpawn = false
			playerStatus[player.UserId] = "frozen"
			CharacterLock.Freeze(char)
			evStartCountdown:FireClient(player)
		else
			-- Respawn after death: resume immediately.
			playerStatus[player.UserId] = "alive"
			LeaderboardService.Respawn(player)
			BonusService.ResetDebounce(player)
		end

		setupCharacter(player, char)
		CollisionGroups.Init(player, char)
	end)

	player.AncestryChanged:Connect(function()
		if not player.Parent then
			pickupConn:Disconnect()
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	playerStatus[player.UserId]   = nil
	lastStep[player.UserId]       = nil
	pickupDebounce[player.UserId] = nil
	BridgeService.FullCleanup(player)
	PlankService.Cleanup(player)
	LeaderboardService.Remove(player)
end)