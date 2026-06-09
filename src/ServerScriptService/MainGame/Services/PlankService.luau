-- PlankService
-- Tracks plank counts for all active players on the server.
-- Intentionally minimal: validation and cooldowns live in the callers.

local PlankService = {}

local data = {}
-- data[userId] = { planks = 0 }

function PlankService.Init(player)
	data[player.UserId] = { planks = 0 }
end

-- Negative amount subtracts. Always clamps to >= 0.
function PlankService.Add(player, amount)
	local d = data[player.UserId]
	if not d then return 0 end

	d.planks = math.max(0, d.planks + amount)
	return d.planks
end

function PlankService.Get(player)
	local d = data[player.UserId]
	return d and d.planks or 0
end

function PlankService.Reset(player)
	local d = data[player.UserId]
	if d then d.planks = 0 end
end

function PlankService.Cleanup(player)
	data[player.UserId] = nil
end

return PlankService
