-- 蛋标牌回归：使用本地夹具隔离网络，验证悬浮间隔、进度、加速确认和共享冷却
--!strict
assert(game:GetService("RunService"):IsClient(), "Run in Play client")
local Storage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Info = require(Storage.Scripts.Client.ClientGameInfo)
local Net = require(Storage.Scripts.Shared.NetMsg)
local Controller = require(Storage.Scripts.Client.ClientHatchController)
local Binder = require(Storage.Scripts.Client.EggBillboardBinder)
local UI = require(Storage.Scripts.Client.UIManager)
local originalInfo, originalSend = Info.GetFarmInfo, Net.FireRequestFarmCommand
local fake = table.clone(originalInfo())
fake.ready, fake.eggId = true, "billboard-fixture"
local requests: { { [string]: unknown } } = {}
local model = Instance.new("Model")
model.Name = "BillboardFixture"
model:SetAttribute("EntityId", fake.eggId)
model:SetAttribute("SpeciesId", "chicken")
model:SetAttribute("QualityId", "normal")
model:SetAttribute("HatchStartTime", workspace:GetServerTimeNow())
model:SetAttribute("HatchEndTime", workspace:GetServerTimeNow() + 60)
model:SetAttribute("HatchDuration", 60)
model:SetAttribute("HatchAccelerationSequence", 0)
local shell = Instance.new("Part")
shell.Size, shell.Shape, shell.Anchored = Vector3.new(1.35,1.73,1.35), Enum.PartType.Ball, true
shell.Parent = model; model.PrimaryPart = shell
local gui = Storage.UI.EggSignGui:Clone()
gui.Adornee = shell; gui.Parent = Players.LocalPlayer.PlayerGui
local binding: Binder.Binding? = nil
local checks: { string } = {}
Info.GetFarmInfo = function() return fake end
Net.FireRequestFarmCommand = function(command: { [string]: unknown }): () table.insert(requests, command) end
UI.CloseAllWindow(); Controller.Stop()
local success, failure = xpcall(function(): boolean
	binding = Binder.Bind(shell, gui)
	local content = gui:WaitForChild("ContentFrame")
	local expanded = content:WaitForChild("ExpandedFrame") :: Frame
	local compact = content:WaitForChild("CompactFrame") :: Frame
	assert(expanded.Visible and not compact.Visible)
	assert(gui.StudsOffset.Y - gui.Size.Y.Scale * .5 > shell.Size.Magnitude * .5, "Label overlaps egg bounding sphere")
	table.insert(checks, "Expanded egg label clears model")
	local feedback = expanded:WaitForChild("FeedbackText") :: TextLabel
	assert(not feedback.Visible)
	assert(Controller.Start("Billboard", fake.eggId))
	assert(not Controller.Start("Keyboard", fake.eggId), "Competing input started another loop")
	assert(#requests == 1 and requests[1].targetId == fake.eggId)
	Controller.Stop()
	assert(Controller.Start("Window", fake.eggId))
	assert(#requests == 1, "Switching input bypassed shared cooldown")
	Controller.Stop()
	assert(not feedback.Visible, "Request displayed unconfirmed success")
	table.insert(checks, "One input owner, shared cooldown, no optimistic success")
	model:SetAttribute("HatchEndTime", (model:GetAttribute("HatchEndTime") :: number) - 1)
	model:SetAttribute("HatchAccelerationSequence", 1)
	task.wait(.15)
	assert(feedback.Visible, "Server-confirmed boost feedback missing")
	local progress = expanded:WaitForChild("ProgressFrame"):WaitForChild("FillFrame") :: Frame
	assert(progress.Size.X.Scale > 0)
	table.insert(checks, "Authoritative acceleration updates feedback and progress")
	fake.eggId = nil; task.wait(.15)
	assert(compact.Visible and not expanded.Visible and not Controller.IsHolding())
	table.insert(checks, "Losing target collapses interactions and stops hold")
	local current = binding
	assert(current); current.Destroy(); binding = nil
	shell.Size *= 2.5
	fake.eggId = "billboard-fixture"
	binding = Binder.Bind(shell, gui)
	assert(gui.StudsOffset.Y - gui.Size.Y.Scale * .5 > shell.Size.Magnitude * .5, "Giant label overlaps model")
	table.insert(checks, "Giant egg clearance follows actual shell dimensions")
	return true
end, debug.traceback)
Controller.Stop()
if binding then binding.Destroy() end
gui:Destroy(); model:Destroy()
Info.GetFarmInfo, Net.FireRequestFarmCommand = originalInfo, originalSend
assert(success, failure)
return checks
