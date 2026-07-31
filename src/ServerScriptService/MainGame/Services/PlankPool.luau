-- PlankPool.luau
-- Generic per-player object pool: clones a template in batches to avoid
-- spawning lag, then lets callers acquire/release instances instead of
-- creating/destroying them on every use. Knows nothing about planks,
-- bridges, or current zones specifically — BridgeService owns what the
-- pooled parts mean and what happens to them while active.

local PlankPool = {}

local CONFIG = {
	POOL_SIZE  = 100, -- Enough for the entire run
	POOL_BATCH = 20,  -- Clone() operations per frame during warmup
}

local pools = {}

-- Creates a pool for userId in batches of POOL_BATCH per frame.
-- Prevents server lag during spawning by spreading out Clone() calls:
-- 20 per frame instead of 100 in a single synchronous operation.
-- onReady() is called when the entire pool is prepared.
function PlankPool.Create(userId, template, parent, onReady)
	local pool = { free = {}, active = {}, ready = false }
	pools[userId] = pool

	local done = 0

	local function nextBatch()
		if not pools[userId] then return end

		for _ = 1, CONFIG.POOL_BATCH do
			done = done + 1
			if done > CONFIG.POOL_SIZE then
				pool.ready = true
				if onReady then onReady() end
				return
			end

			local p = template:Clone()
			p.Anchored     = true
			p.CanCollide   = false
			p.CanTouch     = false
			p.CFrame       = CFrame.new(0, -500, 0)
			p.Transparency = 1
			p.Parent       = parent
			table.insert(pool.free, p)
		end

		task.defer(nextBatch)
	end

	task.defer(nextBatch)
end

function PlankPool.IsReady(userId)
	local pool = pools[userId]
	return pool ~= nil and pool.ready
end

function PlankPool.Acquire(userId, cf, labelForWarning)
	local pool = pools[userId]
	if not pool or #pool.free == 0 then
		if pool and pool.ready then
			warn("[PlankPool] Pool is empty for", labelForWarning or userId, "- increase POOL_SIZE")
		end
		return nil
	end

	local p = table.remove(pool.free)
	table.insert(pool.active, p)

	p.CFrame       = cf
	p.Transparency = 0

	return p
end

function PlankPool.Release(userId, plank)
	local pool = pools[userId]

	if not pool then
		if plank and plank.Parent then
			plank:Destroy()
		end
		return
	end

	for i, p in ipairs(pool.active) do
		if p == plank then
			table.remove(pool.active, i)
			break
		end
	end

	-- Reset to resting state — callers may have changed the physical state
	-- while this instance was active (e.g. a current zone unanchored it).
	plank.Anchored               = true
	plank.CanCollide             = false
	plank.AssemblyLinearVelocity = Vector3.zero
	plank.CFrame                 = CFrame.new(0, -500, 0)
	plank.Transparency           = 1

	table.insert(pool.free, plank)
end

function PlankPool.Destroy(userId)
	local pool = pools[userId]
	if not pool then return end

	pool.ready = false

	for _, p in ipairs(pool.free) do
		if p and p.Parent then
			p:Destroy()
		end
	end

	for _, p in ipairs(pool.active) do
		if p and p.Parent then
			p:Destroy()
		end
	end

	pools[userId] = nil
end

return PlankPool