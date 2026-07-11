--!strict
-- SpikeTrap.luau
-- One instance = one spike union in Workspace.
-- Found by tag "SpikeTrap" via CollectionService in InteractablesManager.
-- Each spike runs its own independent loop with a random start offset.

local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players")

local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
local evDied  = remotes:WaitForChild("PlayerDied")
local evSound = remotes:WaitForChild("PlaySound")

-- ── Constants ─────────────────────────────────────────────────────────────────

local WARN_TIME   = 1.0  -- sec: spike is below ground, about to rise
local RISE_TIME   = 0.3  -- sec: spike rises to full height
local ACTIVE_TIME = 1.5  -- sec: spike is up and kills on touch
local SINK_TIME   = 0.3  -- sec: spike retracts underground
local PAUSE_TIME  = 2.5  -- sec: spike is hidden, waiting for next cycle
local RISE_HEIGHT = 4    -- studs: how far the spike travels upward

-- ── Class ─────────────────────────────────────────────────────────────────────

local SpikeTrap = {}
SpikeTrap.__index = SpikeTrap

function SpikeTrap.new(part: BasePart)
	-- Store resting CFrame so we always tween from a known position
	local restCFrame = part.CFrame

	-- Hide spike underground at startup
	part.CFrame = restCFrame + Vector3.new(0, -RISE_HEIGHT, 0)

	local self = setmetatable({
		_part       = part,
		_restCFrame = restCFrame,
		_active     = false,
		_hit        = {} :: { [Model]: boolean },
	}, SpikeTrap)

	return self
end

-- ── Private ───────────────────────────────────────────────────────────────────

-- Tweens the spike to an absolute CFrame target and waits until complete
function SpikeTrap:_tweenTo(targetCFrame: CFrame, duration: number)
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local completed = false

	local tween = TweenService:Create(self._part, tweenInfo, { CFrame = targetCFrame })
	tween.Completed:Connect(function()
		completed = true
	end)
	tween:Play()

	local elapsed = 0
	while not completed do
		elapsed += task.wait(0.05)
		if elapsed > duration + 1 then break end
	end
end

-- Kills the player whose body part touched the spike
function SpikeTrap:_onTouch(hit: BasePart)
	if not self._active then return end

	local character = hit.Parent
	if not character or not character:IsA("Model") then return end
	if self._hit[character] then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end

	self._hit[character] = true

	evDied:FireClient(player)
	evSound:FireClient(player, "DrownSound")
	task.delay(0.1, function()
		if humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end)
end

-- ── Public ────────────────────────────────────────────────────────────────────

function SpikeTrap:Start()
	self._part.Touched:Connect(function(hit)
		self:_onTouch(hit)
	end)

	task.spawn(function()
		-- Random start offset so spikes don't all fire at the same time
		local offset = math.random(0, math.floor(PAUSE_TIME * 10)) / 10
		task.wait(offset)

		while true do
			task.wait(PAUSE_TIME)

			-- Rise to surface
			self:_tweenTo(self._restCFrame, RISE_TIME)
			self._active = true

			-- Active — kills on touch
			task.wait(ACTIVE_TIME)

			-- Retract underground
			self._active = false
			self._hit    = {}
			self:_tweenTo(self._restCFrame + Vector3.new(0, -RISE_HEIGHT, 0), SINK_TIME)
		end
	end)
end

return SpikeTrap