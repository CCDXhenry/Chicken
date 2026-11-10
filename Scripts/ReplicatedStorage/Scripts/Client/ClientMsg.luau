-- 客户端消息封装：统一界面、玩家和农场数据变更通知
--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClientMsg = {}

local bindableEventsFolder: Folder = replicatedStorage:FindFirstChild("BindableEvents") :: Folder
local closeWindowEvent: BindableEvent = bindableEventsFolder:FindFirstChild("CloseWindow") :: BindableEvent
local openWindowEvent: BindableEvent = bindableEventsFolder:FindFirstChild("OpenWindow") :: BindableEvent
local localPlayerInfoInitEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerInfoInit") :: BindableEvent
local otherPlayerInfoInitEvent: BindableEvent = bindableEventsFolder:FindFirstChild("OtherPlayerInfoInit") :: BindableEvent
local localPlayerAcquiredGamePassEvent: BindableEvent = bindableEventsFolder:FindFirstChild("LocalPlayerAcquiredGamePass") :: BindableEvent

--关闭窗口事件
function ClientMsg.FireCloseWindow(windowName: string): ()
	closeWindowEvent:Fire(windowName)
end

function ClientMsg.ConnectCloseWindow(callback: (windowName: string) -> ()): RBXScriptConnection
	return closeWindowEvent.Event:Connect(callback)
end

--打开窗口事件
function ClientMsg.FireOpenWindow(windowName: string): ()
	openWindowEvent:Fire(windowName)
end

function ClientMsg.ConnectOpenWindow(callback: (windowName: string) -> ()): RBXScriptConnection
	return openWindowEvent.Event:Connect(callback)
end

--自己的玩家信息初始化事件
function ClientMsg.FireLocalPlayerInfoInit(): ()
	localPlayerInfoInitEvent:Fire()
end

function ClientMsg.ConnectLocalPlayerInfoInit(callback: () -> ()): RBXScriptConnection
	return localPlayerInfoInitEvent.Event:Connect(callback)
end

--其他玩家的信息初始化事件
function ClientMsg.FireOtherPlayerInfoInit(playerId: number): ()
	otherPlayerInfoInitEvent:Fire(playerId)
end

function ClientMsg.ConnectOtherPlayerInfoInit(callback: (playerId: number) -> ()): RBXScriptConnection
	return otherPlayerInfoInitEvent.Event:Connect(callback)
end

--自己获得了通行证
function ClientMsg.FireLocalPlayerAcquiredGamePass(gamePassId: number): ()
	localPlayerAcquiredGamePassEvent:Fire(gamePassId)
end

function ClientMsg.ConnectLocalPlayerAcquiredGamePass(callback: (gamePassId: number) -> ()): RBXScriptConnection
	return localPlayerAcquiredGamePassEvent.Event:Connect(callback)
end

local farmInfoChangedEvent = bindableEventsFolder:WaitForChild("FarmInfoChanged") :: BindableEvent
function ClientMsg.FireFarmInfoChanged(): ()
	farmInfoChangedEvent:Fire()
end
function ClientMsg.ConnectFarmInfoChanged(callback: () -> ()): RBXScriptConnection
	return farmInfoChangedEvent.Event:Connect(callback)
end
return ClientMsg
