-- 蛋标牌绑定器：驱动结构化倒计时、品质、服务端加速反馈与蛋旁长按交互
--!strict
local Storage = game:GetService("ReplicatedStorage")
local Input = game:GetService("UserInputService")
local Lifecycle = require(Storage.Scripts.Shared.LifecycleTool)
local Config = require(Storage.Scripts.Shared.FarmEconomyConfig)
local Info = require(script.Parent.ClientGameInfo)
local Text = require(script.Parent.FarmTextTool)
local UI = require(script.Parent.UIManager)
local Hatch = require(script.Parent.ClientHatchController)
local Binder = {}
export type Binding = { Destroy: () -> () }
local function NumberAttribute(object: Instance, name: string, fallback: number): number
	local value = object:GetAttribute(name); return if typeof(value) == "number" then value else fallback
end
function Binder.Bind(part: BasePart, gui: BillboardGui): Binding
	local scope = Lifecycle.new()
	local model = part:FindFirstAncestorOfClass("Model")
	assert(model, "Egg must belong to a model")
	local frame = gui:WaitForChild("ContentFrame") :: Frame
	local compact = frame:WaitForChild("CompactFrame") :: Frame
	local expanded = frame:WaitForChild("ExpandedFrame") :: Frame
	local id = model:GetAttribute("EntityId")
	assert(typeof(id) == "string", "Egg missing EntityId")
	local accelerate = expanded:WaitForChild("AccelerateButton") :: ImageButton
	local details = expanded:WaitForChild("DetailsButton") :: ImageButton
	local feedback = expanded:WaitForChild("FeedbackText") :: TextLabel
	local lastSequence = NumberAttribute(model, "HatchAccelerationSequence", 0)
	local lastFinish = NumberAttribute(model, "HatchEndTime", 0)
	local feedbackUntil = 0
	local wasExpanded: boolean? = nil
	local qualityId = model:GetAttribute("QualityId")
	local qualityName = if qualityId == "golden" then "Golden" elseif qualityId == "rainbow" then "Rainbow" elseif qualityId == "giant" then "Giant" else "Normal"
	local speciesId = model:GetAttribute("SpeciesId")
	local species = if typeof(speciesId) == "string" then Config.GetSpecies(speciesId) else nil
	for _, panel in { compact, expanded } do
		Text.Set(panel:WaitForChild("QualityText") :: TextLabel, qualityName)
		Text.Set(panel:WaitForChild("NameText") :: TextLabel, if species then species.name else "Egg")
	end
	local lastActionText = ""
	local function Render(): ()
		local info = Info.GetFarmInfo()
		local selected = info.ready == true and info.eggId == id and not UI.HasShowingWindow()
		if wasExpanded ~= selected then
			wasExpanded = selected
			compact.Visible, expanded.Visible = not selected, selected
			local size = gui:GetAttribute(if selected then "ExpandedSize" else "CompactSize")
			assert(typeof(size) == "Vector2", "Missing egg size contract")
			gui.Size = UDim2.fromScale(size.X, size.Y)
			local gap = NumberAttribute(gui, "ModelClearanceStuds", 0.3)
			-- 相机空间上移：用蛋壳包围球和半个标牌高度预留间隔，巨型蛋同样适用。
			gui.StudsOffset = Vector3.new(0, part.Size.Magnitude * 0.5 + gap + size.Y * 0.5, 0)
		end
		local finish = NumberAttribute(model, "HatchEndTime", 0)
		local start = NumberAttribute(model, "HatchStartTime", finish - 1)
		local duration = NumberAttribute(model, "HatchDuration", math.max(1, finish - start))
		local sequence = NumberAttribute(model, "HatchAccelerationSequence", 0)
		local now = workspace:GetServerTimeNow()
		if sequence > lastSequence and finish < lastFinish then
			feedbackUntil = os.clock() + NumberAttribute(gui, "FeedbackSeconds", .65)
			lastSequence, lastFinish = sequence, finish
		end
		local remaining = math.max(0, finish - now)
		local ratio = math.clamp(1 - remaining / duration, 0, 1)
		local color = if typeof(qualityId) == "string" then gui:GetAttribute("Quality_" .. qualityId) else nil
		for _, panel in { compact, expanded } do
			local time = panel:WaitForChild("TimeText") :: TextLabel
			time.Text = string.format("%.1fs", remaining)
			local progress = panel:WaitForChild("ProgressFrame"):WaitForChild("FillFrame") :: Frame
			progress.Size = UDim2.fromScale(ratio, 1)
			local qualityText = panel:WaitForChild("QualityText") :: TextLabel
			if typeof(color) == "Color3" then qualityText.TextColor3 = color end
		end
		accelerate.Active, details.Active = selected, selected
		if not selected then return end
		local holding = Hatch.IsHolding(id)
		local actionText = if holding then "Accelerating…" elseif Input.PreferredInput == Enum.PreferredInput.Touch then "Hold to accelerate" else "[F] Hold to accelerate"
		if actionText ~= lastActionText then Text.Set(accelerate, actionText); lastActionText = actionText end
		local fill = accelerate:WaitForChild("CooldownFrame"):WaitForChild("FillFrame") :: Frame
		fill.Size = UDim2.fromScale(Hatch.CooldownFraction(), 1)
		feedback.Visible = os.clock() < feedbackUntil
	end
	local function OnBegin(input: InputObject): ()
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then Hatch.Start("Billboard", id, input) end
	end
	local function OnDetails(): () if Info.GetFarmInfo().eggId == id and not UI.HasShowingWindow() then Hatch.OpenDetails() end end
	scope:Connect(accelerate.InputBegan:Connect(OnBegin))
	scope:Connect(details.Activated:Connect(OnDetails))
	Render()
	scope:Spawn(function(): () while scope.alive do task.wait(.1); if scope.alive then Render() end end end)
	return { Destroy = function(): () if Hatch.IsHolding(id) then Hatch.Stop() end; scope:Destroy(); Text.Remove(gui) end }
end
return Binder
