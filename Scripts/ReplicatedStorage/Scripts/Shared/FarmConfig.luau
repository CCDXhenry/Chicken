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
	CameraDefaultDistance = 16, -- 出生摄像机视距，studs
	CameraPitchAngle = -15, -- 出生摄像机俯仰角，度（向下倾斜15度）
	CameraHeightOffset = 2.5, -- 摄像机焦点相对 RootPart 高度偏移，studs
	CameraMinZoomDistance = 0.5, -- 允许玩家缩放的最小视距，studs
	CameraMaxZoomDistance = 128, -- 允许玩家缩放的最大视距，studs
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

	-- 动画与动作控制配置 (Prompt to Animation 规范与动力学参数)
	AnimationPrompts = {
		Zap_T1 = "A Roblox R15 character sharply swings an electrified wand forward in a crisp one-handed thrust and instantly resets to idle.",
		Zap_T2 = "A Roblox R15 character raises a sci-fi pistol with two hands, aims straight forward, and shoots with a punchy upward recoil kick.",
		Zap_Heavy = "A Roblox R15 character firmly plants feet in a combat stance, holding a heavy cannon with both hands, and fires with a strong backward body recoil.",
		Zap_T5 = "A Roblox R15 character thrusts a high-tech pulse weapon forward with both hands, unleashing a burst with a full-body forward shove and subtle shockwave recovery.",
		Pickup_Sweep = "A Roblox R15 character swiftly bends knees, reaches down with both hands to scoop up items from the floor, and stands back up smoothly.",
		Carry_Heavy = "A Roblox R15 character walks forward with a pronounced forward torso lean and heavier steps, conveying the weight of carrying a heavy backpack.",
	},
	-- 人物动作动画已停用（表现不佳）；保留键位占位，禁止填入并播放
	AnimationAssetIds = {
		Zap_T1 = "",
		Zap_T2 = "",
		Zap_Heavy = "",
		Zap_T5 = "",
		Pickup_Sweep = "",
		Carry_Heavy = "",
	} :: { [string]: string },
	EnableCharacterActionAnims = false,
	-- ReplicatedStorage.VFX 下的优质特效模板名（Edit 唯一来源，运行时只 Clone）
	VfxTemplateFolder = "VFX",
	VfxTemplates = {
		ZapMuzzlePrefix = "ZapMuzzle_T", -- ZapMuzzle_T1..T5
		ZapArc = "ZapArcBeam",
		HitImpact = "HitImpact",
		RoastFlight = "RoastFlight",
		FloatAnchor = "FloatAnchor",
	},

	-- 优质实例四层特效与飞行动效常数
	PickupFlightDuration = 0.32, -- 原熟食弹入背后背篓耗时，秒
	PickupArcHeight = 2.8, -- 弹飞弧顶附加高度，studs
	PickupBasketOffset = { x = 0, y = 0.55, z = 1 }, -- 背篓口，相对 HumanoidRootPart；正 Z 为背后
	PickupTumbleTurns = 0.5, -- 弹入时向后翻滚圈数
	PickupReserveRange = 22, -- 请求拾取时预克隆熟食的距离，studs
	PickupReserveSeconds = 1.5, -- 未命中预克隆的保留时间，秒
	PickupMatchDistance = 1.5, -- 视觉事件起点与预克隆的匹配距离，studs
	DeliveryFlightDuration = 0.25, -- 餐厅交货弧线飞入柜台耗时，秒
	DeliveryArcHeight = 3.2, -- 餐厅交货飞行弧顶高度，studs
	RecoilKickDistance = 0.18, -- 武器后坐力反冲距离，studs
	RecoilRecoverySeconds = 0.18, -- 后坐力平滑回正耗时，秒
	CameraShakeIntensity = 0.14, -- 镜头开火受击微震强度，studs
	CameraShakeDuration = 0.12, -- 镜头微震持续时间，秒
	VfxPoolWarmupCount = 24, -- 特效槽位预热数量 (零GC)
	ZapColors = {
		[1] = "53DEFF", -- T1 疾电短弧：冰青蓝
		[2] = "3B82F6", -- T2 连锁电枪：湛蓝电弧
		[3] = "F97316", -- T3 区域电炮：亮橙等离子
		[4] = "C084FC", -- T4 广角电炮：幻紫磁暴波
		[5] = "FACC15", -- T5 脉冲电炮：神圣金白
	},
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
		"FarmPlotId",
		"FarmSpawnSequence",
	},
}

return FarmConfig
