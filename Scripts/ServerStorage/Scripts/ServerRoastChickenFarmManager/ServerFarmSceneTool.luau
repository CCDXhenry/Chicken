-- 农场场景表现工具：维护模型、模板克隆和临时特效的生命周期
--!strict
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local sharedScripts = replicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local FarmConfig = require(sharedScripts:WaitForChild("FarmConfig"))
local LifecycleTool = require(sharedScripts:WaitForChild("LifecycleTool"))
local ServerFarmTypes = require(script.Parent.Parent:WaitForChild("ServerFarmTypes"))
type FarmContext = ServerFarmTypes.FarmContext
type PlayerFarmState = ServerFarmTypes.PlayerFarmInfo

local ServerFarmSceneTool = {}
function ServerFarmSceneTool.FlatVector(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end
function ServerFarmSceneTool.GetPlayerRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	return if rootPart and rootPart:IsA("BasePart") then rootPart else nil
end
function ServerFarmSceneTool.IsInZone(rootPart: BasePart, zone: BasePart): boolean
	local point = zone.CFrame:PointToObjectSpace(rootPart.Position)
	return math.abs(point.X) <= zone.Size.X / 2 and math.abs(point.Z) <= zone.Size.Z / 2 and math.abs(point.Y) < FarmConfig.ZoneHeightTolerance
end
function ServerFarmSceneTool.CreatePiece(parent: Instance, name: string, size: Vector3, cf: CFrame, hex: string, ball: boolean?): Part
	local part = Instance.new("Part")
	part.Name, part.Size, part.CFrame, part.Color = name, size, cf, Color3.fromHex(hex)
	part.Shape = if ball then Enum.PartType.Ball else Enum.PartType.Block
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
	part.Parent = parent
	return part
end
function ServerFarmSceneTool.BindSign(part: BasePart, templateName: string, studsOffsetY: number?, audience: string?): ()
	part:SetAttribute("FarmSign", templateName)
	part:SetAttribute("FarmSignAudience", audience or "Public")
	CollectionService:AddTag(part, "FarmSignPart")
	if studsOffsetY ~= nil then
		part:SetAttribute("FarmStudsOffsetY", studsOffsetY)
	end
end
function ServerFarmSceneTool.ClearSign(part: BasePart): ()
	CollectionService:RemoveTag(part, "FarmSignPart")
	part:SetAttribute("FarmSign", nil)
	part:SetAttribute("FarmSignAudience", nil)
	part:SetAttribute("FarmText", nil)
	part:SetAttribute("FarmHealthTone", nil)
	part:SetAttribute("FarmStudsOffsetY", nil)
end
function ServerFarmSceneTool.SetSignText(part: BasePart, message: string): ()
	part:SetAttribute("FarmText", message)
end
function ServerFarmSceneTool.SetHealthTone(part: BasePart, damaged: boolean): ()
	part:SetAttribute("FarmHealthTone", if damaged then "damaged" else "healthy")
end
function ServerFarmSceneTool.UpdateBasketVisual(self: FarmContext, player: Player, s: PlayerFarmState): ()
	local character = player.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local model = character:FindFirstChild("ChickenBasket")
	if not model and #s.items > 0 then
		local basketModel = Instance.new("Model")
		basketModel.Name = "ChickenBasket"
		basketModel.Parent = character
		model = basketModel

		local function attach(name: string, size: Vector3, offset: Vector3, hex: string, ball: boolean?): Part
			local p = ServerFarmSceneTool.CreatePiece(basketModel, name, size, root.CFrame * CFrame.new(offset), hex, ball)
			p.Massless = true
			p.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = p
			weld.Parent = p
			return p
		end

		attach("Basket", Vector3.new(1.85, 0.85, 1.05), Vector3.new(0, -0.1, 1), "B57436")
		for _, y in { -0.36, -0.1, 0.16, 0.36 } do
			attach("WovenBand", Vector3.new(1.92, 0.09, 1.1), Vector3.new(0, y, 1), "EDB568")
		end
		for i = 1, FarmConfig.BasketCapacity do
			local xOffset = ((i - 1) % 3 - 1) * 0.55
			local zOffset = 0.76 + math.floor((i - 1) / 3) * 0.45
			attach("Roast" .. i, Vector3.new(0.55, 0.47, 0.5), Vector3.new(xOffset, 0.45, zOffset), "EF953B", true)
		end
	end

	if model then
		for i = 1, FarmConfig.BasketCapacity do
			local roastPart = model:FindFirstChild("Roast" .. i) :: BasePart?
			if roastPart then
				roastPart.Transparency = if i <= #s.items then 0 else 1
			end
		end
		if #s.items == 0 then
			model:Destroy()
		end
	end
end

function ServerFarmSceneTool.CreateAnimalHealthLabel(self: FarmContext, model: Model): ()
	local primaryPart = model.PrimaryPart
	assert(primaryPart, "Animal model needs PrimaryPart")
	local bounds, size = model:GetBoundingBox()
	local offsetY = bounds.Position.Y + size.Y / 2 - primaryPart.Position.Y + 0.25
	ServerFarmSceneTool.BindSign(primaryPart, "AnimalHealthGui", offsetY, "Public")
end

function ServerFarmSceneTool.GetAnimalPosition(info: ServerFarmTypes.AnimalInfo): Vector3
	return info.pos
end
function ServerFarmSceneTool.GetRoastPosition(info: ServerFarmTypes.RoastInfo): Vector3
	return info.pos
end
function ServerFarmSceneTool.FindNearby<T>(
	self: FarmContext,
	pool: { [Model]: T },
	getPosition: (T) -> Vector3,
	origin: Vector3,
	range: number,
	direction: Vector3?,
	minDot: number?
): { { model: Model, pos: Vector3, dist: number } }
	local list: { ServerFarmTypes.NearbyTarget } = {}
	local thresholdDot = minDot or 0
	for model, data in pairs(pool) do
		local pos = getPosition(data)
		local offset = ServerFarmSceneTool.FlatVector(pos - origin)
		local dist = offset.Magnitude
		if dist <= range and (not direction or dist < 0.01 or direction:Dot(offset.Unit) >= thresholdDot) then
			table.insert(list, { model = model, pos = pos, dist = dist })
		end
	end
	table.sort(list, function(a, b)
		return a.dist < b.dist
	end)
	return list
end

function ServerFarmSceneTool.SpawnLightningArc(self: { map: Folder, rng: Random, scope: LifecycleTool.Lifecycle }, from: Vector3, to: Vector3): ()
	local last = from
	for i = 1, 5 do
		local nextPoint = from:Lerp(to, i / 5)
		if i < 5 then
			nextPoint += Vector3.new(self.rng:NextNumber(-0.38, 0.38), self.rng:NextNumber(-0.5, 0.5), self.rng:NextNumber(-0.38, 0.38))
		end
		local length = (last - nextPoint).Magnitude
		if length > 0.02 then
			local p = ServerFarmSceneTool.CreatePiece(
				self.map,
				"Lightning",
				Vector3.new(0.17, 0.17, length),
				CFrame.lookAt((last + nextPoint) / 2, nextPoint),
				"53DEFF"
			)
			self.scope:Own(p)
			p.Material = Enum.Material.Neon
			Debris:AddItem(p, 0.2)
		end
		last = nextPoint
	end
end

function ServerFarmSceneTool.CollectRoast(self: FarmContext, targetModel: Model, root: BasePart): ()
	self.info.roasts[targetModel] = nil
	local start = targetModel:GetPivot()
	self.scope:Own(targetModel)
	self.scope:Spawn(function()
		for i = 1, FarmConfig.PickupAnimationSteps do
			if not root.Parent or not targetModel.Parent then
				break
			end
			local t = i / FarmConfig.PickupAnimationSteps
			local destPos = (root.CFrame * CFrame.new(0, 0.25, 1)).Position
			local pos = start.Position:Lerp(destPos, t)
			targetModel:PivotTo(CFrame.new(pos + Vector3.yAxis * math.sin(t * math.pi) * 1.6) * CFrame.Angles(0, t * 4, 0))
			task.wait(FarmConfig.PickupAnimationInterval)
		end
		targetModel:Destroy()
	end)
end
return ServerFarmSceneTool
