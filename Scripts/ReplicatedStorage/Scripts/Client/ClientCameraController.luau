-- 客户端摄像机控制器：负责出生与重生时的视距、俯仰角及面朝方向自适应重置
--!strict
local workspace = game:GetService("Workspace")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

local sharedScripts = replicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local Paths = require(sharedScripts:WaitForChild("FarmScenePaths"))
local FarmConfig = require(sharedScripts:WaitForChild("FarmConfig"))
local LifecycleTool = require(sharedScripts:WaitForChild("LifecycleTool"))

local ClientCameraController = {}
ClientCameraController.__index = ClientCameraController

export type ClientCameraController = typeof(setmetatable(
	{} :: {
		player: Player,
		scope: LifecycleTool.Lifecycle?,
		initialized: boolean,
		lastSequence: number,
	},
	ClientCameraController
))

function ClientCameraController.new(): ClientCameraController
	local self = setmetatable({
		player = players.LocalPlayer :: Player,
		initialized = false,
		lastSequence = -1,
	}, ClientCameraController)
	return self
end

function ClientCameraController.Init(self: ClientCameraController): ()
	if self.initialized then
		return
	end
	self.initialized = true
	local scope = LifecycleTool.new()
	self.scope = scope

	local function OnSpawnChanged(): ()
		local seq = self.player:GetAttribute("FarmSpawnSequence")
		if typeof(seq) == "number" and seq ~= self.lastSequence then
			self.lastSequence = seq
			self:ResetCameraToSpawn()
		end
	end

	local function OnCharacterAdded(character: Model): ()
		task.defer(function()
			if not self.initialized or self.player.Character ~= character then
				return
			end
			local rootPart = character:WaitForChild("HumanoidRootPart", FarmConfig.CharacterRootWait)
			if rootPart and self.player.Character == character then
				self:ResetCameraToSpawn()
			end
		end)
	end

	scope:Connect(self.player:GetAttributeChangedSignal("FarmSpawnSequence"):Connect(OnSpawnChanged))
	scope:Connect(self.player.CharacterAdded:Connect(OnCharacterAdded))

	local currentSeq = self.player:GetAttribute("FarmSpawnSequence")
	if typeof(currentSeq) == "number" then
		self.lastSequence = currentSeq
		self:ResetCameraToSpawn()
	elseif self.player.Character then
		OnCharacterAdded(self.player.Character)
	end
end

function ClientCameraController.ResetCameraToSpawn(self: ClientCameraController): boolean
	local camera = workspace.CurrentCamera
	local character = self.player.Character
	if not camera or not character then
		return false
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return false
	end

	local forwardVector = rootPart.CFrame.LookVector
	local plotId = self.player:GetAttribute("FarmPlotId")
	if typeof(plotId) == "string" then
		local farms = workspace:FindFirstChild("PersonalFarms")
		local farm = if farms then farms:FindFirstChild(plotId) else nil
		local spawn = if farm then Paths.Find(farm, "FarmSpawn") else nil
		if spawn and spawn:IsA("BasePart") then
			forwardVector = spawn.CFrame.LookVector
		end
	end

	local flatForward = Vector3.new(forwardVector.X, 0, forwardVector.Z)
	if flatForward.Magnitude < 0.001 then
		flatForward = -Vector3.zAxis
	else
		flatForward = flatForward.Unit
	end

	local pitchRad = math.rad(FarmConfig.CameraPitchAngle)
	local yawRad = math.atan2(-flatForward.X, -flatForward.Z)
	local rotation = CFrame.Angles(0, yawRad, 0) * CFrame.Angles(pitchRad, 0, 0)

	local focusPoint = rootPart.Position + Vector3.new(0, FarmConfig.CameraHeightOffset, 0)
	local cameraPos = focusPoint - rotation.LookVector * FarmConfig.CameraDefaultDistance

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(cameraPos) * rotation
	camera.Focus = CFrame.new(focusPoint)
	camera.CameraSubject = humanoid

	pcall(function()
		self.player.CameraMinZoomDistance = FarmConfig.CameraDefaultDistance
		self.player.CameraMaxZoomDistance = FarmConfig.CameraDefaultDistance
	end)

	task.defer(function()
		if camera and camera.CameraType == Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Custom
		end
		pcall(function()
			self.player.CameraMinZoomDistance = FarmConfig.CameraMinZoomDistance
			self.player.CameraMaxZoomDistance = FarmConfig.CameraMaxZoomDistance
		end)
	end)

	return true
end

function ClientCameraController.Destroy(self: ClientCameraController): ()
	if not self.initialized then
		return
	end
	self.initialized = false
	if self.scope then
		self.scope:Destroy()
		self.scope = nil
	end
end

return ClientCameraController
