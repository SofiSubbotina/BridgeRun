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
local LethalHit           = require(script.Services.LethalHit)
local PlayerStatus       = require(script.Services.PlayerStatus)
local LevelProgress      = require(script.Services.LevelProgress)
local SpawnGate           = require(script.Services.SpawnGate)

local remotes          = ReplicatedStorage:WaitForChild("Remotes")
local evUpdate         = remotes:WaitForChild("PlankUpdate")
local evCollect        = remotes:WaitForChild("PlankCollected")
local evSound          = remotes:WaitForChild("PlaySound")
local evSpawnPlanks    = remotes:WaitForChild("SpawnPersonalPlanks")
local evPickup         = remotes:WaitForChild("PlankPickedUp")
local evReady          = remotes:WaitForChild("ClientReady")
local evStartCountdown = remotes:WaitForChild("StartCountdown")
local evLevelReset     = remotes:WaitForChild("LevelReset")

-- Plank amounts keyed by template name, used to validate pickup events.
-- PlanksTemplate is organised into per-level sub-folders (Level1, Level2, …).
local planksTemplate = ReplicatedStorage
	:WaitForChild("Clones")
	:WaitForChild("PlanksTemplate")

local templateData = {}
for _, levelFolder in ipairs(planksTemplate:GetChildren()) do
	local levelId = tonumber(levelFolder.Name:match("^Level(%d+)$")) or 1
	for _, part in ipairs(levelFolder:GetChildren()) do
		templateData[part] = {
		amount = part:GetAttribute("Planks") or 1,
		position = part.Position,
		levelId  = levelId,
		}
	end
end

local CONFIG = {
	DROWN_DELAY        = 1.5,  -- seconds before humanoid health is set to 0
	CLEANUP_DELAY      = 3,    -- seconds before bridge cleanup after death
	HEARTBEAT_INTERVAL = 0.05, -- minimum seconds between water checks per player
	PICKUP_COOLDOWN    = 0.3,  -- minimum seconds between plank pickup events
	PICKUP_MAX_DISTANCE = 10,   -- studs, server-side proximity check for pickup requests
}

local lastStep       = {}
local pickupDebounce = {}
local collectedPlanks = {}

local function syncPlanks(player)
	evUpdate:FireAllClients(player.UserId, PlankService.Get(player))
end

local function handleDrown(player, character, humanoid, conn)
    
	BridgeService.DrownPlayer(player)
	LethalHit.Kill(player, humanoid, { delay = CONFIG.DROWN_DELAY })

	task.delay(CONFIG.CLEANUP_DELAY, function()
		BridgeService.Cleanup(player)
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
	LeaderboardService.Pause(player) -- stop the run clock the instant they die
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

Players.PlayerAdded:Connect(function(player)
	AnalyticsService.Init(player)
	collectedPlanks[player.UserId] = {}
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

		local collected = collectedPlanks[player.UserId]
		if collected and collected[plankInstance] then return end
        if not LevelProgress.HasAccess(player, template.levelId) then return end

		local character = player.Character
		local root       = character and character:FindFirstChild("HumanoidRootPart")
		if not root then return end
		if (root.Position - template.position).Magnitude > CONFIG.PICKUP_MAX_DISTANCE then return end

		if collected then collected[plankInstance] = true end

		PlankService.Add(player, template.amount)
		syncPlanks(player)
		evCollect:FireClient(player, template.amount)
	end)

	local firstSpawn = true
	player.CharacterAdded:Connect(function(char)
		if not char.Parent then
			char.AncestryChanged:Wait()
		end

		-- The object is "frozen"; SpawnGate holds it in a frozen state until the client 
		-- confirms that control has been transferred to it. Time does not elapse during the loading process.
		PlayerStatus.Set(player, "frozen") 

		if firstSpawn then
			firstSpawn = false
			evStartCountdown:FireClient(player, true)
			SpawnGate.AwaitReady(player, char, function()
			PlayerStatus.Set(player, "alive")
			   CharacterLock.Freeze(char)
			   LeaderboardService.Init(player)
			end)
		else
			-- Respawn after death, or restart: run-finish state resets now,
			-- but the timer stays paused until SpawnGate confirms the client
			-- is actually ready (LeaderboardService.Resume runs it then).
			LeaderboardService.Respawn(player)
			BonusService.ResetDebounce(player)
            collectedPlanks[player.UserId] = {}

			LevelProgress.Reset(player) 
			evLevelReset:FireClient(player, LevelProgress.Get(player))

			evStartCountdown:FireClient(player, false)
			SpawnGate.AwaitReady(player, char, function()
				PlayerStatus.Set(player, "alive")
				LeaderboardService.Resume(player)
			end)
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
	SpawnGate.Cancel(player)
	lastStep[player.UserId]       = nil
	pickupDebounce[player.UserId] = nil
	collectedPlanks[player.UserId] = nil
	BridgeService.FullCleanup(player)
	PlankService.Cleanup(player)
	BonusService.Cleanup(player)
	LeaderboardService.Remove(player)
	AnalyticsService.Save(player)
end)