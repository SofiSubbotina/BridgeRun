--!nonstrict
-- LevelTransitionEffect.client.luau
-- Listens for LevelUnlocked and shows a fading "Level N" billboard
-- above the local player's head, with a sound cue.
-- Server sends nothing extra — LevelUnlocked already carries the level id.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")

local player  = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local evLevelUnlocked = remotes:WaitForChild("LevelUnlocked")

local sounds = workspace:WaitForChild("Sounds")

-- ── Constants ─────────────────────────────────────────────────────────────────

local HOLD_TIME  = 2.5  -- sec: how long the label stays at full opacity
local FADE_TIME  = 0.6  -- sec: fade in/out duration
local OFFSET_Y   = 3    -- studs: how far above the head the label floats
local SOUND_NAME = "LevelUpSound" -- must exist under workspace.Sounds

-- ── Private ───────────────────────────────────────────────────────────────────

-- Clone-and-play so this doesn't interrupt other sounds already playing,
-- same pattern as SoundClient uses for one-shot effects.
local function playLevelUpSound()
	local sound = sounds:FindFirstChild(SOUND_NAME)
	if not sound then
		warn("[LevelTransitionEffect] Sound not found:", SOUND_NAME)
		return
	end

	local clone = sound:Clone()
	clone.Parent = workspace
	clone:Play()
	Debris:AddItem(clone, clone.TimeLength + 0.5)
end

-- Builds and animates the billboard for one level-up event.
-- Reads player.Character at call time, so it survives death/respawn
-- between levels without needing a persistent character reference.
local function showLevelBillboard(levelId: number)
	local character = player.Character
	if not character then return end

	local head = character:FindFirstChild("Head")
	if not head then return end

	local billboard = Instance.new("BillboardGui")
	billboard.Name        = "LevelTransitionGui"
	billboard.Size        = UDim2.new(4, 0, 1.2, 0)
	billboard.StudsOffset = Vector3.new(0, OFFSET_Y, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee     = head
	billboard.Parent      = head

	local label = Instance.new("TextLabel")
	label.Name                   = "LevelLabel"
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font                   = Enum.Font.GothamBold
	label.TextScaled             = true
	label.Text                   = "Level " .. tostring(levelId)
	label.TextColor3             = Color3.fromRGB(255, 200, 70) -- Gold, matches project palette
	label.TextStrokeTransparency = 0.4
	label.TextTransparency       = 1 -- start invisible, tween in below
	label.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
	label.Parent                 = billboard

	local fadeIn = TweenService:Create(
		label,
		TweenInfo.new(FADE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ TextTransparency = 0, TextStrokeTransparency = 0 }
	)
	fadeIn:Play()

	playLevelUpSound()

	task.delay(FADE_TIME + HOLD_TIME, function()
		if not billboard.Parent then return end -- character may have died/respawned already

		local fadeOut = TweenService:Create(
			label,
			TweenInfo.new(FADE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		)
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			billboard:Destroy()
		end)
	end)
end

-- ── Public ────────────────────────────────────────────────────────────────────

evLevelUnlocked.OnClientEvent:Connect(function(levelId: number)
	showLevelBillboard(levelId)
end)