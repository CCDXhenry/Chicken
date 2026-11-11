-- 客户端农场管理器：负责输入请求、反馈分发与界面生命周期
--!strict
local contextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local sharedScripts = replicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local FarmConfig = require(sharedScripts:WaitForChild("FarmConfig"))
local LifecycleTool = require(sharedScripts:WaitForChild("LifecycleTool"))
local ClientGameInfo = require(script.Parent:WaitForChild("ClientGameInfo"))
local RoastChickenHUDFrame = require(script.Parent:WaitForChild("RoastChickenHUDFrame"))
local SpeciesManager = require(script.Parent:WaitForChild("ClientFarmSpeciesManager"))
local UIManager = require(script.Parent:WaitForChild("UIManager"))
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
	local equipment = (hud.container:WaitForChild("EquipmentButton") :: ImageButton)
	local function OnEquipment(): () speciesUI:Open("Equipment") end
	scope:Connect(equipment.Activated:Connect(OnEquipment))
	local function OnFeedback(message: string, kind: string?): ()
		if kind == "sale" then
			hud:ShowSaleNotice(message)
		else
			hud:ShowMessage(message)
		end
	end
	scope:Connect(NetMsg.ConnectNotifyFarmFeedback(OnFeedback))
	local function OnZap(_: string, state: Enum.UserInputState): Enum.ContextActionResult
		return if state == Enum.UserInputState.Begin and self:TriggerAction("zap") then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
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
end
function ClientRoastChickenFarmManager.TriggerAction(self: ClientRoastChickenFarmManager, action: FarmConfig.FarmAction): boolean
	if self.initialized and ClientGameInfo.GetFarmInfo().ready == true and not UIManager.HasShowingWindow() and not UserInputService:GetFocusedTextBox() and not GuiService.MenuIsOpen then
		local camera = workspace.CurrentCamera
		if action == "zap" and camera then
			local direction = camera.CFrame.LookVector
			NetMsg.FireRequestFarmCommand({ action = action, aim = { x = direction.X, y = direction.Y, z = direction.Z } })
		else NetMsg.FireRequestFarmAction(action) end
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
