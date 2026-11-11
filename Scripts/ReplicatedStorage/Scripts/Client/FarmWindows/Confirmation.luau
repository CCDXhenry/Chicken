-- 确认独立窗口：消费服务端令牌并在取消或销毁时通知服务端
--!strict
local Storage = game:GetService("ReplicatedStorage")
local Net = require(Storage.Scripts.Shared.NetMsg)
local Info = require(script.Parent.Parent.ClientGameInfo)
local Common = require(script.Parent.Common)
local Confirmation = {}
function Confirmation.Bind(ctx: Common.Context): ()
	local info = Info.GetFarmInfo()
	local token = info.confirmationId
	local submitted = false
	Common.Label(ctx.panel, "BodyText", info.confirmationMessage or "")
	Common.Label(ctx.panel, "RiskText", info.confirmationRisk or "")
	Common.Wallet(ctx)
	local function OnConfirm(): ()
		if submitted or not token or Info.GetFarmInfo().confirmationId ~= token then return end
		submitted = true
		Net.FireRequestFarmCommand({ action = "confirm", confirmationId = token })
		ctx.window:Close()
	end
	local function OnCancel(): () ctx.window:Close() end
	ctx.window.scope:Connect(Common.Button(ctx.panel, "ConfirmButton").Activated:Connect(OnConfirm))
	ctx.window.scope:Connect(Common.Button(ctx.panel, "CancelButton").Activated:Connect(OnCancel))
	local oldClose = ctx.window.onClosed
	ctx.window.onClosed = function(): ()
		if not submitted and token and Info.GetFarmInfo().confirmationId == token then Net.FireRequestFarmCommand({ action = "cancel", confirmationId = token }) end
		if oldClose then oldClose() end
	end
end
return Confirmation
