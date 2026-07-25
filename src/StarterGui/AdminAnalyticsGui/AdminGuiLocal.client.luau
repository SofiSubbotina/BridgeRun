-- AdminGuiLocal.client.luau
-- Admin-only panel showing player session analytics.
-- Toggled with F4. Destroys itself immediately for non-admin players.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local player = Players.LocalPlayer
local gui    = script.Parent

local DevConfig = require(ReplicatedStorage.DevConfig)

local isAdmin = false
for _, id in ipairs(DevConfig.ADMIN_USER_IDS) do
	if player.UserId == id then isAdmin = true end
end

if not isAdmin then
	gui:Destroy()
	return
end

local frame          = gui:WaitForChild("MainFrame")
local scroll         = frame:WaitForChild("RowsScroll")
local template       = scroll:WaitForChild("RowTemplate")
local refreshButton  = frame:WaitForChild("RefreshButton")

local getAnalytics = ReplicatedStorage.Remotes:WaitForChild("GetAnalytics")

local function clearRows()
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") and child ~= template then
			child:Destroy()
		end
	end
end

local function fillRow(row, data)
	row.NameLabel.Text     = data.name or "?"
	row.DurationLabel.Text = tostring(data.durationSeconds or 0) .. "s"
	row.AttemptsLabel.Text = tostring(data.attempts or 0)
	row.FinishedLabel.Text = data.finished and "✅" or "—"
	row.RegionLabel.Text   = data.region or "?"
end

local function refresh()
	local sessions = getAnalytics:InvokeServer()
	clearRows()

	if #sessions == 0 then
		return 
	end

	for _, data in ipairs(sessions) do
		local row = template:Clone()
		row.Visible = true
		row.Parent = scroll
		fillRow(row, data)
	end
end

refreshButton.MouseButton1Click:Connect(refresh)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.L then
		gui.Enabled = not gui.Enabled
	end
end)