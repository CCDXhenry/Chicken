-- Studio Edit 构筑器：在 ReplicatedStorage.UI 中创建完全对齐动物标牌（AnimalHealthGui）风格的 CookedFoodSignGui 模板
--!strict
local RunService = game:GetService("RunService")
assert(not RunService:IsRunning(), "Edit only")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

ChangeHistoryService:SetWaypoint("Before CookedFoodSignGui template")

local uiFolder = ReplicatedStorage:FindFirstChild("UI")
if not uiFolder then
	local folder = Instance.new("Folder")
	folder.Name = "UI"
	folder.Parent = ReplicatedStorage
	uiFolder = folder
end

local existing = uiFolder:FindFirstChild("CookedFoodSignGui")
if existing then
	existing:Destroy()
end

local gui = Instance.new("BillboardGui")
gui.Name = "CookedFoodSignGui"
gui.AlwaysOnTop = true
gui.LightInfluence = 0
gui.MaxDistance = 25
gui.Size = UDim2.new(4.8, 0, 2.0, 0)
gui.StudsOffset = Vector3.new(0, 2.475, 0)
gui.ResetOnSpawn = false
gui:SetAttribute("BaseStudsOffset", Vector3.new(0, 0, 0))
gui:SetAttribute("HeightCompensationStuds", 0.475)
gui:SetAttribute("ReferenceHeightStuds", 1.05)
gui:SetAttribute("HealthyColor", Color3.new(0.545098, 0.682353, 0.607843))
gui:SetAttribute("DamagedColor", Color3.new(0.796078, 0.611765, 0.521569))
gui:SetAttribute("Quality_normal", Color3.new(0.823529, 0.819608, 0.788235))
gui:SetAttribute("Quality_golden", Color3.new(0.901961, 0.776471, 0.478431))
gui:SetAttribute("Quality_rainbow", Color3.new(0.764706, 0.670588, 0.85098))
gui:SetAttribute("Quality_giant", Color3.new(0.65098, 0.807843, 0.819608))

local contentFrame = Instance.new("Frame")
contentFrame.Name = "ContentFrame"
contentFrame.AnchorPoint = Vector2.new(0.5, 1)
contentFrame.Position = UDim2.new(0.5, 0, 1, 0)
contentFrame.Size = UDim2.new(1, 0, 1, 0)
contentFrame.BackgroundTransparency = 1
contentFrame.BorderSizePixel = 0
contentFrame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0.12, 0)
corner.Parent = contentFrame

local uiScale = Instance.new("UIScale")
uiScale.Scale = 1
uiScale.Parent = contentFrame

local function CreateAnimalStyleLabel(name: string, pos: UDim2, size: UDim2, text: string, color: Color3, autoLocalize: boolean): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = pos
	label.Size = size
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextColor3 = color
	label.Text = text
	label.AutoLocalize = autoLocalize
	label.BorderSizePixel = 0

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	stroke.Thickness = 0.065
	stroke.Color = Color3.fromRGB(25, 32, 25)
	stroke.Transparency = 0
	stroke.Parent = label

	label.Parent = contentFrame
	return label
end

CreateAnimalStyleLabel("QualityText", UDim2.new(0.08, 0, 0, 0), UDim2.new(0.84, 0, 0.20, 0), "Normal", Color3.new(0.823529, 0.819608, 0.788235), true)
CreateAnimalStyleLabel("ContentText", UDim2.new(0.02, 0, 0.23, 0), UDim2.new(0.96, 0, 0.27, 0), "Roast Chicken", Color3.new(0.952941, 0.941176, 0.905882), true)
CreateAnimalStyleLabel("StatsText", UDim2.new(0.05, 0, 0.54, 0), UDim2.new(0.90, 0, 0.25, 0), "1.0 kg · 10 coins", Color3.fromRGB(255, 218, 92), false)

local timeFrame = Instance.new("Frame")
timeFrame.Name = "TimeFrame"
timeFrame.Position = UDim2.new(0.14, 0, 0.86, 0)
timeFrame.Size = UDim2.new(0.72, 0, 0.10, 0)
timeFrame.BackgroundColor3 = Color3.new(0.32549, 0.360784, 0.376471)
timeFrame.BackgroundTransparency = 0.25
timeFrame.BorderSizePixel = 0
timeFrame.Parent = contentFrame

local timeFrameCorner = Instance.new("UICorner")
timeFrameCorner.CornerRadius = UDim.new(0.5, 0)
timeFrameCorner.Parent = timeFrame

local fillFrame = Instance.new("Frame")
fillFrame.Name = "FillFrame"
fillFrame.Position = UDim2.new(0, 0, 0, 0)
fillFrame.Size = UDim2.new(1, 0, 1, 0)
fillFrame.BackgroundColor3 = Color3.new(0.545098, 0.682353, 0.607843)
fillFrame.BackgroundTransparency = 0
fillFrame.BorderSizePixel = 0
fillFrame.Parent = timeFrame

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0.5, 0)
fillCorner.Parent = fillFrame

gui.Parent = uiFolder
ChangeHistoryService:SetWaypoint("Built CookedFoodSignGui template (aligned with AnimalHealthGui)")
print("[BuildCookedFoodSignGui] 成功在 ReplicatedStorage.UI 创建动物同款 CookedFoodSignGui 模板！")
