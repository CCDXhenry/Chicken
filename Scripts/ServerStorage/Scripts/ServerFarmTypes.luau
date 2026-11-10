-- 服务端农场类型契约：区分会话业务状态、模型表现引用与子系统上下文
--!strict
local replicatedStorage = game:GetService("ReplicatedStorage")
local sharedScripts = replicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local FarmConfig = require(sharedScripts:WaitForChild("FarmConfig"))
local LifecycleTool = require(sharedScripts:WaitForChild("LifecycleTool"))

export type PlayerFarmInfo = FarmConfig.PlayerFarmInfo
export type AnimalInfo = { center: Vector3, pos: Vector3, dir: Vector3, turn: number, phase: number, variant: number, maxHealth: number, health: number }
export type RoastInfo = { pos: Vector3, variant: number, expiresAt: number }
export type EggInfo = {
	model: Model,
	origin: Vector3,
	landing: Vector3,
	variant: number,
	started: number,
	landAt: number,
	finish: number,
	height: number,
	seconds: number?,
}
export type CustomerInfo = { model: Model, pos: Vector3, phase: number, inExitLane: boolean?, finish: number? }
export type StockInfo = { owner: Player, variant: number }
export type RestaurantInfo = {
	stock: { StockInfo },
	queue: { CustomerInfo },
	lanes: { [number]: CustomerInfo },
	leaving: { CustomerInfo },
	nextArrival: number,
	level: number,
	serial: number,
}
export type FarmSessionInfo = {
	flock: { [Model]: AnimalInfo },
	roasts: { [Model]: RoastInfo },
	eggs: { EggInfo },
	playerStates: { [Player]: PlayerFarmInfo },
	nestLevel: number,
	nextEggTime: number,
	restaurant: RestaurantInfo,
}
export type RestaurantSystem = {
	Deposit: (Player, { number }) -> number,
	Upgrade: (number) -> (number?, number?),
	Update: (number, number) -> (),
	GetLevel: () -> number,
	GetCount: () -> number,
	Destroy: () -> (),
}
export type FarmContext = {
	info: FarmSessionInfo,
	map: Folder,
	liveFolder: Folder,
	roastFolder: Folder,
	eggFolder: Folder,
	rng: Random,
	scope: LifecycleTool.Lifecycle,
	restaurant: RestaurantSystem,
	nestSign: BasePart,
	SyncPlayerState: (Player, PlayerFarmInfo) -> (),
	SendFeedback: (Player, string, string?) -> (),
}
export type NearbyTarget = { model: Model, pos: Vector3, dist: number }

return {}
