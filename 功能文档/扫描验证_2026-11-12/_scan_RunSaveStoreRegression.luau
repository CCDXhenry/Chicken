local fs = require('@lune/fs')
local luau = require('@lune/luau')
local serde = require('@lune/serde')
local function Load(path, environment) return luau.load(fs.readFile(path), {environment=environment})() end
local root = 'Scripts/'
local Save = Load(root..'ReplicatedStorage/Scripts/Shared/FarmSaveData.luau')
local Rules = Load(root..'ServerStorage/Scripts/PlayerSaveLeaseRules.luau')
local clock, guid, checks = 1000, 0, 0
local function Check(value, message) assert(value, message); checks+=1 end
local function Clone(value) return serde.decode('json', serde.encode('json', value)) end
local row = {value=nil, metadata={ForeignKey='preserved'}, writes=0, failNext=false, retryNext=false, pauseNext=false}
local backend = {}
local function SafeUpdate(_, key, transform)
 assert(key=='101')
 if row.failNext then row.failNext=false; return false, 'injected transport failure' end
 if row.pauseNext then row.pauseNext=false; coroutine.yield('updatePaused') end
 while true do
  local keyInfo = {GetMetadata=function() return table.clone(row.metadata) end, GetUserIds=function() return {101} end}
  local value, _, metadata = transform(row.value, keyInfo)
  if value==nil then return true, nil end
  row.value, row.metadata = Clone(value), table.clone(metadata)
  row.writes+=1
  if row.retryNext then row.retryNext=false else return true, Clone(row.value) end
 end
end
local node={}
function node:WaitForChild(name)
 if name=='Core' or name=='Scripts' or name=='Shared' then return self end
 return name
end
local modules={
 DataStoreTool={SafeUpdate=SafeUpdate}, FarmSaveData=Save, PlayerSaveLeaseRules=Rules,
 GameConfig={CreateDefaultPlayerSaveInfo=function() return {dataVersion=1,farm=Save.CreateDefault(),settingInfo={bgmVolume=0.4},loginDays=17} end}
}
local environment={
 game={GetService=function(_,name)
  if name=='HttpService' then return {GenerateGUID=function() guid+=1; return 'token-'..guid end} end
  return node
 end},
 script={Parent=node}, require=function(name) return assert(modules[name],name) end,
 os={time=function() return clock end}, task={wait=function() return coroutine.yield('wait') end},
}
local Store=Load(root..'ServerStorage/Scripts/ServerPlayerSaveStore.luau',environment)
local a,b=Store.new(backend),Store.new(backend)
local acquired,value=a:Acquire(101)
Check(acquired and value.farm.cash==0 and a:IsActive(101),'new default is acquired under a lease')
Check(row.metadata.ForeignKey=='preserved','foreign metadata retained')
local tokenA=row.metadata.ChickenSessionId
Check(not b:Acquire(101),'second live session denied')
b:Release(101)
Check(row.metadata.ChickenSessionId==tokenA,'failed second acquisition cannot release first session')
local function Snapshot(cash,revision)
 local snapshot=Clone(row.value)
 snapshot.farm.cash=cash
 snapshot.farm.revision=revision
 return snapshot
end
Check(a:Save(101,Snapshot(10,1),1) and row.value.farm.cash==10,'full snapshot saved')
Check(row.value.settingInfo.bgmVolume==0.4 and row.value.loginDays==17,'generic save fields preserved')
clock+=121
Check(not a:IsActive(101),'expired lease disables activity locally')
Check(b:Acquire(101),'new session can acquire expired lease')
local tokenB=row.metadata.ChickenSessionId
Check(tokenB~=tokenA,'new session uses a different token')
Check(not a:Save(101,Snapshot(999,2),2) and row.value.farm.cash==10,'old server cannot overwrite new owner')
a:Release(101)
Check(row.metadata.ChickenSessionId==tokenB,'old release cannot clear new owner')
Check(b:Save(101,Snapshot(20,2),2),'new owner can write')
local revision=row.metadata.ChickenSaveRevision
row.retryNext=true
Check(b:Save(101,Snapshot(30,3),3),'lost acknowledgement retry succeeds')
Check(row.metadata.ChickenSaveRevision==revision+1 and row.value.farm.cash==30,'same operation replay keeps one storage revision')
Check(b:Save(101,Snapshot(1,1),1) and row.value.farm.cash==30,'out of order local snapshot is superseded')
row.failNext=true
Check(not b:Save(101,Snapshot(999,4),4) and row.value.farm.cash==30,'transport failure preserves stored snapshot')
row.pauseNext=true
local newerOK,olderOK
local newer=coroutine.create(function() newerOK=b:Save(101,Snapshot(40,4),4) end)
local older=coroutine.create(function() olderOK=b:Save(101,Snapshot(35,3),3) end)
local ok,signal=coroutine.resume(newer)
Check(ok and signal=='updatePaused' and b:IsBusy(101),'save remains owned while transport yields')
ok,signal=coroutine.resume(older)
Check(ok and signal=='wait' and row.value.farm.cash==30,'concurrent save waits for current writer')
assert(coroutine.resume(newer))
assert(coroutine.resume(older))
Check(newerOK and olderOK and row.value.farm.cash==40,'late older writer cannot roll back newer snapshot')
row.pauseNext=true
local released
local pending=coroutine.create(function() b:Save(101,Snapshot(50,5),5) end)
local release=coroutine.create(function() released=b:Release(101) end)
assert(coroutine.resume(pending))
ok,signal=coroutine.resume(release)
Check(ok and signal=='wait' and not b:IsActive(101),'release freezes session and waits for in flight save')
assert(coroutine.resume(pending))
assert(coroutine.resume(release))
Check(released and row.value.farm.cash==50 and row.metadata.ChickenSessionId==nil,'release preserves final snapshot and removes only its lease')
Check(not b:Save(101,Snapshot(777,6),6),'released session cannot write')
local metadata=Rules.Acquire({ForeignKey='kept'},'a',0,120)
assert(metadata)
local nextMetadata=Rules.Write(metadata,'a',0,120,0,'op1')
assert(nextMetadata)
Check(Rules.Write(nextMetadata,'a',1,120,0,'different')==nil,'storage revision rejects a different stale operation')
Check(Rules.Write(nextMetadata,'a',120,120,1,'op2')==nil,'exact expiry rejects writing')
Check(Rules.Acquire({ChickenSessionId=17},'b',0,120)==nil,'corrupt metadata rejected')
print('SaveStoreRegression passed:',checks,'checks; old sessions, callback replay, ordering, failures, concurrent save and release')