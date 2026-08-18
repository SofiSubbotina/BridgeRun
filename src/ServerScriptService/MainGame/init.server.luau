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
local AnalyticsService = require(script.Services.AnalyticsService)
local PlankPenalty       = require(script.Services.PlankPenalty)
local PlayerStatus       = require(script.Services.PlayerStatus)

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
		templateData[part] = {
		amount = part:GetAttribute("Planks") or 1,
		position = part.Position,
		}
	end
end

local CONFIG = {
	WALK_SPEED         = 18,
	JUMP_POWER         = 25,
	DROWN_DELAY        = 1.5,  -- seconds before humanoid health is set to 0
	CLEANUP_DELAY      = 3,    -- seconds before bridge cleanup after death
	HEARTBEAT_INTERVAL = 0.05, -- minimum seconds between water checks per player
	PICKUP_COOLDOWN    = 0.3,  -- minimum seconds between plank pickup events
	PICKUP_MAX_DISTANCE = 10,   -- studs, server-side proximity check for pickup requests
}

local lastStep       = {}
local pickupDebounce = {}

local function syncPlanks(player)
	evUpdate:FireAllClients(player.UserId, PlankService.Get(player))
end

local function handleDrown(player, character, humanoid, conn)
    
	BridgeService.DrownPlayer(player)
	PlankPenalty.ScatterOnDeath(player)
	evDied:FireClient(player)
	evSound:FireClient(player, "DrownSound")

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
	humanoid.Died:Connect(function()
	LeaderboardService.AddAttempt(player)
	AnalyticsService.AddAttempt(player)
end)

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
		if PlayerStatus.Get(player) ~= "alive" then return end

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
	if PlayerStatus.Get(player) == "frozen"
		or PlayerStatus.Get(player) == "alive" then
		evSpawnPlanks:FireClient(player)
	end
end)

-- Unfreeze player after countdown finishes.
evPlayerReady.OnServerEvent:Connect(function(player)
	if PlayerStatus.Get(player) ~= "frozen" then return end
	local character = player.Character
	if not character then return end

	PlayerStatus.Set(player, "alive")
	CharacterLock.Unfreeze(character, CONFIG.WALK_SPEED, CONFIG.JUMP_POWER)
	LeaderboardService.Init(player)
end)

Players.PlayerAdded:Connect(function(player)
	AnalyticsService.Init(player)
	-- Listen for plank pickup events from this player.
	local pickupConn = evPickup.OnServerEvent:Connect(function(plr, plankInstance)
		if plr ~= player then return end
		if PlayerStatus.Get(player) ~= "alive" then return end

		local now = tick()
		if now - (pickupDebounce[player.UserId] or 0) < CONFIG.PICKUP_COOLDOWN then return end
		pickupDebounce[player.UserId] = now

		if typeof(plankInstance) ~= "Instance" then return end
		local template = templateData[plankInstance]
		if not template then return end

		local character = player.Character
		local root       = character and character:FindFirstChild("HumanoidRootPart")
		if not root then return end
		if (root.Position - template.position).Magnitude > CONFIG.PICKUP_MAX_DISTANCE then return end

		PlankService.Add(player, template.amount)
		syncPlanks(player)
		evCollect:FireClient(player, template.amount)
	end)

	local firstSpawn = true
	player.CharacterAdded:Connect(function(char)
		if not char.Parent then
			char.AncestryChanged:Wait()
		end

		if firstSpawn then
			-- First spawn: freeze and show countdown.
			firstSpawn = false
			PlayerStatus.Set(player, "frozen")
			CharacterLock.Freeze(char)
			evStartCountdown:FireClient(player)
		else
			-- Respawn after death: resume immediately.
			PlayerStatus.Set(player, "alive")
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
	PlayerStatus.Cleanup(player)
	lastStep[player.UserId]       = nil
	pickupDebounce[player.UserId] = nil
	BridgeService.FullCleanup(player)
	PlankService.Cleanup(player)
	BonusService.Cleanup(player)
	LeaderboardService.Remove(player)
	AnalyticsService.Save(player)
end)