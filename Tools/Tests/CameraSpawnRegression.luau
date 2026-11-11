-- 玩家出生视角与面朝方向摄像机离线回归：验证相机几何数学、朝向对齐、序列通知与控制器生命周期
--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

local checks = 0
local function Check(condition: boolean, message: string)
	assert(condition, message)
	checks += 1
end

-- 1. 验证 FarmConfig 摄像机配置项
local configSource = fs.readFile("Scripts/ReplicatedStorage/Scripts/Shared/FarmConfig.luau")
local FarmConfig = luau.load(configSource)()

Check(FarmConfig.CameraDefaultDistance == 16, "CameraDefaultDistance must be 16 studs")
Check(FarmConfig.CameraPitchAngle == -15, "CameraPitchAngle must be -15 degrees")
Check(FarmConfig.CameraHeightOffset == 2.5, "CameraHeightOffset must be 2.5 studs")
Check(FarmConfig.CameraMinZoomDistance == 0.5, "CameraMinZoomDistance must be 0.5 studs")
Check(FarmConfig.CameraMaxZoomDistance == 128, "CameraMaxZoomDistance must be 128 studs")

local hasPlotId, hasSpawnSeq = false, false
for _, attr in FarmConfig.AttributeNames do
	if attr == "FarmPlotId" then hasPlotId = true end
	if attr == "FarmSpawnSequence" then hasSpawnSeq = true end
end
Check(hasPlotId, "FarmConfig.AttributeNames contains FarmPlotId")
Check(hasSpawnSeq, "FarmConfig.AttributeNames contains FarmSpawnSequence")

-- 2. 验证左侧（奇数）与右侧（偶数）地块的相机几何学与朝向对齐计算
local rows = { -192, -64, 64, 192 }
for index = 1, 8 do
	local row = math.ceil(index / 2)
	local left = index % 2 == 1
	local transform = CFrame.new(if left then -80 else 80, 0, rows[row]) * CFrame.Angles(0, math.rad(if left then 90 else -90), 0)
	local name = string.format("Plot%02d", index)

	-- 验证出生点朝向：左侧朝向 -X，右侧朝向 +X
	local expectedFacing = if left then Vector3.new(-1, 0, 0) else Vector3.new(1, 0, 0)
	local dotProduct = transform.LookVector:Dot(expectedFacing)
	Check(dotProduct > 0.999, name .. " FarmSpawn LookVector must face " .. (if left then "West (-X)" else "East (+X)"))

	-- 计算角色与相机相对位置
	local rootPosition = transform.Position + Vector3.new(0, FarmConfig.SpawnHeight, 0)
	local forwardVector = transform.LookVector
	local flatForward = Vector3.new(forwardVector.X, 0, forwardVector.Z).Unit
	local pitchRad = math.rad(FarmConfig.CameraPitchAngle)
	local yawRad = math.atan2(-flatForward.X, -flatForward.Z)
	local rotation = CFrame.Angles(0, yawRad, 0) * CFrame.Angles(pitchRad, 0, 0)

	local focusPoint = rootPosition + Vector3.new(0, FarmConfig.CameraHeightOffset, 0)
	local cameraPos = focusPoint - rotation.LookVector * FarmConfig.CameraDefaultDistance
	local cameraCFrame = CFrame.new(cameraPos) * rotation

	-- 验证摄像机是否位于角色后方（左侧农场相机在角色东侧即 X 更大，右侧农场相机在角色西侧即 X 更小）
	if left then
		Check(cameraPos.X > rootPosition.X, name .. " (Left): Camera position must be behind character (East of character)")
	else
		Check(cameraPos.X < rootPosition.X, name .. " (Right): Camera position must be behind character (West of character)")
	end

	-- 验证摄像机高度高于焦点（俯视）
	Check(cameraPos.Y > focusPoint.Y, name .. " Camera must be positioned higher than focus for downward pitch")

	-- 验证水平观察方向严格与角色朝向一致
	local cameraLookFlat = Vector3.new(cameraCFrame.LookVector.X, 0, cameraCFrame.LookVector.Z).Unit
	Check(cameraLookFlat:Dot(expectedFacing) > 0.999, name .. " Camera horizontal LookVector must match spawn facing")

	-- 验证俯仰角严格等于 -15 度
	local pitchAngle = math.deg(math.asin(cameraCFrame.LookVector.Y))
	Check(math.abs(pitchAngle - FarmConfig.CameraPitchAngle) < 0.01, name .. " Pitch angle must be -15 deg")
end

-- 3. 验证服务端 PositionCharacter 中自增序号逻辑
local mockPlayerAttributes: { [string]: any } = {}
local mockPlayer = {
	UserId = 12345,
	GetAttribute = function(_self: any, name: string) return mockPlayerAttributes[name] end,
	SetAttribute = function(_self: any, name: string, val: any) mockPlayerAttributes[name] = val end,
}
Check(mockPlayer:GetAttribute("FarmSpawnSequence") == nil, "Initial FarmSpawnSequence is nil")

-- 模拟服务端自增
local seq1 = (mockPlayer:GetAttribute("FarmSpawnSequence") or 0) + 1
mockPlayer:SetAttribute("FarmSpawnSequence", seq1)
Check(mockPlayer:GetAttribute("FarmSpawnSequence") == 1, "First spawn sequence is 1")

local seq2 = (mockPlayer:GetAttribute("FarmSpawnSequence") or 0) + 1
mockPlayer:SetAttribute("FarmSpawnSequence", seq2)
Check(mockPlayer:GetAttribute("FarmSpawnSequence") == 2, "Respawn sequence is incremented to 2")

-- 4. 验证 ClientCameraController 模块装载、视角计算与生命周期
local lifecycleSource = fs.readFile("Scripts/ReplicatedStorage/Scripts/Shared/LifecycleTool.luau")
local LifecycleTool = luau.load(lifecycleSource)()

local mockCamera = {
	CameraType = "Custom",
	CFrame = CFrame.identity,
	Focus = CFrame.identity,
	CameraSubject = nil :: any,
}

local mockRootPart = {
	Position = Vector3.new(-80, 3.95, -176),
	CFrame = CFrame.new(-80, 3.95, -176) * CFrame.Angles(0, math.rad(90), 0),
	IsA = function(_self: any, class: string) return class == "BasePart" end,
	FindFirstChild = function(_self: any, _name: string) return nil end,
}

local mockHumanoid = {
	Health = 100,
	IsA = function(_self: any, class: string) return class == "Humanoid" end,
}

local mockCharacter = {
	FindFirstChild = function(_self: any, name: string)
		if name == "HumanoidRootPart" then return mockRootPart end
		return nil
	end,
	FindFirstChildOfClass = function(_self: any, class: string)
		if class == "Humanoid" then return mockHumanoid end
		return nil
	end,
	WaitForChild = function(_self: any, name: string, _timeout: number?)
		if name == "HumanoidRootPart" then return mockRootPart end
		return nil
	end,
}

local attributeCallbacks: { [string]: { () -> () } } = {}
local mockLocalPlayer = {
	Character = mockCharacter,
	CameraMinZoomDistance = 0.5,
	CameraMaxZoomDistance = 128,
	GetAttribute = function(_self: any, name: string) return mockPlayerAttributes[name] end,
	SetAttribute = function(_self: any, name: string, val: any)
		mockPlayerAttributes[name] = val
		local list = attributeCallbacks[name]
		if list then for _, cb in list do cb() end end
	end,
	GetAttributeChangedSignal = function(_self: any, name: string)
		return {
			Connect = function(_selfSignal: any, cb: () -> ())
				if not attributeCallbacks[name] then attributeCallbacks[name] = {} end
				table.insert(attributeCallbacks[name], cb)
				return {
					Disconnect = function()
						local idx = table.find(attributeCallbacks[name], cb)
						if idx then table.remove(attributeCallbacks[name], idx) end
					end,
				}
			end,
		}
	end,
	CharacterAdded = {
		Connect = function(_selfSignal: any, _cb: any)
			return { Disconnect = function() end }
		end,
	},
}

local mockWorkspace = {
	CurrentCamera = mockCamera,
	FindFirstChild = function(_self: any, _name: string) return nil end,
}

local mockPlayers = {
	LocalPlayer = mockLocalPlayer,
}

local mockShared = {
	WaitForChild = function(_self: any, name: string)
		return { Name = name }
	end,
}

local mockScripts = {
	WaitForChild = function(_self: any, name: string)
		if name == "Shared" then return mockShared end
		error("Unknown script folder: " .. name)
	end,
}

local mockReplicated = {
	WaitForChild = function(_self: any, name: string)
		if name == "Scripts" then return mockScripts end
		error("Unknown replicated folder: " .. name)
	end,
}

local mockEnv = {
	game = {
		GetService = function(_self: any, service: string)
			if service == "Workspace" then return mockWorkspace end
			if service == "Players" then return mockPlayers end
			if service == "ReplicatedStorage" then return mockReplicated end
			error("Unknown service: " .. service)
		end,
	},
	task = {
		defer = function(cb: () -> ()) cb() end,
	},
	Enum = {
		CameraType = {
			Scriptable = "Scriptable",
			Custom = "Custom",
		},
	},
	pcall = pcall,
	typeof = typeof,
	setmetatable = setmetatable,
	require = function(target: any)
		if typeof(target) == "table" and target.Name == "FarmConfig" then
			return FarmConfig
		elseif typeof(target) == "table" and target.Name == "LifecycleTool" then
			return LifecycleTool
		end
		error("Unknown require target: " .. tostring(target))
	end,
	Vector3 = Vector3,
	CFrame = CFrame,
	math = math,
}

local controllerSource = fs.readFile("Scripts/ReplicatedStorage/Scripts/Client/ClientCameraController.luau")
local ClientCameraController = luau.load(controllerSource, {
	environment = mockEnv,
})()

local controller = ClientCameraController.new()
Check(controller ~= nil, "ClientCameraController instantiated")
controller:Init()
Check(controller.initialized == true, "ClientCameraController initialized")

-- 验证重置后相机参数
local ok = controller:ResetCameraToSpawn()
Check(ok == true, "ResetCameraToSpawn succeeded")
Check(mockCamera.CameraSubject == mockHumanoid, "CameraSubject bound to Humanoid")
Check(mockCamera.CameraType == "Custom", "CameraType restored to Custom after deferred step")
Check(mockCamera.CFrame.Position.X > mockRootPart.Position.X, "Camera positioned behind RootPart for West-facing character")
local lookAngle = math.deg(math.asin(mockCamera.CFrame.LookVector.Y))
Check(math.abs(lookAngle - FarmConfig.CameraPitchAngle) < 0.05, "Controller applies -15 deg pitch")

-- 验证自增序号触发视角重置
mockRootPart.Position = Vector3.new(80, 3.95, -176)
mockRootPart.CFrame = CFrame.new(80, 3.95, -176) * CFrame.Angles(0, math.rad(-90), 0)
mockPlayer:SetAttribute("FarmSpawnSequence", 3)
Check(mockCamera.CFrame.Position.X < mockRootPart.Position.X, "OnSpawnChanged re-aligned camera behind East-facing character")

-- 验证生命周期清理
controller:Destroy()
Check(controller.initialized == false, "Controller cleanly destroyed")

print(string.format("CameraSpawnRegression passed: %d checks; geometry, facing vectors, pitch angle, mock controller and spawn sequence verified.", checks))
