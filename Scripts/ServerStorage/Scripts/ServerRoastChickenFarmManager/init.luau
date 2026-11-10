-- 农场主管理器：统一初始化子系统、调度会话更新及清理玩家和场景资源
--!strict
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local sharedScripts = replicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local FarmConfig = require(sharedScripts:WaitForChild("FarmConfig"))
local LifecycleTool = require(sharedScripts:WaitForChild("LifecycleTool"))
local NetMsg = require(sharedScripts:WaitForChild("NetMsg"))
local catalog = require(sharedScripts:WaitForChild("RoastChickenCatalog"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))
local ServerGameInfo = require(script.Parent:WaitForChild("ServerGameInfo"))
local ServerFarmTypes = require(script.Parent:WaitForChild("ServerFarmTypes"))
local SceneTool = require(script:WaitForChild("ServerFarmSceneTool"))
local EggManager = require(script:WaitForChild("ServerEggManager"))
local AnimalManager = require(script:WaitForChild("ServerAnimalManager"))
local CombatManager = require(script:WaitForChild("ServerCombatManager"))
local InventoryManager = require(script:WaitForChild("ServerInventoryManager"))
local UpgradeManager = require(script:WaitForChild("ServerUpgradeManager"))
local ServerRestaurant = require(script:WaitForChild("ServerRestaurant"))
type FarmContext = ServerFarmTypes.FarmContext
type Lifecycle = LifecycleTool.Lifecycle
local ServerRoastChickenFarmManager = {}
ServerRoastChickenFarmManager.__index = ServerRoastChickenFarmManager
export type ServerRoastChickenFarmManager = typeof(setmetatable(
	{} :: { context: FarmContext?, scope: Lifecycle?, playerScopes: { [Player]: Lifecycle }, running: boolean },
	ServerRoastChickenFarmManager
))
local function SyncPlayerState(player: Player, info: ServerFarmTypes.PlayerFarmInfo): ()
	player:SetAttribute("FarmCash", info.cash)
	player:SetAttribute("FarmBasket", #info.items)
	player:SetAttribute("FarmZap", info.zap)
	player:SetAttribute("FarmCollect", info.collect)
end
local function SendFeedback(player: Player, message: string, kind: string?): ()
	NetMsg.FireNotifyFarmFeedback(player, message, kind)
end
local function GetRuntimeFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing:IsA("Folder"), "Invalid farm folder: " .. name)
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name, folder.Parent = name, parent
	return folder
end
function ServerRoastChickenFarmManager.Update(self: ServerRoastChickenFarmManager, now: number, dt: number): ()
	local context = self.context
	if not self.running or not context then
		return
	end
	ServerGameInfo.UpdateFarmInfo(function()
		EggManager.UpdateEggs(context, now)
		context.restaurant.Update(now, dt)
		local roots = InventoryManager.Update(context, now)
		AnimalManager.Update(context, now, dt, roots)
	end)
end
function ServerRoastChickenFarmManager.new(): ServerRoastChickenFarmManager
	return setmetatable({ running = false, playerScopes = {} }, ServerRoastChickenFarmManager)
end
function ServerRoastChickenFarmManager.Init(self: ServerRoastChickenFarmManager): ()
	if self.running then
		return
	end
	local map = workspace:WaitForChild("RoastChickenFarm")
	assert(map:IsA("Folder"), "RoastChickenFarm must be a Folder")
	local scope = LifecycleTool.new()
	local info = ServerGameInfo.InitFarmInfo()
	local liveFolder, roastFolder, eggFolder = GetRuntimeFolder(map, "LiveAnimals"), GetRuntimeFolder(map, "CookedFood"), GetRuntimeFolder(map, "Eggs")
	local nest = map:WaitForChild("Nest")
	local productionSign = nest:WaitForChild("ProductionSign") :: BasePart
	SceneTool.BindSign(productionSign, "NestSignGui")
	local function OnDishSold(player: Player, creatureInfo: catalog.CreatureConfig): ()
		local playerInfo = info.playerStates[player]
		if not playerInfo then
			return
		end
		playerInfo.cash += creatureInfo.value
		SyncPlayerState(player, playerInfo)
		SendFeedback(player, GameTexts.Farm.Sold.source:format(creatureInfo.food, creatureInfo.value), "sale")
	end
	local restaurant = ServerRestaurant.Init(map, SceneTool.CreatePiece, OnDishSold, info.restaurant, scope)
	self.context = {
		info = info,
		map = map,
		liveFolder = liveFolder,
		roastFolder = roastFolder,
		eggFolder = eggFolder,
		rng = Random.new(),
		scope = scope,
		restaurant = restaurant,
		nestSign = productionSign,
		SyncPlayerState = SyncPlayerState,
		SendFeedback = SendFeedback,
	}
	self.scope, self.running = scope, true
	local function OnPlayerAdded(player: Player): ()
		self:OnPlayerAdded(player)
	end
	local function OnPlayerRemoving(player: Player): ()
		self:OnPlayerRemoving(player)
	end
	local function OnFarmAction(player: Player, action: FarmConfig.FarmAction): ()
		self:OnFarmAction(player, action)
	end
	scope:Connect(players.PlayerAdded:Connect(OnPlayerAdded))
	scope:Connect(players.PlayerRemoving:Connect(OnPlayerRemoving))
	scope:Connect(NetMsg.ConnectRequestFarmAction(OnFarmAction))
	for _, player in players:GetPlayers() do
		self:OnPlayerAdded(player)
	end
	scope:Spawn(function()
		while self.running do
			local dt = math.min(task.wait(FarmConfig.UpdateInterval), FarmConfig.MaximumDeltaTime)
			self:Update(os.clock(), dt)
		end
	end)
end
function ServerRoastChickenFarmManager.OnPlayerAdded(self: ServerRoastChickenFarmManager, player: Player): ()
	local context = self.context
	if not context or self.playerScopes[player] then
		return
	end
	local scope = LifecycleTool.new()
	self.playerScopes[player] = scope
	local info = ServerGameInfo.InitPlayerFarmInfo(player)
	SyncPlayerState(player, info)
	local function OnCharacterAdded(character: Model): ()
		scope:Spawn(function()
			local rootPart = character:WaitForChild("HumanoidRootPart", FarmConfig.CharacterRootWait)
			if not rootPart or player.Character ~= character or not scope.alive then
				return
			end
			local spawnPart = context.map:FindFirstChild("FarmSpawn")
			if spawnPart and spawnPart:IsA("BasePart") then
				character:PivotTo(spawnPart.CFrame * CFrame.new(0, FarmConfig.SpawnHeight, 0))
			end
			SceneTool.UpdateBasketVisual(context, player, info)
		end)
	end
	scope:Connect(player.CharacterAdded:Connect(OnCharacterAdded))
	if player.Character then
		OnCharacterAdded(player.Character)
	end
end
function ServerRoastChickenFarmManager.OnPlayerRemoving(self: ServerRoastChickenFarmManager, player: Player): ()
	local scope = self.playerScopes[player]
	if scope then
		scope:Destroy()
		self.playerScopes[player] = nil
	end
	local character = player.Character
	local basket = if character then character:FindFirstChild("ChickenBasket") else nil
	if basket then
		basket:Destroy()
	end
	ServerGameInfo.RemovePlayerFarmInfo(player)
end
function ServerRoastChickenFarmManager.OnFarmAction(self: ServerRoastChickenFarmManager, player: Player, action: FarmConfig.FarmAction): ()
	local context = self.context
	if not context or not self.running then
		return
	end
	local info = context.info.playerStates[player]
	local rootPart = SceneTool.GetPlayerRoot(player)
	if not info or not rootPart or not FarmConfig.Actions[action] then
		return
	end
	local now = os.clock()
	if (info.cooldowns[action] or 0) > now then
		return
	end
	info.cooldowns[action] = now + (if action == "zap" then FarmConfig.ZapCooldown else FarmConfig.ActionCooldown)
	local flatDirection = SceneTool.FlatVector(rootPart.CFrame.LookVector)
	local direction = if flatDirection.Magnitude > 0 then flatDirection.Unit else Vector3.zAxis
	ServerGameInfo.UpdateFarmInfo(function()
		if action == "zap" then
			CombatManager.Zap(context, player, info, rootPart, direction)
		elseif action == "collect" then
			InventoryManager.Collect(context, player, info, rootPart, direction)
		else
			UpgradeManager.Purchase(context, player, info, rootPart, action)
		end
	end)
end
function ServerRoastChickenFarmManager.Destroy(self: ServerRoastChickenFarmManager): ()
	if not self.running then
		return
	end
	self.running = false
	for player in self.playerScopes do
		self:OnPlayerRemoving(player)
	end
	if self.scope then
		self.scope:Destroy()
		self.scope = nil
	end
	local context = self.context
	if context then
		SceneTool.ClearSign(context.nestSign)
		context.restaurant.Destroy()
		for model in context.info.flock do
			model:Destroy()
		end
		for model in context.info.roasts do
			model:Destroy()
		end
		for _, egg in context.info.eggs do
			egg.model:Destroy()
		end
	end
	self.context = nil
	ServerGameInfo.ResetFarmInfo()
end
return ServerRoastChickenFarmManager
