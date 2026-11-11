-- 客户端标牌：按零件属性在本地 PlayerGui 克隆世界标牌，并在零件移除时销毁
--!strict
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local LifecycleTool = require(script.Parent.Parent:WaitForChild("Shared"):WaitForChild("LifecycleTool"))
local FarmTextTool = require(script.Parent:WaitForChild("FarmTextTool"))
local EggBinder = require(script.Parent:WaitForChild("EggBillboardBinder"))
local CookedFoodBinder = require(script.Parent:WaitForChild("CookedFoodBillboardBinder"))
local Config = require(script.Parent.Parent.Shared.FarmEconomyConfig)

local uiTemplates = replicatedStorage:WaitForChild("UI")

type AnyBinding = { Destroy: () -> () }
type SignRecord = {
	name: string,
	gui: BillboardGui,
	label: TextLabel?,
	binding: AnyBinding?,
	scope: LifecycleTool.Lifecycle,
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
	if record.binding then record.binding.Destroy() end
	record.scope:Destroy()
	FarmTextTool.Remove(record.gui)
	record.gui:Destroy()
	self.signs[part] = nil
end

function ClientBillboardManager.Apply(self: ClientBillboardManager, part: BasePart): ()
	local record = self.signs[part]
	if not record then
		return
	end
	if record.binding then
		return
	end
	local templateOffset = record.gui:GetAttribute("BaseStudsOffset")
	local baseOffset = if typeof(templateOffset) == "Vector3" then templateOffset else Vector3.zero
	local offsetY = part:GetAttribute("FarmStudsOffsetY")
	if typeof(offsetY) == "number" then
		baseOffset = Vector3.new(baseOffset.X, offsetY, baseOffset.Z)
	end
	local compensation = record.gui:GetAttribute("HeightCompensationStuds")
	record.gui.StudsOffset = baseOffset + Vector3.new(0, if typeof(compensation) == "number" then compensation else 0, 0)
	local label = record.label
	if not label then
		return
	end
	local model = part:FindFirstAncestorOfClass("Model")
	if record.name == "AnimalHealthGui" and model then
		local health, maximum = model:GetAttribute("Health"), model:GetAttribute("MaxHealth")
		if typeof(health) == "number" and typeof(maximum) == "number" then
			local speciesId = model:GetAttribute("SpeciesId")
			local species = if typeof(speciesId) == "string" then Config.GetSpecies(speciesId) else nil
			FarmTextTool.Set(label, if species then species.name else model.Name)
			local qualityId = model:GetAttribute("QualityId")
			local qualityLabel = record.gui:FindFirstChild("QualityText", true) :: TextLabel
			FarmTextTool.Set(qualityLabel, if qualityId == "golden" then "Golden" elseif qualityId == "rainbow" then "Rainbow" elseif qualityId == "giant" then "Giant" else "Normal")
			local qualityColor = record.gui:GetAttribute("Quality_" .. tostring(qualityId))
			if typeof(qualityColor) == "Color3" then qualityLabel.TextColor3 = qualityColor end
			local healthText = record.gui:FindFirstChild("HealthText", true) :: TextLabel
			healthText.Text = tostring(health) .. " / " .. tostring(maximum)
			local fill = record.gui:FindFirstChild("FillFrame", true) :: Frame
			fill.Size = UDim2.fromScale(math.clamp(health / math.max(1, maximum), 0, 1), 1)
			local track = fill.Parent :: Frame
			track.Visible = health < maximum
			local color = record.gui:GetAttribute(if health < maximum then "DamagedColor" else "HealthyColor")
			if typeof(color) == "Color3" then fill.BackgroundColor3 = color end
			return
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
	local template = uiTemplates:FindFirstChild(signName) or uiTemplates:WaitForChild(signName, 2)
	assert(template ~= nil and template:IsA("BillboardGui"), "Missing farm sign template: " .. signName)
	local gui = template:Clone()
	gui.Adornee = part
	gui.Parent = playerGui
	local label = gui:FindFirstChild("ContentText", true)
	local signScope = LifecycleTool.new()
	self.signs[part] = {
		name = signName,
		gui = gui,
		label = if label ~= nil and label:IsA("TextLabel") then label else nil,
		scope = signScope,
		binding = if signName == "EggSignGui"
			then EggBinder.Bind(part, gui)
			elseif signName == "CookedFoodSignGui"
			then CookedFoodBinder.Bind(part, gui)
			else nil,
	}
	local model = part:FindFirstAncestorOfClass("Model")
	if signName == "AnimalHealthGui" and model then
		local function OnHealth(): () self:Apply(part) end
		signScope:Connect(model:GetAttributeChangedSignal("Health"):Connect(OnHealth))
		signScope:Connect(model:GetAttributeChangedSignal("MaxHealth"):Connect(OnHealth))
	end
	self:Apply(part)
end

function ClientBillboardManager.Refresh(self: ClientBillboardManager, part: BasePart): ()
	local ownerId = part:GetAttribute("OwnerUserId")
	local audience = part:GetAttribute("FarmSignAudience")
	if audience == "Private" and typeof(ownerId) == "number" and ownerId ~= Players.LocalPlayer.UserId then
		self:Release(part)
		return
	end
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
	partScope:Connect(part:GetAttributeChangedSignal("OwnerUserId"):Connect(OnSignChanged))
	partScope:Connect(part:GetAttributeChangedSignal("FarmSignAudience"):Connect(OnSignChanged))
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
		if instance:IsA("BasePart") and (typeof(instance:GetAttribute("FarmSign")) == "string" or CollectionService:HasTag(instance, "FarmSignPart")) then
			self:TrackPart(instance)
		end
	end
	local function OnTagged(instance: Instance): ()
		if instance:IsDescendantOf(workspace) then OnAdded(instance) end
	end
	local function OnRemoving(instance: Instance): ()
		if instance:IsA("BasePart") then
			self:ForgetPart(instance)
		end
	end
	scope:Connect(CollectionService:GetInstanceAddedSignal("FarmSignPart"):Connect(OnTagged))
	scope:Connect(CollectionService:GetInstanceRemovedSignal("FarmSignPart"):Connect(OnRemoving))
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
