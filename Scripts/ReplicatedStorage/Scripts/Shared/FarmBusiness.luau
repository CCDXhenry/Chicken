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
	for _, queue in { farm.packed, farm.playerCarry, farm.workerCarry["1"], farm.workerCarry["2"], farm.counter } do
		for _, current in queue do if current.itemId == cargo.itemId then return false, "duplicate" end end
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
-- 打包只生产成品，不结算金币；单工位在本次推进结束后接下一份货。
function FarmBusiness.TickKitchen(farm: FarmSave, dt: number): number
	assert(dt >= 0 and dt == dt and dt < math.huge, "Invalid kitchen delta")
	local processing = false
	local completed = 0
	for i = #farm.kitchen, 1, -1 do
		local order = farm.kitchen[i]
		if order.state == "Processing" then
			order.remainingSeconds = math.max(0, order.remainingSeconds - dt)
			if order.remainingSeconds == 0 then
				table.insert(farm.packed, order.cargo)
				table.remove(farm.kitchen, i)
				completed += 1
			else processing = true end
		end
	end
	if not processing then
		local restaurant = Config.Restaurants[farm.restaurantLevel]
		for _, order in farm.kitchen do
			if order.state == "Waiting" then
				order.state = "Processing"
				order.speedSnapshot = restaurant.speed * restaurant.workers
				order.durationSnapshot = order.cargo.weightKg / order.speedSnapshot
				order.remainingSeconds = order.durationSnapshot
				processing = true
				break
			end
		end
	end
	if processing or completed > 0 then farm.revision += 1 end
	return completed
end
local function GetCarrier(farm: FarmSave, carrier: string): { Cargo }
	assert(carrier == "player" or carrier == "1" or carrier == "2", "Invalid carrier")
	return if carrier == "player" then farm.playerCarry else farm.workerCarry[carrier]
end
local function MoveAll(source: { Cargo }, target: { Cargo }): number
	local count = #source
	for _, cargo in source do table.insert(target, cargo) end
	table.clear(source)
	return count
end
function FarmBusiness.TakePackages(farm: FarmSave, carrier: string): number
	local count = MoveAll(farm.packed, GetCarrier(farm, carrier))
	if count > 0 then farm.revision += 1 end
	return count
end
function FarmBusiness.PlacePackages(farm: FarmSave, carrier: string): number
	local count = MoveAll(GetCarrier(farm, carrier), farm.counter)
	if count > 0 then farm.revision += 1 end
	return count
end
function FarmBusiness.ReturnPackages(farm: FarmSave, carrier: string): number
	local count = MoveAll(GetCarrier(farm, carrier), farm.packed)
	if count > 0 then farm.revision += 1 end
	return count
end
function FarmBusiness.RestoreCarriedPackages(farm: FarmSave): ()
	for _, carrier in { "player", "1", "2" } do FarmBusiness.ReturnPackages(farm, carrier) end
end
-- 仅顾客到达队首并完成购买节奏校验后调用；扣货和加钱不 yield。
function FarmBusiness.SellCounterOne(farm: FarmSave): Cargo?
	local cargo = table.remove(farm.counter, 1)
	if not cargo then return nil end
	farm.cash += cargo.saleValue
	farm.revision += 1
	return cargo
end
function FarmBusiness.GetPackageCounts(farm: FarmSave): (number, number, number)
	return #farm.packed, #farm.playerCarry + #farm.workerCarry["1"] + #farm.workerCarry["2"], #farm.counter
end
function FarmBusiness.GetKitchenCounts(farm: FarmSave): (number, number, number)
	local waiting, processing, expected = 0, 0, 0
	for _, order in farm.kitchen do
		if order.state == "Waiting" then waiting += 1 else processing += 1 end
		expected += order.cargo.saleValue
	end
	for _, queue in { farm.packed, farm.playerCarry, farm.workerCarry["1"], farm.workerCarry["2"], farm.counter } do
		for _, cargo in queue do expected += cargo.saleValue end
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
