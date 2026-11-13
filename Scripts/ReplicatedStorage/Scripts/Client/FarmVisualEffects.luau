-- 客户端特效管理器：统一管理电弧实时跟随、无闪光命中及对象池播放生命周期
--!strict
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local Paths = require(Shared:WaitForChild("FarmScenePaths"))
local FarmConfig = require(Shared:WaitForChild("FarmConfig"))
local Economy = require(Shared:WaitForChild("FarmEconomyConfig"))
local Texts = require(Shared:WaitForChild("GameTexts"))
local LifecycleTool = require(Shared:WaitForChild("LifecycleTool"))
local FarmSoundTool = require(Shared:WaitForChild("FarmSoundTool"))

local localPlayer = Players.LocalPlayer

local AttackDuration = 0.12
local SparkDuration = 0.12
local PickupHoldSeconds = 0.45
local PickupFadeSeconds = 0.15
local PickupSoundMergeSeconds = 0.08
local PickupLabelScale = 1.05
local PickupLowerRise = 1.35
local PickupUpperRise = 2.85
local PickupStrokeColor = Color3.fromRGB(20, 30, 10)

-- 仅使用已装备武器预置枪口，不回退到身体或历史坐标，避免出现悬空电弧。
local function GetLiveZapOrigin(): Vector3?
	local character = localPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not character or not character.Parent or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local weapon = character:FindFirstChild("FarmWeapon")
	local muzzle = if weapon and weapon:IsA("Tool") then weapon:FindFirstChild("Muzzle", true) else nil
	if muzzle and muzzle:IsA("Attachment") and muzzle.Parent and muzzle.Parent:IsA("BasePart") then
		return muzzle.WorldPosition
	end
	return nil
end

local FarmVisualEffects = {}
FarmVisualEffects.__index = FarmVisualEffects

type DamageLabelSlot = {
	gui: BillboardGui,
	label: TextLabel,
	stroke: UIStroke,
	scale: UIScale,
	baseSize: UDim2,
	defaultColor: Color3,
	defaultStrokeColor: Color3,
	active: boolean,
	generation: number,
	playback: LifecycleTool.Lifecycle,
	cleanup: (() -> ())?,
}

type VfxSlot = {
	model: Model,
	active: boolean,
	kind: string,
	tier: number?,
	generation: number,
	playback: LifecycleTool.Lifecycle,
	startedAt: number,
	expiresAt: number,
}

type ArcPlayback = {
	slots: { VfxSlot },
	generations: { number },
	offsets: { Vector3 },
	from: Vector3,
	to: Vector3,
	followPlayer: boolean,
	color: Color3,
	tier: number,
	elapsed: number,
}

type ReservedRoast = {
	source: Model,
	model: Model,
	position: Vector3,
	expiresAt: number,
}

type PickupNotice = {
	key: string,
	speciesId: string,
	qualityId: string,
	count: number,
	weightKg: number,
}

type PickupRow = {
	notice: PickupNotice,
	slot: DamageLabelSlot,
	generation: number,
	serial: number,
	rowIndex: number,
}

export type VfxManager = typeof(setmetatable(
	{} :: {
		scope: LifecycleTool.Lifecycle,
		poolFolder: Folder,
		templateFolder: Folder?,
		camera: Camera?,
		characterScope: LifecycleTool.Lifecycle,
		damagePool: { DamageLabelSlot },
		pickupPool: { DamageLabelSlot },
		muzzlePool: { VfxSlot },
		arcPool: { VfxSlot },
		activeArcs: { ArcPlayback },
		hitPool: { VfxSlot },
		roastPool: { VfxSlot },
		roastReserves: { ReservedRoast },
		anchorPool: { VfxSlot },
		pickupQueue: { PickupNotice },
		pickupRows: { [number]: PickupRow? },
		pickupAdornee: BasePart?,
		pickupAnchor: VfxSlot?,
		pickupAnchorGeneration: number,
		pickupFallback: BasePart?,
		pickupFallbackPos: Vector3,
		nextPickupSoundAt: number,
		shakeIntensity: number,
		shakeRemaining: number,
		originalFov: number,
		fovShockRemaining: number,
		fovDelta: number,
		rng: Random,
		initialized: boolean,
	},
	FarmVisualEffects
))

local function GetTemplateFolder(): Folder?
	local folder = ReplicatedStorage:FindFirstChild(FarmConfig.VfxTemplateFolder)
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

local function EmitNamed(root: Instance, name: string, count: number): ()
	local emitter = root:FindFirstChild(name, true)
	if emitter and emitter:IsA("ParticleEmitter") then
		emitter:Emit(count)
	end
end

local function HideModel(model: Model): ()
	model:SetAttribute("PoolActive", false)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
		elseif descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
			descendant.Rate = 0
			descendant:Clear()
		elseif descendant:IsA("Light") then
			descendant.Enabled = false
			descendant.Brightness = 0
		elseif descendant:IsA("Beam") then
			descendant.Enabled = false
		elseif descendant:IsA("Trail") then
			descendant.Enabled = false
			descendant:Clear()
		end
	end
end

local function HideSlot(slot: VfxSlot, poolFolder: Folder): ()
	slot.generation += 1
	slot.playback:Destroy()
	slot.active = false
	HideModel(slot.model)
	slot.model.Parent = poolFolder
end

local function BeginSlot(slot: VfxSlot): VfxSlot
	HideSlot(slot, slot.model.Parent :: Folder)
	slot.playback = LifecycleTool.new()
	slot.active = true
	slot.startedAt = os.clock()
	slot.expiresAt = math.huge
	slot.model:SetAttribute("PoolActive", true)
	return slot
end

local function NewSlot(model: Model, kind: string, tier: number?): VfxSlot
	return { model = model, active = false, kind = kind, tier = tier, generation = 0, playback = LifecycleTool.new(), startedAt = 0, expiresAt = math.huge }
end

local function HideLabel(slot: DamageLabelSlot): ()
	slot.generation += 1
	slot.playback:Destroy()
	slot.gui.Enabled = false
	slot.gui:ResetPropertyToDefault("Adornee")
	slot.active = false
	if slot.cleanup then
		slot.cleanup()
		slot.cleanup = nil
	end
end

function FarmVisualEffects.new(): VfxManager
	return setmetatable({
		scope = LifecycleTool.new(),
		poolFolder = nil :: any,
		templateFolder = nil,
		camera = nil,
		characterScope = LifecycleTool.new(),
		damagePool = {},
		pickupPool = {},
		muzzlePool = {},
		arcPool = {},
		activeArcs = {},
		hitPool = {},
		roastPool = {},
		roastReserves = {},
		anchorPool = {},
		pickupQueue = {},
		pickupRows = {},
		pickupAdornee = nil,
		pickupAnchor = nil,
		pickupAnchorGeneration = 0,
		pickupFallback = nil,
		pickupFallbackPos = Vector3.zero,
		nextPickupSoundAt = -math.huge,
		shakeIntensity = 0,
		shakeRemaining = 0,
		originalFov = 70,
		fovShockRemaining = 0,
		fovDelta = 0,
		rng = Random.new(),
		initialized = false,
	}, FarmVisualEffects)
end

local function CloneTemplate(templates: Folder, name: string, poolFolder: Folder): Model?
	local template = templates:FindFirstChild(name)
	if not template or not template:IsA("Model") then
		return nil
	end
	local clone = template:Clone()
	clone.Name = name .. "_Pool"
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
			descendant.Massless = true
		elseif descendant:IsA("ParticleEmitter") then
			descendant.Rate = 0
		elseif descendant:IsA("PointLight") then
			descendant.Brightness = 0
		end
	end
	HideModel(clone)
	clone.Parent = poolFolder
	return clone
end

function FarmVisualEffects.WarmupPools(self: VfxManager): ()
	local templates = self.templateFolder
	if not templates then
		return
	end
	local names = FarmConfig.VfxTemplates
	-- 电弧按配置最大目标数预热，保证单次多目标攻击可以完整显示。
	local maximumTargets = 1
	for _, weapon in Economy.Weapons do
		maximumTargets = math.max(maximumTargets, weapon.maximumTargets)
	end
	for tier = 1, 5 do
		local model = CloneTemplate(templates, names.ZapMuzzlePrefix .. tostring(tier), self.poolFolder)
		if model then
			table.insert(self.muzzlePool, NewSlot(model, "muzzle", tier))
		end
	end
	for _ = 1, maximumTargets * 6 do
		local model = CloneTemplate(templates, names.ZapArc, self.poolFolder)
		if model then
			table.insert(self.arcPool, NewSlot(model, "arc", nil))
		end
	end
	for _ = 1, maximumTargets do
		local model = CloneTemplate(templates, names.HitImpact, self.poolFolder)
		if model then
			table.insert(self.hitPool, NewSlot(model, "hit", nil))
		end
	end
	for _ = 1, 4 do
		local model = CloneTemplate(templates, names.RoastFlight, self.poolFolder)
		if model then
			table.insert(self.roastPool, NewSlot(model, "roast", nil))
		end
	end
	for _ = 1, 24 do
		local model = CloneTemplate(templates, names.FloatAnchor, self.poolFolder)
		if model then
			table.insert(self.anchorPool, NewSlot(model, "anchor", nil))
		end
	end
end

local function Acquire(pool: { VfxSlot }): VfxSlot?
	local oldest: VfxSlot? = nil
	for _, slot in pool do
		if not slot.active then
			return BeginSlot(slot)
		end
		if not oldest or slot.startedAt < oldest.startedAt then
			oldest = slot
		end
	end
	return if oldest then BeginSlot(oldest) else nil
end

local function ReleaseArc(self: VfxManager, arc: ArcPlayback): ()
	for i, slot in arc.slots do
		if slot.generation == arc.generations[i] then
			HideSlot(slot, self.poolFolder)
		end
	end
end

local function UpdateArc(arc: ArcPlayback, liveOrigin: Vector3): ()
	local origin = if arc.followPlayer then liveOrigin else arc.from
	local last = origin
	local progress = math.clamp(arc.elapsed / AttackDuration, 0, 1)
	for i, slot in arc.slots do
		if slot.generation ~= arc.generations[i] then
			continue
		end
		local nextPoint = origin:Lerp(arc.to, i / #arc.slots) + arc.offsets[i]
		local distance = (nextPoint - last).Magnitude
		local root = slot.model.PrimaryPart
		local core = slot.model:FindFirstChild("ArcCore")
		local glow = slot.model:FindFirstChild("ArcGlow")
		if distance > 0.02 then
			local cf = CFrame.lookAt((last + nextPoint) / 2, nextPoint)
			if root then
				root.CFrame = cf
			end
			if core and core:IsA("BasePart") then
				local width = (0.18 + arc.tier * 0.03) * (1 - progress) + 0.02 * progress
				core.Size = Vector3.new(width, width, distance)
				core.CFrame = cf
				core.Color = arc.color
				core.Transparency = progress
			end
			if glow and glow:IsA("BasePart") then
				local width = 0.35 + arc.tier * 0.04
				glow.Size = Vector3.new(width, width, distance)
				glow.CFrame = cf
				glow.Color = arc.color:Lerp(Color3.new(1, 1, 1), 0.35)
				glow.Transparency = 0.45 + progress * 0.55
			end
		else
			if core and core:IsA("BasePart") then
				core.Transparency = 1
			end
			if glow and glow:IsA("BasePart") then
				glow.Transparency = 1
			end
		end
		last = nextPoint
	end
end

function FarmVisualEffects.ClearAttacks(self: VfxManager): ()
	for _, arc in self.activeArcs do
		ReleaseArc(self, arc)
	end
	table.clear(self.activeArcs)
	for _, pool in { self.muzzlePool, self.hitPool } do
		for _, slot in pool do
			HideSlot(slot, self.poolFolder)
		end
	end
	for _, slot in self.damagePool do
		HideLabel(slot)
	end
end

function FarmVisualEffects.UpdateAttacks(self: VfxManager, dt: number): ()
	local origin = GetLiveZapOrigin()
	if not origin then
		self:ClearAttacks()
		return
	end
	for i = #self.activeArcs, 1, -1 do
		local arc = self.activeArcs[i]
		arc.elapsed += dt
		if arc.elapsed >= AttackDuration then
			ReleaseArc(self, arc)
			table.remove(self.activeArcs, i)
		else
			UpdateArc(arc, origin)
		end
	end
	for _, pool in { self.muzzlePool, self.hitPool } do
		for _, slot in pool do
			if slot.active then
				if os.clock() >= slot.expiresAt then
					HideSlot(slot, self.poolFolder)
				elseif slot.kind == "muzzle" then
					slot.model:PivotTo(CFrame.new(origin))
				end
			end
		end
	end
end

function FarmVisualEffects.Init(self: VfxManager): ()
	if self.initialized then
		return
	end
	self.initialized = true
	self.nextPickupSoundAt = -math.huge
	self.scope = LifecycleTool.new()

	self.camera = workspace.CurrentCamera
	if self.camera then
		self.originalFov = self.camera.FieldOfView
	end

	local poolFolder = workspace:FindFirstChild("FarmVfxPool")
	if not poolFolder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "FarmVfxPool"
		newFolder.Parent = workspace
		poolFolder = newFolder
	end
	self.poolFolder = poolFolder :: Folder
	self.templateFolder = GetTemplateFolder()
	self:WarmupPools()

	-- 预热 VFX 模板资源（人物动作动画已停用，不再预载 Animation）
	if self.templateFolder then
		self.scope:Spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync({ self.templateFolder :: Folder })
			end)
		end)
	end

	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local damageTemplate = ReplicatedStorage:WaitForChild("UI"):WaitForChild("DamagePopGui") :: BillboardGui
	-- 拾取提示独立持有两行，避免收起武器时被攻击清理或伤害飘字复用。
	for i = 1, 26 do
		local isPickup = i > 24
		local gui = damageTemplate:Clone()
		gui.Name = if isPickup then "PickupPopGui_" .. (i - 24) else "DamagePopGui_" .. i
		local frame = gui:WaitForChild("DamageFrame") :: Frame
		local scale = frame:WaitForChild("UIScale") :: UIScale
		local label = frame:WaitForChild("DamageText") :: TextLabel
		local stroke = label:WaitForChild("UIStroke") :: UIStroke

		gui.Parent = playerGui
		table.insert(if isPickup then self.pickupPool else self.damagePool, {
			gui = gui,
			label = label,
			stroke = stroke,
			scale = scale,
			baseSize = gui.Size,
			defaultColor = label.TextColor3,
			defaultStrokeColor = stroke.Color,
			active = false,
			generation = 0,
			playback = LifecycleTool.new(),
			cleanup = nil,
		})
	end

	local function OnCharacterAdded(character: Model): ()
		self:ClearAttacks()
		self.characterScope:Destroy()
		self.characterScope = LifecycleTool.new()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			self.characterScope:Connect(humanoid.Died:Connect(function()
				self:ClearAttacks()
			end))
		end
	end
	-- 子生命周期只持有当前角色的死亡连接，重生时不会累计旧连接。
	self.scope:Connect(localPlayer.CharacterRemoving:Connect(function()
		self.characterScope:Destroy()
		self.characterScope = LifecycleTool.new()
		self:ClearAttacks()
		self:ClearPickupNotices()
	end))
	self.scope:Connect(localPlayer.CharacterAdded:Connect(OnCharacterAdded))

	if localPlayer.Character then
		OnCharacterAdded(localPlayer.Character)
	end
	self.scope:Connect(RunService.RenderStepped:Connect(function(dt: number)
		self:UpdateAttacks(dt)
		local cam = self.camera or workspace.CurrentCamera
		if not cam then
			return
		end
		if self.shakeRemaining > 0 then
			self.shakeRemaining = math.max(0, self.shakeRemaining - dt)
			local progress = self.shakeRemaining / FarmConfig.CameraShakeDuration
			local offsetX = self.rng:NextNumber(-1, 1) * self.shakeIntensity * progress
			local offsetY = self.rng:NextNumber(-1, 1) * self.shakeIntensity * progress
			cam.CFrame = cam.CFrame * CFrame.new(offsetX, offsetY, 0)
		end
		if self.fovShockRemaining > 0 then
			self.fovShockRemaining = math.max(0, self.fovShockRemaining - dt)
			local fovProgress = self.fovShockRemaining / 0.15
			cam.FieldOfView = self.originalFov + self.fovDelta * fovProgress
		else
			if math.abs(cam.FieldOfView - self.originalFov) > 0.05 then
				cam.FieldOfView = self.originalFov
			end
		end
	end))
end

function FarmVisualEffects.TriggerScreenImpact(self: VfxManager, shakeIntensity: number?, fovDelta: number?): ()
	self.shakeIntensity = shakeIntensity or FarmConfig.CameraShakeIntensity
	self.shakeRemaining = FarmConfig.CameraShakeDuration
	if fovDelta and fovDelta ~= 0 then
		self.fovDelta = fovDelta
		self.fovShockRemaining = 0.15
	end
end

function FarmVisualEffects.SpawnFloatingText(self: VfxManager, pos: Vector3, text: string, color: Color3?, strokeColor: Color3?, scaleMultiplier: number?): () -> ()
	local slot: DamageLabelSlot? = nil
	for _, s in self.damagePool do
		if not s.active then
			slot = s
			break
		end
	end
	if not slot then
		slot = self.damagePool[1]
	end
	assert(slot)

	HideLabel(slot)
	slot.playback = LifecycleTool.new()
	slot.active = true
	local generation = slot.generation
	local gui = slot.gui
	local label = slot.label
	local stroke = slot.stroke

	label.Text = text
	label.TextColor3 = color or slot.defaultColor
	stroke.Color = strokeColor or slot.defaultStrokeColor
	local baseSize = scaleMultiplier or 1.0
	gui.Size = UDim2.fromOffset(math.floor(slot.baseSize.X.Offset * baseSize), math.floor(slot.baseSize.Y.Offset * baseSize))
	slot.scale.Scale = baseSize
	label.TextTransparency = 0

	local anchorSlot = Acquire(self.anchorPool)
	local anchorGeneration = if anchorSlot then anchorSlot.generation else 0
	local anchorPart: BasePart? = nil
	if anchorSlot then
		local root = anchorSlot.model.PrimaryPart
		if root then
			root.CFrame = CFrame.new(pos + Vector3.yAxis * 0.8)
			anchorPart = root
		end
	end
	if not anchorPart then
		if anchorSlot then
			HideSlot(anchorSlot, self.poolFolder)
			anchorSlot = nil
		end
		-- 模板缺失时的一次性兜底锚点（仍回收 Destroy，正常路径应走池）
		local fallback = Instance.new("Part")
		fallback.Name = "FloatAnchorFallback"
		fallback.Size = Vector3.new(0.1, 0.1, 0.1)
		fallback.Transparency = 1
		fallback.CanCollide = false
		fallback.CanQuery = false
		fallback.CanTouch = false
		fallback.Anchored = true
		fallback.CFrame = CFrame.new(pos + Vector3.yAxis * 0.8)
		fallback.Parent = self.poolFolder
		anchorPart = fallback
	end

	slot.cleanup = function()
		if anchorSlot and anchorSlot.generation == anchorGeneration then
			HideSlot(anchorSlot, self.poolFolder)
		elseif not anchorSlot then
			local fallback = anchorPart
			if fallback then
				fallback:Destroy()
			end
		end
	end
	gui.Adornee = anchorPart :: BasePart
	gui.StudsOffset = Vector3.zero
	gui.Enabled = true

	local targetStudsOffset = Vector3.new(self.rng:NextNumber(-0.6, 0.6), 2.2, 0)
	slot.playback:Play(TweenService:Create(gui, TweenInfo.new(0.65, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		StudsOffset = targetStudsOffset,
	}))

	slot.playback:Delay(0.4, function()
		if not slot.active or slot.generation ~= generation then
			return
		end
		slot.playback:Play(TweenService:Create(label, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		}))
	end)

	slot.playback:Delay(0.68, function()
		if slot.generation == generation then
			HideLabel(slot)
		end
	end)
	-- 槽位复用后，旧攻击的回执不能撤销新提示。
	return function(): ()
		if slot.generation == generation then HideLabel(slot) end
	end
end

function FarmVisualEffects.PlayMuzzle(self: VfxManager, tier: number, _fromPos: Vector3, _zapColor: Color3): ()
	local origin = GetLiveZapOrigin()
	if not origin then
		return
	end
	for _, candidate in self.muzzlePool do
		if candidate.tier == math.clamp(tier, 1, 5) then
			local slot = BeginSlot(candidate)
			slot.model:PivotTo(CFrame.new(origin))
			local sparks = slot.model:FindFirstChild("Sparks", true)
			if sparks and sparks:IsA("ParticleEmitter") then
				sparks.LockedToPart = true
			end
			EmitNamed(slot.model, "Sparks", 3)
			slot.expiresAt = os.clock() + SparkDuration
			return
		end
	end
end

function FarmVisualEffects.CreateLightningSegment(self: VfxManager, from: Vector3, to: Vector3, color: Color3, tier: number, followPlayer: boolean?): ()
	local origin = GetLiveZapOrigin()
	if not origin then
		return
	end
	local steps = if tier >= 3 then 6 else 4
	if #self.arcPool < steps then
		return
	end
	local function CountFree(): number
		local count = 0
		for _, slot in self.arcPool do
			if not slot.active then
				count += 1
			end
		end
		return count
	end
	-- 总是整条回收最早电弧，保证新电弧的分段不会抢占同一条电弧。
	while CountFree() < steps do
		local oldest = table.remove(self.activeArcs, 1)
		if not oldest then
			return
		end
		ReleaseArc(self, oldest)
	end
	local arc: ArcPlayback =
		{ slots = {}, generations = {}, offsets = {}, from = from, to = to, followPlayer = followPlayer ~= false, color = color, tier = tier, elapsed = 0 }
	local maxDisplacement = if tier >= 4 then 0.55 else 0.32
	for _, slot in self.arcPool do
		if slot.active then
			continue
		end
		BeginSlot(slot)
		table.insert(arc.slots, slot)
		table.insert(arc.generations, slot.generation)
		local offset = if #arc.slots == steps
			then Vector3.zero
			else Vector3.new(
				self.rng:NextNumber(-maxDisplacement, maxDisplacement),
				self.rng:NextNumber(-maxDisplacement, maxDisplacement),
				self.rng:NextNumber(-maxDisplacement, maxDisplacement)
			)
		table.insert(arc.offsets, offset)
		if #arc.slots == steps then
			break
		end
	end
	table.insert(self.activeArcs, arc)
	UpdateArc(arc, origin)
end

function FarmVisualEffects.CreateHitImpact(self: VfxManager, pos: Vector3, damage: number, isCooked: boolean, _tier: number): () -> ()
	local slot = Acquire(self.hitPool)
	if slot then
		slot.model:PivotTo(CFrame.new(pos))
		EmitNamed(slot.model, "Sparks", if isCooked then 5 else 3)
		slot.expiresAt = os.clock() + SparkDuration
	end

	local cancel: () -> ()
	if isCooked then
		cancel = self:SpawnFloatingText(pos + Vector3.yAxis * 0.9, Texts.Farm.KnockoutLoot.source, Color3.fromRGB(255, 215, 0), Color3.fromRGB(60, 25, 0), 1.2)
		FarmSoundTool.Play("AnimalCooked", pos)
	else
		cancel = self:SpawnFloatingText(pos, "-" .. tostring(damage), Color3.fromRGB(255, 200, 60), Color3.fromRGB(40, 10, 0), 1.0)
		FarmSoundTool.Play("AnimalHit", pos)
	end
	return cancel
end

function FarmVisualEffects.PlayZapEffects(
	self: VfxManager,
	tier: number,
	_fromPos: Vector3,
	targets: { { x: number, y: number, z: number, damage: number, isCooked: boolean, id: string?, remainingHealth: number? } }
): { [string]: () -> () }
	local clampedTier = math.clamp(tier, 1, 5)
	local weapon = Economy.Weapons[clampedTier]
	local mode = if weapon then weapon.mode else "single"
	local colorHex = FarmConfig.ZapColors[clampedTier] or "53DEFF"
	local zapColor = Color3.fromHex(colorHex)
	-- 攻击起点读取已装备电击枪预制枪口的实时世界坐标
	local liveFrom = GetLiveZapOrigin()
	local cancellations: { [string]: () -> () } = {}
	if not self.initialized or not liveFrom then
		return cancellations
	end

	self:PlayMuzzle(clampedTier, liveFrom, zapColor)
	self:TriggerScreenImpact(0.1 + clampedTier * 0.03, if mode == "cone" then -1.8 else 0)

	local previous = liveFrom
	for index, target in targets do
		local targetPos = Vector3.new(target.x, target.y, target.z)
		local segmentStart = liveFrom
		local followMuzzle = true
		if mode == "chain" and index > 1 then
			segmentStart = previous
			followMuzzle = false
		end
		self:CreateLightningSegment(segmentStart, targetPos, zapColor, clampedTier, followMuzzle)
		previous = targetPos
		local cancel = self:CreateHitImpact(targetPos, target.damage, target.isCooked, clampedTier)
		if target.id then cancellations[target.id] = cancel end
	end
	return cancellations
end

function FarmVisualEffects.PlayZapMiss(self: VfxManager, tier: number, aim: Vector3): ()
	local clampedTier = math.clamp(tier, 1, 5)
	local weapon = Economy.Weapons[clampedTier]
	local liveFrom = GetLiveZapOrigin()
	if not weapon or not self.initialized or not liveFrom then
		return
	end
	local flat = Vector3.new(aim.X, 0, aim.Z)
	if flat.Magnitude <= 1e-4 then
		return
	end
	local colorHex = FarmConfig.ZapColors[clampedTier] or "53DEFF"
	local zapColor = Color3.fromHex(colorHex)
	self:PlayMuzzle(clampedTier, liveFrom, zapColor)
	self:TriggerScreenImpact(0.1 + clampedTier * 0.03, if weapon.mode == "cone" then -1.8 else 0)
	self:CreateLightningSegment(liveFrom, liveFrom + flat.Unit * weapon.range, zapColor, clampedTier, true)
end

local function StyleRoastBody(body: BasePart, qualityId: string): ()
	if qualityId == "golden" then
		body.Color = Color3.fromRGB(255, 204, 40)
		body.Material = Enum.Material.Metal
		body.Size = Vector3.new(0.55, 0.48, 0.5)
	elseif qualityId == "rainbow" then
		body.Color = Color3.fromRGB(127, 240, 255)
		body.Material = Enum.Material.Neon
		body.Size = Vector3.new(0.55, 0.48, 0.5)
	elseif qualityId == "giant" then
		body.Color = Color3.fromRGB(80, 220, 255)
		body.Material = Enum.Material.Neon
		body.Size = Vector3.new(0.8, 0.7, 0.7)
	else
		body.Color = Color3.fromHex("EF953B")
		body.Material = Enum.Material.SmoothPlastic
		body.Size = Vector3.new(0.55, 0.48, 0.5)
	end
	body.Transparency = 0
end

local function PrepareFlightClone(clone: Model): ()
	local billboards: { BillboardGui } = {}
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BillboardGui") then
			table.insert(billboards, descendant)
		elseif descendant:IsA("BasePart") then
			if CollectionService:HasTag(descendant, "FarmSignPart") then
				CollectionService:RemoveTag(descendant, "FarmSignPart")
			end
			descendant:SetAttribute("FarmSign", nil)
			descendant:SetAttribute("FarmSignAudience", nil)
			descendant:SetAttribute("FarmText", nil)
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
	for _, billboard in billboards do
		billboard:Destroy()
	end
end

local function HideWorldRoast(model: Model): ()
	local alive, parent = pcall(function()
		return model.Parent
	end)
	if not alive or parent == nil then
		return
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = 1
		elseif descendant:IsA("Highlight") then
			descendant.Enabled = false
		elseif descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
		elseif descendant:IsA("Light") then
			descendant.Enabled = false
		end
	end
end

local function RoastPosition(model: Model): Vector3?
	local primary = model.PrimaryPart
	if primary then
		return primary.Position
	end
	local part = model:FindFirstChildWhichIsA("BasePart")
	if part then
		return part.Position
	end
	return nil
end

local function GetCookedFolder(): Folder?
	local plotId = localPlayer:GetAttribute("FarmPlotId")
	if typeof(plotId) ~= "string" then
		return nil
	end
	local farms = workspace:FindFirstChild("PersonalFarms")
	local plot = if farms then farms:FindFirstChild(plotId) else nil
	local folder = if plot then Paths.Find(plot, "CookedFood") else nil
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

local function GetBasketMouth(): Vector3?
	local character = localPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not character or not root or not root:IsA("BasePart") then
		return nil
	end
	local basket = character:FindFirstChild("ChickenBasket")
	local body = if basket then basket:FindFirstChild("Basket") else nil
	if body and body:IsA("BasePart") then
		return body.Position + body.CFrame.UpVector * (body.Size.Y * 0.5)
	end
	local offset = FarmConfig.PickupBasketOffset
	return (root.CFrame * CFrame.new(offset.x, offset.y, offset.z)).Position
end

local function PruneRoastReserves(self: VfxManager, now: number): ()
	local kept: { ReservedRoast } = {}
	for _, reserve in self.roastReserves do
		if now < reserve.expiresAt then
			table.insert(kept, reserve)
		else
			reserve.model:Destroy()
		end
	end
	self.roastReserves = kept
end

local function ClaimRoastReserve(self: VfxManager, fromPos: Vector3): Model?
	local bestIndex: number? = nil
	local bestDistance = FarmConfig.PickupMatchDistance
	for index, reserve in self.roastReserves do
		local distance = (reserve.position - fromPos).Magnitude
		if distance <= bestDistance then
			bestIndex = index
			bestDistance = distance
		end
	end
	if not bestIndex then
		return nil
	end
	local reserve = self.roastReserves[bestIndex]
	table.remove(self.roastReserves, bestIndex)
	HideWorldRoast(reserve.source)
	return reserve.model
end

local function CloneLiveRoast(fromPos: Vector3): Model?
	local folder = GetCookedFolder()
	if not folder then
		return nil
	end
	local best: Model? = nil
	local bestDistance = FarmConfig.PickupMatchDistance
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			local position = RoastPosition(child)
			if position then
				local distance = (position - fromPos).Magnitude
				if distance <= bestDistance then
					best = child
					bestDistance = distance
				end
			end
		end
	end
	if not best then
		return nil
	end
	local clone = best:Clone()
	PrepareFlightClone(clone)
	HideWorldRoast(best)
	return clone
end

-- 拾取成功最多两行，贴在筐口上方。同物种同品质合并件数和重量，其余种类排队补上空位。
local function PickupKey(speciesId: string, qualityId: string): string
	return speciesId .. "\0" .. qualityId
end

local function PickupColor(qualityId: string): Color3
	if qualityId == "golden" then
		return Color3.fromRGB(255, 215, 0)
	elseif qualityId == "giant" then
		return Color3.fromRGB(120, 240, 255)
	end
	return Color3.fromRGB(120, 255, 120)
end

local function PickupText(notice: PickupNotice): string
	local species = Economy.GetSpecies(notice.speciesId)
	local foodName = if species then species.foodName else Texts.Farm.LootFoodFallback.source
	return Texts.Farm.LootPickup.source:format(foodName, notice.count, notice.weightKg)
end

local function RowOffset(adornee: BasePart, rowIndex: number): Vector3
	local lift = if adornee.Name == "Basket" then adornee.Size.Y * 0.5 else 0
	local rise = if rowIndex == 1 then PickupLowerRise else PickupUpperRise
	return Vector3.new(0, lift + rise, 0)
end

local function ReleasePickupAnchor(self: VfxManager): ()
	local anchor = self.pickupAnchor
	self.pickupAnchor = nil
	if anchor and anchor.generation == self.pickupAnchorGeneration then
		HideSlot(anchor, self.poolFolder)
	end
	self.pickupAnchorGeneration = 0
	local fallback = self.pickupFallback
	self.pickupFallback = nil
	if fallback then
		fallback:Destroy()
	end
	self.pickupAdornee = nil
end

local function EnsurePickupAnchor(self: VfxManager, fallbackPos: Vector3): BasePart
	local current = self.pickupAdornee
	if current and current.Parent then
		return current
	end
	ReleasePickupAnchor(self)
	local character = localPlayer.Character
	local basket = if character then character:FindFirstChild("ChickenBasket") else nil
	local body = if basket then basket:FindFirstChild("Basket") else nil
	if body and body:IsA("BasePart") then
		self.pickupAdornee = body
		return body
	end
	local mouth = GetBasketMouth() or fallbackPos
	local anchorSlot = Acquire(self.anchorPool)
	if anchorSlot then
		local root = anchorSlot.model.PrimaryPart
		if root and root:IsA("BasePart") then
			root.CFrame = CFrame.new(mouth)
			self.pickupAnchor = anchorSlot
			self.pickupAnchorGeneration = anchorSlot.generation
			self.pickupAdornee = root
			return root
		end
		HideSlot(anchorSlot, self.poolFolder)
	end
	local fallback = Instance.new("Part")
	fallback.Name = "FloatAnchorFallback"
	fallback.Size = Vector3.new(0.1, 0.1, 0.1)
	fallback.Transparency = 1
	fallback.CanCollide = false
	fallback.CanQuery = false
	fallback.CanTouch = false
	fallback.Anchored = true
	fallback.CFrame = CFrame.new(mouth)
	fallback.Parent = self.poolFolder
	self.pickupFallback = fallback
	self.pickupAdornee = fallback
	return fallback
end

function FarmVisualEffects.ClearPickupNotices(self: VfxManager): ()
	table.clear(self.pickupQueue)
	for rowIndex = 1, 2 do
		local row = self.pickupRows[rowIndex]
		self.pickupRows[rowIndex] = nil
		if row and row.slot.generation == row.generation then
			HideLabel(row.slot)
		end
	end
	ReleasePickupAnchor(self)
end

local PumpPickupRows: (VfxManager) -> ()
local SchedulePickupRow: (VfxManager, PickupRow) -> ()

local function ReleasePickupRow(self: VfxManager, row: PickupRow, generation: number, serial: number): ()
	if self.pickupRows[row.rowIndex] ~= row or row.serial ~= serial then
		return
	end
	self.pickupRows[row.rowIndex] = nil
	if row.slot.generation == generation then
		HideLabel(row.slot)
	end
	if not self.pickupRows[1] and not self.pickupRows[2] then
		ReleasePickupAnchor(self)
	end
	PumpPickupRows(self)
end

SchedulePickupRow = function(self: VfxManager, row: PickupRow): ()
	local serial = row.serial
	local generation = row.generation
	local slot = row.slot
	slot.playback:Delay(PickupHoldSeconds, function()
		if self.pickupRows[row.rowIndex] ~= row or row.serial ~= serial or slot.generation ~= generation then
			return
		end
		slot.playback:Play(TweenService:Create(slot.label, TweenInfo.new(PickupFadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
		}))
	end)
	slot.playback:Delay(PickupHoldSeconds + PickupFadeSeconds, function()
		ReleasePickupRow(self, row, generation, serial)
	end)
end

local function RefreshPickupRow(self: VfxManager, row: PickupRow): ()
	row.serial += 1
	local slot = row.slot
	slot.playback:Destroy()
	slot.playback = LifecycleTool.new()
	slot.label.Text = PickupText(row.notice)
	slot.label.TextTransparency = 0
	SchedulePickupRow(self, row)
end

local function ForgetPickupSlot(self: VfxManager, slot: DamageLabelSlot): ()
	for rowIndex = 1, 2 do
		local row = self.pickupRows[rowIndex]
		if row and row.slot == slot then
			self.pickupRows[rowIndex] = nil
		end
	end
end

local function ShowPickupRow(self: VfxManager, rowIndex: number, notice: PickupNotice, fallbackPos: Vector3): boolean
	local adornee = EnsurePickupAnchor(self, fallbackPos)
	local slot: DamageLabelSlot? = nil
	for _, candidate in self.pickupPool do
		if not candidate.active then
			slot = candidate
			break
		end
	end
	if not slot then
		slot = self.pickupPool[1]
	end
	if not slot then
		if not self.pickupRows[1] and not self.pickupRows[2] then
			ReleasePickupAnchor(self)
		end
		return false
	end
	ForgetPickupSlot(self, slot)
	HideLabel(slot)
	slot.playback = LifecycleTool.new()
	slot.active = true
	local generation = slot.generation
	slot.label.Text = PickupText(notice)
	slot.label.TextColor3 = PickupColor(notice.qualityId)
	slot.stroke.Color = PickupStrokeColor
	slot.label.TextTransparency = 0
	slot.gui.Size = UDim2.fromOffset(
		math.floor(slot.baseSize.X.Offset * PickupLabelScale),
		math.floor(slot.baseSize.Y.Offset * PickupLabelScale)
	)
	slot.scale.Scale = PickupLabelScale
	slot.gui.Adornee = adornee
	slot.gui.StudsOffset = RowOffset(adornee, rowIndex)
	slot.gui.Enabled = true
	slot.cleanup = nil
	local row: PickupRow = {
		notice = notice,
		slot = slot,
		generation = generation,
		serial = 1,
		rowIndex = rowIndex,
	}
	self.pickupRows[rowIndex] = row
	SchedulePickupRow(self, row)
	return true
end

PumpPickupRows = function(self: VfxManager): ()
	for rowIndex = 1, 2 do
		if not self.pickupRows[rowIndex] then
			local notice = table.remove(self.pickupQueue, 1)
			if not notice then
				return
			end
			if not ShowPickupRow(self, rowIndex, notice, self.pickupFallbackPos) then
				table.insert(self.pickupQueue, 1, notice)
				return
			end
		end
	end
end

local function EnqueuePickup(self: VfxManager, pos: Vector3, speciesId: string, qualityId: string, weightKg: number): ()
	self.pickupFallbackPos = pos
	local key = PickupKey(speciesId, qualityId)
	for rowIndex = 1, 2 do
		local row = self.pickupRows[rowIndex]
		if row and row.notice.key == key then
			row.notice.count += 1
			row.notice.weightKg += weightKg
			RefreshPickupRow(self, row)
			return
		end
	end
	for _, notice in self.pickupQueue do
		if notice.key == key then
			notice.count += 1
			notice.weightKg += weightKg
			return
		end
	end
	table.insert(self.pickupQueue, {
		key = key,
		speciesId = speciesId,
		qualityId = qualityId,
		count = 1,
		weightKg = weightKg,
	})
	PumpPickupRows(self)
end

local function PlayPickupFeedback(self: VfxManager, pos: Vector3, speciesId: string, qualityId: string, weightKg: number): ()
	if not self.initialized then
		return
	end
	local now = os.clock()
	if now >= self.nextPickupSoundAt then
		self.nextPickupSoundAt = now + PickupSoundMergeSeconds
		FarmSoundTool.Play("Pickup")
	end
	EnqueuePickup(self, pos, speciesId, qualityId, weightKg)
end

function FarmVisualEffects.ReserveNearbyRoasts(self: VfxManager): ()
	if not self.initialized then
		return
	end
	local character = localPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	local folder = GetCookedFolder()
	if not folder then
		return
	end
	local now = os.clock()
	PruneRoastReserves(self, now)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			local position = RoastPosition(child)
			local alreadyReserved = false
			for _, reserve in self.roastReserves do
				if reserve.source == child then
					alreadyReserved = true
					reserve.position = position or reserve.position
					reserve.expiresAt = now + FarmConfig.PickupReserveSeconds
				end
			end
			if not alreadyReserved and position and (position - root.Position).Magnitude <= FarmConfig.PickupReserveRange then
				local clone = child:Clone()
				PrepareFlightClone(clone)
				table.insert(self.roastReserves, {
					source = child,
					model = clone,
					position = position,
					expiresAt = now + FarmConfig.PickupReserveSeconds,
				})
			end
		end
	end
	self.scope:Delay(FarmConfig.PickupReserveSeconds, function()
		PruneRoastReserves(self, os.clock())
	end)
end

function FarmVisualEffects.PlayOriginalRoastIntoBasket(
	self: VfxManager,
	fromPos: Vector3,
	speciesId: string,
	qualityId: string,
	weightKg: number
): ()
	local model = ClaimRoastReserve(self, fromPos) or CloneLiveRoast(fromPos)
	if not model then
		local mouth = GetBasketMouth()
		PlayPickupFeedback(self, mouth or fromPos, speciesId, qualityId, weightKg)
		return
	end
	model.Parent = self.poolFolder
	local startPivot = model:GetPivot()
	local p0 = startPivot.Position
	local spin = startPivot - startPivot.Position
	local duration = FarmConfig.PickupFlightDuration
	local elapsed = 0
	local arrive = p0

	self.scope:Spawn(function()
		while elapsed < duration do
			local dt = task.wait()
			if not self.initialized or not model.Parent then
				return
			end
			elapsed += dt
			local linear = math.clamp(elapsed / duration, 0, 1)
			local t = 1 - (1 - linear) * (1 - linear)
			local mouth = GetBasketMouth()
			if not mouth then
				model:Destroy()
				PlayPickupFeedback(self, arrive, speciesId, qualityId, weightKg)
				return
			end
			arrive = mouth
			local mid = (p0 + mouth) * 0.5
			local p1 = mid + Vector3.yAxis * FarmConfig.PickupArcHeight
			local u = 1 - t
			local pos = u * u * p0 + 2 * u * t * p1 + t * t * mouth
			local tumble = CFrame.Angles(-t * FarmConfig.PickupTumbleTurns * math.pi * 2, 0, 0)
			model:PivotTo(CFrame.new(pos) * spin * tumble)
		end
		if model.Parent then
			model:Destroy()
		end
		PlayPickupFeedback(self, arrive, speciesId, qualityId, weightKg)
	end)
end

function FarmVisualEffects.PlayDeliveryFlying(self: VfxManager, fromPos: Vector3, toPos: Vector3, _speciesId: string, qualityId: string): ()
	local slot = Acquire(self.roastPool)
	if not slot then
		return
	end
	local generation = slot.generation
	local model = slot.model
	local root = model.PrimaryPart
	local body = model:FindFirstChild("RoastBody") :: BasePart?
	if not root or not body then
		HideSlot(slot, self.poolFolder)
		return
	end
	StyleRoastBody(body, qualityId)
	root.CFrame = CFrame.new(fromPos)
	body.CFrame = root.CFrame

	local p0 = fromPos
	local p2 = toPos
	local p1 = (p0 + p2) * 0.5 + Vector3.new(0, FarmConfig.DeliveryArcHeight, 0)
	local duration = FarmConfig.DeliveryFlightDuration
	local elapsed = 0

	slot.playback:Spawn(function()
		while elapsed < duration do
			local dt = task.wait()
			if not self.initialized or not slot.active or slot.generation ~= generation then
				return
			end
			elapsed += dt
			local t = math.clamp(elapsed / duration, 0, 1)
			local u = 1 - t
			local currentPos = u * u * p0 + 2 * u * t * p1 + t * t * p2
			local cf = CFrame.new(currentPos) * CFrame.Angles(t * 4, 0, t * 2)
			root.CFrame = cf
			body.CFrame = cf
		end
		HideSlot(slot, self.poolFolder)
	end)
end

function FarmVisualEffects.Destroy(self: VfxManager): ()
	if not self.initialized then
		return
	end
	self.initialized = false
	self:ClearPickupNotices()
	self.scope:Destroy()
	self.characterScope:Destroy()
	self:ClearAttacks()
	for _, pool in { self.arcPool, self.roastPool, self.anchorPool } do
		for _, slot in pool do
			HideSlot(slot, self.poolFolder)
		end
	end
	for _, pool in { self.damagePool, self.pickupPool } do
		for _, slot in pool do
			slot.gui:Destroy()
		end
	end
	self.damagePool = {}
	self.pickupPool = {}
	self.muzzlePool = {}
	self.arcPool = {}
	self.hitPool = {}
	self.roastPool = {}
	for _, reserve in self.roastReserves do
		reserve.model:Destroy()
	end
	self.roastReserves = {}
	self.anchorPool = {}
	if self.poolFolder and self.poolFolder.Parent then
		self.poolFolder:Destroy()
	end
	self.scope:Destroy()
end

return FarmVisualEffects
