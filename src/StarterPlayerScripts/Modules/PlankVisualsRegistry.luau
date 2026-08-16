--!strict
-- PlankVisualsRegistry.luau
-- Single source of truth for "which physical plank Parts is userId X
-- currently carrying right now". Bridges PlankStack (builds/owns the
-- carried-stack Parts) and PlankScatterEffect (destroys them on impact)
-- without either script reaching into the other's internals.
--
-- Registration uses a GETTER FUNCTION, not a raw table reference,
-- because PlankStack reassigns its own `stack` table on respawn
-- (stack = {}) — a stored reference would go stale, a closure won't.

local Registry = {}

type Entry = {
	getPlanks: () -> { BasePart },
	scattering: boolean,
}

local entries: { [number]: Entry } = {}

function Registry.Register(userId: number, getPlanks: () -> { BasePart })
	entries[userId] = { getPlanks = getPlanks, scattering = false }
end

function Registry.Unregister(userId: number)
	entries[userId] = nil
end

-- Called by PlankScatterEffect to fetch what to scatter.
function Registry.GetPlanks(userId: number): { BasePart }
	local entry = entries[userId]
	if not entry then return {} end
	return entry.getPlanks()
end

-- While true, PlankStack must not rebuild/destroy this user's stack —
-- the planks are mid-flight from a scatter effect.
function Registry.IsScattering(userId: number): boolean
	local entry = entries[userId]
	return entry ~= nil and entry.scattering
end

function Registry.SetScattering(userId: number, value: boolean)
	local entry = entries[userId]
	if entry then entry.scattering = value end
end

return Registry