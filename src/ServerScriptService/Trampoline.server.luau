-- Trampoline
-- Launches players upward when they touch a trampoline part.
-- Each trampoline part needs a LaunchVector attribute (Vector3).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")

local remotes      = ReplicatedStorage:WaitForChild("Remotes")
local evTrampoline = remotes:WaitForChild("TrampolineJump")
local evSound      = remotes:WaitForChild("PlaySound")

local CollectionService = game:GetService("CollectionService")
local debounce    = {}

local function setupTrampoline(part)
	if not part:IsA("BasePart") then return end
	part.Touched:Connect(function(hit)
		local character = hit.Parent
		local player    = Players:GetPlayerFromCharacter(character)
		if not player then return end
		if debounce[player.UserId] then return end

		local humanoid = character:FindFirstChild("Humanoid")
		local root     = character:FindFirstChild("HumanoidRootPart")
		if not humanoid or not root then return end
		if humanoid.Health <= 0 then return end

		debounce[player.UserId] = true

		-- Apply launch force via BodyVelocity, removed after 0.15s
		local launch = part:GetAttribute("LaunchVector") or Vector3.new(0, 80, 0)
		local bv     = Instance.new("BodyVelocity")
		bv.Velocity  = launch
		bv.MaxForce  = Vector3.new(math.huge, math.huge, math.huge)
		bv.P         = math.huge
		bv.Parent    = root
		Debris:AddItem(bv, 0.15)

		evTrampoline:FireAllClients(player.UserId)
		evSound:FireClient(player, "TrampolineSound")

		task.delay(0.5, function()
			debounce[player.UserId] = nil
		end)
	end)
end

-- Tag-based lookup: works regardless of where in the hierarchy the part lives
for _, part in ipairs(CollectionService:GetTagged("Trampoline")) do
	setupTrampoline(part)
end
CollectionService:GetInstanceAddedSignal("Trampoline"):Connect(setupTrampoline)