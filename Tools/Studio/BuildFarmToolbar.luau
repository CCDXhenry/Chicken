-- Studio Edit 工具栏移植：先通过 MCP 导入 RopeJumpBottomButtonsReference.rbxm 到 ReplicatedStorage.UI
-- 直接使用参考实例，保留原版布局与图片；仅适配模型层及农场两槽文案，不改触控模板或道具。
local UI = game:GetService("ReplicatedStorage"):WaitForChild("UI")
local hud = UI:WaitForChild("RoastChickenHUDFrame")
local imported = UI:FindFirstChild("BottomButtonsFrame")
assert(imported and imported:IsA("Frame"), "请先通过 MCP 导入参考 BottomButtonsFrame")
local previous = hud:WaitForChild("BottomButtonsFrame")
local viewportTemplate = previous.WeaponButton.ToolViewport:Clone()
viewportTemplate.WorldModel:ClearAllChildren()
local bottom = imported:Clone()
bottom.Position = UDim2.new(0.5, 0, 1, -100)
bottom.Parent = hud
local template = bottom:WaitForChild("ToolButton")
local icon = template:WaitForChild("ToolIconImage")
local viewport = viewportTemplate
viewport.AnchorPoint = icon.AnchorPoint
viewport.Position = icon.Position
viewport.Size = icon.Size
viewport.ZIndex = icon.ZIndex
local oldScale = viewport:FindFirstChildOfClass("UIScale")
if oldScale then oldScale:Destroy() end
icon.UIScale:Clone().Parent = viewport
viewport.Parent = template
icon:Destroy()
template.QualityImage.Visible = false
template.ToolUsageEffectFrame.Visible = false
template.EquippedImage.Visible = false
for _, item in template:GetDescendants() do
	if item:IsA("TextLabel") then
		item.TextScaled = false
		item.TextWrapped = false
		local size = if item.Name == "KeyCodeText" then 36 elseif item.Name == "ToolUsageEffectText" then 32 else 28
		item.TextSize = size
		item:SetAttribute("DesignTextSize", size)
		item.AutoLocalize = item.Name == "ToolNameText"
	end
	if item:IsA("UIStroke") then
		item.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
		item.Thickness = if item.Parent:IsA("TextLabel") then 0.05 else 0.02
	end
end
for index, name in { "WeaponButton", "CollectorButton" } do
	local button = template:Clone()
	button.Name = name
	button.LayoutOrder = index
	button.Visible = true
	button.KeyCodeText.Text = tostring(index)
	button.ToolNameText.Text = if index == 1 then "Weapon" else "Collector"
	button.ToolLvText.Text = if index == 1 then "Lv.1" else ""
	button.ToolViewport:SetAttribute("ViewDirection", if index == 1 then Vector3.new(-1, 0.7, -1.5) else Vector3.new(1, 0.7, -1.5))
	button.Parent = bottom
end
template.Visible = false
previous:Destroy()
imported:Destroy()
return "Imported reference toolbar: two 132px slots, 18px gap, original textures and interaction scale"
