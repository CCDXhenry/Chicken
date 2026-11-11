-- 个人农场主管理器：加载后分配地块，调度物种品质链、主人交互与退出冻结
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("FarmEconomyConfig"))
local FarmConfig = require(Shared:WaitForChild("FarmConfig"))
local Save = require(Shared:WaitForChild("FarmSaveData"))
local Business = require(Shared:WaitForChild("FarmBusiness"))
local CombatRules = require(Shared:WaitForChild("FarmCombatRules"))
local HatchRules = require(Shared:WaitForChild("FarmHatchRules"))
local NetMsg = require(Shared:WaitForChild("NetMsg"))
local FarmRequest = require(Shared:WaitForChild("FarmRequest"))
local Lifecycle = require(Shared:WaitForChild("LifecycleTool"))
local Texts = require(Shared:WaitForChild("GameTexts"))
local NumberFormat = require(Shared:WaitForChild("FarmNumberFormat"))
local ServerGameInfo = require(script.Parent:WaitForChild("ServerGameInfo"))
local Scene = require(script.Parent:WaitForChild("ServerRoastChickenFarmManager"):WaitForChild("ServerFarmSceneTool"))
local Builder = require(script.Parent:WaitForChild("ServerRoastChickenFarmManager"):WaitForChild("ServerCreatureBuilder"))

local Types = require(script.Parent:WaitForChild("ServerPersonalFarmTypes"))
local View = require(script.Parent:WaitForChild("ServerPersonalFarmView"))
local FarmSoundTool = require(Shared:WaitForChild("FarmSoundTool"))
local Village = require(script.Parent:WaitForChild("ServerFarmVillageTool"))
local VillageConfig = require(Shared:WaitForChild("FarmVillageConfig"))
type Egg = Types.Egg
type Animal = Types.Animal
type Confirmation = Types.Confirmation
export type FarmMetrics = Types.FarmMetrics
export type Session = Types.Session
local Manager = {}
Manager.__index = Manager
export type ServerPersonalFarmManager = typeof(setmetatable({} :: {
	sessions: { [Player]: Session }, reservations: { [BasePart]: Player }, waiting: { [Player]: boolean },
	scope: Lifecycle.Lifecycle?, runtime: Folder?, legacy: Folder?, running: boolean,
}, Manager))
local activeManager: ServerPersonalFarmManager?
local UpdateSeconds = 0.075 -- 会话更新周期，秒；生产按时间戳而非帧数计算
local MaximumDelta = 0.2 -- 动物移动步长上限，秒；打包和经营计时使用当前会话的实际在线步长
local TurnSeconds = 1 -- 动物游荡方向刷新间隔，秒
local RoamRadius = 9 -- 相对出生点游荡半径，studs
local ConfirmationSeconds = 15 -- 物种购买/清理确认有效期，秒；令牌只能消费一次

local SetOwnership = View.SetOwnership
local SetSign = View.SetSign
local ApplyQuality = View.ApplyQuality
local UpdateQuality = View.UpdateQuality

local function MarkChanged(session: Session): ()
	ServerGameInfo.MarkPlayerInfoChanged(session.owner)
end
local function GetMetrics(session: Session): FarmMetrics
	local metrics = session.metrics
	if metrics then return metrics end
	local created: FarmMetrics = { startedAt = os.clock(), cashStart = session.farm.cash, salesIncome = 0, spent = 0, sold = 0, spawned = 0, killed = 0, collected = 0, delivered = 0, expired = 0, fullSeconds = 0, waitingItemSeconds = 0, processingItemSeconds = 0, unloadSeconds = 0, deliveredKg = 0, trips = 0, firstSaleSeconds = -1, firstEnhancementSeconds = -1, firstAffordEnhancementSeconds = -1, normalEggs = 0, goldenEggs = 0, rainbowEggs = 0, giantEggs = 0 }
	session.metrics = created
	return created
end
local function FindEgg(session: Session, targetId: string?, now: number): Egg?
	local root = Scene.GetPlayerRoot(session.owner)
	if not root then return nil end
	local closest: Egg?
	local bestDistance = Config.HatchInteractionRange
	for _, egg in session.eggs do
		local distance = (egg.landing + Vector3.yAxis * egg.height - root.Position).Magnitude
		if not egg.committed and now >= egg.landAt and now < egg.finish and (not targetId or egg.id == targetId) and distance <= bestDistance then closest, bestDistance = egg, distance end
	end
	return closest
end
local function Project(session: Session): ()
	GetMetrics(session)
	local now = os.clock()
	View.Project(session, FindEgg(session, nil, now), now)
end
local function GetFolder(parent: Instance, name: string): Folder
	local folder = parent:FindFirstChild(name)
	if folder and folder:IsA("Folder") then return folder end
	local created = Instance.new("Folder")
	created.Name, created.Parent = name, parent
	return created
end
local function PositionCharacter(session: Session, character: Model): ()
	session.scope:Spawn(function()
		local root = character:WaitForChild("HumanoidRootPart", FarmConfig.CharacterRootWait)
		if root and session.scope.alive and not session.frozen and session.owner.Character == character then
			local spawn = session.map:FindFirstChild("FarmSpawn")
			if spawn and spawn:IsA("BasePart") then
				character:PivotTo(spawn.CFrame * CFrame.new(0, FarmConfig.SpawnHeight, 0))
				local currentSeq = session.owner:GetAttribute("FarmSpawnSequence")
				local seq = (if typeof(currentSeq) == "number" then currentSeq else 0) + 1
				session.owner:SetAttribute("FarmSpawnSequence", seq)
			end
			Project(session)
		end
	end)
end
local function SpawnEgg(session: Session, now: number): ()
	local species = Config.GetSpecies(session.farm.selectedSpeciesId)
	assert(species)
	local qualityId = Config.RollQuality(session.rng:NextNumber())
	local sequence = session.testQualitySequence
	if RunService:IsStudio() and sequence and #sequence > 0 then
		local index = session.testQualityIndex or 1
		qualityId = sequence[(index - 1) % #sequence + 1] :: Config.QualityId
		session.testQualityIndex = index + 1
	end
	local quality = Config.GetQuality(qualityId)
	assert(quality)
	local originPart = session.map:WaitForChild("Nest"):FindFirstChild("Chute") :: BasePart
	local landing = session.plot.CFrame:PointToWorldSpace(Vector3.new(session.rng:NextNumber(FarmConfig.EggLandingXMinimum, FarmConfig.EggLandingXMaximum), 0, session.rng:NextNumber(FarmConfig.EggLandingZMinimum, FarmConfig.EggLandingZMaximum)))
	local model = Instance.new("Model")
	model.Name = species.name .. "Egg"
	SetOwnership(model, session)
	local id = HttpService:GenerateGUID(false)
	model:SetAttribute("EntityId", id)
	model:SetAttribute("SpeciesId", species.key)
	model:SetAttribute("QualityId", qualityId)
	local shell = Scene.CreatePiece(model, "Shell", Vector3.new(1.35, 1.73, 1.35), CFrame.new(originPart.Position), "FFF0CF", true)
	model.PrimaryPart = shell
	shell:SetAttribute("FarmSignAudience", "Public")
	ApplyQuality(model, qualityId)
	model:SetAttribute("HatchStartTime", workspace:GetServerTimeNow() + Config.EggFlightSeconds)
	model:SetAttribute("HatchDuration", species.hatchSeconds * quality.hatchMultiplier)
	model:SetAttribute("HatchEndTime", workspace:GetServerTimeNow() + Config.EggFlightSeconds + species.hatchSeconds * quality.hatchMultiplier)
	model:SetAttribute("HatchAccelerationSequence", 0)
	model.Parent = GetFolder(session.map, "Eggs")
	local egg: Egg = { id = id, model = model, speciesId = species.key, qualityId = qualityId, height = 0.865 * quality.visualScale, origin = originPart.Position, landing = landing, started = now, landAt = now + Config.EggFlightSeconds, finish = now + Config.EggFlightSeconds + species.hatchSeconds * quality.hatchMultiplier, committed = false }
	table.insert(session.eggs, egg)
	FarmSoundTool.Play("EggSpawn", originPart.Position)
	GetMetrics(session).spawned += 1
	GetMetrics(session)[qualityId .. "Eggs"] += 1
end
local function SpawnAnimal(session: Session, egg: Egg): ()
	local species, quality = Config.GetSpecies(egg.speciesId), Config.GetQuality(egg.qualityId)
	assert(species and quality)
	local model = Builder.Build(species.tier, false, Scene.CreatePiece)
	model.Name = species.name
	View.ApplySpecies(model, egg.speciesId)
	ApplyQuality(model, egg.qualityId)
	SetOwnership(model, session)
	model:SetAttribute("EntityId", egg.id)
	model:SetAttribute("SpeciesId", egg.speciesId)
	model:SetAttribute("QualityId", egg.qualityId)
	local health = species.health * quality.healthMultiplier
	model:SetAttribute("Health", health)
	model:SetAttribute("MaxHealth", health)
	local primary = model.PrimaryPart
	if primary then
		SetSign(primary, "AnimalHealthGui", Texts.Farm.PersonalHealth.source:format(species.name, egg.qualityId, NumberFormat.Number(health), NumberFormat.Number(health)), session.owner.UserId, "Public")
		Scene.SetHealthTone(primary, false)
		primary:SetAttribute("FarmStudsOffsetY", 2 * quality.visualScale)
	end
	model:PivotTo(CFrame.new(egg.landing + Vector3.yAxis * FarmConfig.AnimalHeights[species.tier] * quality.visualScale))
	model.Parent = GetFolder(session.map, "LiveAnimals")
	session.animals[egg.id] = { id = egg.id, model = model, speciesId = egg.speciesId, qualityId = egg.qualityId, pos = egg.landing, center = egg.landing, direction = Vector3.zAxis, nextTurn = 0, health = health, maxHealth = health, fleeUntil = 0, fleeReadyAt = 0 }
end
local function HatchEgg(session: Session, egg: Egg, now: number, price: number?): boolean
	local index = table.find(session.eggs, egg)
	if not index then return false end
	local committed: boolean
	local remainingCash = session.farm.cash
	if price then committed, remainingCash = HatchRules.TryInstantHatch(egg, now, session.farm.cash, price)
	else committed = HatchRules.TryCommit(egg, now) end
	if not committed then return false end
	table.remove(session.eggs, index)
	SpawnAnimal(session, egg)
	egg.model:Destroy()
	FarmSoundTool.Play("EggHatch", egg.landing)
	if price then
		session.farm.cash = remainingCash
		session.farm.revision += 1
		MarkChanged(session)
		GetMetrics(session).spent += price
	end
	return true
end
local function UpdateProduction(session: Session, now: number, dt: number): ()
	local count = #session.eggs
	local species = Config.GetSpecies(session.farm.selectedSpeciesId)
	assert(species)
	for _ in session.animals do count += 1 end
	if count >= Config.PopulationCapacity then GetMetrics(session).fullSeconds += dt end
	if count < Config.PopulationCapacity and now >= session.nextEggAt then
		SpawnEgg(session, now)
		session.nextEggAt = now + species.interval
	end
	for i = #session.eggs, 1, -1 do
		local egg = session.eggs[i]
		UpdateQuality(egg.model, egg.qualityId, now)
		if now >= egg.finish then
			-- 在同一无 yield 调用中移除蛋并生成动物，不能重复转换。
			HatchEgg(session, egg, now)
		elseif now < egg.landAt then
			local t = math.clamp((now - egg.started) / Config.EggFlightSeconds, 0, 1)
			egg.model:PivotTo(CFrame.new(egg.origin:Lerp(egg.landing + Vector3.yAxis * egg.height, t) + Vector3.yAxis * math.sin(t * math.pi) * FarmConfig.EggArcHeight))
		else
			if not egg.model:GetAttribute("HasLanded") then
				egg.model:SetAttribute("HasLanded", true)
				FarmSoundTool.Play("EggLand", egg.landing)
			end
			egg.model:PivotTo(CFrame.new(egg.landing + Vector3.yAxis * egg.height))
			local shell = egg.model.PrimaryPart
			local eggSpecies = Config.GetSpecies(egg.speciesId)
			if shell and eggSpecies then SetSign(shell, "EggSignGui", Texts.Farm.QualityEggCountdown.source:format(eggSpecies.name, egg.qualityId, math.max(0, math.ceil(egg.finish - now))), session.owner.UserId, "Public") end
		end
	end
	local nest = session.map:WaitForChild("Nest"):FindFirstChild("ProductionSign")
	if nest and nest:IsA("BasePart") then
		SetSign(nest, "NestSignGui", Texts.Farm.NestStatus.source:format(species.tier, species.name, if count >= Config.PopulationCapacity then Texts.Farm.PopulationFull.source else Texts.Farm.NextEgg.source:format(math.max(0, math.ceil(session.nextEggAt - now)))), session.owner.UserId, "Public")
	end
end
local function UpdateAnimals(session: Session, now: number, dt: number): ()
	local root = Scene.GetPlayerRoot(session.owner)
	for _, animal in session.animals do
		local species, quality = Config.GetSpecies(animal.speciesId), Config.GetQuality(animal.qualityId)
		assert(species and quality)
		UpdateQuality(animal.model, animal.qualityId, now)
		if root and now >= animal.fleeReadyAt then
			local away = Scene.FlatVector(animal.pos - root.Position)
			if away.Magnitude < Config.AnimalFleeRange and away.Magnitude > 0.01 then
				animal.direction = away.Unit
				animal.fleeUntil = now + Config.AnimalFleeSeconds
				animal.fleeReadyAt = animal.fleeUntil + Config.AnimalFleeSeconds
				FarmSoundTool.Play("AnimalScared", animal.pos)
			end
		end
		if now >= animal.nextTurn and now >= animal.fleeUntil then
			animal.nextTurn = now + TurnSeconds
			local angle = session.rng:NextNumber(0, math.pi * 2)
			animal.direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		end
		local offset = animal.center - animal.pos
		if offset.Magnitude > RoamRadius then animal.direction = offset.Unit end
		local proposed = animal.pos + animal.direction * (if now < animal.fleeUntil then Config.AnimalFleeSpeed else Config.AnimalWalkSpeed) * dt
		local point = session.plot.CFrame:PointToObjectSpace(proposed)
		local bounded = Vector3.new(math.clamp(point.X, VillageConfig.PastureMinimumX, VillageConfig.PastureMaximumX), 0, math.clamp(point.Z, VillageConfig.PastureMinimumZ, VillageConfig.PastureMaximumZ))
		if point.X ~= bounded.X or point.Z ~= bounded.Z then animal.direction = -animal.direction end
		animal.pos = session.plot.CFrame:PointToWorldSpace(bounded)
		local pos = animal.pos + Vector3.yAxis * FarmConfig.AnimalHeights[species.tier] * quality.visualScale
		animal.model:PivotTo(CFrame.lookAt(pos, pos + animal.direction))
	end
end
local function UpdateInventory(session: Session, now: number, dt: number): ()
	for id, ground in session.ground do
		UpdateQuality(ground.model, ground.cargo.qualityId, now)
		if now >= ground.expiresAt then session.ground[id] = nil; ground.model:Destroy(); GetMetrics(session).expired += 1 end
	end
	local root = Scene.GetPlayerRoot(session.owner)
	local sell = session.map:FindFirstChild("Sell")
	if root and sell and sell:IsA("BasePart") and Scene.IsInZone(root, sell) and #session.farm.basket > 0 then
		local metrics = GetMetrics(session)
		metrics.unloadSeconds += dt
		if not session.nextUnloadAt then metrics.trips += 1 end
		local nextUnloadAt = session.nextUnloadAt or now + Config.UnloadIntervalSeconds
		session.nextUnloadAt = nextUnloadAt
		local deposited = false
		while now >= nextUnloadAt and #session.farm.basket > 0 do
			metrics.deliveredKg += session.farm.basket[1].weightKg
			Business.DepositOne(session.farm)
			metrics.delivered += 1
			nextUnloadAt += Config.UnloadIntervalSeconds
			deposited = true
		end
		session.nextUnloadAt = nextUnloadAt
		if deposited then
			FarmSoundTool.Play("Delivery", sell.Position)
			MarkChanged(session)
		end
	else
		session.nextUnloadAt = nil
	end
end
local function CookAnimal(session: Session, animal: Animal): ()
	GetMetrics(session).killed += 1
	local species = Config.GetSpecies(animal.speciesId)
	assert(species)
	session.animals[animal.id] = nil
	animal.model:Destroy()
	local cargo = Business.CreateCargo(animal.id, animal.speciesId, animal.qualityId)
	local model = Builder.Build(species.tier, true, Scene.CreatePiece)
	model.Name = species.foodName
	model:SetAttribute("FoodName", species.foodName)
	ApplyQuality(model, animal.qualityId)
	SetOwnership(model, session)
	model:SetAttribute("ItemId", cargo.itemId)
	model:SetAttribute("SpeciesId", cargo.speciesId)
	model:SetAttribute("QualityId", cargo.qualityId)
	model:SetAttribute("WeightKg", cargo.weightKg)
	model:SetAttribute("SaleValue", cargo.saleValue)
	model:SetAttribute("ExpiresAt", workspace:GetServerTimeNow() + Config.GroundLifetimeSeconds)
	model:SetAttribute("Lifetime", Config.GroundLifetimeSeconds)
	local pos = animal.pos + Vector3.yAxis * 0.53
	model:PivotTo(CFrame.new(pos))
	model.Parent = GetFolder(session.map, "CookedFood")
	session.ground[cargo.itemId] = { model = model, pos = pos, cargo = cargo, expiresAt = os.clock() + Config.GroundLifetimeSeconds }
	FarmSoundTool.Play("FoodDrop", pos)
	local primary = model.PrimaryPart
	if primary then
		local quality = Config.GetQuality(animal.qualityId)
		local visualScale = if quality then quality.visualScale else 1
		primary:SetAttribute("FarmStudsOffsetY", 2.0 * visualScale)
		SetSign(primary, "CookedFoodSignGui", "", session.owner.UserId)
	end
end
local function Zap(session: Session, root: BasePart, aim: Vector3?): ()
	local candidates: { CombatRules.Candidate } = {}
	for _, animal in session.animals do
		table.insert(candidates, { id = animal.id, x = animal.pos.X, y = animal.pos.Y, z = animal.pos.Z, health = animal.health })
	end
	local farm = session.farm
	-- 范围攻击以玩家为中心：全向 360 度索敌
	local hits = CombatRules.ResolveShot(
		farm.equippedWeaponTier,
		farm.weaponLevels[tostring(farm.equippedWeaponTier)],
		root.Position.X,
		root.Position.Y,
		root.Position.Z,
		nil,
		nil,
		candidates
	)
	if #hits == 0 then NetMsg.FireNotifyFarmFeedback(session.owner, Texts.Farm.AimHint.source); return end
	local from = root.Position
	local total, cooked = 0, 0
	for _, hit in hits do
		local animal = session.animals[hit.id]
		animal.health -= hit.damage
		total += hit.damage
		Scene.SpawnLightningArc(session, from, animal.pos + Vector3.yAxis)
		if Config.Weapons[farm.equippedWeaponTier].mode == "chain" then from = animal.pos + Vector3.yAxis end
		if animal.health == 0 then CookAnimal(session, animal); cooked += 1 else
			animal.model:SetAttribute("Health", animal.health)
			local species = Config.GetSpecies(animal.speciesId)
			local primary = animal.model.PrimaryPart
			if species and primary then
				SetSign(primary, "AnimalHealthGui", Texts.Farm.PersonalHealth.source:format(species.name, animal.qualityId, NumberFormat.Number(animal.health), NumberFormat.Number(animal.maxHealth)), session.owner.UserId, "Public")
				Scene.SetHealthTone(primary, true)
			end
		end
	end
	NetMsg.FireNotifyFarmFeedback(session.owner, if cooked > 0 then Texts.Farm.DamageCooked.source:format(total, cooked) else Texts.Farm.Damage.source:format(total))
end

local function ClearConfirmation(session: Session): ()
	session.confirmation = nil
	session.owner:SetAttribute("FarmConfirmId", nil)
	session.owner:SetAttribute("FarmConfirmMessage", nil)
	session.owner:SetAttribute("FarmConfirmRisk", nil)
end
local function ApplySpecies(session: Session, speciesId: string, now: number): ()
	local species = Config.GetSpecies(speciesId)
	if not species then return end
	local cashBefore = session.farm.cash
	local unlocked = Business.TryUnlockSpecies(session.farm, speciesId)
	if not unlocked then return end
	GetMetrics(session).spent += cashBefore - session.farm.cash
	for _, egg in session.eggs do egg.model:Destroy() end
	for _, animal in session.animals do animal.model:Destroy() end
	table.clear(session.eggs)
	table.clear(session.animals)
	Business.SelectSpecies(session.farm, speciesId)
	session.nextEggAt = now + species.interval
	MarkChanged(session)
	Project(session)
end
local function RequestSpecies(session: Session, speciesId: string, now: number): ()
	local species = Config.GetSpecies(speciesId)
	if not species or speciesId == session.farm.selectedSpeciesId then return end
	local prevSpecies = Config.Species[species.tier - 1]
	local prevKey = (prevSpecies :: any).key or (prevSpecies :: any).speciesId or tostring(prevSpecies.id)
	if species.tier > 1 and not session.farm.unlockedSpecies[prevKey] then return end
	local price = if session.farm.unlockedSpecies[speciesId] then 0 else species.unlockPrice
	if session.farm.cash < price then NetMsg.FireNotifyFarmFeedback(session.owner, Texts.Farm.PersonalNeedCoins.source:format(NumberFormat.Number(price - session.farm.cash))); return end
	local hasEntities = #session.eggs > 0 or next(session.animals) ~= nil
	if not hasEntities and price == 0 then ClearConfirmation(session); ApplySpecies(session, speciesId, now); return end
	local normalShots, goldenShots, fits = Business.GetSpeciesRisk(session.farm, speciesId)
	local confirmation: Confirmation = { id = HttpService:GenerateGUID(false), kind = "species", speciesId = speciesId, previousSpeciesId = session.farm.selectedSpeciesId, expiresAt = now + ConfirmationSeconds }
	session.confirmation = confirmation
	session.owner:SetAttribute("FarmConfirmMessage", Texts.Farm.SpeciesConfirm.source:format(species.name, NumberFormat.Number(price)))
	session.owner:SetAttribute("FarmConfirmRisk", Texts.Farm.SpeciesRisk.source:format(normalShots, goldenShots, fits))
	session.owner:SetAttribute("FarmConfirmId", confirmation.id)
end
local function ConfirmSpecies(session: Session, confirmationId: string, now: number): ()
	local confirmation = session.confirmation
	if not confirmation or confirmation.id ~= confirmationId then return end
	if confirmation.expiresAt < now then ClearConfirmation(session); return end
	if confirmation.kind == "hatch" then
		local egg = if confirmation.targetId then FindEgg(session, confirmation.targetId, now) else nil
		ClearConfirmation(session)
		local species = if egg then Config.GetSpecies(egg.speciesId) else nil
		if egg and species then HatchEgg(session, egg, now, species.instantHatchPrice); Project(session) end
		return
	end
	local speciesId = confirmation.speciesId
	if not speciesId or confirmation.previousSpeciesId ~= session.farm.selectedSpeciesId then ClearConfirmation(session); return end
	local species = Config.GetSpecies(speciesId)
	if not species then ClearConfirmation(session); return end
	local price = if session.farm.unlockedSpecies[speciesId] then 0 else species.unlockPrice
	if session.farm.cash < price then
		ClearConfirmation(session)
		NetMsg.FireNotifyFarmFeedback(session.owner, Texts.Farm.PersonalNeedCoins.source:format(NumberFormat.Number(price - session.farm.cash)))
		return
	end
	ClearConfirmation(session)
	ApplySpecies(session, speciesId, now)
end
local function RequestInstantHatch(session: Session, targetId: string, now: number): ()
	local egg = FindEgg(session, targetId, now)
	local species = if egg then Config.GetSpecies(egg.speciesId) else nil
	if not egg or not species then return end
	if session.farm.cash < species.instantHatchPrice then NetMsg.FireNotifyFarmFeedback(session.owner, Texts.Farm.PersonalNeedCoins.source:format(NumberFormat.Number(species.instantHatchPrice - session.farm.cash))); return end
	local confirmation: Confirmation = { id = HttpService:GenerateGUID(false), kind = "hatch", targetId = egg.id, expiresAt = now + ConfirmationSeconds, entityIds = {} }
	session.confirmation = confirmation
	session.owner:SetAttribute("FarmConfirmMessage", Texts.Farm.InstantHatchConfirm.source:format(species.name, egg.qualityId, species.instantHatchPrice))
	session.owner:SetAttribute("FarmConfirmRisk", "")
	session.owner:SetAttribute("FarmConfirmId", confirmation.id)
end
local function Collect(session: Session, root: BasePart): ()
	local tool = Config.Collectors[session.farm.collectTier]
	local direction = Scene.FlatVector(root.CFrame.LookVector)
	local targets: { { id: string, distance: number } } = {}
	for id, ground in session.ground do
		local offset = ground.pos - root.Position
		local horizontal = Scene.FlatVector(offset)
		local facing = tool.angleDegrees == 360 or horizontal.Magnitude < 0.01 or direction:Dot(horizontal.Unit) >= math.cos(math.rad(tool.angleDegrees / 2))
		local distance = offset.Magnitude
		if distance <= tool.range and facing then table.insert(targets, { id = id, distance = distance }) end
	end
	table.sort(targets, function(a, b) return a.distance < b.distance end)
	local target = targets[1]
	if not target then NetMsg.FireNotifyFarmFeedback(session.owner, Texts.Farm.CollectHint.source); return end
	local count = 0
	local failure: string?
	local remainingBlocked = false
	for _, candidate in targets do
		local ground = session.ground[candidate.id]
		if os.clock() >= ground.expiresAt then continue end
		local collected, reason = Business.TryCollect(session.farm, ground.cargo)
		if collected then
			session.ground[candidate.id] = nil
			ground.model:Destroy()
			count += 1
			if count >= tool.maximumItems then break end
		else
			failure = reason
			if reason == "remainingCapacity" then remainingBlocked = true end
		end
	end
	if count > 0 then
		GetMetrics(session).collected += count
		MarkChanged(session)
		Project(session)
		NetMsg.FireNotifyFarmFeedback(session.owner, Texts.Farm.Collected.source:format(count))
	else
		NetMsg.FireNotifyFarmFeedback(session.owner, if remainingBlocked then Texts.Farm.RemainingCapacity.source elseif failure == "itemTooHeavy" then Texts.Farm.ItemTooHeavy.source else Texts.Farm.CollectHint.source)
	end
end

function Manager.new(): ServerPersonalFarmManager
	return setmetatable({ sessions = {}, reservations = {}, waiting = {}, running = false }, Manager)
end
function Manager.GetActive(): ServerPersonalFarmManager?
	return activeManager
end
function Manager.SetMeasurementSequence(self: ServerPersonalFarmManager, player: Player, seed: number, sequence: { string }?): boolean
	-- 仅本地 Studio 运行验证开放，不接入 Remote，正式服务器始终拒绝指定品质。
	if not RunService:IsStudio() or seed ~= seed or seed % 1 ~= 0 or seed < 0 or seed > 2147483647 then return false end
	local session = self.sessions[player]
	if not session or session.frozen then return false end
	local validated: { string } = {}
	if sequence then
		if #sequence > 1000 then return false end
		for _, qualityId in sequence do if not Config.GetQuality(qualityId) then return false end; table.insert(validated, qualityId) end
	end
	session.rng = Random.new(seed)
	session.testQualitySequence = if #validated > 0 then validated else nil
	session.testQualityIndex = 1
	return true
end
function Manager.OnPlayerLoaded(self: ServerPersonalFarmManager, player: Player): ()
	if not self.running or self.sessions[player] or not player.Parent then return end
	local profile = ServerGameInfo.GetPlayerInfo(player)
	if not profile then return end
	player:SetAttribute("FarmStage", 2)
	local plots = workspace:WaitForChild("FarmPlots")
	local farms = self.runtime
	assert(farms, "Farm village must be initialized before player loading")
	local plot, map = Village.FindAvailable(plots, farms, self.reservations)
	if not plot or not map then
		self.waiting[player] = true
		player:SetAttribute("FarmReady", false)
		NetMsg.FireNotifyFarmFeedback(player, Texts.Farm.PlotWaiting.source)
		return
	end
	assert(Village.Claim(map, plot, player, self.reservations), "Farm plot claim failed")
	self.waiting[player] = nil
	local species = Config.GetSpecies(profile.farm.selectedSpeciesId)
	assert(species)
	local session: Session = { owner = player, plot = plot, map = map, scope = Lifecycle.new(), farm = profile.farm, eggs = {}, animals = {}, ground = {}, nextEggAt = os.clock() + species.interval, cooldowns = {}, frozen = false, rng = Random.new(), lastUpdateAt = os.clock() }
	self.sessions[player] = session
	local function OnCharacterAdded(character: Model): () PositionCharacter(session, character) end
	session.scope:Connect(player.CharacterAdded:Connect(OnCharacterAdded))
	if player.Character then PositionCharacter(session, player.Character) end
	player:SetAttribute("FarmPlotId", plot.Name)
	Project(session)
end
function Manager.FreezePlayer(self: ServerPersonalFarmManager, player: Player): ()
	self.waiting[player] = nil
	local session = self.sessions[player]
	if session then session.frozen = true; ClearConfirmation(session); Project(session) end
end
function Manager.RemovePlayer(self: ServerPersonalFarmManager, player: Player): ()
	self:FreezePlayer(player)
	local session = self.sessions[player]
	if session then
		session.scope:Destroy()
		Village.Release(session.map, session.plot, player, self.reservations)
		player:SetAttribute("FarmPlotId", nil)
		player:SetAttribute("FarmReady", false)
		self.sessions[player] = nil
		local character = player.Character
		local basket = if character then character:FindFirstChild("ChickenBasket") else nil
		if basket then basket:Destroy() end
		local weapon = if character then character:FindFirstChild("FarmWeapon") else nil
		if weapon then weapon:Destroy() end
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack then
			local bpWeapon = backpack:FindFirstChild("FarmWeapon")
			if bpWeapon then bpWeapon:Destroy() end
		end
	end
	if self.running then for waitingPlayer in self.waiting do self:OnPlayerLoaded(waitingPlayer) end end
end
function Manager.OnAction(self: ServerPersonalFarmManager, player: Player, action: string, aim: Vector3?, expectedStep: number?): ()
	local session = self.sessions[player]
	if not session or session.frozen or not self.running or not ServerGameInfo.GetPlayerInfo(player) then return end
	local now = os.clock()
	if Business.GetPurchasePrice(session.farm, action) then
		if now < (session.cooldowns.purchase or 0) then return end
		session.cooldowns.purchase = now + Config.CollectCooldownSeconds
		local cashBefore = session.farm.cash
		local purchased, reason = Business.TryPurchase(session.farm, action, expectedStep)
		if purchased then
			local metrics = GetMetrics(session)
			metrics.spent += cashBefore - session.farm.cash
			if action == "enhanceWeapon" and metrics.firstEnhancementSeconds < 0 then metrics.firstEnhancementSeconds = now - metrics.startedAt end
			if action == "buyRestaurant" then Business.TickKitchen(session.farm, 0) end
			MarkChanged(session); Project(session)
		elseif reason == "insufficientCash" then
			local price = Business.GetPurchasePrice(session.farm, action)
			if price then NetMsg.FireNotifyFarmFeedback(player, Texts.Farm.PersonalNeedCoins.source:format(NumberFormat.Number(price - session.farm.cash))) end
		elseif reason == "stateChanged" then NetMsg.FireNotifyFarmFeedback(player, Texts.Farm.ConfirmationExpired.source)
		end
		return
	end
	if action ~= "zap" and action ~= "collect" then return end
	local root = Scene.GetPlayerRoot(player)
	if not root then return end
	if now < (session.cooldowns[action] or 0) then return end
	session.cooldowns[action] = now + (if action == "zap" then Config.ZapCooldownSeconds else Config.CollectCooldownSeconds)
	if action == "zap" then Zap(session, root, aim) else Collect(session, root) end
end
function Manager.OnCommand(self: ServerPersonalFarmManager, player: Player, command: FarmRequest.Request): ()
	local session = self.sessions[player]
	if not self.running or not session or session.frozen or not ServerGameInfo.GetPlayerInfo(player) then return end
	local now = os.clock()
	if Business.GetPurchaseStep(session.farm, command.action) and command.expectedStep == nil then return end
	if command.action == "selectSpecies" and command.speciesId then
		if now < (session.cooldowns.selectSpecies or 0) then return end
		session.cooldowns.selectSpecies = now + Config.CollectCooldownSeconds
		RequestSpecies(session, command.speciesId, now)
	elseif command.action == "confirm" and command.confirmationId then
		ConfirmSpecies(session, command.confirmationId, now)
	elseif command.action == "cancel" and session.confirmation and session.confirmation.id == command.confirmationId then
		ClearConfirmation(session)
	elseif command.action == "equipWeapon" and command.tier then
		if Business.TryEquipWeapon(session.farm, command.tier) then MarkChanged(session); Project(session) end
	elseif command.action == "accelerateEgg" and command.targetId then
		local egg = FindEgg(session, command.targetId, now)
		if egg then
			local accelerated, nextAllowed = HatchRules.Accelerate(egg, now, session.cooldowns.accelerateEgg or 0)
			if accelerated then
				session.cooldowns.accelerateEgg = nextAllowed
				egg.model:SetAttribute("HatchEndTime", workspace:GetServerTimeNow() + math.max(0, egg.finish - now))
				local sequence = egg.model:GetAttribute("HatchAccelerationSequence")
				egg.model:SetAttribute("HatchAccelerationSequence", (if typeof(sequence) == "number" then sequence else 0) + 1)
				if egg.finish <= now then HatchEgg(session, egg, now) end
				Project(session)
			end
		end
	elseif command.action == "requestInstantHatch" and command.targetId then
		if now < (session.cooldowns.hatchPrompt or 0) then return end
		session.cooldowns.hatchPrompt = now + Config.CollectCooldownSeconds
		RequestInstantHatch(session, command.targetId, now)
	else
		local aim = command.aim
		self:OnAction(player, command.action, if aim then Vector3.new(aim.x, aim.y, aim.z) else nil, command.expectedStep)
	end
end
function Manager.Update(self: ServerPersonalFarmManager, now: number, dt: number): ()
	for _, session in self.sessions do
		if session.frozen then continue end
		local activeDelta = math.min(dt, math.max(0, now - (session.lastUpdateAt or now - dt)))
		session.lastUpdateAt = now
		if session.confirmation and now > session.confirmation.expiresAt then ClearConfirmation(session) end
		local metrics = GetMetrics(session)
		local waiting, processing = Business.GetKitchenCounts(session.farm)
		metrics.waitingItemSeconds += waiting * activeDelta
		metrics.processingItemSeconds += processing * activeDelta
		UpdateProduction(session, now, activeDelta)
		local confirmation = session.confirmation
		if confirmation and confirmation.kind == "hatch" and (not confirmation.targetId or not FindEgg(session, confirmation.targetId, now)) then ClearConfirmation(session) end
		UpdateAnimals(session, now, math.min(activeDelta, MaximumDelta))
		UpdateInventory(session, now, activeDelta)
		local revision = session.farm.revision
		local sold, income = Business.TickKitchen(session.farm, activeDelta)
		metrics.sold += sold
		metrics.salesIncome += income
		if sold > 0 and metrics.firstSaleSeconds < 0 then metrics.firstSaleSeconds = os.clock() - metrics.startedAt end
		if session.farm.cash >= Config.Weapons[1].enhancementPrices[1] and metrics.firstAffordEnhancementSeconds < 0 then metrics.firstAffordEnhancementSeconds = os.clock() - metrics.startedAt end
		if session.farm.revision ~= revision then MarkChanged(session) end
		if sold > 0 then
			FarmSoundTool.Play("PackageDone", session.plot.Position)
			NetMsg.FireNotifyFarmFeedback(session.owner, Texts.Farm.PersonalSold.source:format(sold, NumberFormat.Number(income)), "sale")
		end
		Project(session)
	end
end
function Manager.Init(self: ServerPersonalFarmManager): ()
	if self.running then return end
	local scope = Lifecycle.new()
	self.scope, self.running = scope, true
	activeManager = self
	local legacy = workspace:FindFirstChild("RoastChickenFarm")
	if legacy and legacy:IsA("Folder") then self.legacy = legacy; legacy.Parent = ServerStorage end
	local farms = workspace:WaitForChild("PersonalFarms")
	assert(farms:IsA("Folder"), "PersonalFarms must be a prebuilt Folder")
	Village.Validate(workspace:WaitForChild("FarmPlots"), farms)
	self.runtime = farms
	for _, map in farms:GetChildren() do if map:IsA("Folder") then Village.Reset(map) end end
	local function OnAction(player: Player, action: string): ()
		if action == "zap" or action == "collect" then self:OnAction(player, action) end
	end
	local function OnCommand(player: Player, command: FarmRequest.Request): () self:OnCommand(player, command) end
	scope:Connect(NetMsg.ConnectRequestFarmAction(OnAction))
	scope:Connect(NetMsg.ConnectRequestFarmCommand(OnCommand))
	scope:Spawn(function()
		while self.running do
			local elapsed = task.wait(UpdateSeconds)
			if self.running then self:Update(os.clock(), elapsed) end
		end
	end)
	for _, player in Players:GetPlayers() do self:OnPlayerLoaded(player) end
end
function Manager.Destroy(self: ServerPersonalFarmManager): ()
	if activeManager == self then activeManager = nil end
	self.running = false
	table.clear(self.waiting)
	for player in self.sessions do self:RemovePlayer(player) end
	if self.scope then self.scope:Destroy(); self.scope = nil end
	self.runtime = nil
	if self.legacy then self.legacy.Parent = workspace; self.legacy = nil end
end
return Manager
