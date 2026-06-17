--!strict
--[[
	Whirlpool.luau
	Represents a single whirlpool hazard placed on the water surface.

	Responsibilities:
		- Carves a funnel-shaped hole into Terrain water so the visual
		  model isn't occluded by Terrain Water rendering.
		- Clones and positions a pre-built funnel model
		  (ReplicatedStorage.Clones.<TemplateName>) and spins it in place.
		- Player hazard: an invisible Touched-trigger above the water that,
		  on contact, takes over the player's HumanoidRootPart, tweens it
		  toward the center, then kills the Humanoid.

	Usage:
		local Whirlpool = require(game.ServerStorage.Whirlpool)
		local pool = Whirlpool.new({ Position = Vector3.new(0, 0.06, 0) })
		pool:Start()
]]

local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Whirlpool = {}
Whirlpool.__index = Whirlpool

--[[
	All radius/depth/offset values are expressed at Scale = 1.
	They are multiplied by Scale once in .new(), so callers can
	resize an entire whirlpool with a single number.
]]
export type WhirlpoolConfig = {
	Position:      Vector3?, -- World position of the whirlpool center. Y MUST match the water surface height.
	PullRadius:    number?,  -- Radius (studs) of the player hazard zone.
	FunnelRadius:  number?,  -- Radius (studs) of the hole carved into Terrain.
	HoleDepth:     number?,  -- Depth (studs) of the hole carved into Terrain.
	KillRadius:    number?,  -- Distance (studs) from center where the player is pulled to before dying.
	Scale:         number?,  -- Uniform size multiplier applied to the model and all radii.
	RotationSpeed: number?,  -- Visual spin speed of the funnel model, in degrees/second.
	TriggerHeight: number?,  -- Vertical extent (studs) of the player kill-trigger.
	PullDuration:  number?,  -- Seconds to pull a caught player to KillRadius before killing them.
	TemplateName:  string?,  -- Name of the funnel model under ReplicatedStorage.Clones.
}

type Connection = RBXScriptConnection

export type Whirlpool = typeof(setmetatable(
	{} :: {
		Position:      Vector3,
		PullRadius:    number,
		FunnelRadius:  number,
		HoleDepth:     number,
		KillRadius:    number,
		Scale:         number,
		RotationSpeed: number,
		TriggerHeight: number,
		PullDuration:  number,
		TemplateName:  string,

		_active:      boolean,
		_connections: { Connection },
		_model:       Model?,
		_caught:      { [Model]: boolean },
	},
	Whirlpool
))

local DEFAULTS = {
	Position      = Vector3.new(0, 0, 0),
	PullRadius    = 40,
	FunnelRadius  = 15,
	HoleDepth     = 20,
	KillRadius    = 3,
	Scale         = 1,
	RotationSpeed = 60,
	TriggerHeight = 6,
	PullDuration  = 0.7,
	TemplateName  = "FunnelTemplate",
}

-- ─────────────────────────────────────────────────────────────────
-- Terrain carving
-- ─────────────────────────────────────────────────────────────────

--[[
	Carves a cone-shaped hole of Air into Terrain water beneath center,
	so the funnel model isn't hidden behind the Terrain Water render layer.
	The radius tapers toward the bottom to roughly match a funnel shape.
]]
local function carveHole(center: Vector3, radius: number, depth: number)
	local terrain   = workspace.Terrain
	local voxelSize = 4

	for y = 0, depth, voxelSize do
		local layerRadius = radius * (1 - (y / depth) * 0.7)
		terrain:FillCylinder(
			CFrame.new(center - Vector3.new(0, y, 0)),
			voxelSize,
			layerRadius,
			Enum.Material.Air
		)
	end
end

-- ─────────────────────────────────────────────────────────────────
-- Trigger construction
-- ─────────────────────────────────────────────────────────────────

--[[
	Builds an invisible, non-collidable cylinder centered on center.
	height controls how far above/below the water surface the trigger
	extends — needs to cover bridge/plank height.
]]
local function buildTrigger(center: Vector3, radius: number, height: number, parent: Instance): BasePart
	local trigger        = Instance.new("Part")
	trigger.Name         = "KillTrigger"
	trigger.Shape        = Enum.PartType.Cylinder
	trigger.Anchored     = true
	trigger.CanCollide   = false
	trigger.CanTouch     = true
	trigger.CastShadow   = false
	trigger.Transparency = 1
	trigger.Size         = Vector3.new(height, radius * 2, radius * 2)
	trigger.CFrame       = CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2)
	trigger.Parent       = parent
	return trigger
end

-- ─────────────────────────────────────────────────────────────────
-- Constructor
-- ─────────────────────────────────────────────────────────────────

function Whirlpool.new(config: WhirlpoolConfig?): Whirlpool
	local merged = {} :: any
	for key, defaultValue in DEFAULTS do
		local override = config and (config :: any)[key]
		merged[key] = if override ~= nil then override else defaultValue
	end

	-- Scale every spatial parameter once up front.
	local scale          = merged.Scale
	merged.FunnelRadius *= scale
	merged.PullRadius   *= scale
	merged.HoleDepth    *= scale
	merged.KillRadius   *= scale

	merged._active      = false
	merged._connections = {}
	merged._model       = nil
	merged._caught      = {}

	return setmetatable(merged, Whirlpool) :: any
end

-- ─────────────────────────────────────────────────────────────────
-- Player capture
-- ─────────────────────────────────────────────────────────────────

--[[
	Takes control of character, pulls it toward the whirlpool center
	over PullDuration seconds, then kills it. Idempotent: repeated
	calls for a character already caught are ignored.
]]
function Whirlpool._catchCharacter(self: Whirlpool, character: Model)
	if self._caught[character] then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp      = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not hrp then return end
	if humanoid.Health <= 0 then return end

	self._caught[character] = true

	-- Anchor the root part for the duration of the pull so neither
	-- water buoyancy nor plank-walking state can interfere.
	hrp.Anchored = true

	local center             = self.Position
	local horizontalOffset   = (hrp.Position - center) * Vector3.new(1, 0, 1)
	local horizontalDistance = horizontalOffset.Magnitude

	local targetHorizontal = if horizontalDistance > 0.01
		then center + horizontalOffset.Unit * self.KillRadius
		else center

	local targetPosition = Vector3.new(
		targetHorizontal.X,
		center.Y - self.HoleDepth * 0.3,
		targetHorizontal.Z
	)

	local pullTween = TweenService:Create(
		hrp,
		TweenInfo.new(self.PullDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
		{ CFrame = CFrame.new(targetPosition) }
	)
	pullTween:Play()

	pullTween.Completed:Connect(function()
		if humanoid.Parent and humanoid.Health > 0 then
			humanoid.Health = 0
		end
		self._caught[character] = nil
	end)

	-- Release claim if the player dies from something else mid-pull,
	-- so a respawned character isn't permanently marked as caught.
	humanoid.Died:Connect(function()
		self._caught[character] = nil
	end)
end

-- ─────────────────────────────────────────────────────────────────
-- Lifecycle
-- ─────────────────────────────────────────────────────────────────

function Whirlpool.Start(self: Whirlpool)
	if self._active then return end

	local center = self.Position

	local clones   = ReplicatedStorage:FindFirstChild("Clones")
	local template = clones and clones:FindFirstChild(self.TemplateName)
	if not template then
		warn(`[Whirlpool] Template '{self.TemplateName}' not found in ReplicatedStorage.Clones`)
		return
	end

	self._active = true

	carveHole(center, self.FunnelRadius, self.HoleDepth)

	local model  = (template :: Model):Clone()
	model.Name   = "WhirlpoolFunnel"
	model.Parent = workspace

	local primary: BasePart? = model.PrimaryPart
	if not primary then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				primary           = descendant
				model.PrimaryPart = descendant
				break
			end
		end
	end

	if primary then
		-- Preserve the model's authored orientation — only translate into place.
		local originalRotation = primary.CFrame.Rotation
		model:PivotTo(CFrame.new(center) * originalRotation)
	else
		warn("[Whirlpool] Template model has no BaseParts")
	end

	if self.Scale ~= 1 then
		model:ScaleTo(self.Scale)
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored   = true
			descendant.CanCollide = false
			descendant.CastShadow = false
		end
	end

	self._model = model

	-- Spin the visual model around its own vertical axis.
	table.insert(self._connections,
		RunService.Heartbeat:Connect(function(dt: number)
			if not self._active or not model.PrimaryPart then return end

			local rotation = CFrame.Angles(0, math.rad(self.RotationSpeed * dt), 0)
			local relative = CFrame.new(center):Inverse() * model:GetPivot()
			model:PivotTo(CFrame.new(center) * rotation * relative)
		end)
	)

	-- Player hazard: pull and kill on touch.
	local trigger = buildTrigger(center, self.PullRadius, self.TriggerHeight, model)
	table.insert(self._connections,
		trigger.Touched:Connect(function(hit: BasePart)
			local character = hit.Parent
			if character and character:FindFirstChildOfClass("Humanoid") then
				self:_catchCharacter(character :: Model)
			end
		end)
	)
end

return Whirlpool