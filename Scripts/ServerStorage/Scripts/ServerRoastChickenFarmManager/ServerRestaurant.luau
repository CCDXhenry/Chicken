-- 服务端餐厅经营系统：负责顾客生成、排队取餐、备餐架库存管理与柜台升级
--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local catalog = require(sharedScripts:WaitForChild("RoastChickenCatalog"))
local GameTexts = require(sharedScripts:WaitForChild("GameTexts"))

local FarmConfig = require(sharedScripts:WaitForChild("FarmConfig"))
local ServerFarmTypes = require(script.Parent.Parent:WaitForChild("ServerFarmTypes"))
local LifecycleTool = require(sharedScripts:WaitForChild("LifecycleTool"))
local ServerFarmSceneTool = require(script.Parent:WaitForChild("ServerFarmSceneTool"))
local ServerCreatureBuilder = require(script.Parent:WaitForChild("ServerCreatureBuilder"))
type PieceFunc = ServerCreatureBuilder.PieceFunc

export type SaleCallback = (player: Player, creatureInfo: catalog.CreatureConfig) -> ()
export type RestaurantSystem = ServerFarmTypes.RestaurantSystem
type CustomerData = ServerFarmTypes.CustomerInfo
local prices = catalog.restaurantPrices
local duration = FarmConfig.RestaurantDurations
local customerScale = 1.35
local customerHeight = Vector3.new(0, 1.48 * customerScale, 0)
local capacity = FarmConfig.RestaurantCapacity
local palette = { "45A5E5", "ED6A72", "AB7FE4", "55BD90", "FFA84D" }

local ServerRestaurant = {}

function ServerRestaurant.Init(
	map: Folder,
	piece: PieceFunc,
	onSale: SaleCallback,
	info: ServerFarmTypes.RestaurantInfo,
	scope: LifecycleTool.Lifecycle
): RestaurantSystem
	local restaurant = map:WaitForChild("Restaurant") :: Folder
	local queueHeadPart = restaurant:WaitForChild("QueueHead") :: BasePart
	local queueStartPart = restaurant:WaitForChild("QueueStart") :: BasePart
	local queueExitPart = restaurant:WaitForChild("QueueExit") :: BasePart
	local stockSignPart = restaurant:WaitForChild("StockSign") :: BasePart
	local lane2LampPart = restaurant:WaitForChild("Lane2Lamp") :: BasePart

	local queueHead = queueHeadPart.Position + customerHeight
	local entrance = queueStartPart.Position + customerHeight
	local exit = queueExitPart.Position + customerHeight
	local queueDirection = (queueHead - entrance).Unit

	local folder = Instance.new("Folder")
	folder.Name = "Customers"
	folder.Parent = restaurant

	scope:Own(folder)
	ServerFarmSceneTool.BindSign(stockSignPart, "RestaurantSignGui")

	local function CreateCustomer(): CustomerData
		info.serial += 1
		local model = Instance.new("Model")
		model.Name = "Customer" .. info.serial
		local shirt = palette[(info.serial - 1) % #palette + 1]
		local skin = if info.serial % 2 == 0 then "E4AA79" else "FFD0A5"

		local function CreateCustomerPart(
			name: string,
			x: number,
			y: number,
			z: number,
			sx: number,
			sy: number,
			sz: number,
			color: string,
			ball: boolean?
		): Part
			return piece(model, name, Vector3.new(sx, sy, sz), CFrame.new(x, y, z), color, ball)
		end

		model.PrimaryPart = CreateCustomerPart("Shirt", 0, 0, 0, 1.13, 1.33, 0.76, shirt)
		CreateCustomerPart("Head", 0, 1.08, 0, 0.92, 0.92, 0.89, skin)
		CreateCustomerPart("Hair", 0, 1.4, 0.05, 0.94, 0.48, 0.88, "4F3432")
		for _, side in { -1, 1 } do
			CreateCustomerPart("Eye", side * 0.17, 1.13, -0.4, 0.1, 0.14, 0.08, "312631", true)
			CreateCustomerPart("Arm", side * 0.73, 0.04, 0, 0.34, 1.11, 0.37, shirt)
			CreateCustomerPart("Leg", side * 0.29, -1.04, 0, 0.48, 0.85, 0.62, "42567A")
		end

		model:ScaleTo(customerScale)
		local pos = entrance
		model:PivotTo(CFrame.new(pos))
		model.Parent = folder

		return { model = model, pos = pos, phase = info.serial }
	end

	local function MoveCustomer(customer: CustomerData, target: Vector3, dt: number, now: number): boolean
		local offset = target - customer.pos
		local distance = offset.Magnitude
		if distance <= FarmConfig.CustomerMoveThreshold then
			return true
		end
		local step = math.min(distance, dt * FarmConfig.CustomerSpeed)
		customer.pos += offset.Unit * step
		local bob = math.sin(now * 16 + customer.phase) * 0.11
		local visual = customer.pos + Vector3.yAxis * bob
		customer.model:PivotTo(CFrame.lookAt(visual, visual + offset.Unit))
		return step == distance
	end

	local function UpdateSign()
		ServerFarmSceneTool.SetSignText(
			stockSignPart,
			(GameTexts.Farm.RestaurantStock.source):format(#info.stock, capacity, if info.level == FarmConfig.MaximumRestaurantLevel then 2 else 1)
		)
		lane2LampPart.Color = Color3.fromHex(if info.level == FarmConfig.MaximumRestaurantLevel then "7CE777" else "99635A")
		for i = 1, 6 do
			local displayPart = restaurant:FindFirstChild("DisplayFood" .. i) :: BasePart?
			if displayPart then
				displayPart.Transparency = if i <= #info.stock then 0 else 1
			end
		end
	end

	UpdateSign()

	local function Deposit(player: Player, basket: { number }): number
		local count = math.min(#basket, capacity - #info.stock)
		for _ = 1, count do
			table.insert(info.stock, { owner = player, variant = table.remove(basket, 1) :: number })
		end
		if count > 0 then
			UpdateSign()
		end
		return count
	end

	local function Upgrade(balance: number): (number?, number?)
		local cost = prices[info.level]
		if not cost or balance < cost then
			return nil, cost
		end
		info.level += 1
		UpdateSign()
		return cost, nil
	end

	local function Update(now: number, dt: number)
		if #info.queue < FarmConfig.CustomerQueueCapacity and now >= info.nextArrival then
			table.insert(info.queue, CreateCustomer())
			info.nextArrival = now + FarmConfig.CustomerArrivalInterval
		end
		for i, customer in ipairs(info.queue) do
			MoveCustomer(customer, queueHead - queueDirection * ((i - 1) * FarmConfig.CustomerQueueSpacing), dt, now)
		end
		for i = #info.leaving, 1, -1 do
			local customer = info.leaving[i]
			if not customer.inExitLane then
				customer.inExitLane = MoveCustomer(customer, Vector3.new(exit.X, exit.Y, customer.pos.Z), dt, now)
			elseif MoveCustomer(customer, exit, dt, now) then
				customer.model:Destroy()
				table.remove(info.leaving, i)
			end
		end
		local activeLanes = if info.level == FarmConfig.MaximumRestaurantLevel then 2 else 1
		for i = 1, activeLanes do
			local customer = info.lanes[i]
			if customer then
				local counterPart = restaurant:FindFirstChild("ServiceCounter" .. i) :: BasePart
				local counter = counterPart.Position
				if MoveCustomer(customer, Vector3.new(counter.X, queueHead.Y, counter.Z) - queueDirection * FarmConfig.CounterApproachOffset, dt, now) then
					customer.finish = customer.finish or (now + duration[info.level])
					if now >= (customer.finish :: number) then
						local entry = table.remove(info.stock, 1)
						if entry then
							onSale(entry.owner, catalog.creatures[entry.variant])
							UpdateSign()
						end
						table.insert(info.leaving, customer)
						info.lanes[i] = nil
					end
				end
			elseif
				#info.stock > (if info.lanes[3 - i] then 1 else 0)
				and info.queue[1]
				and (info.queue[1].pos - queueHead).Magnitude <= FarmConfig.CustomerArrivalThreshold
			then
				local nextCustomer = table.remove(info.queue, 1)
				if nextCustomer then info.lanes[i] = nextCustomer end
			end
		end
	end

	return {
		Deposit = Deposit,
		Upgrade = Upgrade,
		Update = Update,
		GetLevel = function(): number
			return info.level
		end,
		GetCount = function(): number
			return #info.stock
		end,
		Destroy = function(): ()
			ServerFarmSceneTool.ClearSign(stockSignPart)
			folder:Destroy()
		end,
	}
end

return ServerRestaurant
