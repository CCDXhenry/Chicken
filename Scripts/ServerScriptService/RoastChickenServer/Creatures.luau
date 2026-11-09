local catalog = require(game.ReplicatedStorage.RoastChickenCatalog)
local roastColors = {"DF7926","C96B3D","A74D36","B94133","D67537"}

local function build(variant, cooked, piece)
 local info = catalog[variant]
 local model = Instance.new("Model")
 model.Name = cooked and info.food or info.name
 local function add(name,x,y,z,sx,sy,sz,hex)
  return piece(model,name,Vector3.new(sx,sy,sz),CFrame.new(x,y,z),hex,false)
 end

 if cooked then
  model.PrimaryPart = add("Roast",0,0,0,1.74,0.83,1.91,roastColors[variant])
  add("Glaze",0,0.39,-0.12,1.46,0.18,1.51,"FFC05D")
  local bones = variant == 1 and {-1,1} or {1}
  for _, side in bones do
   add("Drumstick",side*0.71,-0.02,0.47,0.63,0.59,0.9,roastColors[variant])
   add("Bone",side*0.8,0,1,0.24,0.23,0.55,"FFF2C4")
   add("BoneTip",side*0.8,0,1.24,0.39,0.3,0.27,"FFF2C4")
  end
  if variant == 5 then model:ScaleTo(1.25) end
  return model
 end

 local function eyes(z,y,spacing,size)
  for _, side in {-1,1} do
   local x=side*spacing
   add("EyeWhite",x,y,z,size*1.35,size*1.5,0.085,"FFFCF5")
   add("Pupil",x+side*0.025,y-0.015,z-0.055,size*0.75,size,0.055,"241D31")
   add("EyeGlint",x-0.02,y+size*0.18,z-0.09,size*0.21,size*0.21,0.022,"FFFFFF")
  end
 end

 if variant == 1 then
  model.PrimaryPart = add("Body",0,0,0,1.52,1.19,1.6,"FFF4D8")
  add("Head",0,0.54,-0.58,1.21,1.13,1.03,"FFFCED")
  add("Beak",0,0.41,-1.2,0.48,0.25,0.34,"FFB429")
  add("Wattle",0,0.17,-1.07,0.25,0.31,0.18,"EB4338")
  for i=1,3 do add("Comb",0,1.14+0.09*(3-i),-0.89+0.23*i,0.29,0.35,0.24,"F3453D") end
  for _, side in {-1,1} do
   add("Wing",side*0.79,-0.04,0.14,0.32,0.6,0.93,"F7DDB0")
   add("Foot",side*0.39,-0.67,-0.15,0.42,0.2,0.64,"F8A82C")
  end
  add("Tail",0,0.31,0.83,0.74,0.64,0.32,"FFFCED").CFrame *= CFrame.Angles(math.rad(-25),0,0)
  eyes(-1.115,0.66,0.34,0.2)
 elseif variant == 2 then
  model.PrimaryPart = add("Body",0,0,0,1.6,1.18,1.72,"E6B495")
  add("Head",0,0.47,-0.63,1.38,1.17,1.15,"FBD9BC")
  add("Tail",0,0.16,0.95,0.56,0.54,0.52,"FFF3DC")
  for _, side in {-1,1} do
   local ear=add("Ear",side*0.37,1.48,-0.63,0.41,1.18,0.35,"FBD9BC")
   ear.CFrame *= CFrame.Angles(0,0,math.rad(-side*7))
   add("InnerEar",side*0.42,1.47,-0.83,0.24,0.82,0.07,"F183AA")
   add("Paw",side*0.52,-0.62,-0.26,0.51,0.22,0.78,"DFA588")
  end
  add("Nose",0,0.36,-1.26,0.21,0.15,0.1,"D95684")
  add("Muzzle",0,0.22,-1.23,0.48,0.2,0.13,"FFF0D9")
  eyes(-1.22,0.63,0.39,0.19)
 else
  local wool = variant==3
  local dino = variant==5
  local body = wool and "F9EDE0" or dino and "69D24D" or "FBE6CA"
  local face = wool and "66526A" or dino and "83E254" or "FBE6CA"
  model.PrimaryPart = add("Body",0,0,0,2.12,1.42,2.38,body)
  add("Head",0,0.52,-1.03,1.55,1.22,1.13,face)
  for _, side in {-1,1} do
   for _, z in {-0.72,0.72} do
    add("Leg",side*0.66,-0.67,z,0.46,0.65,0.52,face)
    add("Foot",side*0.66,-0.98,z-0.04,0.52,0.23,0.59,dino and "409A3B" or "674C49")
   end
   if not dino then add("Ear",side*0.88,0.71,-1,0.49,0.32,0.46,face) end
  end
  if wool then
   for _, z in {-0.75,0,0.75} do
    add("WoolTop",0,0.78,z,1.71,0.49,0.72,"FFF9EC")
    for _, side in {-1,1} do add("WoolCurl",side*1.02,0.15,z,0.34,0.92,0.7,"FFF5E7") end
   end
   add("Forelock",0,1.12,-1.03,1.39,0.38,0.98,"FFF9EC")
  elseif dino then
   add("Jaw",0,0.24,-1.63,1.41,0.42,0.72,"B6EB6A")
   add("Tail",0,-0.08,1.48,0.77,0.64,1.02,"69D24D")
   add("TailTip",0,-0.02,2.04,0.49,0.48,0.53,"53BA4E")
   for i=1,4 do
    add("Spine",0,0.84,1.37-i*0.55,0.34,0.48,0.32,"FFBC4A").CFrame *= CFrame.Angles(math.rad(24),0,0)
   end
  else
   add("Muzzle",0,0.28,-1.62,1.31,0.49,0.35,"F595A0")
   for _, side in {-1,1} do
    add("Horn",side*0.55,1.2,-0.99,0.26,0.48,0.36,"F3C26E")
    add("Nostril",side*0.28,0.31,-1.81,0.12,0.09,0.055,"A24E62")
   end
   add("Patch",-1.07,0.22,0.29,0.06,0.82,0.79,"744B41")
   add("Patch",1.07,0.34,-0.36,0.06,0.68,0.81,"744B41")
  end
  eyes(-1.62,0.76,0.44,0.23)
  if dino then model:ScaleTo(1.15) end
 end
 return model
end

return build
