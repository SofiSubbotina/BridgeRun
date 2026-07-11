--!strict
-- Trampoline.luau
-- One instance = one trampoline part in Workspace.
-- Found by tag "Trampoline" via CollectionService in InteractablesManager.
-- Launches the player using LaunchVector attribute on the part.

local Players       = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local remotes      = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
local evTrampoline = remotes:WaitForChild("TrampolineJump")
local evSound      = remotes:WaitForChild("PlaySound")

local LevelProgress = require(
	game:GetService("ServerScriptService").MainGame.Services.LevelProgress
)

-- ── Constants ─────────────────────────────────────────────────────────────────

local DEBOUNCE_TIME    = 0.5   -- sec: cooldown per player between jumps
local BODYVELOCITY_TTL = 0.15  -- sec: how long BodyVelocity stays before removal

-- ── Class ─────────────────────────────────────────────────────────────────────

local Trampoline = {}
Trampoline.__index = Trampoline

-- Shared debounce table across all trampoline instances
-- (one player can only trigger one trampoline at a time anyway)
local debounce: { [number]: boolean } = {}

function Trampoline.new(part: BasePart)
	local self = setmetatable({
		_part = part,
	}, Trampoline)

	return self
end

-- ── Private ───────────────────────────────────────────────────────────────────

function Trampoline:_onTouch(hit: BasePart)
	local character = hit.Parent
	local player    = Players:GetPlayerFromCharacter(character)
	if not player then return end
	if debounce[player.UserId] then return end

	local humanoid = character:FindFirstChild("Humanoid")
	local root     = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then return end
	if humanoid.Health <= 0 then return end

	-- Check if player has unlocked this trampoline's level
	if not LevelProgress.HasAccess(player, self._part:GetAttribute("LevelId") or 1) then return end

	debounce[player.UserId] = true

	-- Apply launch force using BodyVelocity
	local launch = self._part:GetAttribute("LaunchVector") or Vector3.new(0, 80, 0)
	local bv         = Instance.new("BodyVelocity")
	bv.Velocity      = launch
	bv.MaxForce      = Vector3.new(math.huge, math.huge, math.huge)
	bv.P             = math.huge
	bv.Parent        = root
	game:GetService("Debris"):AddItem(bv, BODYVELOCITY_TTL)

	-- Notify all clients so they can play the jump animation on the correct character
	evTrampoline:FireAllClients(player.UserId)
	-- Sound only to the jumping player — others hear 3D sound from the part
	evSound:FireClient(player, "TrampolineSound")

	task.delay(DEBOUNCE_TIME, function()
		debounce[player.UserId] = nil
	end)
end

-- ── Public ────────────────────────────────────────────────────────────────────

function Trampoline:Start()
	self._part.Touched:Connect(function(hit)
		self:_onTouch(hit)
	end)
end

return Trampoline