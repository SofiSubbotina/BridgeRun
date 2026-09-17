--!nonstrict
-- PredatorZone.luau
-- One instance = one zone Part with a child "Fish" MeshPart inside it.
-- Found by tag "PredatorFish" via CollectionService in InteractablesManager.
--
-- Two update rates, chosen by whether a player is currently in the zone:
--   - idle (patrolling): ticked on a slow shared loop (PATROL_TICK_RATE) —
--     nobody is watching closely, so this doesn't need frame precision.
--   - occupied (chasing): ticked on the shared Heartbeat, full rate —
--     needed for accurate hit detection and responsive movement.
-- The idle set can grow with the number of traps in the game; the chasing
-- set is bounded by how many players are inside a trap zone at once, so
-- total cost doesn't scale with total trap count.

local RunService         = game:GetService("RunService")
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LethalHit      = require(ServerScriptService.MainGame.Services.LethalHit)
local PlankPenalty  = require(ServerScriptService.MainGame.Services.PlankPenalty)  -- needed for the non-lethal Steal() branch below
local LevelProgress = require(ServerScriptService.MainGame.Services.LevelProgress)

local remotes     = ReplicatedStorage:WaitForChild("Remotes")
local evSound     = remotes:WaitForChild("PlaySound")
local bonusEffect = remotes:WaitForChild("BonusEffect")

local FACING_CORRECTION = CFrame.Angles(0, math.pi, 0) -- fish mesh front faces +Z

local PATROL_SPEED     = 6 -- independent of each zone's ChaseSpeed attribute
local PATROL_MIN_WAIT  = 1.0
local PATROL_MAX_WAIT  = 2.5
local PATROL_TICK_RATE = 1 / 15 -- idle zones update 15x/sec, not 60x/sec
local ARRIVE_THRESHOLD = 0.5

local TURN_SPEED = 8 -- how fast the fish turns to face its travel direction

local PredatorZone = {}
PredatorZone.__index = PredatorZone

-- Idle (patrolling) zones, ticked by the slow loop at the bottom.
local idleZones = {}
-- Occupied (chasing) zones, ticked every Heartbeat frame.
local chasingZones = {}

function PredatorZone.new(zonePart: BasePart)
	local fish = zonePart:FindFirstChild("Fish")
	assert(fish and fish:IsA("BasePart"), "PredatorZone: child 'Fish' not found in " .. zonePart:GetFullName())

	local levelId = zonePart:GetAttribute("LevelId")
	assert(levelId ~= nil, "PredatorZone: 'LevelId' attribute not set on " .. zonePart:GetFullName())

	local self = setmetatable({
		_zone = zonePart,
		_fish = fish,
		_fixedY = fish.Position.Y,

		_attackCooldown = zonePart:GetAttribute("AttackCooldown") or 1.5,
		_attackRange    = zonePart:GetAttribute("AttackRange") or 5,
		_chaseSpeed     = zonePart:GetAttribute("ChaseSpeed") or 12,
		_damageAmount   = zonePart:GetAttribute("DamageAmount") or 10,
		_stealAmount    = zonePart:GetAttribute("StealAmount") or 3,
		_levelId        = levelId,

		_playersInZone = {} :: { [Player]: boolean },

		-- Per-player attack cooldown: catching one player doesn't protect
		-- everyone else nearby — each player gets bitten independently,
		-- at most once per AttackCooldown for themselves.
		_cooldownUntil = {} :: { [Player]: number },

		-- "waiting" | "moving", only meaningful while in idleZones
		_state        = "waiting",
		_waitTimer    = 0,
		_patrolTarget = nil :: Vector3?,
	}, PredatorZone)

	return self
end

function PredatorZone:_hasPlayers(): boolean
	return next(self._playersInZone) ~= nil
end

function PredatorZone:_nearestPlayer(): (Player?, number)
	local nearest, nearestDist = nil, math.huge

	for player in self._playersInZone do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local dist = (self._fish.Position - root.Position).Magnitude
			if dist < nearestDist then
				nearest, nearestDist = player, dist
			end
		else
			self._playersInZone[player] = nil
		end
	end

	return nearest, nearestDist
end

function PredatorZone:_randomPointInZone(): Vector3
	local size = self._zone.Size
	local cf   = self._zone.CFrame
	local dx = (math.random() - 0.5) * size.X
	local dz = (math.random() - 0.5) * size.Z
	local world = cf:PointToWorldSpace(Vector3.new(dx, 0, dz))
	return Vector3.new(world.X, self._fixedY, world.Z)
end

-- Steps the fish one frame toward targetPos and smoothly turns it to face
-- its actual travel direction. Returns true once it has arrived.
function PredatorZone:_stepToward(targetPos: Vector3, speed: number, dt: number): boolean
	local current = self._fish.Position
	local toTarget = Vector3.new(targetPos.X - current.X, 0, targetPos.Z - current.Z)
	local distance = toTarget.Magnitude

	if distance <= ARRIVE_THRESHOLD then
		return true
	end

	local step = toTarget.Unit * speed * dt
	if step.Magnitude > distance then
		step = toTarget
	end
	local newPos = Vector3.new(current.X + step.X, self._fixedY, current.Z + step.Z)

	local desiredLook = CFrame.lookAt(newPos, newPos + toTarget) * FACING_CORRECTION
	local rotAlpha = math.clamp(TURN_SPEED * dt, 0, 1)
	local blendedRotation = self._fish.CFrame.Rotation:Lerp(desiredLook.Rotation, rotAlpha)

	self._fish.CFrame = CFrame.new(newPos) * blendedRotation

	return false
end

function PredatorZone:_applyHit(player: Player)
	if not LevelProgress.HasAccess(player, self._levelId) then return end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	self._cooldownUntil[player] = tick() + self._attackCooldown

	-- A damaging hit that would reach 0 HP must scatter planks before death,
	-- same as every other lethal trap. TakeDamage() doesn't let us control
	-- that ordering, so the lethal case is handled manually here.
	local lethalHit = self._damageAmount > 0 and (humanoid.Health - self._damageAmount) <= 0

	if lethalHit then
LethalHit.Kill(player, humanoid)
		return
	end

	local stolen = self._stealAmount > 0 and PlankPenalty.Steal(player, self._stealAmount) or 0
	if self._damageAmount > 0 then
		humanoid:TakeDamage(self._damageAmount)
	end

	if stolen > 0 or self._damageAmount > 0 then
		evSound:FireClient(player, "BitingFish")
	end

	local text
	if self._damageAmount > 0 and stolen > 0 then
		text = string.format("-%d HP\n-%d planks", self._damageAmount, stolen)
	elseif self._damageAmount > 0 then
		text = string.format("-%d HP", self._damageAmount)
	elseif stolen > 0 then
		text = string.format("-%d planks", stolen)
	end

	if text then
		bonusEffect:FireClient(player, "penalty", text, "MeanFish")
	end
end

-- Moves this zone from idle to chasing (or vice versa) when its player
-- occupancy flips. Called from Touched/TouchEnded, not from the tick loops.
function PredatorZone:_enterChase()
	idleZones[self] = nil
	chasingZones[self] = true
end

function PredatorZone:_exitChase()
	chasingZones[self] = nil
	idleZones[self] = true
	self._state = "waiting"
	self._waitTimer = math.random() * (PATROL_MAX_WAIT - PATROL_MIN_WAIT) + PATROL_MIN_WAIT
end

-- Called for zones in chasingZones, every Heartbeat frame.
function PredatorZone:_updateChase(dt: number)
	local target, distance = self:_nearestPlayer()
	if not target then return end

	local root = target.Character.HumanoidRootPart
	self:_stepToward(Vector3.new(root.Position.X, self._fixedY, root.Position.Z), self._chaseSpeed, dt)

	local cooldownUntil = self._cooldownUntil[target]
	local offCooldown   = not cooldownUntil or tick() >= cooldownUntil
	if offCooldown and distance <= self._attackRange then
		self:_applyHit(target)
	end
end

-- Called for zones in idleZones, on the slow shared loop.
function PredatorZone:_updatePatrol(dt: number)
	if self._state == "waiting" then
		self._waitTimer -= dt
		if self._waitTimer <= 0 then
			self._patrolTarget = self:_randomPointInZone()
			self._state = "moving"
		end
	elseif self._state == "moving" then
		local arrived = self:_stepToward(self._patrolTarget :: Vector3, PATROL_SPEED, dt)
		if arrived then
			self._state = "waiting"
			self._waitTimer = math.random() * (PATROL_MAX_WAIT - PATROL_MIN_WAIT) + PATROL_MIN_WAIT
		end
	end
end

function PredatorZone:Start()
	self._zone.Touched:Connect(function(hit)
		if hit.Name ~= "HumanoidRootPart" then return end

		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or self._playersInZone[player] then return end

		local wasEmpty = not self:_hasPlayers()
		self._playersInZone[player] = true
		if wasEmpty then
			self:_enterChase()
		end
	end)

	self._zone.TouchEnded:Connect(function(hit)
		if hit.Name ~= "HumanoidRootPart" then return end

		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player then return end

		self._playersInZone[player] = nil
		if not self:_hasPlayers() then
			self:_exitChase()
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local hadPlayer = self._playersInZone[player]
		self._playersInZone[player] = nil
		self._cooldownUntil[player] = nil
		if hadPlayer and not self:_hasPlayers() then
			self:_exitChase()
		end
	end)

	idleZones[self] = true
end

RunService.Heartbeat:Connect(function(dt)
	for zone in chasingZones do
		zone:_updateChase(dt)
	end
end)

task.spawn(function()
	while true do
		local dt = task.wait(PATROL_TICK_RATE)
		for zone in idleZones do
			zone:_updatePatrol(dt)
		end
	end
end)

return PredatorZone