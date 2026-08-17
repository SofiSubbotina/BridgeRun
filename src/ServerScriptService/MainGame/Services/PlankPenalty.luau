--!strict
-- PlankPenalty.luau
-- Single entry point for "knocking planks out of the player's hands" —
-- used by any trap that needs to scatter carried planks.
--
-- Two variants:
--   Scatter(player)        — non-lethal traps (SwingingLog and similar):
--                             scatters planks AND resets the real server-side count,
--                             since the player survives and keeps playing with 0 planks.
--   ScatterOnDeath(player) — lethal traps (Whirlpool, SpikeTrap, future ones):
--                             only fires the scatter effect. The actual plank count reset
--                             happens naturally through PlankService.Init on respawn —
--                             calling PlankService.Reset here would be redundant.
--                             MUST be fired before the PlayerDied remote, or PlankStack's
--                             clear() on the client destroys the planks before they scatter.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local PlankService = require(ServerScriptService.MainGame.Services.PlankService)
local PlayerStatus = require(script.Parent.PlayerStatus)

local remotes   = ReplicatedStorage:WaitForChild("Remotes")
local evScatter = remotes:WaitForChild("WhirlpoolCatch") -- reused as a generic "scatter planks" signal
local evUpdate  = remotes:WaitForChild("PlankUpdate")
local evSound   = remotes:WaitForChild("PlaySound")

local SYNC_DELAY = 2 -- sec, gives the scatter animation time to play before the HUD/stack rebuild

local PlankPenalty = {}

-- Non-lethal: player keeps playing, so the server count is reset and the client
-- is told the truth about it a moment later — not a hardcoded 0, in case the
-- player already picked up a new plank during the delay.
function PlankPenalty.Scatter(player: Player, soundName: string?)
	evScatter:FireAllClients(player.UserId)
	evSound:FireClient(player, soundName or "PenaltySound")

	PlankService.Reset(player)

	task.delay(SYNC_DELAY, function()
		evUpdate:FireAllClients(player.UserId, PlankService.Get(player))
	end)
end

-- Lethal: no server-side reset needed, PlankService.Init on respawn handles it.
function PlankPenalty.ScatterOnDeath(player: Player)
	PlayerStatus.Set(player, "dead") 
	evScatter:FireAllClients(player.UserId)
end

return PlankPenalty