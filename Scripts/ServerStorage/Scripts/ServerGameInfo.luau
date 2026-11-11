-- 服务端数据层：管理玩家资料与独立于存档的农场会话状态
--!strict
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local ServerGameInfo = {}
local ServerFarmTypes = require(script.Parent:WaitForChild("ServerFarmTypes"))
type FarmSessionInfo = ServerFarmTypes.FarmSessionInfo
local farmInfo: FarmSessionInfo?

local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerMsg = require(serverScripts:FindFirstChild("ServerMsg"))
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local DateTimeExtension = require(coreSharedScripts:FindFirstChild("DateTimeExtension"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local FarmSaveData = require(sharedScripts:WaitForChild("FarmSaveData"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))

local playerInfoMap: { [number]: GameConfig.PlayerInfo } = {}

--初始化玩家信息
function ServerGameInfo.InitPlayerInfo(
	player: Player,
	playerSaveInfo: GameConfig.PlayerSaveInfo,
	countryRegion: string,
	playerConfigInfo: GameConfig.PlayerConfigInfo
): ()
	local playerInfo: GameConfig.PlayerInfo = {
		dataVersion = playerSaveInfo.dataVersion,
		firstEnterTime = playerSaveInfo.firstEnterTime,
		firstEnterVersion = playerSaveInfo.firstEnterVersion,
		gameTime = playerSaveInfo.gameTime,
		loginDays = playerSaveInfo.loginDays,
		lastOnlineDateUTC = playerSaveInfo.lastOnlineDateUTC,
		settingInfo = playerSaveInfo.settingInfo,
		ownedGamePassList = playerSaveInfo.ownedGamePassList,
		farm = FarmSaveData.Copy(playerSaveInfo.farm),
		playerInfoChanged = false,
		changeRevision = 0,
		timeOfThisLogin = DateTime.now().UnixTimestamp,
		countryRegion = countryRegion,
		lastOnlineDate = DateTimeExtension.GetDate(DateTime.fromUnixTimestamp(playerSaveInfo.lastOnlineDateUTC)),
		ownedGamePassMap = {},
		playerConfigInfo = playerConfigInfo,
	}
	for ownedGamePassIndex: number, ownedGamePassId: number in playerInfo.ownedGamePassList do
		playerInfo.ownedGamePassMap[ownedGamePassId] = true
	end
	playerInfoMap[player.UserId] = playerInfo
	ServerMsg.FirePlayerInfoInit(player)
	local clientLocalPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo = {
		settingInfo = playerInfo.settingInfo,
		ownedGamePassList = playerInfo.ownedGamePassList,
	}
	local clientOtherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo = {}
	local clientOtherPlayerSyncInfoMap: { [string]: GameConfig.ClientOtherPlayerSyncInfo } = {}
	for player2Index: number, player2: Player in players:GetPlayers() do
		if player2.UserId == player.UserId then
			continue
		end
		local player2Info: GameConfig.PlayerInfo = playerInfoMap[player2.UserId]
		if player2Info == nil then
			continue
		end
		local clientOtherPlayer2SyncInfo: GameConfig.ClientOtherPlayerSyncInfo = {}
		clientOtherPlayerSyncInfoMap[tostring(player2.UserId)] = clientOtherPlayer2SyncInfo
	end
	NetMsg.FireNotifyPlayerInfoInit(player, clientLocalPlayerSaveInfo, clientOtherPlayerSyncInfoMap, playerConfigInfo)
	NetMsg.FireNotifyPlayersOtherPlayerInfoInit(player.UserId, clientOtherPlayerSaveInfo)
end

--移除玩家信息
function ServerGameInfo.RemovePlayerInfo(player: Player): ()
	playerInfoMap[player.UserId] = nil
end

--获取玩家信息
function ServerGameInfo.GetPlayerInfo(player: Player): GameConfig.PlayerInfo?
	return playerInfoMap[player.UserId]
end

--创建玩家存档信息
function ServerGameInfo.CreatePlayerSaveInfoByPlayerInfo(playerInfo: GameConfig.PlayerInfo): GameConfig.PlayerSaveInfo
	return {
		dataVersion = playerInfo.dataVersion,
		firstEnterTime = playerInfo.firstEnterTime,
		firstEnterVersion = playerInfo.firstEnterVersion,
		gameTime = playerInfo.gameTime,
		loginDays = playerInfo.loginDays,
		lastOnlineDateUTC = playerInfo.lastOnlineDateUTC,
		lastOnlineDate = playerInfo.lastOnlineDate,
		farm = FarmSaveData.Copy(playerInfo.farm),
		ownedGamePassList = table.clone(playerInfo.ownedGamePassList),
		settingInfo = table.clone(playerInfo.settingInfo),
	}
end

-- 统一记录资料版本，防止异步保存成功回调清掉保存期间产生的新修改。
function ServerGameInfo.MarkPlayerInfoChanged(player: Player): ()
	local info = playerInfoMap[player.UserId]
	if info then
		info.playerInfoChanged = true
		info.changeRevision += 1
	end
end

--增加玩家游戏时间
function ServerGameInfo.AddPlayerGameTime(player: Player, addGameTime: number): ()
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		return
	end
	playerInfo.gameTime += addGameTime
	ServerGameInfo.MarkPlayerInfoChanged(player)
end

--改变玩家登录天数
function ServerGameInfo.ChangePlayerLoginDays(player: Player, loginDays: number, lastOnlineDate: DateTimeExtension.DateTimeTable): ()
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil then
		return
	end
	playerInfo.loginDays = loginDays
	playerInfo.lastOnlineDate = lastOnlineDate
	playerInfo.lastOnlineDateUTC = DateTime.fromUniversalTime(lastOnlineDate.Year, lastOnlineDate.Month, lastOnlineDate.Day).UnixTimestamp
	ServerGameInfo.MarkPlayerInfoChanged(player)
end

--设置玩家通行证为已获得
function ServerGameInfo.SetPlayerGamePassAcquired(player: Player, gamePassId: number): ()
	local playerInfo: GameConfig.PlayerInfo = playerInfoMap[player.UserId]
	if playerInfo == nil or playerInfo.ownedGamePassMap[gamePassId] then
		return
	end
	table.insert(playerInfo.ownedGamePassList, gamePassId)
	playerInfo.ownedGamePassMap[gamePassId] = true
	ServerGameInfo.MarkPlayerInfoChanged(player)
	NetMsg.FireNotifyPlayerAcquiredGamePass(player, gamePassId)
end

-- 农场状态只存在于当前服务器会话，不参与 PlayerSaveInfo 序列化。
function ServerGameInfo.InitFarmInfo(): FarmSessionInfo
	if farmInfo then
		return farmInfo
	end
	local info: FarmSessionInfo = {
		flock = {},
		roasts = {},
		eggs = {},
		playerStates = {},
		nestLevel = 1,
		nextEggTime = 0,
		restaurant = { stock = {}, queue = {}, lanes = {}, leaving = {}, nextArrival = 0, level = 1, serial = 0 },
	}
	farmInfo = info
	return info
end
function ServerGameInfo.GetFarmInfo(): FarmSessionInfo?
	return farmInfo
end
function ServerGameInfo.UpdateFarmInfo(update: (FarmSessionInfo) -> ()): ()
	local info = farmInfo
	if not info then
		return
	end
	update(info)
	ServerMsg.FireFarmInfoChanged()
end
function ServerGameInfo.InitPlayerFarmInfo(player: Player): ServerFarmTypes.PlayerFarmInfo
	local info = ServerGameInfo.InitFarmInfo()
	local existing = info.playerStates[player]
	if existing then
		return existing
	end
	local playerFarmInfo: ServerFarmTypes.PlayerFarmInfo = { cash = 0, items = {}, zap = 1, collect = 1, cooldowns = {} }
	info.playerStates[player] = playerFarmInfo
	return playerFarmInfo
end
function ServerGameInfo.RemovePlayerFarmInfo(player: Player): ()
	if farmInfo then
		farmInfo.playerStates[player] = nil
	end
end
function ServerGameInfo.ResetFarmInfo(): ()
	farmInfo = nil
end
return ServerGameInfo
