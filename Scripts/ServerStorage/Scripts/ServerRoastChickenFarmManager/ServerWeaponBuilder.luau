-- 服务端武器构建器：仅克隆 ReplicatedStorage.Models.Weapons 预制电击枪，投影装备等级与伤害属性
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("FarmEconomyConfig"))

local ServerWeaponBuilder = {}

function ServerWeaponBuilder.BuildWeaponTool(tier: number, level: number): Tool
	local models = ReplicatedStorage:WaitForChild("Models")
	local weapons = models:WaitForChild("Weapons")
	local template = weapons:FindFirstChild("ZapWeapon_T" .. tostring(tier))
	assert(template and template:IsA("Tool"), "缺少电击枪预制模板：ReplicatedStorage.Models.Weapons.ZapWeapon_T" .. tostring(tier))
	local handle = template:FindFirstChild("Handle")
	local muzzle = template:FindFirstChild("Muzzle", true)
	assert(handle and handle:IsA("BasePart"), "电击枪模板缺少 Handle")
	assert(muzzle and muzzle:IsA("Attachment") and muzzle.Parent and muzzle.Parent:IsA("BasePart"), "电击枪模板缺少枪口 Muzzle Attachment")

	local tool = template:Clone()
	tool.Name = "FarmWeapon"
	tool:SetAttribute("WeaponTier", tier)
	tool:SetAttribute("WeaponLevel", level)
	tool:SetAttribute("WeaponDamage", Config.GetDamage(tier, level))
	return tool
end

return ServerWeaponBuilder
