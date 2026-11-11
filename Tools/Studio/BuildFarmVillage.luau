-- 八人村落 Edit 构筑器：整理唯一农场模板、生成常驻八户与中央公共道路；禁止在 Play 执行
assert(not game:GetService("RunService"):IsRunning(), "Edit only")
local Storage=game:GetService("ServerStorage")
local Replicated=game:GetService("ReplicatedStorage")
local History=game:GetService("ChangeHistoryService")
History:SetWaypoint("Before eight-player village")
local template=Storage.Models.PersonalFarmTemplate
local function Folder(parent,name)
 local node=parent:FindFirstChild(name)
 if not node then node=Instance.new("Folder"); node.Name=name; node.Parent=parent end
 return node
end
local function Piece(parent,name,size,cf,color,collide)
 local p=Instance.new("Part"); p.Name=name; p.Size=size; p.CFrame=cf
 p.Color=Color3.fromHex(color); p.Anchored=true; p.CanCollide=collide==true
 p.CanTouch=false; p.CanQuery=collide==true; p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth
 p.Parent=parent; return p
end
local function Count(root)
 local parts,collision=0,0
 for _,p in root:GetDescendants() do if p:IsA("BasePart") then parts+=1; if p.CanCollide then collision+=1 end end end
 return {parts=parts,collision=collision,instances=#root:GetDescendants()}
end
local before=Count(template)
if template:GetAttribute("VillageTemplateVersion")~=1 then
 local landscaping=Folder(template,"Landscaping")
 local foliage=Folder(landscaping,"Flowers")
 local fences=Folder(template,"Boundary")
 local ground=Folder(template,"Ground")
 local paths=Folder(template,"Paths")
 local trees=Folder(landscaping,"Trees")
 local tool=Instance.new("Model"); tool.Name="ToolStand"; tool.Parent=template
 local mill=Instance.new("Model"); mill.Name="Windmill"; mill.Parent=template
 local centers,petals={},{}
 for _,p in template:GetChildren() do
  if p.Name=="FlowerCenter" then table.insert(centers,p) elseif p.Name=="Petal" then table.insert(petals,p) end
 end
 table.sort(centers,function(a,b) return a.Position.X==b.Position.X and a.Position.Z<b.Position.Z or a.Position.X<b.Position.X end)
 for index,center in centers do
  if index%2==0 then
   for _,p in petals do if p.Parent and (p.Position-center.Position).Magnitude<1.5 then p:Destroy() end end
   center:Destroy()
  end
 end
 local toolNames={ShopPost=true,ShopCounter=true,ShopTop=true,ShopSign=true,Awning=true,BlasterCoil=true,VacuumNozzle=true,ScoopBlade=true,DisplayScoop=true,DisplayBlaster=true,DisplayVacuum=true}
 for _,p in template:GetChildren() do
  if p:IsA("BasePart") then
   local n=p.Name
   if n=="Cloud" then p:Destroy()
   elseif n=="Grass" then p.Parent=ground
   elseif n=="HomePath" or n=="ToolPath" then p.Parent=paths
   elseif n=="FenceRail" or n=="FencePost" then p.Parent=fences
   elseif n=="Petal" or n=="FlowerCenter" or n=="HayBale" or n=="HayTwine" then p.Parent=foliage
   elseif n=="TreeCanopy" or n=="TreeTrunk" then p.Parent=trees
   elseif n:sub(1,4)=="Mill" then p.Parent=mill
   elseif toolNames[n] then p.Parent=tool end
  end
 end
 -- 合并同高、同材质且连续的围栏横梁；保留原有门洞。
 local groups={}
 for _,p in fences:GetChildren() do if p.Name=="FenceRail" then
  local along=if p.Size.X>=p.Size.Z then p.CFrame.RightVector else p.CFrame.LookVector
  local axis=if math.abs(along.X)>0.99 then "X" else "Z"
  local length=math.max(p.Size.X,p.Size.Z)
  local center=if axis=="X" then p.Position.X else p.Position.Z
  local constant=if axis=="X" then p.Position.Z else p.Position.X
  local key=string.format("%s:%.3f:%.3f:%s",axis,constant,p.Position.Y,tostring(p.Color))
  groups[key]=groups[key] or {}; table.insert(groups[key],{part=p,lo=center-length/2,hi=center+length/2,axis=axis})
 end end
 for _,segments in groups do
  table.sort(segments,function(a,b) return a.lo<b.lo end)
  local current=nil
  for _,segment in segments do
   if current and segment.lo<=current.hi+0.02 then
    current.hi=math.max(current.hi,segment.hi)
    local p=current.part
    local center=(current.lo+current.hi)/2
    local pos=if segment.axis=="X" then Vector3.new(center,p.Position.Y,p.Position.Z) else Vector3.new(p.Position.X,p.Position.Y,center)
    p.CFrame=CFrame.new(pos)*p.CFrame.Rotation
    if p.Size.X>=p.Size.Z then p.Size=Vector3.new(current.hi-current.lo,p.Size.Y,p.Size.Z) else p.Size=Vector3.new(p.Size.X,p.Size.Y,current.hi-current.lo) end
    segment.part:Destroy()
   else current=segment end
  end
 end
 local restaurant=template.Restaurant
 local details=Folder(restaurant,"FloorDetails")
 local boundary=Folder(restaurant,"Boundary")
 local display=Folder(restaurant,"Display")
 for _,p in restaurant:GetChildren() do
  if p.Name=="Tile" or p.Name=="StaffAisleMark" or p.Name=="QueueMarker" then p.Parent=details
  elseif p.Name=="FarmBoundaryRail" or p.Name=="FarmBoundaryPost" then p.Parent=boundary
  elseif p.Name:match("^DisplayFood") or p.Name=="MarqueeBulb" then p.Parent=display end
 end
 for _,model in {tool,mill} do
  local cf,size=model:GetBoundingBox()
  local root=Piece(model,"RootPart",Vector3.new(0.2,0.2,0.2),CFrame.new(cf.Position-Vector3.yAxis*(size.Y/2-0.1)),"FFFFFF",false)
  root.Transparency=1; root.CastShadow=false; root.Massless=true; model.PrimaryPart=root
 end
 for _,p in template:GetDescendants() do
  if p:IsA("BasePart") then
   p.CanTouch=false
   if p:IsDescendantOf(landscaping) or p.Name=="FencePost" or p.Name=="MarqueeBulb" or p.Name=="Tile" or p.Name=="Straw" or p.Name=="MillSail" or p.Name=="MillSpar" then
    p.CanCollide=false; p.CanQuery=false
   elseif not p.CanCollide then p.CanQuery=false end
  end
 end
 template.FarmSpawn.Enabled=false
 local sign=Piece(template,"OwnerSign",Vector3.new(0.2,0.2,0.2),CFrame.new(-10,3,59),"FFFFFF",false)
 sign.Transparency=1; sign.CastShadow=false
 sign:SetAttribute("FarmSign","FarmOwnerSignGui"); sign:SetAttribute("FarmSignAudience","Public")
 sign:SetAttribute("FarmText","Plot01 · Vacant farm")
 local publicGui=Replicated.UI:FindFirstChild("FarmOwnerSignGui")
 if not publicGui then
  publicGui=Replicated.UI.NestSignGui:Clone(); publicGui.Name="FarmOwnerSignGui"; publicGui.Parent=Replicated.UI
 end
 publicGui.MaxDistance=100; publicGui.Size=UDim2.fromScale(13,2.4)
 publicGui.AlwaysOnTop=true; publicGui.LightInfluence=0
 for _,v in publicGui:GetDescendants() do
  if v:IsA("TextLabel") then v.TextScaled=true; v.Text="Vacant farm"; v.AutoLocalize=false end
  if v:IsA("UIStroke") then v.StrokeSizingMode=Enum.StrokeSizingMode.ScaledSize end
 end
 template:SetAttribute("VillageTemplateVersion",1)
end
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
 map.OwnerSign:SetAttribute("FarmText",name.." · Vacant farm")
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
