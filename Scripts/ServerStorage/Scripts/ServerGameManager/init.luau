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
local MarketplaceTool = require(serverCoreScripts:FindFirstChild("MarketplaceTool"))
local serverScripts = serverStorage:WaitForChild("Scripts")
local PlayerSaveInfoVersionUpdateTool = require(serverScripts:FindFirstChild("PlayerSaveInfoVersionUpdateTool"))
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local ServerPlayerSaveStore = require(serverScripts:WaitForChild("ServerPlayerSaveStore"))
local AnalyticsTool = require(serverScripts:FindFirstChild("AnalyticsTool"))
local ServerRoastChickenFarmManager = require(serverScripts:WaitForChild("ServerPersonalFarmManager"))
type ServerRoastChickenFarmManager = ServerRoastChickenFarmManager.ServerPersonalFarmManager
local activeFarmManager: ServerRoastChickenFarmManager?
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
local playerSaveStore = ServerPlayerSaveStore.new(playerInfoDataStore)
local closing = false
local closeBound = false
local removingPlayers: { [Player]: boolean } = {}

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
		local revision = playerInfo.changeRevision
		local playerSaveInfo: GameConfig.PlayerSaveInfo = ServerGameInfo.CreatePlayerSaveInfoByPlayerInfo(playerInfo)
		local success, reason = playerSaveStore:Save(player.UserId, playerSaveInfo, revision)
		if success and playerInfo.changeRevision == revision and playerInfo.farm.revision == playerSaveInfo.farm.revision then
			playerInfo.playerInfoChanged = false
		end
		if not success then warn("[ServerGameManager] Player save failed", player.UserId, reason) end
	end
end

local function OnHeartbeat(deltaTime: number): ()
	if closing then return end
	local nowDate: DateTimeExtension.DateTimeTable = DateTimeExtension.GetNowDate()
	for playerIndex: number, player: Player in players:GetPlayers() do
		if removingPlayers[player] then continue end
		if ServerGameInfo.GetPlayerInfo(player) and not playerSaveStore:IsActive(player.UserId) then
			if activeFarmManager then activeFarmManager:FreezePlayer(player) end
			player:Kick("Your data session expired. Please rejoin to keep your progress safe.")
			continue
		end
		ServerGameInfo.AddPlayerGameTime(player, deltaTime)
		CheckPlayerLoginDays(player, nowDate)
	end
end

--玩家加入事件
local function OnPlayerAdded(player: Player): ()
	if closing then player:Kick("Server is closing. Please rejoin."); return end
	if playerScopes[player] then
		return
	end
	local scope = LifecycleTool.new()
	playerScopes[player] = scope
	player:SetAttribute("FarmStage", 2)
	player:SetAttribute("FarmReady", false)
	--读取玩家存档
	local success: boolean, result: any, loadReason = playerSaveStore:Acquire(player.UserId)
	--如果没有读取成功，将玩家踢出服务器，提示玩家读取存档失败
	if not success then
		warn("[ServerGameManager] Player session acquisition failed", player.UserId, loadReason)
		player:Kick("Your saved data is unavailable or active in another server. Please rejoin later.")
		return
	end
	if not scope.alive or not player.Parent then
		return
	end
	--初始化玩家信息
	local playerSaveInfo: GameConfig.PlayerSaveInfo
	if result ~= nil then
		local migrated, migrationError = PlayerSaveInfoVersionUpdateTool.Update(result)
		if not migrated then
			warn("[ServerGameManager] Save migration rejected", player.UserId, migrationError)
			player:Kick("Your saved data could not be loaded. Please rejoin later.")
			return
		end
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
	if not playerSaveStore:IsActive(player.UserId) then player:Kick("Your data session expired while loading. Please rejoin."); return end
	ServerGameInfo.InitPlayerInfo(player, playerSaveInfo, countryRegion, playerConfigInfo)
	if activeFarmManager then activeFarmManager:OnPlayerLoaded(player) end
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
			local saveScope = activeScope
			if scope.alive and saveScope and not playerSaveStore:IsBusy(player.UserId) then
				-- 保存任务归服务器作用域所有；退出销毁玩家作用域不会取消正在进行的写入。
				saveScope:Spawn(function(): () SavePlayerInfo(player) end)
			end
		end
	end)
	--埋点添加玩家
	AnalyticsTool.AddPlayer(player)
end

--玩家离开事件
local function OnPlayerRemoving(player: Player): ()
	if removingPlayers[player] then return end
	removingPlayers[player] = true
	if activeFarmManager then activeFarmManager:FreezePlayer(player) end
	local scope = playerScopes[player]
	if scope then
		scope:Destroy()
		playerScopes[player] = nil
	end
	--埋点移除玩家
	AnalyticsTool.RemovePlayer(player)
	--离开前保存玩家数据
	SavePlayerInfo(player)
	if activeFarmManager then activeFarmManager:RemovePlayer(player) end
	--移除玩家数据
	ServerGameInfo.RemovePlayerInfo(player)
	local released = playerSaveStore:Release(player.UserId)
	if not released then warn("[ServerGameManager] Session release failed; lease will expire", player.UserId) end
	removingPlayers[player] = nil
end

local function OnServerClosing(): ()
	closing = true
	for _, player in players:GetPlayers() do
		if activeFarmManager then activeFarmManager:FreezePlayer(player) end
	end
	for _, player in players:GetPlayers() do
		local saveScope = activeScope
		if saveScope then saveScope:Spawn(function(): () OnPlayerRemoving(player) end) else OnPlayerRemoving(player) end
	end
	while next(playerScopes) or next(removingPlayers) do task.wait(0.05) end
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
	closing = false
	local scope = LifecycleTool.new()
	activeScope = scope
	if not closeBound then game:BindToClose(OnServerClosing); closeBound = true end
	print("GameVersion", GameConfig.GameVersion)
	AnalyticsTool.Init()
	scope:Connect(players.PlayerAdded:Connect(OnPlayerAdded))
	scope:Connect(players.PlayerRemoving:Connect(OnPlayerRemoving))
	scope:Connect(runService.Heartbeat:Connect(OnHeartbeat))

	self.marketplaceManager:Init()
	self.playerSettingManager:Init()
	self.playerChatCommandManager:Init()
	self.roastChickenFarmManager:Init()
	activeFarmManager = self.roastChickenFarmManager
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
	closing = true
	for player in playerScopes do if activeFarmManager then activeFarmManager:FreezePlayer(player) end end
	self.marketplaceManager:Destroy()
	self.playerSettingManager:Destroy()
	self.playerChatCommandManager:Destroy()
	for player in playerScopes do
		OnPlayerRemoving(player)
	end
	while next(removingPlayers) do task.wait() end
	if activeScope then activeScope:Destroy(); activeScope = nil end
	self.roastChickenFarmManager:Destroy()
	activeFarmManager = nil
	AnalyticsTool.Destroy()
end
return ServerGameManager
