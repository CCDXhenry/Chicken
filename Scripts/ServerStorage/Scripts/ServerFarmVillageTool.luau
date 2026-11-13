-- 常驻农场地块工具：验证预置实例、唯一认领、清理经营对象并恢复空置标牌
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("FarmVillageConfig"))
local Texts = require(Shared:WaitForChild("GameTexts"))
local Paths = require(Shared:WaitForChild("FarmScenePaths"))
local Tool = {}
function Tool.Reset(map: Folder): ()
 local runtime = Paths.Find(map, "Runtime")
 if runtime then runtime:Destroy() end
	map:SetAttribute("OwnerUserId", nil)
	map:SetAttribute("Occupied", false)
	for _, object in map:GetDescendants() do
		object:SetAttribute("OwnerUserId", nil)
		if object:IsA("BasePart") and object:GetAttribute("FarmSign") and object.Name ~= "OwnerSign" then
			object:SetAttribute("FarmSign", nil)
			object:SetAttribute("FarmSignAudience", nil)
			object:SetAttribute("FarmText", nil)
		end
	end
	local sign = Paths.Find(map, "OwnerSign")
	if sign and sign:IsA("BasePart") then sign:SetAttribute("FarmText", Texts.Farm.VillageVacant.source:format(tostring(map:GetAttribute("FarmId")))) end
end

function Tool.FindAvailable(plots: Instance, farms: Instance, reservations: { [BasePart]: Player }): (BasePart?, Folder?)
	local ordered = plots:GetChildren()
	table.sort(ordered, function(a, b) return a.Name < b.Name end)
	for _, candidate in ordered do
		if candidate:IsA("BasePart") and Config.IsPlotId(candidate.Name) and not reservations[candidate] then
			local map = farms:FindFirstChild(candidate.Name)
			if map and map:IsA("Folder") and map:GetAttribute("OwnerUserId") == nil then return candidate, map end
		end
	end
	return nil, nil
end

function Tool.Claim(map: Folder, plot: BasePart, player: Player, reservations: { [BasePart]: Player }): boolean
	for _, owner in reservations do if owner == player then return false end end
	if reservations[plot] or map:GetAttribute("OwnerUserId") ~= nil then return false end
	if map.Name ~= plot.Name or map:GetAttribute("FarmId") ~= plot.Name then return false end
	Tool.Reset(map)
	reservations[plot] = player
	map:SetAttribute("OwnerUserId", player.UserId)
	map:SetAttribute("Occupied", true)
	for _, object in map:GetDescendants() do if object:IsA("BasePart") then object:SetAttribute("OwnerUserId", player.UserId) end end
	local sign = Paths.Find(map, "OwnerSign")
	if sign and sign:IsA("BasePart") then sign:SetAttribute("FarmText", Texts.Farm.VillageOwner.source:format(plot.Name, player.DisplayName)) end
	return true
end

function Tool.Release(map: Folder, plot: BasePart, player: Player, reservations: { [BasePart]: Player }): boolean
	if reservations[plot] ~= player or map:GetAttribute("OwnerUserId") ~= player.UserId then return false end
	Tool.Reset(map)
	reservations[plot] = nil
	return true
end

function Tool.Validate(plots: Instance, farms: Instance): ()
	assert(#plots:GetChildren() == Config.Capacity and #farms:GetChildren() == Config.Capacity, "Farm village requires exactly eight plots and static farms")
	for index = 1, Config.Capacity do
		local name = string.format("Plot%02d", index)
		local plot, map = plots:FindFirstChild(name), farms:FindFirstChild(name)
		assert(plot and plot:IsA("BasePart") and map and map:IsA("Folder"), "Missing village plot " .. name)
		assert(map:GetAttribute("FarmId") == name, "Village FarmId mismatch: " .. name)
  for key in Paths.StaticPaths do
   if key ~= "Runtime" and key ~= "Eggs" and key ~= "LiveAnimals" and key ~= "CookedFood" and key ~= "RestaurantRuntime" then
    Paths.Require(map, key)
   end
  end
	end
end
return Tool
