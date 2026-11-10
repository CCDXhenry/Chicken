-- 服务端主管理器：负责全局玩家生命周期、数据存档、各子系统初始化与分发
--!strict
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local dataStoreService: DataStoreService = game:GetService("DataStoreService")
local players: Players = game:GetService("Players")
local localizationService: LocalizationService = game:GetService("LocalizationService")
local runService: RunService = game:GetService("RunService")
local configService: ConfigService = game:GetService("ConfigService")
local serverCore = serverStorage:WaitForChild("Core")
local serverCoreScripts = serverCore:WaitForChild("Scripts")
local DataStoreTool = require(serverCoreScripts:FindFirstChild("DataStoreTool"))
local MarketplaceTool = require(serverCoreScripts:FindFirstChild("MarketplaceTool"))
local serverScripts = serverStorage:WaitForChild("Scripts")
local PlayerSaveInfoVersionUpdateTool = require(serverScripts:FindFirstChild("PlayerSaveInfoVersionUpdateTool"))
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local AnalyticsTool = require(serverScripts:FindFirstChild("AnalyticsTool"))
local ServerRoastChickenFarmManager = require(serverScripts:WaitForChild("ServerRoastChickenFarmManager"))
type ServerRoastChickenFarmManager = ServerRoastChickenFarmManager.ServerRoastChickenFarmManager
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local RetryAsync = require(coreSharedScripts:FindFirstChild("RetryAsync"))
local DateTimeExtension = require(coreSharedScripts:FindFirstChild("DateTimeExtension"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local ServerMarketplaceManager = require(script:FindFirstChild("ServerMarketplaceManager"))
type ServerMarketplaceManager = ServerMarketplaceManager.ServerMarketplaceManager
local ServerPlayerSettingManager = require(script:FindFirstChild("ServerPlayerSettingManager"))
type ServerPlayerSettingManager = ServerPlayerSettingManager.ServerPlayerSettingManager
local ServerPlayerChatCommandManager = require(script:FindFirstChild("ServerPlayerChatCommandManager"))
type ServerPlayerChatCommandManager = ServerPlayerChatCommandManager.ServerPlayerChatCommandManager

local playerInfoDataStore: DataStore = dataStoreService:GetDataStore("PlayerInfo")

local LifecycleTool = require(sharedScripts:WaitForChild("LifecycleTool"))
local activeScope: LifecycleTool.Lifecycle?
local playerScopes: { [Player]: LifecycleTool.Lifecycle } = {}
local ServerGameManager = {}
ServerGameManager.__index = ServerGameManager

export type ServerGameManager = typeof(setmetatable(
	{} :: {
		marketplaceManager: ServerMarketplaceManager,
		playerSettingManager: ServerPlayerSettingManager,
		playerChatCommandManager: ServerPlayerChatCommandManager,
		roastChickenFarmManager: ServerRoastChickenFarmManager,
		initialized: boolean,
	},
	ServerGameManager
))

local AutoSavePlayerInfoInterval: number = 30 --自动保存玩家信息间隔时间

local function SplitVersion(version: string): { number }
	local result: { number } = {}
	for v: string in string.gmatch(version, "%d+") do
		local v2: number? = tonumber(v)
		if v2 ~= nil then
			table.insert(result, v2)
		end
	end
	return result
end

--版本1是否是版本2后的版本
local function IsVersionAfter(version1: string, version2: string): boolean
	local v1: { number } = SplitVersion(version1)
	local v2: { number } = SplitVersion(version2)
	local length: number = math.max(#v1, #v2)
	for i: number = 1, length do
		local v1i: number = v1[i] or 0
		local v2i: number = v2[i] or 0
		if v1i ~= v2i then
			return v1i > v2i
		end
	end
	return true
end

local function CheckPlayerLoginDays(player: Player, todayDate: DateTimeExtension.DateTimeTable): ()
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if
		playerInfo ~= nil
		and (
			todayDate.Year > playerInfo.lastOnlineDate.Year
			or (todayDate.Year == playerInfo.lastOnlineDate.Year and todayDate.Month > playerInfo.lastOnlineDate.Month)
			or (
				todayDate.Year == playerInfo.lastOnlineDate.Year
				and todayDate.Month == playerInfo.lastOnlineDate.Month
				and todayDate.Day > playerInfo.lastOnlineDate.Day
			)
		)
	then
		--登录天数+1
		ServerGameInfo.ChangePlayerLoginDays(player, playerInfo.loginDays + 1, todayDate)
	end
end

local function CheckOwnedGamePasses(player: Player): ()
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	local scope = playerScopes[player]
	if playerInfo ~= nil and scope then
		scope:Spawn(function()
			for gamePassIdKey: string, gamePassIdValue: number in pairs(GameConfig.GamePassId) do
				if playerInfo.ownedGamePassMap[gamePassIdValue] == nil then
					local success: boolean, result: any = MarketplaceTool.SafeUserOwnsGamePass(player, gamePassIdValue)
					if success and result then
						ServerGameInfo.SetPlayerGamePassAcquired(player, gamePassIdValue)
						AnalyticsTool.AddPassPurchaseEvent(player, gamePassIdValue, GameConfig.GamePassPrice[gamePassIdValue])
					end
				end
			end
		end)
	end
end

--保存玩家信息
local function SavePlayerInfo(player: Player): ()
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo ~= nil and playerInfo.playerInfoChanged then
		local playerSaveInfo: GameConfig.PlayerSaveInfo = ServerGameInfo.CreatePlayerSaveInfoByPlayerInfo(playerInfo)
		local success: boolean, _: any = DataStoreTool.SafeSet(playerInfoDataStore, tostring(player.UserId), playerSaveInfo)
		if success then
			playerInfo.playerInfoChanged = false
		end
	end
end

local function OnHeartbeat(deltaTime: number): ()
	local nowDate: DateTimeExtension.DateTimeTable = DateTimeExtension.GetNowDate()
	for playerIndex: number, player: Player in players:GetPlayers() do
		ServerGameInfo.AddPlayerGameTime(player, deltaTime)
		CheckPlayerLoginDays(player, nowDate)
	end
end

--玩家加入事件
local function OnPlayerAdded(player: Player): ()
	if playerScopes[player] then
		return
	end
	local scope = LifecycleTool.new()
	playerScopes[player] = scope
	--读取玩家存档
	local success: boolean, result: any = DataStoreTool.SafeGet(playerInfoDataStore, tostring(player.UserId))
	--如果没有读取成功，将玩家踢出服务器，提示玩家读取存档失败
	if not success then
		player:Kick(result)
		return
	end
	if not scope.alive or not player.Parent then
		return
	end
	--初始化玩家信息
	local playerSaveInfo: GameConfig.PlayerSaveInfo
	if result ~= nil then
		PlayerSaveInfoVersionUpdateTool.Update(result)
		playerSaveInfo = result
	else
		playerSaveInfo = GameConfig.CreateDefaultPlayerSaveInfo()
	end
	--获取玩家国家/地区
	success, result = RetryAsync(function()
		return localizationService:GetCountryRegionForPlayerAsync(player)
	end, 5, 1)
	local countryRegion: string = if success then result else "unknown"
	if not scope.alive or not player.Parent then
		return
	end
	--远程配置
	local _config: ConfigSnapshot?
	local configSuccess, configError = pcall(function()
		if IsVersionAfter(playerSaveInfo.firstEnterVersion, GameConfig.ABTestVersion) then
			_config = configService:GetConfigForPlayerAsync(player)
		else
			--老玩家不参与AB测试
			_config = configService:GetConfigAsync()
		end
	end)
	if not configSuccess then
		warn("远程配置读取失败", configError)
	end
	if not scope.alive or not player.Parent then
		return
	end
	local playerConfigInfo: GameConfig.PlayerConfigInfo = {}
	ServerGameInfo.InitPlayerInfo(player, playerSaveInfo, countryRegion, playerConfigInfo)
	--检查登录天数
	local nowDate: DateTimeExtension.DateTimeTable = DateTimeExtension.GetNowDate()
	CheckPlayerLoginDays(player, nowDate)
	--检查拥有的通行证
	CheckOwnedGamePasses(player)
	--每隔一段时间自动保存玩家数据
	scope:Spawn(function()
		while scope.alive do
			task.wait(AutoSavePlayerInfoInterval)
			--保存玩家数据
			SavePlayerInfo(player)
		end
	end)
	--埋点添加玩家
	AnalyticsTool.AddPlayer(player)
end

--玩家离开事件
local function OnPlayerRemoving(player: Player): ()
	local scope = playerScopes[player]
	if scope then
		scope:Destroy()
		playerScopes[player] = nil
	end
	--埋点移除玩家
	AnalyticsTool.RemovePlayer(player)
	--离开前保存玩家数据
	SavePlayerInfo(player)
	--移除玩家数据
	ServerGameInfo.RemovePlayerInfo(player)
	local scope = playerScopes[player]
	if scope then
		scope:Destroy()
		playerScopes[player] = nil
	end
end

function ServerGameManager.new(): ServerGameManager
	local self: ServerGameManager = setmetatable({}, ServerGameManager) :: ServerGameManager
	self.initialized = false
	self.marketplaceManager = ServerMarketplaceManager.new()
	self.playerSettingManager = ServerPlayerSettingManager.new()
	self.playerChatCommandManager = ServerPlayerChatCommandManager.new()
	self.roastChickenFarmManager = ServerRoastChickenFarmManager.new()
	return self
end

function ServerGameManager.Init(self: ServerGameManager): ()
	if self.initialized then
		return
	end
	self.initialized = true
	local scope = LifecycleTool.new()
	activeScope = scope
	print("GameVersion", GameConfig.GameVersion)
	AnalyticsTool.Init()
	scope:Connect(players.PlayerAdded:Connect(OnPlayerAdded))
	scope:Connect(players.PlayerRemoving:Connect(OnPlayerRemoving))
	scope:Connect(runService.Heartbeat:Connect(OnHeartbeat))

	self.marketplaceManager:Init()
	self.playerSettingManager:Init()
	self.playerChatCommandManager:Init()
	self.roastChickenFarmManager:Init()
	for _, player in players:GetPlayers() do
		scope:Spawn(function()
			OnPlayerAdded(player)
		end)
	end
end

function ServerGameManager.Destroy(self: ServerGameManager): ()
	if not self.initialized then
		return
	end
	self.initialized = false
	if activeScope then
		activeScope:Destroy()
		activeScope = nil
	end
	self.roastChickenFarmManager:Destroy()
	self.marketplaceManager:Destroy()
	self.playerSettingManager:Destroy()
	self.playerChatCommandManager:Destroy()
	for player in playerScopes do
		OnPlayerRemoving(player)
	end
	AnalyticsTool.Destroy()
end
return ServerGameManager
