-- 客户端数据层：管理玩家信息与农场 Attributes 的只读展示投影
--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClientGameInfo = {}
local FarmConfig = require(script.Parent.Parent:WaitForChild("Shared"):WaitForChild("FarmConfig"))
local LifecycleTool = require(script.Parent.Parent:WaitForChild("Shared"):WaitForChild("LifecycleTool"))
local farmScope: LifecycleTool.Lifecycle?
local farmInfo: FarmConfig.ClientFarmInfo =
	{ stage = 2, ready = false, cash = 0, basketCount = 0, zap = 1, collect = 1, stock = 0, atShop = false, atNest = false, atRestaurant = false, nestLevel = 1, restaurantLevel = 1 }

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local clientScripts = scripts:WaitForChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))

local localPlayerInfo: GameConfig.ClientLocalPlayerInfo?
local otherPlayerInfoMap: { [number]: GameConfig.ClientOtherPlayerInfo } = {}

--初始化玩家信息
function ClientGameInfo.InitPlayerInfo(
	localPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo,
	otherPlayerSaveInfoMap: { [string]: GameConfig.ClientOtherPlayerSyncInfo },
	playerConfigInfo: GameConfig.PlayerConfigInfo
): ()
	--初始化自己的玩家信息
	localPlayerInfo = {
		settingInfo = localPlayerSaveInfo.settingInfo,
		ownedGamePassList = localPlayerSaveInfo.ownedGamePassList,
		ownedGamePassMap = {},
		playerConfigInfo = playerConfigInfo,
	}
	if localPlayerInfo == nil then
		return
	end
	for ownedGamePassIndex: number, ownedGamePassId: number in localPlayerInfo.ownedGamePassList do
		localPlayerInfo.ownedGamePassMap[ownedGamePassId] = true
	end
	--初始化其他玩家的玩家信息
	for otherPlayerIdKey: string, otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo in otherPlayerSaveInfoMap do
		local otherPlayerId: number? = tonumber(otherPlayerIdKey)
		if otherPlayerId == nil then
			continue
		end
		local otherPlayerInfo: GameConfig.ClientOtherPlayerInfo = {}
		otherPlayerInfoMap[otherPlayerId] = otherPlayerInfo
	end
	--发送消息
	ClientMsg.FireLocalPlayerInfoInit()
end

--初始化其他玩家信息
function ClientGameInfo.InitOtherPlayerInfo(playerId: number, otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo): ()
	local otherPlayerInfo: GameConfig.ClientOtherPlayerInfo = {}
	otherPlayerInfoMap[playerId] = otherPlayerInfo
	ClientMsg.FireOtherPlayerInfoInit(playerId)
end

--获取自己的玩家信息
function ClientGameInfo.GetLocalPlayerInfo(): GameConfig.ClientLocalPlayerInfo?
	return localPlayerInfo
end

--获取其他玩家的玩家信息
function ClientGameInfo.GetOtherPlayerInfo(playerId: number): GameConfig.ClientOtherPlayerInfo?
	if otherPlayerInfoMap == nil then
		return nil
	end
	return otherPlayerInfoMap[playerId]
end

--自己获得了通行证
function ClientGameInfo.SetLocalPlayerGamePassAcquired(gamePassId: number): ()
	if localPlayerInfo == nil or localPlayerInfo.ownedGamePassMap[gamePassId] then
		return
	end
	table.insert(localPlayerInfo.ownedGamePassList, gamePassId)
	localPlayerInfo.ownedGamePassMap[gamePassId] = true
	ClientMsg.FireLocalPlayerAcquiredGamePass(gamePassId)
end

function ClientGameInfo.GetFarmInfo(): FarmConfig.ClientFarmInfo
	return farmInfo
end
function ClientGameInfo.InitFarmInfo(): ()
	if farmScope then
		return
	end
	local scope = LifecycleTool.new()
	farmScope = scope
	local player = game:GetService("Players").LocalPlayer
	local function ReadNumber(name: string, default: number): number
		local value = player:GetAttribute(name)
		return if typeof(value) == "number" then value else default
	end
	local function OnFarmAttributeChanged(): ()
		local unlocked: { [string]: boolean } = {}
		for _, id in { "chicken", "rabbit", "sheep", "cow", "dragon" } do unlocked[id] = player:GetAttribute("FarmSpecies_" .. id) == true end
		local confirmationId = player:GetAttribute("FarmConfirmId")
		local confirmationMessage = player:GetAttribute("FarmConfirmMessage")
		local confirmationRisk = player:GetAttribute("FarmConfirmRisk")
		local eggId, eggSpecies, eggQuality = player:GetAttribute("FarmEggId"), player:GetAttribute("FarmEggSpecies"), player:GetAttribute("FarmEggQuality")
		local weaponLevels: { [string]: number } = {}
		for tier = 1, 5 do weaponLevels[tostring(tier)] = ReadNumber("FarmWeaponLevel_" .. tier, if tier == 1 then 1 else 0) end
		farmInfo = {
			eggId = if typeof(eggId) == "string" then eggId else nil,
			eggSpecies = if typeof(eggSpecies) == "string" then eggSpecies else nil,
			eggQuality = if typeof(eggQuality) == "string" then eggQuality else nil,
			eggEndTime = ReadNumber("FarmEggEndTime", 0),
			eggPrice = ReadNumber("FarmEggPrice", 0),
			weaponLevels = weaponLevels,
			weaponLevel = ReadNumber("FarmWeaponLevel", 1),
			basketTier = ReadNumber("FarmBasketTier", 1),
			unlockedSpecies = unlocked,
			confirmationId = if typeof(confirmationId) == "string" then confirmationId else nil,
			confirmationMessage = if typeof(confirmationMessage) == "string" then confirmationMessage else nil,
			confirmationRisk = if typeof(confirmationRisk) == "string" then confirmationRisk else nil,
			stage = ReadNumber("FarmStage", 2),
			ready = player:GetAttribute("FarmReady") == true,
			basketWeight = ReadNumber("FarmBasketWeight", 0),
			basketCapacity = ReadNumber("FarmBasketCapacity", 12),
			damage = ReadNumber("FarmDamage", 2),
			waiting = ReadNumber("FarmWaiting", 0),
			processing = ReadNumber("FarmProcessing", 0),
			expectedValue = ReadNumber("FarmExpectedValue", 0),
			cash = ReadNumber("FarmCash", 0),
			basketCount = ReadNumber("FarmBasket", 0),
			zap = ReadNumber("FarmZap", 1),
			collect = ReadNumber("FarmCollect", 1),
			stock = ReadNumber("FarmStock", 0),
			atShop = player:GetAttribute("FarmShop") == true,
			atNest = player:GetAttribute("FarmNestShop") == true,
			atRestaurant = player:GetAttribute("FarmRestaurantShop") == true,
			nestLevel = ReadNumber("FarmNestLevel", 1),
			restaurantLevel = ReadNumber("FarmRestaurantLevel", 1),
		}
		ClientMsg.FireFarmInfoChanged()
	end
	for _, name in FarmConfig.AttributeNames do
		scope:Connect(player:GetAttributeChangedSignal(name):Connect(OnFarmAttributeChanged))
	end
	OnFarmAttributeChanged()
end
function ClientGameInfo.DestroyFarmInfo(): ()
	if farmScope then
		farmScope:Destroy()
		farmScope = nil
	end
end
return ClientGameInfo
