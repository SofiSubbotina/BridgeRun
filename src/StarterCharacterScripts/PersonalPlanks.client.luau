local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player  = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local evSpawnPlanks = remotes:WaitForChild("SpawnPersonalPlanks")
local evPickup      = remotes:WaitForChild("PlankPickedUp")
local evReady       = remotes:WaitForChild("ClientReady")

local planksTemplate = ReplicatedStorage
	:WaitForChild("Clones")
	:WaitForChild("PlanksTemplate")

local planksFolder = workspace:FindFirstChild("PersonalPlanks_" .. player.UserId)
if planksFolder then
	planksFolder:ClearAllChildren()
else
	planksFolder = Instance.new("Folder")
	planksFolder.Name   = "PersonalPlanks_" .. player.UserId
	planksFolder.Parent = workspace
end

local myPlanks = {}

local function clearPlanks()
	for _, p in ipairs(myPlanks) do
		if p and p.Parent then p:Destroy() end
	end
	myPlanks = {}
	planksFolder:ClearAllChildren()
end

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

local function spawnMyPlanks()
	clearPlanks()

	for _, template in ipairs(planksTemplate:GetChildren()) do
		local p = template:Clone()
		p.CFrame     = template.CFrame
		p.Anchored   = true
		p.CanCollide = true
		p.CanTouch   = true
		p.Parent     = planksFolder

		local amount = p:GetAttribute("Planks") or 1
		attachBillboard(p, amount)

		local debounce = false
		p.Touched:Connect(function(hit)
			if debounce then return end
			local char = player.Character
			if not char then return end
			if not hit:IsDescendantOf(char) then return end
			debounce = true

			p.Transparency = 1
			p.CanCollide   = false
			p.CanTouch     = false

			-- Отправляем имя шаблона, сервер сам знает сколько досок
			evPickup:FireServer(template.Name)

			task.delay(0.1, function()
				if p and p.Parent then p:Destroy() end
			end)
		end)

		table.insert(myPlanks, p)
	end
end

evSpawnPlanks.OnClientEvent:Connect(function()
	spawnMyPlanks()
end)

evReady:FireServer()

player.CharacterRemoving:Connect(clearPlanks)
