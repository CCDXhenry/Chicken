-- 经营测量只读快照：在获授权的 Play 服务端分别采集五分钟场次开始和结束值
--!strict
assert(game:GetService("RunService"):IsRunning() and game:GetService("RunService"):IsServer(), "Run in a Play server")
local Manager = require(game:GetService("ServerStorage"):WaitForChild("Scripts"):WaitForChild("ServerPersonalFarmManager"))
local manager = Manager.GetActive()
assert(manager, "Personal farm manager is not ready")
local MetricNames = { "startedAt", "cashStart", "salesIncome", "spent", "sold", "spawned", "killed", "collected", "delivered", "expired", "fullSeconds", "waitingItemSeconds", "processingItemSeconds", "unloadSeconds", "deliveredKg", "trips", "firstSaleSeconds", "firstEnhancementSeconds", "firstAffordEnhancementSeconds", "normalEggs", "goldenEggs", "rainbowEggs", "giantEggs" }
local result: { { [string]: unknown } } = {}
for _, player in game:GetService("Players"):GetPlayers() do
	local row: { [string]: unknown } = { userId = player.UserId, time = os.clock() }
	local session = manager.sessions[player]
	local metrics = if session then session.metrics else nil
	if metrics then for _, name in MetricNames do row[name] = metrics[name] end end
	for _, name in { "FarmReady", "FarmStage", "FarmPlotId", "FarmCash", "FarmNestLevel", "FarmZap", "FarmWeaponLevel", "FarmCollect", "FarmBasketWeight", "FarmBasketCapacity", "FarmStock", "FarmWaiting", "FarmProcessing", "FarmExpectedValue", "FarmRestaurantLevel" } do row[name] = player:GetAttribute(name) end
	table.insert(result, row)
end
return result
