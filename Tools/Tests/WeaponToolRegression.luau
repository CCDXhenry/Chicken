-- 武器 Tool 离线回归：验证唯一预制来源、枪口 Attachment、克隆隔离与握持装配
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Instance = roblox.Instance

local Config = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmEconomyConfig")

local models = Instance.new("Folder")
models.Name = "Models"
local weapons = roblox.deserializeModel(fs.readFile("Assets/Studio/ZapWeaponTemplates.rbxm"))[1]
assert(weapons.Name == "Weapons" and weapons:IsA("Folder"), "asset must preserve Models.Weapons folder")
weapons.Parent = models

local replicatedStorageMock = {
	WaitForChild = function(_self, name)
		if name == "Models" then
			return { WaitForChild = function(_, childName)
				assert(childName == "Weapons")
				return weapons
			end }
		elseif name == "Scripts" or name == "Shared" then
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
	Check(tool.ManualActivationOnly == true, "ManualActivationOnly is true for tier " .. tier)
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
Check(
	tier5Tool:FindFirstChild("PulseCore") ~= nil and tier5Tool:FindFirstChild("Ring1") ~= nil and tier5Tool:FindFirstChild("Ring3") ~= nil,
	"Tier 5 has PulseCore and 3 rings"
)

print("--> 验证枪口预制、克隆引用及模板为唯一模型来源...")
for tier = 1, 5 do
	local template = weapons:FindFirstChild("ZapWeapon_T" .. tier)
	local tool = builder.BuildWeaponTool(tier, 2)
	local muzzle = tool:FindFirstChild("Muzzle", true)
	Check(muzzle ~= nil and muzzle:IsA("Attachment"), "Tier " .. tier .. " has preset Muzzle Attachment")
	Check(muzzle.Parent:IsA("BasePart") and muzzle.Parent.Parent == tool, "Muzzle is mounted on cloned weapon tip")
	Check(math.abs(muzzle.CFrame.Position.Z + muzzle.Parent.Size.Z / 2) < 0.001, "Muzzle lies on forward tip surface")
	Check(template:GetAttribute("WeaponLevel") == nil and template:GetAttribute("WeaponDamage") == nil, "runtime attributes never mutate template")
	Check(#tool:GetDescendants() == #template:GetDescendants(), "runtime does not assemble extra geometry")
	tool:Destroy()
	Check(template.Parent == weapons and template:FindFirstChild("Muzzle", true) ~= nil, "destroying clone preserves template")
end
local template = weapons:FindFirstChild("ZapWeapon_T1")
local customTip = template:FindFirstChild("CrystalTip")
customTip.Color = roblox.Color3.fromRGB(13, 27, 39)
Check(builder.BuildWeaponTool(1, 1):FindFirstChild("CrystalTip").Color == customTip.Color, "editing template changes runtime appearance without code changes")
local muzzle = template:FindFirstChild("Muzzle", true)
muzzle.Parent = nil
Check(not pcall(builder.BuildWeaponTool, 1, 1), "missing muzzle fails clearly without generating a fallback")
muzzle.Parent = customTip
Check(not pcall(builder.BuildWeaponTool, 99, 1), "missing template fails clearly without procedural model fallback")

print("--> [4/4] 验证电击按准心射界结算，缺失方向不会变成全向...")
local Combat = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmCombatRules")
local function MakeCandidate(id: string, x: number, z: number, health: number): Combat.Candidate
	return { id = id, x = x, y = 0, z = z, health = health }
end

-- 玩家在 (0, 0, 0)，准心朝 +Z。前方两只在 60° 扇区内，侧向、身后和超距不在射界。
local candidates = {
	MakeCandidate("front", 0, 6, 2),
	MakeCandidate("front_far", 1, 12, 2),
	MakeCandidate("back", 0, -6, 2),
	MakeCandidate("side", 6, 0, 2),
	MakeCandidate("far_away", 0, 50, 2),
}

local missing = Combat.ResolveShot(3, 1, 0, 0, 0, nil, nil, candidates)
Check(#missing == 0, "missing aim does not hit surrounding targets")
local hits = Combat.ResolveShot(3, 1, 0, 0, 0, 0, 1, candidates)
Check(#hits == 2 and hits[1].id == "front" and hits[2].id == "front_far", "cone hits both forward targets in distance order")
Check(hits[1].damage == 2 and hits[2].damage == 2, "cone caps each equal share by remaining health")
local bulky = {
	MakeCandidate("front", 0, 6, 100),
	MakeCandidate("front_far", 1, 12, 100),
	MakeCandidate("back", 0, -6, 100),
	MakeCandidate("side", 6, 0, 100),
	MakeCandidate("far_away", 0, 50, 100),
}
local split = Combat.ResolveShot(3, 1, 0, 0, 0, 0, 1, bulky)
Check(#split == 2 and split[1].damage == 9 and split[2].damage == 9, "cone splits one shot equally across forward targets")
local hitIds: { [string]: boolean } = {}
for _, hit in hits do
	hitIds[hit.id] = true
end
Check(not hitIds["back"] and not hitIds["side"] and not hitIds["far_away"], "behind, wide side and out-of-range targets are excluded")

print(string.format("=== ALL %d CHECKS PASSED: WeaponToolRegression passed successfully! ===", checks))
