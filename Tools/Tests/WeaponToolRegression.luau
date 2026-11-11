-- 武器 Tool 离线回归：脱机验证 1~5 阶武器 Tool 的实体装配、属性投影、Handle 与刚性约束
--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Instance = roblox.Instance

local Config = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmEconomyConfig")

local replicatedStorageMock = {
	WaitForChild = function(_self, name)
		if name == "Scripts" or name == "Shared" then
			return _self
		elseif name == "FarmEconomyConfig" then
			return Config
		end
		error("Unknown WaitForChild: " .. tostring(name))
	end,
}

local gameMock = {
	GetService = function(_self, name)
		if name == "ReplicatedStorage" then
			return replicatedStorageMock
		end
		error("Unknown GetService: " .. tostring(name))
	end,
}

local env = {
	game = gameMock,
	Instance = Instance,
	CFrame = roblox.CFrame,
	Vector3 = roblox.Vector3,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
	math = math,
	assert = assert,
	require = function(target)
		if target == Config then
			return Config
		end
		error("Unexpected require in test: " .. tostring(target))
	end,
}

local builderSource = fs.readFile("Scripts/ServerStorage/Scripts/ServerRoastChickenFarmManager/ServerWeaponBuilder.luau")
local builder = luau.load(builderSource, { environment = env })()

local checks = 0
local function Check(condition: boolean, msg: string)
	assert(condition, "Check failed: " .. msg)
	checks += 1
end

print("--> [1/3] 验证 1~5 阶武器 Tool 实例构建与核心属性...")
for tier = 1, 5 do
	local level = 2
	local tool = builder.BuildWeaponTool(tier, level)
	Check(tool ~= nil, "Tool exists for tier " .. tier)
	Check(tool.ClassName == "Tool", "ClassName is Tool for tier " .. tier)
	Check(tool.Name == "FarmWeapon", "Name is FarmWeapon for tier " .. tier)
	Check(tool.CanBeDropped == false, "CanBeDropped is false for tier " .. tier)
	Check(tool.RequiresHandle == true, "RequiresHandle is true for tier " .. tier)
	Check(tool.ManualActivationOnly == false, "ManualActivationOnly is false for tier " .. tier)
	Check(tool:GetAttribute("WeaponTier") == tier, "WeaponTier attribute matches for tier " .. tier)
	Check(tool:GetAttribute("WeaponLevel") == level, "WeaponLevel attribute matches for tier " .. tier)
	local expectedDamage = Config.GetDamage(tier, level)
	Check(tool:GetAttribute("WeaponDamage") == expectedDamage, "WeaponDamage matches config for tier " .. tier)
end

print("--> [2/3] 验证 Handle 与刚性物理装配 (Anchored=false, Massless=true, CanCollide=false)...")
for tier = 1, 5 do
	local tool = builder.BuildWeaponTool(tier, 1)
	local handle = tool:FindFirstChild("Handle")
	Check(handle ~= nil and handle:IsA("BasePart"), "Handle exists and is BasePart for tier " .. tier)
	Check(handle.Anchored == false, "Handle is not anchored for tier " .. tier)
	Check(handle.CanCollide == false, "Handle CanCollide is false for tier " .. tier)
	Check(handle.Massless == true, "Handle Massless is true for tier " .. tier)

	local welds = 0
	local parts = 0
	for _, child in tool:GetChildren() do
		if child:IsA("BasePart") and child ~= handle then
			parts += 1
			Check(child.Anchored == false, child.Name .. " Anchored is false for tier " .. tier)
			Check(child.CanCollide == false, child.Name .. " CanCollide is false for tier " .. tier)
			Check(child.Massless == true, child.Name .. " Massless is true for tier " .. tier)
			local weld = handle:FindFirstChild(child.Name .. "Weld")
			Check(weld ~= nil and weld:IsA("WeldConstraint"), "WeldConstraint exists for " .. child.Name .. " in tier " .. tier)
			if weld then
				Check(weld.Part0 == handle, "Weld Part0 is handle")
				Check(weld.Part1 == child, "Weld Part1 is " .. child.Name)
				welds += 1
			end
		end
	end
	Check(parts > 0, "Tier " .. tier .. " has visual accessory parts")
	Check(welds == parts, "All visual parts are welded to handle for tier " .. tier)
end

print("--> [3/4] 验证各阶武器的特色外观分异...")
local tier1Tool = builder.BuildWeaponTool(1, 1)
Check(tier1Tool:FindFirstChild("CrystalTip") ~= nil, "Tier 1 has CrystalTip")

local tier2Tool = builder.BuildWeaponTool(2, 1)
Check(tier2Tool:FindFirstChild("Receiver") ~= nil and tier2Tool:FindFirstChild("Coil1") ~= nil, "Tier 2 has Receiver and Coils")

local tier3Tool = builder.BuildWeaponTool(3, 1)
Check(tier3Tool:FindFirstChild("CannonBody") ~= nil and tier3Tool:FindFirstChild("PlasmaChamber") ~= nil, "Tier 3 has CannonBody and PlasmaChamber")

local tier4Tool = builder.BuildWeaponTool(4, 1)
Check(tier4Tool:FindFirstChild("WingL") ~= nil and tier4Tool:FindFirstChild("WingR") ~= nil, "Tier 4 has dual wings")

local tier5Tool = builder.BuildWeaponTool(5, 1)
Check(tier5Tool:FindFirstChild("PulseCore") ~= nil and tier5Tool:FindFirstChild("Ring1") ~= nil and tier5Tool:FindFirstChild("Ring3") ~= nil, "Tier 5 has PulseCore and 3 rings")

print("--> [4/4] 验证以玩家为中心的全向范围攻击规则 (AOE Centered on Player)...")
local Combat = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmCombatRules")
local function MakeCandidate(id: string, x: number, z: number, health: number): Combat.Candidate
	return { id = id, x = x, y = 0, z = z, health = health }
end

-- 玩家在 (0, 0, 0)，周围四面八方分别放置动物（前、后、左、右、超远范围）
local candidates = {
	MakeCandidate("front", 0, 6, 2),
	MakeCandidate("back", 0, -6, 2),
	MakeCandidate("left", -6, 0, 2),
	MakeCandidate("right", 6, 0, 2),
	MakeCandidate("far_away", 0, 50, 2), -- 远超出攻击范围 (50 studs)
}

-- 使用 Tier 3 武器，范围 22，以玩家为中心范围攻击 (directionX = nil, directionZ = nil)
local hits = Combat.ResolveShot(3, 1, 0, 0, 0, nil, nil, candidates)
Check(#hits == 4, "AOE hits all 4 surrounding candidates (front, back, left, right)")
local hitIds: { [string]: boolean } = {}
for _, hit in hits do
	hitIds[hit.id] = true
end
Check(hitIds["front"] and hitIds["back"] and hitIds["left"] and hitIds["right"], "All 4 directions hit simultaneously")
Check(not hitIds["far_away"], "Far away candidate outside range is not hit")

print(string.format("=== ALL %d CHECKS PASSED: WeaponToolRegression passed successfully! ===", checks))
