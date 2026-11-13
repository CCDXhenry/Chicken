-- 餐厅打包取货 Edit 构筑器：幂等维护九套场景锚点、员工顾客模板和包装模型
--!strict
assert(not game:GetService("RunService"):IsRunning(), "Edit only")
local storage = game:GetService("ServerStorage")
local replicated = game:GetService("ReplicatedStorage")
local history = game:GetService("ChangeHistoryService")
history:SetWaypoint("Before restaurant packaging flow")
-- Script Sync 在 Edit 使用草稿；只读加载无副作用的路径契约，不提交草稿或覆写 Source。
local pathModule = game:GetService("ReplicatedStorage").Scripts.Shared.FarmScenePaths
local loadPaths, loadError = loadstring(game:GetService("ScriptEditorService"):GetEditorSource(pathModule), "FarmScenePaths")
assert(loadPaths, loadError)
local Paths = loadPaths()
local models = storage.Models
local function Piece(parent: Instance, name: string, size: Vector3, cf: CFrame, hex: string, visible: boolean): Part
	local previous = parent:FindFirstChild(name)
	if previous then previous:Destroy() end
	local part = Instance.new("Part")
	part.Name, part.Size, part.CFrame = name, size, cf
	part.Color = Color3.fromHex(hex)
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
	part.Transparency = if visible then 0 else 1
	part.CastShadow = visible
	part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end
local function ActorTemplate(name: string, color: string, customer: boolean): ()
	local old = models:FindFirstChild(name)
	if old then old:Destroy() end
	local model = models.FarmWorkerTemplate:Clone()
	model.Name = name
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
			if part.Name == "Apron" or part.Name == "Cap" then part.Color = Color3.fromHex(color) end
			if customer and part.Name == "Cap" then part.Transparency = 1 end
			if part.Name == "Arm" or part.Name == "Leg" then part:SetAttribute("RestCFrame", model:GetPivot():ToObjectSpace(part.CFrame)) end
		end
	end
	model.Parent = models
end
ActorTemplate("FarmPackerTemplate", "F4F0DD", false)
ActorTemplate("FarmCustomerTemplate", "77B5DE", true)
for _, part in models.FarmWorkerTemplate:GetChildren() do
	if part:IsA("BasePart") and (part.Name == "Arm" or part.Name == "Leg") then part:SetAttribute("RestCFrame", models.FarmWorkerTemplate:GetPivot():ToObjectSpace(part.CFrame)) end
end
local oldPackage = models:FindFirstChild("FarmPackageTemplate")
if oldPackage then oldPackage:Destroy() end
local package = Instance.new("Model")
package.Name = "FarmPackageTemplate"
local root = Piece(package, "RootPart", Vector3.one * 0.2, CFrame.new(0, 0.1, 0), "FFFFFF", false)
root.Massless = true
package.PrimaryPart = root
Piece(package, "Box", Vector3.new(0.78, 0.42, 0.58), CFrame.new(0, 0.21, 0), "C99B61", true)
Piece(package, "Lid", Vector3.new(0.82, 0.06, 0.62), CFrame.new(0, 0.45, 0), "E8C58F", true)
Piece(package, "Band", Vector3.new(0.16, 0.012, 0.63), CFrame.new(0, 0.486, 0), "CE523B", true)
for _, part in package:GetChildren() do
	if part:IsA("BasePart") and part ~= root then
		local weld = Instance.new("WeldConstraint")
		weld.Name, weld.Part0, weld.Part1, weld.Parent = "Weld_" .. part.Name, root, part, root
	end
end
package.Parent = models
local template = models.PersonalFarmTemplate
-- 原始交货区参考资产只读保存于 Models；它来自功能修改前的场景，不参与运行期克隆。
local original = models:WaitForChild("FarmRestaurantOriginalLayout")
local OriginalNames: { [string]: boolean } = { Sell = true, StockShelf = true, StockShelfTop = true, StockSign = true, DepositBorder = true, DeliveryDirection = true, KitchenEntranceSign = true, PrepTable = true, PrepTop = true }
local RetiredParts: { [string]: boolean } = { PrepTable = true, PrepTop = true, Oven = true, OvenDoor = true, OvenWindow = true }
local SignTemplates: { [string]: string } = { Sell = "OriginalFoodDeliverySignGui", DeliveryDirection = "OriginalFoodDirectionSignGui", KitchenEntranceSign = "OriginalKitchenEntranceSignGui" }
for partName, templateName in SignTemplates do
	if not replicated.UI:FindFirstChild(templateName) then
		local source = original:WaitForChild(partName):FindFirstChildOfClass("BillboardGui")
		assert(source, "Missing original authored delivery sign: " .. partName)
		local gui = source:Clone()
		gui.Name = templateName
		gui:ResetPropertyToDefault("Adornee")
		gui.Parent = replicated.UI
	end
end
local function Build(map: Instance): ()
 assert(map:GetAttribute("FarmHierarchyVersion") == 2, "Organize farm hierarchy first")
	local restaurant = Paths.Require(map, "Restaurant")
 local anchors = Paths.Require(map, "RestaurantAnchors")
 local kitchen = restaurant:WaitForChild("Kitchen")
 local packing = restaurant:WaitForChild("Packing")
	assert(restaurant)
	-- 厨房入口保持原位，用它求刚性变换；不依赖本次会移动的打包员和台面。
	local entrance = anchors:FindFirstChild("KitchenEntranceSign") :: BasePart
	local originalEntrance = original:WaitForChild("KitchenEntranceSign") :: BasePart
	local transform = entrance.CFrame * originalEntrance.CFrame:Inverse()
	local sell = Paths.Find(map, "Sell")
	if sell then sell:Destroy() end
	for _, parent in {anchors, kitchen} do
  for _, part in parent:GetChildren() do
   if OriginalNames[part.Name] or part.Name:match("^DepositBorder%d+$") then part:Destroy() end
  end
 end
	local borders: { BasePart } = {}
 for _, source in original:GetChildren() do if source:IsA("BasePart") and source.Name == "DepositBorder" then table.insert(borders, source) end end
 table.sort(borders, function(a,b)
  if a.CFrame.Position.X ~= b.CFrame.Position.X then return a.CFrame.Position.X < b.CFrame.Position.X end
  if a.CFrame.Position.Z ~= b.CFrame.Position.Z then return a.CFrame.Position.Z < b.CFrame.Position.Z end
  return a.CFrame.Position.Y < b.CFrame.Position.Y
 end)
 for _, source in original:GetChildren() do
  if source:IsA("BasePart") and not RetiredParts[source.Name] then
			local restored = source:Clone()
			restored.CFrame = transform * source.CFrame
   if source.Name == "DepositBorder" then restored.Name = "DepositBorder" .. string.format("%02d", table.find(borders, source) :: number) end
			restored:SetAttribute("OwnerUserId", nil)
			restored:SetAttribute("FarmId", map:GetAttribute("FarmId"))
			local guiName = SignTemplates[source.Name]
			if guiName then
				for _, child in restored:GetChildren() do if child:IsA("BillboardGui") then child:Destroy() end end
				local gui = replicated.UI:WaitForChild(guiName):Clone() :: BillboardGui
				gui.Adornee, gui.Parent = restored, restored
			end
			restored.Parent = if source.Name == "StockShelf" or source.Name == "StockShelfTop" or source.Name == "DepositBorder" then kitchen else anchors
		end
	end
	local function Anchor(name: string, position: Vector3, size: Vector3, target: Vector3?): ()
		local cf = if target then CFrame.lookAt(position, target) else CFrame.new(position)
		Piece(anchors, name, size, transform * cf, "FFFFFF", false)
	end
	-- 玩家面对原货架时，右手边为模板局部 -X；原交货区和货架几何保持原样。
	Anchor("PackerSpot", Vector3.new(8.3, 0.2, 33.7), Vector3.one * 0.2, Vector3.new(8.3, 0.2, 31.7))
	Anchor("FoodDepositTarget", Vector3.new(8.3, 2.95, 31.7), Vector3.one * 0.2, nil)
	Piece(packing, "PackageShelf", Vector3.new(2.6, 2.6, 1.9), transform * CFrame.new(4.3, 1.3, 31.7), "976D45", true)
	Piece(packing, "PackageShelfTop", Vector3.new(2.8, 0.26, 2.1), transform * CFrame.new(4.3, 2.63, 31.7), "D6AF76", true)
	Anchor("PackedDisplay", Vector3.new(4.3, 2.86, 31.7), Vector3.one * 0.2, nil)
	Anchor("PackageApproachSpot", Vector3.new(1.8, 0.2, 29), Vector3.one * 0.2, nil)
	Anchor("PackagePickupSpot", Vector3.new(3.9, 0.2, 29), Vector3.one * 0.2, nil)
	Anchor("PackagePickupZone", Vector3.new(3.9, 0.2, 29), Vector3.new(3, 0.2, 3), nil)
	local pickupZone = anchors:WaitForChild("PackagePickupZone") :: BasePart
	pickupZone:SetAttribute("FarmUIEntry", "PackagePickup")
	pickupZone:SetAttribute("FarmUIRange", 4)
	-- 只清理明确淘汰的展示占位和旧装饰，运行期区域与路径锚点仍由业务使用。
	for _, part in restaurant:GetDescendants() do
		if part:IsA("BasePart") and (RetiredParts[part.Name] or part.Name:match("^DisplayFood%d+$")) then part:Destroy() end
	end
	local management = anchors:WaitForChild("UpgradeZone") :: BasePart
	management.CFrame = transform * CFrame.new(-0.6, 0.13, 23.3) * CFrame.Angles(0, math.pi, 0)
	management:SetAttribute("FarmUIRange", 6)
	Anchor("CounterDropSpot", Vector3.new(-1.2, 0.2, 40.55), Vector3.one * 0.2, nil)
	Anchor("CounterDropZone", Vector3.new(-1.2, 0.2, 40.55), Vector3.new(5, 0.2, 3), nil)
	Anchor("CounterDisplay", Vector3.new(-1.2, 2.75, 42.55), Vector3.one * 0.2, nil)
	for _, name in { "WorkerSpot1", "WorkerSpot2" } do
		local spot = anchors:FindFirstChild(name) :: BasePart
		spot.Transparency, spot.CanCollide, spot.CanQuery = 1, false, false
	end
	map:SetAttribute("RestaurantFlowVersion", 5)
end
Build(template)
for _, map in workspace.PersonalFarms:GetChildren() do Build(map) end
-- HUD 采用现有模板的同一库存文字框，增加宽度以容纳六项流转状态。
local hud = replicated.UI:FindFirstChild("RoastChickenHUDFrame", true)
if hud then
	local text = hud:FindFirstChild("StockText", true)
	if text and text:IsA("TextLabel") then
		local pill = text.Parent
		if pill and pill:IsA("Frame") then pill.Size = UDim2.fromOffset(1080, 44) end
		text.Size = UDim2.fromOffset(1000, 42)
		text:SetAttribute("DesignTextSize", 24)
		text.TextSize = 24
		text.Text = "Waiting 0 · Packing 0 · Ready 0 · Carry 0 · Counter 0 · Value 0"
	end
end
local localization = game:GetService("LocalizationService"):FindFirstChild("FarmLocalizationTable")
if localization and localization:IsA("LocalizationTable") then
	local entries = localization:GetEntries()
	local additions = {
		{ Key = "FarmTakeAllPackages", Source = "Take all", Values = { ["zh-cn"] = "全部取走" } },
		{ Key = "FarmPackedFood", Source = "Packed food", Values = { ["zh-cn"] = "打包成品" } },
		{ Key = "FarmPackingDeliverySign", Source = "Packing table\nDeliver food here", Values = { ["zh-cn"] = "打包台\n在此交付食材" } },
		{ Key = "FarmPackingEntranceSign", Source = "Kitchen entrance\nDeliver food at the packing table", Values = { ["zh-cn"] = "后厨入口\n请到打包台交付食材" } },
		{ Key = "FarmUITransportWorkers", Source = "{1} waiters / 1 packer / {2} kg/s", Values = { ["zh-cn"] = "{1}名服务员 / 1名打包员 / {2} kg/s" } },
		{ Key = "FarmRestaurantBoard", Source = "Waiting {1} · Packing {2}\nReady {3} · Carry {4} · Counter {5}\nUnsold value {6}", Values = { ["zh-cn"] = "等待 {1} · 打包 {2}\n待搬 {3} · 搬运 {4} · 前台 {5}\n未售价值 {6}" } },
		{ Key = "FarmRestaurantStock", Source = "Waiting {1} · Packing {2} · Ready {3} · Carry {4} · Counter {5} · Value {6}", Values = { ["zh-cn"] = "等待 {1} · 打包 {2} · 待搬 {3} · 搬运 {4} · 前台 {5} · 预计 {6}" } },
		{ Key = "FarmPackerWorking", Source = "Packer · {1} seconds", Values = { ["zh-cn"] = "打包员 · 还需 {1}秒" } },
		{ Key = "FarmPackerIdle", Source = "Packer · Ready", Values = { ["zh-cn"] = "打包员 · 空闲" } },
		{ Key = "FarmPackagesReady", Source = "Ready to carry · {1}", Values = { ["zh-cn"] = "待搬运 · {1}份" } },
		{ Key = "FarmPackagesCounter", Source = "Counter {1} · Customers {2}", Values = { ["zh-cn"] = "前台 {1}份 · 顾客 {2}位" } },
		{ Key = "FarmPackageCarried", Source = "Carrying {1} packages", Values = { ["zh-cn"] = "携带 {1}份成品" } },
		{ Key = "FarmTransportIdle", Source = "Waiter {1} · Ready · {2} packages", Values = { ["zh-cn"] = "服务员 {1} · 待命 · {2}份" } },
		{ Key = "FarmTransportPickup", Source = "Waiter {1} · Picking up · {2} packages", Values = { ["zh-cn"] = "服务员 {1} · 前往取货 · {2}份" } },
		{ Key = "FarmTransportDrop", Source = "Waiter {1} · Delivering · {2} packages", Values = { ["zh-cn"] = "服务员 {1} · 送往前台 · {2}份" } },
		{ Key = "FarmTransportReturn", Source = "Waiter {1} · Returning · {2} packages", Values = { ["zh-cn"] = "服务员 {1} · 返回 · {2}份" } },
		{ Key = "FarmLoopHint", Source = "Deliver → Pack → Carry to counter → Sell", Values = { ["zh-cn"] = "交货 → 打包 → 搬到前台 → 顾客购买" } },
		{ Key = "FarmRestaurantBoard", Source = "Waiting {1} · Packing {2}\nReady {3} · Carry {4} · Counter {5}\nUnsold value {6}", Values = { ["zh-cn"] = "等待 {1} · 打包 {2}\n待搬 {3} · 搬运 {4} · 前台 {5}\n未售价值 {6}" } },
		{ Key = "FarmRestaurantStock", Source = "Food shelf {1} / {2}\nService counters {3}", Values = { ["zh-cn"] = "等待 {1} · 打包 {2} · 待搬 {3} · 搬运 {4} · 前台 {5} · 预计 {6}" } }
	}
	for _, entry in additions do
		local found = false
		for index, previous in entries do if previous.Key == entry.Key then entries[index] = entry; found = true; break end end
		if not found then table.insert(entries, entry) end
	end
	localization:SetEntries(entries)
end
history:SetWaypoint("Restaurant packaging flow created")
return { farms = #workspace.PersonalFarms:GetChildren(), models = { "FarmPackerTemplate", "FarmCustomerTemplate", "FarmPackageTemplate" } }
