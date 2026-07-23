--!nonstrict
-- Geyser.luau
-- Instantiated per-part by InteractablesManager via CollectionService tag "Geyser".
-- Works on any part regardless of where it lives in the hierarchy (per-level
-- folders, nested subfolders, etc.) — discovery is tag-based, not path-based.
--
-- Expected children on the part:
--   Beam folder (may contain nested subfolders) — the water column.
--     Beams start Enabled = false, faded in/out when triggered.
--   One ParticleEmitter (any name) — base mist/bubbling puff on trigger.
--     Rate = 0, Enabled = false at rest, fired via :Emit().
--   Sound named "GeyserSplash" — positional 3D splash, plays for everyone
--     nearby with distance falloff (not routed through a Remote).

local Players      = game:GetService("Players")
local Debris       = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

-- ── Constants ─────────────────────────────────────────────────────────────────

local LAUNCH_UP_FORCE   = 130  -- studs/s
local LAUNCH_SIDE_MIN   = 25   -- studs/s
local LAUNCH_SIDE_MAX   = 70   -- studs/s

local DEBOUNCE_TIME     = 1.0  -- sec
local BODYVELOCITY_TTL  = 0.2  -- sec

local CONTROL_LOCK_TIME = 0.6  -- sec: player can't steer with WASD during this
-- window, otherwise a held movement key overrides
-- the random kick the instant BodyVelocity expires

local COLUMN_FADE_IN_TIME  = 0.12 -- sec
local COLUMN_HOLD_TIME     = 0.25 -- sec: fully visible plateau between fades
local COLUMN_FADE_OUT_TIME = 0.45 -- sec: slower than fade-in, reads as "dying down"
local MIST_EMIT_COUNT      = 50

local rng = Random.new() -- separate generator, not shared math.random

-- ── Class ─────────────────────────────────────────────────────────────────────

local Geyser = {}
Geyser.__index = Geyser

-- Shared across all geyser instances so one player can't be launched twice
-- by two different geysers within the same debounce window.
local debounce: { [number]: boolean } = {}

-- Scales every keypoint's Transparency toward 1 (invisible) by `alpha`.
-- alpha=0 returns the original look, alpha=1 returns fully transparent —
-- used because TweenService can't tween NumberSequence properties directly,
-- so Beam fading has to be stepped by hand.
local function fadedTransparency(original: NumberSequence, alpha: number): NumberSequence
	local keypoints = {}
	for _, kp in ipairs(original.Keypoints) do
		local value = kp.Value + (1 - kp.Value) * alpha
		table.insert(keypoints, NumberSequenceKeypoint.new(kp.Time, value, kp.Envelope))
	end
	return NumberSequence.new(keypoints)
end

function Geyser.new(part: BasePart)
	local beamFolder = part:WaitForChild("Beam")

	-- GetDescendants (not GetChildren) so this still works if Beams end up
	-- nested in subfolders later, without touching this script.
	local beams = {}
	local beamBaseTransparency = {}
	for _, obj in ipairs(beamFolder:GetDescendants()) do
		if obj:IsA("Beam") then
			table.insert(beams, obj)
			beamBaseTransparency[obj] = obj.Transparency -- captured once, as authored in Properties
		end
	end

	-- By class, not by name — the emitter can be renamed freely in Properties.
	local mist = part:FindFirstChildOfClass("ParticleEmitter")

	local self = setmetatable({
		_part                 = part,
		_beams                = beams,
		_beamBaseTransparency = beamBaseTransparency,
		_mist                 = mist,
		_sound                = part:WaitForChild("GeyserSplash"),
		_fadeToken            = 0, -- lets a new trigger take over a fade already in progress
	}, Geyser)

	return self
end

-- ── Private ───────────────────────────────────────────────────────────────────

-- direction = true fades in (alpha 1 -> 0), false fades out (alpha 0 -> 1)
function Geyser:_fadeColumn(fadeIn: boolean, duration: number)
	self._fadeToken += 1
	local myToken = self._fadeToken

	local start = os.clock()
	while true do
		if myToken ~= self._fadeToken then return end -- a newer trigger took over

		local t = math.clamp((os.clock() - start) / duration, 0, 1)
		local eased = TweenService:GetValue(t, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		local alpha = fadeIn and (1 - eased) or eased

		for beam, baseTransparency in pairs(self._beamBaseTransparency) do
			beam.Transparency = fadedTransparency(baseTransparency, alpha)
		end

		if t >= 1 then break end
		task.wait()
	end
end

function Geyser:_playColumn()
	for _, beam in ipairs(self._beams) do
		beam.Enabled = true
	end

	self:_fadeColumn(true, COLUMN_FADE_IN_TIME)
	task.wait(COLUMN_HOLD_TIME)
	self:_fadeColumn(false, COLUMN_FADE_OUT_TIME)

	for _, beam in ipairs(self._beams) do
		beam.Enabled = false
	end
end

function Geyser:_onTouch(hit: BasePart)
	local character = hit.Parent
	local player    = Players:GetPlayerFromCharacter(character)
	if not player then return end
	if debounce[player.UserId] then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root     = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then return end
	if humanoid.Health <= 0 then return end

	debounce[player.UserId] = true

	-- Full-circle random direction: helps toward the path or hurts (off
	-- course / straight back) with equal odds — risk is the point.
	local angle      = rng:NextNumber() * math.pi * 2
	local sideForce  = rng:NextNumber(LAUNCH_SIDE_MIN, LAUNCH_SIDE_MAX)
	local sideVector = Vector3.new(math.cos(angle), 0, math.sin(angle)) * sideForce

	local launch = Vector3.new(sideVector.X, LAUNCH_UP_FORCE, sideVector.Z)

	local bv    = Instance.new("BodyVelocity")
	bv.Velocity = launch
	bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bv.P        = math.huge
	bv.Parent   = root
	Debris:AddItem(bv, BODYVELOCITY_TTL)

	local savedWalkSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = 0
	task.delay(CONTROL_LOCK_TIME, function()
		if humanoid and humanoid.Parent then
			humanoid.WalkSpeed = savedWalkSpeed
		end
	end)

	if self._mist then
		self._mist:Emit(MIST_EMIT_COUNT)
	end
	task.spawn(function()
		self:_playColumn()
	end)

	self._sound:Play()

	task.delay(DEBOUNCE_TIME, function()
		debounce[player.UserId] = nil
	end)
end

-- ── Public ────────────────────────────────────────────────────────────────────

function Geyser:Start()
	self._part.Touched:Connect(function(hit)
		self:_onTouch(hit)
	end)
end

return Geyser