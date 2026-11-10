-- 库存子系统：负责熟食拾取、鸡筐投影、区域交货和过期清理
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
local ServerInventoryManager = {}
function ServerInventoryManager.Collect(self: FarmContext, player: Player, s: PlayerFarmState, root: BasePart, direction: Vector3): ()
	if #s.items == FarmConfig.BasketCapacity then
		self.SendFeedback(player, GameTexts.Farm.FullBasket.source)
		return
	end
	local tier = s.collect
	local facing = if tier == 2 then direction else nil
	local range = FarmConfig.CollectRanges[tier]
	local targets = ServerFarmSceneTool.FindNearby(self, self.info.roasts, ServerFarmSceneTool.GetRoastPosition, root.Position, range, facing, 0)
	local maxLimit = FarmConfig.CollectLimits[tier]
	local count = math.min(maxLimit, FarmConfig.BasketCapacity - #s.items, #targets)
	if count == 0 then
		self.SendFeedback(player, GameTexts.Farm.CollectHint.source)
		return
	end

	for i = 1, count do
		local target = targets[i]
		local roastData = self.info.roasts[target.model]
		if roastData then
			table.insert(s.items, roastData.variant)
			ServerFarmSceneTool.CollectRoast(self, target.model, root)
		end
	end

	self.SyncPlayerState(player, s)
	ServerFarmSceneTool.UpdateBasketVisual(self, player, s)
	self.SendFeedback(
		player,
		if #s.items == FarmConfig.BasketCapacity then GameTexts.Farm.FullBasketCollected.source else GameTexts.Farm.Collected.source:format(count)
	)
end
function ServerInventoryManager.Update(self: FarmContext, now: number): { BasePart }
	for model, roast in self.info.roasts do
		if now >= roast.expiresAt then
			self.info.roasts[model] = nil
			model:Destroy()
		end
	end
	local roots: { BasePart } = {}
	for player, s in pairs(self.info.playerStates) do
		local root = ServerFarmSceneTool.GetPlayerRoot(player)
		if root then
			table.insert(roots, root)
			player:SetAttribute("FarmShop", ServerFarmSceneTool.IsInZone(root, self.map.Shop :: BasePart))
			local nestUpgradeZone = self.map.Nest:FindFirstChild("UpgradeZone") :: BasePart?
			player:SetAttribute("FarmNestShop", if nestUpgradeZone then ServerFarmSceneTool.IsInZone(root, nestUpgradeZone) else false)
			local restUpgradeZone = self.map.Restaurant:FindFirstChild("UpgradeZone") :: BasePart?
			player:SetAttribute("FarmRestaurantShop", if restUpgradeZone then ServerFarmSceneTool.IsInZone(root, restUpgradeZone) else false)

			local sellZone = self.map:FindFirstChild("Sell") :: BasePart?
			if #s.items > 0 and sellZone and ServerFarmSceneTool.IsInZone(root, sellZone) then
				local deposited = self.restaurant.Deposit(player, s.items)
				if deposited > 0 then
					self.SyncPlayerState(player, s)
					ServerFarmSceneTool.UpdateBasketVisual(self, player, s)
					self.SendFeedback(player, GameTexts.Farm.Deposited.source:format(deposited))
				elseif not s.atFullShelf then
					self.SendFeedback(player, GameTexts.Farm.ShelfFull.source)
				end
				s.atFullShelf = self.restaurant.GetCount() >= FarmConfig.RestaurantCapacity
			else
				s.atFullShelf = false
			end
		end
		player:SetAttribute("FarmStock", self.restaurant.GetCount())
		player:SetAttribute("FarmNestLevel", self.info.nestLevel)
		player:SetAttribute("FarmRestaurantLevel", self.restaurant.GetLevel())
	end

	return roots
end
return ServerInventoryManager
