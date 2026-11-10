-- 动物子系统：负责生成、生命值、游荡与击倒产物
--!strict
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local replicatedStorage = game:GetService("ReplicatedStorage")
local sharedScripts = replicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local catalog = require(sharedScripts:WaitForChild("RoastChickenCatalog"))
local FarmConfig = require(sharedScripts:WaitForChild("FarmConfig"))
local ServerFarmTypes = require(script.Parent.Parent:WaitForChild("ServerFarmTypes"))
type FarmContext = ServerFarmTypes.FarmContext
type AnimalData = ServerFarmTypes.AnimalInfo

local ServerFarmSceneTool = require(script.Parent:WaitForChild("ServerFarmSceneTool"))
local ServerCreatureBuilder = require(script.Parent:WaitForChild("ServerCreatureBuilder"))
local ServerAnimalManager = {}
function ServerAnimalManager.SetAnimalHealth(self: FarmContext, model: Model, animal: AnimalData, health: number): ()
	animal.health = health
	model:SetAttribute("Health", health)
	local part = model.PrimaryPart
	assert(part, "Animal model needs PrimaryPart")
	ServerFarmSceneTool.SetSignText(part, ("%d / %d"):format(health, animal.maxHealth))
	ServerFarmSceneTool.SetHealthTone(part, health < animal.maxHealth)
end

function ServerAnimalManager.SpawnAnimal(self: FarmContext, center: Vector3, variant: number): ()
	local angle = self.rng:NextNumber(0, 2 * math.pi)
	local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local pos = center
	local model = ServerCreatureBuilder.Build(variant, false, ServerFarmSceneTool.CreatePiece)
	model:SetAttribute("Species", catalog.creatures[variant].name)
	model:PivotTo(CFrame.lookAt(pos + Vector3.yAxis, pos + Vector3.yAxis + dir))

	local maxHealth = catalog.creatures[variant].health
	ServerFarmSceneTool.CreateAnimalHealthLabel(self, model)
	local animal: AnimalData = {
		center = center,
		pos = pos,
		dir = dir,
		turn = 0,
		phase = angle,
		variant = variant,
		maxHealth = maxHealth,
		health = maxHealth,
	}
	model:SetAttribute("MaxHealth", maxHealth)
	ServerAnimalManager.SetAnimalHealth(self, model, animal, maxHealth)
	self.info.flock[model] = animal
	model.Parent = self.liveFolder
end

function ServerAnimalManager.CookAnimal(self: FarmContext, model: Model, animal: AnimalData): ()
	self.info.flock[model] = nil
	model:Destroy()

	local roast = ServerCreatureBuilder.Build(animal.variant, true, ServerFarmSceneTool.CreatePiece)
	roast:SetAttribute("Species", catalog.creatures[animal.variant].name)
	local pos = animal.pos + Vector3.new(0, 0.53, 0)
	roast:PivotTo(CFrame.new(pos))
	self.info.roasts[roast] = { pos = pos, variant = animal.variant, expiresAt = os.clock() + FarmConfig.RoastLifetime }
	roast.Parent = self.roastFolder

	for _ = 1, 5 do
		local p = ServerFarmSceneTool.CreatePiece(self.map, "Puff", Vector3.one * 0.62, CFrame.new(pos), "FFF6DF", true)
		self.scope:Own(p)
		self.scope:Play(TweenService:Create(p, TweenInfo.new(0.42), {
			Transparency = 1,
			Size = Vector3.one * 1.05,
			Position = pos + Vector3.new(self.rng:NextNumber(-1.4, 1.4), self.rng:NextNumber(0.8, 1.7), self.rng:NextNumber(-1.4, 1.4)),
		}))
		Debris:AddItem(p, 0.45)
	end
end
function ServerAnimalManager.Update(self: FarmContext, now: number, dt: number, roots: { BasePart }): ()
	for model, data in pairs(self.info.flock) do
		local speed = FarmConfig.AnimalWalkSpeed
		if now >= data.turn then
			data.turn = now + self.rng:NextNumber(FarmConfig.AnimalTurnMinimumInterval, FarmConfig.AnimalTurnMaximumInterval)
			local angle = self.rng:NextNumber(0, 2 * math.pi)
			data.dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		end

		local dir = data.dir
		local offset = data.center - data.pos
		if offset.Magnitude > FarmConfig.AnimalRoamRadius then
			dir = offset.Unit
		else
			for _, root in ipairs(roots) do
				local away = data.pos - ServerFarmSceneTool.FlatVector(root.Position)
				if away.Magnitude < FarmConfig.AnimalFleeRange and away.Magnitude > 0.01 then
					dir = away.Unit
					speed = FarmConfig.AnimalFleeSpeed
					break
				end
			end
		end

		data.pos += dir * speed * dt
		local height = FarmConfig.AnimalHeights[data.variant]
		local pos = data.pos + Vector3.yAxis * (height + math.abs(math.sin(now * speed * 2 + data.phase)) * 0.23)
		model:PivotTo(CFrame.lookAt(pos, pos + dir))
	end
end
return ServerAnimalManager
