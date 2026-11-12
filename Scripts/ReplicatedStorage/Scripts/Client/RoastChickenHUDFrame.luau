-- 农场界面包装器：克隆正式模板，通过客户端数据层刷新单行文案并管理交互生命周期
--!strict
local replicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CAPACITY_DENIED_COLOR = Color3.fromRGB(255, 56, 56)
local BASKET_FULL_COLOR = Color3.fromRGB(255, 80, 80)
local BASKET_NORMAL_COLOR = Color3.fromRGB(255, 255, 255)
local PULSE_SCALE = 1.18
local PULSE_UP = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PULSE_DOWN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
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
		basketScale: UIScale,
		stockText: TextLabel,
		hintText: TextLabel,
		hintScale: UIScale,
		hintRestColor: Color3,
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
		emphasizingCapacity: boolean,
		initialized: boolean,
		scope: LifecycleTool.Lifecycle,
		onActionTriggered: (FarmConfig.FarmAction) -> (),
		messageSequence: number,
		saleSequence: number,
		pulseToken: number,
		pulseTweens: { Tween },
	},
	RoastChickenHUDFrame
))
function RoastChickenHUDFrame.new(onActionTriggered: (FarmConfig.FarmAction) -> ()): RoastChickenHUDFrame
	return setmetatable({
		onActionTriggered = onActionTriggered,
		showingMessage = false,
		emphasizingCapacity = false,
		initialized = false,
		scope = LifecycleTool.new(),
		messageSequence = 0,
		saleSequence = 0,
		pulseToken = 0,
		pulseTweens = {} :: { Tween },
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
	self.basketScale = self.basketText:WaitForChild("UIScale") :: UIScale
	local coinRow = statsCardFrame:WaitForChild("CoinRow")
	self.coinText = coinRow:WaitForChild("CoinText") :: TextLabel
	local leftActionsFrame = container:WaitForChild("LeftActionsFrame")
	self.shopButton = leftActionsFrame:WaitForChild("ShopButton") :: ImageButton
	self.indexButton = leftActionsFrame:WaitForChild("IndexButton") :: ImageButton
	local rightActionsFrame = container:WaitForChild("RightActionsFrame")
	self.eggButton = rightActionsFrame:WaitForChild("EggButton") :: ImageButton
	self.equipmentButton = rightActionsFrame:WaitForChild("EquipmentButton") :: ImageButton
	self.hintText = container:WaitForChild("FarmHintText") :: TextLabel
	self.hintScale = self.hintText:WaitForChild("UIScale") :: UIScale
	self.hintRestColor = self.hintText.TextColor3
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
	local isFull = (info.basketWeight or 0) >= (info.basketCapacity or 12)
	FarmTextTool.Set(self.basketText, string.format("%s / %s", NumberFormat.Weight(info.basketWeight or 0), NumberFormat.Weight(info.basketCapacity or 12)))
	if not self.emphasizingCapacity then
		self.basketText.TextColor3 = if isFull then BASKET_FULL_COLOR else BASKET_NORMAL_COLOR
	end
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

function RoastChickenHUDFrame.StopCapacityPulse(self: RoastChickenHUDFrame): ()
	self.pulseToken += 1
	local tweens = self.pulseTweens
	self.pulseTweens = {} :: { Tween }
	for _, tween in tweens do
		if tween.PlaybackState == Enum.PlaybackState.Playing then
			tween:Cancel()
		end
		tween:Destroy()
	end
	if self.initialized then
		self.hintScale.Scale = 1
		self.basketScale.Scale = 1
	end
end
function RoastChickenHUDFrame.PlayCapacityPulse(self: RoastChickenHUDFrame): ()
	self:StopCapacityPulse()
	local token = self.pulseToken
	local function Pulse(scale: UIScale): ()
		local up = TweenService:Create(scale, PULSE_UP, { Scale = PULSE_SCALE })
		local down = TweenService:Create(scale, PULSE_DOWN, { Scale = 1 })
		table.insert(self.pulseTweens, up)
		table.insert(self.pulseTweens, down)
		up.Completed:Once(function(state: Enum.PlaybackState): ()
			if not self.scope.alive or token ~= self.pulseToken or state ~= Enum.PlaybackState.Completed then
				return
			end
			self.scope:Play(down)
		end)
		self.scope:Play(up)
	end
	Pulse(self.hintScale)
	Pulse(self.basketScale)
end
function RoastChickenHUDFrame.ApplyBasketColor(self: RoastChickenHUDFrame): ()
	local info = ClientGameInfo.GetFarmInfo()
	local isFull = (info.basketWeight or 0) >= (info.basketCapacity or 12)
	self.basketText.TextColor3 = if isFull then BASKET_FULL_COLOR else BASKET_NORMAL_COLOR
end
function RoastChickenHUDFrame.ShowMessage(self: RoastChickenHUDFrame, message: string): ()
	if not self.initialized then
		return
	end
	if self.emphasizingCapacity then
		self.emphasizingCapacity = false
		self:StopCapacityPulse()
		self.hintText.TextColor3 = self.hintRestColor
		self:ApplyBasketColor()
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
function RoastChickenHUDFrame.ShowCapacityDenied(self: RoastChickenHUDFrame, message: string): ()
	if not self.initialized then
		return
	end
	self.messageSequence += 1
	local sequence = self.messageSequence
	self.showingMessage = true
	self.emphasizingCapacity = true
	FarmTextTool.Set(self.hintText, message)
	UIManager.FitTextLabel(self.hintText)
	self.hintText.TextColor3 = CAPACITY_DENIED_COLOR
	self.basketText.TextColor3 = CAPACITY_DENIED_COLOR
	self:PlayCapacityPulse()
	self.scope:Delay(FarmConfig.MessageDuration, function()
		if self.messageSequence ~= sequence then
			return
		end
		self.showingMessage = false
		self.emphasizingCapacity = false
		self:StopCapacityPulse()
		self.hintText.TextColor3 = self.hintRestColor
		self:Render()
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
	self:StopCapacityPulse()
	self.emphasizingCapacity = false
	self.initialized = false
	FarmTextTool.Remove(self.container)
	UIAdapter.RemoveAdaptiveFrame(self.container)
	self.scope:Destroy()
end
return RoastChickenHUDFrame
