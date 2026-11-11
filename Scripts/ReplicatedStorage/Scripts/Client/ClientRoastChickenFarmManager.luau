-- 客户端农场管理器：负责输入请求、武器 Tool 联动、反馈分发与界面生命周期
--!strict
local contextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local sharedScripts = replicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local FarmConfig = require(sharedScripts:WaitForChild("FarmConfig"))
local LifecycleTool = require(sharedScripts:WaitForChild("LifecycleTool"))
local ClientGameInfo = require(script.Parent:WaitForChild("ClientGameInfo"))
local RoastChickenHUDFrame = require(script.Parent:WaitForChild("RoastChickenHUDFrame"))
local SpeciesManager = require(script.Parent:WaitForChild("ClientFarmSpeciesManager"))
local UIManager = require(script.Parent:WaitForChild("UIManager"))
local FarmSoundTool = require(sharedScripts:WaitForChild("FarmSoundTool"))

local localPlayer = players.LocalPlayer
local ClientRoastChickenFarmManager = {}
ClientRoastChickenFarmManager.__index = ClientRoastChickenFarmManager
export type ClientRoastChickenFarmManager = typeof(setmetatable(
	{} :: { hud: RoastChickenHUDFrame.RoastChickenHUDFrame?, speciesUI: SpeciesManager.ClientFarmSpeciesManager?, scope: LifecycleTool.Lifecycle?, initialized: boolean },
	ClientRoastChickenFarmManager
))

function ClientRoastChickenFarmManager.new(): ClientRoastChickenFarmManager
	return setmetatable({ initialized = false }, ClientRoastChickenFarmManager)
end

function ClientRoastChickenFarmManager.Init(self: ClientRoastChickenFarmManager, screenGui: ScreenGui): ()
	if self.initialized then
		return
	end
	self.initialized = true
	local scope = LifecycleTool.new()
	self.scope = scope
	ClientGameInfo.InitFarmInfo()
	local function OnAction(action: FarmConfig.FarmAction): ()
		self:TriggerAction(action)
	end
	local hud = RoastChickenHUDFrame.new(OnAction)
	self.hud = hud
	hud:Init(screenGui)
	local speciesUI = SpeciesManager.new()
	self.speciesUI = speciesUI
	speciesUI:Init(screenGui)
	local function OnShop(): ()
		FarmSoundTool.Play("UIClick")
		speciesUI:Open("ToolShop")
	end
	scope:Connect(hud.shopButton.Activated:Connect(OnShop))

	local function OnIndex(): ()
		FarmSoundTool.Play("UIClick")
		speciesUI:Open("Species")
	end
	scope:Connect(hud.indexButton.Activated:Connect(OnIndex))

	local function OnEgg(): ()
		FarmSoundTool.Play("UIClick")
		speciesUI:Open("Hatch")
	end
	scope:Connect(hud.eggButton.Activated:Connect(OnEgg))

	local function OnEquipment(): ()
		FarmSoundTool.Play("UIClick")
		speciesUI:Open("Equipment")
	end
	scope:Connect(hud.equipmentButton.Activated:Connect(OnEquipment))
	local function OnFeedback(message: string, kind: string?): ()
		if kind == "sale" then
			FarmSoundTool.Play("Coin")
			hud:ShowSaleNotice(message)
		else
			if string.find(message, "拾取") or string.find(message, "Collected") then
				FarmSoundTool.Play("Pickup")
			elseif string.find(message, "超重") or string.find(message, "不足") or string.find(message, "Capacity") or string.find(message, "ItemTooHeavy") then
				FarmSoundTool.Play("Warning")
			elseif string.find(message, "熟食") or string.find(message, "Cooked") then
				FarmSoundTool.Play("AnimalCooked")
			elseif string.find(message, "命中") or string.find(message, "Damage") then
				FarmSoundTool.Play("AnimalHit")
			end
			hud:ShowMessage(message)
		end
	end
	scope:Connect(NetMsg.ConnectNotifyFarmFeedback(OnFeedback))

	local lastZapAt = 0
	local function TriggerZapDirect(): ()
		local now = os.clock()
		if now - lastZapAt < 0.15 then return end
		lastZapAt = now
		self:TriggerAction("zap")
	end

	-- 键盘备选快捷键 (Q 电击, E 收集, F 加速孵化)
	local function OnZap(_: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			TriggerZapDirect()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end
	local function OnCollect(_: string, state: Enum.UserInputState): Enum.ContextActionResult
		return if state == Enum.UserInputState.Begin and self:TriggerAction("collect") then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
	end
	contextActionService:BindAction("Farm_zap", OnZap, false, Enum.KeyCode.Q)
	contextActionService:BindAction("Farm_collect", OnCollect, false, Enum.KeyCode.E)
	local function OnHatch(_: string, state: Enum.UserInputState): Enum.ContextActionResult
		if UserInputService:GetFocusedTextBox() or GuiService.MenuIsOpen then speciesUI:StopHatchHold(); return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin then return if speciesUI:StartHatchHold() then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass end
		local wasHolding = speciesUI:IsHatchHolding()
		speciesUI:StopHatchHold()
		return if wasHolding then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
	end
	contextActionService:BindAction("Farm_hatch", OnHatch, false, Enum.KeyCode.F)

	-- 绑定武器 Tool 道具生命周期与手持激活 (左键攻击)
	local function BindWeaponTool(tool: Instance): ()
		if not tool:IsA("Tool") or tool.Name ~= "FarmWeapon" then return end
		local toolScope = LifecycleTool.new()
		scope:Connect(tool.AncestryChanged:Connect(function(_, parent)
			if not parent or not tool:IsDescendantOf(game) then
				toolScope:Destroy()
			end
		end))
		toolScope:Connect(tool.Activated:Connect(function()
			TriggerZapDirect()
		end))
		toolScope:Connect(tool.Unequipped:Connect(function()
			task.defer(function()
				if not self.initialized then return end
				local char = localPlayer.Character
				local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
				local backpack = localPlayer:FindFirstChildOfClass("Backpack")
				if hum and hum.Health > 0 and backpack and tool.Parent == backpack then
					hum:EquipTool(tool)
				end
			end)
		end))
		local char = localPlayer.Character
		local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
		local bp = localPlayer:FindFirstChildOfClass("Backpack")
		if hum and hum.Health > 0 and bp and tool.Parent == bp then
			hum:EquipTool(tool)
		end
	end

	local function WatchContainer(container: Instance): ()
		for _, child in container:GetChildren() do
			BindWeaponTool(child)
		end
		scope:Connect(container.ChildAdded:Connect(BindWeaponTool))
	end

	local function OnCharacterAdded(char: Model): ()
		WatchContainer(char)
		local bp = localPlayer:WaitForChild("Backpack", 5)
		if bp then WatchContainer(bp) end
	end
	if localPlayer.Character then OnCharacterAdded(localPlayer.Character) end
	scope:Connect(localPlayer.CharacterAdded:Connect(OnCharacterAdded))
	local initialBp = localPlayer:FindFirstChildOfClass("Backpack")
	if initialBp then WatchContainer(initialBp) end

	-- 鼠标右键收集判断：检测范围内是否存在烤肉，若有则即时拾取；无烤肉时保证旋转镜头无缝流畅且不误报飘字
	local function HasNearbyRoasts(): boolean
		local character = localPlayer.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if not root or not root:IsA("BasePart") then return false end
		local plotId = localPlayer:GetAttribute("FarmPlotId")
		if typeof(plotId) ~= "string" then return false end
		local personalFarms = workspace:FindFirstChild("PersonalFarms")
		local farmPlot = if personalFarms then personalFarms:FindFirstChild(plotId) else nil
		local cookedFolder = if farmPlot then farmPlot:FindFirstChild("CookedFood") else nil
		if not cookedFolder then return false end
		local rootPos = root.Position
		for _, item in cookedFolder:GetChildren() do
			if item:IsA("BasePart") then
				if (item.Position - rootPos).Magnitude <= 35 then return true end
			elseif item:IsA("Model") then
				local primary = item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")
				if primary and (primary.Position - rootPos).Magnitude <= 35 then return true end
			end
		end
		return false
	end

	local function OnInputBegan(input: InputObject, gameProcessed: boolean): ()
		if gameProcessed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			TriggerZapDirect()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			if HasNearbyRoasts() then
				self:TriggerAction("collect")
			end
		end
	end
	scope:Connect(UserInputService.InputBegan:Connect(OnInputBegan))
end

function ClientRoastChickenFarmManager.TriggerAction(self: ClientRoastChickenFarmManager, action: FarmConfig.FarmAction): boolean
	if self.initialized and ClientGameInfo.GetFarmInfo().ready == true and not UIManager.HasShowingWindow() and not UserInputService:GetFocusedTextBox() and not GuiService.MenuIsOpen then
		if action == "zap" then
			local tier = ClientGameInfo.GetFarmInfo().zap or 1
			FarmSoundTool.Play("Zap_T" .. tostring(math.clamp(tier, 1, 5)))
			NetMsg.FireRequestFarmAction("zap")
		else
			if action == "collect" then
				FarmSoundTool.Play("UIClick")
			end
			NetMsg.FireRequestFarmAction(action)
		end
		return true
	end
	return false
end

function ClientRoastChickenFarmManager.Destroy(self: ClientRoastChickenFarmManager): ()
	if not self.initialized then
		return
	end
	self.initialized = false
	contextActionService:UnbindAction("Farm_zap")
	contextActionService:UnbindAction("Farm_collect")
	contextActionService:UnbindAction("Farm_hatch")
	if self.scope then
		self.scope:Destroy()
		self.scope = nil
	end
	if self.hud then
		self.hud:Destroy()
		self.hud = nil
	end
	if self.speciesUI then self.speciesUI:Destroy(); self.speciesUI = nil end
	ClientGameInfo.DestroyFarmInfo()
end

return ClientRoastChickenFarmManager