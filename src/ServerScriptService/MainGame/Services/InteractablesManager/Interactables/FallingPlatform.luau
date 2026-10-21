--!nonstrict
-- FallingPlatform.luau
-- Platform bobs up and down at random. If a player is still standing on it
-- after being touched, it drops, then eases back to its swing position.
-- Found by tag "FallingPlatform" via CollectionService in InteractablesManager.
-- Part must be Anchored; needs a numeric LevelId attribute.

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local LevelProgress = require(ServerScriptService.MainGame.Services.LevelProgress)

-- ── Constants ─────────────────────────────────────────────────────────────────

local WARNING_TIME = 1.2 -- sec: from first touch to the drop
local FALL_TIME    = 1.5 -- sec: platform stays unanchored
local RETURN_TIME  = 1   -- sec: ease back into the swing

-- ── Class ─────────────────────────────────────────────────────────────────────

local FallingPlatform = {}
FallingPlatform.__index = FallingPlatform

local rng = Random.new()

-- All platforms share one Heartbeat and one clock (see bottom of file).
local platforms = {}
local clock = 0

function FallingPlatform.new(part: BasePart)
	return setmetatable({
		_part       = part,
		_baseCFrame = part.CFrame,
		_amplitude  = rng:NextNumber(3, 6),
		_speed      = rng:NextNumber(1, 3),
		_phase      = rng:NextNumber(0, math.pi * 2),
		_busy       = false, -- true while warning / falling / returning
	}, FallingPlatform)
end

-- ── Private ───────────────────────────────────────────────────────────────────

-- Where the platform should be right now if it were swinging undisturbed.
function FallingPlatform:_swingCFrame(): CFrame
	local offset = math.sin(clock * self._speed + self._phase) * self._amplitude
	return self._baseCFrame + Vector3.new(0, offset, 0)
end

function FallingPlatform:_isOccupied(): boolean
	for _, touching in self._part:GetTouchingParts() do
		local model = touching:FindFirstAncestorOfClass("Model")
		if model and Players:GetPlayerFromCharacter(model) then
			return true
		end
	end
	return false
end

function FallingPlatform:_fall()
	local part = self._part

	task.wait(WARNING_TIME)

	if self:_isOccupied() then
		part.Anchored = false
		part:SetNetworkOwner(nil) -- the fall is computed by the server, not by the player standing on it
		task.wait(FALL_TIME)

		part.AssemblyLinearVelocity  = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
		part.Anchored = true
	end

	-- Ease toward the LIVE swing position (not the start point),
	-- so there is no jump when swinging resumes.
	local from, elapsed = part.CFrame, 0
	while elapsed < RETURN_TIME do
		elapsed += RunService.Heartbeat:Wait()
		part.CFrame = from:Lerp(self:_swingCFrame(), math.min(elapsed / RETURN_TIME, 1))
	end

	self._busy = false
end

function FallingPlatform:_onTouch(hit: BasePart)
	if self._busy then return end

	local character = hit:FindFirstAncestorOfClass("Model")
	local player    = character and Players:GetPlayerFromCharacter(character)
	if not player then return end

	if not LevelProgress.HasAccess(player, self._part:GetAttribute("LevelId") or 1) then return end

	self._busy = true
	task.spawn(self._fall, self)
end

-- ── Public ────────────────────────────────────────────────────────────────────

function FallingPlatform:Start()
	self._part.Touched:Connect(function(hit)
		self:_onTouch(hit)
	end)
	platforms[self] = true
end

RunService.Heartbeat:Connect(function(dt)
	clock += dt
	for platform in platforms do
		if not platform._busy then
			platform._part.CFrame = platform:_swingCFrame()
		end
	end
end)

return FallingPlatform