-- 客户端农场管理器：负责输入请求、反馈分发与界面生命周期
--!strict
local contextActionService = game:GetService("ContextActionService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local sharedScripts = replicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local FarmConfig = require(sharedScripts:WaitForChild("FarmConfig"))
local LifecycleTool = require(sharedScripts:WaitForChild("LifecycleTool"))
local ClientGameInfo = require(script.Parent:WaitForChild("ClientGameInfo"))
local RoastChickenHUDFrame = require(script.Parent:WaitForChild("RoastChickenHUDFrame"))
local ClientRoastChickenFarmManager = {}
ClientRoastChickenFarmManager.__index = ClientRoastChickenFarmManager
export type ClientRoastChickenFarmManager = typeof(setmetatable(
	{} :: { hud: RoastChickenHUDFrame.RoastChickenHUDFrame?, scope: LifecycleTool.Lifecycle?, initialized: boolean },
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
	local function OnFeedback(message: string, kind: string?): ()
		if kind == "sale" then
			hud:ShowSaleNotice(message)
		else
			hud:ShowMessage(message)
		end
	end
	scope:Connect(NetMsg.ConnectNotifyFarmFeedback(OnFeedback))
	local function OnZap(_: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			self:TriggerAction("zap")
		end
		return Enum.ContextActionResult.Sink
	end
	local function OnCollect(_: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			self:TriggerAction("collect")
		end
		return Enum.ContextActionResult.Sink
	end
	contextActionService:BindAction("Farm_zap", OnZap, false, Enum.KeyCode.Q)
	contextActionService:BindAction("Farm_collect", OnCollect, false, Enum.KeyCode.E)
end
function ClientRoastChickenFarmManager.TriggerAction(self: ClientRoastChickenFarmManager, action: FarmConfig.FarmAction): ()
	if self.initialized then
		NetMsg.FireRequestFarmAction(action)
	end
end
function ClientRoastChickenFarmManager.Destroy(self: ClientRoastChickenFarmManager): ()
	if not self.initialized then
		return
	end
	self.initialized = false
	contextActionService:UnbindAction("Farm_zap")
	contextActionService:UnbindAction("Farm_collect")
	if self.scope then
		self.scope:Destroy()
		self.scope = nil
	end
	if self.hud then
		self.hud:Destroy()
		self.hud = nil
	end
	ClientGameInfo.DestroyFarmInfo()
end
return ClientRoastChickenFarmManager
