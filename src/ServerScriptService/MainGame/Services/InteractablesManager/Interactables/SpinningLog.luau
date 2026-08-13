--!nonstrict
-- SpinningLog.luau
-- One instance = one swinging log body (body_geom MeshPart) in Workspace.
-- Found by tag "SpinningLog" via CollectionService in InteractablesManager.
-- Non-lethal hazard: knocks the player away using the log's own swing
-- velocity as push direction, and drops all currently carried planks
-- (via PlankPenalty.Scatter — same helper already used for penalty walls).

local Players             = game:GetService("Players")
local Debris              = game:GetService("Debris")
local ServerScriptService = game:GetService("ServerScriptService")

local PlankPenalty = require(ServerScriptService.MainGame.Services.PlankPenalty)

-- ── Constants ─────────────────────────────────────────────────────────────────

local DEBOUNCE_TIME     = 1.5   -- sec: cooldown per player between hits
local BODYVELOCITY_TTL  = 0.2   -- sec: how long BodyVelocity stays before removal
local PUSH_SPEED        = 55    -- studs/s: horizontal knockback strength
local PUSH_UP           = 25    -- studs/s: vertical lift, independent of swing phase
local MIN_LOG_SPEED     = 0.5   -- studs/s: below this, log velocity is too weak to trust as a direction

-- ── Class ─────────────────────────────────────────────────────────────────────

local SwingingLog = {}
SwingingLog.__index = SwingingLog

-- Shared across all log instances so one player can't be hit by two logs at once
local debounce: { [number]: boolean } = {}

function SwingingLog.new(part: BasePart)
	local self = setmetatable({
		_part = part,
	}, SwingingLog)

	return self
end

-- ── Private ───────────────────────────────────────────────────────────────────

function SwingingLog:_onTouch(hit: BasePart)
	local character = hit.Parent
	local player    = Players:GetPlayerFromCharacter(character)
	if not player then return end
	if debounce[player.UserId] then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root     = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then return end
	if humanoid.Health <= 0 then return end

	debounce[player.UserId] = true

	-- Direction: use the log's own swing velocity so the knock reads as
	-- "hit by the log", not a random shove. Falls back to pushing straight
	-- away from the log if contact happens near the top of the swing,
	-- where tangential velocity is close to zero.
	local logVel     = self._part.AssemblyLinearVelocity
	local horizontal = Vector3.new(logVel.X, 0, logVel.Z)
	local pushDir: Vector3

	if horizontal.Magnitude > MIN_LOG_SPEED then
		pushDir = horizontal.Unit
	else
		local away = Vector3.new(
			root.Position.X - self._part.Position.X,
			0,
			root.Position.Z - self._part.Position.Z
		)
		pushDir = away.Magnitude > 0.01 and away.Unit or Vector3.new(1, 0, 0)
	end

	local launch = pushDir * PUSH_SPEED + Vector3.new(0, PUSH_UP, 0)

	local bv    = Instance.new("BodyVelocity")
	bv.Velocity = launch
	bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bv.P        = math.huge
	bv.Parent   = root
	Debris:AddItem(bv, BODYVELOCITY_TTL)

	-- Non-lethal: PlankPenalty.Scatter handles the scatter effect, sound,
	-- resetting the plank count, and the delayed re-sync so the toss
	-- animation has time to finish. No PlayerDied — character keeps playing.
	PlankPenalty.Scatter(player)

	task.delay(DEBOUNCE_TIME, function()
		debounce[player.UserId] = nil
	end)
end

-- ── Public ────────────────────────────────────────────────────────────────────

function SwingingLog:Start()
	self._part.Touched:Connect(function(hit)
		self:_onTouch(hit)
	end)
end

return SwingingLog