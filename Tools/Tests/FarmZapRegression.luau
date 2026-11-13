-- 电棒命中回归：真实请求入口验证扣血、熟食产出、宽松距离及拒绝回执；预测账本验证乱序和超时
--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local r = require("@lune/roblox")
local Prediction = require("../../Scripts/ReplicatedStorage/Scripts/Client/FarmZapPrediction")
local Rules = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmCombatRules")
local Request = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmRequest")
local checks = 0
local function Check(value, message)
	assert(value, message)
	checks += 1
end
for _, invalid in { 0, -1, 1.5, math.huge, 0/0, "1", 9007199254740992 } do
	Check(Request.Parse({action="zap",shotId=invalid}) == nil, "invalid shot ID rejected")
end
Check(Request.Parse({action="zap",shotId=1}).shotId == 1, "shot ID preserved")
local function Target(id, damage, cooked)
	return {id=id,x=5,y=0,z=0,damage=damage,isCooked=cooked}
end
local tracker = Prediction.new()
local cancelled = 0
local function Cancel() cancelled += 1 end
local a = tracker:Begin({Target("rabbit",3,true)}, {rabbit=Cancel})
local b = tracker:Begin({Target("other",2,false)}, {other=Cancel})
Check(#tracker:Resolve(b,true,{Target("other",2,false)}) == 0 and cancelled == 0, "out-of-order matching ack does not replay")
local corrected = tracker:Resolve(a,true,{Target("rabbit",1,false)})
Check(#corrected == 1 and corrected[1].damage == 1 and cancelled == 1, "corrected damage cancels false death")
Check(#tracker:Resolve(a,true,{Target("rabbit",1,false)}) == 0 and cancelled == 1, "duplicate ack ignored")
local c = tracker:Begin({Target("rabbit",3,true)}, {rabbit=Cancel})
Check(#tracker:Resolve(c,false,{}) == 0 and cancelled == 2, "rejection cancels predicted death")
local d = tracker:Begin({Target("rabbit",3,true)}, {rabbit=Cancel})
tracker:Expire(d)
Check(cancelled == 3 and next(tracker.pending) == nil, "timeout frees predictions")
Check(#tracker:Resolve(d,true,{Target("rabbit",3,true)}) == 0, "late ack cannot replay expired shot")
local e = tracker:Begin({}, {})
Check(e > d, "IDs continue after timeout")
tracker:Clear()
Check(next(tracker.pending) == nil, "respawn clears predictions")
local function Candidate(id,x,y,z) return {id=id,x=x,y=y,z=z,health=100} end
Check(Rules.ValidateOrderedTargets(1,0,0,0,1,0,{Candidate("a",-13,0,0)}), "server accepts angular drift and exactly 4 stud margin")
Check(not Rules.ValidateOrderedTargets(1,0,0,0,1,0,{Candidate("a",13.01,0,0)}), "server rejects outside margin")
Check(Rules.ValidateOrderedTargets(2,0,0,0,1,0,{Candidate("a",18,0,0),Candidate("b",32,0,0)}), "chain hop has 4 stud margin")
Check(not Rules.ValidateOrderedTargets(2,0,0,0,1,0,{Candidate("a",18,0,0),Candidate("b",32.01,0,0)}), "overlong chain rejected")
Check(#Rules.ResolveShot(1,1,0,0,0,1,0,{Candidate("a",9.01,0,0)}) == 0, "client range remains strict")
Check(#Rules.ResolveShot(1,1,0,0,0,1,0,{Candidate("a",-5,0,0)}) == 0, "client angle remains strict")

-- 复用既有服务端沙箱，只增加真实电击/熟食逻辑所需的场景替身。
local source = fs.readFile("Tools/Tests/SpeciesSwitchRegression.luau")
source = source:sub(1, assert(source:find("local rabbitPlayer, rabbitSession",1,true))-1)
source = source:gsub("local source = fs.readFile", [[
local r = require("@lune/roblox")
local root = {Position=r.Vector3.zero}
local receipts = {}
local function Model(position)
	return {PrimaryPart={Position=position,SetAttribute=function() end}, attributes={},
		SetAttribute=function(self,key,value) self.attributes[key]=value end,
		Destroy=function(self) self.destroyed=true end, PivotTo=function() end}
end
modules.ServerFarmSceneTool.GetPlayerRoot = function() return root end
modules.ServerFarmSceneTool.SetHealthTone = function() end
modules.ServerCreatureBuilder.Build = function() return Model(r.Vector3.zero) end
modules.NetMsg.FireNotifyFarmVisual = function(_,event) table.insert(receipts,event) end
node.GetServerTimeNow = function() return 100 end
environment.Vector3,environment.CFrame = r.Vector3,r.CFrame
modules.FarmScenePaths = luau.load(fs.readFile("Scripts/ReplicatedStorage/Scripts/Shared/FarmScenePaths.luau"), {environment={Instance=r.Instance}})()
local source = fs.readFile]],1)
source ..= [[
local player,session = NewSession("rabbit",false)
local level = 2
local tool={Enabled=true,IsA=function(_,class) return class=="Tool" end,
	GetAttribute=function(_,key) return if key=="WeaponTier" then 1 elseif key=="WeaponLevel" then level else nil end}
player.Character={FindFirstChildOfClass=function() return {Health=100} end,
	FindFirstChild=function(_,name) return if name=="FarmWeapon" then tool else nil end}
session.map=r.Instance.new("Folder")
local id=0
local function AddAnimal(name,hp,position)
	local model=Model(position)
	session.animals[name]={id=name,health=hp,maxHealth=hp,pos=r.Vector3.new(1000,0,0),model=model,speciesId="rabbit",qualityId="normal"}
	return model
end
local function Shot(name,reset)
	if reset~=false then session.cooldowns.zap=0 end
	id+=1
	local command=Request.Parse({action="zap",shotId=id,aim={x=1,y=0,z=0},targetIds={name}})
	assert(command)
	manager:OnCommand(player,command)
	assert(receipts[#receipts].shotId==id,"every shot must have correlated receipt")
	return receipts[#receipts]
end
session.farm.weaponLevels["1"]=2
local model=AddAnimal("rabbit",6,r.Vector3.new(6,1,0))
local first=Shot("rabbit")
assert(first.accepted and first.targets[1].damage==3 and first.targets[1].remainingHealth==3 and not first.targets[1].isCooked)
assert(session.animals.rabbit.health==3 and model.attributes.Health==3)
local rejected=Shot("rabbit",false)
assert(not rejected.accepted and session.animals.rabbit.health==3,"cooldown rejection acknowledged without damage")
local final=Shot("rabbit")
assert(final.accepted and final.targets[1].isCooked and final.targets[1].remainingHealth==0)
assert(not session.animals.rabbit and model.destroyed and session.ground.rabbit,"kill creates food exactly once")
assert(not Shot("rabbit").accepted,"missing/dead target rejected")
level=1;session.farm.weaponLevels["1"]=1
AddAnimal("lv1",6,r.Vector3.new(4,1,0))
for remaining=4,0,-2 do
	local receipt=Shot("lv1")
	assert(receipt.accepted and receipt.targets[1].remainingHealth==remaining)
end
assert(session.ground.lv1 and not session.animals.lv1)
AddAnimal("moving",6,r.Vector3.new(-12,1,0))
assert(Shot("moving").accepted,"primary part position and generous server angle used")
AddAnimal("remote",6,r.Vector3.new(1000,0,0))
assert(not Shot("remote").accepted and session.animals.remote.health==6)
assert(not Shot("foreign").accepted,"foreign ID rejected")
tool.Enabled=false
assert(not Shot("moving").accepted,"equipment rejection acknowledged")
tool.Enabled=true
session.frozen=true
assert(not Shot("moving").accepted,"frozen rejection acknowledged")
session.frozen=false
local count=#receipts
manager:OnCommand(player,{action="zap",shotId=id,targetIds={"moving"}})
assert(#receipts==count+1 and not receipts[#receipts].accepted,"replay rejected")
manager.sessions[player]=nil
assert(not Shot("moving").accepted,"missing session rejection acknowledged")
print("Server zap regression passed: Lv2 6->3->food; Lv1 6->4->2->food; primary coordinates, margin, cooldown, equipment, ownership, session, replay")
]]
local imports = {}
for path in source:gmatch('require%("([^"]+)"%)') do imports[path] = require(path) end
luau.load(source,{environment={require=function(path) return assert(imports[path],path) end}})()
print("FarmZapRegression: " .. checks .. " protocol, prediction and spatial checks passed")

-- 加载真实特效模块，验证取消回调与飘字池代次绑定。
local function Noop() end
local node = {}
function node:WaitForChild(name) return if name=="Scripts" or name=="Shared" then node else name end
local lifecycle = {new=function() return {Destroy=Noop,Play=Noop,Delay=Noop} end}
local modules = {
 FarmScenePaths = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmScenePaths"),FarmConfig={},FarmEconomyConfig={},GameTexts={},LifecycleTool=lifecycle,FarmSoundTool={Play=Noop}}
local services = {Players={LocalPlayer={}},ReplicatedStorage={WaitForChild=function() return node end},TweenService={Create=function() return {} end}}
local vfx = luau.load(fs.readFile("Scripts/ReplicatedStorage/Scripts/Client/FarmVisualEffects.luau"), {environment={
	game={GetService=function(_,name) return services[name] end},
	require=function(name) return assert(modules[name],name) end,
	Color3=r.Color3,Vector3=r.Vector3,UDim2=r.UDim2,CFrame=r.CFrame,Enum=r.Enum,
	TweenInfo={new=function() return {} end},
	Instance={new=function() return {Destroy=Noop} end},
}})()
local slot = {active=false,generation=0,playback=lifecycle.new(),gui={ResetPropertyToDefault=Noop},
	label={},stroke={},scale={},baseSize=r.UDim2.fromOffset(100,40)}
local fake = {damagePool={slot},anchorPool={},poolFolder={},rng={NextNumber=function() return 0 end},SpawnFloatingText=vfx.SpawnFloatingText}
local old = vfx.SpawnFloatingText(fake,r.Vector3.zero,"old")
local current = vfx.SpawnFloatingText(fake,r.Vector3.zero,"new")
old()
Check(slot.active and slot.gui.Enabled and slot.label.Text=="new", "old shot cannot cancel reused label slot")
current()
Check(not slot.active and not slot.gui.Enabled, "current shot cancels its own label")
print("Floating label generation regression passed")

-- 真实 NetMsg 入口在请求解析失败但编号有效时也必须返回拒绝回执。
local onCommand, delivered, invoked
local remote = {OnServerEvent={Connect=function(_,callback) onCommand=callback; return {} end},
	FireClient=function(_,player,event) delivered={player=player,event=event} end}
local netNode = {}
function netNode:WaitForChild(name)
	if name=="FarmConfig" or name=="FarmRequest" then return name end
	if name=="RoastChickenAction" then return remote end
	return netNode
end
function netNode:FindFirstChild(name) return if name=="GameConfig" then name else remote end
local net = luau.load(fs.readFile("Scripts/ReplicatedStorage/Scripts/Shared/NetMsg.luau"), {environment={
	game={GetService=function() return netNode end},script={Parent=netNode},
	require=function(name) return if name=="FarmRequest" then Request else {} end,
}})()
net.ConnectRequestFarmCommand(function() invoked=true end)
onCommand("player",{action="zap",shotId=17,aim={x=0/0,y=0,z=0}})
Check(delivered.player=="player" and delivered.event.shotId==17 and delivered.event.accepted==false and not invoked,"malformed correlated zap gets rejection")
delivered=nil
onCommand("player",{action="zap",shotId=18,targetIds={"rabbit"}})
Check(invoked and delivered==nil,"valid zap reaches manager without duplicate receipt")
print("NetMsg rejection receipt regression passed")
