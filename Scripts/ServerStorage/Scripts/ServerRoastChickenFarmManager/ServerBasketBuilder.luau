-- 服务端鸡筐构建器：仅克隆 ReplicatedStorage.Models.Baskets 分阶预制，并按承重比例显示固定货物件
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerBasketBuilder = {}
local CargoCount = 4

function ServerBasketBuilder.BuildBasketModel(tier: number): Model
	local models = ReplicatedStorage:WaitForChild("Models")
	local baskets = models:WaitForChild("Baskets")
	local template = baskets:FindFirstChild("Basket_T" .. tostring(tier))
	assert(template and template:IsA("Model"), "缺少鸡筐预制：ReplicatedStorage.Models.Baskets.Basket_T" .. tostring(tier))
	local root = template.PrimaryPart
	assert(root and root:IsA("BasePart") and root.Name == "RootPart", "鸡筐模板缺少 RootPart")
	local body = template:FindFirstChild("Basket")
	assert(body and body:IsA("BasePart"), "鸡筐模板缺少 Basket")
	for index = 1, CargoCount do
		local cargo = template:FindFirstChild("Cargo" .. index)
		assert(cargo and cargo:IsA("BasePart"), "鸡筐模板缺少 Cargo" .. index)
	end
	local model = template:Clone()
	model.Name = "ChickenBasket"
	model:SetAttribute("BasketTier", tier)
	return model
end

function ServerBasketBuilder.ApplyCargoFill(model: Model, weightKg: number, capacityKg: number): ()
	local ratio = 0
	if capacityKg > 0 and weightKg > 0 then
		ratio = math.clamp(weightKg / capacityKg, 0, 1)
	end
	local shown = if ratio <= 0 then 0 else math.ceil(ratio * CargoCount)
	for index = 1, CargoCount do
		local cargo = model:FindFirstChild("Cargo" .. index)
		if cargo and cargo:IsA("BasePart") then
			cargo.Transparency = if index <= shown then 0 else 1
		end
	end
end

return ServerBasketBuilder
