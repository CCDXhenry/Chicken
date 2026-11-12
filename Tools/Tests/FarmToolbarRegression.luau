-- 双槽工具栏离线回归：执行真实控制器、服务端入口与表现层，验证使用门禁和装备保持
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Instance = roblox.Instance
local checks = 0
local function Check(value, message)
	assert(value, message)
	checks += 1
end
local function Node(name)
	return { Name = name, WaitForChild = function(_, child) return Node(child) end }
end
local character = Instance.new("Model")
local backpack = Instance.new("Backpack")
local alive, modal, focused, now = true, false, nil, 1
local humanoid = { Health = 100 }
local equipCount = 0
function humanoid:EquipTool(tool)
	equipCount += 1
	for _, child in character:GetChildren() do if child:IsA("Tool") then child.Parent = backpack end end
	tool.Parent = character
end
function humanoid:UnequipTools()
	for _, child in character:GetChildren() do if child:IsA("Tool") then child.Parent = backpack end end
end
local char = {
	FindFirstChild = function(_, name) return character:FindFirstChild(name) end,
	FindFirstChildOfClass = function() return humanoid end,
	GetChildren = function() return character:GetChildren() end,
}
local player = {
	Character = char,
	FindFirstChildOfClass = function() return backpack end,
}
local inputService = { GetFocusedTextBox = function() return focused end }
local guiService = { MenuIsOpen = false }
local config = { ZapCooldownSeconds = 0.35, CollectCooldownSeconds = 0.35 }
local modules = {
	LifecycleTool = { new = function() return { alive = true } end },
	FarmEconomyConfig = config,
	ClientGameInfo = { GetFarmInfo = function() return { ready = alive } end },
	UIManager = { HasShowingWindow = function() return modal end },
}
local services = {
	Players = { LocalPlayer = player }, ReplicatedStorage = Node("ReplicatedStorage"),
	UserInputService = inputService, GuiService = guiService,
}
local env = {
	game = { GetService = function(_, name) return services[name] or Node(name) end },
	script = { Parent = Node("Client") },
	require = function(target) return modules[target.Name] or {} end,
	setmetatable = setmetatable, pairs = pairs, ipairs = ipairs, assert = assert,
	math = math, string = string, table = table, tostring = tostring,
	CFrame = roblox.CFrame, Vector3 = roblox.Vector3, Color3 = roblox.Color3,
	os = { clock = function() return now end },
}
local controllerModule = luau.load(fs.readFile("Scripts/ReplicatedStorage/Scripts/Client/ClientFarmToolbar.luau"), { environment = env })()
local calls = {}
local controller = controllerModule.new(function(slot) table.insert(calls, slot) end)
-- 只替换渲染边界；选择、手持检查、冷却与取消均执行生产方法。
controller.RefreshEquipped = function(self)
	self.selected = if character:FindFirstChild("FarmWeapon") then "zap" elseif character:FindFirstChild("FarmCollector") then "collect" else nil
end
local weapon = Instance.new("Tool"); weapon.Name = "FarmWeapon"; weapon.Parent = backpack
local collector = Instance.new("Tool"); collector.Name = "FarmCollector"; collector.Parent = backpack
controller.pending = "zap"; controller:EquipPending(); controller:RefreshEquipped()
Check(controller.selected == "zap" and #calls == 0, "default equip never uses tool")
controller:Select("collect")
Check(controller.selected == "collect" and weapon.Parent == backpack and #calls == 0, "switch only equips")
controller:Select("collect")
Check(controller.selected == nil and collector.Parent == backpack, "repeat slot unequips")
controller:Start({}); Check(#calls == 0, "empty hands cannot use")
controller:Select("zap"); controller:Start({})
Check(#calls == 1 and calls[1] == "zap", "press triggers once immediately")
controller:Start({}); controller:UpdateUse(); Check(#calls == 1, "duplicate press and same frame do not repeat")
now = 1.34; controller:UpdateUse(); Check(#calls == 1, "cooldown enforced")
now = 1.36; controller:UpdateUse(); Check(#calls == 2, "hold repeats after cooldown")
controller:Stop(); now = 2; controller:UpdateUse(); Check(#calls == 2, "release stops repeating")
for _, block in { "modal", "text", "menu", "death", "notReady" } do
	controller:Start({}); local before = #calls
	if block == "modal" then modal = true elseif block == "text" then focused = {} elseif block == "menu" then guiService.MenuIsOpen = true elseif block == "death" then humanoid.Health = 0 else alive = false end
	now += 1; controller:UpdateUse()
	Check(#calls == before and controller.held == nil, block .. " cancels hold")
	modal, focused, guiService.MenuIsOpen, humanoid.Health, alive = false, nil, false, 100, true
	controller:UpdateUse(); Check(#calls == before, "unblocking does not resume automatically")
end
controller:Start({}); local before = #calls; controller:Select("collect"); now += 1; controller:UpdateUse()
Check(#calls == before and controller.held == nil, "switch stops old action")

-- 真正执行服务器 OnAction；用 GetPlayerRoot 边界标记是否通过装备校验，避免调用经营系统。
local reached = false
modules.ServerGameInfo = { GetPlayerInfo = function() return {} end }
modules.FarmBusiness = { GetPurchasePrice = function() return nil end }
modules.ServerFarmSceneTool = { GetPlayerRoot = function() reached = true; return nil end }
local server = luau.load(fs.readFile("Scripts/ServerStorage/Scripts/ServerPersonalFarmManager.luau"), { environment = env })()
local session = { farm = { equippedWeaponTier = 2, collectTier = 3, weaponLevels = { ["2"] = 4 } }, cooldowns = {} }
local manager = setmetatable({ sessions = { [player] = session }, running = true }, server)
weapon:SetAttribute("WeaponTier", 2); weapon:SetAttribute("WeaponLevel", 4); collector:SetAttribute("CollectorTier", 3)
local function Accepts(action)
	reached = false; manager:OnAction(player, action); return reached
end
Check(Accepts("collect") and not Accepts("zap"), "server accepts only actual held collector")
collector:SetAttribute("CollectorTier", 2); Check(not Accepts("collect"), "server rejects stale collector tier"); collector:SetAttribute("CollectorTier", 3)
humanoid:EquipTool(weapon)
Check(Accepts("zap") and not Accepts("collect"), "server accepts only actual held weapon")
weapon:SetAttribute("WeaponLevel", 3); Check(not Accepts("zap"), "server rejects stale weapon level"); weapon:SetAttribute("WeaponLevel", 4)
weapon:SetAttribute("WeaponTier", 1); Check(not Accepts("zap"), "server rejects stale weapon tier"); weapon:SetAttribute("WeaponTier", 2)
weapon.Enabled = false; Check(not Accepts("zap"), "server rejects disabled tool"); weapon.Enabled = true
humanoid.Health = 0; Check(not Accepts("zap"), "server rejects dead character"); humanoid.Health = 100
humanoid:UnequipTools(); Check(not Accepts("zap") and not Accepts("collect"), "server rejects empty hands")

-- 独立的轻量容器夹具保留 Parent 身份，验证服务端替换 Tool 的位置语义。
local viewChar, viewBackpack = {}, {}
local viewHumanoid = { Health = 100 }
local viewItems = {}
local viewEquips = 0
local function FakeTool(name, tier, level)
	local attrs = { WeaponTier = tier, WeaponLevel = level }
	local tool = { Name = name, Parent = viewBackpack }
	function tool:IsA(class) return class == "Tool" end
	function tool:GetAttribute(key) return attrs[key] end
	function tool:Destroy() self.Parent = nil end
	table.insert(viewItems, tool)
	return tool
end
function viewChar:GetChildren() local out = {}; for _, tool in viewItems do if tool.Parent == self then table.insert(out, tool) end end; return out end
viewBackpack.GetChildren = viewChar.GetChildren
function viewChar:FindFirstChildOfClass() return viewHumanoid end
function viewHumanoid:EquipTool(tool)
	viewEquips += 1
	for _, item in viewItems do if item.Parent == viewChar then item.Parent = viewBackpack end end
	tool.Parent = viewChar
end
local viewPlayer = { Character = viewChar, FindFirstChildOfClass = function() return viewBackpack end }
modules.ServerWeaponBuilder = { BuildWeaponTool = function(tier, level) return FakeTool("FarmWeapon", tier, level) end }
local view = luau.load(fs.readFile("Scripts/ServerStorage/Scripts/ServerPersonalFarmView.luau"), { environment = env })()
session.owner = viewPlayer
local viewWeapon = FakeTool("FarmWeapon", 2, 4)
view.UpdateWeaponVisual(session)
Check(viewEquips == 0, "farm refresh preserves empty hands")
local viewCollector = FakeTool("FarmCollector", 3, nil); viewCollector.Parent = viewChar
view.UpdateWeaponVisual(session)
Check(viewEquips == 0 and viewCollector.Parent == viewChar, "farm refresh does not steal collector slot")
viewCollector.Parent = viewBackpack; viewWeapon.Parent = viewChar
session.farm.weaponLevels["2"] = 5
view.UpdateWeaponVisual(session)
Check(viewEquips == 1 and viewItems[#viewItems].Parent == viewChar and viewItems[#viewItems]:GetAttribute("WeaponLevel") == 5, "upgrading held weapon preserves hand")

local roots = roblox.deserializeModel(fs.readFile("Assets/Studio/FarmUITemplates.rbxm"))
local ui = roots[1]
Check(ui.RoastChickenHUDFrame:FindFirstChild("ActionsFrame") == nil, "old action cards removed")
for _, name in { "WeaponButton", "CollectorButton" } do
	local button = ui.RoastChickenHUDFrame.BottomButtonsFrame[name]
	Check(button.ToolViewport:IsA("ViewportFrame") and button.ToolViewport:FindFirstChild("WorldModel") and button.ToolViewport:FindFirstChild("Camera"), "preview hierarchy persisted")
	Check(string.find(tostring(button.ImageContent), "18300392432", 1, true) ~= nil, "slot uses imported reference texture")
	Check(button.Size == roblox.UDim2.fromOffset(132, 132), "reference slot dimensions")
	Check(string.find(tostring(button.EquippedImage.ImageContent), "18300392104", 1, true) ~= nil and button.EquippedImage.ImageColor3 == roblox.Color3.new(1, 1, 0), "original yellow equipped image")
	Check(button.ToolViewport:GetAttribute("PreviewFieldOfView") == 35, "camera parameters replicate as attributes")
	Check(button.ToolViewport.Size.Y.Offset * button.ToolViewport.UIScale.Scale == 128, "model fills reference icon layer")
	Check(button.ToolNameText.ZIndex > button.ToolViewport.ZIndex and button.ToolLvText.ZIndex > button.ToolViewport.ZIndex, "text overlays model")
	Check(button.ToolNameText.Position.Y.Offset == -10 and button.ToolNameText.AnchorPoint.Y == 1, "reference name is anchored inside bottom edge")
	Check(button:GetAttribute("HasInteractionEffect") == true and button.UIScale.Scale == 1 and button.AnchorPoint == roblox.Vector2.new(0.5, 0.5), "reference centered interaction scaling")
end
Check(ui.FarmTouchUseFrame.UseButton:GetAttribute("AttackRectOffset") ~= ui.FarmTouchUseFrame.UseButton:GetAttribute("CollectRectOffset"), "touch actions use distinct atlas regions")
local use = ui.FarmTouchUseFrame.UseButton
Check(use.AnchorPoint == roblox.Vector2.new(0.5, 0.5) and use.Position == roblox.UDim2.fromScale(0.5, 0.5), "touch scaling stays centered")
Check(use:FindFirstChild("UIScale") and use:GetAttribute("PressedScale") == 0.86, "touch press scale is template driven")
Check(use.ActionText.Position.Y.Scale + use.ActionText.Size.Y.Scale < 1, "touch label remains within full icon")
local previewContracts = 0
for _, name in { "FarmWeaponShopFrame", "FarmEquipmentFrame", "FarmWeaponEnhanceFrame", "FarmToolShopFrame" } do
	for _, instance in ui[name]:GetDescendants() do
		local tier = instance:GetAttribute("PreviewWeaponTier")
		if instance:IsA("ViewportFrame") and typeof(tier) == "number" then
			Check(#instance:FindFirstChildOfClass("WorldModel"):GetChildren() == 0, "weapon preview cannot preserve independent geometry")
			Check(tier >= 0 and tier <= 5, "weapon preview tier contract")
			previewContracts += 1
		end
	end
end
Check(previewContracts == 17, "all weapon previews use canonical source contract")
local bottom = ui.RoastChickenHUDFrame.BottomButtonsFrame
Check(bottom.UIListLayout.Padding == roblox.UDim.new(0, 18), "reference 18px spacing")
Check(not bottom.ToolButton.Visible, "reference template is hidden")
for _, name in { "WeaponButton", "CollectorButton" } do
	local button = bottom[name]
	Check(button:GetAttribute("EquippedTint") == nil and button:GetAttribute("UnequippedTint") == nil, "custom dimming removed")
	Check(button.EquippedImage:FindFirstChild("EquippedBadgeText") == nil, "custom badge removed")
	Check(not button.QualityImage.Visible and not button.ToolUsageEffectFrame.Visible, "foreign game features hidden")
end
print("FarmToolbarRegression passed: " .. checks .. " checks")
