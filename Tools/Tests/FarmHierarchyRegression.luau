-- 农场层级资产回归：对真实备份执行迁移与失败预检，验证幂等性及两个重建工具
--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Paths = luau.load(fs.readFile("Scripts/ReplicatedStorage/Scripts/Shared/FarmScenePaths.luau"), {environment={Instance=roblox.Instance}})()
roblox.implementMethod("Instance", "WaitForChild", function(self,name)
 local child=self:FindFirstChild(name)
 assert(child,name)
 return child
end)
roblox.implementMethod("Model", "GetPivot", function(self) return self.PrimaryPart.CFrame end)
local checks = 0
local function Check(value, message)
 assert(value,message); checks+=1
end
local function Folder(name,parent)
 local node=roblox.Instance.new("Folder"); node.Name=name; node.Parent=parent; return node
end
local function Read(file)
 local roots=roblox.deserializeModel(fs.readFile(file))
 local holder=Folder("Assets")
 for _,root in roots do root.Parent=holder end
 return holder
end
local backup=Read("Assets/Studio/PersonalFarms.before-hierarchy.rbxm")
local village=Read("Assets/Studio/FarmVillage.rbxm")
local package=Read("Assets/Studio/PersonalFarmTemplates.rbxm")
local models=Folder("Models")
local replicated=Folder("ReplicatedStorage")
Folder("UI",replicated)
local scripts=Folder("Scripts",replicated); local shared=Folder("Shared",scripts)
local module=roblox.Instance.new("ModuleScript"); module.Name="FarmScenePaths"; module.Parent=shared
local world=roblox.Instance.new("Workspace")
backup.PersonalFarms.Parent=world
village.FarmPlots:Clone().Parent=world
backup.PersonalFarmTemplate.Parent=models
for _,root in package:GetChildren() do if root.Name~="PersonalFarmTemplate" and root.Name~="FarmPlots" then root:Clone().Parent=models end end
for partName,name in {Sell="OriginalFoodDeliverySignGui",DeliveryDirection="OriginalFoodDirectionSignGui",KitchenEntranceSign="OriginalKitchenEntranceSignGui"} do
 local gui=models.FarmRestaurantOriginalLayout:FindFirstChild(partName):FindFirstChildOfClass("BillboardGui"):Clone()
 gui.Name=name; gui.Parent=replicated.UI
end
local history={SetWaypoint=function() end}
local storage=roblox.Instance.new("ServerStorage")
models.Parent=storage
local services={ServerStorage=storage,ReplicatedStorage=replicated,RunService={IsRunning=function() return false end},ChangeHistoryService=history,ScriptEditorService={GetEditorSource=function() return fs.readFile("Scripts/ReplicatedStorage/Scripts/Shared/FarmScenePaths.luau") end},LocalizationService={FindFirstChild=function() return nil end}}
local gameMock={ServerStorage=storage,ReplicatedStorage=replicated,Players={MaxPlayers=60},GetService=function(_,name) return assert(services[name],name) end}
local env={game=gameMock,workspace=world,Instance=roblox.Instance,CFrame=roblox.CFrame,Vector3=roblox.Vector3,Color3=roblox.Color3,Enum=roblox.Enum,task={wait=function() end},require=function(target) assert(target.Name=="FarmScenePaths"); return Paths end}
env.loadstring=function(source) return luau.load(source,{environment={Instance=roblox.Instance}}) end
local function Run(file) return luau.load(fs.readFile(file),{environment=env})() end
local template=models.PersonalFarmTemplate
local oldRoots={template}
for _,root in world.PersonalFarms:GetChildren() do table.insert(oldRoots,root) end
local snapshots={}
for _,root in oldRoots do for _,part in root:GetDescendants() do if part:IsA("BasePart") then snapshots[part]={cf=part.CFrame,size=part.Size,color=part.Color,collision=part.CanCollide,material=part.Material} end end end
-- An unmatched ninth-farm part must abort before touching even the first template.
local extra=roblox.Instance.new("Part"); extra.Name="Unexpected"; extra.Parent=world.PersonalFarms.Plot08
Check(not pcall(Run,"Tools/Studio/OrganizePersonalFarms.luau"),"mismatched farm rejects complete migration")
Check(template:FindFirstChild("Nest")~=nil and template:GetAttribute("FarmHierarchyVersion")==nil,"preflight failure leaves template untouched")
extra:Destroy()
local result=Run("Tools/Studio/OrganizePersonalFarms.luau")
Check(result.roots==9 and result.newFolders==189,"nine legacy farms migrated")
for part,snapshot in snapshots do
 Check(part.Parent~=nil and part.CFrame==snapshot.cf and part.Size==snapshot.size and part.Color==snapshot.color and part.CanCollide==snapshot.collision and part.Material==snapshot.material,"original geometry and style preserved")
end
Check(Run("Tools/Studio/OrganizePersonalFarms.luau").changes==0,"second migration changes nothing")
local function Signature(root)
 local paths={}
 for _,node in root:GetDescendants() do
  local segments={node.Name}; local parent=node.Parent
  while parent~=root do table.insert(segments,1,parent.Name); parent=parent.Parent end
  table.insert(paths,table.concat(segments,"/")..":"..node.ClassName)
 end
 table.sort(paths)
 return table.concat(paths,"\n")
end
local expected=Signature(template)
Check(expected==Signature(package.PersonalFarmTemplate),"saved template matches migration")
for index=1,8 do
 local name=string.format("Plot%02d",index)
 Check(Signature(world.PersonalFarms[name])==expected and Signature(village.PersonalFarms[name])==expected,"same paths, classes and stable names in "..name)
 for key,segments in Paths.StaticPaths do if segments[1]~="Runtime" then Check(Paths.Find(world.PersonalFarms[name],key)~=nil,"static contract "..key) end end
end
-- Two independent UpgradeZone leaves must resolve to their own areas.
Check(Paths.Require(template,"NestUpgradeZone")~=Paths.Require(template,"RestaurantUpgradeZone"),"duplicate anchor names cannot collide")
Check(Paths.Find(template,"Eggs")==nil,"static assets contain no runtime")
Run("Tools/Studio/BuildFarmVillage.luau")
for _,root in world.PersonalFarms:GetChildren() do Check(Signature(root)==expected,"village rebuild preserves organized schema") end
-- The restaurant rebuild may replace authored fixtures but must preserve schema and stable numbering.
Run("Tools/Studio/BuildRestaurantFlow.luau")
Check(Signature(template)==expected,"restaurant rebuild preserves template schema")
for _,root in world.PersonalFarms:GetChildren() do Check(Signature(root)==expected,"restaurant rebuild preserves all farm schemas") end
local runtime=Paths.EnsureRuntime(template,"Eggs")
Check(runtime:GetFullName():match("Runtime.Eggs$")~=nil and Paths.EnsureRuntime(template,"Eggs")==runtime,"runtime creation uses one exact container")
print("FarmHierarchyRegression passed:",checks,"checks; assets, preflight, preservation, stable names and both builders")
