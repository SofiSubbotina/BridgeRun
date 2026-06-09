-- AutoRun.client.luau
-- Forces the character forward and handles left/right steering.
-- Also syncs the trampoline flip animation across clients.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local character = script.Parent
local humanoid  = character:WaitForChild("Humanoid")
local hrp       = character:WaitForChild("HumanoidRootPart")
local animator  = humanoid:WaitForChild("Animator")

local remotes      = ReplicatedStorage:WaitForChild("Remotes")
local evTrampoline = remotes:WaitForChild("TrampolineJump")

local CountdownState = require(ReplicatedStorage:WaitForChild("CountdownState"))

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local FLIP_ID_R15 = "rbxassetid://72626603872884"
local FLIP_ID_R6  = "rbxassetid://75139835536167"

local flipId   = humanoid.RigType == Enum.HumanoidRigType.R15 and FLIP_ID_R15 or FLIP_ID_R6
local flipAnim = Instance.new("Animation")
flipAnim.AnimationId = flipId

local flipTrack = animator:LoadAnimation(flipAnim)
flipTrack.Priority = Enum.AnimationPriority.Action
flipTrack.Looped   = false

-- Cache tracks for other players — without this, every jump creates
-- a new AnimationTrack that is never cleaned up.
local otherFlipTracks = {}

evTrampoline.OnClientEvent:Connect(function(jumperId)
	if jumperId == player.UserId then
		flipTrack:Stop()
		flipTrack:Play()
	else
		local otherPlayer = Players:GetPlayerByUserId(jumperId)
		if not otherPlayer then return end
		local char = otherPlayer.Character
		if not char then return end
		local hum  = char:FindFirstChild("Humanoid")
		local anim = hum and hum:FindFirstChildOfClass("Animator")
		if not anim then return end

		local track = otherFlipTracks[jumperId]
		if not track then
			track = anim:LoadAnimation(flipAnim)
			track.Priority = Enum.AnimationPriority.Action
			track.Looped   = false
			otherFlipTracks[jumperId] = track
		end

		track:Stop()
		track:Play()
	end
end)

Players.PlayerRemoving:Connect(function(p)
	otherFlipTracks[p.UserId] = nil
end)

Players.PlayerAdded:Connect(function(p)
	p.CharacterRemoving:Connect(function()
		otherFlipTracks[p.UserId] = nil
	end)
end)

RunService.RenderStepped:Connect(function()
	if humanoid.Health <= 0 then return end

	if CountdownState.active then
		humanoid:Move(Vector3.zero, false)
		return
	end

	local fwd    = Vector3.new(hrp.CFrame.LookVector.X,  0, hrp.CFrame.LookVector.Z).Unit
	local right_ = Vector3.new(hrp.CFrame.RightVector.X, 0, hrp.CFrame.RightVector.Z).Unit
	local moveX  = 0

	if isMobile then
		local md = humanoid.MoveDirection
		if md.Magnitude > 0.1 then
			moveX = md:Dot(right_)
			moveX = math.clamp(moveX, -1, 1)
		end
	else
		local left  = UserInputService:IsKeyDown(Enum.KeyCode.A)
			or UserInputService:IsKeyDown(Enum.KeyCode.Left)
		local right = UserInputService:IsKeyDown(Enum.KeyCode.D)
			or UserInputService:IsKeyDown(Enum.KeyCode.Right)
		if left  then moveX = -1 end
		if right then moveX =  1 end
	end

	local dir = fwd + right_ * moveX * 0.6
	humanoid:Move(dir, false)
end)