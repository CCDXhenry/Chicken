-- 通用客户端弹窗窗口基类模板：封装弹窗动画、关闭生命周期与动作抽象
--!strict
local TweenService = game:GetService("TweenService")

export type UIActions = {
	openWindow: (windowId: string, ...any) -> (),
	closeWindow: (windowId: string) -> (),
	closeAllWindow: () -> (),
	createFrame: (frameName: string, frameParent: GuiBase2d?, zIndex: number?) -> Frame,
	hasShowingWindow: () -> boolean,
	isWindowShowing: (windowId: string) -> boolean,
}

local WindowOpenScaleTweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local WindowBase = {}
WindowBase.__index = WindowBase

WindowBase.OpenAnimation = {
	None = "None",
	Scale = "Scale",
}

export type WindowBase = typeof(setmetatable(
	{} :: {
		frame: Frame,
		windowId: string,
		uiActions: UIActions,
		openAnimation: string?,
	},
	WindowBase
))

function WindowBase.new(frame: Frame, windowId: string, uiActions: UIActions, openAnimation: string?): WindowBase
	local self: WindowBase = setmetatable({}, WindowBase) :: WindowBase
	self.frame = frame
	self.windowId = windowId
	self.uiActions = uiActions
	self.openAnimation = openAnimation or WindowBase.OpenAnimation.Scale
	return self
end

local function PlayScaleOpenAnimation(window: Frame)
	local uiScale: UIScale? = window:FindFirstChildOfClass("UIScale")
	if uiScale == nil then
		return
	end
	local targetScale = uiScale.Scale
	uiScale.Scale = 0
	local tween = TweenService:Create(uiScale, WindowOpenScaleTweenInfo, { Scale = targetScale })
	tween:Play()
end

function WindowBase.OnInit(self: WindowBase)
	if self.openAnimation == WindowBase.OpenAnimation.Scale then
		PlayScaleOpenAnimation(self.frame)
	end
end

function WindowBase.OnClose(self: WindowBase)
	self.frame:Destroy()
end

function WindowBase.Close(self: WindowBase)
	self.uiActions.closeWindow(self.windowId)
end

function WindowBase.CloseWindow(self: WindowBase, windowId: string)
	self.uiActions.closeWindow(windowId)
end

function WindowBase.CloseAllWindow(self: WindowBase)
	self.uiActions.closeAllWindow()
end

function WindowBase.OpenWindow(self: WindowBase, windowId: string, ...: any)
	self.uiActions.openWindow(windowId, ...)
end

function WindowBase.CreateFrame(self: WindowBase, frameName: string, frameParent: GuiBase2d?, zIndex: number?): Frame
	return self.uiActions.createFrame(frameName, frameParent, zIndex)
end

return WindowBase
