-- 农场客户端回归：仅在 Play 客户端执行，验证固定画布、全屏遮罩与界面重复初始化和销毁
--!strict
assert(game:GetService("RunService"):IsRunning(), "Run this test in a Play client")
local storage = game:GetService("ReplicatedStorage")
local clientScripts = storage.Scripts.Client
local HUD = require(clientScripts.RoastChickenHUDFrame)
local playerGui = game.Players.LocalPlayer.PlayerGui
local screen = storage.UI.GameScreenGui:Clone()
screen.Name = "FarmLifecycleFixture"
screen.Parent = playerGui
local hud = HUD.new(function(): () end)
local success, failure = xpcall(function(): boolean
	hud:Init(screen)
	hud:Init(screen)
	local root = screen:FindFirstChild("RoastChickenHUDFrame") :: Frame
	assert(root.Size == UDim2.fromOffset(1920, 1080), "Canvas dimensions changed")
	assert(root.AnchorPoint == Vector2.new(0.5, 0.5) and root.Position == UDim2.fromScale(0.5, 0.5))
	local scale = root:FindFirstChildOfClass("UIScale") :: UIScale
	local expected = math.min(screen.AbsoluteSize.X / 1920, screen.AbsoluteSize.Y / 1080)
	assert(math.abs(scale.Scale - expected) < 0.00001, "Canvas scale mismatch")
	assert(not root:FindFirstChild("SystemReservedAreasFrame") and not root:FindFirstChild("UiLayoutRegionsFrame"))
	assert(not root:FindFirstChild("ScreenLayoutGuideFrame"), "Design guide leaked into runtime")
	local modal = screen:FindFirstChild("ModalButton") :: GuiObject
	assert(modal.Size == UDim2.fromScale(1, 1) and modal.Active, "Modal must block the full viewport")
	local count = 0
	for _, obj in screen:GetChildren() do
		if obj.Name == "RoastChickenHUDFrame" then
			count += 1
		end
	end
	assert(count == 1, "Duplicate HUD after repeated Init")
	hud:ShowMessage("测试延迟销毁")
	hud:Destroy()
	hud:Destroy()
	task.wait(0.1)
	return true
end, debug.traceback)
hud:Destroy()
screen:Destroy()
assert(success, failure)
return { "固定1920画布", "居中等比缩放", "纯设计参考隔离", "全屏遮罩", "HUD重复初始化", "幂等销毁" }
