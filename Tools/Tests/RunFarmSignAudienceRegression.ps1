# 标牌受众与全公开查看离线回归：验证所有农场世界标牌对访客开放、私有标牌过滤与重置清理。
$ErrorActionPreference = 'Stop'
Push-Location (Resolve-Path "$PSScriptRoot/../..")
try {
@'
local fs = require('@lune/fs')
local luau = require('@lune/luau')
local roblox = require('@lune/roblox')
local Instance = roblox.Instance

local checks = 0
local function Check(value, message)
	assert(value, message)
	checks += 1
end

-- 1. 服务端 ServerFarmSceneTool 标牌受众测试
local node = {}
function node:WaitForChild() return self end
local sceneToolEnv = {
	game = {
		GetService = function(_, name)
			if name == "CollectionService" then
				return {
					AddTag = function() end,
					RemoveTag = function() end,
				}
			end
			return node
		end,
	},
	script = {
		Parent = {
			Parent = node,
		},
	},
	require = function()
		return {}
	end,
}
local SceneTool = luau.load(fs.readFile('Scripts/ServerStorage/Scripts/ServerRoastChickenFarmManager/ServerFarmSceneTool.luau'), { environment = sceneToolEnv })()

local testPart = Instance.new("Part")
SceneTool.BindSign(testPart, "AnimalHealthGui", 2.5)
Check(testPart:GetAttribute("FarmSign") == "AnimalHealthGui", "BindSign sets FarmSign")
Check(testPart:GetAttribute("FarmSignAudience") == "Public", "BindSign defaults to Public audience")
Check(testPart:GetAttribute("FarmStudsOffsetY") == 2.5, "BindSign sets studs offset")

SceneTool.BindSign(testPart, "TestSign", nil, "Private")
Check(testPart:GetAttribute("FarmSignAudience") == "Private", "BindSign respects explicit Private audience")

SceneTool.ClearSign(testPart)
Check(testPart:GetAttribute("FarmSign") == nil, "ClearSign clears FarmSign")
Check(testPart:GetAttribute("FarmSignAudience") == nil, "ClearSign clears FarmSignAudience")
Check(testPart:GetAttribute("FarmStudsOffsetY") == nil, "ClearSign clears FarmStudsOffsetY")

-- 2. 地块清理重置（Tool.Reset）对 Public 业务标牌的清理与门牌保留
local villageConfig = luau.load(fs.readFile('Scripts/ReplicatedStorage/Scripts/Shared/FarmVillageConfig.luau'))()
local node = {}
function node:WaitForChild(name) return (name == 'Scripts' or name == 'Shared') and self or name end
local villageModules = {
	FarmVillageConfig = villageConfig,
	GameTexts = { Farm = { VillageVacant = { source = '%s · Vacant farm' }, VillageOwner = { source = "%s · %s's farm" } } }
}
local villageEnv = { game = { GetService = function() return node end }, require = function(name) return assert(villageModules[name], name) end }
local VillageTool = luau.load(fs.readFile('Scripts/ServerStorage/Scripts/ServerFarmVillageTool.luau'), { environment = villageEnv })()

local farmMap = Instance.new("Folder")
farmMap.Name = "Plot01"
farmMap:SetAttribute("FarmId", "Plot01")
local ownerSign = Instance.new("Part")
ownerSign.Name = "OwnerSign"
ownerSign:SetAttribute("FarmSign", "FarmOwnerSignGui")
ownerSign:SetAttribute("FarmSignAudience", "Public")
ownerSign.Parent = farmMap

local nestSign = Instance.new("Part")
nestSign.Name = "ProductionSign"
nestSign:SetAttribute("FarmSign", "NestSignGui")
nestSign:SetAttribute("FarmSignAudience", "Public")
nestSign:SetAttribute("FarmText", "T1 Chicken · Next egg in 2s")
nestSign.Parent = farmMap

local restaurantSign = Instance.new("Part")
restaurantSign.Name = "StockSign"
restaurantSign:SetAttribute("FarmSign", "RestaurantSignGui")
restaurantSign:SetAttribute("FarmSignAudience", "Public")
restaurantSign:SetAttribute("FarmText", "1 waiting · Expected 10 coins")
restaurantSign.Parent = farmMap

VillageTool.Reset(farmMap)
Check(ownerSign:GetAttribute("FarmSign") == "FarmOwnerSignGui", "Reset preserves FarmOwnerSignGui on OwnerSign")
Check(ownerSign:GetAttribute("FarmText") == "Plot01 · Vacant farm", "Reset updates OwnerSign to vacant text")
Check(nestSign:GetAttribute("FarmSign") == nil, "Reset clears public NestSignGui on business building")
Check(nestSign:GetAttribute("FarmSignAudience") == nil, "Reset clears NestSign FarmSignAudience")
Check(nestSign:GetAttribute("FarmText") == nil, "Reset clears NestSign FarmText")
Check(restaurantSign:GetAttribute("FarmSign") == nil, "Reset clears public RestaurantSignGui on business building")
Check(restaurantSign:GetAttribute("FarmSignAudience") == nil, "Reset clears RestaurantSign FarmSignAudience")

-- 3. 客户端 ClientBillboardManager 受众过滤规则验证
-- 模拟本地玩家为 LocalPlayer (UserId = 100)
local localUserId = 100
local foreignUserId = 200

local function FilterSign(part, currentUserId)
	local ownerId = part:GetAttribute("OwnerUserId")
	local audience = part:GetAttribute("FarmSignAudience")
	if audience == "Private" and typeof(ownerId) == "number" and ownerId ~= currentUserId then
		return "Released"
	end
	local signName = part:GetAttribute("FarmSign")
	if typeof(signName) ~= "string" or signName == "" then
		return "Released"
	end
	return "Mounted"
end

local publicSigns = {
	"AnimalHealthGui",
	"EggSignGui",
	"NestSignGui",
	"RestaurantSignGui",
	"WorkerSignGui",
	"CookedFoodSignGui",
	"FarmOwnerSignGui",
}

for _, signName in ipairs(publicSigns) do
	local foreignPart = Instance.new("Part")
	foreignPart:SetAttribute("OwnerUserId", foreignUserId)
	foreignPart:SetAttribute("FarmSign", signName)
	foreignPart:SetAttribute("FarmSignAudience", "Public")
	Check(FilterSign(foreignPart, localUserId) == "Mounted", "Visitor mounts foreign public sign: " .. signName)
end

-- 验证显式 Private 标牌对访客被 Release 拦截
local privatePart = Instance.new("Part")
privatePart:SetAttribute("OwnerUserId", foreignUserId)
privatePart:SetAttribute("FarmSign", "SecretSign")
privatePart:SetAttribute("FarmSignAudience", "Private")
Check(FilterSign(privatePart, localUserId) == "Released", "Visitor cannot mount foreign Private sign")
Check(FilterSign(privatePart, foreignUserId) == "Mounted", "Owner can mount their own Private sign")

print('FarmSignAudienceRegression passed:', checks, 'checks; public signs, private filtering, reset cleanup')
'@ | lune run -
    if ($LASTEXITCODE -ne 0) { throw 'FarmSignAudienceRegression failed' }
} finally { Pop-Location }
