-- 升级子系统：负责购买区域、价格、余额与等级上限校验
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
local ServerUpgradeManager = {}
function ServerUpgradeManager.Purchase(self: FarmContext, player: Player, s: PlayerFarmState, root: BasePart, action: FarmConfig.FarmAction): ()
	if action == "buyNest" then
		local upgradeZone = self.map.Nest:FindFirstChild("UpgradeZone") :: BasePart?
		if not upgradeZone or not ServerFarmSceneTool.IsInZone(root, upgradeZone) then
			return
		end
		local nextType = catalog.creatures[self.info.nestLevel + 1]
		if not nextType then
			return
		end
		if s.cash < nextType.unlock then
			self.SendFeedback(player, GameTexts.Farm.NeedCoins.source:format(nextType.unlock - s.cash))
			return
		end
		s.cash -= nextType.unlock
		self.info.nestLevel += 1
		self.info.nextEggTime = math.min(self.info.nextEggTime, os.clock() + FarmConfig.NestUpgradeDelay)
		self.SyncPlayerState(player, s)
		self.SendFeedback(player, GameTexts.Farm.NestUpgraded.source:format(nextType.egg))
	elseif action == "buyRestaurant" then
		local upgradeZone = self.map.Restaurant:FindFirstChild("UpgradeZone") :: BasePart?
		if not upgradeZone or not ServerFarmSceneTool.IsInZone(root, upgradeZone) then
			return
		end
		local paid, cost = self.restaurant.Upgrade(s.cash)
		if paid then
			s.cash -= paid
			self.SyncPlayerState(player, s)
			self.SendFeedback(player, if self.restaurant.GetLevel() == 3 then GameTexts.Farm.CounterOpened.source else GameTexts.Farm.RestaurantUpgraded.source)
		elseif cost then
			self.SendFeedback(player, GameTexts.Farm.NeedCoins.source:format(cost - s.cash))
		end
	elseif ServerFarmSceneTool.IsInZone(root, self.map.Shop :: BasePart) then
		local key = if action == "buyZap" then "zap" else "collect"
		local currentLevel = if key == "zap" then s.zap else s.collect
		local price = FarmConfig.ToolPrices[currentLevel]
		if not price then
			return
		end
		if s.cash < price then
			self.SendFeedback(player, GameTexts.Farm.NeedCoins.source:format(price - s.cash))
			return
		end
		s.cash -= price
		if key == "zap" then
			s.zap += 1
		else
			s.collect += 1
		end
		self.SyncPlayerState(player, s)
		if key == "zap" then
			self.SendFeedback(player, GameTexts.Farm.ZapUpgraded.source:format(catalog.zapDamage[s.zap]))
		else
			self.SendFeedback(player, GameTexts.Farm.CollectUpgraded.source:format(FarmConfig.CollectLimits[s.collect]))
		end
	end
end
return ServerUpgradeManager
