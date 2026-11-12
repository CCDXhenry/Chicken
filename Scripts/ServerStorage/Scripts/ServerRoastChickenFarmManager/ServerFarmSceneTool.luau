-- 农场场景表现工具：生成模型部件、绑定标牌并判定交互区
--!strict
local CollectionService = game:GetService("CollectionService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local sharedScripts = replicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local FarmConfig = require(sharedScripts:WaitForChild("FarmConfig"))

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
function ServerFarmSceneTool.SetSignText(part: BasePart, message: string): ()
	part:SetAttribute("FarmText", message)
end
function ServerFarmSceneTool.SetHealthTone(part: BasePart, damaged: boolean): ()
	part:SetAttribute("FarmHealthTone", if damaged then "damaged" else "healthy")
end
return ServerFarmSceneTool
