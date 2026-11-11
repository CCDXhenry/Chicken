import sys
import os
from pathlib import Path

sys.path.append(r'C:\Users\herong\.gemini\config\skills\roblox-studio-mcp\scripts')
from fast_connect import RobloxMCPClient

client = RobloxMCPClient()
studios = client.list_studios()
if not studios:
    print("No active studios found")
    sys.exit(1)

sid = studios[0]['id']

code = """
local rs = game:GetService("ReplicatedStorage")
local ui = rs:WaitForChild("UI")
local hud = ui:WaitForChild("RoastChickenHUDFrame")

-- 1. 移除旧的 StatusFrame 和 EquipmentButton
local oldStatus = hud:FindFirstChild("StatusFrame")
if oldStatus then oldStatus:Destroy() end

local oldEquipment = hud:FindFirstChild("EquipmentButton")
if oldEquipment then oldEquipment:Destroy() end

local oldLeft = hud:FindFirstChild("LeftActionsFrame")
if oldLeft then oldLeft:Destroy() end

local oldRight = hud:FindFirstChild("RightActionsFrame")
if oldRight then oldRight:Destroy() end

local oldStats = hud:FindFirstChild("StatsCardFrame")
if oldStats then oldStats:Destroy() end

local oldTopPill = hud:FindFirstChild("TopStatusPill")
if oldTopPill then oldTopPill:Destroy() end

-- 辅助函数：创建 ScaledSize UIStroke
local function addStroke(parent, color, thickness, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Thickness = thickness or 0.04
    stroke.Transparency = transparency or 0
    stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
    stroke.Parent = parent
    return stroke
end

local function addCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
    return corner
end

local function addScale(parent)
    local scale = Instance.new("UIScale")
    scale.Scale = 1
    scale.Parent = parent
    return scale
end

-- 2. 构建 TopStatusPill
local topPill = Instance.new("Frame")
topPill.Name = "TopStatusPill"
topPill.Position = UDim2.new(0.5, 0, 0, 32)
topPill.AnchorPoint = Vector2.new(0.5, 0)
topPill.Size = UDim2.fromOffset(480, 44)
topPill.BackgroundColor3 = Color3.fromRGB(24, 28, 24)
topPill.BackgroundTransparency = 0.35
addCorner(topPill, 22)
addStroke(topPill, Color3.fromRGB(255, 255, 255), 0.02, 0.8)

local stockText = Instance.new("TextLabel")
stockText.Name = "StockText"
stockText.Position = UDim2.fromScale(0.5, 0.5)
stockText.AnchorPoint = Vector2.new(0.5, 0.5)
stockText.Size = UDim2.new(1, -24, 1, -8)
stockText.BackgroundTransparency = 1
stockText.Font = Enum.Font.FredokaOne
stockText.TextColor3 = Color3.fromRGB(245, 245, 245)
stockText.TextSize = 22
stockText.Text = "等待 0 · 打包 0 · 预计 0"
stockText.TextScaled = false
stockText:SetAttribute("DesignTextSize", 22)
stockText.Parent = topPill
topPill.Parent = hud

-- 3. 构建 LeftActionsFrame (商店与索引)
local leftFrame = Instance.new("Frame")
leftFrame.Name = "LeftActionsFrame"
leftFrame.Position = UDim2.fromOffset(48, 360)
leftFrame.Size = UDim2.fromOffset(230, 180)
leftFrame.BackgroundTransparency = 1

local leftLayout = Instance.new("UIListLayout")
leftLayout.FillDirection = Enum.FillDirection.Vertical
leftLayout.Padding = UDim.new(0, 16)
leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
leftLayout.Parent = leftFrame

-- 商店按钮
local shopBtn = Instance.new("ImageButton")
shopBtn.Name = "ShopButton"
shopBtn.LayoutOrder = 1
shopBtn.Size = UDim2.fromOffset(210, 72)
shopBtn.BackgroundColor3 = Color3.fromRGB(76, 217, 100)
shopBtn.Image = ""
shopBtn.AutoButtonColor = true
shopBtn:SetAttribute("HasInteractionEffect", true)
addCorner(shopBtn, 18)
addStroke(shopBtn, Color3.fromRGB(35, 140, 55), 0.04)
addScale(shopBtn)

local shopIcon = Instance.new("ImageLabel")
shopIcon.Name = "IconImage"
shopIcon.Position = UDim2.new(0, 14, 0.5, 0)
shopIcon.AnchorPoint = Vector2.new(0, 0.5)
shopIcon.Size = UDim2.fromOffset(46, 46)
shopIcon.BackgroundTransparency = 1
shopIcon.Image = "rbxthumb://type=Asset&id=125831873235464&w=420&h=420"
shopIcon.ScaleType = Enum.ScaleType.Fit
shopIcon.Parent = shopBtn

local shopText = Instance.new("TextLabel")
shopText.Name = "ContentText"
shopText.Position = UDim2.new(0, 68, 0.5, 0)
shopText.AnchorPoint = Vector2.new(0, 0.5)
shopText.Size = UDim2.fromOffset(110, 46)
shopText.BackgroundTransparency = 1
shopText.Font = Enum.Font.FredokaOne
shopText.TextColor3 = Color3.fromRGB(255, 255, 255)
shopText.TextSize = 32
shopText.Text = "商店"
shopText.TextXAlignment = Enum.TextXAlignment.Left
shopText.TextScaled = false
shopText:SetAttribute("DesignTextSize", 32)
addStroke(shopText, Color3.fromRGB(20, 90, 35), 0.05)
shopText.Parent = shopBtn

local shopBadge = Instance.new("Frame")
shopBadge.Name = "BadgeFrame"
shopBadge.Position = UDim2.new(1, -8, 0, 4)
shopBadge.AnchorPoint = Vector2.new(1, 0)
shopBadge.Size = UDim2.fromOffset(24, 24)
shopBadge.BackgroundColor3 = Color3.fromRGB(235, 75, 75)
addCorner(shopBadge, 12)
addStroke(shopBadge, Color3.fromRGB(255, 255, 255), 0.08)

local shopBadgeText = Instance.new("TextLabel")
shopBadgeText.Name = "BadgeText"
shopBadgeText.Size = UDim2.fromScale(1, 1)
shopBadgeText.BackgroundTransparency = 1
shopBadgeText.Font = Enum.Font.FredokaOne
shopBadgeText.TextColor3 = Color3.fromRGB(255, 255, 255)
shopBadgeText.TextSize = 16
shopBadgeText.Text = "1"
shopBadgeText.Parent = shopBadge
shopBadge.Parent = shopBtn
shopBtn.Parent = leftFrame

-- 索引按钮
local indexBtn = Instance.new("ImageButton")
indexBtn.Name = "IndexButton"
indexBtn.LayoutOrder = 2
indexBtn.Size = UDim2.fromOffset(210, 72)
indexBtn.BackgroundColor3 = Color3.fromRGB(0, 174, 239)
indexBtn.Image = ""
indexBtn.AutoButtonColor = true
indexBtn:SetAttribute("HasInteractionEffect", true)
addCorner(indexBtn, 18)
addStroke(indexBtn, Color3.fromRGB(0, 110, 185), 0.04)
addScale(indexBtn)

local indexIcon = Instance.new("ImageLabel")
indexIcon.Name = "IconImage"
indexIcon.Position = UDim2.new(0, 14, 0.5, 0)
indexIcon.AnchorPoint = Vector2.new(0, 0.5)
indexIcon.Size = UDim2.fromOffset(46, 46)
indexIcon.BackgroundTransparency = 1
indexIcon.Image = "rbxthumb://type=Asset&id=96903664405321&w=420&h=420"
indexIcon.ScaleType = Enum.ScaleType.Fit
indexIcon.Parent = indexBtn

local indexText = Instance.new("TextLabel")
indexText.Name = "ContentText"
indexText.Position = UDim2.new(0, 68, 0.5, 0)
indexText.AnchorPoint = Vector2.new(0, 0.5)
indexText.Size = UDim2.fromOffset(110, 46)
indexText.BackgroundTransparency = 1
indexText.Font = Enum.Font.FredokaOne
indexText.TextColor3 = Color3.fromRGB(255, 255, 255)
indexText.TextSize = 32
indexText.Text = "索引"
indexText.TextXAlignment = Enum.TextXAlignment.Left
indexText.TextScaled = false
indexText:SetAttribute("DesignTextSize", 32)
addStroke(indexText, Color3.fromRGB(0, 75, 140), 0.05)
indexText.Parent = indexBtn

local indexBadge = Instance.new("Frame")
indexBadge.Name = "BadgeFrame"
indexBadge.Position = UDim2.new(1, -8, 0, 4)
indexBadge.AnchorPoint = Vector2.new(1, 0)
indexBadge.Size = UDim2.fromOffset(24, 24)
indexBadge.BackgroundColor3 = Color3.fromRGB(235, 75, 75)
addCorner(indexBadge, 12)
addStroke(indexBadge, Color3.fromRGB(255, 255, 255), 0.08)

local indexBadgeText = Instance.new("TextLabel")
indexBadgeText.Name = "BadgeText"
indexBadgeText.Size = UDim2.fromScale(1, 1)
indexBadgeText.BackgroundTransparency = 1
indexBadgeText.Font = Enum.Font.FredokaOne
indexBadgeText.TextColor3 = Color3.fromRGB(255, 255, 255)
indexBadgeText.TextSize = 16
indexBadgeText.Text = "1"
indexBadgeText.Parent = indexBadge
indexBadge.Parent = indexBtn
indexBtn.Parent = leftFrame
leftFrame.Parent = hud

-- 4. 构建 RightActionsFrame (蛋与装备)
local rightFrame = Instance.new("Frame")
rightFrame.Name = "RightActionsFrame"
rightFrame.Position = UDim2.fromOffset(1796, 360)
rightFrame.Size = UDim2.fromOffset(92, 200)
rightFrame.BackgroundTransparency = 1

local rightLayout = Instance.new("UIListLayout")
rightLayout.FillDirection = Enum.FillDirection.Vertical
rightLayout.Padding = UDim.new(0, 16)
rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
rightLayout.Parent = rightFrame

-- 蛋按钮
local eggBtn = Instance.new("ImageButton")
eggBtn.Name = "EggButton"
eggBtn.LayoutOrder = 1
eggBtn.Size = UDim2.fromOffset(80, 80)
eggBtn.BackgroundColor3 = Color3.fromRGB(235, 77, 75)
eggBtn.Image = ""
eggBtn.AutoButtonColor = true
eggBtn:SetAttribute("HasInteractionEffect", true)
addCorner(eggBtn, 18)
addStroke(eggBtn, Color3.fromRGB(70, 20, 20), 0.04)
addScale(eggBtn)

local eggIcon = Instance.new("ImageLabel")
eggIcon.Name = "IconImage"
eggIcon.Position = UDim2.fromScale(0.5, 0.5)
eggIcon.AnchorPoint = Vector2.new(0.5, 0.5)
eggIcon.Size = UDim2.fromOffset(56, 56)
eggIcon.BackgroundTransparency = 1
eggIcon.Image = "rbxthumb://type=Asset&id=136763459729356&w=420&h=420"
eggIcon.ScaleType = Enum.ScaleType.Fit
eggIcon.Parent = eggBtn
eggBtn.Parent = rightFrame

-- 装备按钮
local equipBtn = Instance.new("ImageButton")
equipBtn.Name = "EquipmentButton"
equipBtn.LayoutOrder = 2
equipBtn.Size = UDim2.fromOffset(80, 80)
equipBtn.BackgroundColor3 = Color3.fromRGB(243, 156, 18)
equipBtn.Image = ""
equipBtn.AutoButtonColor = true
equipBtn:SetAttribute("HasInteractionEffect", true)
addCorner(equipBtn, 18)
addStroke(equipBtn, Color3.fromRGB(80, 50, 10), 0.04)
addScale(equipBtn)

local equipIcon = Instance.new("ImageLabel")
equipIcon.Name = "IconImage"
equipIcon.Position = UDim2.fromScale(0.5, 0.5)
equipIcon.AnchorPoint = Vector2.new(0.5, 0.5)
equipIcon.Size = UDim2.fromOffset(56, 56)
equipIcon.BackgroundTransparency = 1
equipIcon.Image = "rbxthumb://type=Asset&id=131128360815313&w=420&h=420"
equipIcon.ScaleType = Enum.ScaleType.Fit
equipIcon.Parent = equipBtn
equipBtn.Parent = rightFrame
rightFrame.Parent = hud

-- 5. 构建 StatsCardFrame (左下角背筐与金币)
local statsFrame = Instance.new("Frame")
statsFrame.Name = "StatsCardFrame"
statsFrame.Position = UDim2.fromOffset(48, 860)
statsFrame.Size = UDim2.fromOffset(420, 140)
statsFrame.BackgroundTransparency = 1

-- 背筐行
local basketRow = Instance.new("Frame")
basketRow.Name = "BasketRow"
basketRow.Position = UDim2.fromOffset(0, 0)
basketRow.Size = UDim2.fromOffset(400, 56)
basketRow.BackgroundTransparency = 1

local basketIcon = Instance.new("ImageLabel")
basketIcon.Name = "BasketIcon"
basketIcon.Position = UDim2.new(0, 0, 0.5, 0)
basketIcon.AnchorPoint = Vector2.new(0, 0.5)
basketIcon.Size = UDim2.fromOffset(50, 50)
basketIcon.BackgroundTransparency = 1
basketIcon.Image = "rbxthumb://type=Asset&id=70658055348739&w=420&h=420"
basketIcon.ScaleType = Enum.ScaleType.Fit
basketIcon.Parent = basketRow

local basketText = Instance.new("TextLabel")
basketText.Name = "BasketText"
basketText.Position = UDim2.new(0, 62, 0.5, 0)
basketText.AnchorPoint = Vector2.new(0, 0.5)
basketText.Size = UDim2.fromOffset(330, 52)
basketText.BackgroundTransparency = 1
basketText.Font = Enum.Font.FredokaOne
basketText.TextColor3 = Color3.fromRGB(255, 255, 255)
basketText.TextSize = 34
basketText.Text = "0 / 12 kg"
basketText.TextXAlignment = Enum.TextXAlignment.Left
basketText.TextScaled = false
basketText:SetAttribute("DesignTextSize", 34)
addStroke(basketText, Color3.fromRGB(20, 25, 20), 0.06)
basketText.Parent = basketRow
basketRow.Parent = statsFrame

-- 金币行
local coinRow = Instance.new("Frame")
coinRow.Name = "CoinRow"
coinRow.Position = UDim2.fromOffset(0, 64)
coinRow.Size = UDim2.fromOffset(400, 68)
coinRow.BackgroundTransparency = 1

local coinIcon = Instance.new("ImageLabel")
coinIcon.Name = "CoinIcon"
coinIcon.Position = UDim2.new(0, 0, 0.5, 0)
coinIcon.AnchorPoint = Vector2.new(0, 0.5)
coinIcon.Size = UDim2.fromOffset(60, 60)
coinIcon.BackgroundTransparency = 1
coinIcon.Image = "rbxthumb://type=Asset&id=127017022836974&w=420&h=420"
coinIcon.ScaleType = Enum.ScaleType.Fit
coinIcon.Parent = coinRow

local coinText = Instance.new("TextLabel")
coinText.Name = "CoinText"
coinText.Position = UDim2.new(0, 72, 0.5, 0)
coinText.AnchorPoint = Vector2.new(0, 0.5)
coinText.Size = UDim2.fromOffset(320, 64)
coinText.BackgroundTransparency = 1
coinText.Font = Enum.Font.FredokaOne
coinText.TextColor3 = Color3.fromRGB(255, 215, 0)
coinText.TextSize = 46
coinText.Text = "$0"
coinText.TextXAlignment = Enum.TextXAlignment.Left
coinText.TextScaled = false
coinText:SetAttribute("DesignTextSize", 46)
addStroke(coinText, Color3.fromRGB(20, 20, 20), 0.06)
coinText.Parent = coinRow
coinRow.Parent = statsFrame
statsFrame.Parent = hud

return "SUCCESS"
"""

res = client.execute_luau(code, datamodel_type="Edit", studio_id=sid)
print(res)
client.close()
