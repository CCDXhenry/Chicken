-- 界面动作契约：定义窗口与模板克隆的业务接口
--!strict
export type UIActions = {
	closeWindow: (windowId: string) -> (),
	closeAllWindow: () -> (),
	openWindow: (windowId: string, ...any) -> (),
	createFrame: (frameName: string, frameParent: GuiBase2d?, ZIndex: number?) -> Frame,
	hasShowingWindow: () -> boolean,
	isWindowShowing: (windowId: string) -> boolean,
}

return {}
