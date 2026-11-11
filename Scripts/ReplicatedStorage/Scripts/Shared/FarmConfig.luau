-- 农场现行玩法配置：集中维护本轮重构前的参数，不提前采用策划的新数值
--!strict
export type FarmAction = "zap" | "collect" | "buyZap" | "buyCollect" | "buyNest" | "buyRestaurant"
export type PlayerFarmInfo = {
	cash: number,
	items: { number },
	zap: number,
	collect: number,
	cooldowns: { [string]: number },
	zapTarget: Model?,
	atFullShelf: boolean?,
}
export type ClientFarmInfo = {
	stage: number?,
	ready: boolean?,
	unlockedSpecies: { [string]: boolean }?,
	confirmationId: string?,
	confirmationMessage: string?,
	confirmationRisk: string?,
	weaponLevels: { [string]: number }?,
	weaponLevel: number?,
	basketTier: number?,
	eggId: string?,
	eggSpecies: string?,
	eggQuality: string?,
	eggEndTime: number?,
	eggPrice: number?,
	basketWeight: number?,
	basketCapacity: number?,
	damage: number?,
	waiting: number?,
	processing: number?,
	expectedValue: number?,
	cash: number,
	basketCount: number,
	zap: number,
	collect: number,
	stock: number,
	atShop: boolean,
	atNest: boolean,
	atRestaurant: boolean,
	nestLevel: number,
	restaurantLevel: number,
}

local FarmConfig = {
	ZoneHeightTolerance = 8, -- 交互区允许的垂直距离，studs
	CharacterRootWait = 8, -- 等待角色根部件的超时，秒
	SpawnHeight = 3.5, -- 角色生成点上方偏移，studs
	AnimalTurnMinimumInterval = 0.65, -- 游荡转向最短间隔，秒
	AnimalTurnMaximumInterval = 1.65, -- 游荡转向最长间隔，秒
	EggLandingXMinimum = -11, -- 现有共享牧场落蛋区 X 最小坐标，studs
	EggLandingXMaximum = 11, -- 落蛋区 X 最大坐标，studs
	EggLandingZMinimum = -10, -- 落蛋区 Z 最小坐标，studs
	EggLandingZMaximum = 6, -- 落蛋区 Z 最大坐标，studs
	EggArcHeight = 6, -- 抛蛋轨迹最高附加高度，studs
	CustomerSpeed = 9, -- 顾客移动速度，studs/秒
	CustomerQueueSpacing = 2.18, -- 排队间距，studs
	CustomerArrivalThreshold = 0.55, -- 进入柜台前的队首到达判定，studs
	CustomerMoveThreshold = 0.06, -- 顾客抵达位置判定，studs
	CounterApproachOffset = 1.75, -- 柜台服务点偏移，studs
	MaximumRestaurantLevel = 3, -- 当前餐厅最高等级；第三级开放第二柜台
	PickupAnimationSteps = 8, -- 熟食飞入鸡筐的动画步数
	PickupAnimationInterval = 0.025, -- 拾取动画每步间隔，秒

	BasketCapacity = 6, -- 鸡筐容量，单位份；本轮保留件数制
	ToolPrices = { 60, 180 }, -- 工具逐级购买价格，金币；最高三级
	CollectLimits = { 1, 3, 6 }, -- 每次拾取最多件数，按工具等级索引
	CollectRanges = { 5.5, 10, 17 }, -- 拾取距离，studs
	ZapRanges = { 9, 14, 21 }, -- 电击首目标射程，studs
	ZapMinimumDots = { -0.15, -0.15, 0.42 }, -- 水平方向夹角余弦下限
	ChainRange = 10, -- 二级武器后续目标查询半径，studs；保留现有分配顺序
	ZapCooldown = 0.55, -- 电击冷却，秒
	ActionCooldown = 0.27, -- 其余动作冷却，秒
	UpdateInterval = 0.075, -- 农场逻辑刷新间隔，秒
	MaximumDeltaTime = 0.2, -- 单次逻辑步长上限，秒
	PopulationCapacity = 28, -- 蛋与活体合计上限
	EggFlightDuration = 1.15, -- 蛋飞行时长，秒；落地后开始孵化
	RoastLifetime = 75, -- 地面熟食保留时长，秒；入库后结束此计时
	NestUpgradeDelay = 0.4, -- 现有产蛋窝升级后的最迟产蛋延迟，秒
	RestaurantCapacity = 24, -- 备餐架容量，份
	RestaurantDurations = { 3.4, 1.9, 1.5 }, -- 现有各等级点单时间，秒
	CustomerArrivalInterval = 1.35, -- 顾客生成间隔，秒
	CustomerQueueCapacity = 4, -- 等待队列人数上限
	AnimalWalkSpeed = 3.8, -- 游荡速度，studs/秒
	AnimalFleeSpeed = 8.8, -- 受惊速度，studs/秒
	AnimalFleeRange = 6, -- 玩家惊扰半径，studs
	AnimalRoamRadius = 9, -- 游荡中心边界，studs
	AnimalHeights = { 0.78, 0.74, 1.1, 1.1, 1.26 }, -- 各物种模型站立高度，studs
	MessageDuration = 2.5, -- 操作反馈展示时间，秒
	SaleNoticeDuration = 2, -- 销售反馈展示时间，秒
	Actions = { zap = true, collect = true, buyZap = true, buyCollect = true, buyNest = true, buyRestaurant = true } :: { [string]: boolean },
	AttributeNames = {
		"FarmStage", "FarmReady", "FarmBasketWeight", "FarmBasketCapacity", "FarmDamage",
		"FarmWaiting", "FarmProcessing", "FarmExpectedValue",
		"FarmConfirmId", "FarmConfirmMessage", "FarmConfirmRisk",
		"FarmSpecies_chicken", "FarmSpecies_rabbit", "FarmSpecies_sheep", "FarmSpecies_cow", "FarmSpecies_dragon",
		"FarmWeaponLevel", "FarmBasketTier", "FarmWeaponLevel_1", "FarmWeaponLevel_2", "FarmWeaponLevel_3", "FarmWeaponLevel_4", "FarmWeaponLevel_5",
		"FarmEggId", "FarmEggSpecies", "FarmEggQuality", "FarmEggEndTime", "FarmEggPrice",
		"FarmCash",
		"FarmBasket",
		"FarmZap",
		"FarmCollect",
		"FarmShop",
		"FarmStock",
		"FarmNestShop",
		"FarmRestaurantShop",
		"FarmNestLevel",
		"FarmRestaurantLevel",
	},
}

return FarmConfig
