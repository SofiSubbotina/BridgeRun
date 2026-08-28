-- LeaderboardService
-- Tracks active runs, personal records, and the global top.
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
local topCache = {}

local CONFIG = {
	TOP_COUNT    = 20,  -- how many places in the top
	MAX_RETRIES  = 3,   -- how many attempts to save
}
-- ── Save Queue ────────────────────────────────────────────────────────────
-- Roblox throttle: no more than 1 SetAsync/UpdateAsync per key every 6 seconds.
-- The queue guarantees that requests are processed one at a time and are not lost.

local saveQueue  = {}   -- { userId, attempt }
local isSaving   = false

local refreshTop

local function processSaveQueue()
	if isSaving then return end
	if #saveQueue == 0 then return end

	isSaving = true
	local item = table.remove(saveQueue, 1)
	local userId  = item.userId
	local rec     = item.rec
	local attempt = item.attempt or 1

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
		if attempt < CONFIG.MAX_RETRIES then
			task.delay(2 ^ attempt, function()
				table.insert(saveQueue, { userId = userId, rec = rec, attempt = attempt + 1 })
				isSaving = false
				processSaveQueue()
			end)
			return
		else
			warn("[LeaderboardService] Рекорд игрока", userId, "потерян после", CONFIG.MAX_RETRIES, "попыток")
		end
	else
		-- Update OrderedDataStore only if the main save succeeded
		local okOrd, errOrd = pcall(function()
			orderedStore:SetAsync(tostring(userId), timeMs)
		end)
		if not okOrd then
			warn("[LeaderboardService] OrderedDataStore не обновлён:", errOrd)
		else
			task.defer(refreshTop)
		end
	end

	isSaving = false
	task.defer(processSaveQueue)
end

local function queueSave(player, rec)
	table.insert(saveQueue, { userId = player.UserId, rec = rec, attempt = 1 })
	processSaveQueue()
end

-- ── Top ────────────────────────────────────────────────────────────────

local isRefreshing  = false
local needsRefresh  = false

-- Protection against request spam:
-- if refreshTop is already running,
-- simply mark that another refresh is needed after completion.
refreshTop = function(attempt)
	if isRefreshing then
		needsRefresh = true
		return
	end

	isRefreshing = true
	needsRefresh = false
	attempt = attempt or 1

	local ok, result = pcall(function()
		local pages = orderedStore:GetSortedAsync(true, CONFIG.TOP_COUNT)
		return pages:GetCurrentPage()
	end)

	if not ok then
		warn("[LeaderboardService] Топ не загружен, попытка", attempt, ":", result)
		if attempt < CONFIG.MAX_RETRIES then
			task.delay(2 ^ attempt, function()
				isRefreshing = false
				refreshTop(attempt + 1)
			end)
			return
		end
		isRefreshing = false
		return
	end

	topCache = {}
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

		table.insert(topCache, {
			name     = name,
			bestTime = timeMs / 1000,
		})
	end

	LeaderboardService.Broadcast()
	isRefreshing = false

	if needsRefresh then
		task.defer(refreshTop)
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
		if attempt < CONFIG.MAX_RETRIES then
			task.delay(2 ^ attempt, function() loadPlayerRecord(player, attempt + 1) end)
		end
		return
	end
	if result then
		local existing = records[player.UserId]
		if not existing or result.bestTime < existing.bestTime then
		   records[player.UserId] = result
		end
	end
end

-- Elapsed = time already banked (accumulated) plus time since the current
-- segment started (startTime). startTime == nil means the timer is paused
-- (character loading in, or dead) and only `accumulated` counts. This is
-- what lets a respawn/restart's load time be excluded from the run.
local function elapsedFor(d)
	local live = d.startTime and (tick() - d.startTime) or 0
	return d.accumulated + live
end

local function getActive()
	local list = {}
	for _, d in pairs(current) do
		table.insert(list, {
			name       = d.name,
			elapsed    = elapsedFor(d),
			live       = d.startTime ~= nil,
			finished   = d.finished,
			finishTime = d.finishTime,
		})
	end
	return list
end

function LeaderboardService.Broadcast()
	evLeaderboard:FireAllClients({
		top      = topCache, 
		active     = getActive(),
	})
end

-- Called once the client confirms it's actually in control (via SpawnGate),
-- so the timer starts live immediately — no loading time is ever counted.
function LeaderboardService.Init(player)
	task.defer(function() loadPlayerRecord(player) end)
	current[player.UserId] = {
		name       = player.DisplayName,
		accumulated = 0,
		startTime  = tick(),
		finished   = false,
		finishTime = nil,
		attempts   = 0,
	}
	LeaderboardService.Broadcast()
end

-- Called right when the character respawns after death, before the client
-- has confirmed it's ready. Resets run-finish state but leaves the timer
-- paused (Pause() already ran on death) — SpawnGate calls Resume() once
-- the client actually has control.
function LeaderboardService.Respawn(player)
	local d = current[player.UserId]
	if not d then return end
	d.finished   = false
	d.finishTime = nil
	LeaderboardService.Broadcast()
end

-- Pauses the timer — called on death. Safe to call when already paused.
function LeaderboardService.Pause(player)
	local d = current[player.UserId]
	if not d or not d.startTime then return end
	d.accumulated += tick() - d.startTime
	d.startTime    = nil
	LeaderboardService.Broadcast()
end

-- Resumes a paused timer. Called by SpawnGate once the client confirms
-- it's actually in control of the character (respawn or restart).
function LeaderboardService.Resume(player)
	local d = current[player.UserId]
	if not d or d.startTime then return end
	d.startTime = tick()
	LeaderboardService.Broadcast()
end

function LeaderboardService.AddAttempt(player)
	local d = current[player.UserId]
	if not d then return end
	d.attempts = d.attempts + 1
end

function LeaderboardService.PeekElapsed(player)
	local d = current[player.UserId]
	if not d or d.finished then return nil end
	return elapsedFor(d)
end

function LeaderboardService.Finish(player)
	local d = current[player.UserId]
	if not d or d.finished then return nil end

	local elapsed = elapsedFor(d)
	d.finished    = true
	d.finishTime  = elapsed

	local existing    = records[player.UserId]
	local isNewRecord = not existing or elapsed < existing.bestTime

	if isNewRecord then
		local rec = {
			name     = player.DisplayName,
			bestTime = elapsed,
		}
		records[player.UserId] = rec
		-- rec passed by value into the queue so PlayerRemoving can't erase it before it's saved
		task.defer(function() queueSave(player, rec) end) 
	end

	LeaderboardService.Broadcast()

	local bestTime = records[player.UserId].bestTime
	return elapsed, bestTime, d.attempts
end

function LeaderboardService.NewRun(player)
	current[player.UserId] = {
		name       = player.DisplayName,
		accumulated = 0,
		startTime  = nil,
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

task.defer(refreshTop)

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