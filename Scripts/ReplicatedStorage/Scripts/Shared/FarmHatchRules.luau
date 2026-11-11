-- 孵化原子规则：统一自然到时、免费加速与付费提交，已提交的蛋不能重复生成或扣款
--!strict
local Config = if script then require(script.Parent:WaitForChild("FarmEconomyConfig")) else require("./FarmEconomyConfig")
export type EggState = { landAt: number, finish: number, committed: boolean }
local Rules = {}
function Rules.TryCommit(egg: EggState, now: number, instant: boolean?): boolean
	if egg.committed or now < egg.landAt or (not instant and now < egg.finish) then return false end
	egg.committed = true
	return true
end
function Rules.Accelerate(egg: EggState, now: number, nextAllowed: number): (boolean, number)
	if egg.committed or now < egg.landAt or now >= egg.finish or now < nextAllowed then return false, nextAllowed end
	egg.finish = math.max(now, egg.finish - Config.HatchReductionSeconds)
	return true, now + Config.HatchCooldownSeconds
end
function Rules.TryInstantHatch(egg: EggState, now: number, cash: number, price: number): (boolean, number)
	if price < 0 or price ~= price or price == math.huge or cash < price or now >= egg.finish then return false, cash end
	if not Rules.TryCommit(egg, now, true) then return false, cash end
	return true, cash - price
end
return Rules
