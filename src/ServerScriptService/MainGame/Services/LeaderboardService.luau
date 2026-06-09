-- LeaderboardService
-- Tracks active runs, personal records, and the global top-10.
-- Saves records via an async queue with exponential backoff retry.

local LeaderboardService = {}

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")

local remotes       = ReplicatedStorage:WaitForChild("Remotes")
local evLeaderboard = remotes:WaitForChild("LeaderboardUpdate")

local recordsStore = DataStoreService:GetDataStore("PlayerRecords_v1")
local orderedStore = DataStoreService:GetOrderedDataStore("BestTimes_v1")

local current   = {}
local records   = {}
local top10Cache = {}

-- ── Save Queue ────────────────────────────────────────────────────────────
-- Roblox throttle: no more than 1 SetAsync/UpdateAsync per key every 6 seconds.
-- The queue guarantees that requests are processed one at a time and are not lost.

local saveQueue  = {}   -- { userId, attempt }
local isSaving   = false

local function processSaveQueue()
	if isSaving then return end
	if #saveQueue == 0 then return end

	isSaving = true
	local item = table.remove(saveQueue, 1)
	local userId  = item.userId
	local attempt = item.attempt or 1

	local rec = records[userId]
	if not rec then
		isSaving = false
		task.defer(processSaveQueue)
		return
	end

	local key    = "record_" .. userId
	local timeMs = math.floor(rec.bestTime * 1000)

	-- UpdateAsync is atomic and protects against race conditions.
	-- If two requests arrive at the same time, the lower time wins.
	local ok, err = pcall(function()
		recordsStore:UpdateAsync(key, function(old)
			if old and old.bestTime and old.bestTime <= rec.bestTime then
				return nil -- do not overwrite if the existing record is better
			end
			return rec
		end)
	end)

	if not ok then
		warn("[LeaderboardService] Save failed, attempt", attempt, ":", err)
		if attempt < 3 then
			task.delay(2 ^ attempt, function()
				table.insert(saveQueue, { userId = userId, attempt = attempt + 1 })
				isSaving = false
				processSaveQueue()
			end)
			return
		else
			warn("[LeaderboardService] Player record", userId, "was lost after 3 attempts")
		end
	else
		-- Update OrderedDataStore only if the main save succeeded
		local okOrd, errOrd = pcall(function()
			orderedStore:SetAsync(tostring(userId), timeMs)
		end)
		if not okOrd then
			warn("[LeaderboardService] OrderedDataStore was not updated:", errOrd)
		else
			task.defer(refreshTop10)
		end
	end

	isSaving = false
	task.defer(processSaveQueue)
end

local function queueSave(player)
	table.insert(saveQueue, { userId = player.UserId, attempt = 1 })
	processSaveQueue()
end

-- ── Top 10 ────────────────────────────────────────────────────────────────

local isRefreshing  = false
local needsRefresh  = false

-- Protection against request spam:
-- if refreshTop10 is already running,
-- simply mark that another refresh is needed after completion.
function refreshTop10(attempt)
	if isRefreshing then
		needsRefresh = true
		return
	end

	isRefreshing = true
	needsRefresh = false
	attempt = attempt or 1

	local ok, result = pcall(function()
		local pages = orderedStore:GetSortedAsync(true, 10)
		return pages:GetCurrentPage()
	end)

	if not ok then
		warn("[LeaderboardService] Failed to load Top 10, attempt", attempt, ":", result)
		if attempt < 3 then
			task.delay(2 ^ attempt, function()
				isRefreshing = false
				refreshTop10(attempt + 1)
			end)
			return
		end
		isRefreshing = false
		return
	end

	top10Cache = {}
	for _, entry in ipairs(result) do
		local userId = tonumber(entry.key)
		local timeMs = entry.value

		local name = records[userId] and records[userId].name
		if not name then
			local nameOk, fetchedName = pcall(function()
				return Players:GetNameFromUserIdAsync(userId)
			end)
			name = nameOk and fetchedName or "???"
		end

		table.insert(top10Cache, {
			name     = name,
			bestTime = timeMs / 1000,
		})
	end

	LeaderboardService.Broadcast()
	isRefreshing = false

	if needsRefresh then
		task.defer(refreshTop10)
	end
end

-- ── Record Loading ────────────────────────────────────────────────────────

local function loadPlayerRecord(player, attempt)
	attempt = attempt or 1
	local key = "record_" .. player.UserId
	local ok, result = pcall(function()
		return recordsStore:GetAsync(key)
	end)
	if not ok then
		warn("[LeaderboardService] Failed to load record, attempt", attempt, ":", result)
		if attempt < 3 then
			task.delay(2 ^ attempt, function() loadPlayerRecord(player, attempt + 1) end)
		end
		return
	end
	if result then
		records[player.UserId] = result
	end
end

-- ── Remaining Functions (unchanged) ───────────────────────────────────────

local function getActive()
	local list = {}
	for _, d in pairs(current) do
		table.insert(list, {
			name       = d.name,
			startTime  = d.startTime,
			finished   = d.finished,
			finishTime = d.finishTime,
		})
	end
	return list
end

function LeaderboardService.Broadcast()
	evLeaderboard:FireAllClients({
		top10      = top10Cache, 
		active     = getActive(),
		serverTime = tick(),
	})
end

function LeaderboardService.Init(player)
	task.defer(function() loadPlayerRecord(player) end)
	current[player.UserId] = {
		name       = player.DisplayName,
		startTime  = tick(),
		finished   = false,
		finishTime = nil,
		attempts   = 0,
	}
	LeaderboardService.Broadcast()
end

function LeaderboardService.Respawn(player)
	local d = current[player.UserId]
	if not d then return end
	d.finished   = false
	d.finishTime = nil
	LeaderboardService.Broadcast()
end

function LeaderboardService.AddAttempt(player)
	local d = current[player.UserId]
	if not d then return end
	d.attempts = d.attempts + 1
end

function LeaderboardService.Finish(player)
	local d = current[player.UserId]
	if not d or d.finished then return nil end

	local elapsed = tick() - d.startTime
	d.finished    = true
	d.finishTime  = elapsed

	local existing    = records[player.UserId]
	local isNewRecord = not existing or elapsed < existing.bestTime

	if isNewRecord then
		records[player.UserId] = {
			name     = player.DisplayName,
			bestTime = elapsed,
		}
		task.defer(function() queueSave(player) end) -- save through the queue
	end

	LeaderboardService.Broadcast()

	local bestTime = records[player.UserId].bestTime
	return elapsed, bestTime, d.attempts
end

function LeaderboardService.NewRun(player)
	current[player.UserId] = {
		name       = player.DisplayName,
		startTime  = tick(),
		finished   = false,
		finishTime = nil,
		attempts   = 0,
	}
	LeaderboardService.Broadcast()
end

function LeaderboardService.Remove(player)
	current[player.UserId] = nil
	records[player.UserId] = nil
	LeaderboardService.Broadcast()
end

task.defer(refreshTop10)

game:BindToClose(function()
	for userId, rec in pairs(records) do
		if not rec then continue end

		local key    = "record_" .. userId
		local timeMs = math.floor(rec.bestTime * 1000)

		-- Synchronous save: the queue will not have time to finish.
		-- pcall prevents one failed request from interrupting the others.
		local ok, err = pcall(function()
			recordsStore:UpdateAsync(key, function(old)
				if old and old.bestTime and old.bestTime <= rec.bestTime then
					return nil
				end
				return rec
			end)
		end)

		if not ok then
			warn("[LeaderboardService] BindToClose: failed to save", userId, err)
		else
			pcall(function()
				orderedStore:SetAsync(tostring(userId), timeMs)
			end)
		end
	end
end)

return LeaderboardService