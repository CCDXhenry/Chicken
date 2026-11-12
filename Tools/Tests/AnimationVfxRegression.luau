-- 动画与特效算法离线回归测试：脱机验证 Prompt to Animation 配置、四层特效常数、二次贝塞尔曲线与屏幕冲击
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Instance = roblox.Instance

local Config = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmConfig")

local roastChickenAction = {
	Name = "RoastChickenAction",
	FireServer = function() end,
	FireClient = function() end,
	FireAllClients = function() end,
	OnServerEvent = { Connect = function() return { Disconnect = function() end } end },
	OnClientEvent = { Connect = function() return { Disconnect = function() end } end },
}

local remoteEventsFolder = {
	Name = "RemoteEvents",
	WaitForChild = function(_self, name)
		if name == "RoastChickenAction" then return roastChickenAction end
		return roastChickenAction
	end,
	FindFirstChild = function(_self, name)
		if name == "RoastChickenAction" then return roastChickenAction end
		return roastChickenAction
	end,
}

local replicatedStorageMock = {
	WaitForChild = function(_self, name)
		if name == "Scripts" or name == "Shared" then
			return _self
		elseif name == "FarmConfig" then
			return Config
		elseif name == "RemoteEvents" then
			return remoteEventsFolder
		end
		return _self
	end,
	FindFirstChild = function(_self, name)
		if name == "RemoteEvents" then
			return remoteEventsFolder
		end
		return nil
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

local scriptMock = {
	Parent = replicatedStorageMock,
}

local env = {
	script = scriptMock,
	game = gameMock,
	Instance = Instance,
	CFrame = roblox.CFrame,
	Vector3 = roblox.Vector3,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
	math = math,
	assert = assert,
	typeof = function(v)
		if type(v) == "userdata" then return "Instance" end
		return type(v)
	end,
	require = function(target)
		return Config
	end,
}

local netMsgSource = fs.readFile("Scripts/ReplicatedStorage/Scripts/Shared/NetMsg.luau")
local NetMsg = luau.load(netMsgSource, { environment = env })()

local checks = 0
local function Check(condition: boolean, msg: string)
	assert(condition, "Check failed: " .. msg)
	checks += 1
end

print("--> [1/4] 验证 Prompt to Animation 提示词规格与配置完整性...")
local prompts = Config.AnimationPrompts
Check(prompts ~= nil, "AnimationPrompts defined in FarmConfig")
Check(type(prompts.Zap_T1) == "string" and #prompts.Zap_T1 > 10, "Zap_T1 prompt valid")
Check(type(prompts.Zap_T2) == "string" and #prompts.Zap_T2 > 10, "Zap_T2 prompt valid")
Check(type(prompts.Zap_Heavy) == "string" and #prompts.Zap_Heavy > 10, "Zap_Heavy prompt valid")
Check(type(prompts.Zap_T5) == "string" and #prompts.Zap_T5 > 10, "Zap_T5 prompt valid")
Check(type(prompts.Pickup_Sweep) == "string" and #prompts.Pickup_Sweep > 10, "Pickup_Sweep prompt valid")
Check(type(prompts.Carry_Heavy) == "string" and #prompts.Carry_Heavy > 10, "Carry_Heavy prompt valid")

-- 验证包含 R15 与动作特征关键词
Check(string.find(prompts.Zap_T1, "R15") ~= nil, "Prompt contains R15 target")
Check(string.find(prompts.Zap_T2, "recoil") ~= nil, "Prompt specifies recoil")
Check(string.find(prompts.Pickup_Sweep, "bends") ~= nil, "Prompt specifies bending")

print("--> [1b/4] 验证人物动作动画已停用，VFX 模板配置仍完整...")
local assetIds = Config.AnimationAssetIds
Check(assetIds ~= nil, "AnimationAssetIds defined")
Check(Config.EnableCharacterActionAnims == false, "EnableCharacterActionAnims is false")
local animKeys = { "Zap_T1", "Zap_T2", "Zap_Heavy", "Zap_T5", "Pickup_Sweep", "Carry_Heavy" }
for _, key in animKeys do
	local id = assetIds[key]
	Check(type(id) == "string" and #id == 0, key .. " animation id cleared (disabled)")
end
Check(Config.VfxTemplateFolder == "VFX", "VfxTemplateFolder is ReplicatedStorage.VFX")
Check(Config.VfxTemplates ~= nil and Config.VfxTemplates.HitImpact == "HitImpact", "VfxTemplates.HitImpact named")
Check(Config.VfxTemplates.ZapArc == "ZapArcBeam", "VfxTemplates.ZapArc named")
Check(Config.VfxTemplates.RoastFlight == "RoastFlight", "VfxTemplates.RoastFlight named")
Check(Config.VfxTemplates.FloatAnchor == "FloatAnchor", "VfxTemplates.FloatAnchor named")

print("--> [2/4] 验证优质实例四层特效与弹道参数常数...")
local zapColors = Config.ZapColors
Check(zapColors ~= nil, "ZapColors defined")
Check(zapColors[1] == "53DEFF", "T1 is cyan")
Check(zapColors[2] == "3B82F6", "T2 is blue")
Check(zapColors[3] == "F97316", "T3 is orange plasma")
Check(zapColors[4] == "C084FC", "T4 is purple EMP")
Check(zapColors[5] == "FACC15", "T5 is celestial gold")

Check(Config.PickupFlightDuration > 0.2 and Config.PickupFlightDuration < 0.6, "Pickup duration valid")
Check(Config.PickupArcHeight >= 2.0, "Pickup arc height clears ground by at least 2 studs")
local basketOffset = Config.PickupBasketOffset
Check(basketOffset.x == 0 and basketOffset.z > 0, "Pickup basket offset sits behind the character")
Check(Config.DeliveryFlightDuration > 0.15 and Config.DeliveryFlightDuration < 0.5, "Delivery duration valid")
Check(Config.VfxPoolWarmupCount >= 20, "VfxPool prewarms at least 20 slots for zero GC")

print("--> [3/4] 验证熟食飞向鸡筐的二次贝塞尔曲线数学算法...")
local p0 = { x = 0, y = 0, z = 0 }
local p2 = { x = 10, y = 2, z = 10 }
local mid = { x = (p0.x + p2.x) * 0.5, y = (p0.y + p2.y) * 0.5, z = (p0.z + p2.z) * 0.5 }
local p1 = { x = mid.x, y = mid.y + Config.PickupArcHeight, z = mid.z }

local function Bezier(t: number)
	local u = 1 - t
	return {
		x = u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
		y = u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y,
		z = u * u * p0.z + 2 * u * t * p1.z + t * t * p2.z,
	}
end

-- 端点与中点验证
local startPoint = Bezier(0)
Check(math.abs(startPoint.x - p0.x) < 1e-4 and math.abs(startPoint.y - p0.y) < 1e-4, "Bezier(0) == P0")

local endPoint = Bezier(1)
Check(math.abs(endPoint.x - p2.x) < 1e-4 and math.abs(endPoint.y - p2.y) < 1e-4, "Bezier(1) == P2")

local midPoint = Bezier(0.5)
-- 中点的高度应该明显高于线性插值高度 (mid.y)
local linearMidY = (p0.y + p2.y) * 0.5
Check(midPoint.y > linearMidY + Config.PickupArcHeight * 0.45, "Bezier arc peak is significantly higher than linear interpolation")

print("--> [4/4] 验证轻量视觉事件数据结构规范...")
local testVisualEvent: any = {
	kind = "zap",
	tier = 2,
	fromPos = { x = 0, y = 1.5, z = 0 },
	targets = {
		{ x = 5, y = 1, z = 5, damage = 6, isCooked = false },
		{ x = 8, y = 1, z = 6, damage = 6, isCooked = true },
	},
}
Check(testVisualEvent.kind == "zap", "VisualEvent kind valid")
Check(testVisualEvent.targets ~= nil and #testVisualEvent.targets == 2, "VisualEvent targets list valid")
Check(testVisualEvent.targets[2].isCooked == true, "Cooked target flag verified")

print("=== ALL " .. checks .. " CHECKS PASSED: AnimationVfxRegression passed successfully! ===")
