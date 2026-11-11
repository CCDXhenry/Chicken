-- 服务端设置管理器：接收并更新玩家音效与振动设置
--!strict
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameInfo = require(serverScripts:FindFirstChild("ServerGameInfo"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))

local LifecycleTool = require(sharedScripts:WaitForChild("LifecycleTool"))
local ServerPlayerSettingManager = {}
ServerPlayerSettingManager.__index = ServerPlayerSettingManager

export type ServerPlayerSettingManager = typeof(setmetatable({} :: { scope: LifecycleTool.Lifecycle? }, ServerPlayerSettingManager))

local function OnPlayerRequestSetBGMVolume(player: Player, volume: number): ()
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil or playerInfo.settingInfo.bgmVolume == volume then
		return
	end
	playerInfo.settingInfo.bgmVolume = volume
	ServerGameInfo.MarkPlayerInfoChanged(player)
end

local function OnPlayerRequestSetSoundEffectVolume(player: Player, volume: number): ()
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil or playerInfo.settingInfo.soundEffectVolume == volume then
		return
	end
	playerInfo.settingInfo.soundEffectVolume = volume
	ServerGameInfo.MarkPlayerInfoChanged(player)
end

local function OnPlayerRequestSetVibrationsOnOffState(player: Player, vibrationsOn: boolean): ()
	local playerInfo: GameConfig.PlayerInfo? = ServerGameInfo.GetPlayerInfo(player)
	if playerInfo == nil or playerInfo.settingInfo.vibrationOn == vibrationsOn then
		return
	end
	playerInfo.settingInfo.vibrationOn = vibrationsOn
	ServerGameInfo.MarkPlayerInfoChanged(player)
end

function ServerPlayerSettingManager.new(): ServerPlayerSettingManager
	return setmetatable({}, ServerPlayerSettingManager) :: ServerPlayerSettingManager
end

function ServerPlayerSettingManager.Init(self: ServerPlayerSettingManager): ()
	if self.scope then
		return
	end
	local scope = LifecycleTool.new()
	self.scope = scope
	scope:Connect(NetMsg.ConnectRequestSetBGMVolume(OnPlayerRequestSetBGMVolume))
	scope:Connect(NetMsg.ConnectRequestSetSoundEffectVolume(OnPlayerRequestSetSoundEffectVolume))
	scope:Connect(NetMsg.ConnectRequestSetVibrationsOnOffState(OnPlayerRequestSetVibrationsOnOffState))
end

function ServerPlayerSettingManager.Destroy(self: ServerPlayerSettingManager): ()
	if self.scope then
		self.scope:Destroy()
		self.scope = nil
	end
end
return ServerPlayerSettingManager
