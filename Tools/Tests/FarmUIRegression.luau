-- 农场界面回归：在 Play 客户端隔离数据和网络，验证路由、模态内请求及销毁
--!strict
assert(game:GetService("RunService"):IsClient(), "Run in Play client")
local Storage = game:GetService("ReplicatedStorage")
local Client = Storage.Scripts.Client
local Manager = require(Client.ClientFarmSpeciesManager)
local UI = require(Client.UIManager)
local Info = require(Client.ClientGameInfo)
local Net = require(Storage.Scripts.Shared.NetMsg)
local Common = require(Client.FarmWindows.Common)
local Rules = require(Storage.Scripts.Shared.FarmUIConfig)
local player = game.Players.LocalPlayer
local character = player.Character
assert(character)
local oldPivot = character:GetPivot()
local originalInfo, originalSend = Info.GetFarmInfo, Net.FireRequestFarmCommand
local fake = table.clone(originalInfo())
fake.ready, fake.cash, fake.stage = true, 1000000, 5
local requests: { { [string]: unknown } } = {}
local manager = Manager.new()
local screen = player.PlayerGui:WaitForChild("GameScreenGui") :: ScreenGui
local checks: { string } = {}
UI.CloseAllWindow()
Info.GetFarmInfo = function() return fake end
Net.FireRequestFarmCommand = function(command: { [string]: unknown }): () table.insert(requests, command) end
local success, failure = xpcall(function(): boolean
	manager:Init(screen); manager:Init(screen)
	local farm = workspace.PersonalFarms:FindFirstChild(tostring(player:GetAttribute("FarmPlotId")))
	assert(farm)
	local entries: { [string]: BasePart } = {}
	for _, part in farm:GetDescendants() do if part:IsA("BasePart") then local id = part:GetAttribute("FarmUIEntry"); if typeof(id) == "string" then entries[id] = part end end end
	for _, id in Rules.Windows do
		if id == "Hatch" then fake.eggId = "ui-fixture-egg"; fake.eggEndTime = workspace:GetServerTimeNow() + 30; fake.eggPrice = 5 end
		local source = entries[if Rules.ToolWindows[id] then "ToolShop" else id]
		if source then character:PivotTo(source.CFrame * CFrame.new(0, 3, 0)) end
		manager:Open(id, source)
		assert(UI.IsWindowShowing("Farm" .. id), "Route failed: " .. id)
		local frame = screen:FindFirstChild("Farm" .. id .. "Frame") :: Frame
		assert(frame and frame.Size == UDim2.fromOffset(1920, 1080))
		assert((screen:WaitForChild("ModalButton") :: ImageButton).Visible)
		for _, other in Rules.Windows do if other ~= id then assert(not UI.IsWindowShowing("Farm" .. other), "Main windows overlap") end end
		manager:CloseMain()
	end
	table.insert(checks, "9 independent routes and exclusive modal windows")
	manager:Open("WeaponShop")
	assert(not UI.IsWindowShowing("FarmWeaponShop"), "Weapon shop opened without a tool shop session")
	manager:Open("ToolShop")
	manager:Open("WeaponShop")
	assert(UI.IsWindowShowing("FarmWeaponShop"), "HUD tool shop view failed")
	manager:CloseMain()
	table.insert(checks, "HUD tool shop opens weapon shop and rejects a bare weapon route")
	character:PivotTo(entries.ToolShop.CFrame * CFrame.new(0,3,0))
	manager:Open("WeaponEnhance", entries.ToolShop)
	local frame = screen:FindFirstChild("FarmWeaponEnhanceFrame") :: Frame
	-- 使用真实窗口基类管理测试请求的超时任务。
	local Window = require(Client.UIManager.WindowBase)
	local ctx: Common.Context = { window = Window.new(frame, "FixtureRequest", UI.GetUIActions()), panel = frame:WaitForChild("PanelFrame") :: Frame, pending = false, open = function(): () end, allowed = function(): boolean return true end }
	Common.Submit(ctx, { action = "enhanceWeapon", expectedStep = 8 }, function(): () end)
	Common.Submit(ctx, { action = "enhanceWeapon", expectedStep = 8 }, function(): () end)
	assert(#requests == 1 and requests[1].expectedStep == 8, "Modal request blocked or duplicated")
	ctx.window.scope:Destroy()
	table.insert(checks, "Purchase inside modal and repeated submission blocked")
	character:PivotTo(oldPivot * CFrame.new(0,0,200)); manager:Scan()
	assert(not UI.IsWindowShowing("FarmWeaponEnhance"), "Out-of-range window remained open")
	table.insert(checks, "Leaving shop closes window")
	character:PivotTo(entries.Species.CFrame * CFrame.new(0,3,0))
	manager:Open("Species", entries.Species)
	fake.confirmationId, fake.confirmationMessage, fake.confirmationRisk = "fixture-token", "Fixture confirmation", "No real purchase"
	manager:Refresh()
	assert(UI.IsWindowShowing("FarmConfirmation") and UI.IsWindowShowing("FarmSpecies"), "Confirmation lost its parent")
	UI.CloseWindow("FarmConfirmation")
	assert(requests[#requests].action == "cancel" and requests[#requests].confirmationId == "fixture-token")
	assert(UI.IsWindowShowing("FarmSpecies"), "Cancel closed parent window")
	fake.confirmationId = nil; manager:Refresh(); manager:CloseMain()
	table.insert(checks, "Confirmation overlay preserves parent and cancels its token")
	fake.eggId, fake.eggEndTime = "fixture-hold", workspace:GetServerTimeNow() + 30
	manager:Open("Hatch")
	assert(manager:StartHatchHold(true) and requests[#requests].action == "accelerateEgg", "Hatch button cannot work inside its modal")
	manager:CloseMain()
	local sentBefore = #requests
	task.wait(0.85)
	assert(not manager.holding and #requests == sentBefore, "Hatch hold leaked after close")
	table.insert(checks, "Hatch hold works inside modal and stops when closed")
	local savedLevels = fake.weaponLevels
	fake.weaponLevels = { ["1"] = 5, ["2"] = 5, ["3"] = 5, ["4"] = 5, ["5"] = 5 }
	fake.zap, fake.weaponLevel, fake.collect, fake.basketTier, fake.restaurantLevel = 5, 5, 5, 5, 5
	character:PivotTo(entries.ToolShop.CFrame * CFrame.new(0,3,0))
	for _, id in { "WeaponEnhance", "CollectorShop", "BasketShop" } do
		manager:Open(id, entries.ToolShop)
		local main = screen:FindFirstChild("Farm" .. id .. "Frame") :: Frame
		local details = main:WaitForChild("PanelFrame"):WaitForChild("DetailsFrame")
		assert(not Common.Button(details, "PurchaseButton").Active, "Maximum tier still purchasable")
		manager:CloseMain()
	end
	fake.weaponLevels = savedLevels
	fake.zap, fake.weaponLevel, fake.collect, fake.basketTier, fake.restaurantLevel, fake.cash = 1, 1, 1, 1, 1, 0
	manager:Open("BasketShop", entries.ToolShop)
	assert(not Common.Button((screen:FindFirstChild("FarmBasketShopFrame") :: Frame):WaitForChild("PanelFrame"):WaitForChild("DetailsFrame"), "PurchaseButton").Active)
	manager:CloseMain()
	table.insert(checks, "Maximum tier and insufficient funds disable purchases")
	manager:Open("Equipment")
	fake.ready = false; manager:Refresh()
	assert(not UI.IsWindowShowing("FarmEquipment"))
	fake.ready = true
	manager:Open("Hatch")
	fake.eggId = nil; manager:Refresh()
	assert(not UI.IsWindowShowing("FarmHatch") and not manager.holding)
	table.insert(checks, "Unready and lost egg close windows")
	for _ = 1, 15 do manager:Open("Equipment"); manager:CloseMain() end
	manager:Destroy(); manager:Destroy()
	assert(not UI.HasShowingWindow())
	table.insert(checks, "Repeated open-close and idempotent destruction")
	return true
end, debug.traceback)
manager:Destroy()
Info.GetFarmInfo, Net.FireRequestFarmCommand = originalInfo, originalSend
character:PivotTo(oldPivot)
assert(success, failure)
return checks
