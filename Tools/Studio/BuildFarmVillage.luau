-- 八人村落 Edit 构筑器：整理唯一农场模板、生成常驻八户与中央公共道路；禁止在 Play 执行
--!strict
assert(not game:GetService("RunService"):IsRunning(), "Edit only")
local Storage=game:GetService("ServerStorage")
local Replicated=game:GetService("ReplicatedStorage")
local History=game:GetService("ChangeHistoryService")
History:SetWaypoint("Before eight-player village")
-- Script Sync 在 Edit 使用草稿；只读加载无副作用的路径契约，不提交草稿或覆写 Source。
local pathModule = game:GetService("ReplicatedStorage").Scripts.Shared.FarmScenePaths
local loadPaths, loadError = loadstring(game:GetService("ScriptEditorService"):GetEditorSource(pathModule), "FarmScenePaths")
assert(loadPaths, loadError)
local Paths = loadPaths()
local template=Storage.Models.PersonalFarmTemplate
local function Folder(parent: Instance,name: string): Instance
 local node=parent:FindFirstChild(name)
 if not node then local folder=Instance.new("Folder"); folder.Name=name; folder.Parent=parent; node=folder end
 assert(node)
 return node
end
local function Piece(parent: Instance,name: string,size: Vector3,cf: CFrame,color: string,collide: boolean): Part
 local p=Instance.new("Part"); p.Name=name; p.Size=size; p.CFrame=cf
 p.Color=Color3.fromHex(color); p.Anchored=true; p.CanCollide=collide==true
 p.CanTouch=false; p.CanQuery=collide==true; p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth
 p.Parent=parent; return p
end
local function Count(root: Instance)
 local parts,collision=0,0
 for _,p in root:GetDescendants() do if p:IsA("BasePart") then parts+=1; if p.CanCollide then collision+=1 end end end
 return {parts=parts,collision=collision,instances=#root:GetDescendants()}
end
local before=Count(template)
assert(template:GetAttribute("FarmHierarchyVersion")==2,"Run OrganizePersonalFarms before rebuilding the village")
local after=Count(template)
assert(after.parts<=601 and after.collision<=159,"Template budget exceeded")
local archive=Folder(Storage,"FarmVillageArchive")
for _,name in {"RoastChickenFarm","Baseplate","SpawnLocation"} do
 local legacy=workspace:FindFirstChild(name)
 if legacy then legacy.Parent=archive end
end
for _,name in {"FarmPlots","PersonalFarms","FarmVillage"} do local old=workspace:FindFirstChild(name); if old then old:Destroy() end end
local plots=Folder(workspace,"FarmPlots")
local farms=Folder(workspace,"PersonalFarms")
local public=Folder(workspace,"FarmVillage")
public:SetAttribute("Capacity",8)
Piece(public,"VillageGround",Vector3.new(320,1,560),CFrame.new(0,-0.65,0),"719F48",true)
Piece(public,"CentralRoad",Vector3.new(24,0.2,520),CFrame.new(0,-0.1,0),"CBAA79",true)
for _,side in {-1,1} do
 Piece(public,"RoadShoulder",Vector3.new(3,0.12,520),CFrame.new(side*13.5,-0.04,0),"E7CF9F",true)
end
local rows={-192,-64,64,192}
for index=1,8 do
 local row=math.ceil(index/2)
 local left=index%2==1
 local transform=CFrame.new(if left then -80 else 80,0,rows[row])*CFrame.Angles(0,math.rad(if left then 90 else -90),0)
 local name=string.format("Plot%02d",index)
 local plot=Piece(plots,name,Vector3.new(0.2,0.2,0.2),transform,"FFFFFF",false)
 plot.Transparency=1; plot.CastShadow=false
 local map=template:Clone()
 map.Name=name; map:SetAttribute("FarmId",name); map:SetAttribute("OwnerUserId",nil); map:SetAttribute("Occupied",false)
 for _,p in map:GetDescendants() do
  p:SetAttribute("OwnerUserId",nil)
  if p:IsA("BasePart") then p.CFrame=transform*p.CFrame; p:SetAttribute("FarmId",name) end
 end
 Paths.Require(map,"OwnerSign"):SetAttribute("FarmText",name.." · Vacant farm")
 map.Parent=farms
 Piece(public,"EntryPath_"..name,Vector3.new(12,0.15,16),transform*CFrame.new(0,-0.025,60),"E7CF9F",true)
 task.wait()
end
-- 公共道路两端的候场点；资料加载后由业务入口送至自家出生点。
local spawn=Instance.new("SpawnLocation"); spawn.Name="VillageArrival"; spawn.Size=Vector3.new(10,0.2,10)
spawn.CFrame=CFrame.new(0,0.1,-250); spawn.Anchored=true; spawn.Transparency=1; spawn.CanCollide=false
spawn.CanTouch=false; spawn.CanQuery=false; spawn.Duration=0; spawn.Neutral=true; spawn.Parent=public
local green=Folder(public,"Greenery")
for _,z in {-256,-128,0,128,256} do
 for _,side in {-1,1} do
  local trunk=Piece(green,"RoadTreeTrunk",Vector3.new(1.2,5,1.2),CFrame.new(side*23,2.4,z),"85613E",true)
  local canopy=Piece(green,"RoadTreeCanopy",Vector3.new(7,6,7),CFrame.new(side*23,7,z),"4F8E48",false)
  canopy.Shape=Enum.PartType.Ball
 end
end
workspace.StreamingEnabled=true
-- 标牌由常驻客户端管理器拥有，角色重生不能清除 PlayerGui 中的这些实例。
for _,gui in Replicated.UI:GetChildren() do if gui:IsA("BillboardGui") then gui.ResetOnSpawn=false end end
local capacityOk,capacityError=pcall(function() game.Players.MaxPlayers=8 end)
local localization=game:GetService("LocalizationService"):FindFirstChild("FarmLocalizationTable")
if localization then
 local entries=localization:GetEntries()
 local additions={
  {Key="FarmVillageVacant",Source="{1} · Vacant farm",Values={["zh-cn"]="{1} · 空置农场"}},
  {Key="FarmVillageOwner",Source="{1} · {2}'s farm",Values={["zh-cn"]="{1} · {2}的农场"}}
 }
 for _,entry in additions do
  local found=false; for _,old in entries do if old.Key==entry.Key then old.Source=entry.Source; old.Values=entry.Values; found=true end end
  if not found then table.insert(entries,entry) end
 end
 localization:SetEntries(entries)
end
History:SetWaypoint("Built eight-player village")
return {before=before,after=after,staticFarms=Count(farms),public=Count(public),capacitySet=capacityOk,capacityError=if capacityOk then nil else tostring(capacityError),maxPlayers=game.Players.MaxPlayers}
