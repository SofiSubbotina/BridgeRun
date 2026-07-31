-- CurrentWaterEffect.luau
-- Cycles the built-in Roblox water normal-map frames on every part tagged "Current",
-- so current zones read visually as flowing water.
-- Purely decorative — the actual push comes from AssemblyLinearVelocity set by
-- hand on the part in Properties, this script never touches physics.

local CollectionService = game:GetService("CollectionService")

local CurrentWaterEffect = {}

local FRAME_COUNT = 25
local FRAME_RATE  = 30 -- frames per second of the texture cycle

-- Cached per-part texture lists, so we don't re-scan GetChildren() every frame.
local textureGroups = {}

local function registerCurrentPart(part)
	if not part:IsA("BasePart") then return end

	local textures = {}
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Texture") then
			table.insert(textures, child)
		end
	end

	if #textures > 0 then
		table.insert(textureGroups, textures)
	end
end

function CurrentWaterEffect.Start()
	for _, part in ipairs(CollectionService:GetTagged("Current")) do
		registerCurrentPart(part)
	end
	CollectionService:GetInstanceAddedSignal("Current"):Connect(registerCurrentPart)

	task.spawn(function()
		local frame = 1
		while true do
			local texturePath = string.format("rbxasset://textures/water/normal_%02d.dds", frame)

			for _, textures in ipairs(textureGroups) do
				for _, tex in ipairs(textures) do
					tex.Texture = texturePath
				end
			end

			frame = frame % FRAME_COUNT + 1
			task.wait(1 / FRAME_RATE)
		end
	end)
end

return CurrentWaterEffect