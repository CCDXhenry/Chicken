-- 物种切换请求回归：验证服务端从高阶切回首阶鸡、重复选择、非法物种和有蛋确认
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Config = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmEconomyConfig")
local Save = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmSaveData")
local Business = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmBusiness")
local Request = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmRequest")
local Texts = require("../../Scripts/ReplicatedStorage/Scripts/Shared/GameTexts")
local Format = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmNumberFormat")
local FarmConfig = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmConfig")
local Combat = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmCombatRules")
local Hatch = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmHatchRules")
local Lifecycle = require("../../Scripts/ReplicatedStorage/Scripts/Shared/LifecycleTool")

local checks = 0
local function Check(condition: boolean, message: string): ()
	assert(condition, message)
	checks += 1
end

local node = {}
function node:WaitForChild(name: string): any
	if name == "Scripts" or name == "Shared" or name == "ServerRoastChickenFarmManager" then
		return node
	end
	return name
end
function node:FindFirstChild(): any
	return nil
end
function node:IsA(): boolean
	return false
end

local modules: { [string]: any } = {
	FarmEconomyConfig = Config,
	FarmConfig = FarmConfig,
	FarmSaveData = Save,
	FarmBusiness = Business,
	FarmCombatRules = Combat,
	FarmHatchRules = Hatch,
	NetMsg = { FireNotifyFarmFeedback = function() end },
	FarmRequest = Request,
	LifecycleTool = Lifecycle,
	GameTexts = Texts,
	FarmNumberFormat = Format,
	ServerGameInfo = {
		GetPlayerInfo = function(): any
			return {}
		end,
		MarkPlayerInfoChanged = function() end,
	},
	ServerFarmSceneTool = {
		GetPlayerRoot = function(): any
			return nil
		end,
	},
	ServerCreatureBuilder = {},
	ServerPersonalFarmTypes = {},
	ServerPersonalFarmView = {
		SetOwnership = function() end,
		SetSign = function() end,
		ApplyQuality = function() end,
		UpdateQuality = function() end,
		ApplySpecies = function() end,
		Project = function() end,
	},
	FarmSoundTool = { Play = function() end },
	ServerFarmVillageTool = {},
	FarmVillageConfig = {},
}

local gameMock = {
	GetService = function(_self: any, name: string): any
		if name == "HttpService" then
			return {
				GenerateGUID = function(): string
					return "species-confirm"
				end,
			}
		end
		if name == "RunService" then
			return {
				IsStudio = function(): boolean
					return false
				end,
			}
		end
		return node
	end,
}

local environment = setmetatable({
	game = gameMock,
	script = { Parent = node },
	require = function(name: any): any
		local module = modules[tostring(name)]
		assert(module ~= nil, "missing module " .. tostring(name))
		return module
	end,
	workspace = node,
	setmetatable = setmetatable,
	getmetatable = getmetatable,
	os = os,
	next = next,
	pairs = pairs,
	ipairs = ipairs,
	type = type,
	typeof = typeof,
	tostring = tostring,
	tonumber = tonumber,
	error = error,
	assert = assert,
	pcall = pcall,
	table = table,
	math = math,
	string = string,
	select = select,
	rawget = rawget,
	rawset = rawset,
	print = print,
}, { __index = _G })

local source = fs.readFile("Scripts/ServerStorage/Scripts/ServerPersonalFarmManager.luau")
local loadedManager = luau.load(source, { environment = environment })()
local manager = loadedManager.new()
manager.running = true

local function NewPlayer(): any
	local attributes: { [string]: any } = {}
	return {
		SetAttribute = function(_self: any, name: string, value: any)
			attributes[name] = value
		end,
		GetAttribute = function(_self: any, name: string): any
			return attributes[name]
		end,
	}
end
local function UnlockAll(farm: any): ()
	farm.unlockedSpecies.rabbit = true
	farm.unlockedSpecies.sheep = true
	farm.unlockedSpecies.cow = true
	farm.unlockedSpecies.dragon = true
end
local function NewSession(selectedSpeciesId: string, withEgg: boolean): (any, any)
	local player = NewPlayer()
	local farm = Save.CreateDefault()
	UnlockAll(farm)
	farm.selectedSpeciesId = selectedSpeciesId
	local session = {
		owner = player,
		plot = {},
		map = {},
		scope = {},
		farm = farm,
		eggs = if withEgg then { { model = { Destroy = function() end } } } else {},
		animals = {},
		ground = {},
		nextEggAt = 0,
		cooldowns = {},
		frozen = false,
	}
	manager.sessions[player] = session
	return player, session
end
local function Select(player: any, speciesId: string): ()
	local ok, err = pcall(function()
		manager:OnCommand(player, { action = "selectSpecies", speciesId = speciesId })
	end)
	Check(ok, "selectSpecies " .. speciesId .. " raised: " .. tostring(err))
end

local rabbitPlayer, rabbitSession = NewSession("rabbit", false)
local rabbitCash = rabbitSession.farm.cash
Select(rabbitPlayer, "chicken")
Check(rabbitSession.farm.selectedSpeciesId == "chicken", "empty rabbit pasture switches back to chicken")
Check(rabbitSession.farm.cash == rabbitCash, "already unlocked chicken does not charge")
Check(rabbitPlayer:GetAttribute("FarmConfirmId") == nil, "empty switch does not ask for confirmation")

local dragonPlayer, dragonSession = NewSession("dragon", false)
Select(dragonPlayer, "chicken")
Check(dragonSession.farm.selectedSpeciesId == "chicken", "empty dragon pasture switches back to chicken")

local repeatPlayer, repeatSession = NewSession("chicken", false)
local repeatRevision = repeatSession.farm.revision
Select(repeatPlayer, "chicken")
Check(repeatSession.farm.selectedSpeciesId == "chicken", "selecting the current first tier stays on chicken")
Check(repeatSession.farm.revision == repeatRevision, "repeat selection does not revise the save")

local illegalPlayer, illegalSession = NewSession("chicken", false)
Select(illegalPlayer, "phoenix")
Check(illegalSession.farm.selectedSpeciesId == "chicken", "unknown species leaves the current selection")
Check(Request.Parse({ action = "selectSpecies", speciesId = "phoenix" }) == nil, "request parser rejects an unknown species")
Check(Request.Parse({ action = "selectSpecies", speciesId = "chicken" }) ~= nil, "request parser accepts chicken")

local occupiedPlayer, occupiedSession = NewSession("rabbit", true)
Select(occupiedPlayer, "chicken")
Check(occupiedSession.farm.selectedSpeciesId == "rabbit", "eggs stay until the species switch is confirmed")
Check(occupiedPlayer:GetAttribute("FarmConfirmId") == "species-confirm", "occupied switch stores a confirmation token")
Check(occupiedSession.confirmation ~= nil and occupiedSession.confirmation.speciesId == "chicken", "confirmation targets chicken")
Check(occupiedSession.confirmation.previousSpeciesId == "rabbit", "confirmation remembers the previous species")

print("SpeciesSwitchRegression passed:", checks, "checks; first tier, repeat, illegal and confirmation")
