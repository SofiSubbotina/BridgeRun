--!nonstrict
-- PredatorZone.luau
-- One instance = one zone Part with a child "Fish" MeshPart inside it.
-- Found by tag "PredatorFish" via CollectionService in InteractablesManager.
--
-- Idle: Fish tweens between random points inside the zone's bounds (X/Z
-- only, Y is fixed at spawn height). No Heartbeat runs while idle.
-- Occupied: Touched/TouchEnded tracks players currently in the zone.
-- Chasing runs on Heartbeat only while the zone is non-empty, and
-- re-targets the nearest player every tick.
-- Attack: DamageAmount and StealAmount are independent — either can be 0
-- to disable that half of the effect on a given zone. If a hit would
-- bring health to 0, PlankPenalty.ScatterOnDeath fires before the kill,
-- matching every other lethal trap in this project.

local RunService         = game:GetService("RunService")
local TweenService       = game:GetService("TweenService")
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlankPenalty  = require(ServerScriptService.MainGame.Services.PlankPenalty)
local LevelProgress = require(ServerScriptService.MainGame.Services.LevelProgress)

local remotes     = ReplicatedStorage:WaitForChild("Remotes")
local evDied       = remotes:WaitForChild("PlayerDied")
local evSound     = remotes:WaitForChild("PlaySound")
local bonusEffect = remotes:WaitForChild("BonusEffect")

-- ── Constants ────────────────────────────────────────────────────────────

local PATROL_MIN_WAIT   = 1.0
local PATROL_MAX_WAIT   = 2.5
local FACING_CORRECTION = CFrame.Angles(0, math.pi, 0) -- model's nose faces local +Z, not Roblox's default -Z

local ALIVE_PULSE_SCALE = 0.06 -- fraction of body size, constant idle "breathing" cue
local ALIVE_PULSE_TIME  = 0.8

-- ── Class ────────────────────────────────────────────────────────────────

local PredatorZone = {}
PredatorZone.__index = PredatorZone

function PredatorZone.new(zonePart: BasePart)
	local fish = zonePart:FindFirstChild("Fish")
	assert(fish and fish:IsA("BasePart"), "PredatorZone: child 'Fish' not found in " .. zonePart:GetFullName())

	local self = setmetatable({
		_zone = zonePart,
		_fish = fish,
		_fixedY = fish.Position.Y,

		_attackCooldown = zonePart:GetAttribute("AttackCooldown") or 1.5,
		_attackRange    = zonePart:GetAttribute("AttackRange") or 5,
		_chaseSpeed     = zonePart:GetAttribute("ChaseSpeed") or 12,
		_damageAmount   = zonePart:GetAttribute("DamageAmount") or 10,
		_stealAmount    = zonePart:GetAttribute("StealAmount") or 3,
		_levelId        = zonePart:GetAttribute("LevelId") or 1,

		_playersInZone = {} :: { [Player]: boolean },

		_chasing      = false,
		_cooldown     = false,
		_chaseConn    = nil :: RBXScriptConnection?,
		_currentTween = nil :: Tween?,
	}, PredatorZone)

	return self
end

-- ── Private: presence ─────────────────────────────────────────────────────

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

-- ── Private: patrol (Tween-driven, runs only while the zone is empty) ────

function PredatorZone:_randomPointInZone(): Vector3
	local size = self._zone.Size
	local cf   = self._zone.CFrame
	local dx = (math.random() - 0.5) * size.X
	local dz = (math.random() - 0.5) * size.Z
	local world = cf:PointToWorldSpace(Vector3.new(dx, 0, dz))
	return Vector3.new(world.X, self._fixedY, world.Z)
end

function PredatorZone:_startPatrol()
	if self._chasing then return end

	task.spawn(function()
		while not self:_hasPlayers() do
			local target = self:_randomPointInZone()
			local current = self._fish.Position
			local direction = target - current
			local flatDistance = Vector3.new(direction.X, 0, direction.Z).Magnitude
			local duration = math.max(flatDistance / (self._chaseSpeed * 0.4), 0.5)

			local goalCFrame
			if direction.Magnitude > 0.05 then
				goalCFrame = CFrame.lookAt(target, target + direction) * FACING_CORRECTION
			else
				goalCFrame = self._fish.CFrame - self._fish.CFrame.Position + target
			end

			local tween = TweenService:Create(
				self._fish,
				TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ CFrame = goalCFrame }
			)
			self._currentTween = tween
			tween:Play()
			tween.Completed:Wait()

			if self:_hasPlayers() then break end
			task.wait(math.random() * (PATROL_MAX_WAIT - PATROL_MIN_WAIT) + PATROL_MIN_WAIT)
		end
	end)
end

-- ── Private: attack ────────────────────────────────────────────────────────

function PredatorZone:_applyHit(player: Player)
	if not LevelProgress.HasAccess(player, self._levelId) then return end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	self._cooldown = true
	task.delay(self._attackCooldown, function()
		self._cooldown = false
	end)

	-- A damaging hit that would reach 0 HP must scatter planks before death,
	-- same requirement as every other lethal trap — TakeDamage() doesn't let
	-- us control that ordering, so the lethal case is handled manually here.
	local lethalHit = self._damageAmount > 0 and (humanoid.Health - self._damageAmount) <= 0

	if lethalHit then
		PlankPenalty.ScatterOnDeath(player)
		evDied:FireClient(player)
		evSound:FireClient(player, "DrownSound")
		humanoid.Health = 0
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

-- ── Private: chase (Heartbeat, only while the zone is occupied) ──────────

function PredatorZone:_startChase()
	if self._chaseConn then return end
	self._chasing = true

	if self._currentTween then
		self._currentTween:Cancel()
		self._currentTween = nil
	end

	self._chaseConn = RunService.Heartbeat:Connect(function(dt)
		if not self:_hasPlayers() then
			self._chaseConn:Disconnect()
			self._chaseConn = nil
			self._chasing = false
			self:_startPatrol()
			return
		end

		local target, distance = self:_nearestPlayer()
		if not target then return end

		local root = target.Character.HumanoidRootPart
		local current = self._fish.Position
		local toTarget = Vector3.new(root.Position.X - current.X, 0, root.Position.Z - current.Z)

		if toTarget.Magnitude > 0.1 then
			local step = toTarget.Unit * self._chaseSpeed * dt
			if step.Magnitude > toTarget.Magnitude then
				step = toTarget
			end
			local newPos = Vector3.new(current.X + step.X, self._fixedY, current.Z + step.Z)
			self._fish.CFrame = CFrame.lookAt(newPos, newPos + toTarget) * FACING_CORRECTION
		end

		if not self._cooldown and distance <= self._attackRange then
			self:_applyHit(target)
		end
	end)
end

-- ── Public ──────────────────────────────────────────────────────────────

function PredatorZone:Start()
	self._zone.Touched:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or self._playersInZone[player] then return end

		self._playersInZone[player] = true
		self:_startChase()
	end)

	self._zone.TouchEnded:Connect(function(hit)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if player then
			self._playersInZone[player] = nil
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._playersInZone[player] = nil
	end)

	local baseSize = self._fish.Size
	TweenService:Create(
		self._fish,
		TweenInfo.new(ALIVE_PULSE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Size = baseSize * (1 + ALIVE_PULSE_SCALE) }
	):Play()

	self:_startPatrol()
end

return PredatorZone