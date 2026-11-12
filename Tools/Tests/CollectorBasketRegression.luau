-- 拾取工具与鸡筐离线回归：验证唯一预制来源、分阶外观、焊接约束、承重显示与克隆隔离
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local models = roblox.deserializeModel(fs.readFile("Assets/Studio/CollectorBasketTemplates.rbxm"))[1]
assert(models.Name == "Models" and models:IsA("Folder"), "asset must preserve Models folder")
local collectorsFolder = models:FindFirstChild("Collectors")
local basketsFolder = models:FindFirstChild("Baskets")
assert(collectorsFolder and collectorsFolder:IsA("Folder") and basketsFolder and basketsFolder:IsA("Folder"), "Collectors and Baskets folders are required")
local toolTemplates = roblox.deserializeModel(fs.readFile("Assets/Studio/CollectorToolTemplates.rbxm"))[1]
toolTemplates.Parent = models
local collectors = collectorsFolder
local baskets = basketsFolder

local replicatedStorageMock = {
	WaitForChild = function(_self, name)
		assert(name == "Models")
		return {
			WaitForChild = function(_models, childName: string)
				local child = models:FindFirstChild(childName)
				assert(child, childName)
				return child
			end,
		}
	end,
}
local gameMock = {
	GetService = function(_self, name)
		if name == "ReplicatedStorage" then
			return replicatedStorageMock
		end
		error("Unknown GetService: " .. tostring(name))
	end,
}
local env = {
	game = gameMock,
	assert = assert,
	error = error,
	tostring = tostring,
	math = math,
	type = type,
	string = string,
}
local collectorBuilder = luau.load(fs.readFile("Scripts/ServerStorage/Scripts/ServerRoastChickenFarmManager/ServerCollectorBuilder.luau"), { environment = env })()
local basketBuilder = luau.load(fs.readFile("Scripts/ServerStorage/Scripts/ServerRoastChickenFarmManager/ServerBasketBuilder.luau"), { environment = env })()

local checks = 0
local function Check(condition: boolean, message: string): ()
	assert(condition, message)
	checks += 1
end

local function CountVisuals(model: Model): (number, number)
	local root = model.PrimaryPart
	assert(root)
	local parts = 0
	local welds = 0
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child ~= root then
			parts += 1
			Check(child.Anchored == false, child.Name .. " is unanchored")
			Check(child.CanCollide == false, child.Name .. " does not collide")
			Check(child.Massless == true, child.Name .. " is massless")
			Check(child.CanTouch == false and child.CanQuery == false, child.Name .. " is not queryable")
			local weld = root:FindFirstChild(child.Name .. "Weld")
			Check(weld ~= nil and weld:IsA("WeldConstraint"), child.Name .. " weld exists")
			if weld and weld:IsA("WeldConstraint") then
				Check(weld.Part0 == root and weld.Part1 == child, child.Name .. " weld joins the root")
				welds += 1
			end
		end
	end
	return parts, welds
end

local collectorMarks = {
	{ "Palm" },
	{ "Blade" },
	{ "Canister" },
	{ "Intake" },
	{ "RingA", "RingB" },
}
local basketMarks = { "WovenBand", "WoodRim", "IronRim", "AlloyBrace", "PneumaticCap" }

print("--> 验证五阶拾取工具与鸡筐只从预制克隆")
for tier = 1, 5 do
	local collector = collectorBuilder.BuildCollectorModel(tier)
	local basket = basketBuilder.BuildBasketModel(tier)
	Check(collector:IsA("Model") and collector.Name == "FarmCollector", "collector clone is named FarmCollector")
	Check(basket:IsA("Model") and basket.Name == "ChickenBasket", "basket clone is named ChickenBasket")
	Check(collector:GetAttribute("CollectorTier") == tier, "collector tier attribute")
	Check(basket:GetAttribute("BasketTier") == tier, "basket tier attribute")
	local collectorTemplate = collectors:FindFirstChild("Collector_T" .. tier)
	local basketTemplate = baskets:FindFirstChild("Basket_T" .. tier)
	assert(collectorTemplate and collectorTemplate:IsA("Model"))
	assert(basketTemplate and basketTemplate:IsA("Model"))
	Check(collectorTemplate:GetAttribute("CollectorTier") == nil, "template collector tier stays empty")
	Check(basketTemplate:GetAttribute("BasketTier") == nil, "template basket tier stays empty")
	Check(#collector:GetDescendants() == #collectorTemplate:GetDescendants(), "collector clone adds no geometry")
	Check(#basket:GetDescendants() == #basketTemplate:GetDescendants(), "basket clone adds no geometry")
	for _, model in { collector, basket, collectorTemplate, basketTemplate } do
		local root = model.PrimaryPart
		Check(root ~= nil and root:IsA("BasePart") and root.Name == "RootPart", model.Name .. " root is RootPart")
		if root and root:IsA("BasePart") then
			Check(root.Transparency == 1 and root.Massless == true and root.CanCollide == false, model.Name .. " root is an invisible mount")
		end
		local parts, welds = CountVisuals(model)
		Check(parts > 0 and parts == welds, model.Name .. " visual parts are welded to the root")
	end
	for _, mark in collectorMarks[tier] do
		Check(collector:FindFirstChild(mark) ~= nil, "collector T" .. tier .. " has " .. mark)
	end
	Check(basket:FindFirstChild("Basket") ~= nil, "basket body exists")
	Check(basket:FindFirstChild(basketMarks[tier]) ~= nil, "basket T" .. tier .. " has its accent")
	for index = 1, 4 do
		local cargo = basket:FindFirstChild("Cargo" .. index)
		Check(cargo ~= nil and cargo:IsA("BasePart"), "basket has Cargo" .. index)
	end
	collector:Destroy()
	basket:Destroy()
	Check(collectorTemplate.Parent == collectors and basketTemplate.Parent == baskets, "destroying clones preserves templates")
end

print("--> 验证改模板会进入下次克隆，缺件则失败且不拼备用模型")
local tierOne = collectors:FindFirstChild("Collector_T1")
assert(tierOne)
local palm = tierOne:FindFirstChild("Palm")
assert(palm and palm:IsA("BasePart"))
palm.Color = roblox.Color3.fromRGB(13, 27, 39)
local recolored = collectorBuilder.BuildCollectorModel(1)
local recoloredPalm = recolored:FindFirstChild("Palm")
assert(recoloredPalm and recoloredPalm:IsA("BasePart"))
Check(recoloredPalm.Color == palm.Color, "template color reaches the clone")
recolored:Destroy()

local basketOne = baskets:FindFirstChild("Basket_T1")
assert(basketOne)
local hidden = basketOne:FindFirstChild("Cargo1")
assert(hidden)
hidden.Name = "Cargo1Hidden"
Check(not pcall(basketBuilder.BuildBasketModel, 1), "missing cargo fails clearly")
hidden.Name = "Cargo1"

local removed = collectors:FindFirstChild("Collector_T5")
assert(removed)
removed.Parent = nil
Check(not pcall(collectorBuilder.BuildCollectorModel, 5), "missing collector template fails clearly")
Check(not pcall(collectorBuilder.BuildCollectorModel, 99), "unknown tier fails clearly")
removed.Parent = collectors
Check(collectorBuilder.BuildCollectorModel(5).Name == "FarmCollector", "restored template clones again")

print("--> 验证鸡筐按重量比例显示固定四件货物")
local filled = basketBuilder.BuildBasketModel(2)
basketBuilder.ApplyCargoFill(filled, 0, 36)
for index = 1, 4 do
	local cargo = filled:FindFirstChild("Cargo" .. index)
	assert(cargo and cargo:IsA("BasePart"))
	Check(cargo.Transparency == 1, "empty basket hides cargo " .. index)
end
basketBuilder.ApplyCargoFill(filled, 6, 12)
for index = 1, 4 do
	local cargo = filled:FindFirstChild("Cargo" .. index)
	assert(cargo and cargo:IsA("BasePart"))
	Check(cargo.Transparency == (if index <= 2 then 0 else 1), "half load shows two cargo pieces")
end
basketBuilder.ApplyCargoFill(filled, 40, 36)
for index = 1, 4 do
	local cargo = filled:FindFirstChild("Cargo" .. index)
	assert(cargo and cargo:IsA("BasePart"))
	Check(cargo.Transparency == 0, "full load shows every cargo piece")
end

print(string.format("CollectorBasketRegression passed: %d checks", checks))

-- 新的手持收集器保持独立 Tool 模板，不改变原模型与背篓来源。
for tier = 1, 5 do
	local tool = collectorBuilder.BuildCollectorTool(tier)
	local template = toolTemplates:FindFirstChild("CollectorTool_T" .. tier)
	Check(tool:IsA("Tool") and tool.Name == "FarmCollector", "collector is a Tool")
	Check(tool:GetAttribute("CollectorTier") == tier, "collector tier")
	Check(tool.ManualActivationOnly and tool.RequiresHandle and not tool.CanBeDropped, "manual activation only")
	local handle = tool:FindFirstChild("Handle")
	Check(handle ~= nil and handle:IsA("BasePart"), "collector Handle")
	for _, item in tool:GetDescendants() do
		if item:IsA("WeldConstraint") then Check(item.Part0 == handle and item.Part1:IsDescendantOf(tool), "welds reference cloned Tool") end
		if item:IsA("BasePart") then Check(not item.Anchored and item.Massless and not item.CanCollide, "collector physics") end
	end
	Check(#tool:GetDescendants() == #template:GetDescendants(), "no runtime assembly")
	tool:Destroy()
	Check(template.Parent == toolTemplates, "destroying clone preserves source")
end
print("Collector Tool checks passed; total " .. checks)
