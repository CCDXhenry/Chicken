-- 八人常驻村落运行回归：仅在双人 Play 服务端验证归属、参观、旋转、重生与回收
--!strict
local Paths = require(game.ReplicatedStorage.Scripts.Shared.FarmScenePaths)
local RunService = game:GetService("RunService")
assert(RunService:IsRunning() and RunService:IsServer(), "Play server only")
local Players = game:GetService("Players")
local Manager = require(game.ServerStorage.Scripts.ServerPersonalFarmManager)
local active = Manager.GetActive()
assert(active, "Active personal farm manager required")
local list = Players:GetPlayers()
assert(#list >= 2, "Two loaded players required")
local first, second = active.sessions[list[1]], active.sessions[list[2]]
assert(first and second and first.plot ~= second.plot, "Two independent sessions required")
local checks: { string } = {}
local saved: { [Player]: { pivot: CFrame, anchored: boolean } } = {}
local function Check(value: boolean, message: string): ()
 assert(value, message); table.insert(checks,message)
end
local function Root(player: Player): BasePart
 local character=player.Character
 assert(character)
 local root=character:FindFirstChild("HumanoidRootPart")
 assert(root and root:IsA("BasePart"))
 return root
end
for _,player in list do
 local character=player.Character
 assert(character)
 saved[player]={pivot=character:GetPivot(),anchored=Root(player).Anchored}
 Root(player).Anchored=true
end
local success,failure=xpcall(function(): boolean
 Check(#workspace.PersonalFarms:GetChildren()==8 and #workspace.FarmPlots:GetChildren()==8,"Eight static farms and eight anchors")
 Check(first.map:GetAttribute("OwnerUserId")==first.owner.UserId and second.map:GetAttribute("OwnerUserId")==second.owner.UserId,"Unique live ownership on opposite road sides")
 Check(first.plot.CFrame.RightVector:Dot(second.plot.CFrame.RightVector)<-0.99,"Opposite farm orientation")
 for _,session in {first,second} do
  local spawn=Paths.Find(session.map, "FarmSpawn") :: BasePart
  local localSpawn=session.plot.CFrame:PointToObjectSpace(spawn.Position)
  Check((localSpawn-Vector3.new(0,0.45,16)).Magnitude<0.01,"Rotated local spawn anchor: "..session.plot.Name)
  session.owner:SetAttribute("FarmPlotId",session.plot.Name)
 end
 -- 不修改存档，仅把携带货物的玩家置于邻居交货区；业务只读取其自家 Sell。
 local sell=Paths.Find(second.map, "Sell") :: BasePart
 local basketCount,cash=#first.farm.basket,first.farm.cash
 Root(first.owner).CFrame=sell.CFrame*CFrame.new(0,3,0)
 local unload=first.nextUnloadAt
 active:Update(os.clock(),0)
 Check(#first.farm.basket==basketCount and first.farm.cash==cash and first.nextUnloadAt==nil,"Visiting neighbor cannot unload into foreign restaurant")
 first.nextUnloadAt=unload
 local egg=second.eggs[1]
 if egg then
  local finish=egg.finish
  active:OnCommand(first.owner,{action="accelerateEgg",targetId=egg.id})
  Check(egg.finish==finish,"Foreign egg ID rejected by live manager")
 end
 -- 回收后原地块建筑引用必须保留，其他会话不被清理。
 local player,map,plot=first.owner,first.map,first.plot
 local neighborMap=second.map
 active:RemovePlayer(player)
 Check(map.Parent==workspace.PersonalFarms and map:GetAttribute("OwnerUserId")==nil,"Release preserves static farm and clears owner")
 Check(not Paths.Find(map, "Eggs") and not Paths.Find(map, "LiveAnimals") and not Paths.Find(map, "CookedFood"),"Release removes all production and ground entities")
 local restaurant,sign=map:FindFirstChild("Restaurant"),Paths.Find(map, "OwnerSign")
 Check(restaurant~=nil and not Paths.Find(map, "Runtime") and sign~=nil and sign:GetAttribute("FarmText")==plot.Name.." · Vacant farm","Vacancy restores public sign and removes workers")
 Check(active.sessions[second.owner]==second and neighborMap:GetAttribute("OwnerUserId")==second.owner.UserId,"Neighbor session survives release")
 active:OnPlayerLoaded(player)
 local restored=active.sessions[player]
 Check(restored~=nil and restored.map==map and restored.plot==plot,"Lowest released plot reclaimed without cloning buildings")
 active:OnPlayerLoaded(player)
 Check(active.sessions[player]==restored and #workspace.PersonalFarms:GetChildren()==8,"Duplicate loaded callback cannot create another farm")
 return true
end,debug.traceback)
for player,record in saved do
 local character=player.Character
 if character then character:PivotTo(record.pivot); Root(player).Anchored=record.anchored end
 local session=active.sessions[player]
 if session then player:SetAttribute("FarmPlotId",session.plot.Name) end
end
assert(success,failure)
return checks
