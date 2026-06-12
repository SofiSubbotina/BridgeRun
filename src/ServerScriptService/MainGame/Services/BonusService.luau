-- BonusService
-- Handles bonus and penalty wall collisions.
-- Parts in workspace/Bonuses need BonusType attribute: "multiply" or "penalty".
-- multiply parts also need BonusMultiplier (default 2).
-- penalty parts also need PenaltyPercent (default 0.5).

local BonusService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlankService      = require(script.Parent.PlankService)

local bonusFolder = workspace:FindFirstChild("Bonuses")
local bonusEffect = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BonusEffect")

local MAX_BONUS_DISTANCE = 8 -- studs, extra safety check on top of Touched

local debounce = {}

local function isPlayerNearPart(root, part)
	return (root.Position - part.Position).Magnitude <= MAX_BONUS_DISTANCE
end

function BonusService.Init(player, character, syncCallback)
	if not bonusFolder then return end

	debounce[player.UserId] = {}

	local root     = character:WaitForChild("HumanoidRootPart")
	local humanoid = character:WaitForChild("Humanoid")

	local conn
	conn = root.Touched:Connect(function(hit)
		if not hit:IsDescendantOf(bonusFolder) then return end

		local key = hit:GetFullName()
		if debounce[player.UserId] and debounce[player.UserId][key] then return end
		if not isPlayerNearPart(root, hit) then return end

		if debounce[player.UserId] then
			debounce[player.UserId][key] = true
		end

		local bonusType = hit:GetAttribute("BonusType")
		local current   = PlankService.Get(player)

		if bonusType == "multiply" then
			local multiplier = hit:GetAttribute("BonusMultiplier") or 2
			local bonus      = math.floor(current * (multiplier - 1))
			if bonus > 0 then
				PlankService.Add(player, bonus)
				syncCallback()
				bonusEffect:FireClient(player, "bonus", "+" .. bonus .. " 🪵", "BonusSound")
			end
		elseif bonusType == "penalty" then
			local percent = hit:GetAttribute("PenaltyPercent") or 0.5
			local penalty = math.floor(current * percent)
			if penalty > 0 then
				PlankService.Add(player, -penalty)
				syncCallback()
				bonusEffect:FireClient(player, "penalty", "-" .. penalty .. " 🪵", "PenaltySound")
			end
		end
	end)

	humanoid.Died:Connect(function()
		conn:Disconnect()
	end)
end

function BonusService.Cleanup(player)
	debounce[player.UserId] = nil
end

function BonusService.ResetDebounce(player)
    debounce[player.UserId] = {}
end

return BonusService