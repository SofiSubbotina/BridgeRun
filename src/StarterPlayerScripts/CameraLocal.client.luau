local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local function setupCharacter(char)
	-- Unbind the old loop if it exists — otherwise each respawn adds
	-- a new one and they conflict with each other.
	RunService:UnbindFromRenderStep("FixedCamera")

	local hrp = char:WaitForChild("HumanoidRootPart")
	camera.CameraType = Enum.CameraType.Scriptable

	RunService:BindToRenderStep("FixedCamera", Enum.RenderPriority.Camera.Value, function()
		if not hrp or not hrp.Parent then return end
		local camPos = hrp.Position
			- hrp.CFrame.LookVector * 13
			+ Vector3.new(0, 10, 0)
		camera.CFrame = CFrame.new(camPos, hrp.Position + hrp.CFrame.LookVector * 10)
	end)
end

player.CharacterAdded:Connect(setupCharacter)
if player.Character then setupCharacter(player.Character) end