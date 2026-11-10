--!strict
local runService: RunService = game:GetService("RunService")

local UIAdapter = {}

UIAdapter.AdaptiveType = {
	FullScreen = 1,
	Center = 2,
}

local initialized: boolean = false
local designScreenSize: Vector2
local screenSize: Vector2
local billboardGuiRenderStepBound: boolean = false

type AdaptiveFrame = {
	frame: Frame,
	scaleOrigin: number,
	sizeXOrigin: number,
	sizeYOrigin: number,
}
type AdaptiveBillboardGui = {
	billboardGui: BillboardGui,
	sizeXOrigin: number,
	sizeYOrigin: number,
}
type AdaptiveFrameOfBillboardGui = {
	frame: Frame,
	billboardGui: BillboardGui,
	frameUIScale: UIScale,
}

local adaptiveFrames: { [number]: { AdaptiveFrame } } = {}
for adaptiveTypeKey: string, adaptiveTypeValue: number in pairs(UIAdapter.AdaptiveType) do
	adaptiveFrames[adaptiveTypeValue] = {}
end
local adaptiveBillboardGuis: { AdaptiveBillboardGui } = {}
local adaptiveFramesOfBillboardGui: { AdaptiveFrameOfBillboardGui } = {}

local function GetOpenAnimScale(frame: Frame): number
	local openAnimScale: number? = frame:GetAttribute("OpenAnimScale") :: number?
	return openAnimScale or 1
end

function UIAdapter.SetOpenAnimScale(frame: Frame, openAnimScale: number)
	frame:SetAttribute("OpenAnimScale", openAnimScale)
end

local function UpdateAdaptiveFrame(adaptiveType: number, adaptiveFrame: AdaptiveFrame)
	local uiScale: UIScale? = adaptiveFrame.frame:FindFirstChild("UIScale") :: UIScale?
	if uiScale == nil then
		return
	end
	uiScale.Scale = math.min(screenSize.X / designScreenSize.X, screenSize.Y / designScreenSize.Y)
		* adaptiveFrame.scaleOrigin
		* GetOpenAnimScale(adaptiveFrame.frame)
	if adaptiveType == UIAdapter.AdaptiveType.FullScreen then
		local ratio: number = screenSize.X / screenSize.Y
		local designRatio: number = designScreenSize.X / designScreenSize.Y
		if ratio > designRatio then
			adaptiveFrame.frame.Size = UDim2.fromOffset(adaptiveFrame.sizeXOrigin * ratio / designRatio, adaptiveFrame.sizeYOrigin)
		elseif ratio < designRatio then
			adaptiveFrame.frame.Size = UDim2.fromOffset(adaptiveFrame.sizeXOrigin, adaptiveFrame.sizeYOrigin * designRatio / ratio)
		else
			adaptiveFrame.frame.Size = UDim2.fromOffset(adaptiveFrame.sizeXOrigin, adaptiveFrame.sizeYOrigin)
		end
	end
end

local function UpdateAdaptiveFrames()
	for adaptiveType: number, adaptiveFramesCurrType: { AdaptiveFrame } in pairs(adaptiveFrames) do
		for adaptiveFrameIndex: number, adaptiveFrame: AdaptiveFrame in adaptiveFramesCurrType do
			UpdateAdaptiveFrame(adaptiveType, adaptiveFrame)
		end
	end
end

local function UpdateAdaptiveBillboardGui(adaptiveBillboardGui: AdaptiveBillboardGui)
	local scale: number = math.min(screenSize.X / designScreenSize.X, screenSize.Y / designScreenSize.Y)
	adaptiveBillboardGui.billboardGui.Size = UDim2.fromOffset(adaptiveBillboardGui.sizeXOrigin * scale, adaptiveBillboardGui.sizeYOrigin * scale)
end

local function UpdateAdaptiveBillboardGuis()
	for adaptiveBillboardGuiIndex: number, adaptiveBillboardGui: AdaptiveBillboardGui in adaptiveBillboardGuis do
		UpdateAdaptiveBillboardGui(adaptiveBillboardGui)
	end
end

local function UpdateAdaptiveFrameOfBillboardGui(adaptiveFrameOfBillboardGui: AdaptiveFrameOfBillboardGui)
	local frameSizeX: number = adaptiveFrameOfBillboardGui.frame.Size.X.Offset
	local frameSizeY: number = adaptiveFrameOfBillboardGui.frame.Size.Y.Offset
	if frameSizeX <= 0 or frameSizeY <= 0 then
		return
	end
	adaptiveFrameOfBillboardGui.frameUIScale.Scale =
		math.min(adaptiveFrameOfBillboardGui.billboardGui.AbsoluteSize.X / frameSizeX, adaptiveFrameOfBillboardGui.billboardGui.AbsoluteSize.Y / frameSizeY)
end

local function UpdateAdaptiveFramesOfBillboardGui()
	for adaptiveFrameOfBillboardGuiIndex: number, adaptiveFrameOfBillboardGui: AdaptiveFrameOfBillboardGui in adaptiveFramesOfBillboardGui do
		UpdateAdaptiveFrameOfBillboardGui(adaptiveFrameOfBillboardGui)
	end
end

local function OnBillboardGuiRenderStepped()
	UpdateAdaptiveFramesOfBillboardGui()
end

local function EnsureBillboardGuiRenderStepBound()
	if billboardGuiRenderStepBound then
		return
	end
	billboardGuiRenderStepBound = true
	runService:BindToRenderStep("UIAdapter.BillboardGuiRenderStepped", Enum.RenderPriority.Camera.Value + 1, OnBillboardGuiRenderStepped)
end

function UIAdapter.Init(designScreenSizeNew: Vector2, screenSizeNew: Vector2)
	designScreenSize = designScreenSizeNew
	screenSize = screenSizeNew
	initialized = true
	UpdateAdaptiveFrames()
	UpdateAdaptiveBillboardGuis()
end

function UIAdapter.AddAdaptiveFrame(frame: Frame, adaptiveType: number)
	local uiScale: UIScale = frame:FindFirstChild("UIScale") :: UIScale
	local adaptiveFramesCurrType: { AdaptiveFrame } = adaptiveFrames[adaptiveType]
	local adaptiveFrame: AdaptiveFrame = {
		frame = frame,
		scaleOrigin = uiScale.Scale,
		sizeXOrigin = frame.Size.X.Offset,
		sizeYOrigin = frame.Size.Y.Offset,
	}
	table.insert(adaptiveFramesCurrType, adaptiveFrame)
	if initialized then
		UpdateAdaptiveFrame(adaptiveType, adaptiveFrame)
	end
end

function UIAdapter.RemoveAdaptiveFrame(frame: Frame)
	for adaptiveType: number, adaptiveFramesCurrType: { AdaptiveFrame } in pairs(adaptiveFrames) do
		for adaptiveFrameIndex: number, adaptiveFrame: AdaptiveFrame in adaptiveFramesCurrType do
			if adaptiveFrame.frame == frame then
				table.remove(adaptiveFramesCurrType, adaptiveFrameIndex)
				break
			end
		end
	end
end

function UIAdapter.RefreshAdaptiveFrame(frame: Frame)
	for adaptiveType: number, adaptiveFramesCurrType: { AdaptiveFrame } in pairs(adaptiveFrames) do
		for adaptiveFrameIndex: number, adaptiveFrame: AdaptiveFrame in adaptiveFramesCurrType do
			if adaptiveFrame.frame == frame then
				UpdateAdaptiveFrame(adaptiveType, adaptiveFrame)
				return
			end
		end
	end
end

function UIAdapter.AddAdaptiveBillboardGui(billboardGui: BillboardGui)
	local adaptiveBillboardGui: AdaptiveBillboardGui = {
		billboardGui = billboardGui,
		sizeXOrigin = billboardGui.Size.X.Offset,
		sizeYOrigin = billboardGui.Size.Y.Offset,
	}
	table.insert(adaptiveBillboardGuis, adaptiveBillboardGui)
	if initialized then
		UpdateAdaptiveBillboardGui(adaptiveBillboardGui)
	end
end

function UIAdapter.RemoveAdaptiveBillboardGui(billboardGui: BillboardGui)
	for adaptiveBillboardGuiIndex: number, adaptiveBillboardGui: AdaptiveBillboardGui in adaptiveBillboardGuis do
		if adaptiveBillboardGui.billboardGui == billboardGui then
			table.remove(adaptiveBillboardGuis, adaptiveBillboardGuiIndex)
			break
		end
	end
end

function UIAdapter.AddAdaptiveFrameOfBillboardGui(frame: Frame, billboardGui: BillboardGui, frameUIScale: UIScale)
	local adaptiveFrameOfBillboardGui: AdaptiveFrameOfBillboardGui = {
		frame = frame,
		billboardGui = billboardGui,
		frameUIScale = frameUIScale,
	}
	table.insert(adaptiveFramesOfBillboardGui, adaptiveFrameOfBillboardGui)
	UpdateAdaptiveFrameOfBillboardGui(adaptiveFrameOfBillboardGui)
	EnsureBillboardGuiRenderStepBound()
end

function UIAdapter.RemoveAdaptiveFrameOfBillboardGui(frame: Frame)
	for adaptiveFrameOfBillboardGuiIndex: number, adaptiveFrameOfBillboardGui: AdaptiveFrameOfBillboardGui in adaptiveFramesOfBillboardGui do
		if adaptiveFrameOfBillboardGui.frame == frame then
			table.remove(adaptiveFramesOfBillboardGui, adaptiveFrameOfBillboardGuiIndex)
			break
		end
	end
end

function UIAdapter.OnScreenSizeChange(screenSizeNew: Vector2)
	screenSize = screenSizeNew
	UpdateAdaptiveFrames()
	UpdateAdaptiveBillboardGuis()
end

return UIAdapter
