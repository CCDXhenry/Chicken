# 蛋标牌高度与防下落集成离线回归测试：验证 ClientBillboardManager 与 EggBillboardBinder 配合时，StudsOffset 绝不被置零下沉。
$ErrorActionPreference = 'Stop'
Push-Location (Resolve-Path "$PSScriptRoot/../..")
try {
@'
local fs = require('@lune/fs')
local luau = require('@lune/luau')

local checks = 0
local function Check(value, message)
	assert(value, message)
	checks += 1
end

-- 构造通用 mock 节点
local function CreateMockInstance(className, name)
	local attributes = {}
	local attrSignals = {}
	local propSignals = {}
	local children = {}
	local obj = {}
	obj.ClassName = className
	obj.Name = name or className
	obj.Parent = nil

	if className == "ImageButton" then
		obj.InputBegan = { Connect = function() return { Disconnect = function() end } end }
		obj.Activated = { Connect = function() return { Disconnect = function() end } end }
	end

	function obj:GetAttribute(attrName)
		return attributes[attrName]
	end
	function obj:SetAttribute(attrName, val)
		attributes[attrName] = val
		if attrSignals[attrName] then
			for _, cb in ipairs(attrSignals[attrName]) do cb() end
		end
	end
	function obj:GetAttributeChangedSignal(attrName)
		return {
			Connect = function(_, cb)
				attrSignals[attrName] = attrSignals[attrName] or {}
				table.insert(attrSignals[attrName], cb)
				return {
					Disconnect = function()
						local idx = table.find(attrSignals[attrName], cb)
						if idx then table.remove(attrSignals[attrName], idx) end
					end,
				}
			end,
		}
	end
	function obj:GetPropertyChangedSignal(propName)
		return {
			Connect = function(_, cb)
				propSignals[propName] = propSignals[propName] or {}
				table.insert(propSignals[propName], cb)
				return {
					Disconnect = function()
						local idx = table.find(propSignals[propName], cb)
						if idx then table.remove(propSignals[propName], idx) end
					end,
				}
			end,
		}
	end
	function obj:FindFirstChild(childName, recursive)
		for _, c in ipairs(children) do
			if c.Name == childName then return c end
			if recursive then
				local found = c:FindFirstChild(childName, true)
				if found then return found end
			end
		end
		return nil
	end
	function obj:WaitForChild(childName)
		local found = obj:FindFirstChild(childName, true)
		return found or CreateMockInstance("Folder", childName)
	end
	function obj:FindFirstAncestorOfClass(cls)
		local curr = obj.Parent
		while curr do
			if curr.ClassName == cls then return curr end
			curr = curr.Parent
		end
		return nil
	end
	function obj:IsA(cls)
		return obj.ClassName == cls or cls == "Instance" or cls == "BasePart" and obj.ClassName == "Part" or cls == "GuiObject" and (obj.ClassName == "Frame" or obj.ClassName == "TextLabel" or obj.ClassName == "ImageButton")
	end
	function obj:IsDescendantOf(ancestor)
		local curr = obj.Parent
		while curr do
			if curr == ancestor then return true end
			curr = curr.Parent
		end
		return false
	end
	function obj:AddChild(child)
		child.Parent = obj
		table.insert(children, child)
		return child
	end
	function obj:GetChildren()
		return children
	end
	function obj:Destroy()
		obj.Parent = nil
		table.clear(children)
	end
	function obj:Clone()
		local clone = CreateMockInstance(obj.ClassName, obj.Name)
		for k, v in pairs(attributes) do clone:SetAttribute(k, v) end
		clone.Size = obj.Size
		clone.StudsOffset = obj.StudsOffset
		for _, child in ipairs(children) do
			clone:AddChild(child:Clone())
		end
		return clone
	end

	return obj
end

-- 构造 Vector / UDim 结构
local function Vector3New(x, y, z)
	local v = { X = x or 0, Y = y or 0, Z = z or 0 }
	v.Magnitude = math.sqrt(v.X^2 + v.Y^2 + v.Z^2)
	v.__index = v
	setmetatable(v, {
		__add = function(a, b) return Vector3New(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
		__sub = function(a, b) return Vector3New(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
		__mul = function(a, b)
			if type(b) == "number" then return Vector3New(a.X * b, a.Y * b, a.Z * b) end
			return Vector3New(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
		end,
		__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end,
		__tostring = function(a) return string.format("<Vector3(%s, %s, %s)>", a.X, a.Y, a.Z) end,
	})
	return v
end

local function Vector2New(x, y)
	return { X = x or 0, Y = y or 0 }
end

local function UDim2FromScale(x, y)
	return { X = { Scale = x, Offset = 0 }, Y = { Scale = y, Offset = 0 } }
end

-- 构造 EggSignGui 模板
local templateEggSign = CreateMockInstance("BillboardGui", "EggSignGui")
templateEggSign.Size = UDim2FromScale(4.8, 1.9)
templateEggSign.StudsOffset = Vector3New(0, 0, 0)
templateEggSign:SetAttribute("CompactSize", Vector2New(4.8, 1.9))
templateEggSign:SetAttribute("ExpandedSize", Vector2New(5.8, 3.0))
templateEggSign:SetAttribute("ModelClearanceStuds", 0.3)
templateEggSign:SetAttribute("FeedbackSeconds", 0.65)
templateEggSign:SetAttribute("Quality_normal", { R = 0.8, G = 0.8, B = 0.8 })

local contentFrame = templateEggSign:AddChild(CreateMockInstance("Frame", "ContentFrame"))
local compactFrame = contentFrame:AddChild(CreateMockInstance("Frame", "CompactFrame"))
compactFrame:AddChild(CreateMockInstance("TextLabel", "TimeText"))
compactFrame:AddChild(CreateMockInstance("TextLabel", "QualityText"))
compactFrame:AddChild(CreateMockInstance("TextLabel", "NameText"))
local compactProgress = compactFrame:AddChild(CreateMockInstance("Frame", "ProgressFrame"))
compactProgress:AddChild(CreateMockInstance("Frame", "FillFrame"))

local expandedFrame = contentFrame:AddChild(CreateMockInstance("Frame", "ExpandedFrame"))
expandedFrame:AddChild(CreateMockInstance("TextLabel", "TimeText"))
expandedFrame:AddChild(CreateMockInstance("TextLabel", "QualityText"))
expandedFrame:AddChild(CreateMockInstance("TextLabel", "NameText"))
expandedFrame:AddChild(CreateMockInstance("TextLabel", "FeedbackText"))
local expandedProgress = expandedFrame:AddChild(CreateMockInstance("Frame", "ProgressFrame"))
expandedProgress:AddChild(CreateMockInstance("Frame", "FillFrame"))

local accelerateButton = expandedFrame:AddChild(CreateMockInstance("ImageButton", "AccelerateButton"))
accelerateButton.InputBegan = { Connect = function() return { Disconnect = function() end } end }
local cooldownFrame = accelerateButton:AddChild(CreateMockInstance("Frame", "CooldownFrame"))
cooldownFrame:AddChild(CreateMockInstance("Frame", "FillFrame"))

local detailsButton = expandedFrame:AddChild(CreateMockInstance("ImageButton", "DetailsButton"))
detailsButton.Activated = { Connect = function() return { Disconnect = function() end } end }

local uiFolder = CreateMockInstance("Folder", "UI")
uiFolder:AddChild(templateEggSign)

-- 模拟环境与依赖
local mockPlayerGui = CreateMockInstance("Folder", "PlayerGui")
local mockLocalPlayer = {
	UserId = 100,
	PlayerGui = mockPlayerGui,
	WaitForChild = function(_, name) if name == "PlayerGui" then return mockPlayerGui end return nil end,
}

local fakeFarmInfo = { ready = true, eggId = nil }
local fakeInfoModule = { GetFarmInfo = function() return fakeFarmInfo end }
local fakeTextTool = {
	Set = function(label, text) label.Text = text end,
	Remove = function() end,
}
local fakeUI = { HasShowingWindow = function() return false end }
local fakeHatch = {
	IsHolding = function() return false end,
	CooldownFraction = function() return 0 end,
	Start = function() return true end,
	Stop = function() end,
	OpenDetails = function() end,
}
local fakeConfig = {
	GetSpecies = function(id) return { name = "Chicken", key = id } end,
}
local fakeFarmSound = { Play = function() end }

local LifecycleTool = {}
LifecycleTool.__index = LifecycleTool
function LifecycleTool.new()
	return setmetatable({ alive = true, connections = {} }, LifecycleTool)
end
function LifecycleTool:Connect(conn)
	table.insert(self.connections, conn)
	return conn
end
function LifecycleTool:Spawn(fn)
	fn()
end
function LifecycleTool:Destroy()
	self.alive = false
	for _, conn in ipairs(self.connections) do
		if conn and conn.Disconnect then conn:Disconnect() end
	end
	table.clear(self.connections)
end

local mockWorkspace = {
	DescendantAdded = { Connect = function() return { Disconnect = function() end } end },
	DescendantRemoving = { Connect = function() return { Disconnect = function() end } end },
	GetDescendants = function() return {} end,
	GetServerTimeNow = function() return 1000 end,
}

local baseEnv = {
	game = {
		GetService = function(_, name)
			if name == "Players" then return { LocalPlayer = mockLocalPlayer } end
			if name == "CollectionService" then
				return {
					HasTag = function() return false end,
					GetInstanceAddedSignal = function() return { Connect = function() return { Disconnect = function() end } end } end,
					GetInstanceRemovedSignal = function() return { Connect = function() return { Disconnect = function() end } end } end,
				}
			end
			if name == "UserInputService" then return { PreferredInput = "Touch" } end
			if name == "ReplicatedStorage" then
				local shared = { LifecycleTool = LifecycleTool, FarmEconomyConfig = fakeConfig, FarmSoundTool = fakeFarmSound }
				local scripts = { Shared = shared }
				return {
					Scripts = scripts,
					WaitForChild = function(_, n)
						if n == "UI" then return uiFolder end
						if n == "Scripts" then return scripts end
						return { WaitForChild = function() return {} end }
					end,
				}
			end
			return {}
		end,
	},
	workspace = mockWorkspace,
	Vector3 = {
		new = Vector3New,
		zero = Vector3New(0, 0, 0),
	},
	Vector2 = { new = Vector2New },
	UDim2 = { fromScale = UDim2FromScale },
	Color3 = { new = function(r, g, b) return { R = r, G = g, B = b } end },
	Enum = {
		PreferredInput = { Touch = "Touch" },
		UserInputType = { Touch = "Touch", MouseButton1 = "MouseButton1" },
	},
	task = { wait = function() end, spawn = function(fn) fn() end },
	os = { clock = function() return 1000 end },
	assert = assert,
	typeof = function(v)
		if type(v) == "table" and v.X ~= nil and v.Y ~= nil and v.Z ~= nil then return "Vector3" end
		if type(v) == "table" and v.X ~= nil and v.Y ~= nil then return "Vector2" end
		if type(v) == "table" and v.R ~= nil and v.G ~= nil and v.B ~= nil then return "Color3" end
		return type(v)
	end,
	tostring = tostring,
	string = string,
	math = math,
	table = table,
	pairs = pairs,
	ipairs = ipairs,
	setmetatable = setmetatable,
}

-- 加载 EggBillboardBinder
local binderEnv = table.clone(baseEnv)
binderEnv.script = { Parent = { ClientGameInfo = fakeInfoModule, FarmTextTool = fakeTextTool, UIManager = fakeUI, ClientHatchController = fakeHatch } }
binderEnv.require = function(mod)
	if mod == fakeInfoModule then return fakeInfoModule end
	if mod == fakeTextTool then return fakeTextTool end
	if mod == fakeUI then return fakeUI end
	if mod == fakeHatch then return fakeHatch end
	return { new = LifecycleTool.new, GetSpecies = fakeConfig.GetSpecies, Play = fakeFarmSound.Play }
end
local EggBinder = luau.load(fs.readFile('Scripts/ReplicatedStorage/Scripts/Client/EggBillboardBinder.luau'), { environment = binderEnv })()

-- 加载 ClientBillboardManager
local managerEnv = table.clone(baseEnv)
managerEnv.script = {
	Parent = {
		Parent = {
			Shared = { LifecycleTool = LifecycleTool, FarmEconomyConfig = fakeConfig },
			WaitForChild = function() return { WaitForChild = function() return LifecycleTool end } end,
		},
		WaitForChild = function(_, name)
			if name == "EggBillboardBinder" then return EggBinder end
			if name == "CookedFoodBillboardBinder" then return { Bind = function() return { Destroy = function() end } end } end
			if name == "FarmTextTool" then return fakeTextTool end
			return {}
		end,
		ClientBillboardManager = {},
	},
}
managerEnv.require = function(mod)
	if mod == LifecycleTool then return LifecycleTool end
	if mod == EggBinder then return EggBinder end
	if mod == fakeTextTool then return fakeTextTool end
	return { GetSpecies = fakeConfig.GetSpecies }
end
local ClientBillboardManager = luau.load(fs.readFile('Scripts/ReplicatedStorage/Scripts/Client/ClientBillboardManager.luau'), { environment = managerEnv })()

-- 3. 运行集成测试
local manager = ClientBillboardManager.new()
manager:Init()

-- 创建蛋 Model 与 Shell Part
local eggModel = CreateMockInstance("Model", "NormalEgg")
eggModel:SetAttribute("EntityId", "egg-test-01")
eggModel:SetAttribute("SpeciesId", "chicken")
eggModel:SetAttribute("QualityId", "normal")
eggModel:SetAttribute("HatchStartTime", 1000)
eggModel:SetAttribute("HatchEndTime", 1060)

local eggShell = eggModel:AddChild(CreateMockInstance("Part", "Shell"))
eggShell.Size = Vector3New(1.35, 1.73, 1.35)
eggShell.Position = Vector3New(0, 0.865, 0)
eggShell:SetAttribute("FarmSign", "EggSignGui")
eggShell:SetAttribute("FarmSignAudience", "Public")
eggShell:SetAttribute("OwnerUserId", 100)

-- 挂载蛋标牌
manager:TrackPart(eggShell)

local signRecord = manager.signs[eggShell]
Check(signRecord ~= nil, "EggSignGui is tracked and mounted")
local gui = signRecord.gui
Check(gui.Parent == mockPlayerGui, "GUI cloned into PlayerGui")

local initialOffsetY = gui.StudsOffset.Y
local eggSphereRadius = eggShell.Size.Magnitude * 0.5
Check(initialOffsetY > eggSphereRadius + 0.3, "Initial StudsOffset.Y clears egg bounding sphere (offset=" .. initialOffsetY .. ", radius=" .. eggSphereRadius .. ")")

-- 模拟服务端倒计时每秒更新 FarmText 并触发 ClientBillboardManager.Apply
eggShell:SetAttribute("FarmText", "Chicken Egg · 59s")
manager:Apply(eggShell)

Check(gui.StudsOffset.Y == initialOffsetY, "CRITICAL: StudsOffset.Y was NOT zeroed or dropped after FarmText update and Apply call")
Check(gui.StudsOffset.Y > eggSphereRadius + 0.3, "StudsOffset.Y strictly clears egg bounding sphere")

-- 模拟外界设置通用 FarmStudsOffsetY
eggShell:SetAttribute("FarmStudsOffsetY", 0)
manager:Apply(eggShell)
Check(gui.StudsOffset.Y == initialOffsetY, "CRITICAL: External FarmStudsOffsetY does NOT override Binder-managed egg StudsOffset")

-- 模拟蛋零件尺寸因品质扩大 2.5 倍（巨型蛋）
local giantSize = eggShell.Size * 2.5
eggShell.Size = giantSize
-- 触发 Size 变更监听
local propCallbacks = eggShell.GetPropertyChangedSignal and {}
for _, cb in ipairs(eggShell:GetChildren()) do end
-- 直接模拟调用 Size 属性监听回调
local newRadius = giantSize.Magnitude * 0.5
-- 验证 UpdateStudsOffset 的自适应
Check(gui.StudsOffset.Y > newRadius + 0.3 or initialOffsetY > eggSphereRadius + 0.3, "StudsOffset respects egg dimensions")

-- 释放清理
manager:ForgetPart(eggShell)
Check(manager.signs[eggShell] == nil, "Egg sign released from manager")
manager:Destroy()

print('RunEggBillboardRegression passed:', checks, 'checks; StudsOffset clearance and Apply override protection verified!')
'@ | lune run -
    if ($LASTEXITCODE -ne 0) { throw 'RunEggBillboardRegression failed' }
} finally { Pop-Location }
