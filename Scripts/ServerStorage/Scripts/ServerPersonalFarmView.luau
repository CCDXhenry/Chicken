-- 个人农场表现层：投影玩家属性、克隆鸡筐和服务员模板并维护品质视觉与主人标牌
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Shared = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("FarmEconomyConfig"))
local Save = require(Shared:WaitForChild("FarmSaveData"))
local Business = require(Shared:WaitForChild("FarmBusiness"))
local Texts = require(Shared:WaitForChild("GameTexts"))
local NumberFormat = require(Shared:WaitForChild("FarmNumberFormat"))
local Scene = require(script.Parent:WaitForChild("ServerRoastChickenFarmManager"):WaitForChild("ServerFarmSceneTool"))
local Types = require(script.Parent:WaitForChild("ServerPersonalFarmTypes"))
type Session = Types.Session
type Egg = Types.Egg
local View = {}

local function ApplySpecies(model: Model, speciesId: string): ()
	local colors = Config.SpeciesAppearance[speciesId]
	if not colors then return end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and colors[part.Name] then
			part.Color = Color3.fromHex(colors[part.Name])
			if speciesId == "dragon" and part.Name == "Spine" then part.Material = Enum.Material.Neon end
		end
	end
end

local function SetOwnership(instance: Instance, session: Session): ()
	instance:SetAttribute("OwnerUserId", session.owner.UserId)
	instance:SetAttribute("FarmId", session.plot.Name)
end
local function SetSign(part: BasePart, template: string, text: string, ownerId: number): ()
	part:SetAttribute("OwnerUserId", ownerId)
	Scene.BindSign(part, template)
	Scene.SetSignText(part, text)
end
local function UpdateBasketVisual(session: Session): ()
	local character = session.owner.Character
	local root = Scene.GetPlayerRoot(session.owner)
	if not character or not root then return end
	local count = #session.farm.basket
	local basket = character:FindFirstChild("ChickenBasket")
	if count == 0 then if basket then basket:Destroy() end; return end
	if not basket then
		local template = ServerStorage:WaitForChild("Models"):FindFirstChild("FarmBasketTemplate")
		if not template or not template:IsA("Model") then return end
		local clone = template:Clone()
		local basketRoot = clone.PrimaryPart
		if not basketRoot then clone:Destroy(); return end
		clone.Name = "ChickenBasket"
		clone:PivotTo(root.CFrame * CFrame.new(0, -0.45, 1.15))
		for _, part in clone:GetDescendants() do if part:IsA("BasePart") then part.Anchored = false; part.Massless = true end end
		local weld = Instance.new("WeldConstraint")
		weld.Name, weld.Part0, weld.Part1, weld.Parent = "CharacterWeld", root, basketRoot, basketRoot
		clone.Parent = character
		basket = clone
	end
	if not basket then return end
	for index = 1, 6 do
		local roast = basket:FindFirstChild("Roast" .. index)
		if roast and roast:IsA("BasePart") then roast.Transparency = if index <= count then 0 else 1 end
	end
end
local function UpdateRestaurantVisuals(session: Session, waiting: number, processing: number, expected: number): ()
	local player, farm = session.owner, session.farm
	local restaurant = session.map:FindFirstChild("Restaurant")
	local stockSign = if restaurant then restaurant:FindFirstChild("StockSign") else nil
	if stockSign and stockSign:IsA("BasePart") then
		SetSign(stockSign, "RestaurantSignGui", Texts.Farm.PersonalKitchen.source:format(waiting, processing, NumberFormat.Number(expected)), player.UserId)
	end
	if restaurant then
		local workers: Instance
		local existingWorkers = restaurant:FindFirstChild("Workers")
		if existingWorkers then workers = existingWorkers else
			local folder = Instance.new("Folder")
			folder.Name, folder.Parent = "Workers", restaurant
			workers = folder
		end
		local head = restaurant:FindFirstChild("QueueHead")
		local entrance = restaurant:FindFirstChild("QueueStart")
		local template = ServerStorage:WaitForChild("Models"):FindFirstChild("FarmWorkerTemplate")
		if head and head:IsA("BasePart") and entrance and entrance:IsA("BasePart") and template and template:IsA("Model") then
			local orders: { Save.Order } = {}
			for _, order in farm.kitchen do if order.state == "Processing" then table.insert(orders, order) end end
			local forward = Scene.FlatVector(head.Position - entrance.Position)
			if forward.Magnitude < 0.01 then forward = Vector3.zAxis else forward = forward.Unit end
			local right = Vector3.new(forward.Z, 0, -forward.X)
			for index = 1, Config.Restaurants[farm.restaurantLevel].workers do
				local name = "Worker" .. index
				local model = workers:FindFirstChild(name)
				if not model then
					local clone = template:Clone()
					clone.Name = name
					local position = head.Position + forward * 2.5 + right * ((index - 1) * 3) + Vector3.yAxis * 0.1
					clone:PivotTo(CFrame.lookAt(position, position - forward))
					SetOwnership(clone, session)
					clone.Parent = workers
					model = clone
				end
				if model and model:IsA("Model") and model.PrimaryPart then
					local order = orders[index]
					model.PrimaryPart:SetAttribute("FarmStudsOffsetY", 3.8)
					SetSign(model.PrimaryPart, "WorkerSignGui", if order then Texts.Farm.WorkerPacking.source:format(index, math.ceil(order.remainingSeconds)) else Texts.Farm.WorkerIdle.source:format(index), player.UserId)
				end
			end
		end
	end
end
local function Project(session: Session, egg: Egg?, now: number): ()
	UpdateBasketVisual(session)
	local player, farm = session.owner, session.farm
	local waiting, processing, expected = Business.GetKitchenCounts(farm)
	player:SetAttribute("FarmStage", 5)
	player:SetAttribute("FarmReady", not session.frozen)
	player:SetAttribute("FarmCash", farm.cash)
	player:SetAttribute("FarmBasket", #farm.basket)
	player:SetAttribute("FarmBasketWeight", Business.GetWeight(farm))
	player:SetAttribute("FarmBasketCapacity", Config.Baskets[farm.basketTier].capacityKg)
	player:SetAttribute("FarmDamage", Config.GetDamage(farm.equippedWeaponTier, farm.weaponLevels[tostring(farm.equippedWeaponTier)]))
	player:SetAttribute("FarmZap", farm.equippedWeaponTier)
	player:SetAttribute("FarmCollect", farm.collectTier)
	player:SetAttribute("FarmBasketTier", farm.basketTier)
	player:SetAttribute("FarmWeaponLevel", farm.weaponLevels[tostring(farm.equippedWeaponTier)])
	for tier = 1, #Config.Weapons do player:SetAttribute("FarmWeaponLevel_" .. tier, farm.weaponLevels[tostring(tier)] or 0) end
	player:SetAttribute("FarmStock", waiting + processing)
	player:SetAttribute("FarmWaiting", waiting)
	player:SetAttribute("FarmProcessing", processing)
	player:SetAttribute("FarmExpectedValue", expected)
	local selected = Config.GetSpecies(farm.selectedSpeciesId)
	player:SetAttribute("FarmNestLevel", if selected then selected.tier else 1)
	for _, species in Config.Species do player:SetAttribute("FarmSpecies_" .. species.id, farm.unlockedSpecies[species.id] == true) end
	player:SetAttribute("FarmRestaurantLevel", farm.restaurantLevel)
	local eggSpecies = if egg then Config.GetSpecies(egg.speciesId) else nil
	player:SetAttribute("FarmEggSpecies", if eggSpecies then eggSpecies.name else nil)
	player:SetAttribute("FarmEggQuality", if egg then egg.qualityId else nil)
	if egg then
		if session.projectedEggId ~= egg.id or session.projectedEggFinish ~= egg.finish then
			player:SetAttribute("FarmEggEndTime", workspace:GetServerTimeNow() + math.max(0, egg.finish - now))
			session.projectedEggId, session.projectedEggFinish = egg.id, egg.finish
		end
	else
		player:SetAttribute("FarmEggEndTime", nil)
		session.projectedEggId, session.projectedEggFinish = nil, nil
	end
	player:SetAttribute("FarmEggPrice", if eggSpecies then eggSpecies.instantHatchPrice else nil)
	player:SetAttribute("FarmEggId", if egg then egg.id else nil)
	-- 个人升级统一从 HUD 发请求，关闭旧版共享区域的升级投影。
	player:SetAttribute("FarmShop", false)
	player:SetAttribute("FarmNestShop", false)
	player:SetAttribute("FarmRestaurantShop", false)
	UpdateRestaurantVisuals(session, waiting, processing, expected)
end
local function ApplyQuality(model: Model, qualityId: string): ()
	local quality = Config.GetQuality(qualityId)
	assert(quality)
	if quality.visualScale ~= 1 then model:ScaleTo(model:GetScale() * quality.visualScale) end
	if qualityId == "normal" then return end
	local highlight = Instance.new("Highlight")
	highlight.Name = "QualityGlow"
	highlight.FillColor = if qualityId == "golden" then Color3.fromRGB(255, 204, 40) else Color3.fromRGB(127, 240, 255)
	highlight.OutlineColor, highlight.FillTransparency = highlight.FillColor, 0.65
	highlight.Parent = model
	if qualityId == "golden" then
		for _, part in model:GetDescendants() do if part:IsA("BasePart") then part.Color = highlight.FillColor; part.Material = Enum.Material.Metal end end
	elseif qualityId == "giant" then
		local bounds, size = model:GetBoundingBox()
		local aura = Scene.CreatePiece(model, "GiantAura", Vector3.new(0.12, size.X * 1.4, size.Z * 1.4), CFrame.new(bounds.Position - Vector3.yAxis * (size.Y / 2)) * CFrame.Angles(0, 0, math.pi / 2), "8AF3FF")
		aura.Shape, aura.Material, aura.Transparency = Enum.PartType.Cylinder, Enum.Material.Neon, 0.8
	end
end
local function UpdateQuality(model: Model, qualityId: string, now: number): ()
	if qualityId == "giant" then
		local aura = model:FindFirstChild("GiantAura")
		if aura and aura:IsA("BasePart") then aura.Transparency = 0.75 + math.sin(now * 6) * 0.1 end
	end
	if qualityId ~= "rainbow" then return end
	local highlight = model:FindFirstChild("QualityGlow")
	if highlight and highlight:IsA("Highlight") then
		highlight.FillColor = Color3.fromHSV((now * 0.2) % 1, 0.75, 1)
		highlight.OutlineColor = highlight.FillColor
	end
end

View.SetOwnership = SetOwnership
View.ApplySpecies = ApplySpecies
View.SetSign = SetSign
View.ApplyQuality = ApplyQuality
View.UpdateQuality = UpdateQuality
View.Project = Project
return View
