--!strict
--[[
	WhirlpoolManager.lua (Script, ServerScriptService)

	Data-driven spawner for Whirlpool instances. Designers place marker
	Parts under workspace.WhirlpoolMarkers; this script reads each
	marker's position and Attributes, spawns a configured Whirlpool, and
	hides the marker.

	Adding a new whirlpool requires NO code changes:
		1. Duplicate an existing marker Part inside workspace.WhirlpoolMarkers.
		2. Move it to the desired position (Y = water surface height).
		3. Optionally set Attributes to override any WhirlpoolConfig field
		   (PullRadius, Scale, RotationSpeed, TemplateName, ...).

	Attributes are matched 1:1 against Whirlpool.WhirlpoolConfig fields.
]]

local Whirlpool = require(game.ServerStorage.Whirlpool)

local MARKERS_FOLDER_NAME = "WhirlpoolMarkers"

local activeWhirlpools: { Whirlpool.Whirlpool } = {}

local function createFromMarker(marker: Instance)
	if not marker:IsA("BasePart") then
		return
	end

	local config: Whirlpool.WhirlpoolConfig = {
		Position = marker.Position,
	}

	for attributeName, attributeValue in marker:GetAttributes() do
		(config :: any)[attributeName] = attributeValue
	end

	local whirlpool = Whirlpool.new(config)
	whirlpool:Start()
	table.insert(activeWhirlpools, whirlpool)

	-- The marker only exists to define placement/config; hide it once
	-- the whirlpool has been spawned.
	marker.Transparency = 1
	marker.CanCollide = false
end

local function init()
	local folder = workspace:FindFirstChild(MARKERS_FOLDER_NAME)
	if not folder then
		warn(`[WhirlpoolManager] Folder '{MARKERS_FOLDER_NAME}' not found in workspace — no whirlpools spawned`)
		return
	end

	for _, marker in folder:GetChildren() do
		createFromMarker(marker)
	end

	print(`[WhirlpoolManager] Spawned {#activeWhirlpools} whirlpool(s)`)
end

init()

