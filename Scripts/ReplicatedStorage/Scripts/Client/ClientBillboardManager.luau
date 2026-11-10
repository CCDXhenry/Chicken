-- 客户端标牌：按零件属性在本地 PlayerGui 克隆世界标牌，并在零件移除时销毁
--!strict
local Players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local LifecycleTool = require(script.Parent.Parent:WaitForChild("Shared"):WaitForChild("LifecycleTool"))
local FarmTextTool = require(script.Parent:WaitForChild("FarmTextTool"))

local uiTemplates = replicatedStorage:WaitForChild("UI")

type SignRecord = {
	name: string,
	gui: BillboardGui,
	label: TextLabel?,
}

local ClientBillboardManager = {}
ClientBillboardManager.__index = ClientBillboardManager
export type ClientBillboardManager = typeof(setmetatable(
	{} :: {
		scope: LifecycleTool.Lifecycle?,
		playerGui: PlayerGui?,
		partScopes: { [BasePart]: LifecycleTool.Lifecycle },
		signs: { [BasePart]: SignRecord },
	},
	ClientBillboardManager
))

function ClientBillboardManager.new(): ClientBillboardManager
	return setmetatable({
		partScopes = {},
		signs = {},
	}, ClientBillboardManager)
end

function ClientBillboardManager.Release(self: ClientBillboardManager, part: BasePart): ()
	local record = self.signs[part]
	if not record then
		return
	end
	FarmTextTool.Remove(record.gui)
	record.gui:Destroy()
	self.signs[part] = nil
end

function ClientBillboardManager.Apply(self: ClientBillboardManager, part: BasePart): ()
	local record = self.signs[part]
	if not record then
		return
	end
	local offsetY = part:GetAttribute("FarmStudsOffsetY")
	if typeof(offsetY) == "number" then
		record.gui.StudsOffset = Vector3.new(0, offsetY, 0)
	end
	local label = record.label
	if not label then
		return
	end
	local tone = part:GetAttribute("FarmHealthTone")
	if tone == "healthy" or tone == "damaged" then
		local colorName = if tone == "damaged" then "DamagedColor" else "HealthyColor"
		local color = label:GetAttribute(colorName)
		if typeof(color) == "Color3" then
			label.BackgroundColor3 = color
		end
	end
	local message = part:GetAttribute("FarmText")
	if typeof(message) == "string" then
		FarmTextTool.Set(label, message)
	end
end

function ClientBillboardManager.Mount(self: ClientBillboardManager, part: BasePart, signName: string): ()
	local playerGui = self.playerGui
	if not playerGui then
		return
	end
	local existing = self.signs[part]
	if existing ~= nil and existing.name == signName then
		self:Apply(part)
		return
	end
	if existing ~= nil then
		self:Release(part)
	end
	local template = uiTemplates:FindFirstChild(signName)
	assert(template ~= nil and template:IsA("BillboardGui"), "Missing farm sign template: " .. signName)
	local gui = template:Clone()
	gui.Adornee = part
	gui.Parent = playerGui
	local label = gui:FindFirstChild("ContentText", true)
	self.signs[part] = {
		name = signName,
		gui = gui,
		label = if label ~= nil and label:IsA("TextLabel") then label else nil,
	}
	self:Apply(part)
end

function ClientBillboardManager.Refresh(self: ClientBillboardManager, part: BasePart): ()
	local signName = part:GetAttribute("FarmSign")
	if typeof(signName) ~= "string" or signName == "" then
		self:Release(part)
		return
	end
	self:Mount(part, signName)
end

function ClientBillboardManager.TrackPart(self: ClientBillboardManager, part: BasePart): ()
	if self.partScopes[part] then
		return
	end
	local partScope = LifecycleTool.new()
	self.partScopes[part] = partScope
	local function OnSignChanged(): ()
		self:Refresh(part)
	end
	local function OnDetailChanged(): ()
		self:Apply(part)
	end
	partScope:Connect(part:GetAttributeChangedSignal("FarmSign"):Connect(OnSignChanged))
	partScope:Connect(part:GetAttributeChangedSignal("FarmText"):Connect(OnDetailChanged))
	partScope:Connect(part:GetAttributeChangedSignal("FarmHealthTone"):Connect(OnDetailChanged))
	partScope:Connect(part:GetAttributeChangedSignal("FarmStudsOffsetY"):Connect(OnDetailChanged))
	self:Refresh(part)
end

function ClientBillboardManager.ForgetPart(self: ClientBillboardManager, part: BasePart): ()
	self:Release(part)
	local partScope = self.partScopes[part]
	if partScope then
		partScope:Destroy()
		self.partScopes[part] = nil
	end
end

function ClientBillboardManager.Init(self: ClientBillboardManager): ()
	if self.scope then
		return
	end
	local scope = LifecycleTool.new()
	self.scope = scope
	self.playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local function OnAdded(instance: Instance): ()
		if instance:IsA("BasePart") then
			self:TrackPart(instance)
		end
	end
	local function OnRemoving(instance: Instance): ()
		if instance:IsA("BasePart") then
			self:ForgetPart(instance)
		end
	end
	scope:Connect(workspace.DescendantAdded:Connect(OnAdded))
	scope:Connect(workspace.DescendantRemoving:Connect(OnRemoving))
	for _, instance in workspace:GetDescendants() do
		OnAdded(instance)
	end
end

function ClientBillboardManager.Destroy(self: ClientBillboardManager): ()
	if self.scope then
		self.scope:Destroy()
		self.scope = nil
	end
	local signedParts: { BasePart } = {}
	for part in self.signs do
		table.insert(signedParts, part)
	end
	for _, part in signedParts do
		self:Release(part)
	end
	for _, partScope in self.partScopes do
		partScope:Destroy()
	end
	table.clear(self.signs)
	table.clear(self.partScopes)
	self.playerGui = nil
end

return ClientBillboardManager
