-- Leaderboard.client.luau
-- Renders the top-10 records panel and the live active-players timer.
-- Receives LeaderboardData from the server via LeaderboardUpdate remote.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local remotes       = ReplicatedStorage:WaitForChild("Remotes")
local evLeaderboard = remotes:WaitForChild("LeaderboardUpdate")

local gui        = script.Parent
local panel      = gui:WaitForChild("Panel")
local topList  = panel:WaitForChild("Top5List")
local activeList = panel:WaitForChild("ActiveList")

-- ── Type definitions ──────────────────────────────────────────────────────

type LeaderboardEntry = {
	name:       string,
	elapsed:    number,   -- server-computed elapsed time at broadcast time (accounts for pauses)
	live:       boolean,  -- true while this run is actively counting, not paused or finished
	finishTime: number?,  -- elapsed seconds for this run, nil if still running
	finished:   boolean,
}
type LeaderboardData = {
	active:     { LeaderboardEntry },  -- all players currently in a run
	top:      { LeaderboardEntry },    -- all-time top scores from OrderedDataStore
}

-- Initialised with empty arrays so Heartbeat guard `lastData.active` is safe
-- before the first server broadcast arrives.
local lastData: LeaderboardData = { active = {}, top = {} }

-- Stores per-player timer state so the Heartbeat loop can interpolate live times.
local activeTimer = {}

-- Formats a time in seconds as "M:SS.mm" (e.g. "1:04.32").
local function formatTime(seconds)
	if not seconds then return "--:--" end
	if seconds < 0 then seconds = 0 end
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%d:%05.2f", m, s)
end

-- Adds a UIListLayout to `parent` if one doesn't already exist.
local function ensureLayout(parent)
	if not parent:FindFirstChildOfClass("UIListLayout") then
		local l = Instance.new("UIListLayout", parent)
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Padding   = UDim.new(0, 2)
	end
end

-- Creates a single leaderboard row with place number, player name, and time.
-- Gold background is applied to 1st place.
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

-- Removes all Frame children from a list container.
local function clearList(list)
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
end

-- ── Leaderboard update ────────────────────────────────────────────────────

local function updateLeaderboard(data: LeaderboardData)
	lastData = data

	-- Snapshot each active run's server-computed elapsed time so it can be
	-- interpolated locally between broadcasts without needing a shared clock.
	activeTimer = {}
	for i, entry in ipairs(data.active) do
		if not entry.finished then
			activeTimer[i] = {
				elapsed    = entry.elapsed,
				live       = entry.live,
				receivedAt = tick(),  -- local time of receipt for interpolation
			}
		end
	end

	ensureLayout(topList)
	ensureLayout(activeList)

	-- Rebuild top panel
	clearList(topList)
	if #data.top == 0 then
		local empty = Instance.new("TextLabel", topList)
		empty.Size                   = UDim2.new(1, 0, 0, 20)
		empty.BackgroundTransparency = 1
		empty.Text                   = "No records yet"
		empty.TextColor3             = Color3.fromRGB(180, 180, 180)
		empty.Font                   = Enum.Font.Gotham
		empty.TextSize               = 10
	else
		for i, entry in ipairs(data.top) do
			makeRow(topList, i, entry.name,
				formatTime(entry.bestTime),
				Color3.fromRGB(100, 255, 120),
				i == 1
			)
		end
	end

	-- Rebuild active-players panel
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

-- ── Live timer interpolation ──────────────────────────────────────────────

-- Updates the displayed time for each still-running player every frame,
-- interpolating locally so the timer looks smooth without server spam.
RunService.Heartbeat:Connect(function()
	if not lastData.active then return end
	local rows = activeList:GetChildren()
	for i, entry in ipairs(lastData.active) do
		if not entry.finished then
			local t = activeTimer[i]
			if t then
			    -- Paused runs (respawning/dead) hold at t.elapsed; live runs
				-- keep counting up from it locally between broadcasts.
				local current = t.elapsed and (t.elapsed + (tick() - t.receivedAt)) or t.elapsed
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