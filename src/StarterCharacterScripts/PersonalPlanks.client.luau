-- PersonalPlanks.client.luau
-- Manages the local player's collectible plank pickups.
-- Planks are organised by level under PlanksTemplate/Level1, Level2, etc.
-- Only planks belonging to unlocked levels are shown and interactable.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player  = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local evSpawnPlanks   = remotes:WaitForChild("SpawnPersonalPlanks")
local evPickup        = remotes:WaitForChild("PlankPickedUp")
local evReady         = remotes:WaitForChild("ClientReady")
local evLevelUnlocked = remotes:WaitForChild("LevelUnlocked")

local planksTemplate = ReplicatedStorage
	:WaitForChild("Clones")
	:WaitForChild("PlanksTemplate")

-- Per-player folder keeps workspace tidy and avoids name collisions.
local planksFolder = workspace:FindFirstChild("PersonalPlanks_" .. player.UserId)
if planksFolder then
	planksFolder:ClearAllChildren()
else
	planksFolder = Instance.new("Folder")
	planksFolder.Name   = "PersonalPlanks_" .. player.UserId
	planksFolder.Parent = workspace
end

-- ── State ─────────────────────────────────────────────────────────────────

local pool          = {} -- all pool entries across all levels
local unlockedLevel = 1  -- highest level currently unlocked for this client
local HIDE_POS      = CFrame.new(0, -500, 0) -- off-map position for inactive parts

-- ── Billboard ─────────────────────────────────────────────────────────────

local function attachBillboard(part, amount)
	if part:FindFirstChild("PlankBillboard") then return end

	local bb = Instance.new("BillboardGui")
	bb.Name           = "PlankBillboard"
	bb.Adornee        = part
	bb.Size           = UDim2.new(0, 70, 0, 36)
	bb.StudsOffset    = Vector3.new(0, 2, 0)
	bb.AlwaysOnTop    = false
	bb.LightInfluence = 0.3
	bb.MaxDistance    = 30
	bb.Parent         = part

	local bg = Instance.new("Frame", bb)
	bg.Size                   = UDim2.fromScale(1, 1)
	bg.BackgroundColor3       = Color3.fromRGB(25, 25, 25)
	bg.BackgroundTransparency = 0.2
	bg.BorderSizePixel        = 0
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 10)

	local stroke = Instance.new("UIStroke", bg)
	stroke.Color     = Color3.fromRGB(255, 200, 70)
	stroke.Thickness = 1.5

	local icon = Instance.new("TextLabel", bg)
	icon.Size                   = UDim2.new(0, 28, 1, 0)
	icon.Position               = UDim2.new(0, 2, 0, 0)
	icon.BackgroundTransparency = 1
	icon.Text                   = "🪵"
	icon.TextScaled             = true

	local label = Instance.new("TextLabel", bg)
	label.Size                   = UDim2.new(1, -32, 1, 0)
	label.Position               = UDim2.new(0, 32, 0, 0)
	label.BackgroundTransparency = 1
	label.Text                   = "+" .. tostring(amount)
	label.TextColor3             = Color3.fromRGB(255, 240, 180)
	label.TextScaled             = true
	label.Font                   = Enum.Font.GothamBold
	label.TextXAlignment         = Enum.TextXAlignment.Left
end

-- ── Pool ──────────────────────────────────────────────────────────────────

-- Builds pool entries from a single level folder.
local function buildPoolForLevel(levelFolder, levelId)
	for _, template in ipairs(levelFolder:GetChildren()) do
		local amount = template:GetAttribute("Planks") or 1

		local part = template:Clone()
		part.Anchored   = true
		part.CanCollide = false
		part.CanTouch   = false
		part.CFrame     = HIDE_POS
		part.Parent     = planksFolder

		attachBillboard(part, amount)

		table.insert(pool, {
			part         = part,
			templateName = template.Name,
			amount       = amount,
			templateCF   = template.CFrame,
			levelId      = levelId,
			connection   = nil,
		})
	end
end

-- Builds pool entries for all level folders found in PlanksTemplate.
local function buildPool()
	for _, levelFolder in ipairs(planksTemplate:GetChildren()) do
		local levelId = tonumber(levelFolder.Name:match("^Level(%d+)$"))
		if levelId then
			buildPoolForLevel(levelFolder, levelId)
		end
	end
end

-- ── Show / Hide ───────────────────────────────────────────────────────────

local function hideEntry(entry)
	entry.part.CFrame       = HIDE_POS
	entry.part.CanCollide   = false
	entry.part.CanTouch     = false
	entry.part.Transparency = 1

	if entry.connection then
		entry.connection:Disconnect()
		entry.connection = nil
	end
end

local function hideAll()
	for _, entry in ipairs(pool) do
		hideEntry(entry)
	end
end

-- Activates a single pool entry and connects its touch event.
local function showEntry(entry)
	local part = entry.part
	part.CFrame       = entry.templateCF
	part.CanCollide   = true
	part.CanTouch     = true
	part.Transparency = 0

	local debounce = false
	entry.connection = part.Touched:Connect(function(hit)
		if debounce then return end
		local char = player.Character
		if not char then return end
		if not hit:IsDescendantOf(char) then return end
		debounce = true

		-- Hide immediately on touch — server handles the actual count.
		hideEntry(entry)
		evPickup:FireServer(entry.templateName)
	end)
end

-- Shows all planks belonging to unlocked levels.
local function spawnMyPlanks()
	hideAll()

	for _, entry in ipairs(pool) do
		if entry.levelId <= unlockedLevel then
			showEntry(entry)
		end
	end
end

-- Shows planks belonging to a specific level (called on unlock).
local function spawnPlanksForLevel(levelId)
	for _, entry in ipairs(pool) do
		if entry.levelId == levelId then
			showEntry(entry)
		end
	end
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────

buildPool()

-- Spawn all currently unlocked planks on respawn.
evSpawnPlanks.OnClientEvent:Connect(spawnMyPlanks)

-- Spawn planks for the newly unlocked level.
evLevelUnlocked.OnClientEvent:Connect(function(levelId)
	unlockedLevel = levelId
	spawnPlanksForLevel(levelId)
end)

evReady:FireServer()

player.CharacterRemoving:Connect(hideAll)