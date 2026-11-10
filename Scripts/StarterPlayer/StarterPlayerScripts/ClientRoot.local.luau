-- 客户端唯一启动入口：负责引导加载 ClientGameManager
--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local ClientGameManager = require(clientScripts:FindFirstChild("ClientGameManager"))

local manager = ClientGameManager.new()
local function OnRootDestroying(): ()
	manager:Destroy()
end
script.Destroying:Connect(OnRootDestroying)
manager:Init()
