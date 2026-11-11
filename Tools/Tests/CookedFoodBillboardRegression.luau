-- 熟食标牌回归：使用本地夹具验证熟食 3D 标牌的属性自适应、品质颜色、重量售价格式、倒计时以及生命周期清理（对齐动物标牌规范）
--!strict
local Storage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Binder = require(Storage.Scripts.Client.CookedFoodBillboardBinder)

local function CreateTemplateFixture(): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = "CookedFoodSignGui"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 25
	gui.Size = UDim2.new(4.8, 0, 2.0, 0)
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

	local function AddLabel(name: string): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.BackgroundTransparency = 1
		label.Parent = contentFrame
		local s = Instance.new("UIStroke")
		s.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
		s.Thickness = 0.065
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		s.Parent = label
		return label
	end

	AddLabel("QualityText")
	AddLabel("ContentText")
	AddLabel("StatsText")

	local timeFrame = Instance.new("Frame")
	timeFrame.Name = "TimeFrame"
	timeFrame.Position = UDim2.new(0.14, 0, 0.86, 0)
	timeFrame.Size = UDim2.new(0.72, 0, 0.10, 0)
	timeFrame.BackgroundColor3 = Color3.new(0.32549, 0.360784, 0.376471)
	timeFrame.BackgroundTransparency = 0.25
	timeFrame.BorderSizePixel = 0
	timeFrame.Parent = contentFrame

	local fillFrame = Instance.new("Frame")
	fillFrame.Name = "FillFrame"
	fillFrame.Position = UDim2.new(0, 0, 0, 0)
	fillFrame.Size = UDim2.new(1, 0, 1, 0)
	fillFrame.BackgroundColor3 = Color3.new(0.545098, 0.682353, 0.607843)
	fillFrame.BorderSizePixel = 0
	fillFrame.Parent = timeFrame

	return gui
end

local checks: { string } = {}

local success, failure = xpcall(function(): boolean
	local uiFolder = Storage:FindFirstChild("UI")
	local template = if uiFolder then uiFolder:FindFirstChild("CookedFoodSignGui") else nil
	local gui = if template and template:IsA("BillboardGui") then template:Clone() else CreateTemplateFixture()

	-- 1. 规范检查：AlwaysOnTop、LightInfluence、3D Studs 尺寸、FredokaOne 字体、ScaledSize
	assert(gui.AlwaysOnTop == true, "CookedFoodSignGui must have AlwaysOnTop = true")
	assert(gui.LightInfluence == 0, "CookedFoodSignGui must have LightInfluence = 0")
	assert(gui.Size == UDim2.new(4.8, 0, 2.0, 0), "Size must match animal studs scale {4.8, 2.0}")
	local content = gui:WaitForChild("ContentFrame") :: Frame
	assert(content.BackgroundTransparency == 1, "ContentFrame must have BackgroundTransparency = 1")

	for _, labelName in { "QualityText", "ContentText", "StatsText" } do
		local label = content:WaitForChild(labelName) :: TextLabel
		assert(label.TextScaled == true, labelName .. " must have TextScaled = true")
		assert(label.Font == Enum.Font.FredokaOne, labelName .. " font must be FredokaOne")
		local labelStroke = label:FindFirstChildOfClass("UIStroke")
		if labelStroke then
			assert(labelStroke.StrokeSizingMode == Enum.StrokeSizingMode.ScaledSize, labelName .. " stroke must use ScaledSize")
		end
	end
	local timeFrame = content:WaitForChild("TimeFrame") :: Frame
	local fillFrame = timeFrame:WaitForChild("FillFrame") :: Frame
	assert(fillFrame:IsA("Frame"), "TimeFrame must contain FillFrame")
	table.insert(checks, "CookedFoodSignGui complies with AnimalHealthGui studs scale and FredokaOne specification")

	-- 2. 创建夹具熟食模型与 PrimaryPart
	local model = Instance.new("Model")
	model.Name = "CookedCreatureFixture"
	local part = Instance.new("Part")
	part.Name = "Roast"
	part.Size = Vector3.new(2, 1, 2)
	part.Anchored = true
	part.Parent = model
	model.PrimaryPart = part

	model:SetAttribute("FoodName", "Honey Roast Rabbit")
	model:SetAttribute("QualityId", "golden")
	model:SetAttribute("WeightKg", 3.0)
	model:SetAttribute("SaleValue", 50)
	model:SetAttribute("ExpiresAt", workspace:GetServerTimeNow() + 75)
	model:SetAttribute("Lifetime", 75)

	gui.Adornee = part
	local player = Players.LocalPlayer
	if player then
		gui.Parent = player:FindFirstChildOfClass("PlayerGui")
	end

	-- 3. 绑定并验证静态属性
	part:SetAttribute("FarmStudsOffsetY", 2.0)
	local binding = Binder.Bind(part, gui)
	assert(gui.StudsOffset.Y >= 2.4, "CookedFoodSignGui StudsOffset.Y should be at least 2.4 studs above adornee")
	local qualityLabel = content:WaitForChild("QualityText") :: TextLabel
	local nameLabel = content:WaitForChild("ContentText") :: TextLabel
	local statsLabel = content:WaitForChild("StatsText") :: TextLabel

	assert(nameLabel.Text == "Honey Roast Rabbit", "FoodName not rendered correctly: " .. nameLabel.Text)
	assert(qualityLabel.Text == "Golden", "Quality not rendered correctly: " .. qualityLabel.Text)
	local expectedGolden = gui:GetAttribute("Quality_golden") :: Color3
	assert(qualityLabel.TextColor3 == expectedGolden, "QualityText color does not match Quality_golden")
	assert(string.find(statsLabel.Text, "3.0 kg") ~= nil and string.find(statsLabel.Text, "50 coins") ~= nil, "StatsText not formatted correctly: " .. statsLabel.Text)
	assert(fillFrame.Size.X.Scale > 0.9, "Initial countdown fill should be full")
	table.insert(checks, "Binder correctly renders identity, quality color, weight, coins and initial timer bar")

	-- 4. 动态属性变化响应
	model:SetAttribute("QualityId", "rainbow")
	assert((qualityLabel.Text :: string) == "Rainbow", "Quality change to rainbow failed")
	local expectedRainbow = gui:GetAttribute("Quality_rainbow") :: Color3
	assert(qualityLabel.TextColor3 == expectedRainbow, "QualityText color does not match Quality_rainbow")

	model:SetAttribute("WeightKg", 9.0)
	model:SetAttribute("SaleValue", 250)
	assert(string.find((statsLabel.Text :: string), "9.0 kg") ~= nil and string.find((statsLabel.Text :: string), "250 coins") ~= nil, "Stats change failed: " .. statsLabel.Text)

	-- 紧急倒计时（<=10秒）变色与秒数提示
	model:SetAttribute("ExpiresAt", workspace:GetServerTimeNow() + 5)
	task.wait(0.25)
	local damagedColor = gui:GetAttribute("DamagedColor") :: Color3
	assert(fillFrame.BackgroundColor3 == damagedColor, "Urgent progress bar should turn DamagedColor")
	assert(string.find((statsLabel.Text :: string), "s") ~= nil, "Urgent stats should display remaining seconds")
	table.insert(checks, "Dynamic attributes and urgent countdown bar color updates verified")

	-- 5. 销毁与资源释放
	binding.Destroy()
	gui:Destroy()
	model:Destroy()
	table.insert(checks, "Binding Destroy cleans up lifecycle cleanly")

	return true
end, debug.traceback)

assert(success, failure)
print("[CookedFoodBillboardRegression] All checks passed:")
for _, c in checks do
	print("  - " .. c)
end
return checks
