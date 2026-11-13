-- 餐厅离线调度回归：运行正式餐厅模块，模拟角色与模型验证客流、竞争领取及购买时机
--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Business = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmBusiness")
local Save = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmSaveData")
local Economy = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmEconomyConfig")
local Config = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmRestaurantConfig")
local Texts = require("../../Scripts/ReplicatedStorage/Scripts/Shared/GameTexts")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame
local checks = 0
local function Check(condition, message)
	assert(condition, message)
	checks += 1
end
local function Node(class, name)
	local node = { ClassName = class, Name = name, children = {}, attributes = {}, cf = CFrame.new() }
	function node:IsA(kind) return self.ClassName == kind or kind == "BasePart" and self.ClassName == "Part" end
	function node:FindFirstChild(key) return self.children[key] end
	function node:WaitForChild(key) return assert(self.children[key], key) end
	function node:FindFirstChildOfClass(kind)
		for _, child in self.children do if child:IsA(kind) then return child end end
		return nil
	end
	function node:GetChildren() return {} end -- 肢体动画不参与本离线调度测试。
	function node:GetAttribute(key) return self.attributes[key] end
	function node:SetAttribute(key, value) self.attributes[key] = value end
	function node:GetPivot() return self.cf end
	function node:PivotTo(cf) self.cf = cf end
	function node:Destroy() self.destroyed = true end
	function node:Clone()
		local copy = Node(self.ClassName, self.Name)
		copy.PrimaryPart = Node("Part", "RootPart")
		return copy
	end
	return setmetatable(node, {__newindex = function(self,key,value)
  rawset(self,key,value)
  if key == "Parent" and value then value.children[self.Name] = self end
 end})
end
local registry = {}
function registry:WaitForChild(key) return self[key] or self end
local models = registry
for _, name in { "FarmWorkerTemplate", "FarmCustomerTemplate", "FarmPackerTemplate" } do models[name] = Node("Model", name) end
local packages = { Sync = function(parent, count) parent.packageCount = count end }
local scene = {}
function scene.GetPlayerRoot(owner) return owner.Character and owner.Character.children.HumanoidRootPart end
function scene.IsInZone(root, zone)
	local localPoint = zone.CFrame:PointToObjectSpace(root.Position)
	return math.abs(localPoint.X) <= zone.Size.X / 2 and math.abs(localPoint.Z) <= zone.Size.Z / 2 and math.abs(localPoint.Y) < 8
end
local view = { SetOwnership = function() end, SetSign = function(root, _, text) root.sign = text end }
local Paths = luau.load(fs.readFile("Scripts/ReplicatedStorage/Scripts/Shared/FarmScenePaths.luau"), {environment={Instance={new=function(class) return Node(class,class) end}}})()
local modules = {
 FarmScenePaths = Paths,
	FarmBusiness = Business, FarmSaveData = Save, FarmRestaurantConfig = Config, FarmEconomyConfig = Economy,
	GameTexts = Texts, ServerPersonalFarmTypes = {}, ServerPersonalFarmView = view,
	ServerRestaurantPackageView = packages, ServerFarmSceneTool = scene,
}
local resolver = {}
function resolver:WaitForChild(name) return if modules[name] then name else self end
local gameMock = { GetService = function(_, service) return if service == "ServerStorage" then models else resolver end }
-- ServerStorage 同时解析模型和服务端模块路径。
function models:WaitForChild(name) return self[name] or (if modules[name] then name else self) end
local env = {
	game = gameMock, script = { Parent = resolver }, Vector3 = Vector3, CFrame = CFrame,
	Instance = { new = function(class) return Node(class, class) end },
	require = function(name) return assert(modules[name], tostring(name)) end,
}
local Restaurant = luau.load(fs.readFile("Scripts/ServerStorage/Scripts/ServerPersonalRestaurant.luau"), { environment = env })()
local function Session(id)
	local map, restaurant = Node("Folder", "Map"), Node("Folder", "Restaurant")
	map.children.Restaurant = restaurant
 restaurant.children.Anchors = Node("Folder", "Anchors")
	map:SetAttribute("OwnerUserId", id)
	local anchors = {
		PackerSpot = Vector3.new(8.3, 0.2, 33.7), PackagePickupSpot = Vector3.new(3.9, 0.2, 29),
		PackageApproachSpot = Vector3.new(1.8, 0.2, 29),
		PackagePickupZone = Vector3.new(3.9, 0.2, 29), CounterDropSpot = Vector3.new(-1.2, 0.2, 40.55),
		CounterDropZone = Vector3.new(-1.2, 0.2, 40.55), PackedDisplay = Vector3.new(4.3, 2.86, 31.7),
		CounterDisplay = Vector3.new(-1.2, 2.75, 42.55), WorkerSpot1 = Vector3.new(-1.2, 0.1, 40.55),
		WorkerSpot2 = Vector3.new(-6.3, 0.1, 40.55), QueueHead = Vector3.new(-1.2, 0, 46.6),
		QueueStart = Vector3.new(-1.2, 0, 55.6), QueueExit = Vector3.new(-10, 0, 55.6),
	}
	for name, position in anchors do
		local part = Node("Part", name)
		part.Position, part.CFrame, part.Size = position, CFrame.new(position), Vector3.new(1, 0.2, 1)
		restaurant.children.Anchors.children[name] = part
	end
	local character = Node("Model", "Character")
	local root = Node("Part", "HumanoidRootPart")
	root.Position, root.CFrame = Vector3.new(100, 3, 100), CFrame.new(100, 3, 100)
	character.children.HumanoidRootPart = root
	local humanoid = Node("Humanoid", "Humanoid"); humanoid.Health = 100
	character.children.Humanoid = humanoid
	local owner = { UserId = id, Character = character, CharacterRemoving = { Connect = function() return {} end } }
	local session = { farm = Save.CreateDefault(), owner = owner, map = map, scope = { Connect = function() end } }
	Restaurant.Init(session, function() end)
	return session, root, humanoid
end
local now = 0
local function Step(session, seconds)
	now += seconds
	return Restaurant.Update(session, now, seconds)
end
local first, root, humanoid = Session(1)
local second = Session(2)
for _ = 1, 250 do Step(first, 0.1) end
Check(#first.restaurant.customers == 6 and first.farm.cash == 0, "fixed arrivals cap at six and wait without stock")
Check(#second.restaurant.customers == 0 and second.farm.cash == 0, "other farm not affected")
first.farm.restaurantLevel = 4
for i = 1, 20 do table.insert(first.farm.packed, Business.CreateCargo("batch-" .. i, "chicken", "normal")) end
root.Position = first.map.children.Restaurant.children.Anchors.children.PackagePickupZone.Position
root.CFrame = CFrame.new(root.Position)
Step(first, 0)
Check(#first.farm.playerCarry == 0 and #first.farm.packed == 20, "standing in pickup area does not automatically take packages")
Check(Restaurant.TakePlayerPackages(first) == 20, "explicit player input takes entire batch")
Step(first, 0)
Check(#first.farm.playerCarry == 20 and #first.farm.packed == 0 and first.farm.cash == 0, "nearby player takes complete batch before workers")
Check(#first.restaurant.workers == 2, "Lv4 creates two transport workers")
root.Position = second.map.children.Restaurant.children.Anchors.children.CounterDropZone.Position + Vector3.new(1000, 0, 0)
root.CFrame = CFrame.new(root.Position)
Step(first, 0)
Check(#first.farm.playerCarry == 20, "foreign/distant position cannot drop cargo")
root.Position = first.map.children.Restaurant.children.Anchors.children.CounterDropZone.Position
root.CFrame = CFrame.new(root.Position)
local sold, income = Step(first, 0)
Check(sold == 1 and income == 10 and first.farm.cash == 10 and #first.farm.counter == 19, "waiting customer purchases one after player drops full batch")
Step(first, 0)
Check(first.farm.cash == 10, "repeated update cannot bypass purchase interval")
for _ = 1, 9 do Step(first, 0.1) end
Check(first.farm.cash == 10, "no second sale before one second")
for _ = 1, 30 do Step(first, 0.1) end
Check(first.farm.cash >= 20 and #first.restaurant.leaving <= 3, "customers buy individually and exit models are reclaimed")
table.insert(first.farm.playerCarry, Business.CreateCargo("death", "chicken", "normal"))
humanoid.Health = 0
Step(first, 0)
Check(#first.farm.playerCarry == 0 and #first.farm.packed == 1, "dead character returns carried batch")
Check(first.farm.cash == 40, "death does not create money")
for _ = 1, 20 do Step(first, 0.1) end
Check(#first.farm.packed == 0, "worker reaches pickup and takes remaining batch")
for _ = 1, 30 do Step(first, 0.1) end
Check(#first.farm.workerCarry["1"] + #first.farm.workerCarry["2"] == 0, "worker deposits only after completing movement")
Check(Save.Validate(first.farm), "all runtime transitions preserve save contract")
Check(second.farm.cash == 0 and #second.farm.counter == 0, "all transitions stay in owning farm")
-- 使用与场景相同的 0.1 stud 高度差，覆盖取货→放货→回到原地的最后垂直一步。
local posture = Session(3)
posture.farm.restaurantLevel = 4
local routes = {}
for tick = 1, 80 do
	local previous = {}
	for index, actor in posture.restaurant.workers do previous[index] = actor.phase end
	if tick == 2 then table.insert(posture.farm.packed, Business.CreateCargo("posture", "chicken", "normal")) end
	Step(posture, 0.1)
	for index, actor in posture.restaurant.workers do
		Check(actor.model:GetPivot().UpVector:Dot(Vector3.yAxis) > 0.9999, "worker stays upright through pickup, drop, vertical return and idle")
		routes[actor.phase] = true
		if previous[index] == "PickupApproach" and actor.phase == "Pickup" or previous[index] == "DropApproach" and actor.phase == "Drop" then
			local approach = posture.map.children.Restaurant.children.Anchors.children.PackageApproachSpot.Position
			Check((actor.model:GetPivot().Position - approach).Magnitude < 0.0001, "transport route passes exact approach waypoint in both directions")
		end
		if previous[index] == "PickupApproach" then Check(#posture.farm.workerCarry[tostring(index)] == 0, "no reservation before actual pickup point") end
		if tick == 80 then
			local home = posture.map.children.Restaurant.children.Anchors.children["WorkerSpot" .. index]
			Check(actor.phase == "Idle" and (actor.model:GetPivot().Position - home.Position).Magnitude < 0.0001, "returned worker snaps to exact idle anchor")
			Check(actor.model:GetPivot().LookVector:Dot(home.CFrame.LookVector) > 0.9999, "idle worker faces its original station direction: " .. tostring(actor.model:GetPivot().LookVector) .. " vs " .. tostring(home.CFrame.LookVector))
		end
	end
end
Check(routes.PickupApproach and routes.DropApproach and routes.Pickup and routes.Drop and routes.Return and routes.Idle, "posture regression actually traverses the complete transport cycle")
-- 即使已有角色被旧逻辑翻倒，也应在下一次待命更新恢复。
posture.restaurant.workers[1].model.cf *= CFrame.Angles(math.pi / 2, 0, 0)
Step(posture, 0)
Check(posture.restaurant.workers[1].model:GetPivot().UpVector:Dot(Vector3.yAxis) > 0.9999, "previously tilted idle worker recovers without moving")
local access, accessRoot, accessHumanoid = Session(4)
table.insert(access.farm.packed, Business.CreateCargo("explicit-access", "chicken", "normal"))
Check(Restaurant.TakePlayerPackages(access) == 0, "pickup input outside area rejected")
accessRoot.Position = access.map.children.Restaurant.children.Anchors.children.PackagePickupZone.Position
accessRoot.CFrame = CFrame.new(accessRoot.Position)
access.map:SetAttribute("OwnerUserId", 999)
Check(Restaurant.TakePlayerPackages(access) == 0, "pickup input for foreign farm rejected")
access.map:SetAttribute("OwnerUserId", 4)
accessHumanoid.Health = 0
Check(Restaurant.TakePlayerPackages(access) == 0, "dead player pickup input rejected")
accessHumanoid.Health = 100
access.frozen = true
Check(Restaurant.TakePlayerPackages(access) == 0, "frozen session pickup input rejected")
access.frozen = false
Check(Restaurant.TakePlayerPackages(access) == 1 and Restaurant.TakePlayerPackages(access) == 0, "valid explicit input takes once without duplication")
print("FarmRestaurantRegression passed:", checks, "checks; actual scheduler with mocked engine models")
