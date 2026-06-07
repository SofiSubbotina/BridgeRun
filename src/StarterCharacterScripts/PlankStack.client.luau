-- PlankStack.client.luau
-- Handles the visual plank stack carried by the local player,
-- and mirrors stacks on other players' characters.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local character = script.Parent

local humanoid = character:WaitForChild("Humanoid")
local hrp      = character:WaitForChild("HumanoidRootPart")
local animator = humanoid:WaitForChild("Animator")

local template = ReplicatedStorage:WaitForChild("Clones"):WaitForChild("PlankModel")

local remotes   = ReplicatedStorage:WaitForChild("Remotes")
local evUpdate  = remotes:WaitForChild("PlankUpdate")
local evDied    = remotes:WaitForChild("PlayerDied")
local evCollect = remotes:WaitForChild("PlankCollected")
local evPlaced  = remotes:WaitForChild("PlankPlaced")

-- Carry animation played while the player holds planks
local CARRY_ANIMATION_ID = "rbxassetid://97938793322451"
local carryAnim  = Instance.new("Animation")
carryAnim.AnimationId = CARRY_ANIMATION_ID
local carryTrack = animator:LoadAnimation(carryAnim)
carryTrack.Priority = Enum.AnimationPriority.Action
carryTrack.Looped   = true

local MAX_VISUAL    = 120   -- max planks shown visually (caps render cost)
local PLANK_GAP     = 0.16  -- vertical gap between planks in the stack
local EFFECT_HEIGHT = 20    -- height from which collected planks drop
local THROW_TIME    = 0.18  -- duration of the throw arc animation (seconds)
local THROW_HEIGHT  = 3     -- arc peak height when a plank is thrown

local stack       = {}
local stackCount  = 0
local conn        = nil
local stackAnchor = nil
local motor       = nil

local otherStacks     = {}
local otherStacksConn = nil

-- Creates an invisible anchor part welded to a character's torso.
-- Returns the anchor Part and the Motor6D weld.
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

-- Starts the shared loop that positions planks on other players.
local function startOtherStacksLoop()
	if otherStacksConn then
		otherStacksConn:Disconnect()
		otherStacksConn = nil
	end
	otherStacksConn = RunService.RenderStepped:Connect(function()
		for userId, data in pairs(otherStacks) do
			if not data.anchor or not data.anchor.Parent then
				for _, p in ipairs(data.stack) do
					if p and p.Parent then p:Destroy() end
				end
				if data.motor and data.motor.Parent then data.motor:Destroy() end
				otherStacks[userId] = nil
				continue
			end
			for i, plank in ipairs(data.stack) do
				if plank and plank.Parent then
					plank.CFrame = data.anchor.CFrame * CFrame.new(0, (i - 1) * PLANK_GAP, 0)
				end
			end
		end
	end)
end

-- Destroys the local player's visual stack and disconnects its update loop.
local function clear()
	for _, plank in ipairs(stack) do
		if plank and plank.Parent then plank:Destroy() end
	end
	stack      = {}
	stackCount = 0
	if conn then conn:Disconnect(); conn = nil end
	carryTrack:Stop()
	if motor and motor.Parent then motor:Destroy() end
	if stackAnchor and stackAnchor.Parent then stackAnchor:Destroy() end
	stackAnchor = nil
	motor       = nil
end

-- Returns the CFrame where a newly collected plank should land.
local function getDropTarget()
	local topIndex = math.min(stackCount, MAX_VISUAL)
	local pos = hrp.Position
		+ hrp.CFrame.LookVector * 2
		+ Vector3.new(0, 1 + topIndex * PLANK_GAP, 0)
	return CFrame.new(pos)
end

-- Ghost planks falling from above when planks are collected.
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
			local startCF  = targetCF * CFrame.new(
				math.random(-3, 3) * 0.2,
				EFFECT_HEIGHT + (i * 0.8),
				0
			)
			ghost.CFrame = startCF

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
				bounce.Completed:Connect(function()
					ghost:Destroy()
				end)
			end)
		end)
	end
end

-- Rebuilds the local stack to match `count` planks.
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

-- Arc animation of a plank being thrown forward when placed.
local function animatePlankThrow(angle)
	if not hrp or not hrp.Parent then return end

	local stackHeight = math.min(stackCount, MAX_VISUAL) * PLANK_GAP
	local startPos
	if stackAnchor and stackAnchor.Parent then
		startPos = stackAnchor.Position + Vector3.new(0, stackHeight, 0)
	else
		startPos = hrp.Position + hrp.CFrame.LookVector * 1.4
	end

	local look      = hrp.CFrame.LookVector
	local rootVel   = hrp.AssemblyLinearVelocity
	local extraDist = stackHeight * 0.4

	local endPos = hrp.Position
		+ look * (2.8 + extraDist)
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
		pos = pos + Vector3.new(0, arcHeight * math.sin(t * math.pi), 0)

		ghost.CFrame = CFrame.new(pos)
			* CFrame.Angles(0, angle or 0, 0)
			* CFrame.Angles(t * math.rad(-60), 0, 0)

		if t >= 1 then
			throwConn:Disconnect()
			ghost:Destroy()
		end
	end)
end

-- Removes the visual stack for a remote player.
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

-- Builds the visual plank stack on another player's character.
local function rebuildOtherStack(userId, count)
	local otherPlayer = Players:GetPlayerByUserId(userId)
	if not otherPlayer then return end
	local char = otherPlayer.Character
	if not char then return end

	clearOtherStack(userId)
	if count <= 0 then return end

	local anchor, mot = createAnchor(char)
	local visual = math.min(count, MAX_VISUAL)
	local stk = {}

	for i = 1, visual do
		local plank = template:Clone()
		plank.Anchored   = true
		plank.CanCollide = false
		plank.CanTouch   = false
		plank.CanQuery   = false
		plank.Parent     = char
		stk[i]           = plank
	end

	otherStacks[userId] = { stack = stk, anchor = anchor, motor = mot }
end

-- ── Remote event listeners ────────────────────────────────────────────────

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
		rebuildOtherStack(userId, count)
	end
end)

evDied.OnClientEvent:Connect(function()
	clear()
end)

-- ── Player lifecycle ──────────────────────────────────────────────────────

Players.PlayerRemoving:Connect(function(p)
	clearOtherStack(p.UserId)
end)

Players.PlayerAdded:Connect(function(p)
	p.CharacterRemoving:Connect(function()
		clearOtherStack(p.UserId)
	end)
end)

-- Re-initialise when the local player respawns
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