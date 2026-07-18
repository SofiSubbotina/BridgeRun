-- PlankStack.client.luau
-- Local player's carried stack + mirrored stacks on other players.
-- Other players' planks are WeldConstraint'd to their anchor —
-- engine moves them automatically without per-frame script work.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local character = script.Parent
local humanoid  = character:WaitForChild("Humanoid")
local hrp       = character:WaitForChild("HumanoidRootPart")
local animator  = humanoid:WaitForChild("Animator")
local template  = ReplicatedStorage:WaitForChild("Clones"):WaitForChild("PlankModel")

local remotes   = ReplicatedStorage:WaitForChild("Remotes")
local evUpdate  = remotes:WaitForChild("PlankUpdate")
local evDied    = remotes:WaitForChild("PlayerDied")
local evCollect = remotes:WaitForChild("PlankCollected")
local evPlaced  = remotes:WaitForChild("PlankPlaced")

local scattering = false

local carryAnim = Instance.new("Animation")
carryAnim.AnimationId = "rbxassetid://97938793322451"
local carryTrack = animator:LoadAnimation(carryAnim)
carryTrack.Priority = Enum.AnimationPriority.Action
carryTrack.Looped   = true

local MAX_VISUAL    = 100
local PLANK_GAP     = 0.16
local EFFECT_HEIGHT = 20
local THROW_TIME    = 0.18
local THROW_HEIGHT  = 3

local stack       = {}
local stackCount  = 0
local conn        = nil
local stackAnchor = nil
local motor       = nil

local otherStacks     = {}
local otherStacksConn = nil

local function createAnchor(char)
	local torso = char:FindFirstChild("UpperTorso")
		or char:FindFirstChild("Torso")
		or char:FindFirstChild("HumanoidRootPart")

	local anchor = Instance.new("Part")
	anchor.Name         = "StackAnchor"
	anchor.Size         = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.CanCollide   = false
	anchor.CanTouch     = false
	anchor.CanQuery     = false
	anchor.Anchored     = false
	anchor.Massless     = true
	anchor.Parent       = char

	local weld = Instance.new("Motor6D")
	weld.Name   = "StackMotor"
	weld.Part0  = torso
	weld.Part1  = anchor
	weld.C0     = CFrame.new(0, -0.2, -1.4) * CFrame.Angles(math.rad(-10), 0, 0)
	weld.Parent = torso

	return anchor, weld
end

-- Position before welding so the plank starts at the right offset.
local function weldPlankToAnchor(plank, anchor, index)
	plank.CFrame = anchor.CFrame * CFrame.new(0, (index - 1) * PLANK_GAP, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0  = anchor
	weld.Part1  = plank
	weld.Parent = plank
end

-- Heartbeat only checks for dead anchors — no CFrame updates needed
-- because WeldConstraints handle movement automatically.
local function startOtherStacksLoop()
	if otherStacksConn then
		otherStacksConn:Disconnect()
		otherStacksConn = nil
	end
	otherStacksConn = RunService.Heartbeat:Connect(function()
		for userId, data in pairs(otherStacks) do
			if not data.anchor or not data.anchor.Parent then
				for _, p in ipairs(data.stack) do
					if p and p.Parent then p:Destroy() end
				end
				if data.motor and data.motor.Parent then data.motor:Destroy() end
				otherStacks[userId] = nil
			end
		end
	end)
end

local function clear()
	if not scattering then
	for _, plank in ipairs(stack) do
		if plank and plank.Parent then plank:Destroy() end
	end
end
    scattering = false
	stack      = {}
	if conn then conn:Disconnect(); conn = nil end
	carryTrack:Stop()
	if motor and motor.Parent then motor:Destroy() end
	if stackAnchor and stackAnchor.Parent then stackAnchor:Destroy() end
	stackAnchor = nil
	motor       = nil
end

local function getDropTarget()
	local topIndex = math.min(stackCount, MAX_VISUAL)
	local pos = hrp.Position
		+ hrp.CFrame.LookVector * 2
		+ Vector3.new(0, 1 + topIndex * PLANK_GAP, 0)
	return CFrame.new(pos)
end

local function dropPlanksFromAbove(amount)
	for i = 1, math.min(amount, 10) do
		task.delay((i - 1) * 0.05, function()
			if not hrp or not hrp.Parent then return end
			local ghost = template:Clone()
			ghost.Anchored     = true
			ghost.CanCollide   = false
			ghost.Transparency = 0.2
			ghost.Parent       = workspace

			local targetCF = getDropTarget()
			ghost.CFrame = targetCF * CFrame.new(
				math.random(-3, 3) * 0.2,
				EFFECT_HEIGHT + (i * 0.8),
				0
			)

			local tween = TweenService:Create(ghost,
				TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ CFrame = targetCF, Transparency = 0 }
			)
			tween:Play()
			tween.Completed:Connect(function()
				local bounce = TweenService:Create(ghost,
					TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
					{ CFrame = targetCF * CFrame.new(0, 0.15, 0) }
				)
				bounce:Play()
				bounce.Completed:Connect(function() ghost:Destroy() end)
			end)
		end)
	end
end

local function rebuild(count)
	local visual = math.min(count, MAX_VISUAL)
	for i = visual + 1, #stack do
		if stack[i] and stack[i].Parent then stack[i]:Destroy() end
		stack[i] = nil
	end
	if not stackAnchor then
		stackAnchor, motor = createAnchor(character)
	end
	for i = #stack + 1, visual do
		local plank = template:Clone()
		plank.Anchored   = true
		plank.CanCollide = false
		plank.CanTouch   = false
		plank.CanQuery   = false
		plank.Parent     = character
		stack[i]         = plank
	end
	stackCount = count
	if visual > 0 then
		if not carryTrack.IsPlaying then carryTrack:Play() end
	else
		carryTrack:Stop()
	end
	if not conn then
		conn = RunService.RenderStepped:Connect(function()
			if scattering then return end
			if not stackAnchor or not stackAnchor.Parent then return end
			if not hrp or not hrp.Parent then return end
			for i, plank in ipairs(stack) do
				if plank and plank.Parent then
					plank.CFrame = stackAnchor.CFrame * CFrame.new(0, (i - 1) * PLANK_GAP, 0)
				end
			end
		end)
	end
end

local function animatePlankThrow(angle)
	if not hrp or not hrp.Parent then return end
	local stackHeight = math.min(stackCount, MAX_VISUAL) * PLANK_GAP
	local startPos = stackAnchor and stackAnchor.Parent
		and stackAnchor.Position + Vector3.new(0, stackHeight, 0)
		or hrp.Position + hrp.CFrame.LookVector * 1.4

	local look      = hrp.CFrame.LookVector
	local rootVel   = hrp.AssemblyLinearVelocity
	local endPos    = hrp.Position
		+ look * (2.8 + stackHeight * 0.4)
		+ Vector3.new(rootVel.X, 0, rootVel.Z) * THROW_TIME
		+ Vector3.new(0, -2.5, 0)
	local arcHeight = THROW_HEIGHT + stackHeight * 0.3

	local ghost = template:Clone()
	ghost.Anchored   = true
	ghost.CanCollide = false
	ghost.CanTouch   = false
	ghost.CanQuery   = false
	ghost.CFrame     = CFrame.new(startPos) * CFrame.Angles(0, angle or 0, 0)
	ghost.Parent     = workspace

	local elapsed = 0
	local throwConn
	throwConn = RunService.RenderStepped:Connect(function(dt)
		elapsed = elapsed + dt
		local t = math.clamp(elapsed / THROW_TIME, 0, 1)
		local pos = startPos:Lerp(endPos, t)
			+ Vector3.new(0, arcHeight * math.sin(t * math.pi), 0)
		ghost.CFrame = CFrame.new(pos)
			* CFrame.Angles(0, angle or 0, 0)
			* CFrame.Angles(t * math.rad(-60), 0, 0)
		if t >= 1 then
			throwConn:Disconnect()
			ghost:Destroy()
		end
	end)
end

local function clearOtherStack(userId)
	local data = otherStacks[userId]
	if not data then return end
	for _, p in ipairs(data.stack) do
		if p and p.Parent then p:Destroy() end
	end
	if data.anchor and data.anchor.Parent then data.anchor:Destroy() end
	if data.motor and data.motor.Parent then data.motor:Destroy() end
	otherStacks[userId] = nil
end

local function updateOtherStack(userId, count)
	local otherPlayer = Players:GetPlayerByUserId(userId)
	if not otherPlayer then return end
	local char = otherPlayer.Character
	if not char then return end

	local visual = math.min(count, MAX_VISUAL)

	if visual <= 0 then
		clearOtherStack(userId)
		return
	end

	local data = otherStacks[userId]

	if not data then
		local anchor, mot = createAnchor(char)
		otherStacks[userId] = { stack = {}, anchor = anchor, motor = mot }
		data = otherStacks[userId]
	end

	-- Anchor belongs to old character (after respawn) — rebuild
	if not data.anchor or not data.anchor.Parent
		or not data.anchor:IsDescendantOf(char) then
		clearOtherStack(userId)
		local anchor, mot = createAnchor(char)
		otherStacks[userId] = { stack = {}, anchor = anchor, motor = mot }
		data = otherStacks[userId]
	end

	local current = #data.stack

	for i = current + 1, visual do
		local plank = template:Clone()
		plank.Anchored   = false
		plank.CanCollide = false
		plank.CanTouch   = false
		plank.CanQuery   = false
		plank.Parent     = char
		weldPlankToAnchor(plank, data.anchor, i)
		data.stack[i] = plank
	end

	for i = current, visual + 1, -1 do
		local plank = data.stack[i]
		if plank and plank.Parent then plank:Destroy() end
		data.stack[i] = nil
	end
end

-- ── Events ────────────────────────────────────────────────────────────────

evPlaced.OnClientEvent:Connect(function(_, angle)
	animatePlankThrow(angle)
end)

evCollect.OnClientEvent:Connect(function(amount)
	dropPlanksFromAbove(amount)
end)

evUpdate.OnClientEvent:Connect(function(userId, count)
	if userId == player.UserId then
		rebuild(count)
	else
		updateOtherStack(userId, count)
	end
end)

evDied.OnClientEvent:Connect(function()
	clear()
end)

local evWhirlpool = remotes:WaitForChild("WhirlpoolCatch")
evWhirlpool.OnClientEvent:Connect(function()
    scattering = true
	task.delay(3, function()
        scattering = false
	end)
end)

-- ── Lifecycle ─────────────────────────────────────────────────────────────

Players.PlayerRemoving:Connect(function(p)
	clearOtherStack(p.UserId)
end)

-- PlayerAdded only fires for players joining after this script starts,
-- so handle already-connected players separately.
for _, p in ipairs(Players:GetPlayers()) do
	if p ~= player then
		p.CharacterRemoving:Connect(function()
			clearOtherStack(p.UserId)
		end)
	end
end

Players.PlayerAdded:Connect(function(p)
	p.CharacterRemoving:Connect(function()
		clearOtherStack(p.UserId)
	end)
end)

player.CharacterAdded:Connect(function(newCharacter)
	character  = newCharacter
	humanoid   = character:WaitForChild("Humanoid")
	hrp        = character:WaitForChild("HumanoidRootPart")
	animator   = humanoid:WaitForChild("Animator")
	carryTrack = animator:LoadAnimation(carryAnim)
	carryTrack.Priority = Enum.AnimationPriority.Action
	carryTrack.Looped   = true
	clear()
	startOtherStacksLoop()
end)

startOtherStacksLoop()