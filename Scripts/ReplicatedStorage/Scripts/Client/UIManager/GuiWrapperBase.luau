-- 界面包装器基类：提供窗口动作与销毁回调
--!strict
local LifecycleTool = require(script.Parent.Parent.Parent:WaitForChild("Shared"):WaitForChild("LifecycleTool"))
local UIActions = require(script.Parent:FindFirstChild("UIActions"))
type UIActions = UIActions.UIActions

local GuiWrapperBase = {}
GuiWrapperBase.__index = GuiWrapperBase

export type GuiWrapperBase = typeof(setmetatable(
	{} :: {
		uiActions: UIActions,
		gui: GuiObject,
		scope: LifecycleTool.Lifecycle?,
	},
	GuiWrapperBase
))

function GuiWrapperBase.OnDestroy(self: GuiWrapperBase): ()
	if self.scope then
		self.scope:Destroy()
		self.scope = nil
	end
end

function GuiWrapperBase.new(gui: GuiObject, uiActions: UIActions): GuiWrapperBase
	local self: GuiWrapperBase = setmetatable({}, GuiWrapperBase) :: GuiWrapperBase
	self.uiActions = uiActions
	self.gui = gui
	return self
end

function GuiWrapperBase.Init(self: GuiWrapperBase): ()
	if self.scope then
		return
	end
	local scope = LifecycleTool.new()
	self.scope = scope
	local function OnDestroying(): ()
		self:OnDestroy()
	end
	scope:Connect(self.gui.Destroying:Connect(OnDestroying))
end

function GuiWrapperBase.CloseWindow(self: GuiWrapperBase, windowId: string): ()
	self.uiActions.closeWindow(windowId)
end

function GuiWrapperBase.CloseAllWindow(self: GuiWrapperBase): ()
	self.uiActions.closeAllWindow()
end

function GuiWrapperBase.OpenWindow(self: GuiWrapperBase, windowId: string, ...: any): ()
	self.uiActions.openWindow(windowId, ...)
end

function GuiWrapperBase.CreateFrame(self: GuiWrapperBase, frameName: string, frameParent: GuiBase2d?, zIndex: number?): Frame
	return self.uiActions.createFrame(frameName, frameParent, zIndex)
end

function GuiWrapperBase.HasShowingWindow(self: GuiWrapperBase): boolean
	return self.uiActions.hasShowingWindow()
end

function GuiWrapperBase.IsWindowShowing(self: GuiWrapperBase, windowId: string): boolean
	return self.uiActions.isWindowShowing(windowId)
end

return GuiWrapperBase
