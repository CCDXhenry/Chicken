-- 服务端消息封装：统一玩家初始化通知
--!strict
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local ServerMsg = {}

local bindableEventsFolder: Folder = serverStorage:FindFirstChild("BindableEvents") :: Folder
local playerInfoInitEvent: BindableEvent = bindableEventsFolder:FindFirstChild("PlayerInfoInit") :: BindableEvent

--玩家信息初始化
function ServerMsg.FirePlayerInfoInit(player: Player): ()
	playerInfoInitEvent:Fire(player)
end

function ServerMsg.ConnectPlayerInfoInit(callback: (player: Player) -> ()): RBXScriptConnection
	return playerInfoInitEvent.Event:Connect(callback)
end

return ServerMsg
