-- 农场界面包装器：克隆正式模板，通过客户端数据层刷新单行文案并管理交互生命周期
--!strict
local replicatedStorage = game:GetService("ReplicatedStorage")
local sharedScripts = replicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local catalog = require(sharedScripts:WaitForChild("RoastChickenCatalog"))
local FarmConfig = require(sharedScripts:WaitForChild("FarmConfig"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
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
		actionsFrame: Frame,
		zapButton: ImageButton,
		zapNameText: TextLabel,
		zapDetailText: TextLabel,
		collectButton: ImageButton,
		collectNameText: TextLabel,
		collectDetailText: TextLabel,
		shopFrame: Frame,
		buyZapButton: ImageButton,
		buyZapText: TextLabel,
		buyCollectButton: ImageButton,
		buyCollectText: TextLabel,
		buildingButton: ImageButton,
		buildingTitleText: TextLabel,
		buildingDetailText: TextLabel,
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
	local statusFrame = container:WaitForChild("StatusFrame")
	local statsFrame = statusFrame:WaitForChild("StatsFrame")
	self.coinText = statsFrame:WaitForChild("CoinText") :: TextLabel
	self.basketText = statsFrame:WaitForChild("BasketText") :: TextLabel
	self.stockText = statsFrame:WaitForChild("StockText") :: TextLabel
	self.hintText = container:WaitForChild("FarmHintText") :: TextLabel
	self.actionsFrame = container:WaitForChild("ActionsFrame") :: Frame
	self.zapButton = self.actionsFrame:WaitForChild("ZapButton") :: ImageButton
	self.zapNameText = self.zapButton:WaitForChild("ActionNameText") :: TextLabel
	self.zapDetailText = self.zapButton:WaitForChild("ActionDetailText") :: TextLabel
	self.collectButton = self.actionsFrame:WaitForChild("CollectButton") :: ImageButton
	self.collectNameText = self.collectButton:WaitForChild("ActionNameText") :: TextLabel
	self.collectDetailText = self.collectButton:WaitForChild("ActionDetailText") :: TextLabel
	self.shopFrame = container:WaitForChild("UpgradeShopFrame") :: Frame
	self.buyZapButton = self.shopFrame:WaitForChild("BuyZapButton") :: ImageButton
	self.buyZapText = self.buyZapButton:WaitForChild("ContentText") :: TextLabel
	self.buyCollectButton = self.shopFrame:WaitForChild("BuyCollectButton") :: ImageButton
	self.buyCollectText = self.buyCollectButton:WaitForChild("ContentText") :: TextLabel
	self.buildingButton = container:WaitForChild("BuildingUpgradeButton") :: ImageButton
	self.buildingTitleText = self.buildingButton:WaitForChild("BuildingTitleText") :: TextLabel
	self.buildingDetailText = self.buildingButton:WaitForChild("BuildingDetailText") :: TextLabel
	self.saleNoticeText = container:WaitForChild("SaleNoticeText") :: TextLabel
	UIAdapter.AddAdaptiveFrame(container, UIAdapter.AdaptiveType.Center)
	self:BindEvents()
	self.scope:Connect(ClientMsg.ConnectFarmInfoChanged(function()
		self:Render()
	end))
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
	local function OnBuyZap(): ()
		if self.buyZapButton.Active then
			self.onActionTriggered("buyZap")
		end
	end
	local function OnBuyCollect(): ()
		if self.buyCollectButton.Active then
			self.onActionTriggered("buyCollect")
		end
	end
	local function OnBuyBuilding(): ()
		if not self.buildingButton.Active then
			return
		end
		local info = ClientGameInfo.GetFarmInfo()
		if info.atNest then
			self.onActionTriggered("buyNest")
		elseif info.atRestaurant then
			self.onActionTriggered("buyRestaurant")
		end
	end
	local function BindActivated(button: ImageButton, onActivated: () -> ()): ()
		self.scope:Connect(button.Activated:Connect(onActivated))
	end
	BindActivated(self.zapButton, OnZap)
	BindActivated(self.collectButton, OnCollect)
	BindActivated(self.buyZapButton, OnBuyZap)
	BindActivated(self.buyCollectButton, OnBuyCollect)
	BindActivated(self.buildingButton, OnBuyBuilding)
end
function RoastChickenHUDFrame.Render(self: RoastChickenHUDFrame): ()
	local info = ClientGameInfo.GetFarmInfo()
	local cash = info.cash
	local count = info.basketCount
	local z = info.zap
	local c = info.collect
	local stock = info.stock

	FarmTextTool.Set(self.coinText, (GameTexts.Farm.Coins.source):format(cash))
	FarmTextTool.Set(self.basketText, (GameTexts.Farm.Basket.source):format(count))
	FarmTextTool.Set(self.stockText, (GameTexts.Farm.Stock.source):format(stock))

	local atNest = info.atNest
	local atRestaurant = info.atRestaurant
	local nestLevel = info.nestLevel
	local restaurantLevel = info.restaurantLevel

	local nextType = catalog.creatures[nestLevel + 1]
	local nextPrice = catalog.restaurantPrices[restaurantLevel]

	self.buildingButton.Visible = atNest or atRestaurant
	if atNest then
		self.buildingButton.Active = nextType ~= nil
		if nextType then
			FarmTextTool.Set(self.buildingTitleText, (GameTexts.Farm.NestUpgradeTitle.source):format(nextType.egg))
			FarmTextTool.Set(self.buildingDetailText, (GameTexts.Farm.UpgradePrice.source):format(nextType.unlock))
			self.buildingDetailText.Visible = true
		else
			FarmTextTool.Set(self.buildingTitleText, GameTexts.Farm.NestMax.source)
			self.buildingDetailText.Visible = false
		end
	elseif atRestaurant then
		self.buildingButton.Active = nextPrice ~= nil
		if nextPrice then
			local benefit = if restaurantLevel == 1 then GameTexts.Farm.FasterService.source else GameTexts.Farm.SecondCounter.source
			FarmTextTool.Set(self.buildingTitleText, (GameTexts.Farm.RestaurantUpgradeTitle.source):format(benefit))
			FarmTextTool.Set(self.buildingDetailText, (GameTexts.Farm.UpgradePrice.source):format(nextPrice))
			self.buildingDetailText.Visible = true
		else
			FarmTextTool.Set(self.buildingTitleText, GameTexts.Farm.RestaurantMax.source)
			self.buildingDetailText.Visible = false
		end
	end

	FarmTextTool.Set(self.zapNameText, GameTexts.Farm.ZapActionName.source)
	FarmTextTool.Set(self.zapDetailText, (GameTexts.Farm.ZapActionDetail.source):format(GameTexts.ZapNames[z], catalog.zapDamage[z]))
	FarmTextTool.Set(self.collectNameText, GameTexts.Farm.CollectActionName.source)
	FarmTextTool.Set(self.collectDetailText, (GameTexts.Farm.CollectActionDetail.source):format(GameTexts.CollectNames[c], FarmConfig.CollectLimits[c]))

	self.shopFrame.Visible = info.atShop
	FarmTextTool.Set(
		self.buyZapText,
		if z == 3
			then GameTexts.Farm.ZapMax.source
			else (GameTexts.Farm.ZapUpgrade.source):format(GameTexts.ZapNames[z + 1], catalog.zapDamage[z + 1], FarmConfig.ToolPrices[z])
	)
	FarmTextTool.Set(
		self.buyCollectText,
		if c == 3
			then GameTexts.Farm.CollectMax.source
			else (GameTexts.Farm.CollectUpgrade.source):format(GameTexts.CollectNames[c + 1], FarmConfig.ToolPrices[c])
	)
	self.buyZapButton.Active = z < 3
	self.buyCollectButton.Active = c < 3

	if not self.showingMessage then
		FarmTextTool.Set(self.hintText, if count == FarmConfig.BasketCapacity then GameTexts.Farm.BasketFullHint.source else GameTexts.Farm.LoopHint.source)
	end
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
