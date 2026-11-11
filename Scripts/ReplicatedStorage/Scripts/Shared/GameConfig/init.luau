-- 游戏全局配置中枢：负责维护全局版本、初始值与调试控制、非配表规则、配表子模块与字典索引
--!strict
local replicatedStorage: ReplicatedStorage? = if game then game:GetService("ReplicatedStorage") else nil
local GameConfig = {}

local FarmSaveData: any
if script and script.Parent then
	FarmSaveData = require(script.Parent:WaitForChild("FarmSaveData"))
else
	local ok, mod = pcall(require, "../FarmSaveData")
	if ok then
		FarmSaveData = mod
	else
		local ok2, mod2 = pcall(require, "./FarmSaveData")
		if ok2 then
			FarmSaveData = mod2
		else
			local ok3, mod3 = pcall(require, "../../Scripts/ReplicatedStorage/Scripts/Shared/FarmSaveData")
			if ok3 then
				FarmSaveData = mod3
			end
		end
	end
end

local DateTimeExtension: any = nil
if replicatedStorage then
	local core = replicatedStorage:WaitForChild("Core")
	local coreScripts = core:WaitForChild("Scripts")
	local coreSharedScripts = coreScripts:WaitForChild("Shared")
	DateTimeExtension = require(coreSharedScripts:FindFirstChild("DateTimeExtension"))
end

-- =========================================================
-- 1. 基础版本与环境配置
-- =========================================================
GameConfig.GameVersion = "1.0.0"
GameConfig.ABTestVersion = "1.0.0"
GameConfig.PlayerSaveInfoDataVersion = 1
GameConfig.GameId = 6376748064

if game and game.GameId == GameConfig.GameId then
	GameConfig.GamePlaceId = 17432470623
	GameConfig.ClearDataStorePlaceId = 18733054561
else
	GameConfig.GamePlaceId = 134743372234687
	GameConfig.ClearDataStorePlaceId = 18733054561
end

GameConfig.GamePassId = {}
GameConfig.GamePassPrice = {}

-- =========================================================
-- 2. 初始值设定 (方便调试测试；修改此处即影响新存档默认值)
-- =========================================================
GameConfig.InitialValues = {
	-- 初始金币 (调试测试时可改为如 100000 快速测试购买与升级)
	Cash = 0,

	-- 初始解锁物种 (string key)
	UnlockedSpecies = {
		chicken = true,
		-- rabbit = true, -- 调试时取消注释直接解锁
		-- sheep = true,
		-- cow = true,
		-- dragon = true,
	} :: { [string]: boolean },

	-- 初始选中物种 ID
	SelectedSpeciesId = "chicken",

	-- 初始武器与强化等级
	OwnedWeapons = { ["1"] = true } :: { [string]: boolean },
	WeaponLevels = { ["1"] = 1 } :: { [string]: number },
	EquippedWeaponTier = 1,

	-- 初始装备阶位
	CollectTier = 1,
	BasketTier = 1,
	RestaurantLevel = 1,
}

-- =========================================================
-- 3. 调试开关与倍率 (仅在开发/测试环境中方便调测)
-- =========================================================
GameConfig.Debug = {
	InstantHatchFree = false, -- 是否开启免费即时秒孵
	InstantCooking = false, -- 是否开启餐厅即时秒出餐
	InfiniteBasketCapacity = false, -- 是否忽略鸡筐重量上限
	OneHitKill = false, -- 是否一击击败动物
	CashMultiplier = 1, -- 金币获取倍率 (如设为 10 或 100)
}

-- =========================================================
-- 4. 非配表配置：物种外观部件覆色 (原物种外观表沉淀至此)
-- =========================================================
GameConfig.SpeciesAppearance = {
	chicken = {
		Body = "FFE78A",
		Head = "FFF4BF",
	},
	dragon = {
		Body = "9B3527",
		Head = "CF4A2F",
		Leg = "CF4A2F",
		Tail = "9B3527",
		TailTip = "75302A",
		Jaw = "E58C45",
		Foot = "5D2922",
		Spine = "FFB646",
	},
} :: { [string]: { [string]: string } }

-- =========================================================
-- 5. 非配表配置：农场经营物理与玩法通用规则
-- =========================================================
GameConfig.FarmRules = {
	PopulationCapacity = 28, -- 每名玩家农场蛋和活体合计上限 (个)
	EggFlightSeconds = 1.15, -- 抛蛋飞行时长 (秒)
	EggArcHeight = 6, -- 抛蛋最高高度 (studs)
	EggLandingBounds = {
		XMin = -11,
		XMax = 11,
		ZMin = -10,
		ZMax = 6,
	},
	GroundRoastLifetimeSeconds = 75, -- 地面熟食留存时长 (秒)
	ZapCooldownSeconds = 0.35, -- 电击冷却 (秒)
	CollectCooldownSeconds = 0.35, -- 拾取冷却 (秒)
	HatchCooldownSeconds = 0.75, -- 免费加速冷却 (秒)
	HatchReductionSeconds = 1, -- 每次免费加速减少时长 (秒)
	HatchInteractionRange = 8, -- 落地蛋交互距离 (studs)
	AnimalWalkSpeed = 3.8, -- 动物游荡速度 (studs/秒)
	AnimalFleeSpeed = 8.8, -- 动物受惊逃跑速度 (studs/秒)
	AnimalFleeRange = 6, -- 玩家惊扰判定半径 (studs)
	AnimalRoamRadius = 9, -- 游荡范围半径 (studs)
	AnimalHeights = { 0.78, 0.74, 1.1, 1.1, 1.26 }, -- 动物站立高度 (studs)
	CustomerSpeed = 9, -- 顾客移速 (studs/秒)
	CustomerQueueSpacing = 2.18, -- 顾客排队间距 (studs)
	CustomerArrivalInterval = 1.35, -- 顾客生成间隔 (秒)
	CustomerQueueCapacity = 4, -- 柜台队列最大排队人数
	RestaurantCapacity = 24, -- 餐厅备餐架最大容量 (份)
	MaximumWeaponLevel = 5, -- 武器最高强化等级
	PickupAnimationSteps = 8, -- 拾取动画步数
	PickupAnimationInterval = 0.025, -- 拾取动画步长 (秒)
}

-- =========================================================
-- 6. 非配表配置：村落地块与公共道路规则
-- =========================================================
GameConfig.VillageRules = {
	Capacity = 8,
	RowZ = { -192, -64, 64, 192 },
	ColumnX = 80,
	RoadWidth = 24,
	RoadLength = 520,
	PastureBounds = { MinX = -23, MaxX = 23, MinZ = -23, MaxZ = 18 },
}

-- =========================================================
-- 7. 非配表配置：UI 与交互参数
-- =========================================================
GameConfig.UIRules = {
	ScanSeconds = 0.15,
	RequestTimeout = 2,
	MessageDuration = 2.5,
	SaleNoticeDuration = 2,
}

-- =========================================================
-- 8. 配表子模块引入与索引字典构建 (对标 ModelCapture)
-- =========================================================
local function LoadChildModule(moduleName: string): any
	if script then
		local child = script:FindFirstChild(moduleName)
		if child and child:IsA("ModuleScript") then
			return require(child)
		end
	end
	local ok, res = pcall(require, "./" .. moduleName)
	if ok then return res end
	local ok2, res2 = pcall(require, "./GameConfig/" .. moduleName)
	if ok2 then return res2 end
	local ok3, res3 = pcall(require, "../../Scripts/ReplicatedStorage/Scripts/Shared/GameConfig/" .. moduleName)
	if ok3 then return res3 end
	return {}
end

local SpeciesDataModule = LoadChildModule("SpeciesData")
local QualityDataModule = LoadChildModule("QualityData")
local WeaponDataModule = LoadChildModule("WeaponData")
local CollectorDataModule = LoadChildModule("CollectorData")
local BasketDataModule = LoadChildModule("BasketData")
local RestaurantDataModule = LoadChildModule("RestaurantData")

GameConfig.Species = SpeciesDataModule
GameConfig.SpeciesMap = {} :: { [any]: any }
GameConfig.SpeciesTierMap = {} :: { [number]: any }
if type(SpeciesDataModule) == "table" then
	for _, sp in SpeciesDataModule do
		if type(sp) == "table" then
			if sp.id then
				GameConfig.SpeciesMap[sp.id] = sp
			end
			if sp.key then
				GameConfig.SpeciesMap[sp.key] = sp
			end
			if sp.tier then
				GameConfig.SpeciesTierMap[sp.tier] = sp
			end
		end
	end
end

GameConfig.Qualities = QualityDataModule
GameConfig.QualityMap = {} :: { [any]: any }
if type(QualityDataModule) == "table" then
	for _, q in QualityDataModule do
		if type(q) == "table" then
			if q.id then
				GameConfig.QualityMap[q.id] = q
			end
			if q.key then
				GameConfig.QualityMap[q.key] = q
			end
		end
	end
end

GameConfig.Weapons = WeaponDataModule
GameConfig.Collectors = CollectorDataModule
GameConfig.Baskets = BasketDataModule
GameConfig.Restaurants = RestaurantDataModule

-- =========================================================
-- 9. 玩家设置与存档类型
-- =========================================================
export type SettingInfo = {
	bgmVolume: number,
	soundEffectVolume: number,
	vibrationOn: boolean,
}

export type PlayerConfigInfo = {}

export type PlayerSaveInfo = {
	dataVersion: number,
	firstEnterTime: number,
	firstEnterVersion: string,
	gameTime: number,
	loginDays: number,
	lastOnlineDateUTC: number,
	settingInfo: SettingInfo,
	ownedGamePassList: { number },
	farm: FarmSaveData.FarmSave,
}

export type PlayerInfo = PlayerSaveInfo & {
	playerInfoChanged: boolean,
	changeRevision: number,
	timeOfThisLogin: number,
	countryRegion: string,
	lastOnlineDate: any,
	ownedGamePassMap: { [number]: boolean },
	playerConfigInfo: PlayerConfigInfo,
}

export type ReceiptInfo = {
	PurchaseId: string,
	PlayerId: number,
	ProductId: number,
	PlaceIdWherePurchased: number,
	CurrencySpent: number,
	CurrencyType: Enum.CurrencyType,
}

-- 默认玩家存档 (将 GameConfig.InitialValues 注入默认档，方便调试与调参)
function GameConfig.CreateDefaultPlayerSaveInfo(): PlayerSaveInfo
	local nowUnix = if DateTime then DateTime.now().UnixTimestamp else os.time()
	local lastOnlineUtc = nowUnix
	if DateTimeExtension and DateTime then
		local nowDate = DateTimeExtension.GetNowDate()
		lastOnlineUtc = DateTime.fromUniversalTime(nowDate.Year, nowDate.Month, nowDate.Day).UnixTimestamp
	end

	return {
		dataVersion = GameConfig.PlayerSaveInfoDataVersion,
		firstEnterTime = nowUnix,
		firstEnterVersion = GameConfig.GameVersion,
		gameTime = 0,
		loginDays = 1,
		lastOnlineDateUTC = lastOnlineUtc,
		settingInfo = {
			bgmVolume = 1,
			soundEffectVolume = 1,
			vibrationOn = true,
		},
		ownedGamePassList = {},
		farm = FarmSaveData.CreateDefault(GameConfig.InitialValues),
	}
end

export type ClientLocalPlayerSaveInfo = {
	settingInfo: SettingInfo,
	ownedGamePassList: { number },
}

export type ClientLocalPlayerInfo = ClientLocalPlayerSaveInfo & {
	ownedGamePassMap: { [number]: boolean },
	playerConfigInfo: PlayerConfigInfo,
}

export type ClientOtherPlayerSaveInfo = {}
export type ClientOtherPlayerSyncInfo = ClientOtherPlayerSaveInfo & {}
export type ClientOtherPlayerInfo = ClientOtherPlayerSyncInfo & {}

return GameConfig
