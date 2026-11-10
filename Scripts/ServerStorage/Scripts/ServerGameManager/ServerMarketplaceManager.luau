-- 服务端商城管理器：处理通行证购买与收据回调
--!strict
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local players: Players = game:GetService("Players")
local marketplaceService: MarketplaceService = game:GetService("MarketplaceService")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local AnalyticsTool = require(serverScripts:FindFirstChild("AnalyticsTool"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))

local LifecycleTool = require(sharedScripts:WaitForChild("LifecycleTool"))
local ServerMarketplaceManager = {}
ServerMarketplaceManager.__index = ServerMarketplaceManager

export type ServerMarketplaceManager = typeof(setmetatable({} :: { scope: LifecycleTool.Lifecycle? }, ServerMarketplaceManager))

local function OnPromptGamePassPurchaseFinished(player: Instance, gamePassId: number, wasPurchased: boolean): ()
	if not wasPurchased then
		return
	end
	if not player:IsA("Player") then
		return
	end
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil or playerInfo.ownedGamePassMap[gamePassId] then
		return
	end
	ServerGameInfo.SetPlayerGamePassAcquired(player, gamePassId)
	AnalyticsTool.AddPassPurchaseEvent(player, gamePassId, GameConfig.GamePassPrice[gamePassId])
end

--处理购买商品收据
local function ProcessReceipt(receiptInfo: GameConfig.ReceiptInfo): Enum.ProductPurchaseDecision
	local player: Player? = players:GetPlayerByUserId(receiptInfo.PlayerId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end

function ServerMarketplaceManager.new(): ServerMarketplaceManager
	return setmetatable({}, ServerMarketplaceManager) :: ServerMarketplaceManager
end

function ServerMarketplaceManager.Init(self: ServerMarketplaceManager): ()
	if self.scope then
		return
	end
	local scope = LifecycleTool.new()
	self.scope = scope
	scope:Connect(marketplaceService.PromptGamePassPurchaseFinished:Connect(OnPromptGamePassPurchaseFinished))
	marketplaceService.ProcessReceipt = ProcessReceipt
end

function ServerMarketplaceManager.Destroy(self: ServerMarketplaceManager): ()
	if self.scope then
		self.scope:Destroy()
		self.scope = nil
	end
end
return ServerMarketplaceManager
