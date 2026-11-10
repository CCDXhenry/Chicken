-- 通用客户端 UI 管理器单例模板：负责预制体克隆、窗口配置驱动、模态遮罩交互及全局按钮动效
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local TextFitting = require(script.Parent:WaitForChild("TextFitting"))
local WindowBase = require(script.Parent:WaitForChild("WindowBaseTemplate"))
type WindowBase = WindowBase.WindowBase
type UIActions = WindowBase.UIActions

local UIManager = {}

local ButtonHoveredScale = 1.1 -- 鼠标悬停放大比例
local ButtonPressedScale = 0.8 -- 按钮按下缩小比例
local ButtonInteractionTweenInfo = TweenInfo.new(0.1)

export type WindowConfig = {
	frameName: string,
	isModal: boolean,
	modalTransparency: number?,
	openAnimation: string?,
	newWindow: (frame: Frame, windowId: string, uiActions: UIActions, ...any) -> WindowBase,
}

local uiTemplatesFolder: Folder
local WindowConfigs: { [string]: WindowConfig } = {}
local addedWindows: { [string]: WindowBase } = {}
local gameScreenGui: ScreenGui?
local modalButton: ImageButton?
local interactionEffectAppliedButtons: { [GuiButton]: boolean } = {}
local uiActions: UIActions

local function MarkButtonApplied(appliedButtons: { [GuiButton]: boolean }, button: GuiButton)
	appliedButtons[button] = true
	button.Destroying:Connect(function()
		appliedButtons[button] = nil
	end)
end

local function CheckModalButtonVisible()
	if modalButton == nil then
		return
	end
	local topModalWindow: Frame?
	local topModalWindowConfig: WindowConfig?
	local modalTransparency = 1
	for windowId, window in addedWindows do
		local windowConfig = WindowConfigs[windowId]
		if windowConfig and windowConfig.isModal then
			if topModalWindow == nil or window.frame.ZIndex > topModalWindow.ZIndex then
				topModalWindow = window.frame
				topModalWindowConfig = windowConfig
			end
			modalTransparency *= (windowConfig.modalTransparency or 0.5)
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

-- 为带 HasInteractionEffect 属性的按钮自动绑定悬停与点击微动效
local function ApplyButtonEffects(button: GuiButton)
	if not button:GetAttribute("HasInteractionEffect") then
		return
	end
	if interactionEffectAppliedButtons[button] then
		return
	end
	local uiScale: UIScale? = button:FindFirstChildOfClass("UIScale")
	if uiScale == nil then
		return
	end
	MarkButtonApplied(interactionEffectAppliedButtons, button)
	local normalScale = uiScale.Scale
	local hoveredScale = ButtonHoveredScale * normalScale
	local pressedScale = ButtonPressedScale * normalScale
	local mouseEnterTween = TweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = hoveredScale })
	local mouseLeaveTween = TweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = normalScale })
	local clickTween1 = TweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = pressedScale })
	local clickTween2 = TweenService:Create(uiScale, ButtonInteractionTweenInfo, { Scale = normalScale })

	clickTween1.Completed:Connect(function()
		clickTween2:Play()
	end)
	button.MouseEnter:Connect(function()
		if not button.Active then
			return
		end
		if UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse then
			mouseEnterTween:Play()
		end
	end)
	button.MouseLeave:Connect(function()
		if UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse then
			mouseLeaveTween:Play()
		end
	end)
	button.Activated:Connect(function()
		clickTween1:Play()
	end)
end

-- 注册窗口配置
function UIManager.RegisterWindow(windowId: string, config: WindowConfig)
	WindowConfigs[windowId] = config
end

-- 初始化 UIManager
function UIManager.Init(screenGui: ScreenGui, templatesFolder: Folder?)
	gameScreenGui = screenGui
	uiTemplatesFolder = templatesFolder or (ReplicatedStorage:WaitForChild("UI") :: Folder)
	if gameScreenGui == nil then
		return
	end

	-- 创建或复用模态遮罩
	local existingModal = uiTemplatesFolder:FindFirstChild("ModalButton")
	if existingModal and existingModal:IsA("ImageButton") then
		modalButton = existingModal:Clone()
	else
		local defaultModal = Instance.new("ImageButton")
		defaultModal.Name = "ModalButton"
		defaultModal.Size = UDim2.fromScale(1, 1)
		defaultModal.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		defaultModal.BackgroundTransparency = 0.5
		defaultModal.BorderSizePixel = 0
		defaultModal.AutoButtonColor = false
		defaultModal.Visible = false
		modalButton = defaultModal
	end
	if modalButton then
		modalButton.Parent = gameScreenGui
	end

	-- 监听所有当前与新加入的按钮
	local uiParents: { Instance } = { workspace, gameScreenGui }
	for _, uiParent in uiParents do
		uiParent.DescendantAdded:Connect(function(descendant: Instance)
			if descendant:IsA("GuiButton") then
				ApplyButtonEffects(descendant)
			end
		end)
		for _, descendant in uiParent:GetDescendants() do
			if descendant:IsA("GuiButton") then
				ApplyButtonEffects(descendant)
			end
		end
	end
end

-- 非窗口方式克隆 Frame 预制体
function UIManager.CreateFrame(frameName: string, frameParent: GuiBase2d?, zIndex: number?): Frame
	local template = uiTemplatesFolder:FindFirstChild(frameName)
	assert(template and template:IsA("Frame"), "UI template not found or invalid: " .. frameName)
	local frame = template:Clone() :: Frame
	frame.Parent = frameParent or gameScreenGui
	if zIndex ~= nil then
		frame.ZIndex = zIndex
	end
	return frame
end

-- 打开窗口
function UIManager.OpenWindow(windowId: string, ...: any)
	if gameScreenGui == nil then
		return
	end
	if addedWindows[windowId] ~= nil then
		return
	end
	local windowConfig = WindowConfigs[windowId]
	if windowConfig == nil then
		warn("[UIManager] WindowConfig not registered for:", windowId)
		return
	end
	local template = uiTemplatesFolder:FindFirstChild(windowConfig.frameName)
	if template == nil or not template:IsA("Frame") then
		warn("[UIManager] Frame template not found:", windowConfig.frameName)
		return
	end
	local frame = template:Clone() :: Frame
	frame.Parent = gameScreenGui

	local window = windowConfig.newWindow(frame, windowId, uiActions, ...)
	if windowConfig.openAnimation ~= nil then
		window.openAnimation = windowConfig.openAnimation
	end
	addedWindows[windowId] = window

	local count = 0
	for _ in pairs(addedWindows) do
		count += 1
	end
	frame.ZIndex = 100 + count * 2

	window:OnInit()
	CheckModalButtonVisible()
end

-- 窗口是否展示中
function UIManager.IsWindowShowing(windowId: string): boolean
	return addedWindows[windowId] ~= nil
end

-- 关闭窗口
function UIManager.CloseWindow(windowId: string)
	local window = addedWindows[windowId]
	if window == nil then
		return
	end
	addedWindows[windowId] = nil
	window:OnClose()
	CheckModalButtonVisible()
end

-- 切换窗口显示状态
function UIManager.SwitchWindowShowing(windowId: string)
	if UIManager.IsWindowShowing(windowId) then
		UIManager.CloseWindow(windowId)
	else
		UIManager.OpenWindow(windowId)
	end
end

-- 关闭所有窗口
function UIManager.CloseAllWindow()
	local closingList: { { windowId: string, window: WindowBase } } = {}
	for windowId, window in pairs(addedWindows) do
		table.insert(closingList, { windowId = windowId, window = window })
	end
	table.clear(addedWindows)
	CheckModalButtonVisible()
	for _, entry in pairs(closingList) do
		entry.window:OnClose()
	end
end

-- 是否有任意窗口展示中
function UIManager.HasShowingWindow(): boolean
	for _ in pairs(addedWindows) do
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

-- 导出文本拟合工具接口
UIManager.FitTextLabel = TextFitting.FitTextLabel
UIManager.FitTextWithShadow = TextFitting.FitTextWithShadow
UIManager.FitMarkedText = TextFitting.FitMarkedText
UIManager.FitMarkedRoot = TextFitting.FitMarkedRoot

return UIManager
