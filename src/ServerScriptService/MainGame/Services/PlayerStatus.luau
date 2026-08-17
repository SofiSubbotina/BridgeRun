--!strict
-- PlayerStatus.luau
-- Server-side lifecycle status per player: "frozen" | "alive" | "dead" | nil.
-- Single source of truth so multiple systems (pickup gate, drown gate,
-- countdown freeze) don't each track their own copy.

local PlayerStatus = {}

local status = {}

function PlayerStatus.Set(player: Player, value: string?)
	status[player.UserId] = value
end

function PlayerStatus.Get(player: Player): string?
	return status[player.UserId]
end

function PlayerStatus.Cleanup(player: Player)
	status[player.UserId] = nil
end

return PlayerStatus