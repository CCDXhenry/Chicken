-- 熟食标牌绑定器：负责驱动地面熟食的品质、重量、售价与留存倒计时渲染（对齐动物标牌风格）
--!strict
local Storage = game:GetService("ReplicatedStorage")
local Shared = Storage:WaitForChild("Scripts"):WaitForChild("Shared")
local Lifecycle = require(Shared:WaitForChild("LifecycleTool"))
local TextTool = require(script.Parent:WaitForChild("FarmTextTool"))
local NumberFormat = require(Shared:WaitForChild("FarmNumberFormat"))

local Binder = {}
export type Binding = { Destroy: () -> () }

function Binder.Bind(part: BasePart, gui: BillboardGui): Binding
	local scope = Lifecycle.new()
	local model = part:FindFirstAncestorOfClass("Model")
	assert(model, "CookedFood must belong to a model")

	local contentFrame = gui:WaitForChild("ContentFrame") :: Frame
	local nameLabel = contentFrame:WaitForChild("ContentText") :: TextLabel
	local qualityLabel = contentFrame:WaitForChild("QualityText") :: TextLabel
	local statsLabel = contentFrame:WaitForChild("StatsText") :: TextLabel
	local timeFrame = contentFrame:WaitForChild("TimeFrame") :: Frame
	local fillFrame = timeFrame:WaitForChild("FillFrame") :: Frame

	local defaultStatsColor = statsLabel.TextColor3
	local healthyColor = gui:GetAttribute("HealthyColor")
	local damagedColor = gui:GetAttribute("DamagedColor")

	local function UpdateOffset(): ()
		local offsetY = part:GetAttribute("FarmStudsOffsetY")
		local heightOffsetY = if typeof(offsetY) == "number" then offsetY else 2.0
		local compensation = gui:GetAttribute("HeightCompensationStuds")
		local compNum = if typeof(compensation) == "number" then compensation else 0.475
		gui.StudsOffset = Vector3.new(0, heightOffsetY + compNum, 0)
	end
	UpdateOffset()

	local function RenderIdentity(): ()
		local foodName = model:GetAttribute("FoodName")
		TextTool.Set(nameLabel, if typeof(foodName) == "string" then foodName else model.Name)

		local qualityId = model:GetAttribute("QualityId")
		local qualityName = if qualityId == "golden" then "Golden" elseif qualityId == "rainbow" then "Rainbow" elseif qualityId == "giant" then "Giant" else "Normal"
		TextTool.Set(qualityLabel, qualityName)
		local qualityColor = gui:GetAttribute("Quality_" .. tostring(qualityId))
		if typeof(qualityColor) == "Color3" then
			qualityLabel.TextColor3 = qualityColor
		end
	end

	local function RenderTimerAndStats(): ()
		local weight = model:GetAttribute("WeightKg")
		local value = model:GetAttribute("SaleValue")
		local weightNum = if typeof(weight) == "number" then weight else 1
		local valueNum = if typeof(value) == "number" then value else 10

		local expiresAt = model:GetAttribute("ExpiresAt")
		local lifetimeAttr = model:GetAttribute("Lifetime")
		local lifetime = if typeof(lifetimeAttr) == "number" and lifetimeAttr > 0 then lifetimeAttr else 75
		local expireTime = if typeof(expiresAt) == "number" then expiresAt else workspace:GetServerTimeNow() + lifetime

		local remaining = math.max(0, expireTime - workspace:GetServerTimeNow())
		local remainingSec = math.ceil(remaining)
		local ratio = math.clamp(remaining / lifetime, 0, 1)

		fillFrame.Size = UDim2.fromScale(ratio, 1)

		local isUrgent = remainingSec <= 10
		if isUrgent and typeof(damagedColor) == "Color3" then
			fillFrame.BackgroundColor3 = damagedColor
			statsLabel.TextColor3 = damagedColor
			statsLabel.Text = string.format("%s · %s coins (%ds)", NumberFormat.Weight(weightNum), NumberFormat.Number(valueNum), remainingSec)
		else
			if typeof(healthyColor) == "Color3" then
				fillFrame.BackgroundColor3 = healthyColor
			end
			statsLabel.TextColor3 = defaultStatsColor
			statsLabel.Text = string.format("%s · %s coins", NumberFormat.Weight(weightNum), NumberFormat.Number(valueNum))
		end
	end

	RenderIdentity()
	RenderTimerAndStats()

	scope:Connect(model:GetAttributeChangedSignal("FoodName"):Connect(RenderIdentity))
	scope:Connect(model:GetAttributeChangedSignal("QualityId"):Connect(RenderIdentity))
	scope:Connect(model:GetAttributeChangedSignal("WeightKg"):Connect(RenderTimerAndStats))
	scope:Connect(model:GetAttributeChangedSignal("SaleValue"):Connect(RenderTimerAndStats))
	scope:Connect(model:GetAttributeChangedSignal("ExpiresAt"):Connect(RenderTimerAndStats))
	scope:Connect(part:GetAttributeChangedSignal("FarmStudsOffsetY"):Connect(UpdateOffset))

	scope:Spawn(function(): ()
		while scope.alive do
			task.wait(0.2)
			if scope.alive then
				RenderTimerAndStats()
			end
		end
	end)

	return {
		Destroy = function(): ()
			scope:Destroy()
			TextTool.Remove(gui)
		end,
	}
end

return Binder
