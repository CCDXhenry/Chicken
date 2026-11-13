-- 战斗音效触发回归：加载真实客户端入口，验证前置条件、反馈去重及收集成功边界
--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3
local checks = 0
local function Check(value, message)
	assert(value, message)
	checks += 1
end
local function Noop() end
local signal = { Connect = function() return {} end }
local sounds, requests = {}, {}
local delayed = {}
local feedback, visual
local info = { ready = true, zap = 1, weaponLevel = 1 }
local modal, focused, canUse = false, false, true
local liveAnimals = {}
local root = { Position = Vector3.zero, IsA = function(_, class) return class == "BasePart" end }
local character = { FindFirstChild = function() return root end }
local player = { Character = character, CharacterRemoving = signal, GetAttribute = function() return "Plot01" end }
local services = {
	ContextActionService = { BindAction = Noop },
	UserInputService = { GetFocusedTextBox = function() return focused end },
	GuiService = { MenuIsOpen = false },
	Workspace = { CurrentCamera = { CFrame = roblox.CFrame.identity } },
	Players = { LocalPlayer = player },
}
local shared = { WaitForChild = function(_, name) return name end }
local scripts = { WaitForChild = function() return shared end }
services.ReplicatedStorage = { WaitForChild = function() return scripts end }
local vfx = { Init = Noop, ReserveNearbyRoasts = Noop }
local misses, hits, pickups = 0, 0, 0
function vfx:PlayZapMiss() misses += 1 end
local cancelled, corrections = 0, 0
function vfx:PlayZapEffects(_, _, targets)
	hits += 1
	local cancellations = {}
	for _, target in targets do cancellations[target.id] = function() cancelled += 1 end end
	return cancellations
end
function vfx:CreateHitImpact() corrections += 1 end
function vfx:PlayOriginalRoastIntoBasket() pickups += 1 end
local hud = { container = {}, Init = Noop, ShowMessage = Noop, ShowSaleNotice = Noop, ShowCapacityDenied = Noop }
for _, key in { "shopButton", "indexButton", "eggButton", "equipmentButton" } do hud[key] = { Activated = signal } end
local resolved = {}
local modules = {
 FarmScenePaths = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmScenePaths"),
	FarmZapPrediction = require("../../Scripts/ReplicatedStorage/Scripts/Client/FarmZapPrediction"),
	NetMsg = {
		ConnectNotifyFarmFeedback = function(callback) feedback = callback; return {} end,
		ConnectNotifyFarmVisual = function(callback) visual = callback; return {} end,
		FireRequestFarmCommand = function(command) table.insert(requests, command) end,
		FireRequestFarmAction = function(action) table.insert(requests, action) end,
	},
	FarmConfig = {},
	FarmEconomyConfig = { Weapons = { {} }, MaximumWeaponLevel = 10 },
	FarmCombatRules = { ResolveShot = function() return resolved end },
	LifecycleTool = { new = function() return { Connect = Noop, Delay = function(_, _, callback) table.insert(delayed, callback) end } end },
	ClientGameInfo = { InitFarmInfo = Noop, GetFarmInfo = function() return info end },
	RoastChickenHUDFrame = { new = function() return hud end },
	ClientFarmSpeciesManager = { new = function() return { Init = Noop } end },
	UIManager = { HasShowingWindow = function() return modal end },
	FarmSoundTool = { Play = function(name) table.insert(sounds, name) end },
	FarmVisualEffects = { new = function() return vfx end },
	ClientFarmToolbar = { new = function() return { Init = Noop, CanUse = function() return canUse end } end },
}
local managerType = luau.load(fs.readFile("Scripts/ReplicatedStorage/Scripts/Client/ClientRoastChickenFarmManager.luau"), {
	environment = {
		game = { GetService = function(_, name) return services[name] end },
		script = { Parent = shared }, Vector3 = Vector3, Enum = roblox.Enum,
		workspace = { FindFirstChild = function()
			return {FindFirstChild=function() return {FindFirstChild=function() return {FindFirstChild=function() return {GetChildren=function() return liveAnimals end} end} end} end}
		end },
		require = function(name) return assert(modules[name], name) end,
	},
})()
local manager = managerType.new()
manager:Init({})
for _, message in { "熟食 +1", "Cooked 1", "超重", "Capacity", "ItemTooHeavy", "CollectHint" } do feedback(message) end
Check(#sounds == 0, "text feedback cannot replay cooked, pickup or capacity sounds")
feedback("任意本地化容量提示", "capacity")
Check(#sounds == 1 and sounds[1] == "Warning", "structured capacity rejection plays exactly one warning")
feedback("金币不足")
Check(#sounds == 2 and sounds[2] == "Warning", "existing non-collection insufficient-funds warning remains")
table.clear(sounds)
Check(manager:TriggerAction("zap"), "legal empty shot accepted immediately")
Check(#sounds == 1 and sounds[1] == "Zap_T1" and misses == 1, "legal miss has one firing sound")
Check(#requests == 1 and #requests[1].targetIds == 0, "miss still sends empty-target request")
for _, block in { "equipment", "modal", "focus", "menu", "notReady", "root", "aim" } do
	local oldCamera = services.Workspace.CurrentCamera
	if block == "equipment" then canUse = false
	elseif block == "modal" then modal = true
	elseif block == "focus" then focused = true
	elseif block == "menu" then services.GuiService.MenuIsOpen = true
	elseif block == "notReady" then info.ready = false
	elseif block == "root" then player.Character = nil
	else services.Workspace.CurrentCamera = nil end
	local count = #sounds
	Check(not manager:TriggerAction("zap") and #sounds == count, block .. " prevents firing sound")
	canUse, modal, focused, services.GuiService.MenuIsOpen, info.ready = true, false, false, false, true
	player.Character = character
	services.Workspace.CurrentCamera = oldCamera
end
table.clear(sounds)
Check(manager:TriggerAction("collect") and #sounds == 0, "collection request does not play success sound")
feedback("空收集提示")
Check(#sounds == 0 and pickups == 0, "empty collection cannot reach pickup animation")
feedback("满筐", "capacity")
Check(#sounds == 1 and sounds[1] == "Warning" and pickups == 0, "full basket only warns")
visual({ kind = "pickup", speciesId = "chicken", weightKg = 1 })
Check(pickups == 1, "only confirmed pickup routes to arrival feedback")
feedback("熟食", nil)
Check(#sounds == 1, "late cooked feedback cannot replay predicted impact")
local animal = {PrimaryPart={Position=Vector3.new(0,0,-5)},IsA=function() return true end,
	GetAttribute=function(_,key) return if key=="EntityId" then "rabbit" elseif key=="Health" then 3 else nil end}
table.insert(liveAnimals, animal)
resolved = {{id="rabbit",damage=3}}
Check(manager:TriggerAction("zap"), "predicted kill sends request")
local shotId = requests[#requests].shotId
Check(hits == 1 and shotId > requests[1].shotId, "real client links predicted hit to increasing ID")
visual({kind="zapResult",shotId=shotId,accepted=false,targets={}})
Check(cancelled == 1 and corrections == 0, "real client cancels rejected death without replay")
manager:TriggerAction("zap")
shotId=requests[#requests].shotId
visual({kind="zapResult",shotId=shotId,accepted=true,targets={{id="rabbit",x=0,y=0,z=-5,damage=3,isCooked=true,remainingHealth=0}}})
Check(cancelled == 1 and corrections == 0, "matching kill ack does not duplicate sound or popup")
manager:TriggerAction("zap")
shotId=requests[#requests].shotId
visual({kind="zapResult",shotId=shotId,accepted=true,targets={{id="rabbit",x=0,y=0,z=-5,damage=1,isCooked=false,remainingHealth=2}}})
Check(cancelled == 2 and corrections == 1, "real client replaces mismatched death with actual damage")
visual({kind="zapResult",shotId=shotId,accepted=true,targets={{id="rabbit",x=0,y=0,z=-5,damage=1,isCooked=false,remainingHealth=2}}})
Check(corrections == 1, "duplicate ack cannot replay correction")
manager:TriggerAction("zap")
shotId=requests[#requests].shotId
delayed[#delayed]()
Check(cancelled == 3 and manager.zapPrediction.pending[shotId] == nil, "scheduled timeout clears corresponding shot")
visual({kind="zapResult",shotId=shotId,accepted=true,targets={{id="rabbit",x=0,y=0,z=-5,damage=3,isCooked=true}}})
Check(corrections == 1, "late result after timeout is ignored")
print("CombatSoundTriggerRegression: " .. checks .. " checks passed")
