-- 农场回归测试：仅在 Play 服务端执行，使用临时场景验证边界与资源释放
--!strict
assert(game:GetService("RunService"):IsRunning(), "Run this test in a Play server")
local replicatedStorage = game:GetService("ReplicatedStorage")
local sharedScripts = replicatedStorage.Scripts.Shared
local FarmConfig = require(sharedScripts.FarmConfig)
local LifecycleTool = require(sharedScripts.LifecycleTool)
local modules = game.ServerStorage.Scripts.ServerRoastChickenFarmManager
local SceneTool = require(modules.ServerFarmSceneTool)
local AnimalManager = require(modules.ServerAnimalManager)
local CombatManager = require(modules.ServerCombatManager)
local InventoryManager = require(modules.ServerInventoryManager)
local UpgradeManager = require(modules.ServerUpgradeManager)
local Restaurant = require(modules.ServerRestaurant)
local player = game.Players:GetPlayers()[1]
assert(player and player.Character, "A player character is required")
local rootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart
local originalPivot, originalAnchored = player.Character:GetPivot(), rootPart.Anchored
local fixture = workspace.RoastChickenFarm:Clone()
fixture.Name = "FarmRegressionFixture"
fixture.Parent = workspace
fixture.LiveAnimals:ClearAllChildren()
fixture.CookedFood:ClearAllChildren()
fixture.Eggs:ClearAllChildren()
local scope = LifecycleTool.new()
scope:Own(fixture)
local checks: { string } = {}
local success, failure = xpcall(function(): ()
	rootPart.Anchored = true
	local info = {
		flock = {},
		roasts = {},
		eggs = {},
		playerStates = {},
		nestLevel = 1,
		nextEggTime = 0,
		restaurant = { stock = {}, queue = {}, lanes = {}, leaving = {}, nextArrival = 0, level = 1, serial = 0 },
	}
	local playerInfo = { cash = 0, items = {}, zap = 1, collect = 1, cooldowns = {} }
	info.playerStates[player] = playerInfo
	local sales = 0
	local restaurant = Restaurant.Init(fixture, SceneTool.CreatePiece, function(_, creature): ()
		sales += creature.value
	end, info.restaurant, scope)
	local nestGui, nestLabel = SceneTool.CloneBillboard("NestSignGui", fixture.Nest.ProductionSign)
	scope:Own(nestGui)
	local context = {
		info = info,
		map = fixture,
		liveFolder = fixture.LiveAnimals,
		roastFolder = fixture.CookedFood,
		eggFolder = fixture.Eggs,
		rng = Random.new(7),
		scope = scope,
		restaurant = restaurant,
		nestLabel = nestLabel,
		healthLabels = {},
		eggLabels = {},
		SyncPlayerState = function(): () end,
		SendFeedback = function(): () end,
	}
	assert(FarmConfig.BasketCapacity == 6 and FarmConfig.PopulationCapacity == 28 and FarmConfig.ZapCooldown == 0.55 and FarmConfig.RoastLifetime == 75)
	table.insert(checks, "现行数值基线")
	AnimalManager.SpawnAnimal(context, Vector3.new(0, 0, -3), 1)
	AnimalManager.SpawnAnimal(context, Vector3.new(1, 0, -3), 1)
	player.Character:PivotTo(CFrame.new(0, 3, 0))
	CombatManager.Zap(context, player, playerInfo, rootPart, Vector3.new(0, 0, -1))
	assert(#fixture.CookedFood:GetChildren() == 1 and #fixture.LiveAnimals:GetChildren() == 1, "T1 damage budget changed")
	table.insert(checks, "电击伤害与单份掉落")
	playerInfo.items = { 1, 1, 1, 1, 1, 1 }
	InventoryManager.Collect(context, player, playerInfo, rootPart, Vector3.new(0, 0, -1))
	assert(#playerInfo.items == 6 and #fixture.CookedFood:GetChildren() == 1, "Full basket accepted an item")
	playerInfo.items = { 1, 1, 1, 1, 1 }
	InventoryManager.Collect(context, player, playerInfo, rootPart, Vector3.new(0, 0, -1))
	assert(#playerInfo.items == 6 and next(info.roasts) == nil, "Pickup was not removed atomically")
	InventoryManager.Collect(context, player, playerInfo, rootPart, Vector3.new(0, 0, -1))
	assert(#playerInfo.items == 6, "Duplicate pickup")
	table.insert(checks, "满筐拒绝、末位拾取与重复拾取")
	player.Character:PivotTo(fixture.Shop.CFrame * CFrame.new(0, 3, 0))
	UpgradeManager.Purchase(context, player, playerInfo, rootPart, "buyZap")
	assert(playerInfo.zap == 1 and playerInfo.cash == 0, "Insufficient balance accepted")
	playerInfo.cash = 240
	UpgradeManager.Purchase(context, player, playerInfo, rootPart, "buyZap")
	assert(playerInfo.zap == 2 and playerInfo.cash == 180, "First upgrade price changed")
	UpgradeManager.Purchase(context, player, playerInfo, rootPart, "buyZap")
	assert(playerInfo.zap == 3 and playerInfo.cash == 0, "Second upgrade price changed")
	UpgradeManager.Purchase(context, player, playerInfo, rootPart, "buyZap")
	assert(playerInfo.zap == 3 and playerInfo.cash == 0, "Maximum level changed")
	table.insert(checks, "余额、逐级价格与满级边界")
	playerInfo.items = {}
	for _ = 1, 25 do
		table.insert(playerInfo.items, 1)
	end
	assert(restaurant.Deposit(player, playerInfo.items) == 24 and #playerInfo.items == 1, "Restaurant capacity changed")
	assert(restaurant.Deposit(player, playerInfo.items) == 0 and #playerInfo.items == 1, "Full shelf lost basket contents")
	table.clear(info.restaurant.stock)
	assert(restaurant.Deposit(player, playerInfo.items) == 1)
	for step = 1, 1200 do
		restaurant.Update(step * 0.1, 0.1)
	end
	assert(sales == 10 and restaurant.GetCount() == 0, "Sale amount or exactly-once settlement changed")
	for step = 1201, 1250 do
		restaurant.Update(step * 0.1, 0.1)
	end
	assert(sales == 10, "Duplicate restaurant settlement")
	table.insert(checks, "备餐架容量、库存保留与单次售卖结算")
	local delayed = false
	scope:Delay(0.1, function(): ()
		delayed = true
	end)
	scope:Destroy()
	scope:Destroy()
	task.wait(0.15)
	assert(not delayed and fixture.Parent == nil, "Destroy did not cancel delayed work")
	table.insert(checks, "幂等销毁与延迟任务取消")
end, debug.traceback)
scope:Destroy()
player.Character:PivotTo(originalPivot)
rootPart.Anchored = originalAnchored
assert(success, failure)
return checks
