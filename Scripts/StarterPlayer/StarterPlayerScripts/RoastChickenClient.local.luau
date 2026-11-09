local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local player = Players.LocalPlayer
local remote = game.ReplicatedStorage:WaitForChild("RoastChickenAction")
local catalog = require(game.ReplicatedStorage:WaitForChild("RoastChickenCatalog"))
local gui = Instance.new("ScreenGui")
gui.Name = "RoastChickenHUD"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")
local cream = Color3.fromHex("FFF2CD")
local brown = Color3.fromHex("643923")
local blue = Color3.fromHex("225BA4")
local orange = Color3.fromHex("B45525")
local function panel(name,parent,width,height,anchor,pos,background,isButton)
 local item = Instance.new(isButton and "TextButton" or "TextLabel")
 item.Name = name
 item.Size = UDim2.fromOffset(width,height)
 item.AnchorPoint = anchor
 item.Position = pos
 item.BackgroundColor3 = background
 item.BorderSizePixel = 0
 item.TextColor3 = cream
 item.TextSize = 18
 item.Font = Enum.Font.GothamBold
 item.TextWrapped = true
 item.Parent = parent
 local corner = Instance.new("UICorner",item)
 corner.CornerRadius = UDim.new(0,14)
 local stroke = Instance.new("UIStroke",item)
 stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
 stroke.Thickness = 2
 stroke.Color = cream
 return item
end
local function v(x,y) return Vector2.new(x,y) end
local hud = panel("FarmStatus",gui,280,86,v(0.5,0),UDim2.new(0.5,0,0,10),brown)
local hint = panel("FarmHint",gui,294,44,v(0.5,0),UDim2.new(0.5,0,0,105),Color3.fromHex("496D32"))
hint.TextSize = 15
local actions = Instance.new("Frame",gui)
actions.Name = "Actions"
actions.AnchorPoint = v(0.5,1)
actions.Position = UDim2.new(0.5,0,1,-17)
actions.Size = UDim2.fromOffset(310,66)
actions.BackgroundTransparency = 1
local zap = panel("Zap",actions,146,62,v(0,0),UDim2.fromOffset(3,0),blue,true)
local collect = panel("Collect",actions,146,62,v(0,0),UDim2.fromOffset(161,0),orange,true)
local shop = Instance.new("Frame",gui)
shop.Name = "UpgradeShop"
shop.AnchorPoint = v(0.5,0.5)
shop.Position = UDim2.fromScale(0.5,0.51)
shop.Size = UDim2.fromOffset(306,168)
shop.BackgroundTransparency = 1
local heading = panel("ShopHeading",shop,306,40,v(0,0),UDim2.fromOffset(0,0),brown)
heading.Text = "工具商店 · 两条升级路线"
local buyZap = panel("BuyZap",shop,306,51,v(0,0),UDim2.fromOffset(0,51),blue,true)
local buyCollect = panel("BuyCollect",shop,306,51,v(0,0),UDim2.fromOffset(0,112),orange,true)
local building = panel("BuildingUpgrade",gui,286,61,v(0.5,0.5),UDim2.fromScale(0.5,0.48),Color3.fromHex("7045A8"),true)
local sales = panel("SaleNotice",gui,238,36,v(0.5,0),UDim2.new(0.5,0,0,155),Color3.fromHex("397C46"))
sales.TextSize = 14
sales.Visible = false
local saleId = 0
local zapNames = {"基础电棒","连锁电枪","范围电炮"}
local collectNames = {"徒手","收鸡铲","吸鸡器"}
local caps = {1,3,6}
local prices = {60,180}
local messageNumber = 0
local showingMessage = false

local function render()
 local cash = player:GetAttribute("FarmCash") or 0
 local count = player:GetAttribute("FarmBasket") or 0
 local z = player:GetAttribute("FarmZap") or 1
 local c = player:GetAttribute("FarmCollect") or 1
 local stock = player:GetAttribute("FarmStock") or 0
 hud.Text = "烤鸡农场\n金币 "..cash.."   鸡筐 "..count.."/6\n餐厅库存 "..stock.."/24"
 local atNest = player:GetAttribute("FarmNestShop") == true
 local atRestaurant = player:GetAttribute("FarmRestaurantShop") == true
 local nestLevel = player:GetAttribute("FarmNestLevel") or 1
 local restaurantLevel = player:GetAttribute("FarmRestaurantLevel") or 1
 local nextType = catalog[nestLevel+1]
 local nextPrice = catalog.restaurantPrices[restaurantLevel]
 building.Visible = atNest or atRestaurant
 if atNest then
  building.Active = nextType ~= nil
  building.Text = nextType and ("产蛋窝升级 · "..nextType.egg.."\n"..nextType.unlock.." 金币") or "产蛋窝 · 已满级"
 elseif atRestaurant then
  building.Active = nextPrice ~= nil
  local benefit = restaurantLevel == 1 and "加快点单" or "开启第二柜台"
  building.Text = nextPrice and ("餐厅升级 · "..benefit.."\n"..nextPrice.." 金币") or "餐厅 · 已满级"
 end
 zap.Text = "Q · 电击\n"..zapNames[z].." · 伤害 "..catalog.zapDamage[z]
 collect.Text = "E · 拾取\n"..collectNames[c].." ×"..caps[c]
 shop.Visible = player:GetAttribute("FarmShop") == true
 buyZap.Text = z == 3 and "范围电炮 · 已满级" or zapNames[z+1].." · 伤害 "..catalog.zapDamage[z+1].." · "..prices[z].." 金币"
 buyCollect.Text = c == 3 and "吸鸡器 · 已满级" or collectNames[c+1].."  ·  "..prices[c].." 金币"
 buyZap.Active = z < 3
 buyCollect.Active = c < 3
 if not showingMessage then
  hint.Text = count == 6 and "鸡筐已满 · 送到餐厅后厨" or "等蛋孵化 → 电动物 → 装筐补货"
 end
end
for _, name in {"FarmCash","FarmBasket","FarmZap","FarmCollect","FarmShop","FarmStock","FarmNestShop","FarmRestaurantShop","FarmNestLevel","FarmRestaurantLevel"} do
 player:GetAttributeChangedSignal(name):Connect(render)
end
remote.OnClientEvent:Connect(function(message,kind)
 if kind == "sale" then
  saleId += 1
  local current = saleId
  sales.Text = message
  sales.Visible = true
  task.delay(2,function()
   if saleId == current then sales.Visible = false end
  end)
  return
 end
 messageNumber += 1
 local current = messageNumber
 showingMessage = true
 hint.Text = message
 task.delay(2.5,function()
  if messageNumber == current then
   showingMessage = false
   render()
  end
 end)
end)
local function action(button,command,key)
 button.Activated:Connect(function() remote:FireServer(command) end)
 if key then
  ContextActionService:BindAction("Farm_"..command,function(_,inputState)
   if inputState == Enum.UserInputState.Begin then remote:FireServer(command) end
   return Enum.ContextActionResult.Sink
  end,false,key)
 end
end
action(zap,"zap",Enum.KeyCode.Q)
action(collect,"collect",Enum.KeyCode.E)
action(buyZap,"buyZap")
action(buyCollect,"buyCollect")
building.Activated:Connect(function()
 if not building.Active then return end
 if player:GetAttribute("FarmNestShop") then
  remote:FireServer("buyNest")
 elseif player:GetAttribute("FarmRestaurantShop") then
  remote:FireServer("buyRestaurant")
 end
end)
render()
