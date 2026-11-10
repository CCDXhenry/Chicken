-- 烤鸡农场数据字典与全局配置：定义生物种类、蛋孵化、电击伤害与餐厅升级等基础数值
--!strict
export type CreatureConfig = {
	name: string,
	health: number,
	egg: string,
	food: string,
	interval: number,
	hatch: number,
	value: number,
	unlock: number,
	shell: string,
	spot: string,
}

export type CatalogConfig = {
	zapDamage: { number },
	restaurantPrices: { number },
	creatures: { CreatureConfig },
}

local creatures: { CreatureConfig } = {
	{
		name = "Chicken",
		health = 1,
		egg = "Chicken Egg",
		food = "Roast Chicken",
		interval = 2.4,
		hatch = 4,
		value = 10,
		unlock = 0,
		shell = "FFF0CF",
		spot = "F2B946",
	},
	{
		name = "Rabbit",
		health = 3,
		egg = "Rabbit Egg",
		food = "Honey Roast Rabbit",
		interval = 3.1,
		hatch = 7,
		value = 20,
		unlock = 60,
		shell = "FBC8E9",
		spot = "E87CB6",
	},
	{
		name = "Sheep",
		health = 9,
		egg = "Sheep Egg",
		food = "Herb Lamb Chop",
		interval = 3.9,
		hatch = 10,
		value = 35,
		unlock = 180,
		shell = "E9DAFF",
		spot = "AC79DF",
	},
	{
		name = "Cow",
		health = 27,
		egg = "Cow Egg",
		food = "Grilled Steak",
		interval = 4.8,
		hatch = 14,
		value = 55,
		unlock = 360,
		shell = "F5E6D2",
		spot = "92634B",
	},
	{
		name = "Dinosaur",
		health = 81,
		egg = "Dinosaur Egg",
		food = "Volcano Dinosaur Steak",
		interval = 5.8,
		hatch = 19,
		value = 85,
		unlock = 640,
		shell = "A4ED73",
		spot = "4DAD59",
	},
}

local RoastChickenCatalog = {
	zapDamage = { 1, 3, 5 },
	restaurantPrices = { 90, 260 },
	creatures = creatures,
} :: CatalogConfig

return RoastChickenCatalog
