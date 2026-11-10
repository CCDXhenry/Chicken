-- 服务端唯一启动入口：负责引导加载 ServerGameManager
--!strict
local serverStorage: ServerStorage = game:GetService("ServerStorage")
local serverScripts = serverStorage:WaitForChild("Scripts")
local ServerGameManager = require(serverScripts:FindFirstChild("ServerGameManager"))

local manager = ServerGameManager.new()
local function OnRootDestroying(): ()
	manager:Destroy()
end
script.Destroying:Connect(OnRootDestroying)
manager:Init()
