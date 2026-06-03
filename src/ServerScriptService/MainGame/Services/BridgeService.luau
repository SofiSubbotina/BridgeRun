-- BridgeService
-- Manages the plank bridge: object pooling, water colliders,
-- and water detection using raycasts.

local BridgeService = {}

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local PlankService = require(script.Parent.PlankService)

local clones           = ReplicatedStorage:WaitForChild("Clones")
local plankTemplate    = clones:WaitForChild("PlankModel")
local colliderTemplate = clones:WaitForChild("WaterCollider")

local evPlaced = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlankPlaced")

local placedFolder = workspace:FindFirstChild("PlacedPlanks")
if not placedFolder then
	placedFolder = Instance.new("Folder")
	placedFolder.Name   = "PlacedPlanks"
	placedFolder.Parent = workspace
end

local collidersFolder = workspace:FindFirstChild("WaterColliders")
if not collidersFolder then
	collidersFolder = Instance.new("Folder")
	collidersFolder.Name   = "WaterColliders"
	collidersFolder.Parent = workspace
end

local CONFIG = {
	MIN_DIST     = 2.2,
	PLANK_Y      = -2.5,
	LOOK_OFFSET  = 2.6,
	FADE_DELAY   = 1.5,
	RETURN_DELAY = 2,
	POOL_SIZE    = 100, -- Enough for the entire run
	POOL_BATCH   = 20,  -- Clone() operations per frame during warmup
}

local pools  = {}
local placed = {}

-- ── IsOnWater Cache ────────────────────────────────────────────────────────
-- Raycasts are expensive, so run them at most once every 3 frames per player

local waterCache         = {}
local frameCount         = 0
local WATER_CACHE_FRAMES = 3

RunService.Heartbeat:Connect(function()
	frameCount = frameCount + 1
end)

-- ── Plank Pool ─────────────────────────────────────────────────────────────

-- Creates the pool in batches of POOL_BATCH per frame.
-- Prevents server lag during spawning by spreading out Clone() calls:
-- 20 per frame instead of 100 in a single synchronous operation.
-- onReady() is called when the entire pool is prepared.
local function createPool(player, onReady)
	local pool = { free = {}, active = {}, ready = false }
	pools[player.UserId] = pool

	local done = 0

	local function nextBatch()
		if not pools[player.UserId] then return end

		for _ = 1, CONFIG.POOL_BATCH do
			done = done + 1
			if done > CONFIG.POOL_SIZE then
				pool.ready = true
				if onReady then onReady() end
				return
			end

			local p = plankTemplate:Clone()
			p.Anchored     = true
			p.CanCollide   = false
			p.CanTouch     = false
			p.CFrame       = CFrame.new(0, -500, 0)
			p.Transparency = 1
			p.Parent       = placedFolder
			table.insert(pool.free, p)
		end

		task.defer(nextBatch)
	end

	task.defer(nextBatch)
end

local function acquirePlank(player, cf)
	local pool = pools[player.UserId]
	if not pool or #pool.free == 0 then
		if pool and pool.ready then
			warn("[BridgeService] Pool is empty for", player.Name, "- increase POOL_SIZE")
		end
		return nil
	end

	local p = table.remove(pool.free)
	table.insert(pool.active, p)

	p.CFrame       = cf
	p.Transparency = 0

	return p
end

local function releasePlank(player, plank)
	local pool = pools[player.UserId]

	if not pool then
		if plank and plank.Parent then
			plank:Destroy()
		end
		return
	end

	for i, p in ipairs(pool.active) do
		if p == plank then
			table.remove(pool.active, i)
			break
		end
	end

	plank.CFrame       = CFrame.new(0, -500, 0)
	plank.Transparency = 1

	table.insert(pool.free, plank)
end

local function destroyPool(player)
	local pool = pools[player.UserId]
	if not pool then return end

	pool.ready = false

	for _, p in ipairs(pool.free) do
		if p and p.Parent then
			p:Destroy()
		end
	end

	for _, p in ipairs(pool.active) do
		if p and p.Parent then
			p:Destroy()
		end
	end

	pools[player.UserId] = nil
end

-- ── Public Functions ───────────────────────────────────────────────────────

function BridgeService.Init(player, root)
	local col = colliderTemplate:Clone()

	col.Name       = tostring(player.UserId)
	col.Anchored   = true
	col.CanCollide = true
	col.Parent     = collidersFolder

	placed[player.UserId] = {
		parts    = {},
		lastPos  = nil,
		collider = col,
	}

	createPool(player)
end

function BridgeService.IsOnWater(root, character)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return false end

	local d = placed[player.UserId]
	if not d or not d.collider then return false end

	local cache = waterCache[player.UserId]

	if cache and (frameCount - cache.frame) < WATER_CACHE_FRAMES then
		return cache.result
	end

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { d.collider }
	params.FilterType = Enum.RaycastFilterType.Include

	local hit = workspace:Raycast(
		root.Position + Vector3.new(0, -1, 0),
		Vector3.new(0, -4, 0),
		params
	)

	local result = hit ~= nil

	waterCache[player.UserId] = {
		result = result,
		frame = frameCount,
	}

	return result
end

function BridgeService.PlacePlank(player, root)
	local d = placed[player.UserId]
	if not d then return false end

	local pool = pools[player.UserId]

	-- Pool is still warming up.
	-- Do not kill the player; simply skip placement.
	-- In practice the player is frozen by the countdown at this stage.
	if not pool or not pool.ready then
		return true
	end

	if PlankService.Get(player) <= 0 then
		return false
	end

	local look = root.CFrame.LookVector
	local pos = root.Position + look * CONFIG.LOOK_OFFSET + Vector3.new(0, CONFIG.PLANK_Y, 0)

	if d.lastPos then
		local dx = pos.X - d.lastPos.X
		local dz = pos.Z - d.lastPos.Z

		if math.sqrt(dx * dx + dz * dz) < CONFIG.MIN_DIST then
			return true
		end
	end

	d.lastPos = pos

	local angle = math.atan2(look.X, look.Z)
	local cf = CFrame.new(pos) * CFrame.Angles(0, angle, 0)

	local p = acquirePlank(player, cf)

	if not p then
		return true -- Pool is empty, do not kill the player
	end

	table.insert(d.parts, p)

	evPlaced:FireClient(player, pos, angle)

	task.delay(CONFIG.FADE_DELAY, function()
		if p.Transparency < 1 then
			p.Transparency = 0.5
		end
	end)

	task.delay(CONFIG.RETURN_DELAY, function()
		for i, part in ipairs(d.parts) do
			if part == p then
				table.remove(d.parts, i)
				break
			end
		end

		releasePlank(player, p)
	end)

	PlankService.Add(player, -1)

	return true
end

function BridgeService.DrownPlayer(player)
	local d = placed[player.UserId]
	if not d then return end

	if d.collider and d.collider.Parent then
		d.collider.CanCollide = false
	end
end

function BridgeService.ResetStep(player)
	local d = placed[player.UserId]

	if d then
		d.lastPos = nil
	end
end

function BridgeService.Cleanup(player)
	local d = placed[player.UserId]
	if not d then return end

	for _, p in ipairs(d.parts) do
		releasePlank(player, p)
	end

	d.parts = {}
	d.lastPos = nil

	if d.collider and d.collider.Parent then
		d.collider.CanCollide = true
	end
end

function BridgeService.FullCleanup(player)
	waterCache[player.UserId] = nil

	local d = placed[player.UserId]
	if not d then return end

	BridgeService.Cleanup(player)

	if d.collider and d.collider.Parent then
		d.collider:Destroy()
	end

	placed[player.UserId] = nil

	destroyPool(player)
end

return BridgeService