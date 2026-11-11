-- 个人经营数据操作：原子维护货物迁移、重量、打包结算及物种装备购买进度
--!strict
-- Studio 按同步实例取模块；离线 Lune 回归直接加载同一源码和相邻模块。
local Config = if script then require(script.Parent:WaitForChild("FarmEconomyConfig")) else require("./FarmEconomyConfig")
local Save = if script then require(script.Parent:WaitForChild("FarmSaveData")) else require("./FarmSaveData")
type FarmSave = typeof(Save.CreateDefault())
type Cargo = typeof(Save.CreateDefault().basket[1])
local FarmBusiness = {}

function FarmBusiness.CreateCargo(itemId: string, speciesId: string, qualityId: string): Cargo
	local species, quality = Config.GetSpecies(speciesId), Config.GetQuality(qualityId)
	assert(species and quality, "Invalid species or quality")
	return {
		itemId = itemId, speciesId = speciesId, qualityId = qualityId,
		weightKg = species.weightKg * quality.weightMultiplier,
		saleValue = species.saleValue * quality.valueMultiplier,
		packSeconds = species.packSeconds * quality.packMultiplier,
		configVersion = Config.Version,
	}
end
function FarmBusiness.GetWeight(farm: FarmSave): number
	local weight = 0
	for _, cargo in farm.basket do weight += cargo.weightKg end
	return weight
end
function FarmBusiness.TryCollect(farm: FarmSave, cargo: Cargo): (boolean, string?)
	local capacity = Config.Baskets[farm.basketTier].capacityKg
	if cargo.weightKg > capacity then return false, "itemTooHeavy" end
	if FarmBusiness.GetWeight(farm) + cargo.weightKg > capacity then return false, "remainingCapacity" end
	for _, current in farm.basket do
		if current.itemId == cargo.itemId then return false, "duplicate" end
	end
	for _, order in farm.kitchen do
		if order.cargo.itemId == cargo.itemId then return false, "duplicate" end
	end
	table.insert(farm.basket, cargo)
	farm.revision += 1
	return true, nil
end
function FarmBusiness.DepositOne(farm: FarmSave): boolean
	local cargo = table.remove(farm.basket, 1)
	if not cargo then return false end
	table.insert(farm.kitchen, { cargo = cargo, state = "Waiting", remainingSeconds = 0, speedSnapshot = 0, durationSnapshot = 0 })
	farm.revision += 1
	return true
end
function FarmBusiness.TickKitchen(farm: FarmSave, dt: number): (number, number)
	assert(dt >= 0 and dt == dt and dt < math.huge, "Invalid kitchen delta")
	local restaurant = Config.Restaurants[farm.restaurantLevel]
	local processing = 0
	local sold, income = 0, 0
	-- 先推进现有订单；新接单从本帧末开始，不把过去的 dt 算给新货。
	for i = #farm.kitchen, 1, -1 do
		local order = farm.kitchen[i]
		if order.state == "Processing" then
			order.remainingSeconds = math.max(0, order.remainingSeconds - dt)
			if order.remainingSeconds == 0 then
				income += order.cargo.saleValue
				sold += 1
				table.remove(farm.kitchen, i)
			else
				processing += 1
			end
		end
	end
	-- 移除待结算货物与金币记账在同一个不 yield 的调用中完成。
	farm.cash += income
	for _, order in farm.kitchen do
		if processing >= restaurant.workers then break end
		if order.state == "Waiting" then
			order.state = "Processing"
			order.speedSnapshot = restaurant.speed
			order.durationSnapshot = order.cargo.packSeconds / restaurant.speed
			order.remainingSeconds = order.durationSnapshot
			processing += 1
		end
	end
	if processing > 0 or sold > 0 then farm.revision += 1 end
	return sold, income
end
function FarmBusiness.GetKitchenCounts(farm: FarmSave): (number, number, number)
	local waiting, processing, expected = 0, 0, 0
	for _, order in farm.kitchen do
		if order.state == "Waiting" then waiting += 1 else processing += 1 end
		expected += order.cargo.saleValue
	end
	return waiting, processing, expected
end
function FarmBusiness.TryUnlockSpecies(farm: FarmSave, speciesId: string): (boolean, string?)
	local species = Config.GetSpecies(speciesId)
	if not species then return false, "invalidSpecies" end
	if farm.unlockedSpecies[speciesId] then return true, nil end
	local prevSpecies = Config.Species[species.tier - 1]
	local prevKey = if prevSpecies then (prevSpecies.key or tostring(prevSpecies.id)) else nil
	if species.tier > 1 and (not prevKey or not farm.unlockedSpecies[prevKey]) then return false, "previousSpeciesRequired" end
	if farm.cash < species.unlockPrice then return false, "insufficientCash" end
	farm.cash -= species.unlockPrice
	farm.unlockedSpecies[speciesId] = true
	farm.revision += 1
	return true, nil
end
function FarmBusiness.SelectSpecies(farm: FarmSave, speciesId: string): boolean
	if not farm.unlockedSpecies[speciesId] or not Config.GetSpecies(speciesId) then return false end
	if farm.selectedSpeciesId ~= speciesId then farm.selectedSpeciesId = speciesId; farm.revision += 1 end
	return true
end
function FarmBusiness.GetSpeciesRisk(farm: FarmSave, speciesId: string): (number, number, string)
	local species = Config.GetSpecies(speciesId)
	assert(species, "Unknown species")
	local damage = Config.GetDamage(farm.equippedWeaponTier, farm.weaponLevels[tostring(farm.equippedWeaponTier)])
	local capacity = Config.Baskets[farm.basketTier].capacityKg
	local fits: { string } = {}
	for _, quality in Config.Qualities do
		local weight = species.weightKg * quality.weightMultiplier
		table.insert(fits, tostring(weight) .. (if weight <= capacity then "" else "!"))
	end
	return math.ceil(species.health / damage), math.ceil(species.health * 2 / damage), table.concat(fits, " / ")
end
function FarmBusiness.GetPurchasePrice(farm: FarmSave, action: string): number?
	if action == "buyZap" then
		for tier = 2, #Config.Weapons do if not farm.ownedWeapons[tostring(tier)] then return Config.Weapons[tier].price end end
	elseif action == "enhanceWeapon" then
		return Config.Weapons[farm.equippedWeaponTier].enhancementPrices[farm.weaponLevels[tostring(farm.equippedWeaponTier)]]
	elseif action == "buyCollect" then
		local nextTier = Config.Collectors[farm.collectTier + 1]
		return if nextTier then nextTier.price else nil
	elseif action == "buyBasket" then
		local nextTier = Config.Baskets[farm.basketTier + 1]
		return if nextTier then nextTier.price else nil
	elseif action == "buyRestaurant" then
		local nextLevel = Config.Restaurants[farm.restaurantLevel + 1]
		return if nextLevel then nextLevel.price else nil
	end
	return nil
end
function FarmBusiness.GetPurchaseStep(farm: FarmSave, action: string): number?
	if action == "buyZap" then
		local highest = 1
		for tier = 2, #Config.Weapons do if farm.ownedWeapons[tostring(tier)] then highest = tier else break end end
		return highest
	elseif action == "enhanceWeapon" then return Config.GetWeaponProgressStep(farm.equippedWeaponTier, farm.weaponLevels[tostring(farm.equippedWeaponTier)])
	elseif action == "buyCollect" then return farm.collectTier
	elseif action == "buyBasket" then return farm.basketTier
	elseif action == "buyRestaurant" then return farm.restaurantLevel end
	return nil
end
function FarmBusiness.TryPurchase(farm: FarmSave, action: string, expectedStep: number?): (boolean, string?)
	if expectedStep ~= nil and expectedStep ~= FarmBusiness.GetPurchaseStep(farm, action) then return false, "stateChanged" end
	local price = FarmBusiness.GetPurchasePrice(farm, action)
	if not price then return false, "maximumOrUnknown" end
	if farm.cash < price then return false, "insufficientCash" end
	if action == "buyZap" then
		for tier = 2, #Config.Weapons do
			if not farm.ownedWeapons[tostring(tier)] then
				farm.ownedWeapons[tostring(tier)], farm.weaponLevels[tostring(tier)] = true, 1
				farm.equippedWeaponTier = tier
				break
			end
		end
	elseif action == "enhanceWeapon" then
		farm.weaponLevels[tostring(farm.equippedWeaponTier)] += 1
	elseif action == "buyCollect" then farm.collectTier += 1
	elseif action == "buyBasket" then farm.basketTier += 1
	elseif action == "buyRestaurant" then farm.restaurantLevel += 1
	end
	farm.cash -= price
	farm.revision += 1
	return true, nil
end
function FarmBusiness.TryEquipWeapon(farm: FarmSave, tier: number): boolean
	if tier % 1 ~= 0 or tier < 1 or tier > #Config.Weapons or not farm.ownedWeapons[tostring(tier)] then return false end
	if farm.equippedWeaponTier ~= tier then farm.equippedWeaponTier = tier; farm.revision += 1 end
	return true
end
return FarmBusiness
