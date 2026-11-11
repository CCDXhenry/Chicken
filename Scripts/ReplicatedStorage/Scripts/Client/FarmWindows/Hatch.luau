-- 孵化独立窗口：绑定倒计时、免费长按加速与立即孵化确认
--!strict
local Storage = game:GetService("ReplicatedStorage")
local Input = game:GetService("UserInputService")
local Info = require(script.Parent.Parent.ClientGameInfo)
local Common = require(script.Parent.Common)
local Controller = require(script.Parent.Parent.ClientHatchController)
local Hatch = {}
function Hatch.Bind(ctx: Common.Context): ()
	local stop = Controller.Stop
	local eggId = Info.GetFarmInfo().eggId
	local instant = Common.Button(ctx.panel, "InstantButton")
	local accelerate = Common.Button(ctx.panel, "AccelerateButton")
	local activeInput: InputObject? = nil
	local duration = math.max(1, (Info.GetFarmInfo().eggEndTime or 0) - workspace:GetServerTimeNow())
	local function Render(): ()
		local info = Info.GetFarmInfo()
		if info.eggId ~= eggId then stop(); ctx.window:Close(); return end
		local seconds = math.max(0, (info.eggEndTime or 0) - workspace:GetServerTimeNow())
		Common.Wallet(ctx)
		Common.Label(ctx.panel, "InfoText", (info.eggSpecies or "Egg") .. "  /  " .. (info.eggQuality or "normal"))
		Common.Label(ctx.panel, "TimeText", string.format("%.1f seconds", seconds))
		local fill = ctx.panel:WaitForChild("ProgressFrame"):WaitForChild("FillFrame") :: Frame
		fill.Size = UDim2.fromScale(math.clamp(1 - seconds / duration, 0, 1), 1)
		Common.State(instant, if ctx.pending then "Working…" else "Hatch now  /  " .. Common.Price(info.eggPrice), not ctx.pending and info.cash >= (info.eggPrice or 0))
	end
	local function OnBegan(input: InputObject): ()
		if (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1) and Controller.Start("Window", eggId, input) then activeInput = input end
	end
	local function OnEnded(input: InputObject): ()
		if input == activeInput or (activeInput and input.UserInputType == Enum.UserInputType.MouseButton1) then activeInput = nil; stop() end
	end
	local function OnInstant(): () stop(); if instant.Active and eggId then Common.Submit(ctx, { action = "requestInstantHatch", targetId = eggId }, Render) end end
	ctx.window.scope:Connect(accelerate.InputBegan:Connect(OnBegan))
	ctx.window.scope:Connect(Input.InputEnded:Connect(OnEnded))
	ctx.window.scope:Connect(instant.Activated:Connect(OnInstant))
	local oldClose = ctx.window.onClosed
	ctx.window.onClosed = function(): () stop(); if oldClose then oldClose() end end
	Common.Observe(ctx, Render)
	ctx.window.scope:Spawn(function(): () while ctx.window.scope.alive do task.wait(0.1); if ctx.window.scope.alive then Render() end end end)
end
return Hatch
