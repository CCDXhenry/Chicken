-- 服务端聊天命令管理器：处理受限的数据清理传送命令
--!strict
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local runService: RunService = game:GetService("RunService")
local players: Players = game:GetService("Players")
local textChatService: TextChatService = game:GetService("TextChatService")
local serverCore = serverStorage:WaitForChild("Core")
local serverCoreScripts = serverCore:WaitForChild("Scripts")
local GMConfig = require(serverCoreScripts:FindFirstChild("GMConfig"))
local TeleportTool = require(serverCoreScripts:FindFirstChild("TeleportTool"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local customTextChatCommandsFolder: Folder = textChatService:FindFirstChild("CustomTextChatCommands") :: Folder
local clearDataStoreCommand: TextChatCommand = customTextChatCommandsFolder:FindFirstChild("ClearDataStoreCommand") :: TextChatCommand

local LifecycleTool = require(sharedScripts:WaitForChild("LifecycleTool"))
local ServerPlayerChatCommandManager = {}
ServerPlayerChatCommandManager.__index = ServerPlayerChatCommandManager

export type ServerPlayerChatCommandManager = typeof(setmetatable({} :: { scope: LifecycleTool.Lifecycle? }, ServerPlayerChatCommandManager))

--清空数据
local function OnClearDataStoreCommandTrigged(originTextSource: TextSource, unfilteredText: string): ()
	if runService:IsStudio() or not GMConfig.IsGMPlayer(originTextSource.UserId) then
		return
	end
	local player: Player? = players:GetPlayerByUserId(originTextSource.UserId)
	if player == nil then
		return
	end
	--传送到清除玩家数据场景
	local teleportOptions = Instance.new("TeleportOptions")
	local teleportData: any = {
		gameStartPlaceId = GameConfig.GamePlaceId,
		defaultPlayerSaveInfo = GameConfig.CreateDefaultPlayerSaveInfo(),
	}
	teleportOptions:SetTeleportData(teleportData)
	TeleportTool.SafeTeleport(GameConfig.ClearDataStorePlaceId, { player }, teleportOptions)
end

function ServerPlayerChatCommandManager.new(): ServerPlayerChatCommandManager
	return setmetatable({}, ServerPlayerChatCommandManager) :: ServerPlayerChatCommandManager
end

function ServerPlayerChatCommandManager.Init(self: ServerPlayerChatCommandManager): ()
	if self.scope then
		return
	end
	local scope = LifecycleTool.new()
	self.scope = scope
	scope:Connect(clearDataStoreCommand.Triggered:Connect(OnClearDataStoreCommandTrigged))
end

function ServerPlayerChatCommandManager.Destroy(self: ServerPlayerChatCommandManager): ()
	if self.scope then
		self.scope:Destroy()
		self.scope = nil
	end
end
return ServerPlayerChatCommandManager
