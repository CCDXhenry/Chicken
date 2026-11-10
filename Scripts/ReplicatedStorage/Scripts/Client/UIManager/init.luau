-- 界面管理器：维护模板克隆、窗口栈、模态遮罩和交互资源
--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local tweenService: TweenService = game:GetService("TweenService")
local userInputService: UserInputService = game:GetService("UserInputService")
local UIManager = {}
local LifecycleTool = require(script.Parent.Parent:WaitForChild("Shared"):WaitForChild("LifecycleTool"))
local scope = LifecycleTool.new()
local initialized = false
local buttonScopes: { [GuiButton]: LifecycleTool.Lifecycle } = {}

local uiTemplatesFolder: Folder = replicatedStorage:FindFirstChild("UI") :: Folder
local scripts = replicatedStorage:WaitForChild("Scripts")
local clientScripts = scripts:WaitForChild("Client")
local ClientMsg = require(clientScripts:FindFirstChild("ClientMsg"))

local WindowBase = require(script:FindFirstChild("WindowBase"))
type WindowBase = WindowBase.WindowBase
local UIActions = require(script:FindFirstChild("UIActions"))
type UIActions = UIActions.UIActions
local TextFitting = require(script:WaitForChild("TextFitting"))

local ModalTransparency: number = 0.4
local ButtonHoveredScale: number = 1.1 --按钮鼠标移入放大
local ButtonPressedScale: number = 0.8 --按钮按下缩小
local ButtonInteractionTweenInfo: TweenInfo = TweenInfo.new(0.1) --按钮交互动画缓动信息

type WindowConfig = {
	frameName: string,
	isModal: boolean,
	modalTransparency: number?,
	openAnimation: string?,
	newWindow: (frame: Frame, windowId: string, uiActions: UIActions, ...any) -> WindowBase,
}

local WindowConfigs: { [string]: WindowConfig } = {}

local addedWindows: { [string]: WindowBase } = {}
local gameScreenGui: ScreenGui?
local modalButton: ImageButton
local interactionEffectAppliedButtons: { [GuiButton]: boolean } = {}
local uiActions: UIActions

local function MarkButtonApplied(appliedButtons: { [GuiButton]: boolean }, button: GuiButton): ()
	appliedButtons[button] = true
	scope:Connect(button.Destroying:Connect(function()
		appliedButtons[button] = nil
	end))
end

local function CheckModalButtonVisible(): ()
	local topModalWindow: Frame?
	local topModalWindowConfig: WindowConfig?
	local modalTransparency: number = 1
	for windowId: string, window: WindowBase in addedWindows do
		local windowConfig: WindowConfig = WindowConfigs[windowId]
		if windowConfig.isModal then
			if topModalWindow == nil or window.frame.ZIndex > topModalWindow.ZIndex then
				topModalWindow = window.frame
				topModalWindowConfig = windowConfig
			end
			modalTransparency *= windowConfig.modalTransparency or ModalTransparency
		end
	end
	if topModalWindow == nil or topModalWindowConfig == nil then
		modalButton.Visible = false
	else
		modalButton.Visible = true
		modalButton.ZIndex = topModalWindow.ZIndex - 1
		modalButton.BackgroundTransparency = modalTransparency
	end
end

--给按钮加点击和悬停缩放效果
local function ApplyButtonEffects(button: GuiButton): ()
	--如果按钮不需要交互效果
	if not button:GetAttribute("HasInteractionEffect") then
		return
	end
	if interactionEffectAppliedButtons[button] then
		return
	end
	--确保按钮有UIScale
	local uiScale: UIScale? = button:FindFirstChildOfClass("UIScale") :: UIScale?
	if uiScale == nil then
		return
	end
	local buttonScope = LifecycleTool.new()
	buttonScopes[button] = buttonScope
	buttonScope:Connect(button.Destroying:Connect(function(): ()
		buttonScope:Destroy()
		buttonScopes[button] = nil
		interactionEffectAppliedButtons[button] = nil
	end))
	MarkButtonApplied(interactionEffectAppliedButtons, button)
	local normalScale: number = uiScale.Scale
	local hoveredScale: number = ButtonHoveredScale * normalScale
	local pressedScale: number = ButtonPressedScale * normalScale
	local mouseEnterTween: Tween = tweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = hoveredScale })
	local mouseLeaveTween: Tween = tweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = normalScale })
	local clickTween1: Tween = tweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = pressedScale })
	local clickTween2: Tween = tweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = normalScale })
	buttonScope:Connect(clickTween1.Completed:Connect(function(playbackState: Enum.PlaybackState)
		buttonScope:Play(clickTween2)
	end))
	buttonScope:Connect(button.MouseEnter:Connect(function()
		if not button.Active then
			return
		end
		if userInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse then
			buttonScope:Play(mouseEnterTween)
		end
	end))
	buttonScope:Connect(button.MouseLeave:Connect(function()
		if userInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse then
			buttonScope:Play(mouseLeaveTween)
		end
	end))
	buttonScope:Connect(button.Activated:Connect(function(inputObject: InputObject, clickCount: number)
		buttonScope:Play(clickTween1)
	end))
end

--初始化
function UIManager.Init(gameScreenGuiNew: ScreenGui): ()
	if initialized then
		return
	end
	initialized = true
	if not scope.alive then
		scope = LifecycleTool.new()
	end
	gameScreenGui = gameScreenGuiNew
	if gameScreenGui == nil then
		return
	end
	modalButton = gameScreenGuiNew:WaitForChild("ModalButton") :: ImageButton

	local uiParents: { Instance } = { workspace, gameScreenGui }
	for uiParentIndex: number, uiParent: Instance in uiParents do
		scope:Connect(uiParent.DescendantAdded:Connect(function(descendant: Instance)
			if descendant:IsA("GuiButton") then
				ApplyButtonEffects(descendant)
			end
		end))
		for descendantIndex: number, descendant: Instance in uiParent:GetDescendants() do
			if descendant:IsA("GuiButton") then
				ApplyButtonEffects(descendant)
			end
		end
	end
end

--非窗口方式创建界面
function UIManager.CreateFrame(frameName: string, frameParent: GuiBase2d?, ZIndex: number?): Frame
	local frame: Frame = (uiTemplatesFolder:FindFirstChild(frameName) :: Frame):Clone()
	if frameParent == nil then
		frame.Parent = gameScreenGui
	else
		frame.Parent = frameParent
	end
	if ZIndex ~= nil then
		frame.ZIndex = ZIndex
	end
	return frame
end

function UIManager.FitTextLabel(label: TextLabel, options: TextFitting.TextFitOptions?): number
	return TextFitting.FitTextLabel(label, options)
end

function UIManager.FitMarkedText(label: TextLabel): number?
	return TextFitting.FitMarkedText(label)
end

function UIManager.FitMarkedRoot(root: Instance): ()
	TextFitting.FitMarkedRoot(root)
end

--打开窗口
function UIManager.OpenWindow(windowId: string, ...: any): ()
	if gameScreenGui == nil then
		return
	end
	local existingWindow: WindowBase? = addedWindows[windowId]
	if existingWindow ~= nil then
		return
	end
	local windowConfig: WindowConfig? = WindowConfigs[windowId]
	if windowConfig == nil then
		return
	end
	local frame: Frame? = (uiTemplatesFolder:FindFirstChild(windowConfig.frameName) :: Frame):Clone()
	if frame == nil then
		return
	end
	frame.Parent = gameScreenGui
	local window: WindowBase = windowConfig.newWindow(frame, windowId, uiActions, ...)
	if windowConfig.openAnimation ~= nil then
		window.openAnimation = windowConfig.openAnimation
	end
	addedWindows[windowId] = window
	local addedWindowCount: number = 0
	for _: string, _: WindowBase in pairs(addedWindows) do
		addedWindowCount += 1
	end
	frame.ZIndex = 100 + addedWindowCount * 2
	window:OnInit()
	CheckModalButtonVisible()
	ClientMsg.FireOpenWindow(windowId)
end

--窗口是否展示中
function UIManager.IsWindowShowing(windowId: string): boolean
	local window: WindowBase? = addedWindows[windowId]
	return window ~= nil
end

--关闭窗口
function UIManager.CloseWindow(windowId: string): ()
	local window: WindowBase? = addedWindows[windowId]
	if window == nil then
		return
	end
	addedWindows[windowId] = nil
	window:OnClose()
	CheckModalButtonVisible()
	ClientMsg.FireCloseWindow(windowId)
end

--切换窗口显示状态
function UIManager.SwitchWindowShowing(windowId: string): ()
	if UIManager.IsWindowShowing(windowId) then
		UIManager.CloseWindow(windowId)
	else
		UIManager.OpenWindow(windowId)
	end
end

--关闭所有窗口
function UIManager.CloseAllWindow(): ()
	local closingWindows: { { windowId: string, window: WindowBase } } = {}
	for windowId: string, window: WindowBase in pairs(addedWindows) do
		table.insert(closingWindows, { windowId = windowId, window = window })
	end
	table.clear(addedWindows)
	CheckModalButtonVisible()
	for _: number, entry: { windowId: string, window: WindowBase } in pairs(closingWindows) do
		entry.window:OnClose()
		ClientMsg.FireCloseWindow(entry.windowId)
	end
end

--是否有窗口正在展示中
function UIManager.HasShowingWindow(): boolean
	for _: string, _: WindowBase in pairs(addedWindows) do
		return true
	end
	return false
end

uiActions = {
	closeWindow = UIManager.CloseWindow,
	closeAllWindow = UIManager.CloseAllWindow,
	openWindow = UIManager.OpenWindow,
	createFrame = UIManager.CreateFrame,
	hasShowingWindow = UIManager.HasShowingWindow,
	isWindowShowing = UIManager.IsWindowShowing,
}

function UIManager.GetUIActions(): UIActions
	return uiActions
end

function UIManager.Destroy(): ()
	if not initialized then
		return
	end
	UIManager.CloseAllWindow()
	for _, buttonScope in buttonScopes do
		buttonScope:Destroy()
	end
	table.clear(buttonScopes)
	scope:Destroy()
	table.clear(interactionEffectAppliedButtons)
	gameScreenGui = nil
	initialized = false
end
return UIManager
