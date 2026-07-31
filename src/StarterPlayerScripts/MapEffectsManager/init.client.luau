-- MapEffectsManager.client.luau
-- Loads and starts all decorative, tag-driven map effects (rings, currents, etc).
-- To add a new effect: create a module in Effects/ and add one line here.
-- Mirrors the server-side InteractablesManager pattern, but for purely visual
-- effects that don't need per-instance gameplay state.

local TrampolineEffects  = require(script.Effects.TrampolineEffects)
local CurrentWaterEffect = require(script.Effects.CurrentWaterEffect)

TrampolineEffects.Start()
CurrentWaterEffect.Start()