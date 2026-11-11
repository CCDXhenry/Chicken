-- 共享孵化输入控制器：统一键盘、蛋旁按钮和详情窗口的长按、冷却与停止条件
--!strict
local Players = game:GetService("Players")
local Input = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Storage = game:GetService("ReplicatedStorage")
local Config = require(Storage.Scripts.Shared.FarmEconomyConfig)
local Lifecycle = require(Storage.Scripts.Shared.LifecycleTool)
local Net = require(Storage.Scripts.Shared.NetMsg)
local Info = require(script.Parent.ClientGameInfo)
local Msg = require(script.Parent.ClientMsg)
local UI = require(script.Parent.UIManager)
local Controller = {}
export type Source = "Keyboard" | "Billboard" | "Window"
local scope: Lifecycle.Lifecycle? = nil
local target: string? = nil
local source: Source? = nil
local pointer: InputObject? = nil
local pointerConnection: RBXScriptConnection? = nil
local nextRequestAt = 0
local openDetails: (() -> ())? = nil
local PollSeconds = 0.05
function Controller.Stop(): ()
	target, source, pointer = nil, nil, nil
	if pointerConnection then pointerConnection:Disconnect(); pointerConnection = nil end
end
function Controller.IsHolding(id: string?): boolean return target ~= nil and (id == nil or target == id) end
function Controller.CooldownFraction(): number return math.clamp(1 - (nextRequestAt - os.clock()) / Config.HatchCooldownSeconds, 0, 1) end
local function Allowed(inputSource: Source): boolean
	if not Info.GetFarmInfo().ready or Input:GetFocusedTextBox() or GuiService.MenuIsOpen or UI.IsWindowShowing("FarmConfirmation") then return false end
	return not UI.HasShowingWindow() or (inputSource == "Window" and UI.IsWindowShowing("FarmHatch"))
end
function Controller.Start(inputSource: Source, id: string?, input: InputObject?): boolean
	local current = Info.GetFarmInfo().eggId
	if not scope or not current or (id and current ~= id) or not Allowed(inputSource) or target then return false end
	target, source, pointer = current, inputSource, input
	if input then
		pointerConnection = input:GetPropertyChangedSignal("UserInputState"):Connect(function(): ()
			if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then Controller.Stop() end
		end)
	end
	-- 冷却由共享时钟维护，松手重按或切换入口不会重新获得一次免费请求。
	if os.clock() >= nextRequestAt then
		nextRequestAt = os.clock() + Config.HatchCooldownSeconds
		Net.FireRequestFarmCommand({ action = "accelerateEgg", targetId = current })
	end
	return true
end
function Controller.OpenDetails(): () Controller.Stop(); if openDetails then openDetails() end end
function Controller.Init(onDetails: () -> ()): ()
	openDetails = onDetails
	if scope then return end
	local lifetime = Lifecycle.new(); scope = lifetime
	local function OnStop(): () Controller.Stop() end
	lifetime:Connect(Input.InputEnded:Connect(function(input: InputObject): ()
		if (source == "Keyboard" and input.KeyCode == Enum.KeyCode.F) or input == pointer or (pointer and pointer.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then OnStop() end
	end))
	lifetime:Connect(Input.WindowFocusReleased:Connect(OnStop))
	lifetime:Connect(Input.TextBoxFocused:Connect(OnStop))
	lifetime:Connect(GuiService.MenuOpened:Connect(OnStop))
	lifetime:Connect(Players.LocalPlayer.CharacterRemoving:Connect(OnStop))
	lifetime:Connect(Players.LocalPlayer.CharacterAdded:Connect(OnStop))
	lifetime:Connect(Msg.ConnectOpenWindow(OnStop))
	lifetime:Connect(Msg.ConnectCloseWindow(OnStop))
	lifetime:Connect(Msg.ConnectFarmInfoChanged(function(): ()
		if target and (Info.GetFarmInfo().eggId ~= target or not Info.GetFarmInfo().ready) then OnStop() end
	end))
	lifetime:Spawn(function(): ()
		while lifetime.alive do
			task.wait(PollSeconds)
			local id = target
			local origin: Source? = source
			if id and origin then
				if Info.GetFarmInfo().eggId ~= id or not Allowed(origin) then OnStop()
				elseif os.clock() >= nextRequestAt then
					nextRequestAt = os.clock() + Config.HatchCooldownSeconds
					Net.FireRequestFarmCommand({ action = "accelerateEgg", targetId = id })
				end
			end
		end
	end)
end
function Controller.Destroy(): ()
	Controller.Stop(); if scope then scope:Destroy(); scope = nil end
	openDetails = nil; nextRequestAt = 0
end
return Controller
