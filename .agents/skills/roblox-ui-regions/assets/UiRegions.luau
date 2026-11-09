-- 屏幕区域机制：统一系统占用矩形、布局坐标转换、预置 Frame 更新和事件生命周期。
--!strict
local Regions = {}
export type Area = { Name: string, Rect: Rect, Valid: boolean }
export type Snapshot = {
	Viewport: Rect,
	Device: Rect,
	Topbar: Rect,
	Origin: Vector2,
	Scale: number,
	Movement: Rect?,
	Jump: Rect?,
}
export type Connection = { Disconnect: (Connection) -> () }
export type Signal = { Connect: (Signal, () -> ()) -> Connection }
export type Options = {
	Root: Frame,
	GetScale: (() -> number)?,
	FindControls: (() -> (GuiObject?, GuiObject?))?,
	ReadSnapshot: (() -> Snapshot)?,
	Observe: ((() -> ()) -> () -> ())?,
}
export type Controller = {
	Changed: Signal,
	GetReservedRects: (Controller) -> { Area },
	GetRegion: (Controller, string) -> Area?,
	IntersectsReserved: (Controller, Rect) -> boolean,
	SetDebugVisible: (Controller, boolean) -> (),
	Refresh: (Controller) -> (),
	Destroy: (Controller) -> (),
}
local ReservedNames = {
	"DeviceTopFrame",
	"DeviceBottomFrame",
	"DeviceLeftFrame",
	"DeviceRightFrame",
	"TopLeftCoreFrame",
	"TopRightCoreFrame",
	"MovementInputFrame",
	"JumpButtonFrame",
}
local RegionNames = { "DeviceContentFrame", "TopCenterFrame", "BodyFrame", "LeftInfoFrame", "BottomCenterFrame", "RightActionsFrame" }

local function MakeRect(x1: number, y1: number, x2: number, y2: number): Rect
	return Rect.new(x1, y1, math.max(x1, x2), math.max(y1, y2))
end
function Regions.Intersects(a: Rect, b: Rect): boolean
	return a.Width > 0 and a.Height > 0 and b.Width > 0 and b.Height > 0 and a.Min.X < b.Max.X and b.Min.X < a.Max.X and a.Min.Y < b.Max.Y and b.Min.Y < a.Max.Y
end
function Regions.Clip(a: Rect, b: Rect): Rect
	local x, y = math.clamp(a.Min.X, b.Min.X, b.Max.X), math.clamp(a.Min.Y, b.Min.Y, b.Max.Y)
	return MakeRect(x, y, math.min(a.Max.X, b.Max.X), math.min(a.Max.Y, b.Max.Y))
end
function Regions.ToLocal(rect: Rect, origin: Vector2, scale: number): Rect
	assert(scale > 0, "Region scale must be positive")
	return Rect.new((rect.Min - origin) / scale, (rect.Max - origin) / scale)
end

-- 输入与输出均为屏幕像素；布局规则不依赖项目设计分辨率。
function Regions.Compute(snapshot: Snapshot): ({ [string]: Area }, { [string]: Area })
	local v, d = snapshot.Viewport, Regions.Clip(snapshot.Device, snapshot.Viewport)
	local top = Regions.Clip(snapshot.Topbar, d)
	local reserved: { [string]: Area } = {}
	local available: { [string]: Area } = {}
	local function Put(target: { [string]: Area }, name: string, rect: Rect?): ()
		local value = if rect then Regions.Clip(rect, v) else Rect.new(0, 0, 0, 0)
		target[name] = { Name = name, Rect = value, Valid = value.Width > 0 and value.Height > 0 }
	end
	Put(reserved, "DeviceTopFrame", MakeRect(v.Min.X, v.Min.Y, v.Max.X, d.Min.Y))
	Put(reserved, "DeviceBottomFrame", MakeRect(v.Min.X, d.Max.Y, v.Max.X, v.Max.Y))
	Put(reserved, "DeviceLeftFrame", MakeRect(v.Min.X, d.Min.Y, d.Min.X, d.Max.Y))
	Put(reserved, "DeviceRightFrame", MakeRect(d.Max.X, d.Min.Y, v.Max.X, d.Max.Y))
	Put(reserved, "TopLeftCoreFrame", MakeRect(d.Min.X, d.Min.Y, top.Min.X, top.Max.Y))
	Put(reserved, "TopRightCoreFrame", MakeRect(top.Max.X, d.Min.Y, d.Max.X, top.Max.Y))
	Put(reserved, "MovementInputFrame", if snapshot.Movement then Regions.Clip(snapshot.Movement, d) else nil)
	Put(reserved, "JumpButtonFrame", if snapshot.Jump then Regions.Clip(snapshot.Jump, d) else nil)
	Put(available, "DeviceContentFrame", d)
	Put(available, "TopCenterFrame", top)
	Put(available, "BodyFrame", MakeRect(d.Min.X, top.Max.Y, d.Max.X, d.Max.Y))
	local move, jump = reserved.MovementInputFrame, reserved.JumpButtonFrame
	Put(
		available,
		"LeftInfoFrame",
		MakeRect(d.Min.X, top.Max.Y, if move.Valid then move.Rect.Max.X else d.Max.X, if move.Valid then move.Rect.Min.Y else d.Max.Y)
	)
	local left = if move.Valid then move.Rect.Max.X else d.Min.X
	local right = if jump.Valid then jump.Rect.Min.X else d.Max.X
	Put(available, "BottomCenterFrame", MakeRect(left, top.Max.Y, right, d.Max.Y))
	Put(
		available,
		"RightActionsFrame",
		MakeRect(if move.Valid then move.Rect.Max.X else d.Min.X, top.Max.Y, d.Max.X, if jump.Valid then jump.Rect.Min.Y else d.Max.Y)
	)
	return reserved, available
end

local function Visible(object: GuiObject): boolean
	local cursor: Instance? = object
	while cursor do
		if cursor:IsA("GuiObject") and not cursor.Visible then
			return false
		end
		if cursor:IsA("ScreenGui") and not cursor.Enabled then
			return false
		end
		cursor = cursor.Parent
	end
	return object.AbsoluteSize.X > 0 and object.AbsoluteSize.Y > 0
end

function Regions.Bind(options: Options): Controller
	local root = options.Root
	local reservedRoot = assert(root:FindFirstChild("SystemReservedAreasFrame"), "Missing Edit reserved areas") :: Frame
	local regionRoot = assert(root:FindFirstChild("UiLayoutRegionsFrame"), "Missing Edit layout regions") :: Frame
	local listeners: { [() -> ()]: boolean } = {}
	local reserved: { [string]: Area } = {}
	local available: { [string]: Area } = {}
	local destroyed, queued, debugVisible = false, false, false
	local lastOrigin: Vector2? = nil
	local lastScale: number? = nil
	local connections: { RBXScriptConnection } = {}
	local watched: { RBXScriptConnection } = {}
	local cameraConnection: RBXScriptConnection? = nil
	local stopObserve: (() -> ())? = nil
	local readSnapshot = options.ReadSnapshot
	local controller: Controller
	local function Schedule(): ()
		if destroyed or queued then
			return
		end
		queued = true
		task.defer(function(): ()
			queued = false
			if not destroyed then
				controller:Refresh()
			end
		end)
	end
	if not readSnapshot then
		local gui = game:GetService("GuiService")
		local input = game:GetService("UserInputService")
		local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
		local function FindControls(): (GuiObject?, GuiObject?)
			if options.FindControls then
				return options.FindControls()
			end
			local touch = playerGui:FindFirstChild("TouchGui")
			local controlRoot = if touch then touch:FindFirstChild("TouchControlFrame") else nil
			local movement: GuiObject? = nil
			local jump: GuiObject? = nil
			if controlRoot then
				for _, name in { "DynamicThumbstickFrame", "ThumbstickFrame", "DPadFrame" } do
					local node = controlRoot:FindFirstChild(name)
					if node and node:IsA("GuiObject") and Visible(node) then
						movement = node
						break
					end
				end
				local node = controlRoot:FindFirstChild("JumpButton")
				if node and node:IsA("GuiObject") and Visible(node) then
					jump = node
				end
			end
			return movement, jump
		end
		readSnapshot = function(): Snapshot
			local full = gui:GetInsetArea(Enum.ScreenInsets.None)
			local shift = -full.Min
			local function Shift(rect: Rect): Rect
				return Rect.new(rect.Min + shift, rect.Max + shift)
			end
			local movement, jump = FindControls()
			local function Bounds(node: GuiObject?): Rect?
				if node and Visible(node) then
					return Rect.new(node.AbsolutePosition + shift, node.AbsolutePosition + shift + node.AbsoluteSize)
				end
				return nil
			end
			local scale = if options.GetScale then options.GetScale() else root.AbsoluteSize.X / root.Size.X.Offset
			return {
				Viewport = Shift(full),
				Device = Shift(gui:GetInsetArea(Enum.ScreenInsets.DeviceSafeInsets)),
				Topbar = Shift(gui:GetInsetArea(Enum.ScreenInsets.TopbarSafeInsets)),
				Origin = root.AbsolutePosition + shift,
				Scale = scale,
				Movement = Bounds(movement),
				Jump = Bounds(jump),
			}
		end
		local function Rewatch(): ()
			for _, c in watched do
				c:Disconnect()
			end
			table.clear(watched)
			local touch = playerGui:FindFirstChild("TouchGui")
			if touch then
				local nodes = touch:GetDescendants()
				table.insert(nodes, touch)
				for _, node in nodes do
					if node:IsA("GuiObject") then
						for _, property in { "AbsolutePosition", "AbsoluteSize", "Visible" } do
							table.insert(watched, node:GetPropertyChangedSignal(property):Connect(Schedule))
						end
					elseif node:IsA("ScreenGui") then
						table.insert(watched, node:GetPropertyChangedSignal("Enabled"):Connect(Schedule))
					end
				end
			end
			Schedule()
		end
		local function OnTree(node: Instance): ()
			if node.Name == "TouchGui" or node:FindFirstAncestor("TouchGui") then
				task.defer(function(): ()
					if not destroyed then
						Rewatch()
					end
				end)
			end
		end
		local function OnCamera(): ()
			if cameraConnection then
				cameraConnection:Disconnect()
			end
			local camera = workspace.CurrentCamera
			cameraConnection = if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(Schedule) else nil
			Schedule()
		end
		table.insert(connections, playerGui.DescendantAdded:Connect(OnTree))
		table.insert(connections, playerGui.DescendantRemoving:Connect(OnTree))
		table.insert(connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(OnCamera))
		table.insert(connections, gui:GetPropertyChangedSignal("TopbarInset"):Connect(Schedule))
		table.insert(connections, input:GetPropertyChangedSignal("PreferredInput"):Connect(Schedule))
		table.insert(connections, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(Schedule))
		table.insert(connections, root:GetPropertyChangedSignal("AbsolutePosition"):Connect(Schedule))
		OnCamera()
		Rewatch()
	end
	local read = readSnapshot :: () -> Snapshot
	local function Paint(group: Frame, areas: { [string]: Area }, snapshot: Snapshot): ()
		for name, area in areas do
			local frame = group:FindFirstChild(name) :: Frame
			assert(frame and frame:IsA("Frame"), "Missing Edit region template: " .. name)
			local rect = Regions.ToLocal(area.Rect, snapshot.Origin, snapshot.Scale)
			frame.Position, frame.Size = UDim2.fromOffset(rect.Min.X, rect.Min.Y), UDim2.fromOffset(rect.Width, rect.Height)
			frame:SetAttribute("RegionValid", area.Valid)
			frame.Visible = debugVisible and area.Valid
		end
	end
	controller = {
		Changed = {
			Connect = function(_, callback: () -> ()): Connection
				if not destroyed then
					listeners[callback] = true
				end
				return {
					Disconnect = function(): ()
						listeners[callback] = nil
					end,
				}
			end,
		},
		GetReservedRects = function(): { Area }
			local result = {}
			for _, name in ReservedNames do
				if reserved[name] then
					table.insert(result, table.clone(reserved[name]))
				end
			end
			return result
		end,
		GetRegion = function(_, name: string): Area?
			local area = available[name] or reserved[name]
			return if area then table.clone(area) else nil
		end,
		IntersectsReserved = function(_, rect: Rect): boolean
			for _, area in reserved do
				if area.Valid and Regions.Intersects(rect, area.Rect) then
					return true
				end
			end
			return false
		end,
		SetDebugVisible = function(_, enabled: boolean): ()
			debugVisible = enabled
			controller:Refresh()
		end,
		Refresh = function(): ()
			if destroyed then
				return
			end
			local snapshot = read()
			if snapshot.Scale <= 0 then
				return
			end
			local r, a = Regions.Compute(snapshot)
			local changed = lastOrigin ~= snapshot.Origin or lastScale ~= snapshot.Scale
			lastOrigin, lastScale = snapshot.Origin, snapshot.Scale
			for _, pair in { { r, reserved }, { a, available } } do
				for name, area in pair[1] do
					local old = pair[2][name]
					if not old or old.Rect ~= area.Rect or old.Valid ~= area.Valid then
						changed = true
					end
				end
			end
			reserved, available = r, a
			Paint(reservedRoot, reserved, snapshot)
			Paint(regionRoot, available, snapshot)
			if changed then
				for callback in table.clone(listeners) do
					if listeners[callback] then
						callback()
					end
				end
			end
		end,
		Destroy = function(): ()
			if destroyed then
				return
			end
			destroyed = true
			for _, c in connections do
				c:Disconnect()
			end
			for _, c in watched do
				c:Disconnect()
			end
			if cameraConnection then
				cameraConnection:Disconnect()
			end
			if stopObserve then
				stopObserve()
			end
			table.clear(listeners)
		end,
	}
	if options.Observe then
		stopObserve = options.Observe(Schedule)
	end
	controller:Refresh()
	return controller
end

Regions.ReservedNames, Regions.RegionNames = ReservedNames, RegionNames
return Regions
