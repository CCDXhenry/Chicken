-- 新版个人农场数值契约：集中定义五物种、四品质、五阶装备与餐厅参数
--!strict
export type SpeciesId = "chicken" | "rabbit" | "sheep" | "cow" | "dragon"
export type QualityId = "normal" | "golden" | "rainbow" | "giant"
export type Species = {
	id: SpeciesId, tier: number, name: string, foodName: string, health: number, interval: number,
	hatchSeconds: number, weightKg: number, saleValue: number, unlockPrice: number,
	packSeconds: number, instantHatchPrice: number,
}
export type Quality = {
	id: QualityId, probability: number, healthMultiplier: number, weightMultiplier: number,
	valueMultiplier: number, hatchMultiplier: number, packMultiplier: number, visualScale: number,
}
export type Weapon = {
	range: number, mode: "single" | "chain" | "cone", maximumTargets: number,
	angleDegrees: number, chainRange: number, damage: number, damageIncrement: number,
	price: number, enhancementPrices: { number },
}
export type Collector = { range: number, maximumItems: number, angleDegrees: number, price: number }
export type Basket = { capacityKg: number, price: number }
export type Restaurant = { workers: number, speed: number, price: number }

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

-- 物种字段单位依次为 HP、秒、秒、kg、金币、金币、秒、金币；初始 T1 免费。
Config.Species = {
	{ id = "chicken", tier = 1, name = "Yellow Chicken", foodName = "Roast Chicken", health = 2, interval = 2.8, hatchSeconds = 3.5, weightKg = 1, saleValue = 10, unlockPrice = 0, packSeconds = 1.8, instantHatchPrice = 5 },
	{ id = "rabbit", tier = 2, name = "Flying Rabbit", foodName = "Honey Roast Rabbit", health = 6, interval = 2.6, hatchSeconds = 3.7, weightKg = 3, saleValue = 50, unlockPrice = 300, packSeconds = 2.1, instantHatchPrice = 25 },
	{ id = "sheep", tier = 3, name = "Woolly Sheep", foodName = "Herb Lamb Chop", health = 18, interval = 2.4, hatchSeconds = 4, weightKg = 9, saleValue = 250, unlockPrice = 1500, packSeconds = 2.5, instantHatchPrice = 125 },
	{ id = "cow", tier = 4, name = "Mighty Cow", foodName = "Tomahawk Steak", health = 54, interval = 2.2, hatchSeconds = 4.3, weightKg = 27, saleValue = 1250, unlockPrice = 7500, packSeconds = 4.6, instantHatchPrice = 625 },
	{ id = "dragon", tier = 5, name = "Lava Dragon", foodName = "Volcano Dragon Steak", health = 162, interval = 2, hatchSeconds = 4.6, weightKg = 81, saleValue = 6250, unlockPrice = 37500, packSeconds = 5.5, instantHatchPrice = 3125 },
} :: { Species }
-- 普通外观覆色；未列出的部件沿用既有模型，品质表现在此后叠加。
Config.SpeciesAppearance = {
	chicken = { Body = "FFE78A", Head = "FFF4BF" },
	dragon = { Body = "9B3527", Head = "CF4A2F", Leg = "CF4A2F", Tail = "9B3527", TailTip = "75302A", Jaw = "E58C45", Foot = "5D2922", Spine = "FFB646" },
} :: { [string]: { [string]: string } }
-- 概率和为 1；视觉缩放与重量倍率独立，巨型外观 2.5 倍、血量/重量 4 倍。
Config.Qualities = {
	{ id = "normal", probability = 0.9, healthMultiplier = 1, weightMultiplier = 1, valueMultiplier = 1, hatchMultiplier = 1, packMultiplier = 1, visualScale = 1 },
	{ id = "golden", probability = 0.08, healthMultiplier = 2, weightMultiplier = 2, valueMultiplier = 10, hatchMultiplier = 1.25, packMultiplier = 1.2, visualScale = 1 },
	{ id = "rainbow", probability = 0.018, healthMultiplier = 3, weightMultiplier = 3, valueMultiplier = 24, hatchMultiplier = 1.5, packMultiplier = 1.4, visualScale = 1 },
	{ id = "giant", probability = 0.002, healthMultiplier = 4, weightMultiplier = 4, valueMultiplier = 50, hatchMultiplier = 2, packMultiplier = 1.6, visualScale = 2.5 },
} :: { Quality }
-- 射程/跳距为 studs，角度为完整射界，伤害为每发共享总量，费用为金币。
Config.Weapons = {
	{ range = 9, mode = "single", maximumTargets = 1, angleDegrees = 180, chainRange = 0, damage = 2, damageIncrement = 1, price = 0, enhancementPrices = { 30, 60, 100, 160 } },
	{ range = 14, mode = "chain", maximumTargets = 4, angleDegrees = 180, chainRange = 10, damage = 6, damageIncrement = 3, price = 200, enhancementPrices = { 150, 300, 500, 800 } },
	{ range = 22, mode = "cone", maximumTargets = 5, angleDegrees = 60, chainRange = 0, damage = 18, damageIncrement = 9, price = 1000, enhancementPrices = { 750, 1500, 2500, 4000 } },
	{ range = 24, mode = "cone", maximumTargets = 7, angleDegrees = 90, chainRange = 0, damage = 54, damageIncrement = 27, price = 5000, enhancementPrices = { 3750, 7500, 12500, 20000 } },
	{ range = 28, mode = "cone", maximumTargets = 9, angleDegrees = 120, chainRange = 0, damage = 162, damageIncrement = 81, price = 25000, enhancementPrices = { 18750, 37500, 62500, 100000 } },
} :: { Weapon }
-- 拾取范围 studs，360 表示周围；成功拾取数才计入 maximumItems，费用为金币。
Config.Collectors = {
	{ range = 5.5, maximumItems = 1, angleDegrees = 360, price = 0 },
	{ range = 9, maximumItems = 3, angleDegrees = 100, price = 110 },
	{ range = 13, maximumItems = 5, angleDegrees = 360, price = 550 },
	{ range = 16, maximumItems = 8, angleDegrees = 360, price = 2750 },
	{ range = 20, maximumItems = 12, angleDegrees = 360, price = 13750 },
} :: { Collector }
-- 鸡筐承重 kg，逐阶购买费为金币，独立于拾取工具。
Config.Baskets = {
	{ capacityKg = 12, price = 0 }, { capacityKg = 36, price = 140 },
	{ capacityKg = 108, price = 700 }, { capacityKg = 324, price = 3500 },
	{ capacityKg = 972, price = 17500 },
} :: { Basket }
-- 接单时记录单人速度倍率；升级不追溯修改正在打包的订单，费用为金币。
Config.Restaurants = {
	{ workers = 1, speed = 1, price = 0 }, { workers = 1, speed = 1.35, price = 150 },
	{ workers = 1, speed = 1.6, price = 750 }, { workers = 2, speed = 1.6, price = 3750 },
	{ workers = 2, speed = 1.9, price = 18750 },
} :: { Restaurant }

function Config.GetSpecies(id: string): Species?
	for _, species in Config.Species do
		if species.id == id then return species end
	end
	return nil
end
function Config.GetQuality(id: string): Quality?
	for _, quality in Config.Qualities do
		if quality.id == id then return quality end
	end
	return nil
end
function Config.RollQuality(sample: number): QualityId
	-- Roblox Random:NextNumber 包含 0 和 1；右端点归入最后的巨型区间。
	assert(sample >= 0 and sample <= 1, "Quality sample must be in [0, 1]")
	local cumulative = 0
	for _, quality in Config.Qualities do
		cumulative += quality.probability
		if sample < cumulative then return quality.id end
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
