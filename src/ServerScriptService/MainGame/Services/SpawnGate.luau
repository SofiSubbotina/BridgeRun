--!strict
-- SpawnGate.luau
-- Shared "freeze character, wait for the client to actually confirm it's
-- in control, then unfreeze" flow — used for every character spawn that
-- must not start counting run time before the client is truly ready:
-- first spawn (full 3-2-1 countdown) and every respawn/restart (silent —
-- CountdownLocal fires PlayerReady immediately when told not to show the
-- countdown). Centralised here so this freeze/wait/unfreeze sequence
-- isn't copied into MainGame and FinishTrigger separately.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterLock = require(script.Parent.CharacterLock)

local remotes       = ReplicatedStorage:WaitForChild("Remotes")
local evPlayerReady = remotes:WaitForChild("PlayerReady")

local SpawnGate = {}

local CONFIG = {
	WALK_SPEED = 18,
	JUMP_POWER = 25,
}

-- pending[userId] = the connection currently waiting for that player's
-- next PlayerReady signal.
local pending: { [number]: RBXScriptConnection } = {}

-- Freezes `character`, waits for this specific player's next PlayerReady
-- event, then unfreezes and calls onReady(). If an earlier wait for the
-- same player is still pending, it's cancelled first so only the latest
-- spawn's callback ever fires.
function SpawnGate.AwaitReady(player: Player, character: Model, onReady: () -> ())
	SpawnGate.Cancel(player)

	CharacterLock.Freeze(character)

	local conn: RBXScriptConnection
	conn = evPlayerReady.OnServerEvent:Connect(function(readyPlayer)
		if readyPlayer ~= player then return end

		pending[player.UserId] = nil
		conn:Disconnect()

		if character.Parent then
			CharacterLock.Unfreeze(character, CONFIG.WALK_SPEED, CONFIG.JUMP_POWER)
		end

		onReady()
	end)

	pending[player.UserId] = conn
end

-- Cancels a pending wait, e.g. on PlayerRemoving. Safe to call even if
-- nothing is pending.
function SpawnGate.Cancel(player: Player)
	local conn = pending[player.UserId]
	if conn then
		conn:Disconnect()
		pending[player.UserId] = nil
	end
end

return SpawnGate