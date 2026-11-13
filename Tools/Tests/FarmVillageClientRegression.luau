-- 村落客户端回归：检查重生保留的本地标牌，以及流送式后代移除和重新到达的监听恢复
--!strict
local Paths = require(game.ReplicatedStorage.Scripts.Shared.FarmScenePaths)
assert(game:GetService("RunService"):IsClient(), "Play client only")
local Players = game:GetService("Players")
local Class = require(game.ReplicatedStorage.Scripts.Client.ClientFarmSpeciesManager)
local player = Players.LocalPlayer
local manager = Class.new()
manager:Scan()
local map = manager.map
assert(map and #manager.entries == 4, "Owned farm entries required")
local shop, sign = Paths.Find(map, "Shop"), Paths.Find(map, "OwnerSign")
assert(shop and sign)
local shopParent, signParent = shop.Parent, sign.Parent
local function CountSigns(): number
	local count = 0
	for _, gui in player.PlayerGui:GetChildren() do
		if gui:IsA("BillboardGui") and gui.Adornee == sign then
			assert(not gui.ResetOnSpawn)
			count += 1
		end
	end
	return count
end
local success, failure = xpcall(function(): boolean
	assert(CountSigns() == 1, "Owner sign must survive respawn; run after a server-triggered respawn")
	shop.Parent = nil
	task.wait(0.1) -- 引擎使用 Deferred 信号；断言在事件队列派发后执行。
	assert(#manager.entries == 3)
	shop.Parent = shopParent
	task.wait(0.1)
	assert(#manager.entries == 4)
	sign.Parent = nil
	task.wait(0.1)
	assert(CountSigns() == 0, "Stale adornee must be released")
	sign.Parent = signParent
	task.wait(0.1)
	assert(CountSigns() == 1, "Returning sign must mount exactly once")
	return true
end, debug.traceback)
shop.Parent, sign.Parent = signParent, map
local entryParents: { [BasePart]: Instance } = {}
for _, entry in manager.entries do if entry.Parent then entryParents[entry] = entry.Parent end end
manager:Destroy()
-- 新建的测试管理器曾接管入口 Prompt；重新到达一次，让正式管理器恢复自己的实例与连接。
for entry in entryParents do entry.Parent = nil end
task.wait(0.1)
for entry, parent in entryParents do entry.Parent = parent end
task.wait(0.1)
assert(success, failure)
return { entriesRestored = true, signsRestored = true, note = "Client-only removal/rearrival fixture; does not force engine stream-out" }
