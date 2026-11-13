-- 八人农场 Edit 静态审计：检查地块、朝向、资产预算、入口通行与标牌模板
--!strict
local loadPaths, loadError = loadstring(game:GetService("ScriptEditorService"):GetEditorSource(game.ReplicatedStorage.Scripts.Shared.FarmScenePaths), "FarmScenePaths")
assert(loadPaths, loadError)
local Paths = loadPaths()
assert(not game:GetService("RunService"):IsRunning(), "Edit audit only")
local plots = workspace:FindFirstChild("FarmPlots")
local farms = workspace:FindFirstChild("PersonalFarms")
local village = workspace:FindFirstChild("FarmVillage")
assert(plots and farms and village)
assert(#plots:GetChildren()==8 and #farms:GetChildren()==8)
local function Count(root: Instance): (number, number)
 local count,collisions=0,0
 for _,object in root:GetDescendants() do if object:IsA("BasePart") then count+=1; if object.CanCollide then collisions+=1 end end end
 return count,collisions
end
local function Bounds(part: BasePart, space: CFrame): (Vector3,Vector3)
 local lo,hi=Vector3.new(math.huge,math.huge,math.huge),Vector3.new(-math.huge,-math.huge,-math.huge)
 for x=-1,1,2 do for y=-1,1,2 do for z=-1,1,2 do
  local point=space:PointToObjectSpace(part.CFrame:PointToWorldSpace(part.Size*Vector3.new(x,y,z)/2))
  lo,hi=lo:Min(point),hi:Max(point)
 end end end
 return lo,hi
end
local boxes: { { minimum: Vector3, maximum: Vector3 } }={}
local rows={-192,-64,64,192}
local farmParts,farmCollisions=0,0
for index=1,8 do
 local name=string.format("Plot%02d",index)
 local plot,map=plots:FindFirstChild(name),farms:FindFirstChild(name)
 assert(plot and plot:IsA("BasePart") and map and map:IsA("Folder"),name)
 assert(map:GetAttribute("FarmId")==name and map:GetAttribute("OwnerUserId")==nil and map:GetAttribute("Occupied")==false)
 local left=index%2==1
 assert((plot.Position-Vector3.new(if left then -80 else 80,0,rows[math.ceil(index/2)])).Magnitude<0.001)
 assert(plot.CFrame.LookVector:Dot(if left then -Vector3.xAxis else Vector3.xAxis)>0.999)
 for _,key in {"FarmSpawn","Sell","OwnerSign","Nest","Restaurant","Shop"} do assert(Paths.Find(map,key),name.."/"..key) end
 local spawn=Paths.Find(map, "FarmSpawn")
 assert(spawn and spawn:IsA("SpawnLocation") and not spawn.Enabled)
 for _,key in {"Eggs","LiveAnimals","CookedFood"} do assert(not Paths.Find(map,key)) end
 local restaurant=map:FindFirstChild("Restaurant")
 assert(restaurant and not Paths.Find(map, "Runtime"))
 local minimum,maximum=Vector3.new(math.huge,math.huge,math.huge),Vector3.new(-math.huge,-math.huge,-math.huge)
 for _,part in map:GetDescendants() do if part:IsA("BasePart") then
  local lo,hi=Bounds(part,plot.CFrame)
  assert(lo.X>=-56.01 and hi.X<=56.01 and lo.Z>=-50.01 and hi.Z<=62.01,"Part exceeds template footprint: "..part:GetFullName())
  assert(not part.CanTouch and part:GetAttribute("OwnerUserId")==nil)
  if part.CanCollide and lo.X<3 and hi.X>-3 and lo.Z<68 and hi.Z>52 and hi.Y>0.5 and lo.Y<5 then error("Farm entry blocked: "..part:GetFullName()) end
  local worldLo,worldHi=Bounds(part,CFrame.identity)
  minimum,maximum=minimum:Min(worldLo),maximum:Max(worldHi)
 end end
 table.insert(boxes,{minimum=minimum,maximum=maximum})
 local count,collisions=Count(map)
 assert(count<=601 and collisions<=159)
 farmParts+=count; farmCollisions+=collisions
 local path=village:FindFirstChild("EntryPath_"..name)
 assert(path and path:IsA("BasePart"))
 local lo,hi=Bounds(path,plot.CFrame)
 assert(lo.Z<=52.01 and hi.Z>=67.99 and path.CanCollide)
end
for i=1,#boxes do for j=i+1,#boxes do
 local a,b=boxes[i],boxes[j]
 assert(a.maximum.X<=b.minimum.X or b.maximum.X<=a.minimum.X or a.maximum.Z<=b.minimum.Z or b.maximum.Z<=a.minimum.Z,"Farm overlap")
end end
local road=village:FindFirstChild("CentralRoad")
assert(road and road:IsA("BasePart") and road.Size.X==24 and road.Size.Z==520)
assert(workspace.StreamingEnabled)
local gui=game.ReplicatedStorage.UI:FindFirstChild("FarmOwnerSignGui")
assert(gui and gui:IsA("BillboardGui") and not gui.ResetOnSpawn and gui.AlwaysOnTop and gui.LightInfluence==0)
for _,object in gui:GetDescendants() do
 if object:IsA("TextLabel") then assert(object.TextScaled) end
 if object:IsA("UIStroke") then assert(object.StrokeSizingMode==Enum.StrokeSizingMode.ScaledSize) end
end
local templateParts,templateCollisions=Count(game.ServerStorage.Models.PersonalFarmTemplate)
local publicParts,publicCollisions=Count(village)
return {plots=8,templateParts=templateParts,templateCollisions=templateCollisions,farmParts=farmParts,farmCollisions=farmCollisions,publicParts=publicParts,publicCollisions=publicCollisions,farmsInstances=#farms:GetDescendants(),publicInstances=#village:GetDescendants(),maxPlayers=game.Players.MaxPlayers,entryCorridorsClear=true,noOverlaps=true}
