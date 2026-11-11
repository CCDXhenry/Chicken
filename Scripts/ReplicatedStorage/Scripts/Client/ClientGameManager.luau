-- 客户端主管理器：负责音效、UI 框架、通行证与子系统初始化
--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local players: Players = game:GetService("Players")
local starterGui: StarterGui = game:GetService("StarterGui")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreClientScripts = coreScripts:WaitForChild("Client")
local UIAdapter = require(coreClientScripts:FindFirstChild("UIAdapter"))
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local FarmSoundTool = require(sharedScripts:WaitForChild("FarmSoundTool"))
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local NetMsg = require(sharedScripts:FindFirstChild("NetMsg"))
local clientScripts = scripts:WaitForChild("Client")
local ClientGameInfo = require(clientScripts:FindFirstChild("ClientGameInfo"))
local ClientRoastChickenFarmManager = require(clientScripts:WaitForChild("ClientRoastChickenFarmManager"))
type ClientRoastChickenFarmManager = ClientRoastChickenFarmManager.ClientRoastChickenFarmManager
local uiManagerScript = clientScripts:WaitForChild("UIManager")
local UIManager = require(uiManagerScript)

local LifecycleTool = require(sharedScripts:WaitForChild("LifecycleTool"))
local ClientBillboardManager = require(clientScripts:WaitForChild("ClientBillboardManager"))
local ClientCameraController = require(clientScripts:WaitForChild("ClientCameraController"))
local ClientGameManager = {}
ClientGameManager.__index = ClientGameManager

export type ClientGameManager = typeof(setmetatable(
	{} :: {
		roastChickenFarmManager: ClientRoastChickenFarmManager,
		billboardManager: ClientBillboardManager.ClientBillboardManager,
		cameraController: ClientCameraController.ClientCameraController,
		scope: LifecycleTool.Lifecycle?,
		screenGui: ScreenGui?,
		initialized: boolean,
	},
	ClientGameManager
))

assert(players.LocalPlayer)

local DesignScreenSize: Vector2 = Vector2.new(1920, 1080)

--通知客户端玩家信息初始化
local function OnNotifyPlayerInfoInit(
	localPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo,
	otherPlayerSaveInfoMap: { [string]: GameConfig.ClientOtherPlayerSyncInfo },
	playerConfigInfo: GameConfig.PlayerConfigInfo
): ()
	ClientGameInfo.InitPlayerInfo(localPlayerSaveInfo, otherPlayerSaveInfoMap, playerConfigInfo)
	local localPlayerInfo: GameConfig.ClientLocalPlayerInfo? = ClientGameInfo.GetLocalPlayerInfo()
	if localPlayerInfo ~= nil then
		FarmSoundTool.SetBGMVolume(localPlayerInfo.settingInfo.bgmVolume)
		FarmSoundTool.SetSoundEffectVolume(localPlayerInfo.settingInfo.soundEffectVolume)
	end
	FarmSoundTool.PlayBGM()
end

local function OnNotifyPlayersOtherPlayerInfoInit(playerId: number, otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo): ()
	if playerId ~= players.LocalPlayer.UserId then
		ClientGameInfo.InitOtherPlayerInfo(playerId, otherPlayerSaveInfo)
	end
end

local function OnNotifyPlayerAcquiredGamePass(gamePassId: number): ()
	ClientGameInfo.SetLocalPlayerGamePassAcquired(gamePassId)
end

function ClientGameManager.new(): ClientGameManager
	local self = setmetatable({}, ClientGameManager) :: ClientGameManager
	self.roastChickenFarmManager = ClientRoastChickenFarmManager.new()
	self.billboardManager = ClientBillboardManager.new()
	self.cameraController = ClientCameraController.new()
	self.initialized = false
	return self
end

function ClientGameManager.Init(self: ClientGameManager): ()
	if self.initialized then
		return
	end
	self.initialized = true
	local scope = LifecycleTool.new()
	self.scope = scope
	scope:Connect(NetMsg.ConnectNotifyPlayerInfoInit(OnNotifyPlayerInfoInit))
	scope:Connect(NetMsg.ConnectNotifyPlayersOtherPlayerInfoInit(OnNotifyPlayersOtherPlayerInfoInit))
	scope:Connect(NetMsg.ConnectNotifyPlayerAcquiredGamePass(OnNotifyPlayerAcquiredGamePass))
	local playerGui = players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local template = replicatedStorage:WaitForChild("UI"):WaitForChild("GameScreenGui")
	assert(template:IsA("ScreenGui"), "Missing GameScreenGui template")
	local old = playerGui:FindFirstChild("GameScreenGui")
	if old then
		old:Destroy()
	end
	local screenGui = template:Clone()
	screenGui.Parent = playerGui
	self.screenGui = screenGui
	scope:Own(screenGui)
	starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	UIManager.Init(screenGui)
	UIAdapter.Init(DesignScreenSize, screenGui.AbsoluteSize)
	local function OnViewportChanged(): ()
		UIAdapter.OnScreenSizeChange(screenGui.AbsoluteSize)
	end
	scope:Connect(screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(OnViewportChanged))
	self.billboardManager:Init()
	self.cameraController:Init()
	self.roastChickenFarmManager:Init(screenGui)
end
function ClientGameManager.Destroy(self: ClientGameManager): ()
	if not self.initialized then
		return
	end
	self.initialized = false
	self.roastChickenFarmManager:Destroy()
	self.cameraController:Destroy()
	self.billboardManager:Destroy()
	UIManager.Destroy()
	if self.scope then
		self.scope:Destroy()
		self.scope = nil
	end
	self.screenGui = nil
end
return ClientGameManager
