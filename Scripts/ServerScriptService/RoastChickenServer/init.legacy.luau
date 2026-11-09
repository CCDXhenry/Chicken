local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local remote = game.ReplicatedStorage:WaitForChild("RoastChickenAction")
local map = workspace:WaitForChild("RoastChickenFarm")
local rng = Random.new()
local capacity = 6
local catalog = require(game.ReplicatedStorage.RoastChickenCatalog)
local buildCreature = require(script.Creatures)
local prices = {60,180}
local collectLimits = {1,3,6}
local state, flock, roasts = {}, {}, {}
local liveFolder = Instance.new("Folder",map)
liveFolder.Name = "LiveAnimals"
local roastFolder = Instance.new("Folder",map)
roastFolder.Name = "CookedFood"

local function flat(v) return Vector3.new(v.X,0,v.Z) end
local function piece(parent, name, size, cf, hex, ball)
 local p = Instance.new("Part")
 p.Name = name
 p.Size = size
 p.CFrame = cf
 p.Color = Color3.fromHex(hex)
 p.Shape = ball and Enum.PartType.Ball or Enum.PartType.Block
 p.Anchored = true
 p.CanCollide = false
 p.CanTouch = false
 p.CanQuery = false
 p.Parent = parent
 return p
end

local function createHealthLabel(model)
 local bounds, size = model:GetBoundingBox()
 local gui = Instance.new("BillboardGui")
 gui.Name = "AnimalHealth"
 gui.Size = UDim2.fromOffset(58,23)
 gui.StudsOffsetWorldSpace = Vector3.yAxis*(bounds.Position.Y+size.Y/2-model.PrimaryPart.Position.Y+0.25)
 gui.MaxDistance = 19
 gui.Parent = model.PrimaryPart
 local label = Instance.new("TextLabel")
 label.Size = UDim2.fromScale(1,1)
 label.TextColor3 = Color3.fromHex("FFF1D0")
 label.Font = Enum.Font.GothamBold
 label.TextSize = 13
 label.Parent = gui
 Instance.new("UICorner",label).CornerRadius = UDim.new(0,7)
 return label
end

local function setHealth(model, animal, health)
 animal.health = health
 model:SetAttribute("Health",health)
 animal.healthLabel.Text = ("%d / %d"):format(health,animal.maxHealth)
 animal.healthLabel.BackgroundColor3 = Color3.fromHex(health < animal.maxHealth and "A93C50" or "3D2443")
end

local function spawnAnimal(center, variant)
 local angle = rng:NextNumber(0,2*math.pi)
 local dir = Vector3.new(math.cos(angle),0,math.sin(angle))
 local pos = center
 local model = buildCreature(variant,false,piece)
 model:SetAttribute("Species",catalog[variant].name)
 model:PivotTo(CFrame.lookAt(pos+Vector3.yAxis,pos+Vector3.yAxis+dir))
 local maxHealth = catalog[variant].health
 local animal = {center=center,pos=pos,dir=dir,turn=0,phase=angle,variant=variant,maxHealth=maxHealth,healthLabel=createHealthLabel(model)}
 model:SetAttribute("MaxHealth",maxHealth)
 setHealth(model,animal,maxHealth)
 flock[model] = animal
 model.Parent = liveFolder
end


local eggs = {}
local eggFolder = Instance.new("Folder",map)
eggFolder.Name = "Eggs"
local nestLevel = 1
local nextEgg = 0
local nestLabel = map.Nest.ProductionSign.BillboardGui.TextLabel

local function makeEgg(now, variant)
 local info = catalog[variant]
 local landing = Vector3.new(rng:NextNumber(-11,11),0,rng:NextNumber(-10,6))
 local origin = map.Nest.Chute.Position
 local size = 1.22 + variant*0.13
 local egg = Instance.new("Model")
 egg.Name = info.egg
 egg:SetAttribute("Species",info.name)
 local shell = piece(egg,"Shell",Vector3.new(size,size*1.28,size),CFrame.new(0,0,0),info.shell,true)
 egg.PrimaryPart = shell
 for i=1,5 do
  local angle = i*math.pi*2/5
  local x,z = math.cos(angle),math.sin(angle)
  local spot = CFrame.lookAt(Vector3.new(x*size*0.46,0.07+0.15*(i%2),z*size*0.46),Vector3.new(x,0.07+0.15*(i%2),z))
  piece(egg,"ShellSpot",Vector3.new(size*0.3,size*0.25,size*0.1),spot,info.spot,true)
 end
 local gui = Instance.new("BillboardGui",shell)
 gui.Size = UDim2.fromOffset(126,46)
 gui.StudsOffset = Vector3.new(0,size*0.82+0.35,0)
 gui.MaxDistance = 37
 gui.Enabled = false
 local label = Instance.new("TextLabel",gui)
 label.Size = UDim2.fromScale(1,1)
 label.BackgroundColor3 = Color3.fromHex("613F86")
 label.TextColor3 = Color3.fromHex("FFF8DC")
 label.Font = Enum.Font.GothamBlack
 label.TextSize = 16
 local corner = Instance.new("UICorner",label)
 corner.CornerRadius = UDim.new(0,10)
 local stroke = Instance.new("UIStroke",label)
 stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
 stroke.Color = Color3.fromHex("FFEEAD")
 stroke.Thickness = 2
 egg:PivotTo(CFrame.new(origin))
 egg.Parent = eggFolder
 return {
  model=egg,label=label,origin=origin,landing=landing,variant=variant,
  started=now,landAt=now+1.15,finish=now+1.15+info.hatch,height=size*0.64,
 }
end

local function updateEggs(now)
 local population = #eggs
 for _ in flock do population += 1 end
 local info = catalog[nestLevel]
 if population < 28 and now >= nextEgg then
  table.insert(eggs,makeEgg(now,nestLevel))
  nextEgg = now+info.interval
 end
 local nestText = population >= 28 and "场地已满 · 等待空位" or ("下颗蛋 %d 秒"):format(math.max(0,math.ceil(nextEgg-now)))
 local description = ("产蛋窝 Lv.%d · %s\n%s"):format(nestLevel,info.egg,nestText)
 if nestLabel.Text ~= description then nestLabel.Text = description end
 for i=#eggs,1,-1 do
  local egg = eggs[i]
  local ground = egg.landing+Vector3.yAxis*egg.height
  if now < egg.landAt then
   local t = (now-egg.started)/(egg.landAt-egg.started)
   local pos = egg.origin:Lerp(ground,t)+Vector3.yAxis*(math.sin(math.pi*t)*6)
   egg.model:PivotTo(CFrame.new(pos)*CFrame.Angles(0,t*3,t*math.pi*2))
  elseif now >= egg.finish then
   spawnAnimal(egg.landing,egg.variant)
   egg.model:Destroy()
   table.remove(eggs,i)
  else
   local seconds = math.ceil(egg.finish-now)
   if seconds ~= egg.seconds then
    egg.seconds = seconds
    egg.model:PivotTo(CFrame.new(ground))
    egg.label.Parent.Enabled = true
    egg.label.Text = ("%s\n孵化 %d 秒"):format(catalog[egg.variant].egg,seconds)
   end
  end
 end
end

local function tell(player, message, kind)
 remote:FireClient(player,message,kind)
end

local restaurant = require(script.Restaurant)(map,piece,function(player,info)
 local s = state[player]
 if s then
  s.cash += info.value
  player:SetAttribute("FarmCash",s.cash)
  tell(player,"顾客买走"..info.food.." · +"..info.value.." 金币","sale")
 end
end)

local function basket(player,s)
 local character = player.Character
 local root = character and character:FindFirstChild("HumanoidRootPart")
 if not root then return end
 local model = character:FindFirstChild("ChickenBasket")
 if not model and #s.items > 0 then
  model = Instance.new("Model")
  model.Name = "ChickenBasket"
  model.Parent = character
  local function attach(name,size,offset,hex,ball)
   local p = piece(model,name,size,root.CFrame*CFrame.new(offset),hex,ball)
   p.Massless = true
   p.Anchored = false
   local weld = Instance.new("WeldConstraint",p)
   weld.Part0, weld.Part1 = root,p
   return p
  end
  attach("Basket",Vector3.new(1.85,0.85,1.05),Vector3.new(0,-0.1,1),"B57436")
  for _, y in {-0.36,-0.1,0.16,0.36} do
   attach("WovenBand",Vector3.new(1.92,0.09,1.1),Vector3.new(0,y,1),"EDB568")
  end
  for i=1,capacity do
   attach("Roast"..i,Vector3.new(0.55,0.47,0.5),Vector3.new(((i-1)%3-1)*0.55,0.45,0.76+math.floor((i-1)/3)*0.45),"EF953B",true)
  end
 end
 if model then
  for i=1,capacity do model["Roast"..i].Transparency = i <= #s.items and 0 or 1 end
  if #s.items == 0 then model:Destroy() end
 end
end

local function sync(player,s)
 player:SetAttribute("FarmCash",s.cash)
 player:SetAttribute("FarmBasket",#s.items)
 player:SetAttribute("FarmZap",s.zap)
 player:SetAttribute("FarmCollect",s.collect)
end

local function join(player)
 local s = {cash=0,items={},zap=1,collect=1,cooldowns={}}
 state[player] = s
 sync(player,s)
 player.CharacterAdded:Connect(function(character)
  task.spawn(function()
   local root = character:WaitForChild("HumanoidRootPart",8)
   if root and player.Character == character then
    character:PivotTo(map.FarmSpawn.CFrame*CFrame.new(0,3.5,0))
    basket(player,s)
   end
  end)
 end)
end
Players.PlayerAdded:Connect(join)
Players.PlayerRemoving:Connect(function(player) state[player] = nil end)
for _, player in Players:GetPlayers() do join(player) end

local function rootOf(player)
 local character = player.Character
 local humanoid = character and character:FindFirstChildOfClass("Humanoid")
 return humanoid and humanoid.Health > 0 and character:FindFirstChild("HumanoidRootPart")
end
local function inZone(root,zone)
 local point = zone.CFrame:PointToObjectSpace(root.Position)
 return math.abs(point.X) <= zone.Size.X/2 and math.abs(point.Z) <= zone.Size.Z/2 and math.abs(point.Y) < 8
end
local function nearby(pool,origin,range,direction,minDot)
 local list = {}
 for model, data in pool do
  local pos = data.pos
  local offset = flat(pos-origin)
  local dist = offset.Magnitude
  if dist <= range and (not direction or dist < 0.01 or direction:Dot(offset.Unit) >= minDot) then
   table.insert(list,{model=model,pos=pos,dist=dist})
  end
 end
 table.sort(list,function(a,b) return a.dist < b.dist end)
 return list
end

local function arc(from,to)
 local last = from
 for i=1,5 do
  local nextPoint = from:Lerp(to,i/5)
  if i < 5 then nextPoint += Vector3.new(rng:NextNumber(-0.38,0.38),rng:NextNumber(-0.5,0.5),rng:NextNumber(-0.38,0.38)) end
  local length = (last-nextPoint).Magnitude
  if length > 0.02 then
   local p = piece(map,"Lightning",Vector3.new(0.17,0.17,length),CFrame.lookAt((last+nextPoint)/2,nextPoint),"53DEFF")
   p.Material = Enum.Material.Neon
   Debris:AddItem(p,0.2)
  end
  last = nextPoint
 end
end
local function cook(target)
 local live = flock[target.model]
 if not live then return end
 flock[target.model] = nil
 target.model:Destroy()
 local roast = buildCreature(live.variant,true,piece)
 roast:SetAttribute("Species",catalog[live.variant].name)
 local pos = target.pos + Vector3.new(0,0.53,0)
 roast:PivotTo(CFrame.new(pos))
 roasts[roast] = {pos=pos,variant=live.variant}
 roast.Parent = roastFolder
 for _=1,5 do
  local p = piece(map,"Puff",Vector3.one*0.62,CFrame.new(pos),"FFF6DF",true)
  TweenService:Create(p,TweenInfo.new(0.42),{Transparency=1,Size=Vector3.one*1.05,Position=pos+Vector3.new(rng:NextNumber(-1.4,1.4),rng:NextNumber(0.8,1.7),rng:NextNumber(-1.4,1.4))}):Play()
  Debris:AddItem(p,0.45)
 end
 task.delay(75,function()
  if roasts[roast] then roasts[roast] = nil; roast:Destroy() end
 end)
end

local function collectRoast(target,root)
 roasts[target.model] = nil
 local model = target.model
 local start = model:GetPivot()
 task.spawn(function()
  for i=1,8 do
   local t = i/8
   local pos = start.Position:Lerp((root.CFrame*CFrame.new(0,0.25,1)).Position,t)
   model:PivotTo(CFrame.new(pos+Vector3.yAxis*math.sin(t*math.pi)*1.6)*CFrame.Angles(0,t*4,0))
   task.wait(0.025)
  end
  model:Destroy()
 end)
end

remote.OnServerEvent:Connect(function(player,action)
 local s = state[player]
 local root = rootOf(player)
 if not s or not root or type(action) ~= "string" then return end
 if action ~= "zap" and action ~= "collect" and action ~= "buyZap" and action ~= "buyCollect" and action ~= "buyNest" and action ~= "buyRestaurant" then return end
 local now = os.clock()
 if (s.cooldowns[action] or 0) > now then return end
 s.cooldowns[action] = now + (action == "zap" and 0.55 or 0.27)
 local direction = flat(root.CFrame.LookVector).Unit
 if action == "zap" then
  local tier = s.zap
  local targets = nearby(flock,root.Position,({9,14,21})[tier],direction,tier == 3 and 0.42 or -0.15)
  local first = targets[1]
  if not first then
   s.zapTarget = nil
   tell(player,"靠近并朝向已孵化的动物")
   return
  end
  for index,target in targets do
   if target.model == s.zapTarget then
    first = table.remove(targets,index)
    table.insert(targets,1,first)
    break
   end
  end
  if tier == 2 then
   targets = {first}
   for _, target in nearby(flock,first.pos,10) do
    if target.model ~= first.model then table.insert(targets,target) end
   end
  end

  local remaining = catalog.zapDamage[tier]
  local from = root.Position+direction*1.2
  local cooked = 0
  s.zapTarget = nil
  for _, target in targets do
   local animal = flock[target.model]
   local damage = math.min(remaining,animal.health)
   local health = animal.health-damage
   remaining -= damage
   local to = target.pos+Vector3.yAxis
   arc(from,to)
   if tier == 2 then from = to end
   setHealth(target.model,animal,health)
   if health == 0 then
    cook(target)
    cooked += 1
   else
    s.zapTarget = target.model
   end
   if remaining == 0 then break end
  end
  local totalDamage = catalog.zapDamage[tier]-remaining
  local message = "造成 "..totalDamage.." 点伤害"
  if cooked > 0 then message ..= " · 烤熟 "..cooked.." 只" end
  tell(player,message)
 elseif action == "collect" then
  if #s.items == capacity then tell(player,"筐装满了，送去餐厅"); return end
  local tier = s.collect
  local facing = tier == 2 and direction or nil
  local targets = nearby(roasts,root.Position,({5.5,10,17})[tier],facing,0)
  local count = math.min(collectLimits[tier],capacity-#s.items,#targets)
  if count == 0 then tell(player,"靠近地上的熟食再拾取"); return end
  for i=1,count do
   local target = targets[i]
   table.insert(s.items,roasts[target.model].variant)
   collectRoast(target,root)
  end
  sync(player,s)
  basket(player,s)
  tell(player,#s.items == capacity and "装满啦！送去餐厅补货" or "拾取 +"..count.." 只")
 elseif action == "buyNest" then
  if not inZone(root,map.Nest.UpgradeZone) then return end
  local nextType = catalog[nestLevel+1]
  if not nextType then return end
  if s.cash < nextType.unlock then tell(player,"还差 "..(nextType.unlock-s.cash).." 金币"); return end
  s.cash -= nextType.unlock
  nestLevel += 1
  nextEgg = math.min(nextEgg,os.clock()+0.4)
  sync(player,s)
  tell(player,"产蛋窝升级！新蛋种 · "..nextType.egg)
 elseif action == "buyRestaurant" then
  if not inZone(root,map.Restaurant.UpgradeZone) then return end
  local paid, cost = restaurant.upgrade(s.cash)
  if paid then
   s.cash -= paid
   sync(player,s)
   tell(player,restaurant.level() == 3 and "第二个柜台开张啦！" or "升级成功！顾客点单更快")
  elseif cost then
   tell(player,"还差 "..(cost-s.cash).." 金币")
  end
 elseif inZone(root,map.Shop) then
  local key = action == "buyZap" and "zap" or "collect"
  local price = prices[s[key]]
  if not price then return end
  if s.cash < price then tell(player,"还差 "..(price-s.cash).." 金币"); return end
  s.cash -= price
  s[key] += 1
  sync(player,s)
  if key == "zap" then
   tell(player,"升级成功！每次电击 "..catalog.zapDamage[s.zap].." 点伤害")
  else
   tell(player,"升级成功！一次最多拾取 "..collectLimits[s.collect].." 份")
  end
 end
end)

while true do
 local dt = math.min(task.wait(0.075),0.2)
 local now = os.clock()
 updateEggs(now)
 restaurant.update(now,dt)
 local roots = {}
 for player,s in state do
  local root = rootOf(player)
  if root then
   table.insert(roots,root)
   player:SetAttribute("FarmShop",inZone(root,map.Shop))
   player:SetAttribute("FarmNestShop",inZone(root,map.Nest.UpgradeZone))
   player:SetAttribute("FarmRestaurantShop",inZone(root,map.Restaurant.UpgradeZone))
   if #s.items > 0 and inZone(root,map.Sell) then
    local deposited = restaurant.deposit(player,s.items)
    if deposited > 0 then
     sync(player,s)
     basket(player,s)
     tell(player,"已补货 "..deposited.." 份 · 等待顾客购买")
    elseif not s.atFullShelf then
     tell(player,"备餐架已满，剩余熟食还在筐里")
    end
    s.atFullShelf = restaurant.count() >= restaurant.capacity
   else
    s.atFullShelf = false
   end
  end
  player:SetAttribute("FarmStock",restaurant.count())
  player:SetAttribute("FarmNestLevel",nestLevel)
  player:SetAttribute("FarmRestaurantLevel",restaurant.level())
 end
 for model, data in flock do
  local speed = 3.8
  if now >= data.turn then
   data.turn = now+rng:NextNumber(0.65,1.65)
   local angle = rng:NextNumber(0,2*math.pi)
   data.dir = Vector3.new(math.cos(angle),0,math.sin(angle))
  end
  local dir = data.dir
  local offset = data.center-data.pos
  if offset.Magnitude > 9 then
   dir = offset.Unit
  else
   for _, root in roots do
    local away = data.pos-flat(root.Position)
    if away.Magnitude < 6 and away.Magnitude > 0.01 then
     dir = away.Unit
     speed = 8.8
     break
    end
   end
  end
  data.pos += dir*speed*dt
  local height = ({0.78,0.74,1.1,1.1,1.26})[data.variant]
  local pos = data.pos+Vector3.yAxis*(height+math.abs(math.sin(now*speed*2+data.phase))*0.23)
  model:PivotTo(CFrame.lookAt(pos,pos+dir))
 end
end
