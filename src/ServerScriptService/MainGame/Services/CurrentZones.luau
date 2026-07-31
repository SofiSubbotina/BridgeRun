-- CurrentZones.luau
-- Tracks all parts tagged "Current" and answers whether a world point falls
-- inside one of them. Used by BridgeService to decide whether a freshly
-- placed plank should be let loose to physics instead of staying anchored.
-- The push itself is NOT scripted here — it comes from AssemblyLinearVelocity
-- set by hand in Properties on each zone part.

local CollectionService = game:GetService("CollectionService")

local CurrentZones = {}

local zones = {}

local function register(part)
	if not part:IsA("BasePart") then return end
	table.insert(zones, part)
end

for _, part in ipairs(CollectionService:GetTagged("Current")) do
	register(part)
end
CollectionService:GetInstanceAddedSignal("Current"):Connect(register)

-- Simple AABB check in the zone part's own local space — cheap, no physics query needed.
local function isPointInZone(point, part)
	local relative = part.CFrame:PointToObjectSpace(point)
	local half     = part.Size * 0.5
	return math.abs(relative.X) <= half.X
		and math.abs(relative.Z) <= half.Z
end

-- Returns the current-zone part containing `point`, or nil if none.
function CurrentZones.Find(point)
	for _, part in ipairs(zones) do
		if part.Parent and isPointInZone(point, part) then
			return part
		end
	end
	return nil
end

return CurrentZones