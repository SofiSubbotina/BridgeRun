--!strict
-- LethalHit.luau
-- Single entry point for "kill this player right" — scatters any carried
-- planks, fires the death remotes, then zeroes health, either immediately
-- or after a delay (so a death animation/tween can finish first).
-- Every lethal trap that isn't Whirlpool needs this exact sequence in this
-- exact order — see the ordering note in PlankPenalty.ScatterOnDeath.
--
-- NOT used by Whirlpool: that trap has its own visual pull-to-center tween
-- and deliberately doesn't fire PlayerDied/DrownSound during the pull —
-- firing them here would double up with its own presentation.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlankPenalty = require(ServerScriptService.MainGame.Services.PlankPenalty)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local evDied  = remotes:WaitForChild("PlayerDied")
local evSound = remotes:WaitForChild("PlaySound")

local LethalHit = {}

export type KillOptions = {
	soundName: string?, -- defaults to "DrownSound" — correct for every current lethal trap, the player is always over water when they die
	delay: number?,     -- seconds before Health is actually zeroed; defaults to 0 (immediate)
}

function LethalHit.Kill(player: Player, humanoid: Humanoid, options: KillOptions?)
	local soundName = (options and options.soundName) or "DrownSound"
	local delay     = (options and options.delay) or 0

	-- MUST fire before Health = 0: PlankStack.client.luau clears carried
	-- planks the instant it sees PlayerDied, so the scatter signal has to
	-- land first or there's nothing left for it to scatter.
	PlankPenalty.ScatterOnDeath(player)
	evDied:FireClient(player)
	evSound:FireClient(player, soundName)

	if delay > 0 then
		task.delay(delay, function()
			if humanoid.Health > 0 then
				humanoid.Health = 0
			end
		end)
	else
		humanoid.Health = 0
	end
end

return LethalHit