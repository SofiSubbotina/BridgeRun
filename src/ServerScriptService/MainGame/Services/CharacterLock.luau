-- CharacterLock
-- Shared helpers for freezing/unfreezing a character's movement.
-- Used by MainGame (countdown freeze) and FinishTrigger (finish freeze).

local CharacterLock = {}

-- Stops the character from moving.
-- zeroVelocity additionally kills existing momentum — needed on finish,
-- where the player must stop instantly instead of just losing control.
function CharacterLock.Freeze(character, zeroVelocity)
	local humanoid = character:FindFirstChild("Humanoid")
	local root      = character:FindFirstChild("HumanoidRootPart")

	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end

	if root then
		if zeroVelocity then
			root.AssemblyLinearVelocity  = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
		root.Anchored = true
	end
end

function CharacterLock.Unfreeze(character, walkSpeed, jumpPower)
	local humanoid = character:FindFirstChild("Humanoid")
	local root      = character:FindFirstChild("HumanoidRootPart")

	if humanoid then
		humanoid.WalkSpeed = walkSpeed
		humanoid.JumpPower = jumpPower
	end
	if root then
		root.Anchored = false
	end
end

return CharacterLock