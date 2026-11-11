-- 孵化离线回归：验证落地、加速冷却、付费与自然孵化竞争及单次提交
--!strict
local Rules = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmHatchRules")
local Config = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmEconomyConfig")
local checks = 0
local function Check(value: boolean, message: string): () assert(value, message); checks += 1 end
local egg: Rules.EggState = { landAt = 1.15, finish = 1.15 + 3.7 * 1.25, committed = false }
local finish = egg.finish
local accepted, nextAllowed = Rules.Accelerate(egg, 1, 0)
Check(not accepted and egg.finish == finish, "flying egg rejects acceleration")
local paid, cash = Rules.TryInstantHatch(egg, 1, 100, 25)
Check(not paid and cash == 100 and not egg.committed, "flying egg cannot charge")
accepted, nextAllowed = Rules.Accelerate(egg, 1.15, 0)
Check(accepted and egg.finish == finish - 1 and nextAllowed == 1.9, "one free acceleration removes one second")
accepted, nextAllowed = Rules.Accelerate(egg, 1.899, nextAllowed)
Check(not accepted and egg.finish == finish - 1, "0.75 second cooldown enforced")
accepted, nextAllowed = Rules.Accelerate(egg, 1.9, nextAllowed)
Check(accepted and egg.finish == finish - 2, "exact cooldown boundary accepted")
paid, cash = Rules.TryInstantHatch(egg, 2, 24, Config.Species[2].instantHatchPrice)
Check(not paid and cash == 24 and not egg.committed, "insufficient funds cannot mutate egg")
paid, cash = Rules.TryInstantHatch(egg, 2, 100, Config.Species[2].instantHatchPrice)
Check(paid and cash == 75 and egg.committed, "golden rabbit costs exactly 25")
paid, cash = Rules.TryInstantHatch(egg, 2, cash, 25)
Check(not paid and cash == 75, "repeated confirmation cannot charge again")
Check(not Rules.TryCommit(egg, 10), "natural expiry cannot duplicate paid hatch")
egg = { landAt = 0, finish = 1, committed = false }
Check(Rules.TryCommit(egg, 1), "natural hatch at exact deadline")
paid, cash = Rules.TryInstantHatch(egg, 1, 100, 5)
Check(not paid and cash == 100, "natural first means paid callback cannot charge")
egg = { landAt = 0, finish = 0.2, committed = false }
accepted = Rules.Accelerate(egg, 0.1, 0)
Check(accepted and egg.finish == 0.1 and Rules.TryCommit(egg, 0.1), "acceleration clamps to zero remaining and commits once")
Check(not Rules.TryCommit(egg, 0.1), "repeated free hatch rejected")
for tier, species in Config.Species do
	for _, quality in Config.Qualities do
		egg = { landAt = 0, finish = species.hatchSeconds * quality.hatchMultiplier, committed = false }
		paid, cash = Rules.TryInstantHatch(egg, 0, species.instantHatchPrice, species.instantHatchPrice)
		Check(paid and cash == 0, "same species price independent of quality at tier " .. tostring(tier))
	end
end
print("FarmHatchRegression passed:", checks, "checks; cooldown, exact boundaries and competing commits")
