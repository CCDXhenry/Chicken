-- 产蛋孵化子系统：负责产能上限、抛蛋轨迹、倒计时和孵化
--!strict
local replicatedStorage = game:GetService("ReplicatedStorage")
local sharedScripts = replicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local catalog = require(sharedScripts:WaitForChild("RoastChickenCatalog"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local FarmConfig = require(sharedScripts:WaitForChild("FarmConfig"))
local ServerFarmTypes = require(script.Parent.Parent:WaitForChild("ServerFarmTypes"))
type FarmContext = ServerFarmTypes.FarmContext
type EggData = ServerFarmTypes.EggInfo

local ServerFarmSceneTool = require(script.Parent:WaitForChild("ServerFarmSceneTool"))
local ServerAnimalManager = require(script.Parent:WaitForChild("ServerAnimalManager"))
local ServerEggManager = {}
function ServerEggManager.MakeEgg(self: FarmContext, now: number, variant: number): EggData
	local info = catalog.creatures[variant]
	local landing = Vector3.new(
		self.rng:NextNumber(FarmConfig.EggLandingXMinimum, FarmConfig.EggLandingXMaximum),
		0,
		self.rng:NextNumber(FarmConfig.EggLandingZMinimum, FarmConfig.EggLandingZMaximum)
	)
	local chutePart = self.map.Nest:WaitForChild("Chute") :: BasePart
	local origin = chutePart.Position
	local size = 1.22 + variant * 0.13

	local egg = Instance.new("Model")
	egg.Name = "Egg" .. variant
	egg:SetAttribute("Species", info.name)
	local shell = ServerFarmSceneTool.CreatePiece(egg, "Shell", Vector3.new(size, size * 1.28, size), CFrame.new(0, 0, 0), info.shell, true)
	egg.PrimaryPart = shell

	for i = 1, 5 do
		local angle = i * math.pi * 2 / 5
		local x, z = math.cos(angle), math.sin(angle)
		local spot = CFrame.lookAt(Vector3.new(x * size * 0.46, 0.07 + 0.15 * (i % 2), z * size * 0.46), Vector3.new(x, 0.07 + 0.15 * (i % 2), z))
		ServerFarmSceneTool.CreatePiece(egg, "ShellSpot", Vector3.new(size * 0.3, size * 0.25, size * 0.1), spot, info.spot, true)
	end

	shell:SetAttribute("FarmStudsOffsetY", size * 0.82 + 0.35)

	egg:PivotTo(CFrame.new(origin))
	egg.Parent = self.eggFolder

	return {
		model = egg,
		origin = origin,
		landing = landing,
		variant = variant,
		started = now,
		landAt = now + FarmConfig.EggFlightDuration,
		finish = now + FarmConfig.EggFlightDuration + info.hatch,
		height = size * 0.64,
	}
end
function ServerEggManager.UpdateEggs(self: FarmContext, now: number): ()
	local population = #self.info.eggs
	for _ in pairs(self.info.flock) do
		population += 1
	end
	local info = catalog.creatures[self.info.nestLevel]
	if population < FarmConfig.PopulationCapacity and now >= self.info.nextEggTime then
		table.insert(self.info.eggs, ServerEggManager.MakeEgg(self, now, self.info.nestLevel))
		self.info.nextEggTime = now + info.interval
	end

	local nestText = if population >= FarmConfig.PopulationCapacity
		then GameTexts.Farm.PopulationFull.source
		else (GameTexts.Farm.NextEgg.source):format(math.max(0, math.ceil(self.info.nextEggTime - now)))
	local description = (GameTexts.Farm.NestStatus.source):format(self.info.nestLevel, info.egg, nestText)
	if self.nestSign:GetAttribute("FarmText") ~= description then
		ServerFarmSceneTool.SetSignText(self.nestSign, description)
	end

	for i = #self.info.eggs, 1, -1 do
		local egg = self.info.eggs[i]
		local ground = egg.landing + Vector3.yAxis * egg.height
		if now < egg.landAt then
			local t = (now - egg.started) / (egg.landAt - egg.started)
			local pos = egg.origin:Lerp(ground, t) + Vector3.yAxis * (math.sin(math.pi * t) * FarmConfig.EggArcHeight)
			egg.model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, t * 3, t * math.pi * 2))
		elseif now >= egg.finish then
			ServerAnimalManager.SpawnAnimal(self, egg.landing, egg.variant)
			egg.model:Destroy()
			table.remove(self.info.eggs, i)
		else
			local seconds = math.ceil(egg.finish - now)
			if seconds ~= egg.seconds then
				egg.seconds = seconds
				egg.model:PivotTo(CFrame.new(ground))
				local shell = egg.model.PrimaryPart
				if shell then
					if shell:GetAttribute("FarmSign") ~= "EggSignGui" then
						ServerFarmSceneTool.BindSign(shell, "EggSignGui")
					end
					ServerFarmSceneTool.SetSignText(shell, (GameTexts.Farm.EggCountdown.source):format(catalog.creatures[egg.variant].egg, seconds))
				end
			end
		end
	end
end
return ServerEggManager
