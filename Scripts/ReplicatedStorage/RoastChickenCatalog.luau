-- 烤鸡农场数据字典快捷重定向：统一指向 Scripts/Shared/RoastChickenCatalog
--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
return require(sharedScripts:WaitForChild("RoastChickenCatalog"))
