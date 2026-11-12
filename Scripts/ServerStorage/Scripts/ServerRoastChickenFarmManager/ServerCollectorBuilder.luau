-- 服务端拾取工具构建器：仅克隆 ReplicatedStorage.Models.Collectors 预制，投影当前阶位
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerCollectorBuilder = {}

function ServerCollectorBuilder.BuildCollectorModel(tier: number): Model
	local models = ReplicatedStorage:WaitForChild("Models")
	local collectors = models:WaitForChild("Collectors")
	local template = collectors:FindFirstChild("Collector_T" .. tostring(tier))
	assert(template and template:IsA("Model"), "缺少拾取工具预制：ReplicatedStorage.Models.Collectors.Collector_T" .. tostring(tier))
	local root = template.PrimaryPart
	assert(root and root:IsA("BasePart") and root.Name == "RootPart", "拾取工具模板缺少 RootPart")
	local model = template:Clone()
	model.Name = "FarmCollector"
	model:SetAttribute("CollectorTier", tier)
	return model
end

return ServerCollectorBuilder
