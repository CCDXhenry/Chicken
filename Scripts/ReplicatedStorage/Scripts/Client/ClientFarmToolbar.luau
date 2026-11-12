-- 农场双槽工具栏：移植绳索跳跃 BackpackFrame 槽位绑定与选中图片逻辑，负责手持选择、模型预览、触控跳跃键依附与可取消的按住使用
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local Lifecycle = require(Shared:WaitForChild("LifecycleTool"))
local Economy = require(Shared:WaitForChild("FarmEconomyConfig"))
local ClientGameInfo = require(script.Parent:WaitForChild("ClientGameInfo"))
local GameTexts = require(Shared:WaitForChild("GameTexts"))
local ClientMsg = require(script.Parent:WaitForChild("ClientMsg"))
local UIManager = require(script.Parent:WaitForChild("UIManager"))
local ModelPreview = require(script.Parent:WaitForChild("FarmModelPreview"))
local TextTool = require(script.Parent:WaitForChild("FarmTextTool"))
local Toolbar = {}
Toolbar.__index = Toolbar
type Slot = "zap" | "collect"
export type Controller = typeof(setmetatable({} :: {
	scope: Lifecycle.Lifecycle,
	characterScope: Lifecycle.Lifecycle?,
	jumpScope: Lifecycle.Lifecycle?,
	buttons: { [string]: ImageButton },
	previewTiers: { [string]: number },
	touchFrame: Frame,
	useButton: ImageButton,
	jumpButton: GuiObject?,
	pressTween: Tween?,
	releaseTween: Tween?,
	selected: Slot?,
	pending: Slot?,
	held: InputObject?,
	heldSlot: Slot?,
	nextUseAt: number,
	onUse: (Slot) -> (),
}, Toolbar))
local ToolNames = { zap = "FarmWeapon", collect = "FarmCollector" }
local player = Players.LocalPlayer

function Toolbar.new(onUse: (Slot) -> ()): Controller
	return setmetatable({ scope = Lifecycle.new(), buttons = {}, previewTiers = {}, nextUseAt = 0, onUse = onUse }, Toolbar) :: Controller
end

function Toolbar.Stop(self: Controller): ()
	if self.held then
		if self.pressTween then self.pressTween:Cancel() end
		if self.releaseTween then self.releaseTween:Play() end
	end
	self.held, self.heldSlot = nil, nil
end

function Toolbar.CanUse(self: Controller, action: string): boolean
	if action ~= "zap" and action ~= "collect" then return false end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local tool = if character then character:FindFirstChild(ToolNames[action]) else nil
	return self.scope.alive and self.selected == action and humanoid ~= nil and humanoid.Health > 0
		and tool ~= nil and tool:IsA("Tool") and tool.Enabled and ClientGameInfo.GetFarmInfo().ready == true
		and not UIManager.HasShowingWindow() and not GuiService.MenuIsOpen and UserInputService:GetFocusedTextBox() == nil
end

function Toolbar.LayoutTouch(self: Controller): ()
	local jump = self.jumpButton
	local touch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
	local visible = jump ~= nil and jump.Parent ~= nil and jump.AbsoluteSize.X > 0
	if jump then
		local ancestor: Instance? = jump
		while ancestor do
			if ancestor:IsA("GuiObject") and not ancestor.Visible then visible = false end
			if ancestor:IsA("ScreenGui") and not ancestor.Enabled then visible = false end
			ancestor = ancestor.Parent
		end
	end
	self.touchFrame.Visible = touch and visible and self.selected ~= nil and not UIManager.HasShowingWindow()
	if not jump or not visible then return end
	local ratio = self.touchFrame:GetAttribute("JumpSizeRatio")
	local minimum = self.touchFrame:GetAttribute("MinimumTouchSize")
	local gap = self.touchFrame:GetAttribute("JumpGap")
	assert(typeof(ratio) == "number" and typeof(minimum) == "number" and typeof(gap) == "number")
	local size = math.max(minimum, jump.AbsoluteSize.X * ratio)
	-- 触控模板独立于普通 HUD 画布；通过父级绝对原点统一坐标空间。
	local origin = self.touchFrame.AbsolutePosition - Vector2.new(self.touchFrame.Position.X.Offset, self.touchFrame.Position.Y.Offset)
	local topLeft = jump.AbsolutePosition - Vector2.new(size + gap, size + gap)
	self.touchFrame.Size = UDim2.fromOffset(size, size)
	self.touchFrame.Position = UDim2.fromOffset(math.max(0, topLeft.X - origin.X), math.max(0, topLeft.Y - origin.Y))
end

function Toolbar.RefreshEquipped(self: Controller): ()
	local character = player.Character
	local selected: Slot? = nil
	if character then
		for slot, name in ToolNames do
			local tool = character:FindFirstChild(name)
			if tool and tool:IsA("Tool") then selected = slot :: Slot end
		end
	end
	if selected ~= self.selected then self:Stop() end
	self.selected = selected
	for slot, button in self.buttons do
		(button:WaitForChild("EquippedImage") :: ImageLabel).Visible = slot == selected
	end
	local imageAttribute = if selected == "zap" then "AttackImage" else "CollectImage"
	local image = self.useButton:GetAttribute(imageAttribute)
	if typeof(image) == "string" then self.useButton.Image = image end
	local rect = self.useButton:GetAttribute(if selected == "zap" then "AttackRectOffset" else "CollectRectOffset")
	if typeof(rect) == "Vector2" then self.useButton.ImageRectOffset = rect end
	TextTool.Set(self.useButton:WaitForChild("ActionText") :: TextLabel, if selected == "zap" then "Zap" else "Collect")
	self:LayoutTouch()
end

function Toolbar.EquipPending(self: Controller): ()
	local selected = self.pending
	if not selected then return end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tool = if backpack then backpack:FindFirstChild(ToolNames[selected]) else nil
	if humanoid and humanoid.Health > 0 and tool and tool:IsA("Tool") then
		self.pending = nil
		humanoid:EquipTool(tool)
	end
end

function Toolbar.Select(self: Controller, slot: Slot): ()
	if UIManager.HasShowingWindow() or GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox() then return end
	self:Stop()
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid or humanoid.Health <= 0 then return end
	if self.selected == slot or self.pending == slot then
		self.pending = nil
		humanoid:UnequipTools()
	else
		self.pending = slot
		self:EquipPending()
	end
	self:RefreshEquipped()
end

function Toolbar.RenderPreview(self: Controller, slot: Slot, tier: number): ()
	if self.previewTiers[slot] == tier then return end
	local viewport = self.buttons[slot]:WaitForChild("ToolViewport") :: ViewportFrame
	local models = ReplicatedStorage:WaitForChild("Models")
	local folder = models:WaitForChild(if slot == "zap" then "Weapons" else "Collectors")
	local source = folder:WaitForChild((if slot == "zap" then "ZapWeapon_T" else "Collector_T") .. tostring(tier))
	ModelPreview.Render(viewport, source)
	self.previewTiers[slot] = tier
end

function Toolbar.Render(self: Controller): ()
	local info = ClientGameInfo.GetFarmInfo()
	self:RenderPreview("zap", info.zap)
	self:RenderPreview("collect", info.collect)
	for slot, button in self.buttons do
		TextTool.Set(button:WaitForChild("ToolNameText") :: TextLabel, if slot == "zap" then GameTexts.ZapNames[info.zap] else GameTexts.CollectNames[info.collect])
		TextTool.Set(button:WaitForChild("ToolLvText") :: TextLabel, if slot == "zap" then string.format("Lv.%d", info.weaponLevel or 1) else "")
	end
	self:RefreshEquipped()
end

function Toolbar.Start(self: Controller, input: InputObject, fromUseButton: boolean?): ()
	local slot = self.selected :: Slot?
	if self.held or not slot or not self:CanUse(slot) then return end
	self.held, self.heldSlot = input, slot :: Slot
	if fromUseButton then
		if self.releaseTween then self.releaseTween:Cancel() end
		if self.pressTween then self.pressTween:Play() end
	end
	if os.clock() >= self.nextUseAt then
		self.nextUseAt = os.clock() + (if slot == "zap" then Economy.ZapCooldownSeconds else Economy.CollectCooldownSeconds)
		self.onUse(slot :: Slot)
	end
end

function Toolbar.UpdateUse(self: Controller): ()
	local slot = self.heldSlot :: Slot?
	if not slot then return end
	if not self:CanUse(slot) then self:Stop(); return end
	if os.clock() >= self.nextUseAt then
		self.nextUseAt = os.clock() + (if slot == "zap" then Economy.ZapCooldownSeconds else Economy.CollectCooldownSeconds)
		self.onUse(slot :: Slot)
	end
end

function Toolbar.WatchCharacter(self: Controller, character: Model): ()
	self:Stop()
	if self.characterScope then self.characterScope:Destroy() end
	local scope = Lifecycle.new()
	self.characterScope = scope
	self.pending = "zap"
	local function OnChanged(): ()
		self:Stop()
		task.defer(function()
			if scope.alive then self:EquipPending(); self:RefreshEquipped() end
		end)
	end
	scope:Connect(character.ChildAdded:Connect(OnChanged))
	scope:Connect(character.ChildRemoved:Connect(OnChanged))
	local function WatchBackpack(backpack: Instance): ()
		if not backpack:IsA("Backpack") then return end
		scope:Connect(backpack.ChildAdded:Connect(OnChanged))
		scope:Connect(backpack.ChildRemoved:Connect(OnChanged))
		OnChanged()
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then WatchBackpack(backpack) end
	scope:Connect(player.ChildAdded:Connect(WatchBackpack))
	scope:Spawn(function()
		local humanoid = character:WaitForChild("Humanoid")
		if humanoid:IsA("Humanoid") then scope:Connect(humanoid.Died:Connect(function() self.pending = nil; self:Stop(); self:RefreshEquipped() end)) end
	end)
	OnChanged()
end

function Toolbar.Init(self: Controller, hud: Frame, screenGui: ScreenGui): ()
	local bottom = hud:WaitForChild("BottomButtonsFrame")
	self.buttons.zap = bottom:WaitForChild("WeaponButton") :: ImageButton
	self.buttons.collect = bottom:WaitForChild("CollectorButton") :: ImageButton
	local template = ReplicatedStorage:WaitForChild("UI"):WaitForChild("FarmTouchUseFrame") :: Frame
	self.touchFrame = template:Clone()
	self.touchFrame.Parent = screenGui
	self.scope:Own(self.touchFrame)
	self.scope:Spawn(function()
		local ok, message = pcall(function() ContentProvider:PreloadAsync({ bottom, self.touchFrame }) end)
		if not ok and self.scope.alive then warn("工具栏素材预载失败：", message) end
	end)
	self.useButton = self.touchFrame:WaitForChild("UseButton") :: ImageButton
	local useScale = self.useButton:WaitForChild("UIScale") :: UIScale
	local pressedScale = self.useButton:GetAttribute("PressedScale")
	local duration = self.useButton:GetAttribute("PressTweenSeconds")
	assert(typeof(pressedScale) == "number" and typeof(duration) == "number")
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	self.pressTween = TweenService:Create(useScale, tweenInfo, { Scale = pressedScale })
	self.releaseTween = TweenService:Create(useScale, tweenInfo, { Scale = useScale.Scale })
	local function OnJumpFound(instance: Instance): ()
		if instance.Name ~= "JumpButton" or not instance:IsA("GuiObject") then return end
		if self.jumpScope then self.jumpScope:Destroy() end
		self.jumpButton = instance
		local scope = Lifecycle.new()
		self.jumpScope = scope
		local function OnLayout(): () self:LayoutTouch() end
		for _, property in { "AbsolutePosition", "AbsoluteSize", "Visible" } do scope:Connect(instance:GetPropertyChangedSignal(property):Connect(OnLayout)) end
		scope:Connect(instance.AncestryChanged:Connect(OnLayout))
		self:LayoutTouch()
	end
	local playerGui = player:WaitForChild("PlayerGui")
	for _, instance in playerGui:GetDescendants() do OnJumpFound(instance) end
	self.scope:Connect(playerGui.DescendantAdded:Connect(OnJumpFound))
	for slot, button in self.buttons do
		self.scope:Connect(button.Activated:Connect(function() self:Select(slot :: Slot) end))
	end
	self.scope:Connect(self.useButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then self:Start(input, true) end
	end))
	self.scope:Connect(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.One then self:Select("zap")
		elseif input.KeyCode == Enum.KeyCode.Two then self:Select("collect")
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 and UserInputService.PreferredInput ~= Enum.PreferredInput.Touch then self:Start(input) end
	end))
	self.scope:Connect(UserInputService.InputEnded:Connect(function(input)
		if input == self.held or (self.held and self.held.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then self:Stop() end
	end))
	self.scope:Connect(UserInputService.WindowFocusReleased:Connect(function() self:Stop() end))
	self.scope:Connect(UserInputService.TextBoxFocused:Connect(function() self:Stop() end))
	self.scope:Connect(GuiService.MenuOpened:Connect(function() self:Stop() end))
	self.scope:Connect(ClientMsg.ConnectOpenWindow(function() self:Stop(); self:LayoutTouch() end))
	self.scope:Connect(ClientMsg.ConnectCloseWindow(function() self:LayoutTouch() end))
	self.scope:Connect(UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function() self:Stop(); self:LayoutTouch() end))
	self.scope:Connect(ClientMsg.ConnectFarmInfoChanged(function() self:Render() end))
	self.scope:Connect(player.CharacterAdded:Connect(function(character) self:WatchCharacter(character) end))
	self.scope:Connect(player.CharacterRemoving:Connect(function() self:Stop(); self.pending = nil end))
	self.scope:Connect(RunService.Heartbeat:Connect(function()
		self:UpdateUse()
	end))
	if player.Character then self:WatchCharacter(player.Character) end
	self:Render()
end

function Toolbar.Destroy(self: Controller): ()
	self:Stop()
	if self.characterScope then self.characterScope:Destroy() end
	if self.jumpScope then self.jumpScope:Destroy() end
	if self.pressTween then self.pressTween:Destroy(); self.pressTween = nil end
	if self.releaseTween then self.releaseTween:Destroy(); self.releaseTween = nil end
	TextTool.Remove(self.touchFrame)
	self.scope:Destroy()
end

return Toolbar
