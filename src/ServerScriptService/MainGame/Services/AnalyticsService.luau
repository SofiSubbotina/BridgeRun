-- AnalyticsService.luau
-- Tracks per-session player stats (join time, attempts, finish status, region)
-- and persists them to DataStore as separate, non-overwriting records.

local AnalyticsService = {}

local Players            = game:GetService("Players")
local DataStoreService    = game:GetService("DataStoreService")
local LocalizationService = game:GetService("LocalizationService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DevConfig = require(ReplicatedStorage.DevConfig)

local sessionsStore = DataStoreService:GetDataStore("PlayerSessions_v1")

local CONFIG = {
	MAX_RETRIES = 3,
	KEY_PREFIX  = "session_",
}

local function isExcluded(player)
	for _, id in ipairs(DevConfig.ADMIN_USER_IDS) do
		if player.UserId == id then return true end
	end
	return false
end

-- In-memory data for sessions currently in progress.
local active = {}

function AnalyticsService.Init(player)
	if isExcluded(player) then return end

	active[player.UserId] = {
		name      = player.Name,
		joinTime  = os.time(),
		attempts  = 0,
		finished  = false,
		finishTime = nil,
	}
end

function AnalyticsService.AddAttempt(player)
	local d = active[player.UserId]
	if not d then return end
	d.attempts = d.attempts + 1
end

function AnalyticsService.RecordFinish(player, elapsed)
	local d = active[player.UserId]
	if not d then return end
	d.finished   = true
	d.finishTime = elapsed
end

-- Fetches the country/region code for the player. Never blocks Save()
-- from completing if the lookup fails — region is "nice to have", not critical.
local function getRegion(player)
	local ok, result = pcall(function()
		return LocalizationService:GetCountryRegionForPlayerAsync(player)
	end)
	if ok then return result end
	return "unknown"
end

local function saveWithRetry(key, data, attempt)
	attempt = attempt or 1
	local ok, err = pcall(function()
		sessionsStore:SetAsync(key, data)
	end)
	if not ok then
		warn("[AnalyticsService] Save failed, attempt", attempt, ":", err)
		if attempt < CONFIG.MAX_RETRIES then
			task.wait(2 ^ attempt)
			saveWithRetry(key, data, attempt + 1)
		end
	end
end

function AnalyticsService.Save(player)
	local d = active[player.UserId]
	if not d then return end
	active[player.UserId] = nil

	d.durationSeconds = os.time() - d.joinTime
	d.region          = getRegion(player)
	d.joinTime        = nil -- not needed in the stored record itself

	local key = CONFIG.KEY_PREFIX .. player.UserId .. "_" .. os.time()
	saveWithRetry(key, d)
end

-- Reads every stored session back out, for the admin GUI.
-- Can be slow with many entries — that's expected for manual/on-demand use.
function AnalyticsService.ListSessions()
	local list = {}

	local ok, pages = pcall(function()
		return sessionsStore:ListKeysAsync(CONFIG.KEY_PREFIX)
	end)
	if not ok then
		warn("[AnalyticsService] ListKeysAsync failed:", pages)
		return list
	end

	while true do
		for _, keyInfo in ipairs(pages:GetCurrentPage()) do
			local okGet, data = pcall(function()
				return sessionsStore:GetAsync(keyInfo.KeyName)
			end)
			if okGet and data then
				table.insert(list, data)
			end
		end
		if pages.IsFinished then break end
		local okAdv = pcall(function() pages:AdvanceToNextPageAsync() end)
		if not okAdv then break end
	end

	return list
end

return AnalyticsService