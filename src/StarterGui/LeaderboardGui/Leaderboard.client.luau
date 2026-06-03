local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player        = Players.LocalPlayer
local remotes       = ReplicatedStorage:WaitForChild("Remotes")
local evLeaderboard = remotes:WaitForChild("LeaderboardUpdate")

local gui        = script.Parent
local panel      = gui:WaitForChild("Panel")
local top10List  = panel:WaitForChild("Top5List")
local activeList = panel:WaitForChild("ActiveList")

local function formatTime(seconds)
	if not seconds then return "--:--" end
	if seconds < 0 then seconds = 0 end
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%d:%05.2f", m, s)
end

local function ensureLayout(parent)
	if not parent:FindFirstChildOfClass("UIListLayout") then
		local l = Instance.new("UIListLayout", parent)
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Padding   = UDim.new(0, 2)
	end
end

local function makeRow(parent, index, name, timeText, color, isGold)
	local row = Instance.new("Frame")
	row.Size               = UDim2.new(1, 0, 0, 24)
	row.BackgroundColor3   = isGold
		and Color3.fromRGB(255, 200, 50)
		or  Color3.fromRGB(40, 40, 40)
	row.BackgroundTransparency = isGold and 0.1 or 0.35
	row.BorderSizePixel    = 0
	row.LayoutOrder        = index
	row.Parent             = parent
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

	local place = Instance.new("TextLabel", row)
	place.Size                   = UDim2.new(0, 16, 1, 0)
	place.Position               = UDim2.new(0, 4, 0, 0)
	place.BackgroundTransparency = 1
	place.Text                   = tostring(index)
	place.TextColor3             = Color3.fromRGB(255, 255, 255)
	place.Font                   = Enum.Font.GothamBold
	place.TextSize               = 11

	local timeL = Instance.new("TextLabel", row)
	timeL.Name                   = "Time"
	timeL.Size                   = UDim2.new(0, 59, 1, 0)
	timeL.Position               = UDim2.new(1, -72, 0, 0)
	timeL.BackgroundTransparency = 1
	timeL.Font                   = Enum.Font.GothamBold
	timeL.TextSize               = 11
	timeL.TextColor3             = color
	timeL.TextXAlignment         = Enum.TextXAlignment.Right
	timeL.Text                   = timeText

	local nameL = Instance.new("TextLabel", row)
	nameL.Size                   = UDim2.new(1, -94, 1, 0)
	nameL.Position               = UDim2.new(0, 22, 0, 0)
	nameL.BackgroundTransparency = 1
	nameL.Text                   = name
	nameL.TextColor3             = Color3.fromRGB(255, 255, 255)
	nameL.Font                   = Enum.Font.Gotham
	nameL.TextSize               = 11
	nameL.TextXAlignment         = Enum.TextXAlignment.Left
	nameL.ClipsDescendants       = true

	return row
end

local lastData    = {}
local activeTimer = {}

local function clearList(list)
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
end

local function updateLeaderboard(data)
	lastData = data

	local serverNow = data.serverTime
	activeTimer = {}
	for i, entry in ipairs(data.active) do
		if not entry.finished then
			activeTimer[i] = {
				elapsed    = serverNow and (serverNow - entry.startTime) or 0,
				receivedAt = tick(),
			}
		end
	end

	ensureLayout(top10List)
	ensureLayout(activeList)

	clearList(top10List)
	if #data.top10 == 0 then
		local empty = Instance.new("TextLabel", top10List)
		empty.Size                   = UDim2.new(1, 0, 0, 20)
		empty.BackgroundTransparency = 1
		empty.Text                   = "No records yet"
		empty.TextColor3             = Color3.fromRGB(180, 180, 180)
		empty.Font                   = Enum.Font.Gotham
		empty.TextSize               = 10
	else
		for i, entry in ipairs(data.top10) do
			makeRow(top10List, i, entry.name,
				formatTime(entry.bestTime),
				Color3.fromRGB(100, 255, 120),
				i == 1
			)
		end
	end

	clearList(activeList)
	for i, entry in ipairs(data.active) do
		local timeText, color
		if entry.finished then
			timeText = formatTime(entry.finishTime)
			color    = Color3.fromRGB(100, 255, 120)
		else
			local t  = activeTimer[i]
			timeText = t and formatTime(t.elapsed) or "0:00.00"
			color    = Color3.fromRGB(255, 255, 255)
		end
		makeRow(activeList, i, entry.name, timeText, color, false)
	end
end

RunService.Heartbeat:Connect(function()
	if not lastData.active then return end
	local rows = activeList:GetChildren()
	for i, entry in ipairs(lastData.active) do
		if not entry.finished then
			local t = activeTimer[i]
			if t then
				local current = t.elapsed + (tick() - t.receivedAt)
				for _, row in ipairs(rows) do
					if row:IsA("Frame") and row.LayoutOrder == i then
						local timeL = row:FindFirstChild("Time")
						if timeL then
							timeL.Text = formatTime(current)
						end
						break
					end
				end
			end
		end
	end
end)

evLeaderboard.OnClientEvent:Connect(updateLeaderboard)