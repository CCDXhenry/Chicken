-- 编辑器区域模板构建器：幂等预置禁放区和可用区 Frame，仅用于 Edit，不在客户端启动时运行。
--!strict
local function Build(root: Frame): ()
	local function Node(parent: Instance, className: string, name: string): Instance
		local old = parent:FindFirstChild(name)
		assert(not old or old.ClassName == className, "Region node class conflict: " .. name)
		if old then
			return old
		end
		local fresh = Instance.new(className)
		fresh.Name, fresh.Parent = name, parent
		return fresh
	end
	for group, names in
		{
			SystemReservedAreasFrame = {
				"DeviceTopFrame",
				"DeviceBottomFrame",
				"DeviceLeftFrame",
				"DeviceRightFrame",
				"TopLeftCoreFrame",
				"TopRightCoreFrame",
				"MovementInputFrame",
				"JumpButtonFrame",
			},
			UiLayoutRegionsFrame = { "DeviceContentFrame", "TopCenterFrame", "BodyFrame", "LeftInfoFrame", "BottomCenterFrame", "RightActionsFrame" },
		}
	do
		local parent = Node(root, "Frame", group) :: Frame
		parent.AnchorPoint, parent.Position, parent.Size = Vector2.zero, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1)
		parent.BackgroundTransparency, parent.Active, parent.ClipsDescendants = 1, false, false
		for _, name in names do
			local frame = Node(parent, "Frame", name) :: Frame
			frame.AnchorPoint, frame.Position, frame.Size = Vector2.zero, UDim2.fromOffset(0, 0), UDim2.fromOffset(0, 0)
			frame.BackgroundColor3 = if group == "SystemReservedAreasFrame" then Color3.fromRGB(240, 60, 60) else Color3.fromRGB(60, 220, 110)
			frame.BackgroundTransparency, frame.BorderSizePixel, frame.Active, frame.Visible = 0.72, 0, false, false
			frame.ZIndex = 100
			frame:SetAttribute("RegionValid", false)
			local label = Node(frame, "TextLabel", "RegionNameText") :: TextLabel
			label.Size, label.BackgroundTransparency, label.Text = UDim2.fromScale(1, 1), 1, name
			label.TextScaled, label.TextWrapped, label.AutoLocalize, label.Active = true, true, false, false
			label.TextColor3, label.ZIndex = Color3.new(1, 1, 1), 101
		end
	end
	root:SetAttribute("UiRegionsVersion", 1)
end
return Build
