-- 通用客户端界面包装器基类模板：提供界面销毁监听、统一的窗口打开/关闭与动作抽象
--!strict
export type UIActions = {
	openWindow: (windowId: string, ...any) -> (),
	closeWindow: (windowId: string) -> (),
	closeAllWindow: () -> (),
	createFrame: (frameName: string, frameParent: GuiBase2d?, zIndex: number?) -> Frame,
	hasShowingWindow: () -> boolean,
	isWindowShowing: (windowId: string) -> boolean,
}

local GuiWrapperBase = {}
GuiWrapperBase.__index = GuiWrapperBase

export type GuiWrapperBase = typeof(setmetatable(
	{} :: {
		uiActions: UIActions,
	},
	GuiWrapperBase
))

function GuiWrapperBase.new(gui: GuiObject, uiActions: UIActions): GuiWrapperBase
	local self: GuiWrapperBase = setmetatable({}, GuiWrapperBase) :: GuiWrapperBase
	self.uiActions = uiActions
	gui.Destroying:Connect(function()
		self:OnDestroy()
	end)
	return self
end

function GuiWrapperBase.OnDestroy(self: GuiWrapperBase)
	-- 子类覆写：在此断开事件连接、清理 Tween、释放动效及对象池资源
end

function GuiWrapperBase.CloseWindow(self: GuiWrapperBase, windowId: string)
	self.uiActions.closeWindow(windowId)
end

function GuiWrapperBase.CloseAllWindow(self: GuiWrapperBase)
	self.uiActions.closeAllWindow()
end

function GuiWrapperBase.OpenWindow(self: GuiWrapperBase, windowId: string, ...: any)
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
