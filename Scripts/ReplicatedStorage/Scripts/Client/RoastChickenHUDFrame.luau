-- 农场界面包装器：克隆正式模板，通过客户端数据层刷新单行文案并管理交互生命周期
--!strict
local replicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local sharedScripts = replicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local FarmConfig = require(sharedScripts:WaitForChild("FarmConfig"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local NumberFormat = require(sharedScripts:WaitForChild("FarmNumberFormat"))
local Economy = require(sharedScripts:WaitForChild("FarmEconomyConfig"))
local LifecycleTool = require(sharedScripts:WaitForChild("LifecycleTool"))
local ClientGameInfo = require(script.Parent:WaitForChild("ClientGameInfo"))
local ClientMsg = require(script.Parent:WaitForChild("ClientMsg"))
local UIManager = require(script.Parent:WaitForChild("UIManager"))
local UIAdapter = require(replicatedStorage:WaitForChild("Core"):WaitForChild("Scripts"):WaitForChild("Client"):WaitForChild("UIAdapter"))
local FarmTextTool = require(script.Parent:WaitForChild("FarmTextTool"))
local RoastChickenHUDFrame = {}
RoastChickenHUDFrame.__index = RoastChickenHUDFrame
export type RoastChickenHUDFrame = typeof(setmetatable(
	{} :: {
		container: Frame,
		coinText: TextLabel,
		basketText: TextLabel,
		stockText: TextLabel,
		hintText: TextLabel,
		shopButton: ImageButton,
		indexButton: ImageButton,
		eggButton: ImageButton,
		equipmentButton: ImageButton,
		actionsFrame: Frame,
		zapButton: ImageButton,
		zapNameText: TextLabel,
		zapDetailText: TextLabel,
		collectButton: ImageButton,
		collectNameText: TextLabel,
		collectDetailText: TextLabel,
		saleNoticeText: TextLabel,
		showingMessage: boolean,
		initialized: boolean,
		scope: LifecycleTool.Lifecycle,
		onActionTriggered: (FarmConfig.FarmAction) -> (),
		messageSequence: number,
		saleSequence: number,
	},
	RoastChickenHUDFrame
))
function RoastChickenHUDFrame.new(onActionTriggered: (FarmConfig.FarmAction) -> ()): RoastChickenHUDFrame
	return setmetatable({
		onActionTriggered = onActionTriggered,
		showingMessage = false,
		initialized = false,
		scope = LifecycleTool.new(),
		messageSequence = 0,
		saleSequence = 0,
	}, RoastChickenHUDFrame) :: RoastChickenHUDFrame
end
function RoastChickenHUDFrame.Init(self: RoastChickenHUDFrame, screenGui: ScreenGui): ()
	if self.initialized then
		return
	end
	self.initialized = true
	local container = UIManager.CreateFrame("RoastChickenHUDFrame", screenGui, 0)
	self.container = container
	self.scope:Own(container)
	local topStatusPill = container:WaitForChild("TopStatusPill")
	self.stockText = topStatusPill:WaitForChild("StockText") :: TextLabel
	local statsCardFrame = container:WaitForChild("StatsCardFrame")
	local basketRow = statsCardFrame:WaitForChild("BasketRow")
	self.basketText = basketRow:WaitForChild("BasketText") :: TextLabel
	local coinRow = statsCardFrame:WaitForChild("CoinRow")
	self.coinText = coinRow:WaitForChild("CoinText") :: TextLabel
	local leftActionsFrame = container:WaitForChild("LeftActionsFrame")
	self.shopButton = leftActionsFrame:WaitForChild("ShopButton") :: ImageButton
	self.indexButton = leftActionsFrame:WaitForChild("IndexButton") :: ImageButton
	local rightActionsFrame = container:WaitForChild("RightActionsFrame")
	self.eggButton = rightActionsFrame:WaitForChild("EggButton") :: ImageButton
	self.equipmentButton = rightActionsFrame:WaitForChild("EquipmentButton") :: ImageButton
	self.hintText = container:WaitForChild("FarmHintText") :: TextLabel
	self.actionsFrame = container:WaitForChild("ActionsFrame") :: Frame
	self.zapButton = self.actionsFrame:WaitForChild("ZapButton") :: ImageButton
	self.zapNameText = self.zapButton:WaitForChild("ActionNameText") :: TextLabel
	self.zapDetailText = self.zapButton:WaitForChild("ActionDetailText") :: TextLabel
	self.collectButton = self.actionsFrame:WaitForChild("CollectButton") :: ImageButton
	self.collectNameText = self.collectButton:WaitForChild("ActionNameText") :: TextLabel
	self.collectDetailText = self.collectButton:WaitForChild("ActionDetailText") :: TextLabel
	self.saleNoticeText = container:WaitForChild("SaleNoticeText") :: TextLabel
	UIAdapter.AddAdaptiveFrame(container, UIAdapter.AdaptiveType.Center)
	self:BindEvents()
	self.scope:Connect(ClientMsg.ConnectFarmInfoChanged(function()
		self:Render()
	end))
	local function OnInputChanged(): () self:Render() end
	self.scope:Connect(UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(OnInputChanged))
	self:Render()
	UIManager.FitMarkedRoot(container)
end
function RoastChickenHUDFrame.BindEvents(self: RoastChickenHUDFrame): ()
	local function OnZap(): ()
		self.onActionTriggered("zap")
	end
	local function OnCollect(): ()
		self.onActionTriggered("collect")
	end
	local function BindActivated(button: ImageButton, onActivated: () -> ()): ()
		self.scope:Connect(button.Activated:Connect(onActivated))
	end
	BindActivated(self.zapButton, OnZap)
	BindActivated(self.collectButton, OnCollect)
end
function RoastChickenHUDFrame.Render(self: RoastChickenHUDFrame): ()
	local info = ClientGameInfo.GetFarmInfo()
	FarmTextTool.Set(self.coinText, string.format("$%s", NumberFormat.Number(info.cash)))
	FarmTextTool.Set(self.basketText, string.format("%s / %s", NumberFormat.Weight(info.basketWeight or 0), NumberFormat.Weight(info.basketCapacity or 12)))
	FarmTextTool.Set(self.stockText, GameTexts.Farm.PersonalKitchen.source:format(info.waiting or 0, info.processing or 0, NumberFormat.Number(info.expectedValue or 0)))
	local touch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
	FarmTextTool.Set(self.zapNameText, if touch then GameTexts.Farm.ZapTouch.source else GameTexts.Farm.ZapActionName.source)
	FarmTextTool.Set(self.zapDetailText, GameTexts.Farm.PersonalWeapon.source:format(info.zap, info.weaponLevel or 1, NumberFormat.Number(info.damage or 2)))
	FarmTextTool.Set(self.collectNameText, if touch then GameTexts.Farm.CollectTouch.source else GameTexts.Farm.CollectActionName.source)
	FarmTextTool.Set(self.collectDetailText, GameTexts.Farm.CollectActionDetail.source:format(GameTexts.CollectNames[info.collect] or tostring(info.collect), Economy.Collectors[info.collect].maximumItems))
	self.zapButton.Active, self.collectButton.Active = info.ready == true, info.ready == true
	if not self.showingMessage then
		FarmTextTool.Set(self.hintText, if not info.ready then GameTexts.Farm.PlotWaiting.source elseif (info.basketWeight or 0) >= (info.basketCapacity or 12) then GameTexts.Farm.BasketFullHint.source else GameTexts.Farm.LoopHint.source)
	end
	UIManager.FitTextLabel(self.coinText)
	UIManager.FitTextLabel(self.basketText)
	UIManager.FitTextLabel(self.stockText)
end

function RoastChickenHUDFrame.ShowMessage(self: RoastChickenHUDFrame, message: string): ()
	if not self.initialized then
		return
	end
	self.messageSequence += 1
	local sequence = self.messageSequence
	self.showingMessage = true
	FarmTextTool.Set(self.hintText, message)
	self.scope:Delay(FarmConfig.MessageDuration, function()
		if self.messageSequence == sequence then
			self.showingMessage = false
			self:Render()
		end
	end)
end
function RoastChickenHUDFrame.ShowSaleNotice(self: RoastChickenHUDFrame, message: string): ()
	if not self.initialized then
		return
	end
	self.saleSequence += 1
	local sequence = self.saleSequence
	FarmTextTool.Set(self.saleNoticeText, message)
	self.saleNoticeText.Visible = true
	self.scope:Delay(FarmConfig.SaleNoticeDuration, function()
		if self.saleSequence == sequence then
			self.saleNoticeText.Visible = false
		end
	end)
end
function RoastChickenHUDFrame.Destroy(self: RoastChickenHUDFrame): ()
	if not self.initialized then
		return
	end
	self.initialized = false
	FarmTextTool.Remove(self.container)
	UIAdapter.RemoveAdaptiveFrame(self.container)
	self.scope:Destroy()
end
return RoastChickenHUDFrame
