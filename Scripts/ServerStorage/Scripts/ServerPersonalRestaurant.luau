-- 个人餐厅流程：调度整批搬运、玩家区域取放和顾客排队购买，金币仅在购买时结算
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Shared = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local Paths = require(Shared:WaitForChild("FarmScenePaths"))
local Config = require(Shared:WaitForChild("FarmRestaurantConfig"))
local Economy = require(Shared:WaitForChild("FarmEconomyConfig"))
local Business = require(Shared:WaitForChild("FarmBusiness"))
local Texts = require(Shared:WaitForChild("GameTexts"))
local Types = require(script.Parent:WaitForChild("ServerPersonalFarmTypes"))
local View = require(script.Parent:WaitForChild("ServerPersonalFarmView"))
local Packages = require(script.Parent:WaitForChild("ServerRestaurantPackageView"))
local Scene = require(script.Parent:WaitForChild("ServerRoastChickenFarmManager"):WaitForChild("ServerFarmSceneTool"))
type Session = Types.Session
type Actor = Types.RestaurantActor
type State = Types.RestaurantState
local Restaurant = {}

local function Anchor(session: Session, name: string): BasePart
	local part = Paths.Find(session.map, name)
	assert(part and part:IsA("BasePart"), "Missing restaurant anchor: " .. name)
	return part
end
local function CloneActor(session: Session, templateName: string, name: string, cf: CFrame, parent: Instance): Model
	local template = ServerStorage:WaitForChild("Models"):WaitForChild(templateName) :: Model
	local model = template:Clone()
	model.Name = name
	model:PivotTo(cf)
	View.SetOwnership(model, session)
	model.Parent = parent
	return model
end
local function Animate(model: Model, now: number, moving: boolean, packing: boolean): ()
	local pivot = model:GetPivot()
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and (part.Name == "Arm" or part.Name == "Leg") then
			local rest = part:GetAttribute("RestCFrame")
			if typeof(rest) == "CFrame" then
				local side = if rest.X < 0 then -1 else 1
				local angle = if packing and part.Name == "Arm" then -0.9 + math.sin(now * 8 + side) * 0.25 elseif moving then math.sin(now * 7) * side * 0.3 else 0
				part.CFrame = pivot * rest * CFrame.Angles(angle, 0, 0)
			end
		end
	end
end
-- 行走高度可以变化，朝向始终只绕世界 Y 轴旋转；同 XZ 的高度差不能令角色俯仰。
local function Upright(position: Vector3, direction: Vector3): CFrame
	local horizontal = Vector3.new(direction.X, 0, direction.Z)
	if horizontal.Magnitude <= Config.ArrivalDistance then horizontal = -Vector3.zAxis end
	local yaw = math.atan2(-horizontal.X, -horizontal.Z)
	return CFrame.new(position) * CFrame.Angles(0, yaw, 0)
end
local function Move(actor: Actor, destination: Vector3, speed: number, dt: number, now: number): boolean
	local current = actor.model:GetPivot()
	local position = current.Position
	local delta = destination - position
	local distance = delta.Magnitude
	local moving = distance > Config.ArrivalDistance
	local arrived = distance <= speed * dt + Config.ArrivalDistance
	local nextPosition = if arrived then destination else position + delta.Unit * speed * dt
	local horizontal = Vector3.new(delta.X, 0, delta.Z)
	local direction = if horizontal.Magnitude > Config.ArrivalDistance then horizontal else current.LookVector
	actor.model:PivotTo(Upright(nextPosition, direction))
	Animate(actor.model, now, moving, false)
	return arrived
end
local function UpdatePlayer(session: Session): ()
	local character = session.owner.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = Scene.GetPlayerRoot(session.owner)
	if not character or not root or not humanoid or humanoid.Health <= 0 then
		Business.ReturnPackages(session.farm, "player")
		if character then local held = character:FindFirstChild("CarriedPackages"); if held then held:Destroy() end end
		return
	end
	if Scene.IsInZone(root, Anchor(session, "CounterDropZone")) then Business.PlacePackages(session.farm, "player") end
	local existingHeld = character:FindFirstChild("CarriedPackages")
	local held: Instance
	if not existingHeld then
		local folder = Instance.new("Folder")
		folder.Name, folder.Parent = "CarriedPackages", character
		held = folder
	else held = existingHeld end
	Packages.Sync(held, #session.farm.playerCarry, root.CFrame * CFrame.new(0, -0.7, -1.6), session.owner.UserId, root)
	-- 角色携带标牌复用本地主人标牌协议。
	if #session.farm.playerCarry > 0 then
		View.SetSign(root, "WorkerSignGui", Texts.Farm.PackageCarried.source:format(#session.farm.playerCarry), session.owner.UserId, "Private")
	elseif root:GetAttribute("FarmSign") == "WorkerSignGui" then
		root:SetAttribute("FarmSign", nil); root:SetAttribute("FarmText", nil)
	end
end
local function UpdateWorkers(session: Session, state: State, now: number, dt: number): ()
	for index = 1, Economy.Restaurants[session.farm.restaurantLevel].workers do
		local key = tostring(index)
		local actor = state.workers[index]
		local home = Anchor(session, "WorkerSpot" .. index)
		if not actor then
			actor = { model = CloneActor(session, "FarmWorkerTemplate", "Worker" .. index, home.CFrame, state.folder), phase = "Idle" }
			state.workers[index] = actor
		end
		local target = home.Position
		if actor.phase == "Idle" and #session.farm.packed > 0 then actor.phase = "PickupApproach" end
		if actor.phase == "PickupApproach" or actor.phase == "DropApproach" or actor.phase == "ReturnApproach" then target = Anchor(session, "PackageApproachSpot").Position
		elseif actor.phase == "Pickup" then target = Anchor(session, "PackagePickupSpot").Position
		elseif actor.phase == "Drop" then target = Anchor(session, "CounterDropSpot").Position end
		local arrived = Move(actor, target, Config.WorkerSpeed, dt, now)
		if arrived then
			if actor.phase == "PickupApproach" then actor.phase = "Pickup"
			elseif actor.phase == "DropApproach" then actor.phase = "Drop"
			elseif actor.phase == "ReturnApproach" then actor.phase = "Return"
			elseif actor.phase == "Pickup" then
				actor.phase = if Business.TakePackages(session.farm, key) > 0 then "DropApproach" else "ReturnApproach"
			elseif actor.phase == "Drop" then Business.PlacePackages(session.farm, key); actor.phase = "Return"
			elseif actor.phase == "Return" then actor.phase = "Idle" end
			if actor.phase == "Idle" then
				actor.model:PivotTo(Upright(home.Position, home.CFrame.LookVector))
				Animate(actor.model, now, false, false)
			end
		end
		local count = #session.farm.workerCarry[key]
		-- NPC 代表盒随模型整体 PivotTo；数量变化时重新投影。
		Packages.Sync(actor.model, count, actor.model:GetPivot() * CFrame.new(0, 1.2, -1.2), session.owner.UserId, nil)
		local root = actor.model.PrimaryPart
		if root then
			View.SetSign(root, "WorkerSignGui", Texts.Farm[if actor.phase == "Idle" then "TransportIdle" elseif actor.phase == "Pickup" or actor.phase == "PickupApproach" then "TransportPickup" elseif actor.phase == "Drop" or actor.phase == "DropApproach" then "TransportDrop" else "TransportReturn"].source:format(index, count), session.owner.UserId)
		end
	end
end
local function UpdateCustomers(session: Session, state: State, now: number, dt: number): (number, number)
	state.arrivalElapsed += dt
	state.purchaseRemaining = math.max(0, state.purchaseRemaining - dt)
	if state.arrivalElapsed >= Config.ArrivalSeconds then
		state.arrivalElapsed %= Config.ArrivalSeconds
		if #state.customers < Config.CustomerLimit then
			state.customerSequence += 1
			table.insert(state.customers, { model = CloneActor(session, "FarmCustomerTemplate", "Customer" .. state.customerSequence, Anchor(session, "QueueStart").CFrame, state.folder), phase = "Queue" })
		end
	end
	local head, start = Anchor(session, "QueueHead").Position, Anchor(session, "QueueStart").Position
	local direction = (start - head).Unit
	local sold, income = 0, 0
	for index, customer in state.customers do
		local destination = head + direction * ((index - 1) * Config.QueueSpacing)
		local arrived = Move(customer, destination, Config.CustomerSpeed, dt, now)
		if index == 1 and arrived and state.purchaseRemaining == 0 then
			local cargo = Business.SellCounterOne(session.farm)
			if cargo then
				state.purchaseRemaining = Config.PurchaseSeconds
				sold, income = 1, cargo.saleValue
				customer.phase = "Exit"
				Packages.Sync(customer.model, 1, customer.model:GetPivot() * CFrame.new(0, 1.2, -1.2), session.owner.UserId, nil)
			end
		end
	end
	if state.customers[1] and state.customers[1].phase == "Exit" then local leaving = table.remove(state.customers, 1); if leaving then table.insert(state.leaving, leaving) end end
	for index = #state.leaving, 1, -1 do
		local customer = state.leaving[index]
		-- 先横向离开队伍，再走出口，避免逆向穿过排队顾客。
		local exit = Anchor(session, "QueueExit").Position
		local target = if customer.phase == "Exit" then Vector3.new(exit.X, head.Y, exit.Z) - direction * (start - head).Magnitude else exit
		if Move(customer, target, Config.CustomerSpeed, dt, now) then
			if customer.phase == "Exit" then customer.phase = "Leaving" else customer.model:Destroy(); table.remove(state.leaving, index) end
		end
	end
	return sold, income
end

function Restaurant.Init(session: Session, onChanged: () -> ()): ()
	Business.RestoreCarriedPackages(session.farm)
	local folder = Paths.EnsureRuntime(session.map, "RestaurantRuntime")
	for _, name in { "PackedDisplay", "CounterDisplay" } do
		local display = Instance.new("Folder")
		display.Name, display.Parent = name, folder
	end
	local packer = CloneActor(session, "FarmPackerTemplate", "Packer", Anchor(session, "PackerSpot").CFrame, folder)
	session.restaurant = { folder = folder, packer = packer, workers = {}, customers = {}, leaving = {}, arrivalElapsed = 0, purchaseRemaining = 0, customerSequence = 0 }
	local function OnCharacterRemoving(): ()
		-- 下一次在线更新前也能被既有自动保存识别。
		if Business.ReturnPackages(session.farm, "player") > 0 then onChanged() end
	end
	session.scope:Connect(session.owner.CharacterRemoving:Connect(OnCharacterRemoving))
end

-- 玩家必须主动发起拾取；服务端独立校验所属地块、角色状态和取货区域。
function Restaurant.TakePlayerPackages(session: Session): number
	if session.frozen or session.map:GetAttribute("OwnerUserId") ~= session.owner.UserId then return 0 end
	local character = session.owner.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = Scene.GetPlayerRoot(session.owner)
	if not root or not humanoid or humanoid.Health <= 0 then return 0 end
	if not Scene.IsInZone(root, Anchor(session, "PackagePickupZone")) then return 0 end
	return Business.TakePackages(session.farm, "player")
end
function Restaurant.Update(session: Session, now: number, dt: number): (number, number)
	local state = session.restaurant
	if not state then return 0, 0 end
	UpdatePlayer(session)
	UpdateWorkers(session, state, now, dt)
	local sold, income = UpdateCustomers(session, state, now, dt)
	local processing = session.farm.kitchen[1]
	local active = processing ~= nil and processing.state == "Processing"
	Animate(state.packer, now, false, active)
	if state.packer.PrimaryPart then
		View.SetSign(state.packer.PrimaryPart, "WorkerSignGui", if active then Texts.Farm.PackerWorking.source:format(math.ceil(processing.remainingSeconds)) else Texts.Farm.PackerIdle.source, session.owner.UserId)
	end
	Packages.Sync(state.folder:WaitForChild("PackedDisplay"), #session.farm.packed, Anchor(session, "PackedDisplay").CFrame, session.owner.UserId, nil)
	Packages.Sync(state.folder:WaitForChild("CounterDisplay"), #session.farm.counter, Anchor(session, "CounterDisplay").CFrame, session.owner.UserId, nil)
	View.SetSign(Anchor(session, "PackedDisplay"), "WorkerSignGui", Texts.Farm.PackagesReady.source:format(#session.farm.packed), session.owner.UserId)
	View.SetSign(Anchor(session, "CounterDisplay"), "WorkerSignGui", Texts.Farm.PackagesCounter.source:format(#session.farm.counter, #state.customers), session.owner.UserId)
	return sold, income
end
return Restaurant
