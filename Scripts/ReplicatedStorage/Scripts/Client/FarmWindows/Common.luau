-- 农场窗口公共绑定：管理模板查找、文字刷新、请求节流和窗口生命周期
--!strict
local Storage = game:GetService("ReplicatedStorage")
local Shared = Storage.Scripts.Shared
local UIManager = require(script.Parent.Parent.UIManager)
local WindowBase = require(script.Parent.Parent.UIManager.WindowBase)
local UIActions = require(script.Parent.Parent.UIManager.UIActions)
local Info = require(script.Parent.Parent.ClientGameInfo)
local Msg = require(script.Parent.Parent.ClientMsg)
local Text = require(script.Parent.Parent.FarmTextTool)
local Net = require(Shared.NetMsg)
local Request = require(Shared.FarmRequest)
local Rules = require(Shared.FarmUIConfig)
local NumberFormat = require(Shared.FarmNumberFormat)
local UIAdapter = require(Storage.Core.Scripts.Client.UIAdapter)
local Common = {}
export type Context = {
	window: WindowBase.WindowBase, panel: Frame, pending: boolean,
	open: (string) -> (), allowed: () -> boolean,
}
function Common.Label(parent: Instance, name: string, value: string): ()
	local label = parent:FindFirstChild(name)
	assert(label and label:IsA("TextLabel"), "Missing text template: " .. name)
	Text.Set(label, value)
end
function Common.Button(parent: Instance, name: string): ImageButton
	local button = parent:FindFirstChild(name)
	assert(button and button:IsA("ImageButton"), "Missing button template: " .. name)
	return button
end
function Common.State(button: ImageButton, value: string, enabled: boolean): ()
	Text.Set(button, value)
	button.Active = enabled
	button.Selectable = enabled
	local alpha = button:GetAttribute(if enabled then "EnabledBackgroundTransparency" else "DisabledBackgroundTransparency")
	if typeof(alpha) == "number" then button.BackgroundTransparency = alpha end
end
function Common.Price(price: number?): string
	return if price then NumberFormat.Number(price) .. " coins" else "Maximum level"
end
function Common.New(frame: Frame, id: string, actions: UIActions.UIActions, open: (string) -> (), allowed: () -> boolean): Context
	local window = WindowBase.new(frame, id, actions)
	local panel = frame:WaitForChild("PanelFrame") :: Frame
	local ctx: Context = { window = window, panel = panel, open = open, allowed = allowed, pending = false }
	UIAdapter.AddAdaptiveFrame(frame, UIAdapter.AdaptiveType.Center)
	local function OnClose(): () window:Close() end
	window.scope:Connect(Common.Button(panel, "CloseButton").Activated:Connect(OnClose))
	local back = panel:FindFirstChild("BackButton")
	if back and back:IsA("ImageButton") then
		local function OnBack(): () if allowed() then open("ToolShop") end end
		window.scope:Connect(back.Activated:Connect(OnBack))
	end
	window.onClosed = function(): () Text.Remove(frame) end
	return ctx
end
function Common.Observe(ctx: Context, render: () -> ()): ()
	local function OnChanged(): () if ctx.window.scope.alive then ctx.pending = false; render() end end
	ctx.window.scope:Connect(Msg.ConnectFarmInfoChanged(OnChanged))
	ctx.window.scope:Connect(Net.ConnectNotifyFarmFeedback(OnChanged))
	render()
	UIManager.FitMarkedRoot(ctx.window.frame)
end
function Common.Wallet(ctx: Context): ()
	Common.Label(ctx.panel, "WalletText", NumberFormat.Number(Info.GetFarmInfo().cash) .. " coins")
end
function Common.Submit(ctx: Context, command: Request.Request, render: () -> ()): ()
	if ctx.pending or not ctx.allowed() or not Info.GetFarmInfo().ready or UIManager.IsWindowShowing("FarmConfirmation") then return end
	ctx.pending = true
	render()
	local payload: { [string]: unknown } = { action = command.action, expectedStep = command.expectedStep, speciesId = command.speciesId, tier = command.tier, targetId = command.targetId, confirmationId = command.confirmationId, aim = command.aim }
	Net.FireRequestFarmCommand(payload)
	ctx.window.scope:Delay(Rules.RequestTimeout, function(): () ctx.pending = false; render() end)
end
return Common
