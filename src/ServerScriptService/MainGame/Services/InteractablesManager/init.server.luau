--!strict
-- InteractablesManager.luau
-- Finds all interactable objects by CollectionService tag and starts them.
-- To add a new mechanic: create a module in Interactables/ and add one line here.

local CollectionService = game:GetService("CollectionService")

local Interactables = script.Interactables

local REGISTRY = {
	{ tag = "SpikeTrap",  module = require(Interactables.SpikeTrap)  },
	{ tag = "Trampoline", module = require(Interactables.Trampoline) },
	-- { tag = "Geyser",    module = require(Interactables.Geyser)    },
	-- { tag = "Current",   module = require(Interactables.Current)   },
}

for _, entry in REGISTRY do
	-- Start all already-existing tagged instances
	for _, instance in CollectionService:GetTagged(entry.tag) do
		entry.module.new(instance):Start()
	end

	-- Auto-start instances added later (e.g. when a new level unlocks)
	CollectionService:GetInstanceAddedSignal(entry.tag):Connect(function(instance)
		entry.module.new(instance):Start()
	end)
end