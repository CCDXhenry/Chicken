-- 网络通信模块：负责双端 RemoteEvent 消息的强类型发送、接收与参数安全校验
--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetMsg = {}
local FarmConfig = require(script.Parent:WaitForChild("FarmConfig"))
local FarmRequest = require(script.Parent:WaitForChild("FarmRequest"))

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local remoteEventsFolder: Folder = replicatedStorage:WaitForChild("RemoteEvents") :: Folder
local requestSetBGMVolumeEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSetBGMVolume") :: RemoteEvent
local requestSetSoundEffectVolumeEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSetSoundEffectVolume") :: RemoteEvent
local requestSetVibrationsOnOffStateEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("RequestSetVibrationsOnOffState") :: RemoteEvent
local notifyPlayerInfoInitEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerInfoInit") :: RemoteEvent
local notifyPlayersOtherPlayerInfoInitEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayersOtherPlayerInfoInit") :: RemoteEvent
local notifyPlayerAcquiredGamePassEvent: RemoteEvent = remoteEventsFolder:FindFirstChild("NotifyPlayerAcquiredGamePass") :: RemoteEvent
local roastChickenActionEvent = remoteEventsFolder:WaitForChild("RoastChickenAction") :: RemoteEvent

--boolean校验
local function ValidateBoolean(value: any): boolean
	if typeof(value) ~= "boolean" then
		return false
	end
	return true
end

--Number校验
local function ValidateNumber(value: any): boolean
	--类型校验
	if typeof(value) ~= "number" then
		return false
	end
	--NaN校验
	if value ~= value then
		return false
	end
	return true
end

--string校验
local function ValidateString(value: any): boolean
	if typeof(value) ~= "string" then
		return false
	end
	return true
end

--Instance校验
local function ValidateInstance(instance: any, expectedClass: string): boolean
	if typeof(instance) ~= "Instance" then
		return false
	end
	return instance:IsA(expectedClass)
end

--Vector3校验
local function ValidateVector3(vector3: any): boolean
	--类型校验
	if typeof(vector3) ~= "Vector3" then
		return false
	end
	--NaN校验
	if vector3 ~= vector3 then
		return false
	end
	return true
end

--CFrame校验
local function ValidateCFrame(cframe: any): boolean
	if typeof(cframe) ~= "CFrame" then
		return false
	end
	if not ValidateVector3(cframe.Position) then
		return false
	end
	if not ValidateVector3(cframe.LookVector) then
		return false
	end
	return true
end

--简单表校验
local function ValidateSimpleTable(tbl: { [any]: any }, keyType: string, validator: (any) -> boolean): boolean
	--类型校验
	if typeof(tbl) ~= "table" then
		return false
	end
	--表中元素类型校验
	for key, value in tbl do
		if typeof(key) ~= keyType then
			return false
		end
		if not validator(value) then
			return false
		end
	end
	return true
end

--客户端请求设置背景音乐音量
function NetMsg.FireRequestSetBGMVolume(volume: number): ()
	requestSetBGMVolumeEvent:FireServer(volume)
end

function NetMsg.ConnectRequestSetBGMVolume(callback: (player: Player, volume: number) -> ()): RBXScriptConnection
	return requestSetBGMVolumeEvent.OnServerEvent:Connect(function(player: Player, volume: number)
		if not ValidateNumber(volume) then
			return
		end
		callback(player, volume)
	end)
end

--客户端请求设置音效音量
function NetMsg.FireRequestSetSoundEffectVolume(volume: number): ()
	requestSetSoundEffectVolumeEvent:FireServer(volume)
end

function NetMsg.ConnectRequestSetSoundEffectVolume(callback: (player: Player, volume: number) -> ()): RBXScriptConnection
	return requestSetSoundEffectVolumeEvent.OnServerEvent:Connect(function(player: Player, volume: number)
		if not ValidateNumber(volume) then
			return
		end
		callback(player, volume)
	end)
end

--客户端请求设置振动开关状态
function NetMsg.FireRequestSetVibrationsOnOffState(vibrationsOn: boolean): ()
	requestSetVibrationsOnOffStateEvent:FireServer(vibrationsOn)
end

function NetMsg.ConnectRequestSetVibrationsOnOffState(callback: (player: Player, vibrationsOn: boolean) -> ()): RBXScriptConnection
	return requestSetVibrationsOnOffStateEvent.OnServerEvent:Connect(function(player: Player, vibrationsOn: boolean)
		if not ValidateBoolean(vibrationsOn) then
			return
		end
		callback(player, vibrationsOn)
	end)
end

--通知客户端玩家信息初始化完成
function NetMsg.FireNotifyPlayerInfoInit(
	player: Player,
	localPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo,
	otherPlayerSaveInfoMap: { [string]: GameConfig.ClientOtherPlayerSyncInfo },
	playerConfigInfo: GameConfig.PlayerConfigInfo
): ()
	notifyPlayerInfoInitEvent:FireClient(player, localPlayerSaveInfo, otherPlayerSaveInfoMap, playerConfigInfo)
end

function NetMsg.ConnectNotifyPlayerInfoInit(callback: (
	localPlayerSaveInfo: GameConfig.ClientLocalPlayerSaveInfo,
	otherPlayerSaveInfoMap: { [string]: GameConfig.ClientOtherPlayerSyncInfo },
	playerConfigInfo: GameConfig.PlayerConfigInfo
) -> ()): RBXScriptConnection
	return notifyPlayerInfoInitEvent.OnClientEvent:Connect(callback)
end

--通知客户端其他玩家信息初始化完成
function NetMsg.FireNotifyPlayersOtherPlayerInfoInit(playerId: number, otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo): ()
	notifyPlayersOtherPlayerInfoInitEvent:FireAllClients(playerId, otherPlayerSaveInfo)
end

function NetMsg.ConnectNotifyPlayersOtherPlayerInfoInit(
	callback: (playerId: number, otherPlayerSaveInfo: GameConfig.ClientOtherPlayerSyncInfo) -> ()
): RBXScriptConnection
	return notifyPlayersOtherPlayerInfoInitEvent.OnClientEvent:Connect(callback)
end

--通知客户端玩家获得了通行证
function NetMsg.FireNotifyPlayerAcquiredGamePass(player: Player, gamePassId: number): ()
	notifyPlayerAcquiredGamePassEvent:FireClient(player, gamePassId)
end

function NetMsg.ConnectNotifyPlayerAcquiredGamePass(callback: (gamePassId: number) -> ()): RBXScriptConnection
	return notifyPlayerAcquiredGamePassEvent.OnClientEvent:Connect(callback)
end

-- 客户端请求农场动作：仅接受六种现有动作，统一经正式 RemoteEvents 节点传输。
function NetMsg.FireRequestFarmAction(action: FarmConfig.FarmAction): ()
	roastChickenActionEvent:FireServer(action)
end
-- 新协议复用既有通道；旧字符串监听器不会处理表请求，新监听器只接收净化后的字段。
function NetMsg.FireRequestFarmCommand(command: { [string]: unknown }): ()
	roastChickenActionEvent:FireServer(command)
end
function NetMsg.ConnectRequestFarmCommand(callback: (Player, FarmRequest.Request) -> ()): RBXScriptConnection
	local function OnCommand(player: Player, value: unknown): ()
		local command = FarmRequest.Parse(value)
		if command then callback(player, command) end
	end
	return roastChickenActionEvent.OnServerEvent:Connect(OnCommand)
end
function NetMsg.ConnectRequestFarmAction(callback: (Player, FarmConfig.FarmAction) -> ()): RBXScriptConnection
	local function OnRequest(player: Player, action: unknown): ()
		if typeof(action) ~= "string" or not FarmConfig.Actions[action] then
			return
		end
		callback(player, action :: FarmConfig.FarmAction)
	end
	return roastChickenActionEvent.OnServerEvent:Connect(OnRequest)
end
function NetMsg.FireNotifyFarmFeedback(player: Player, message: string, kind: string?): ()
	roastChickenActionEvent:FireClient(player, message, kind)
end
function NetMsg.ConnectNotifyFarmFeedback(callback: (string, string?) -> ()): RBXScriptConnection
	local function OnFeedback(message: unknown, kind: unknown): ()
		if typeof(message) ~= "string" then
			return
		end
		callback(message, if typeof(kind) == "string" then kind else nil)
	end
	return roastChickenActionEvent.OnClientEvent:Connect(OnFeedback)
end
return NetMsg
