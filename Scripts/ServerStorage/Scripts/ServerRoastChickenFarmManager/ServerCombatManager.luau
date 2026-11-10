-- 电击子系统：负责现有目标锁定、连锁与剩余伤害分配
--!strict
local replicatedStorage = game:GetService("ReplicatedStorage")
local sharedScripts = replicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local catalog = require(sharedScripts:WaitForChild("RoastChickenCatalog"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local FarmConfig = require(sharedScripts:WaitForChild("FarmConfig"))
local ServerFarmTypes = require(script.Parent.Parent:WaitForChild("ServerFarmTypes"))
type FarmContext = ServerFarmTypes.FarmContext
type PlayerFarmState = ServerFarmTypes.PlayerFarmInfo

local ServerFarmSceneTool = require(script.Parent:WaitForChild("ServerFarmSceneTool"))
local ServerAnimalManager = require(script.Parent:WaitForChild("ServerAnimalManager"))
local ServerCombatManager = {}
function ServerCombatManager.Zap(self: FarmContext, player: Player, s: PlayerFarmState, root: BasePart, direction: Vector3): ()
	local tier = s.zap
	local range = FarmConfig.ZapRanges[tier]
	local minDot = FarmConfig.ZapMinimumDots[tier]
	local targets = ServerFarmSceneTool.FindNearby(self, self.info.flock, ServerFarmSceneTool.GetAnimalPosition, root.Position, range, direction, minDot)
	local first = targets[1]
	if not first then
		s.zapTarget = nil
		self.SendFeedback(player, GameTexts.Farm.AimHint.source)
		return
	end

	for index, target in ipairs(targets) do
		if target.model == s.zapTarget then
			local previousTarget = table.remove(targets, index)
			if previousTarget then
				first = previousTarget
			end
			table.insert(targets, 1, first)
			break
		end
	end

	if tier == 2 then
		targets = { first }
		for _, target in ipairs(ServerFarmSceneTool.FindNearby(self, self.info.flock, ServerFarmSceneTool.GetAnimalPosition, first.pos, FarmConfig.ChainRange)) do
			if target.model ~= first.model then
				table.insert(targets, target)
			end
		end
	end

	local remainingDamage = catalog.zapDamage[tier]
	local from = root.Position + direction * 1.2
	local cookedCount = 0
	s.zapTarget = nil

	for _, target in ipairs(targets) do
		local animal = self.info.flock[target.model]
		if not animal then
			continue
		end
		local damage = math.min(remainingDamage, animal.health)
		local newHealth = animal.health - damage
		remainingDamage -= damage
		local to = target.pos + Vector3.yAxis
		ServerFarmSceneTool.SpawnLightningArc(self, from, to)
		if tier == 2 then
			from = to
		end
		ServerAnimalManager.SetAnimalHealth(self, target.model, animal, newHealth)
		if newHealth == 0 then
			ServerAnimalManager.CookAnimal(self, target.model, animal)
			cookedCount += 1
		else
			s.zapTarget = target.model
		end
		if remainingDamage == 0 then
			break
		end
	end

	local totalDamage = catalog.zapDamage[tier] - remainingDamage
	local msg = GameTexts.Farm.Damage.source:format(totalDamage)
	if cookedCount > 0 then
		msg = GameTexts.Farm.DamageCooked.source:format(totalDamage, cookedCount)
	end
	self.SendFeedback(player, msg)
end
return ServerCombatManager
