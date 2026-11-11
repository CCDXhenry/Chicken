-- 个人农场场景回归：仅在获授权的双人 Play 服务端执行，使用独立经营档与远端临时地块
--!strict
local RunService = game:GetService("RunService")
assert(RunService:IsRunning() and RunService:IsServer(), "Run in an authorized Play server")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local Save = require(Shared:WaitForChild("FarmSaveData"))
local Config = require(Shared:WaitForChild("FarmEconomyConfig"))
local Business = require(Shared:WaitForChild("FarmBusiness"))
local Lifecycle = require(Shared:WaitForChild("LifecycleTool"))
local GameInfo = require(ServerStorage:WaitForChild("Scripts"):WaitForChild("ServerGameInfo"))
local Manager = require(ServerStorage:WaitForChild("Scripts"):WaitForChild("ServerPersonalFarmManager"))
local playerList = Players:GetPlayers()
assert(#playerList >= 2, "Two loaded players are required")
local manager = Manager.new()
manager.running = true
local scopes: { Lifecycle.Lifecycle } = {}
local originalPivots: { [Model]: CFrame } = {}
local originalAnchored: { [BasePart]: boolean } = {}
local checks: { string } = {}
local function CreateFixture(player: Player, x: number): Manager.Session
	assert(GameInfo.GetPlayerInfo(player), "Wait for real profile loading to finish")
	local map = ServerStorage.Models.PersonalFarmTemplate:Clone()
	map.Name = "PersonalFarmRegression_" .. tostring(player.UserId)
	local scope = Lifecycle.new()
	table.insert(scopes, scope)
	local plot = Instance.new("Part")
	plot.Name, plot.CFrame = map.Name, CFrame.new(x, 0, 10000)
	scope:Own(plot)
	for _, object in map:GetDescendants() do
		if object:IsA("BasePart") then object.CFrame = plot.CFrame * object.CFrame end
	end
	map.Parent = workspace
	scope:Own(map)
	local session: Manager.Session = { owner = player, plot = plot, map = map, scope = scope, farm = Save.CreateDefault(), eggs = {}, animals = {}, ground = {}, nextEggAt = 0, cooldowns = {}, frozen = false, rng = Random.new(17) }
	manager.sessions[player], manager.reservations[plot] = session, player
	local character = player.Character
	assert(character, "Player character required")
	local root = character:FindFirstChild("HumanoidRootPart")
	assert(root and root:IsA("BasePart"), "HumanoidRootPart required")
	originalPivots[character], originalAnchored[root] = character:GetPivot(), root.Anchored
	root.Anchored = true
	return session
end
local function CountPopulation(session: Manager.Session): number
	local count = #session.eggs
	for _ in session.animals do count += 1 end
	return count
end
local function SelectedSpecies(session: Manager.Session): string
	return session.farm.selectedSpeciesId
end
local function Root(player: Player): BasePart
	local character = player.Character
	assert(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	assert(root and root:IsA("BasePart"))
	return root
end
local function Drop(session: Manager.Session, id: string, species: string, quality: string, position: Vector3): ()
	local model = Instance.new("Model")
	model.Name, model.Parent = id, session.map
	session.ground[id] = { model = model, pos = position, cargo = Business.CreateCargo(id, species, quality), expiresAt = os.clock() + 75 }
end
local function ForceHatch(session: Manager.Session, species: string, quality: string, position: Vector3): string
	session.nextEggAt = 0
	local now = os.clock()
	manager:Update(now, 0)
	local egg = session.eggs[#session.eggs]
	assert(egg)
	egg.speciesId, egg.qualityId, egg.landing = species, quality, position
	egg.landAt, egg.finish = now - 1, now
	manager:Update(now + 0.001, 0)
	return egg.id
end
local success, failure = xpcall(function(): boolean
	local first = CreateFixture(playerList[1], 10000)
	local second = CreateFixture(playerList[2], 10128)
	manager:Update(0, 0)
	assert(#first.eggs == 1 and #second.eggs == 1 and first.eggs[1].id ~= second.eggs[1].id)
	assert(first.eggs[1].model:GetAttribute("OwnerUserId") == first.owner.UserId)
	assert(second.eggs[1].model:GetAttribute("OwnerUserId") == second.owner.UserId)
	table.insert(checks, "Independent production and entity ownership")
	for i = 1, 35 do manager:Update(i * Config.Species[1].interval, 0) end
	assert(CountPopulation(first) == 28 and CountPopulation(second) == 28)
	table.insert(checks, "Independent 28 entity caps")
	local _, foreignAnimal = next(second.animals)
	assert(foreignAnimal)
	local root1, root2 = Root(first.owner), Root(second.owner)
	root1.CFrame = CFrame.lookAt(foreignAnimal.pos + Vector3.new(0, 2, 4), foreignAnimal.pos + Vector3.yAxis * 2)
	manager:OnAction(first.owner, "zap")
	assert(CountPopulation(second) == 28 and next(second.ground) == nil)
	first.cooldowns.zap = 0
	local animal = nil
	for _, candidate in first.animals do if candidate.qualityId == "normal" then animal = candidate; break end end
	assert(animal)
	root1.CFrame = CFrame.lookAt(animal.pos + Vector3.new(0, 2, 4), animal.pos + Vector3.yAxis * 2)
	manager:OnAction(first.owner, "zap")
	local id, ground = next(first.ground)
	assert(id and ground and ground.cargo.saleValue == 10 and ground.cargo.weightKg == 1)
	root2.CFrame = CFrame.new(ground.pos + Vector3.yAxis * 2)
	manager:OnAction(second.owner, "collect")
	assert(#second.farm.basket == 0 and first.ground[id] ~= nil)
	manager:OnAction(first.owner, "collect")
	assert(#first.farm.basket == 1 and first.farm.basket[1].itemId == id and first.ground[id] == nil)
	table.insert(checks, "Foreign combat and pickup rejected; owned cargo keeps identity")
	local sell = first.map:FindFirstChild("Sell")
	assert(sell and sell:IsA("BasePart"))
	root1.CFrame = sell.CFrame + Vector3.yAxis * 2
	manager:Update(200, 0)
	assert(#first.farm.basket == 1 and #first.farm.kitchen == 0)
	manager:Update(200 + Config.UnloadIntervalSeconds - 0.001, 0)
	assert(#first.farm.basket == 1)
	manager:Update(200 + Config.UnloadIntervalSeconds + 0.001, 0)
	assert(#first.farm.basket == 0 and #first.farm.kitchen == 1 and first.farm.kitchen[1].cargo.itemId == id)
	manager:Update(202, Config.Species[1].packSeconds)
	assert(first.farm.cash == 10 and second.farm.cash == 0 and #first.farm.kitchen == 0)
	manager:Update(204, Config.Species[1].packSeconds)
	assert(first.farm.cash == 10)
	table.insert(checks, "First unload waits 0.15 seconds; first sale 10; repeated settlement rejected")
	-- 后续阶段继续使用同一隔离夹具；不改真实 profile.farm，不直接调用存档服务。
	first.farm.cash = 300
	Business.TryCollect(first.farm, Business.CreateCargo("keep-basket", "chicken", "normal"))
	Drop(first, "keep-ground", "chicken", "normal", first.plot.Position + Vector3.new(0, 0, 50))
	local beforeCount = CountPopulation(first)
	manager:OnCommand(first.owner, { action = "selectSpecies", speciesId = "rabbit" })
	local prompt = first.confirmation
	assert(prompt and first.farm.cash == 300 and SelectedSpecies(first) == "chicken")
	manager:OnCommand(first.owner, { action = "cancel", confirmationId = prompt.id })
	assert(CountPopulation(first) == beforeCount and first.farm.cash == 300)
	first.cooldowns.selectSpecies = 0
	manager:OnCommand(first.owner, { action = "selectSpecies", speciesId = "rabbit" })
	prompt = first.confirmation
	assert(prompt)
	manager:OnCommand(first.owner, { action = "confirm", confirmationId = "wrong-token" })
	assert(first.farm.cash == 300)
	manager:OnCommand(first.owner, { action = "confirm", confirmationId = prompt.id })
	assert(CountPopulation(first) == 0 and first.farm.cash == 0 and SelectedSpecies(first) == "rabbit")
	assert(#first.farm.basket == 1 and first.ground["keep-ground"] ~= nil)
	manager:OnCommand(first.owner, { action = "confirm", confirmationId = prompt.id })
	assert(first.farm.cash == 0)
	first.cooldowns.selectSpecies = 0
	local switchAt = os.clock()
	manager:OnCommand(first.owner, { action = "selectSpecies", speciesId = "chicken" })
	assert(SelectedSpecies(first) == "chicken" and first.farm.cash == 0 and first.nextEggAt >= switchAt + Config.Species[1].interval)
	table.insert(checks, "Species confirmation cancel/replay safety; clear preserves ground and basket; free T1 recovery waits full interval")
	first.cooldowns.selectSpecies = 0
	manager:OnCommand(first.owner, { action = "selectSpecies", speciesId = "rabbit" })
	first.nextEggAt = 0
	manager:Update(os.clock(), 0)
	local goldenEgg = first.eggs[1]
	assert(goldenEgg)
	goldenEgg.speciesId, goldenEgg.qualityId = "rabbit", "golden"
	goldenEgg.landAt, goldenEgg.finish = os.clock() - 1, os.clock() + 100
	root1.CFrame = CFrame.new(goldenEgg.landing + Vector3.yAxis * 2)
	first.farm.cash = 25
	manager:OnCommand(first.owner, { action = "requestInstantHatch", targetId = goldenEgg.id })
	prompt = first.confirmation
	assert(prompt and prompt.kind == "hatch")
	local oldFinish = goldenEgg.finish
	manager:OnCommand(first.owner, { action = "accelerateEgg", targetId = goldenEgg.id })
	local acceleratedFinish = goldenEgg.finish
	manager:OnCommand(first.owner, { action = "accelerateEgg", targetId = goldenEgg.id })
	assert(acceleratedFinish == oldFinish - 1 and goldenEgg.finish == acceleratedFinish)
	manager:OnCommand(second.owner, { action = "requestInstantHatch", targetId = goldenEgg.id })
	assert(not second.confirmation and second.farm.cash == 0)
	manager:OnCommand(first.owner, { action = "confirm", confirmationId = prompt.id })
	local goldenAnimal = first.animals[goldenEgg.id]
	assert(goldenAnimal and goldenAnimal.health == 12 and goldenAnimal.qualityId == "golden" and first.farm.cash == 0)
	manager:OnCommand(first.owner, { action = "confirm", confirmationId = prompt.id })
	assert(first.farm.cash == 0 and CountPopulation(first) == 1)
	table.insert(checks, "Owned landed golden rabbit: free acceleration cooldown, foreign request rejection and exactly one 25 coin instant hatch")
	goldenAnimal.model:Destroy()
	table.clear(first.animals)
	first.farm.cash = 650
	for _, action in { "buyZap", "enhanceWeapon", "enhanceWeapon" } do
		first.cooldowns.purchase = 0
		manager:OnCommand(first.owner, { action = action, expectedStep = Business.GetPurchaseStep(first.farm, action) })
	end
	assert(first.farm.weaponLevels["2"] == 3 and first.farm.cash == 0)
	local firstRabbitId = ForceHatch(first, "rabbit", "normal", first.plot.Position + Vector3.new(0, 0, 4))
	local secondRabbitId = ForceHatch(first, "rabbit", "normal", first.plot.Position + Vector3.new(0, 0, 8))
	root1.CFrame = CFrame.lookAt(first.plot.Position + Vector3.yAxis * 2, first.plot.Position + Vector3.new(0, 2, 1))
	first.cooldowns.zap = 0
	manager:OnAction(first.owner, "zap")
	assert(not first.animals[firstRabbitId] and not first.animals[secondRabbitId])
	assert(first.ground[firstRabbitId].cargo.weightKg == 3 and first.ground[secondRabbitId].cargo.saleValue == 50)
	first.farm.cash, first.cooldowns.purchase = 110, 0
	manager:OnCommand(first.owner, { action = "buyCollect", expectedStep = Business.GetPurchaseStep(first.farm, "buyCollect") })
	Drop(first, "overweight-cow", "cow", "normal", first.plot.Position + Vector3.new(0, 0, 2))
	first.cooldowns.collect = 0
	manager:OnAction(first.owner, "collect")
	assert(first.ground["overweight-cow"] ~= nil and #first.farm.basket == 3 and Business.GetWeight(first.farm) == 7)
	table.insert(checks, "Actual T2 Lv3 chain kills 6+6; directional collector skips 27 kg item and collects both valid rabbits")
	manager:FreezePlayer(first.owner)
	local count, cash = CountPopulation(first), first.farm.cash
	manager:Update(300, 1)
	manager:OnAction(first.owner, "zap")
	assert(CountPopulation(first) == count and first.farm.cash == cash)
	manager:RemovePlayer(first.owner)
	assert(not manager.reservations[first.plot] and first.map.Parent == nil)
	table.insert(checks, "Freeze blocks operations; release destroys owned map and frees plot")
	return true
end, debug.traceback)
manager.running = false
for _, scope in scopes do scope:Destroy() end
for character, pivot in originalPivots do if character.Parent then character:PivotTo(pivot) end end
for root, anchored in originalAnchored do if root.Parent then root.Anchored = anchored end end
assert(success, failure)
return checks
