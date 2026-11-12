-- 新版个人农场数值契约：从配表 Data 组装五物种、四品质、五阶装备与餐厅参数
--!strict
export type SpeciesId = "chicken" | "rabbit" | "sheep" | "cow" | "dragon"
export type QualityId = "normal" | "golden" | "rainbow" | "giant"
export type Species = {
	id: number,
	key: SpeciesId,
	speciesId: SpeciesId,
	tier: number,
	name: string,
	foodName: string,
	name_t: string,
	foodName_t: string,
	description_t: string?,
	health: number,
	interval: number,
	hatchSeconds: number,
	weightKg: number,
	saleValue: number,
	unlockPrice: number,
	instantHatchPrice: number,
}
export type Quality = {
	id: number,
	key: QualityId,
	qualityId: QualityId,
	tier: number,
	name_t: string?,
	description_t: string?,
	colorHex: string?,
	probability: number,
	healthMultiplier: number,
	weightMultiplier: number,
	valueMultiplier: number,
	hatchMultiplier: number,
	visualScale: number,
}
export type Weapon = {
	id: number?, tier: number?, name_t: string?, description_t: string?,
	range: number, mode: "single" | "chain" | "cone", maximumTargets: number,
	angleDegrees: number, chainRange: number, damage: number, damageIncrement: number,
	price: number, enhancementPrices: { number },
}
export type Collector = {
	id: number?, tier: number?, name_t: string?, description_t: string?,
	range: number, maximumItems: number, angleDegrees: number, price: number,
}
export type Basket = {
	id: number?, tier: number?, name_t: string?, description_t: string?,
	capacityKg: number, price: number,
}
export type Restaurant = {
	id: number?, level: number?, name_t: string?, description_t: string?,
	workers: number, speed: number, price: number, -- speed：每名服务员每秒打包重量，kg/s
}
type DataRow = { [string]: any }

local Config = {
	Version = 1, -- 货物生成时保存的数值版本；后续更新不重算已有货物售价/重量
	PopulationCapacity = 28, -- 每名玩家蛋和活体合计上限，单位个
	EggFlightSeconds = 1.15, -- 飞行结束后开始孵化，秒
	GroundLifetimeSeconds = 75, -- 地面货物过期，入筐后取消，秒
	ZapCooldownSeconds = 0.35, -- 服务端电击冷却，秒
	CollectCooldownSeconds = 0.35, -- 服务端拾取冷却，秒
	HatchCooldownSeconds = 0.75, -- 免费加速冷却，秒
	HatchReductionSeconds = 1, -- 每次免费减少秒数，最低为零
	HatchInteractionRange = 8, -- 自家落地蛋的交互距离，studs
	UnloadIntervalSeconds = 0.15, -- 首次入区也等待完整间隔，秒/份
	AnimalWalkSpeed = 4, -- studs/秒
	AnimalFleeSpeed = 9, -- studs/秒
	AnimalFleeRange = 8, -- studs
	AnimalFleeSeconds = 1.2, -- 受惊持续秒数
	MaximumWeaponLevel = 5, -- 每件武器独立从 Lv.1 强化至 Lv.5
}

-- Studio 读 GameConfig 子模块；离线 Lune 按源码相对路径加载同一份 Data。
local function LoadRows(moduleName: string): { DataRow }
	local loaded: any
	if script then
		local gameConfig = script.Parent:WaitForChild("GameConfig")
		if moduleName == "SpeciesData" then
			loaded = require(gameConfig:WaitForChild("SpeciesData"))
		elseif moduleName == "QualityData" then
			loaded = require(gameConfig:WaitForChild("QualityData"))
		elseif moduleName == "WeaponData" then
			loaded = require(gameConfig:WaitForChild("WeaponData"))
		elseif moduleName == "CollectorData" then
			loaded = require(gameConfig:WaitForChild("CollectorData"))
		elseif moduleName == "BasketData" then
			loaded = require(gameConfig:WaitForChild("BasketData"))
		elseif moduleName == "RestaurantData" then
			loaded = require(gameConfig:WaitForChild("RestaurantData"))
		elseif moduleName == "SpeciesAppearanceData" then
			loaded = require(gameConfig:WaitForChild("SpeciesAppearanceData"))
		else
			error("Unknown farm data module")
		end
	elseif moduleName == "SpeciesData" then
		loaded = require("./GameConfig/SpeciesData")
	elseif moduleName == "QualityData" then
		loaded = require("./GameConfig/QualityData")
	elseif moduleName == "WeaponData" then
		loaded = require("./GameConfig/WeaponData")
	elseif moduleName == "CollectorData" then
		loaded = require("./GameConfig/CollectorData")
	elseif moduleName == "BasketData" then
		loaded = require("./GameConfig/BasketData")
	elseif moduleName == "RestaurantData" then
		loaded = require("./GameConfig/RestaurantData")
	elseif moduleName == "SpeciesAppearanceData" then
		loaded = require("./GameConfig/SpeciesAppearanceData")
	else
		error("Unknown farm data module")
	end
	assert(type(loaded) == "table", moduleName)
	return loaded :: { DataRow }
end
local function NumberField(row: DataRow, field: string): number
	local value = row[field]
	assert(type(value) == "number", field)
	return value :: number
end
local function StringField(row: DataRow, field: string): string
	local value = row[field]
	assert(type(value) == "string", field)
	return value :: string
end
local function NumberList(row: DataRow, field: string): { number }
	local value = row[field]
	assert(type(value) == "table", field)
	local source = value :: { any }
	local result: { number } = {}
	for index, item in source do
		assert(type(item) == "number", field)
		result[index] = item :: number
	end
	return result
end
local function SpeciesIdOf(value: string): SpeciesId
	if value == "chicken" or value == "rabbit" or value == "sheep" or value == "cow" or value == "dragon" then
		return value
	end
	error(value)
end
local function QualityIdOf(value: string): QualityId
	if value == "normal" or value == "golden" or value == "rainbow" or value == "giant" then
		return value
	end
	error(value)
end
local function WeaponMode(value: string): "single" | "chain" | "cone"
	assert(value == "single" or value == "chain" or value == "cone", value)
	return value :: "single" | "chain" | "cone"
end

-- 物种字段单位依次为 HP、秒、秒、kg、金币、金币、秒、金币；行顺序即阶位。
local speciesList: { Species } = {}
for index, row in LoadRows("SpeciesData") do
	local tier = NumberField(row, "tier")
	assert(tier == index, "Species tier must match row order")
	local idNum = if row.id ~= nil then NumberField(row, "id") else index
	local keyVal: SpeciesId = SpeciesIdOf(StringField(row, "key"))
	local nameVal = if row.name_t ~= nil then StringField(row, "name_t") else StringField(row, "name")
	local foodNameVal = if row.foodName_t ~= nil then StringField(row, "foodName_t") else StringField(row, "foodName")
	local speciesRow: Species = {
		id = idNum,
		key = keyVal,
		speciesId = keyVal,
		tier = tier,
		name = nameVal,
		foodName = foodNameVal,
		name_t = nameVal,
		foodName_t = foodNameVal,
		description_t = if row.description_t ~= nil then StringField(row, "description_t") else nil,
		health = NumberField(row, "health"),
		interval = NumberField(row, "interval"),
		hatchSeconds = NumberField(row, "hatchSeconds"),
		weightKg = NumberField(row, "weightKg"),
		saleValue = NumberField(row, "saleValue"),
		unlockPrice = NumberField(row, "unlockPrice"),
		instantHatchPrice = NumberField(row, "instantHatchPrice"),
	}
	table.insert(speciesList, speciesRow)
end
assert(#speciesList == 5, "Five species tiers are required")
Config.Species = speciesList
-- 普通外观覆色；优先读取 GameConfig.SpeciesAppearance，若未配置则回退到配表
local appearance: { [string]: { [string]: string } } = {}
local hasGameConfigAppearance = false
if script and script.Parent then
	local gameConfigMod = script.Parent:FindFirstChild("GameConfig")
	if gameConfigMod and gameConfigMod:IsA("ModuleScript") then
		local ok, gc = pcall(require, gameConfigMod)
		if ok and type(gc) == "table" and gc.SpeciesAppearance then
			appearance = gc.SpeciesAppearance
			hasGameConfigAppearance = true
		end
	end
end

if not hasGameConfigAppearance then
	for _, row in LoadRows("SpeciesAppearanceData") do
		local speciesId: string
		if type(row.speciesId) == "number" then
			if row.speciesId == 1 then
				speciesId = "chicken"
			elseif row.speciesId == 5 then
				speciesId = "dragon"
			else
				speciesId = tostring(row.speciesId)
			end
		else
			speciesId = StringField(row, "speciesId")
		end
		if appearance[speciesId] == nil then
			appearance[speciesId] = {}
		end
		local parts = appearance[speciesId] :: { [string]: string }
		parts[StringField(row, "partName")] = StringField(row, "color")
	end
end
Config.SpeciesAppearance = appearance
-- 概率和为 1；视觉缩放与重量倍率独立，巨型外观 2.5 倍、血量/重量 4 倍。
local qualities: { Quality } = {}
local probability = 0
for index, row in LoadRows("QualityData") do
	local idNum = if row.id ~= nil then NumberField(row, "id") else index
	local keyVal: QualityId = QualityIdOf(StringField(row, "key"))
	local quality: Quality = {
		id = idNum,
		key = keyVal,
		qualityId = keyVal,
		tier = if row.tier ~= nil then NumberField(row, "tier") else index,
		name_t = if row.name_t ~= nil then StringField(row, "name_t") else nil,
		description_t = if row.description_t ~= nil then StringField(row, "description_t") else nil,
		colorHex = if row.colorHex ~= nil then StringField(row, "colorHex") else nil,
		probability = NumberField(row, "probability"),
		healthMultiplier = NumberField(row, "healthMultiplier"),
		weightMultiplier = NumberField(row, "weightMultiplier"),
		valueMultiplier = NumberField(row, "valueMultiplier"),
		hatchMultiplier = NumberField(row, "hatchMultiplier"),
		visualScale = NumberField(row, "visualScale"),
	}
	probability += quality.probability
	table.insert(qualities, quality)
end
assert(#qualities == 4 and math.abs(probability - 1) < 1e-9, "Quality probabilities must sum to 1")
Config.Qualities = qualities
-- 射程/跳距为 studs，角度为完整射界，伤害为每发共享总量，费用为金币。
local weapons: { Weapon } = {}
for index, row in LoadRows("WeaponData") do
	local prices = NumberList(row, "enhancementPrices")
	assert(#prices == Config.MaximumWeaponLevel - 1, "Each weapon lists four enhancement prices")
	table.insert(weapons, {
		id = if row.id ~= nil then NumberField(row, "id") else index,
		tier = if row.tier ~= nil then NumberField(row, "tier") else index,
		name_t = if row.name_t ~= nil then StringField(row, "name_t") else nil,
		description_t = if row.description_t ~= nil then StringField(row, "description_t") else nil,
		range = NumberField(row, "range"),
		mode = WeaponMode(StringField(row, "mode")),
		maximumTargets = NumberField(row, "maximumTargets"),
		angleDegrees = NumberField(row, "angleDegrees"),
		chainRange = NumberField(row, "chainRange"),
		damage = NumberField(row, "damage"),
		damageIncrement = NumberField(row, "damageIncrement"),
		price = NumberField(row, "price"),
		enhancementPrices = prices,
	})
end
assert(#weapons == 5, "Five weapon tiers are required")
Config.Weapons = weapons
-- 拾取范围 studs，360 表示周围；成功拾取数才计入 maximumItems，费用为金币。
local collectors: { Collector } = {}
for index, row in LoadRows("CollectorData") do
	table.insert(collectors, {
		id = if row.id ~= nil then NumberField(row, "id") else index,
		tier = if row.tier ~= nil then NumberField(row, "tier") else index,
		name_t = if row.name_t ~= nil then StringField(row, "name_t") else nil,
		description_t = if row.description_t ~= nil then StringField(row, "description_t") else nil,
		range = NumberField(row, "range"),
		maximumItems = NumberField(row, "maximumItems"),
		angleDegrees = NumberField(row, "angleDegrees"),
		price = NumberField(row, "price"),
	})
end
assert(#collectors == 5, "Five collector tiers are required")
Config.Collectors = collectors
-- 鸡筐承重 kg，逐阶购买费为金币，独立于拾取工具。
local baskets: { Basket } = {}
for index, row in LoadRows("BasketData") do
	table.insert(baskets, {
		id = if row.id ~= nil then NumberField(row, "id") else index,
		tier = if row.tier ~= nil then NumberField(row, "tier") else index,
		name_t = if row.name_t ~= nil then StringField(row, "name_t") else nil,
		description_t = if row.description_t ~= nil then StringField(row, "description_t") else nil,
		capacityKg = NumberField(row, "capacityKg"),
		price = NumberField(row, "price"),
	})
end
assert(#baskets == 5, "Five basket tiers are required")
Config.Baskets = baskets
-- 接单时记录单人打包速度（kg/s）；升级不追溯修改正在打包的订单，费用为金币。
local restaurants: { Restaurant } = {}
for index, row in LoadRows("RestaurantData") do
	table.insert(restaurants, {
		id = if row.id ~= nil then NumberField(row, "id") else index,
		level = if row.level ~= nil then NumberField(row, "level") else index,
		name_t = if row.name_t ~= nil then StringField(row, "name_t") else nil,
		description_t = if row.description_t ~= nil then StringField(row, "description_t") else nil,
		workers = NumberField(row, "workers"),
		speed = NumberField(row, "speed"),
		price = NumberField(row, "price"),
	})
end
assert(#restaurants == 5, "Five restaurant levels are required")
for _, restaurant in restaurants do
	assert(restaurant.speed > 0 and restaurant.speed < math.huge, "Restaurant speed must be finite and positive (kg/s)")
end
Config.Restaurants = restaurants

function Config.GetSpecies(id: any): Species?
	for _, species in Config.Species do
		if species.id == id or species.key == id or tostring(species.id) == tostring(id) then return species end
	end
	return nil
end
function Config.GetQuality(id: any): Quality?
	for _, quality in Config.Qualities do
		if quality.id == id or quality.key == id or tostring(quality.id) == tostring(id) then return quality end
	end
	return nil
end
function Config.RollQuality(sample: number): QualityId
	-- Roblox Random:NextNumber 包含 0 和 1；右端点归入最后的巨型区间。
	assert(sample >= 0 and sample <= 1, "Quality sample must be in [0, 1]")
	local cumulative = 0
	for _, quality in Config.Qualities do
		cumulative += quality.probability
		if sample < cumulative then return quality.key end
	end
	return "giant"
end
function Config.GetDamage(tier: number, level: number): number
	local weapon = Config.Weapons[tier]
	assert(weapon and level % 1 == 0 and level >= 1 and level <= Config.MaximumWeaponLevel, "Invalid weapon tier or level")
	return weapon.damage + weapon.damageIncrement * (level - 1)
end
function Config.GetWeaponProgressStep(tier: number, level: number): number
	return tier * (Config.MaximumWeaponLevel + 1) + level
end

return Config
