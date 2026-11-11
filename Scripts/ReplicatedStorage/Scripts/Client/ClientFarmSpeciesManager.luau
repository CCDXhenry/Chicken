-- 农场界面路由管理器：管理独立窗口、个人地块入口、确认令牌与长按孵化
--!strict
local Storage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Input = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Shared = Storage.Scripts.Shared
local Rules = require(Shared.FarmUIConfig)
local HatchController = require(script.Parent.ClientHatchController)
local Lifecycle = require(Shared.LifecycleTool)
local Net = require(Shared.NetMsg)
local Info = require(script.Parent.ClientGameInfo)
local Msg = require(script.Parent.ClientMsg)
local Text = require(script.Parent.FarmTextTool)
local UIManager = require(script.Parent.UIManager)
local UIActions = require(script.Parent.UIManager.UIActions)
local WindowBase = require(script.Parent.UIManager.WindowBase)
local UIAdapter = require(Storage.Core.Scripts.Client.UIAdapter)
local Common = require(script.Parent.FarmWindows.Common)
local ToolShop = require(script.Parent.FarmWindows.ToolShop)
local WeaponShop = require(script.Parent.FarmWindows.WeaponShop)
local WeaponEnhance = require(script.Parent.FarmWindows.WeaponEnhance)
local CollectorShop = require(script.Parent.FarmWindows.CollectorShop)
local BasketShop = require(script.Parent.FarmWindows.BasketShop)
local Species = require(script.Parent.FarmWindows.Species)
local Restaurant = require(script.Parent.FarmWindows.Restaurant)
local Equipment = require(script.Parent.FarmWindows.Equipment)
local Hatch = require(script.Parent.FarmWindows.Hatch)
local Confirmation = require(script.Parent.FarmWindows.Confirmation)
local Controllers: { [string]: { Bind: (Common.Context) -> () } } = { ToolShop = ToolShop, WeaponShop = WeaponShop, WeaponEnhance = WeaponEnhance, CollectorShop = CollectorShop, BasketShop = BasketShop, Species = Species, Restaurant = Restaurant, Equipment = Equipment }
local Manager = {}
Manager.__index = Manager
export type ClientFarmSpeciesManager = typeof(setmetatable({} :: {
	scope: Lifecycle.Lifecycle?, mapScope: Lifecycle.Lifecycle?, frame: Frame?, map: Instance?, entries: { BasePart }, nearest: BasePart?,
	entry: BasePart?, active: string?, eggId: string?, holding: boolean,
	confirmationId: string?, hatchTarget: string?,
}, Manager))
local function InRange(part: BasePart): boolean
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local range = part:GetAttribute("FarmUIRange")
	return part:IsDescendantOf(workspace) and part:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId and root ~= nil and root:IsA("BasePart") and (root.Position - part.Position).Magnitude <= (if typeof(range) == "number" then range else 10)
end
function Manager.new(): ClientFarmSpeciesManager
	return setmetatable({ entries = {}, holding = false }, Manager)
end
function Manager.StopHatchHold(self: ClientFarmSpeciesManager): () self.holding = false; HatchController.Stop() end
function Manager.IsHatchHolding(self: ClientFarmSpeciesManager): boolean return HatchController.IsHolding() end
function Manager.StartHatchHold(self: ClientFarmSpeciesManager, fromWindow: boolean?): boolean
	local accepted = HatchController.Start(if fromWindow then "Window" else "Keyboard", Info.GetFarmInfo().eggId)
	self.holding = HatchController.IsHolding()
	return accepted
end
function Manager.Allowed(self: ClientFarmSpeciesManager): boolean
	if not Info.GetFarmInfo().ready then return false end
	if self.active == "Equipment" then return true end
	if self.active == "Hatch" then return self.hatchTarget ~= nil and self.hatchTarget == Info.GetFarmInfo().eggId end
	return self.entry ~= nil and InRange(self.entry)
end
function Manager.CloseMain(self: ClientFarmSpeciesManager): ()
	local active = self.active
	if active then UIManager.CloseWindow("Farm" .. active) end
	self.active, self.entry, self.hatchTarget = nil, nil, nil
	self:StopHatchHold()
end
function Manager.Open(self: ClientFarmSpeciesManager, id: string, entry: BasePart?): ()
	if UIManager.IsWindowShowing("FarmConfirmation") or not Info.GetFarmInfo().ready then return end
	local source = entry or self.entry
	if id ~= "Equipment" and id ~= "Hatch" then
		if not source or not InRange(source) then return end
		local entryId = source:GetAttribute("FarmUIEntry")
		local expected = if Rules.ToolWindows[id] then "ToolShop" else id
		if entryId ~= expected then return end
	elseif id == "Hatch" and not Info.GetFarmInfo().eggId then return end
	self:CloseMain()
	self.entry, self.active = source, id
	self.hatchTarget = if id == "Hatch" then Info.GetFarmInfo().eggId else nil
	UIManager.OpenWindow("Farm" .. id)
end
function Manager.Refresh(self: ClientFarmSpeciesManager): ()
	local info = Info.GetFarmInfo()
	if self.eggId ~= info.eggId or not info.ready then self:StopHatchHold() end
	self.eggId = info.eggId
	if self.active and not self:Allowed() then UIManager.CloseWindow("FarmConfirmation"); self:CloseMain() end
	if self.confirmationId ~= info.confirmationId then
		self.confirmationId = info.confirmationId
		UIManager.CloseWindow("FarmConfirmation")
		if info.confirmationId and info.ready then UIManager.OpenWindow("FarmConfirmation") end
	end
end
function Manager.Scan(self: ClientFarmSpeciesManager): ()
	local farm: Instance? = nil
	local farms = workspace:FindFirstChild("PersonalFarms")
	if farms then for _, candidate in farms:GetChildren() do if candidate:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId then farm = candidate; break end end end
	if farm ~= self.map then
		if self.mapScope then self.mapScope:Destroy(); self.mapScope = nil end
		self.map = farm; table.clear(self.entries)
		if farm then
			local mapScope = Lifecycle.new()
			self.mapScope = mapScope
			local function OnAdded(object: Instance): ()
				if object:IsA("BasePart") and typeof(object:GetAttribute("FarmUIEntry")) == "string" then table.insert(self.entries, object) end
			end
			local function OnRemoving(object: Instance): ()
				if not object:IsA("BasePart") then return end
				local index = table.find(self.entries, object)
				if index then table.remove(self.entries, index) end
			end
			mapScope:Connect(farm.DescendantAdded:Connect(OnAdded))
			mapScope:Connect(farm.DescendantRemoving:Connect(OnRemoving))
			for _, object in farm:GetDescendants() do OnAdded(object) end
		end
	end
	local nearest: BasePart? = nil
	local distance = math.huge
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if Info.GetFarmInfo().ready and root and root:IsA("BasePart") then
		for _, part in self.entries do if InRange(part) then local d = (root.Position - part.Position).Magnitude; if d < distance then nearest, distance = part, d end end end
	end
	self.nearest = nearest
	if self.active and not self:Allowed() then UIManager.CloseWindow("FarmConfirmation"); self:CloseMain() end
	local frame = self.frame
	if frame then
		local b = Common.Button(frame, "InteractButton")
		local free = not UIManager.HasShowingWindow() and Info.GetFarmInfo().ready == true and not GuiService.MenuIsOpen
		b.Visible = free and nearest ~= nil
		if nearest then
			local id = nearest:GetAttribute("FarmUIEntry")
			local title = if typeof(id) == "string" then Rules.EntryLabels[id] else nil
			Text.Set(b, (if Input.PreferredInput == Enum.PreferredInput.Touch then "" else "[R]  ") .. (title or "Open"))
		end
	end
end
function Manager.Init(self: ClientFarmSpeciesManager, screen: ScreenGui): ()
	if self.scope then return end
	local scope = Lifecycle.new(); self.scope = scope
	HatchController.Init(function(): () self:Open("Hatch") end)
	for _, id in Rules.Windows do
		local function Create(frame: Frame, windowId: string, actions: UIActions.UIActions): WindowBase.WindowBase
			local function Open(nextId: string): () self:Open(nextId) end
			local function Allowed(): boolean return self:Allowed() end
			local ctx = Common.New(frame, windowId, actions, Open, Allowed)
			if id == "Hatch" then Hatch.Bind(ctx) else Controllers[id].Bind(ctx) end
			return ctx.window
		end
		UIManager.RegisterWindow("Farm" .. id, { frameName = "Farm" .. id .. "Frame", isModal = true, openAnimation = WindowBase.OpenAnimation.Scale, newWindow = Create })
	end
	local function CreateConfirmation(frame: Frame, id: string, actions: UIActions.UIActions): WindowBase.WindowBase
		local ctx = Common.New(frame, id, actions, function(): () end, function(): boolean return false end)
		Confirmation.Bind(ctx); UIManager.FitMarkedRoot(frame); return ctx.window
	end
	UIManager.RegisterWindow("FarmConfirmation", { frameName = "FarmConfirmationFrame", isModal = true, openAnimation = WindowBase.OpenAnimation.Scale, newWindow = CreateConfirmation })
	local frame = UIManager.CreateFrame("FarmInteractionFrame", screen, 2); self.frame = frame; scope:Own(frame)
	UIAdapter.AddAdaptiveFrame(frame, UIAdapter.AdaptiveType.Center)
	local function OnInteract(): () if self.nearest then local id = self.nearest:GetAttribute("FarmUIEntry"); if typeof(id) == "string" then self:Open(id, self.nearest) end end end
	local function OnInput(input: InputObject, processed: boolean): ()
		if Input:GetFocusedTextBox() then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			if UIManager.IsWindowShowing("FarmConfirmation") then UIManager.CloseWindow("FarmConfirmation") else self:CloseMain() end
		elseif not processed and input.KeyCode == Enum.KeyCode.R then OnInteract() end
	end
	local function OnStop(): () self:StopHatchHold() end
	local function OnReset(): () UIManager.CloseWindow("FarmConfirmation"); self:CloseMain() end
	scope:Connect(Common.Button(frame, "InteractButton").Activated:Connect(OnInteract))
	scope:Connect(Input.InputBegan:Connect(OnInput))
	scope:Connect(Players.LocalPlayer.CharacterAdded:Connect(OnReset))
	scope:Connect(Players.LocalPlayer.CharacterRemoving:Connect(OnReset))
	scope:Connect(Msg.ConnectCloseWindow(function(id: string): () if self.active and id == "Farm" .. self.active then self.active, self.entry, self.hatchTarget = nil, nil, nil; OnStop() end end))
	scope:Connect(Msg.ConnectFarmInfoChanged(function(): () self:Refresh() end))
	scope:Spawn(function(): () while scope.alive do self:Scan(); task.wait(Rules.ScanSeconds) end end)
	self:Refresh(); UIManager.FitMarkedRoot(frame)
end
function Manager.Destroy(self: ClientFarmSpeciesManager): ()
	if self.mapScope then self.mapScope:Destroy(); self.mapScope = nil end
	self:StopHatchHold(); UIManager.CloseWindow("FarmConfirmation"); self:CloseMain(); HatchController.Destroy()
	if self.frame then Text.Remove(self.frame); UIAdapter.RemoveAdaptiveFrame(self.frame) end
	if self.scope then self.scope:Destroy(); self.scope = nil end
	self.frame, self.map, self.confirmationId = nil, nil, nil; table.clear(self.entries)
end
return Manager
