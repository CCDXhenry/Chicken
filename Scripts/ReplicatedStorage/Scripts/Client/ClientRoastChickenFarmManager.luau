-- 客户端农场管理器：负责输入请求、武器 Tool 联动、反馈分发与界面生命周期
--!strict
local contextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local sharedScripts = replicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local Paths = require(sharedScripts:WaitForChild("FarmScenePaths"))
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local FarmConfig = require(sharedScripts:WaitForChild("FarmConfig"))
local Economy = require(sharedScripts:WaitForChild("FarmEconomyConfig"))
local CombatRules = require(sharedScripts:WaitForChild("FarmCombatRules"))
local LifecycleTool = require(sharedScripts:WaitForChild("LifecycleTool"))
local ClientGameInfo = require(script.Parent:WaitForChild("ClientGameInfo"))
local RoastChickenHUDFrame = require(script.Parent:WaitForChild("RoastChickenHUDFrame"))
local SpeciesManager = require(script.Parent:WaitForChild("ClientFarmSpeciesManager"))
local UIManager = require(script.Parent:WaitForChild("UIManager"))
local FarmSoundTool = require(sharedScripts:WaitForChild("FarmSoundTool"))
local VisualEffects = require(script.Parent:WaitForChild("FarmVisualEffects"))

local ZapPrediction = require(script.Parent:WaitForChild("FarmZapPrediction"))
local Toolbar = require(script.Parent:WaitForChild("ClientFarmToolbar"))

local localPlayer = players.LocalPlayer
local MinimumHorizontalAim = 1e-4
local ZapResultTimeoutSeconds = 2
local ClientRoastChickenFarmManager = {}
ClientRoastChickenFarmManager.__index = ClientRoastChickenFarmManager
export type ClientRoastChickenFarmManager = typeof(setmetatable(
	{} :: {
		hud: RoastChickenHUDFrame.RoastChickenHUDFrame?,
		toolbar: Toolbar.Controller?,
		speciesUI: SpeciesManager.ClientFarmSpeciesManager?,
		vfx: VisualEffects.VfxManager?,
		scope: LifecycleTool.Lifecycle?,
		initialized: boolean,
		zapPrediction: ZapPrediction.Tracker,
	},
	ClientRoastChickenFarmManager
))

function ClientRoastChickenFarmManager.new(): ClientRoastChickenFarmManager
	return setmetatable({ initialized = false, zapPrediction = ZapPrediction.new() }, ClientRoastChickenFarmManager)
end

function ClientRoastChickenFarmManager.Init(self: ClientRoastChickenFarmManager, screenGui: ScreenGui): ()
	if self.initialized then
		return
	end
	self.initialized = true
	local scope = LifecycleTool.new()
	self.scope = scope
	ClientGameInfo.InitFarmInfo()
	local function OnAction(action: FarmConfig.FarmAction): ()
		self:TriggerAction(action)
	end
	local hud = RoastChickenHUDFrame.new()
	self.hud = hud
	hud:Init(screenGui)
	local speciesUI = SpeciesManager.new()
	self.speciesUI = speciesUI
	speciesUI:Init(screenGui)

	local vfx = VisualEffects.new()
	self.vfx = vfx
	vfx:Init()

	-- 监听服务端广播的高品质视觉事件 (电击弹道/熟食飞入鸡筐/交货丰收抛跃)
	local function OnVisual(event: NetMsg.VisualEvent): ()
		if event.kind == "zapResult" then
			if not event.shotId then return end
			local corrections = self.zapPrediction:Resolve(event.shotId, event.accepted == true, event.targets or {})
			for _, target in corrections do
				vfx:CreateHitImpact(Vector3.new(target.x, target.y, target.z), target.damage, target.isCooked, event.tier or 1)
			end
		elseif event.kind == "zap" then
			local from = if event.fromPos then Vector3.new(event.fromPos.x, event.fromPos.y, event.fromPos.z) else Vector3.zero
			local targets = event.targets or {}
			vfx:PlayZapEffects(event.tier or 1, from, targets)
		elseif event.kind == "pickup" then
			local from = if event.fromPos then Vector3.new(event.fromPos.x, event.fromPos.y, event.fromPos.z) else Vector3.zero
			vfx:PlayOriginalRoastIntoBasket(from, event.speciesId or "chicken", event.qualityId or "normal", event.weightKg or 1)
		elseif event.kind == "deliver" then
			local from = if event.fromPos then Vector3.new(event.fromPos.x, event.fromPos.y, event.fromPos.z) else Vector3.zero
			local to = if event.toPos then Vector3.new(event.toPos.x, event.toPos.y, event.toPos.z) else from
			vfx:PlayDeliveryFlying(from, to, event.speciesId or "chicken", event.qualityId or "normal")
		end
	end
	scope:Connect(NetMsg.ConnectNotifyFarmVisual(OnVisual))
	local function OnCharacterRemoving(): ()
		self.zapPrediction:Clear()
	end
	scope:Connect(localPlayer.CharacterRemoving:Connect(OnCharacterRemoving))

	local function OnShop(): ()
		FarmSoundTool.Play("UIClick")
		speciesUI:Open("ToolShop")
	end
	scope:Connect(hud.shopButton.Activated:Connect(OnShop))

	local function OnIndex(): ()
		FarmSoundTool.Play("UIClick")
		speciesUI:Open("Species")
	end
	scope:Connect(hud.indexButton.Activated:Connect(OnIndex))

	local function OnEgg(): ()
		FarmSoundTool.Play("UIClick")
		speciesUI:Open("Hatch")
	end
	scope:Connect(hud.eggButton.Activated:Connect(OnEgg))

	local function OnEquipment(): ()
		FarmSoundTool.Play("UIClick")
		speciesUI:Open("Equipment")
	end
	scope:Connect(hud.equipmentButton.Activated:Connect(OnEquipment))
	local function OnFeedback(message: string, kind: string?): ()
		if kind == "sale" then
			FarmSoundTool.Play("Coin")
			hud:ShowSaleNotice(message)
		elseif kind == "capacity" then
			FarmSoundTool.Play("Warning")
			hud:ShowCapacityDenied(message)
		else
			-- 成功拾取音效由飞行落袋播放；电击命中音由本地电弧播放，避免反馈文案再播一次
			if string.find(message, "不足") then
				FarmSoundTool.Play("Warning")
			end
			hud:ShowMessage(message)
		end
	end
	scope:Connect(NetMsg.ConnectNotifyFarmFeedback(OnFeedback))

	local toolbar = Toolbar.new(OnAction)
	self.toolbar = toolbar
	toolbar:Init(hud.container, screenGui)
	local function OnHatch(_: string, state: Enum.UserInputState): Enum.ContextActionResult
		if UserInputService:GetFocusedTextBox() or GuiService.MenuIsOpen then speciesUI:StopHatchHold(); return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin then return if speciesUI:StartHatchHold() then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass end
		local wasHolding = speciesUI:IsHatchHolding()
		speciesUI:StopHatchHold()
		return if wasHolding then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
	end
	contextActionService:BindAction("Farm_hatch", OnHatch, false, Enum.KeyCode.F)

end

local function CollectLiveAnimalCandidates(): { CombatRules.Candidate }
	local candidates: { CombatRules.Candidate } = {}
	local plotId = localPlayer:GetAttribute("FarmPlotId")
	if typeof(plotId) ~= "string" then
		return candidates
	end
	local personalFarms = workspace:FindFirstChild("PersonalFarms")
	local farmPlot = if personalFarms then personalFarms:FindFirstChild(plotId) else nil
	local liveFolder = if farmPlot then Paths.Find(farmPlot, "LiveAnimals") else nil
	if not liveFolder then
		return candidates
	end
	for _, child in liveFolder:GetChildren() do
		if child:IsA("Model") then
			local id = child:GetAttribute("EntityId")
			local health = child:GetAttribute("Health")
			local primary = child.PrimaryPart
			if typeof(id) == "string" and typeof(health) == "number" and health > 0 and primary then
				local position = primary.Position
				table.insert(candidates, { id = id, x = position.X, y = position.Y, z = position.Z, health = health })
			end
		end
	end
	return candidates
end

function ClientRoastChickenFarmManager.TriggerAction(self: ClientRoastChickenFarmManager, action: FarmConfig.FarmAction): boolean
	if (action == "zap" or action == "collect") and (not self.toolbar or not self.toolbar:CanUse(action)) then return false end
	if self.initialized and ClientGameInfo.GetFarmInfo().ready == true and not UIManager.HasShowingWindow() and not UserInputService:GetFocusedTextBox() and not GuiService.MenuIsOpen then
		if action == "zap" then
			local camera = Workspace.CurrentCamera
			local look = if camera then camera.CFrame.LookVector else nil
			local flat = if look then Vector3.new(look.X, 0, look.Z) else nil
			if not flat or flat.Magnitude < MinimumHorizontalAim then
				return false
			end
			local aim = flat.Unit
			local info = ClientGameInfo.GetFarmInfo()
			local tier = math.clamp(info.zap or 1, 1, #Economy.Weapons)
			local level = math.clamp(info.weaponLevel or 1, 1, Economy.MaximumWeaponLevel)
			local character = localPlayer.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if not root or not root:IsA("BasePart") then
				return false
			end
			local candidates = CollectLiveAnimalCandidates()
			local hits = CombatRules.ResolveShot(tier, level, root.Position.X, root.Position.Y, root.Position.Z, aim.X, aim.Z, candidates)
			local byId: { [string]: CombatRules.Candidate } = {}
			for _, candidate in candidates do
				byId[candidate.id] = candidate
			end
			local targetIds: { string } = {}
			local visualTargets: { ZapPrediction.Target } = {}
			for _, hit in hits do
				local candidate = byId[hit.id]
				if candidate then
					table.insert(targetIds, hit.id)
					table.insert(visualTargets, {
						x = candidate.x,
						y = candidate.y,
						z = candidate.z,
						damage = hit.damage,
						isCooked = candidate.health <= hit.damage,
						id = hit.id,
					})
				end
			end
			local cancellations: ZapPrediction.Cancellations = {}
			FarmSoundTool.Play("Zap_T" .. tostring(tier))
			if self.vfx then
				if #visualTargets == 0 then
					self.vfx:PlayZapMiss(tier, aim)
				else
					cancellations = self.vfx:PlayZapEffects(tier, root.Position, visualTargets)
				end
			end
			local shotId = self.zapPrediction:Begin(visualTargets, cancellations)
			local scope = self.scope
			if scope then
				scope:Delay(ZapResultTimeoutSeconds, function(): () self.zapPrediction:Expire(shotId) end)
			end
			NetMsg.FireRequestFarmCommand({ action = "zap", shotId = shotId, aim = { x = aim.X, y = 0, z = aim.Z }, targetIds = targetIds })
		else
			-- 拾取音效在原熟食弹入背篓结束时播放，避免前置 UIClick 割裂
			if action == "collect" and self.vfx then
				self.vfx:ReserveNearbyRoasts()
			end
			NetMsg.FireRequestFarmAction(action)
		end
		return true
	end
	return false
end

function ClientRoastChickenFarmManager.Destroy(self: ClientRoastChickenFarmManager): ()
	if not self.initialized then
		return
	end
	self.initialized = false
	self.zapPrediction:Clear()
	if self.toolbar then self.toolbar:Destroy(); self.toolbar = nil end
	contextActionService:UnbindAction("Farm_hatch")
	if self.vfx then
		self.vfx:Destroy()
		self.vfx = nil
	end
	if self.scope then
		self.scope:Destroy()
		self.scope = nil
	end
	if self.hud then
		self.hud:Destroy()
		self.hud = nil
	end
	if self.speciesUI then self.speciesUI:Destroy(); self.speciesUI = nil end
	ClientGameInfo.DestroyFarmInfo()
end

return ClientRoastChickenFarmManager
