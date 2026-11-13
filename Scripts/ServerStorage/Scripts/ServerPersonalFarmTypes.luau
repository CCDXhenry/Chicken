-- 个人农场类型契约：共享实体、经营会话、确认令牌与服务端测量状态
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local Save = require(Shared:WaitForChild("FarmSaveData"))
local Lifecycle = require(Shared:WaitForChild("LifecycleTool"))

export type Egg = { id: string, model: Model, speciesId: string, qualityId: string, height: number, origin: Vector3, landing: Vector3, started: number, landAt: number, finish: number, committed: boolean }
export type Animal = { id: string, model: Model, speciesId: string, qualityId: string, pos: Vector3, center: Vector3, direction: Vector3, nextTurn: number, health: number, maxHealth: number, fleeUntil: number, fleeReadyAt: number }
export type Confirmation = { id: string, kind: "species" | "hatch", speciesId: string?, previousSpeciesId: string?, targetId: string?, expiresAt: number, entityIds: { [string]: boolean }? }
export type GroundCargo = { model: Model, pos: Vector3, cargo: Save.Cargo, expiresAt: number }
export type FarmMetrics = {
	[string]: number,
	startedAt: number, cashStart: number, salesIncome: number, spent: number, sold: number,
	spawned: number, killed: number, collected: number, delivered: number, expired: number,
	fullSeconds: number, waitingItemSeconds: number, processingItemSeconds: number,
	unloadSeconds: number, deliveredKg: number, trips: number,
	firstSaleSeconds: number, firstEnhancementSeconds: number, firstAffordEnhancementSeconds: number,
	normalEggs: number, goldenEggs: number, rainbowEggs: number, giantEggs: number,
}
export type RestaurantActor = { model: Model, phase: string }
export type RestaurantState = {
	folder: Folder, packer: Model, workers: { RestaurantActor }, customers: { RestaurantActor }, leaving: { RestaurantActor },
	arrivalElapsed: number, purchaseRemaining: number, customerSequence: number,
}
export type Session = {
	restaurant: RestaurantState?,
	owner: Player, plot: BasePart, map: Folder, scope: Lifecycle.Lifecycle, farm: Save.FarmSave,
	eggs: { Egg }, animals: { [string]: Animal }, ground: { [string]: GroundCargo },
	nextEggAt: number, nextUnloadAt: number?, cooldowns: { [string]: number }, frozen: boolean, rng: Random,
	confirmation: Confirmation?,
	metrics: FarmMetrics?,
	testQualitySequence: { string }?, testQualityIndex: number?,
	projectedEggId: string?, projectedEggFinish: number?,
	lastUpdateAt: number?,
	lastZapShotId: number?,
}
return {}
