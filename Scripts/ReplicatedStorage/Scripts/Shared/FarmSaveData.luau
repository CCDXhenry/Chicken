-- 经营存档契约：创建独立默认档、验证持久化货物并复制不含实例和绝对时钟的快照
--!strict
export type Cargo = {
	itemId: string,
	speciesId: string,
	qualityId: string,
	weightKg: number,
	saleValue: number,
	packSeconds: number,
	configVersion: number,
}
export type Order = {
	cargo: Cargo,
	state: "Waiting" | "Processing",
	remainingSeconds: number,
	speedSnapshot: number,
	durationSnapshot: number,
}
export type FarmSave = {
	version: number,
	revision: number,
	cash: number,
	unlockedSpecies: { [string]: boolean },
	selectedSpeciesId: string,
	ownedWeapons: { [string]: boolean },
	weaponLevels: { [string]: number },
	equippedWeaponTier: number,
	collectTier: number,
	basketTier: number,
	restaurantLevel: number,
	basket: { Cargo },
	kitchen: { Order },
}

local FarmSaveData = {}
FarmSaveData.Version = 1 -- 独立经营结构版本，与通用玩家档的 dataVersion 分开
local SpeciesIds = { chicken = true, rabbit = true, sheep = true, cow = true, dragon = true }
local QualityIds = { normal = true, golden = true, rainbow = true, giant = true }

local function IsFinite(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function IsInteger(value: unknown, minimum: number, maximum: number): boolean
	return type(value) == "number" and IsFinite(value) and value % 1 == 0 and value >= minimum and value <= maximum
end
local function IsPositive(value: unknown): boolean
	return type(value) == "number" and IsFinite(value) and value > 0
end
local function IsId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end
local function ValidateCargo(value: unknown, seen: { [string]: boolean }): boolean
	if type(value) ~= "table" then return false end
	local cargo = value :: { [string]: unknown }
	local id = cargo.itemId
	if type(id) ~= "string" or not IsId(id) or seen[id] then return false end
	if type(cargo.speciesId) ~= "string" or not SpeciesIds[cargo.speciesId] then return false end
	if type(cargo.qualityId) ~= "string" or not QualityIds[cargo.qualityId] then return false end
	if not IsPositive(cargo.weightKg) or not IsPositive(cargo.packSeconds) then return false end
	if not IsInteger(cargo.saleValue, 0, 9007199254740991) or not IsInteger(cargo.configVersion, 1, FarmSaveData.Version) then return false end
	seen[id] = true
	return true
end
local function IsList(value: unknown): boolean
	if type(value) ~= "table" then return false end
	local list = value :: { [unknown]: unknown }
	local count = 0
	for key in list do
		if not IsInteger(key, 1, #list) then return false end
		count += 1
	end
	return count == #list
end
local function CopyCargo(cargo: Cargo): Cargo
	return {
		itemId = cargo.itemId, speciesId = cargo.speciesId, qualityId = cargo.qualityId,
		weightKg = cargo.weightKg, saleValue = cargo.saleValue, packSeconds = cargo.packSeconds,
		configVersion = cargo.configVersion,
	}
end

function FarmSaveData.CreateDefault(overrideInitialValues: { [string]: any }?): FarmSave
	local initial = overrideInitialValues or {}
	local initialUnlocked: { [string]: boolean } = { chicken = true }
	if initial.UnlockedSpecies then
		for k, v in initial.UnlockedSpecies do
			if v == true and SpeciesIds[k] then
				initialUnlocked[k] = true
			end
		end
	end
	local initialOwnedWeapons: { [string]: boolean } = { ["1"] = true }
	if initial.OwnedWeapons then
		for k, v in initial.OwnedWeapons do
			if v == true then
				initialOwnedWeapons[k] = true
			end
		end
	end
	local initialWeaponLevels: { [string]: number } = { ["1"] = 1 }
	if initial.WeaponLevels then
		for k, v in initial.WeaponLevels do
			if type(v) == "number" and v >= 1 and v <= 5 then
				initialWeaponLevels[k] = v
			end
		end
	end

	return {
		version = FarmSaveData.Version,
		revision = 0, -- 每次原子经营变更递增；用于辨别保存期间的新修改
		cash = if type(initial.Cash) == "number" and initial.Cash >= 0 then initial.Cash else 0, -- 初始金币
		unlockedSpecies = initialUnlocked, -- 持久化 Map 全部使用 string key
		selectedSpeciesId = if type(initial.SelectedSpeciesId) == "string" and initialUnlocked[initial.SelectedSpeciesId] then initial.SelectedSpeciesId else "chicken",
		ownedWeapons = initialOwnedWeapons,
		weaponLevels = initialWeaponLevels, -- 每件已购武器独立 Lv.1–5
		equippedWeaponTier = if type(initial.EquippedWeaponTier) == "number" and initial.EquippedWeaponTier >= 1 and initial.EquippedWeaponTier <= 5 then initial.EquippedWeaponTier else 1,
		collectTier = if type(initial.CollectTier) == "number" and initial.CollectTier >= 1 and initial.CollectTier <= 5 then initial.CollectTier else 1,
		basketTier = if type(initial.BasketTier) == "number" and initial.BasketTier >= 1 and initial.BasketTier <= 5 then initial.BasketTier else 1,
		restaurantLevel = if type(initial.RestaurantLevel) == "number" and initial.RestaurantLevel >= 1 and initial.RestaurantLevel <= 5 then initial.RestaurantLevel else 1,
		basket = {}, -- 入筐后停止地面过期，保留生成时的重量与售价
		kitchen = {}, -- FIFO；处理中剩余秒数离线暂停，禁止保存 os.clock 绝对值
	}
end

function FarmSaveData.Validate(value: unknown): (boolean, string?)
	if type(value) ~= "table" then return false, "farm must be a table" end
	local farm = value :: { [string]: unknown }
	if farm.version ~= FarmSaveData.Version then return false, "unsupported farm version" end
	if not IsInteger(farm.revision, 0, 9007199254740991) or not IsInteger(farm.cash, 0, 9007199254740991) then return false, "invalid cash or revision" end
	for _, field in { "equippedWeaponTier", "collectTier", "basketTier", "restaurantLevel" } do
		if not IsInteger(farm[field], 1, 5) then return false, "invalid tier: " .. field end
	end
	if type(farm.unlockedSpecies) ~= "table" or type(farm.ownedWeapons) ~= "table" or type(farm.weaponLevels) ~= "table" then return false, "invalid progression maps" end
	local speciesMap = farm.unlockedSpecies :: { [string]: unknown }
	local weapons = farm.ownedWeapons :: { [string]: unknown }
	local levels = farm.weaponLevels :: { [string]: unknown }
	if speciesMap.chicken ~= true or weapons["1"] ~= true then return false, "missing initial equipment" end
	local previousUnlocked = true
	for _, id in { "chicken", "rabbit", "sheep", "cow", "dragon" } do
		if speciesMap[id] == true and not previousUnlocked then return false, "nonsequential species" end
		previousUnlocked = speciesMap[id] == true
	end
	for id, unlocked in speciesMap do
		if not SpeciesIds[id] or unlocked ~= true then return false, "invalid species unlock" end
	end
	if type(farm.selectedSpeciesId) ~= "string" or speciesMap[farm.selectedSpeciesId] ~= true then return false, "selected species is locked" end
	for key, owned in weapons do
		local tier = tonumber(key)
		if not tier or tostring(tier) ~= key or not IsInteger(tier, 1, 5) or owned ~= true or not IsInteger(levels[key], 1, 5) then return false, "invalid owned weapon" end
		if tier > 1 and weapons[tostring(tier - 1)] ~= true then return false, "nonsequential weapons" end
	end
	for key in levels do
		if weapons[key] ~= true then return false, "level for unowned weapon" end
	end
	if weapons[tostring(farm.equippedWeaponTier)] ~= true then return false, "equipped weapon is unowned" end
	if not IsList(farm.basket) or not IsList(farm.kitchen) then return false, "cargo queues must be lists" end
	local seen: { [string]: boolean } = {}
	for _, cargo in farm.basket :: { unknown } do
		if not ValidateCargo(cargo, seen) then return false, "invalid or duplicate basket cargo" end
	end
	for _, valueOrder in farm.kitchen :: { unknown } do
		if type(valueOrder) ~= "table" then return false, "invalid order" end
		local order = valueOrder :: { [string]: unknown }
		if not ValidateCargo(order.cargo, seen) then return false, "invalid or duplicate kitchen cargo" end
		if not IsFinite(order.remainingSeconds) or not IsFinite(order.durationSnapshot) or not IsFinite(order.speedSnapshot) then return false, "invalid processing timer" end
		local remaining, duration, speed = order.remainingSeconds :: number, order.durationSnapshot :: number, order.speedSnapshot :: number
		if order.state == "Waiting" then
			if remaining ~= 0 or duration ~= 0 or speed ~= 0 then return false, "waiting order has processing snapshot" end
		elseif order.state == "Processing" then
			if remaining < 0 or duration <= 0 or remaining > duration or speed <= 0 then return false, "invalid processing snapshot" end
		else
			return false, "invalid order state"
		end
	end
	return true, nil
end

function FarmSaveData.Copy(farm: FarmSave): FarmSave
	local result = FarmSaveData.CreateDefault()
	result.version, result.revision, result.cash = farm.version, farm.revision, farm.cash
	result.unlockedSpecies = table.clone(farm.unlockedSpecies)
	result.selectedSpeciesId = farm.selectedSpeciesId
	result.ownedWeapons, result.weaponLevels = table.clone(farm.ownedWeapons), table.clone(farm.weaponLevels)
	result.equippedWeaponTier, result.collectTier = farm.equippedWeaponTier, farm.collectTier
	result.basketTier, result.restaurantLevel = farm.basketTier, farm.restaurantLevel
	for _, cargo in farm.basket do table.insert(result.basket, CopyCargo(cargo)) end
	for _, order in farm.kitchen do
		table.insert(result.kitchen, {
			cargo = CopyCargo(order.cargo), state = order.state, remainingSeconds = order.remainingSeconds,
			speedSnapshot = order.speedSnapshot, durationSnapshot = order.durationSnapshot,
		})
	end
	return result
end

return FarmSaveData
