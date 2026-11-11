-- 服务端武器构建器：负责 1~5 阶电击农场武器 Tool 的实体模型装配与握持配置
--!strict
local replicatedStorage = game:GetService("ReplicatedStorage")
local sharedScripts = replicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local Config = require(sharedScripts:WaitForChild("FarmEconomyConfig"))

local ServerWeaponBuilder = {}

local function CreatePiece(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	hex: string,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = Color3.fromHex(hex)
	part.Material = material or Enum.Material.SmoothPlastic
	part.Shape = shape or Enum.PartType.Block
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.Parent = parent
	return part
end

local function WeldToHandle(handle: BasePart, part: BasePart): WeldConstraint
	local weld = Instance.new("WeldConstraint")
	weld.Name = part.Name .. "Weld"
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = handle
	return weld
end

function ServerWeaponBuilder.AttachVisuals(tier: number, handle: BasePart): ()
	local hcf = handle.CFrame
	if tier == 1 then
		-- Tier 1: 基础电棒 (Basic Rod) - 哑光黑握柄 + 顶部青色霓虹晶石棍体
		local shaft = CreatePiece(handle.Parent :: Instance, "Shaft", Vector3.new(0.18, 0.18, 1.3), hcf * CFrame.new(0, 0, -0.9), "4B5563")
		WeldToHandle(handle, shaft)
		local crystalTip = CreatePiece(handle.Parent :: Instance, "CrystalTip", Vector3.new(0.24, 0.24, 0.6), hcf * CFrame.new(0, 0, -1.65), "00F0FF", Enum.Material.Neon)
		WeldToHandle(handle, crystalTip)
		local pommel = CreatePiece(handle.Parent :: Instance, "Pommel", Vector3.new(0.36, 0.36, 0.2), hcf * CFrame.new(0, 0, 0.55), "374151")
		WeldToHandle(handle, pommel)
	elseif tier == 2 then
		-- Tier 2: 连锁电枪 (Chain Zapper) - 枪体握柄 + 弧光放电线圈 + 湛蓝能量核心
		local receiver = CreatePiece(handle.Parent :: Instance, "Receiver", Vector3.new(0.35, 0.5, 0.9), hcf * CFrame.new(0, 0.2, -0.4), "1F2937")
		WeldToHandle(handle, receiver)
		local barrel = CreatePiece(handle.Parent :: Instance, "Barrel", Vector3.new(0.22, 0.22, 1.2), hcf * CFrame.new(0, 0.25, -1.2), "374151")
		WeldToHandle(handle, barrel)
		local coil1 = CreatePiece(handle.Parent :: Instance, "Coil1", Vector3.new(0.32, 0.32, 0.2), hcf * CFrame.new(0, 0.25, -0.9), "3B82F6", Enum.Material.Neon)
		WeldToHandle(handle, coil1)
		local coil2 = CreatePiece(handle.Parent :: Instance, "Coil2", Vector3.new(0.32, 0.32, 0.2), hcf * CFrame.new(0, 0.25, -1.3), "3B82F6", Enum.Material.Neon)
		WeldToHandle(handle, coil2)
		local emitterTip = CreatePiece(handle.Parent :: Instance, "EmitterTip", Vector3.new(0.28, 0.28, 0.25), hcf * CFrame.new(0, 0.25, -1.8), "60A5FA", Enum.Material.Neon)
		WeldToHandle(handle, emitterTip)
	elseif tier == 3 then
		-- Tier 3: 区域电炮 (Area Cannon) - 重型炮身 + 喇叭状能量扩散口 + 橙色等离子舱
		local cannonBody = CreatePiece(handle.Parent :: Instance, "CannonBody", Vector3.new(0.48, 0.55, 1.2), hcf * CFrame.new(0, 0.25, -0.6), "374151")
		WeldToHandle(handle, cannonBody)
		local plasmaChamber = CreatePiece(handle.Parent :: Instance, "PlasmaChamber", Vector3.new(0.38, 0.38, 0.7), hcf * CFrame.new(0, 0.28, -0.6), "F97316", Enum.Material.Neon)
		WeldToHandle(handle, plasmaChamber)
		local muzzle = CreatePiece(handle.Parent :: Instance, "MuzzleCone", Vector3.new(0.7, 0.7, 0.4), hcf * CFrame.new(0, 0.25, -1.35), "4B5563")
		WeldToHandle(handle, muzzle)
		local innerGlow = CreatePiece(handle.Parent :: Instance, "InnerGlow", Vector3.new(0.55, 0.55, 0.15), hcf * CFrame.new(0, 0.25, -1.45), "FB923C", Enum.Material.Neon)
		WeldToHandle(handle, innerGlow)
	elseif tier == 4 then
		-- Tier 4: 广角电炮 (Wide Cannon) - 双翼弧形波发生器 + 强化导轨 + 紫色脉冲条
		local chassis = CreatePiece(handle.Parent :: Instance, "Chassis", Vector3.new(0.52, 0.52, 1.3), hcf * CFrame.new(0, 0.25, -0.7), "4C1D95")
		WeldToHandle(handle, chassis)
		local wingL = CreatePiece(handle.Parent :: Instance, "WingL", Vector3.new(0.15, 0.65, 0.9), hcf * CFrame.new(-0.45, 0.25, -1.1) * CFrame.Angles(0, math.rad(-15), 0), "6D28D9")
		WeldToHandle(handle, wingL)
		local wingR = CreatePiece(handle.Parent :: Instance, "WingR", Vector3.new(0.15, 0.65, 0.9), hcf * CFrame.new(0.45, 0.25, -1.1) * CFrame.Angles(0, math.rad(15), 0), "6D28D9")
		WeldToHandle(handle, wingR)
		local waveEmitter = CreatePiece(handle.Parent :: Instance, "WaveEmitter", Vector3.new(0.9, 0.3, 0.25), hcf * CFrame.new(0, 0.25, -1.45), "C084FC", Enum.Material.Neon)
		WeldToHandle(handle, waveEmitter)
		local powerCore = CreatePiece(handle.Parent :: Instance, "PowerCore", Vector3.new(0.35, 0.35, 0.8), hcf * CFrame.new(0, 0.3, -0.65), "A855F7", Enum.Material.Neon)
		WeldToHandle(handle, powerCore)
	else
		-- Tier 5: 脉冲电炮 (Pulse Cannon) - 高端金白外壳 + 三重霓虹聚焦环 + 脉冲核心
		local chassis = CreatePiece(handle.Parent :: Instance, "Chassis", Vector3.new(0.55, 0.55, 1.4), hcf * CFrame.new(0, 0.25, -0.8), "FEF08A")
		WeldToHandle(handle, chassis)
		local pulseCore = CreatePiece(handle.Parent :: Instance, "PulseCore", Vector3.new(0.42, 0.42, 0.9), hcf * CFrame.new(0, 0.25, -0.8), "FACC15", Enum.Material.Neon)
		WeldToHandle(handle, pulseCore)
		local ring1 = CreatePiece(handle.Parent :: Instance, "Ring1", Vector3.new(0.85, 0.85, 0.15), hcf * CFrame.new(0, 0.25, -1.1), "38BDF8", Enum.Material.Neon)
		WeldToHandle(handle, ring1)
		local ring2 = CreatePiece(handle.Parent :: Instance, "Ring2", Vector3.new(0.75, 0.75, 0.15), hcf * CFrame.new(0, 0.25, -1.35), "38BDF8", Enum.Material.Neon)
		WeldToHandle(handle, ring2)
		local ring3 = CreatePiece(handle.Parent :: Instance, "Ring3", Vector3.new(0.65, 0.65, 0.15), hcf * CFrame.new(0, 0.25, -1.6), "38BDF8", Enum.Material.Neon)
		WeldToHandle(handle, ring3)
		local crownTip = CreatePiece(handle.Parent :: Instance, "CrownTip", Vector3.new(0.35, 0.35, 0.3), hcf * CFrame.new(0, 0.25, -1.8), "E0F2FE", Enum.Material.Neon)
		WeldToHandle(handle, crownTip)
	end
end

function ServerWeaponBuilder.BuildWeaponTool(tier: number, level: number): Tool
	local tool = Instance.new("Tool")
	tool.Name = "FarmWeapon"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = false
	tool:SetAttribute("WeaponTier", tier)
	tool:SetAttribute("WeaponLevel", level)
	tool:SetAttribute("WeaponDamage", Config.GetDamage(tier, level))

	-- 手部握持朝向配置（使武器水平向前持握）
	tool.Grip = CFrame.new(0, -0.15, -0.45)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 0.38, 1.0)
	handle.Color = Color3.fromHex("1E2022")
	handle.Material = Enum.Material.SmoothPlastic
	handle.Anchored = false
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true
	handle.Parent = tool

	ServerWeaponBuilder.AttachVisuals(tier, handle)

	return tool
end

return ServerWeaponBuilder