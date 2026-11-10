-- 屏幕布局采样器：在 Studio 客户端插件上下文只读采集真实几何，返回可持久化的 JSON。
--!strict
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local function Vector(value: Vector2): { number }
	return { value.X, value.Y }
end

local function Rectangle(value: Rect): { number }
	return { value.Min.X, value.Min.Y, value.Max.X, value.Max.Y }
end

local function Visible(object: GuiObject): boolean
	local cursor: Instance? = object
	while cursor do
		if cursor:IsA("GuiObject") and not cursor.Visible then return false end
		if cursor:IsA("ScreenGui") and not cursor.Enabled then return false end
		cursor = cursor.Parent
	end
	return object.AbsoluteSize.X > 0 and object.AbsoluteSize.Y > 0
end

-- 使用前改为该项目的实际 ScreenGui 与固定画布名称。
local ScreenName = "GameScreenGui"
local RootName = "MainHudFrame"
local player = assert(Players.LocalPlayer, "Sample requires a running client")
local screen = player.PlayerGui:WaitForChild(ScreenName) :: ScreenGui
local root = screen:WaitForChild(RootName) :: Frame
local scale = (root:WaitForChild("UIScale") :: UIScale).Scale
assert(root.Size == UDim2.fromOffset(1920, 1080), "Canvas must remain 1920x1080")
assert(scale > 0, "Canvas scale is not ready")
local full = GuiService:GetInsetArea(Enum.ScreenInsets.None)
local shift = -full.Min
local function Shift(value: Rect): Rect
	return Rect.new(value.Min + shift, value.Max + shift)
end
local viewport = Shift(full)
local device = Shift(GuiService:GetInsetArea(Enum.ScreenInsets.DeviceSafeInsets))
local topbar = Shift(GuiService:GetInsetArea(Enum.ScreenInsets.TopbarSafeInsets))
local origin = root.AbsolutePosition + shift
local reserved = {}
local function Add(name: string, value: Rect): ()
	if value.Width > 0 and value.Height > 0 then
		table.insert(reserved, { name = name, screenRect = Rectangle(value) })
	end
end
Add("DeviceTop", Rect.new(viewport.Min, Vector2.new(viewport.Max.X, device.Min.Y)))
Add("DeviceBottom", Rect.new(Vector2.new(0, device.Max.Y), viewport.Max))
Add("DeviceLeft", Rect.new(Vector2.zero, Vector2.new(device.Min.X, viewport.Max.Y)))
Add("DeviceRight", Rect.new(Vector2.new(device.Max.X, 0), viewport.Max))
Add("TopLeftCore", Rect.new(device.Min, Vector2.new(topbar.Min.X, topbar.Max.Y)))
Add("TopRightCore", Rect.new(Vector2.new(topbar.Max.X, device.Min.Y), Vector2.new(device.Max.X, topbar.Max.Y)))
local touch = player.PlayerGui:FindFirstChild("TouchGui")
local jump = touch and touch:FindFirstChild("JumpButton", true)
local jumpState = "absent"
if jump and jump:IsA("GuiObject") then
	jumpState = if Visible(jump) then "visible" else "hidden"
	if Visible(jump) then Add("JumpButton", Rect.new(jump.AbsolutePosition + shift, jump.AbsolutePosition + shift + jump.AbsoluteSize)) end
end
local modal = screen:FindFirstChild("ModalButton") :: GuiObject?
return HttpService:JSONEncode({
	source = "Studio running client device simulation",
	viewport = Rectangle(viewport), device = Rectangle(device), topbar = Rectangle(topbar),
	coordinateShift = Vector(shift), origin = Vector(origin), scale = scale,
	logicalSize = { root.Size.X.Offset, root.Size.Y.Offset }, renderedSize = Vector(root.AbsoluteSize),
	screenSize = Vector(screen.AbsoluteSize), jumpState = jumpState, reserved = reserved,
	movementExcluded = true,
	modal = if modal then { size = Vector(modal.AbsoluteSize), origin = Vector(modal.AbsolutePosition + shift), active = modal.Active } else nil,
})
