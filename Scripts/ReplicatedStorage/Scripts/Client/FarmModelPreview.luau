-- 农场模型预览：统一从正式模型源克隆外观并创建客户端相机，不维护独立展示模型
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Preview = {}
local renderedSources = setmetatable({} :: { [ViewportFrame]: Instance }, { __mode = "k" })

local function GetCamera(viewport: ViewportFrame): Camera
	local existing = viewport:FindFirstChildOfClass("Camera")
	if existing then return existing end
	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.Parent = viewport
	return camera
end

function Preview.Render(viewport: ViewportFrame, source: Instance): ()
	if renderedSources[viewport] == source then return end
	local world = viewport:FindFirstChildOfClass("WorldModel")
	assert(world, "模型预览模板缺少 WorldModel")
	local camera = GetCamera(viewport)
	local fieldOfView = viewport:GetAttribute("PreviewFieldOfView")
	local direction = viewport:GetAttribute("ViewDirection")
	assert(typeof(fieldOfView) == "number" and typeof(direction) == "Vector3", "预览模板缺少相机参数")
	camera.FieldOfView = fieldOfView
	world:ClearAllChildren()
	local clone = source:Clone()
	for _, item in clone:GetDescendants() do
		if item:IsA("BasePart") then item.Anchored = true; item.CanCollide = false; item.CanTouch = false; item.CanQuery = false end
		if item:IsA("LuaSourceContainer") then item:Destroy() end
	end
	clone.Parent = world
	local minimum = Vector3.new(math.huge, math.huge, math.huge)
	local maximum = -minimum
	for _, item in clone:GetDescendants() do
		if item:IsA("BasePart") then
			for x = -1, 1, 2 do for y = -1, 1, 2 do for z = -1, 1, 2 do
				local corner = item.CFrame:PointToWorldSpace(item.Size * Vector3.new(x, y, z) * 0.5)
				minimum = minimum:Min(corner); maximum = maximum:Max(corner)
			end end end
		end
	end
	local center = (minimum + maximum) * 0.5
	local radius = (maximum - minimum).Magnitude * 0.5
	local aspect = viewport.Size.X.Offset / math.max(1, viewport.Size.Y.Offset)
	local halfAngle = math.atan(math.tan(math.rad(fieldOfView * 0.5)) * math.min(1, aspect))
	local distance = radius / math.sin(halfAngle) * 1.12
	camera.CFrame = CFrame.lookAt(center + direction.Unit * distance, center)
	viewport.CurrentCamera = camera
	renderedSources[viewport] = source
end

function Preview.RenderWeapon(viewport: ViewportFrame, tier: number): ()
	local source = ReplicatedStorage:WaitForChild("Models"):WaitForChild("Weapons"):WaitForChild("ZapWeapon_T" .. tostring(tier))
	Preview.Render(viewport, source)
end

return Preview
