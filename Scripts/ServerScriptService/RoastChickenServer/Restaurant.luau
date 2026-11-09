local catalog = require(game.ReplicatedStorage.RoastChickenCatalog)
local prices = catalog.restaurantPrices
local duration = {3.4,1.9,1.5}
local customerScale = 1.35
local customerHeight = Vector3.new(0,1.48*customerScale,0)
local capacity = 24

return function(map,piece,onSale)
 local restaurant = map.Restaurant
 local queueHead = restaurant.QueueHead.Position + customerHeight
 local entrance = restaurant.QueueStart.Position + customerHeight
 local exit = restaurant.QueueExit.Position + customerHeight
 local queueDirection = (queueHead-entrance).Unit
 local folder = Instance.new("Folder",restaurant)
 folder.Name = "Customers"
 local stock, queue, lanes, leaving = {}, {}, {}, {}
 local nextArrival = 0
 local level = 1
 local serial = 0
 local palette = {"45A5E5","ED6A72","AB7FE4","55BD90","FFA84D"}
 local counterLabel = restaurant.StockSign.BillboardGui.TextLabel

 local function makeCustomer()
  serial += 1
  local model = Instance.new("Model")
  model.Name = "顾客 "..serial
  local shirt = palette[(serial-1)%#palette+1]
  local skin = serial%2==0 and "E4AA79" or "FFD0A5"
  local function add(name,x,y,z,sx,sy,sz,color,ball)
   return piece(model,name,Vector3.new(sx,sy,sz),CFrame.new(x,y,z),color,ball)
  end
  model.PrimaryPart = add("Shirt",0,0,0,1.13,1.33,0.76,shirt)
  add("Head",0,1.08,0,0.92,0.92,0.89,skin)
  add("Hair",0,1.4,0.05,0.94,0.48,0.88,"4F3432")
  for _, side in {-1,1} do
   add("Eye",side*0.17,1.13,-0.4,0.1,0.14,0.08,"312631",true)
   add("Arm",side*0.73,0.04,0,0.34,1.11,0.37,shirt)
   add("Leg",side*0.29,-1.04,0,0.48,0.85,0.62,"42567A")
  end
  model:ScaleTo(customerScale)
  local pos = entrance
  model:PivotTo(CFrame.new(pos))
  model.Parent = folder
  return {model=model,pos=pos,phase=serial}
 end

 local function move(customer,target,dt,now)
  local offset = target-customer.pos
  local distance = offset.Magnitude
  if distance <= 0.06 then return true end
  local step = math.min(distance,dt*9)
  customer.pos += offset.Unit*step
  local bob = math.sin(now*16+customer.phase)*0.11
  local visual = customer.pos+Vector3.yAxis*bob
  customer.model:PivotTo(CFrame.lookAt(visual,visual+offset.Unit))
  return step == distance
 end

 local function updateSign()
  counterLabel.Text = ("备餐架  %d / %d\n营业柜台  %d"):format(#stock,capacity,level == 3 and 2 or 1)
  restaurant.Lane2Lamp.Color = Color3.fromHex(level == 3 and "7CE777" or "99635A")
  for i=1,6 do restaurant["DisplayFood"..i].Transparency = i <= #stock and 0 or 1 end
 end
 updateSign()

 local function deposit(player, basket)
  local count = math.min(#basket,capacity-#stock)
  for _=1,count do
   table.insert(stock,{owner=player,variant=table.remove(basket,1)})
  end
  if count > 0 then updateSign() end
  return count
 end

 local function upgrade(balance)
  local cost = prices[level]
  if not cost or balance < cost then return nil,cost end
  level += 1
  updateSign()
  return cost
 end

 local function update(now,dt)
  if #queue < 4 and now >= nextArrival then
   table.insert(queue,makeCustomer())
   nextArrival = now+1.35
  end
  for i,customer in queue do
   move(customer,queueHead-queueDirection*((i-1)*2.18),dt,now)
  end
  for i=#leaving,1,-1 do
   local customer = leaving[i]
   if not customer.inExitLane then
    customer.inExitLane = move(customer,Vector3.new(exit.X,exit.Y,customer.pos.Z),dt,now)
   elseif move(customer,exit,dt,now) then
    customer.model:Destroy()
    table.remove(leaving,i)
   end
  end
  local count = level == 3 and 2 or 1
  for i=1,count do
   local customer = lanes[i]
   if customer then
    local counter = restaurant["ServiceCounter"..i].Position
    if move(customer,Vector3.new(counter.X,queueHead.Y,counter.Z)-queueDirection*1.75,dt,now) then
     customer.finish = customer.finish or now+duration[level]
     if now >= customer.finish then
      local entry = table.remove(stock,1)
      if entry then
       onSale(entry.owner,catalog[entry.variant])
       updateSign()
      end
      table.insert(leaving,customer)
      lanes[i] = nil
     end
    end
   elseif #stock > (lanes[3-i] and 1 or 0) and queue[1] and (queue[1].pos-queueHead).Magnitude <= 0.55 then
    lanes[i] = table.remove(queue,1)
   end
  end
 end

 return {
  deposit=deposit,
  upgrade=upgrade,
  update=update,
  level=function() return level end,
  count=function() return #stock end,
  capacity=capacity,
 }
end
