-- 攻击特效离线回归：直接加载真实管理器，验证跟随、整弧复用、回收及异步生命周期
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local Vector3, CFrame, Color3 = roblox.Vector3, roblox.CFrame, roblox.Color3
local checks = 0
local function Check(value, message)
	assert(value, message)
	checks += 1
end
local function Signal()
	local listeners = {}
	return {
		Connect = function(self, callback)
			local connection = { Connected = true }
			function connection:Disconnect()
				self.Connected = false
			end
			table.insert(listeners, { callback, connection })
			return connection
		end,
		Fire = function(self, ...)
			for _, listener in table.clone(listeners) do
				if listener[2].Connected then
					listener[1](...)
				end
			end
		end,
		Count = function()
			local count = 0
			for _, listener in listeners do
				if listener[2].Connected then
					count += 1
				end
			end
			return count
		end,
	}
end
local function Node(class, name)
	local node = {
		ClassName = class,
		Name = name or class,
		children = {},
		attributes = {},
		Destroying = Signal(),
		Size = Vector3.one,
		CFrame = CFrame.identity,
		Position = Vector3.zero,
		Transparency = 0,
		Enabled = true,
		Rate = 10,
		Brightness = 8,
		particles = 0,
	}
	function node:IsA(kind)
		return self.ClassName == kind or (kind == "BasePart" and self.ClassName == "Part") or (kind == "Light" and self.ClassName == "PointLight")
	end
	function node:GetDescendants()
		local result = {}
		for _, child in self.children do
			table.insert(result, child)
			for _, descendant in child:GetDescendants() do
				table.insert(result, descendant)
			end
		end
		return result
	end
	function node:FindFirstChild(childName, recursive)
		for _, child in (if recursive then self:GetDescendants() else self.children) do
			if child.Name == childName then
				return child
			end
		end
		return nil
	end
	function node:WaitForChild(childName)
		return self:FindFirstChild(childName)
	end
	function node:FindFirstChildOfClass(kind)
		for _, child in self.children do
			if child:IsA(kind) then
				return child
			end
		end
		return nil
	end
	function node:SetAttribute(key, value)
		self.attributes[key] = value
	end
	function node:GetAttribute(key)
		return self.attributes[key]
	end
	function node:Clear()
		self.particles = 0
		self.cleared = true
	end
	function node:Emit(count)
		self.particles += count
	end
	function node:ResetPropertyToDefault(key)
		self[key] = nil
	end
	function node:Destroy()
		self.destroyed = true
		self.Parent = nil
	end
	function node:PivotTo(cf)
		for _, child in self:GetDescendants() do
			if child:IsA("BasePart") then
				child.CFrame = cf
			end
		end
	end
	function node:Clone()
		local clone = Node(self.ClassName, self.Name)
		for _, key in { "Size", "TextColor3", "Color", "Scale", "TextScaled", "StrokeSizingMode", "LightInfluence", "AlwaysOnTop" } do
			clone[key] = self[key]
		end
		for _, child in self.children do
			local copied = child:Clone()
			copied.Parent = clone
			table.insert(clone.children, copied)
			if child == self.PrimaryPart then
				clone.PrimaryPart = copied
			end
		end
		return clone
	end
	return node
end
local function Add(parent, class, name)
	local child = Node(class, name)
	child.Parent = parent
	table.insert(parent.children, child)
	return child
end
local Config = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmConfig")
local templates = Node("Folder", "VFX")
for _, name in { "ZapMuzzle_T1", "ZapMuzzle_T2", "ZapMuzzle_T3", "ZapMuzzle_T4", "ZapMuzzle_T5", "ZapArcBeam", "HitImpact", "RoastFlight", "FloatAnchor" } do
	local model = Add(templates, "Model", name)
	model.PrimaryPart = Add(model, "Part", "RootPart")
	for _, partName in { "ArcCore", "ArcGlow", "Flash", "ShockRing", "RoastBody" } do
		Add(model, "Part", partName)
	end
	for _, emitter in { "Sparks", "BodyFlash", "DarkSmoke", "Trail" } do
		Add(model.PrimaryPart, "ParticleEmitter", emitter)
	end
	Add(model.PrimaryPart, "PointLight", "FlashLight")
end
local character = Node("Model", "Character")
character.Parent = {}
local root = Add(character, "Part", "HumanoidRootPart")
local weapon = Add(character, "Tool", "FarmWeapon")
local weaponTip = Add(weapon, "Part", "EmitterTip")
local muzzle = Add(weaponTip, "Attachment", "Muzzle")
muzzle.WorldPosition = Vector3.new(0, 0.25, -1.925)
local humanoid = Add(character, "Humanoid", "Humanoid")
humanoid.Health = 100
humanoid.Died = Signal()
local player = { Character = character, CharacterRemoving = Signal(), CharacterAdded = Signal() }
function player:WaitForChild()
	return Node("Folder", "PlayerGui")
end
function player:GetAttribute()
	return nil
end
local render = Signal()
local workspace = Node("Folder", "Workspace")
local sounds = {}
local createdTweens = {}
local TweenService = {}
function TweenService:Create(target, _, goals)
	local tween = { Completed = Signal() }
	function tween:Play()
		self.played = true
	end
	function tween:Cancel()
		self.cancelled = true
	end
	function tween:Destroy()
		self.destroyed = true
	end
	table.insert(createdTweens, tween)
	return tween
end
local modules = {
 FarmScenePaths = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmScenePaths"),}
local shared = {}
function shared:WaitForChild(name)
	return if name == "Shared" then self else name
end
-- 从实际导出的 Studio 模板构造测试替身，避免维护第二套 UI 定义。
local ui = Node("Folder", "UI")
local function ImportGui(instance, parent)
	local node = Add(parent, instance.ClassName, instance.Name)
	for _, key in { "Size", "TextColor3", "Color", "Scale", "TextScaled", "StrokeSizingMode", "LightInfluence", "AlwaysOnTop" } do
		local ok, value = pcall(function() return instance[key] end)
		if ok then node[key] = value end
	end
	for _, child in instance:GetChildren() do ImportGui(child, node) end
	return node
end
local damageTemplate = ImportGui(roblox.deserializeModel(fs.readFile("Assets/Studio/DamagePopGui.rbxm"))[1], ui)
local storage = {}
function storage:WaitForChild(name)
	return if name == "UI" then ui else shared
end
function storage:FindFirstChild(name)
	return if name == "VFX" then templates else nil
end
local services = {
	TweenService = TweenService,
	RunService = { RenderStepped = render },
	ContentProvider = { PreloadAsync = function() end },
	Players = { LocalPlayer = player },
	ReplicatedStorage = storage,
}
local env = {
	game = {
		GetService = function(_, name)
			return services[name]
		end,
	},
	workspace = workspace,
	-- Studio 的无参 task.wait 等待一帧；Lune 默认为零，需模拟帧间隔。
	task = setmetatable({ wait = function(seconds) return task.wait(seconds or 1 / 60) end }, { __index = task }),
	Vector3 = Vector3,
	CFrame = CFrame,
	Color3 = Color3,
	Enum = roblox.Enum,
	UDim2 = roblox.UDim2,
	TweenInfo = {
		new = function(...)
			return {}
		end,
	},
	Random = {
		new = function()
			return {
				NextNumber = function(_, a, b)
					return (a + b) / 2
				end,
			}
		end,
	},
	Instance = {
		new = function(class)
			assert(class ~= "BillboardGui" and class ~= "TextLabel" and class ~= "UIStroke" and class ~= "Frame" and class ~= "UIScale", "runtime must clone UI templates")
			return Node(class)
		end,
	},
	require = function(name)
		return assert(modules[name], name)
	end,
}
modules.LifecycleTool = luau.load(fs.readFile("Scripts/ReplicatedStorage/Scripts/Shared/LifecycleTool.luau"), { environment = env })()
modules.FarmConfig = Config
modules.FarmEconomyConfig = {
	Weapons = {
		{ maximumTargets = 3, mode = "single" },
		{ maximumTargets = 3, mode = "chain" },
		{ maximumTargets = 3, mode = "cone" },
	},
	GetSpecies = function()
		return { foodName = "Chicken" }
	end,
}
modules.GameTexts = { Farm = { KnockoutLoot = { source = "Cooked" }, LootFoodFallback = { source = "Chicken" }, LootPickup = { source = "%s x%d (+%.1f kg)" } } }
modules.FarmSoundTool = {
	Play = function(name)
		table.insert(sounds, name)
	end,
}
local Vfx = luau.load(fs.readFile("Scripts/ReplicatedStorage/Scripts/Client/FarmVisualEffects.luau"), { environment = env })()
local manager = Vfx.new()
manager:Init()
local function Hidden(slot)
	for _, node in slot.model:GetDescendants() do
		if node:IsA("BasePart") then
			Check(node.Transparency == 1, "pooled geometry must be hidden")
		end
		if node:IsA("ParticleEmitter") then
			Check(node.particles == 0 and not node.Enabled and node.Rate == 0, "pooled particles must be cleared")
		end
		if node:IsA("Light") then
			Check(node.Brightness == 0 and not node.Enabled, "pooled lights disabled")
		end
	end
end
for _, pool in { manager.muzzlePool, manager.arcPool, manager.hitPool, manager.roastPool, manager.anchorPool } do
	for _, slot in pool do
		Hidden(slot)
	end
end
Check(#manager.arcPool == 18 and #manager.hitPool == 3 and #manager.anchorPool == 24, "pools sized for complete shots and independent labels")
Check(#manager.damagePool == 24, "floating labels retain 24 slots")
Check(damageTemplate:FindFirstChild("DamageText", true).TextScaled, "template enables scaled billboard text")
Check(damageTemplate:FindFirstChild("UIStroke", true).StrokeSizingMode == roblox.Enum.StrokeSizingMode.ScaledSize, "template uses scaled strokes")
manager:CreateHitImpact(Vector3.zero, 7, false, 1)
Check(manager.damagePool[1].label.Text == "-7" and not manager.damagePool[2].active, "nonlethal hit emits exactly one damage label")
Check(sounds[#sounds] == "AnimalHit", "nonlethal sound preserved")
manager:ClearAttacks()
manager:CreateHitImpact(Vector3.zero, 7, true, 1)
Check(manager.damagePool[1].label.Text == "Cooked" and not manager.damagePool[2].active, "lethal hit emits only knockout label")
Check(manager.damagePool[1].scale.Scale == 1.2, "knockout keeps emphasis scale")
Check(sounds[#sounds] == "AnimalCooked", "knockout sound preserved")
manager:ClearAttacks()
manager:PlayZapEffects(2, Vector3.zero, {
	{ x = 8, y = 0, z = 0, damage = 2, isCooked = false },
	{ x = 12, y = 0, z = 0, damage = 9, isCooked = true },
})
Check(manager.damagePool[1].label.Text == "-2" and manager.damagePool[2].label.Text == "Cooked" and not manager.damagePool[3].active, "mixed chain emits one appropriate label per target")
manager:ClearAttacks()
manager:SpawnFloatingText(Vector3.zero, "Pickup", nil, nil, 1.05)
Check(manager.damagePool[1].label.Text == "Pickup" and manager.damagePool[1].scale.Scale == 1.05, "pickup interface retains text and scale")
manager:ClearAttacks()
local targets = { { x = 8, y = 0, z = 0, damage = 1, isCooked = false }, { x = 12, y = 0, z = 0, damage = 1, isCooked = false } }
manager:PlayZapEffects(2, Vector3.zero, targets)
Check(#manager.activeArcs == 2, "chain creates complete arcs")
local first, second = manager.activeArcs[1], manager.activeArcs[2]
Check(first.followPlayer and not second.followPlayer, "only first chain link follows player")
local chainCF = second.slots[1].model:FindFirstChild("ArcCore").CFrame
root.Position = Vector3.new(3, 0, 0)
muzzle.WorldPosition = Vector3.new(3, 2.25, -1.925)
manager:UpdateAttacks(0.04)
local core = first.slots[1].model:FindFirstChild("ArcCore")
local liveOrigin = muzzle.WorldPosition
local nextPoint = liveOrigin:Lerp(first.to, 1 / #first.slots) + first.offsets[1]
Check(
	(core.CFrame.Position - (liveOrigin + nextPoint) / 2).Magnitude < 0.001 and math.abs(core.Size.Z - (nextPoint - liveOrigin).Magnitude) < 0.001,
	"moving weapon muzzle remains connected to first segment"
)
Check(second.slots[1].model:FindFirstChild("ArcCore").CFrame == chainCF, "chain target endpoints stay fixed")
for _, pool in { manager.muzzlePool, manager.hitPool } do
	for _, slot in pool do
		for _, node in slot.model:GetDescendants() do
			if node.Name == "Flash" or node.Name == "ShockRing" then
				Check(node.Transparency == 1, "no flash geometry")
			end
			if node.Name == "BodyFlash" or node.Name == "DarkSmoke" then
				Check(node.particles == 0, "no flash or smoke particles")
			end
		end
	end
end
manager:UpdateAttacks(0.081)
Check(#manager.activeArcs == 0, "arc expires by 0.12 seconds")
manager:ClearAttacks()
manager:PlayZapEffects(3, Vector3.zero, {
	{ x = 8, y = 0, z = 0, damage = 4, isCooked = false },
	{ x = 0, y = 0, z = 8, damage = 5, isCooked = false },
})
Check(#manager.activeArcs == 2, "cone creates one arc per target")
Check(manager.activeArcs[1].followPlayer and manager.activeArcs[2].followPlayer, "cone arcs all start at the muzzle")
Check((manager.activeArcs[1].from - muzzle.WorldPosition).Magnitude < 0.001 and (manager.activeArcs[2].from - muzzle.WorldPosition).Magnitude < 0.001, "cone arcs do not chain between targets")
Check(manager.damagePool[1].label.Text == "-4" and manager.damagePool[2].label.Text == "-5", "cone shows each target damage")
manager:ClearAttacks()
for _, slot in manager.arcPool do
	Hidden(slot)
end
for _ = 1, 4 do
	manager:CreateLightningSegment(Vector3.zero, Vector3.new(12, 0, 0), Color3.new(0, 1, 1), 5)
end
Check(#manager.activeArcs == 3, "pool reclaims oldest whole arc")
local used = {}
for _, arc in manager.activeArcs do
	Check(#arc.slots == 6, "every surviving arc is complete")
	for _, slot in arc.slots do
		Check(not used[slot], "arcs never share segments")
		used[slot] = true
	end
end
-- Reuse a label before its old delay fires. The old timer must not hide the new label or anchor.
manager:ClearAttacks()
manager:SpawnFloatingText(Vector3.zero, "old")
local labelSlot = manager.damagePool[1]
local oldTween = createdTweens[#createdTweens]
task.wait(0.3)
labelSlot.active = false -- force deterministic reuse of this one label
manager:SpawnFloatingText(Vector3.one, "new")
Check(oldTween.cancelled, "reuse cancels old label tween")
local anchor = labelSlot.gui.Adornee
task.wait(0.42)
Check(labelSlot.active and labelSlot.gui.Enabled and labelSlot.gui.Adornee == anchor, "old delayed cleanup cannot hide reused label")
-- Reuse a flight slot while its coroutine is suspended.
manager:PlayDeliveryFlying(Vector3.zero, Vector3.one * 10, "chicken", "normal")
local flight = manager.roastPool[1]
local oldPlayback = flight.playback
for _, slot in manager.roastPool do
	slot.active = true
	slot.startedAt = math.huge
end
flight.startedAt = -1
manager:PlayDeliveryFlying(Vector3.one, Vector3.one * 20, "chicken", "golden")
Check(not oldPlayback.alive, "flight reuse cancels previous coroutine")
manager:PlayZapEffects(1, Vector3.zero, targets)
humanoid.Health = 0
humanoid.Died:Fire()
Check(#manager.activeArcs == 0, "death immediately clears attack")
for _, slot in manager.arcPool do
	Hidden(slot)
end
manager:PlayZapEffects(1, Vector3.zero, targets)
Check(#manager.activeArcs == 0, "dead character cannot spawn effects at stale coordinates")
humanoid.Health = 100
manager:PlayZapEffects(1, Vector3.zero, targets)
player.CharacterRemoving:Fire(character)
Check(#manager.activeArcs == 0, "character removal clears attack")
-- 武器旋转只改变预制枪口的位置，人物根部不动，电弧仍应跟随枪口。
manager:PlayZapEffects(1, Vector3.zero, targets)
muzzle.WorldPosition = Vector3.new(-4, 3, 2)
manager:UpdateAttacks(0.01)
local muzzleArc = manager.activeArcs[1]
local muzzleCore = muzzleArc.slots[1].model:FindFirstChild("ArcCore")
local muzzleNext = muzzle.WorldPosition:Lerp(muzzleArc.to, 1 / #muzzleArc.slots) + muzzleArc.offsets[1]
Check((muzzleCore.CFrame.Position - (muzzle.WorldPosition + muzzleNext) / 2).Magnitude < 0.001, "rotating gun follows attachment rather than character root")
Check(manager.muzzlePool[1].model.PrimaryPart.CFrame.Position == muzzle.WorldPosition, "muzzle sparks use preset attachment")
table.remove(character.children, table.find(character.children, weapon))
manager:UpdateAttacks(0.01)
Check(#manager.activeArcs == 0, "unequipping gun clears active effects")
manager:PlayZapEffects(1, Vector3.zero, targets)
Check(#manager.activeArcs == 0, "missing equipped gun never falls back to body position")
table.insert(character.children, weapon)
muzzle.ClassName = "Folder"
manager:PlayZapEffects(1, Vector3.zero, targets)
Check(#manager.activeArcs == 0, "invalid muzzle never spawns effects")
muzzle.ClassName = "Attachment"
-- 旧飘字定时器先走完，避免占用伤害字池。
task.wait(0.75)
local function ActiveLabelCount()
	local count = 0
	for _, slot in manager.pickupPool do
		if slot.active then
			count += 1
		end
	end
	return count
end
local function LabelWith(text)
	for _, slot in manager.pickupPool do
		if slot.active and slot.label.Text == text then
			return slot
		end
	end
	return nil
end
Check(ActiveLabelCount() == 0, "previous floating text has retired")
local soundsBefore = #sounds
manager:PlayOriginalRoastIntoBasket(Vector3.zero, "chicken", "normal", 1)
manager:PlayOriginalRoastIntoBasket(Vector3.zero, "chicken", "normal", 1)
manager:PlayOriginalRoastIntoBasket(Vector3.zero, "chicken", "normal", 1)
Check(ActiveLabelCount() == 1, "same species and quality occupy one row")
Check(LabelWith("Chicken x3 (+3.0 kg)") ~= nil, "same food accumulates count and total weight")
Check(#sounds - soundsBefore == 1, "simultaneous arrivals merge pickup sound without merging item feedback")
task.wait(0.1)
manager:PlayOriginalRoastIntoBasket(Vector3.zero, "chicken", "normal", 1)
Check(#sounds - soundsBefore == 2, "arrival after 80 ms plays a new sound")
Check(LabelWith("Chicken x4 (+4.0 kg)") ~= nil, "sound merging preserves all four item notices")
Check(#manager.pickupPool == 2, "pickup rows have their own two-slot pool")
table.remove(character.children, table.find(character.children, weapon))
for _ = 1, 3 do
	manager:UpdateAttacks(0.016)
end
local pickupSlot = LabelWith("Chicken x4 (+4.0 kg)")
Check(pickupSlot ~= nil and pickupSlot.gui.Enabled, "pickup remains visible across frames without an equipped gun")
table.insert(character.children, weapon)
for i = 1, 25 do
	manager:SpawnFloatingText(Vector3.zero, "-" .. i)
end
manager:ClearAttacks()
Check(LabelWith("Chicken x4 (+4.0 kg)") == pickupSlot and pickupSlot.gui.Enabled, "damage pool exhaustion and attack cleanup preserve pickup rows")
task.wait(0.7)
Check(ActiveLabelCount() == 0, "merged pickup row retires after its hold")

manager:PlayOriginalRoastIntoBasket(Vector3.zero, "chicken", "normal", 1)
task.wait(0.2)
manager:PlayOriginalRoastIntoBasket(Vector3.zero, "chicken", "golden", 2)
manager:PlayOriginalRoastIntoBasket(Vector3.zero, "chicken", "rainbow", 4)
local normalText = "Chicken x1 (+1.0 kg)"
local goldenText = "Chicken x1 (+2.0 kg)"
local rainbowText = "Chicken x1 (+4.0 kg)"
local normalSlot = LabelWith(normalText)
local goldenSlot = LabelWith(goldenText)
Check(normalSlot ~= nil and goldenSlot ~= nil and LabelWith(rainbowText) == nil, "two qualities fill both rows and the third waits")
Check(ActiveLabelCount() == 2 and #manager.pickupQueue == 1, "only two pickup rows are visible")
local lowerY = normalSlot.gui.StudsOffset.Y
local upperY = goldenSlot.gui.StudsOffset.Y
local sharedAdornee = goldenSlot.gui.Adornee
Check(upperY > lowerY and normalSlot.gui.Adornee == sharedAdornee, "rows stack above one shared anchor")
task.wait(0.5)
local rainbowSlot = LabelWith(rainbowText)
local goldenStill = LabelWith(goldenText)
Check(LabelWith(normalText) == nil and rainbowSlot ~= nil and goldenStill ~= nil, "queued kind fills the freed row")
Check(math.abs(rainbowSlot.gui.StudsOffset.Y - lowerY) < 0.001, "replacement keeps the freed row")
Check(goldenStill.gui.Adornee == sharedAdornee and math.abs(goldenStill.gui.StudsOffset.Y - upperY) < 0.001, "the other row stays put")
Check(#manager.pickupQueue == 0 and ActiveLabelCount() == 2, "queue advances into the empty row only")
manager:PlayOriginalRoastIntoBasket(Vector3.zero, "chicken", "giant", 5)
Check(#manager.pickupQueue == 1 and LabelWith("Chicken x1 (+5.0 kg)") == nil, "a fourth kind waits behind the two rows")
player.CharacterRemoving:Fire(character)
Check(ActiveLabelCount() == 0 and #manager.pickupQueue == 0, "character removal clears pickup rows and queue")
-- 服务端确认成功后，真实飞行结束才响；没有筐口时走一次兜底。
local function ReserveFlight()
	local source = Node("Model", "SourceRoast")
	local clone = Node("Model", "FlightRoast")
	function clone:GetPivot() return CFrame.identity end
	table.insert(manager.roastReserves, {
		source = source, model = clone, position = Vector3.zero, expiresAt = os.clock() + 5,
	})
	return clone
end
task.wait(0.1)
local flightClone = ReserveFlight()
local beforeArrival = #sounds
manager:PlayOriginalRoastIntoBasket(Vector3.zero, "chicken", "normal", 1)
Check(#sounds == beforeArrival, "confirmed pickup waits for flight arrival before sounding")
for _ = 1, 40 do
	if flightClone.destroyed then break end
	task.wait(0.05)
end
Check(#sounds == beforeArrival + 1 and flightClone.destroyed, "normal arrival sounds exactly once and destroys flight clone")
manager:ClearPickupNotices()
task.wait(0.1)
flightClone = ReserveFlight()
player.Character = nil
beforeArrival = #sounds
manager:PlayOriginalRoastIntoBasket(Vector3.zero, "chicken", "normal", 1)
task.wait(0.1)
Check(#sounds == beforeArrival + 1 and flightClone.destroyed, "missing character/basket anchor emits one confirmed-success fallback")
task.wait(Config.PickupFlightDuration + 0.1)
Check(#sounds == beforeArrival + 1, "fallback never emits a second arrival sound")
player.Character = character
manager:Destroy()
Check(render:Count() == 0 and humanoid.Died:Count() == 0, "destroy disconnects frame and death updates")
task.wait(0.75)
Check(manager.poolFolder.destroyed, "destroy cancels pending work and destroys pool")
print("AttackVfxRegression: " .. checks .. " checks passed")
