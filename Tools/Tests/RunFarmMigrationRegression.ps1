# 迁移离线回归：直接执行正式迁移源码，验证旧资料保留及携带货物的 JSON 往返。
$ErrorActionPreference = 'Stop'
Push-Location (Resolve-Path "$PSScriptRoot/../..")
try {
@'
local fs = require('@lune/fs')
local luau = require('@lune/luau')
local serde = require('@lune/serde')
local Save = luau.load(fs.readFile('Scripts/ReplicatedStorage/Scripts/Shared/FarmSaveData.luau'))()
local node = {}
function node:WaitForChild(name)
 if name=='Scripts' or name=='Shared' then return self end
 return name
end
function node:FindFirstChild(name) return name end
local modules={FarmSaveData=Save,GameConfig={PlayerSaveInfoDataVersion=1}}
local environment={game={GetService=function() return node end},script=node,require=function(name) return assert(modules[name],name) end}
local path='Scripts/ServerStorage/Scripts/PlayerSaveInfoVersionUpdateTool/'
modules.PlayerSaveInfoVersionUpdate1=luau.load(fs.readFile(path..'PlayerSaveInfoVersionUpdate1.luau'),{environment=environment})()
local Migration=luau.load(fs.readFile(path..'init.luau'),{environment=environment})()
local checks=0
local function Check(value,message) assert(value,message); checks+=1 end
local old={dataVersion=0,settingInfo={bgmVolume=0.4},loginDays=17,ownedGamePassList={123}}
Check(Migration.Update(old) and old.dataVersion==1 and old.farm.cash==0,'legacy save gains independent farm')
Check(old.settingInfo.bgmVolume==0.4 and old.loginDays==17 and old.ownedGamePassList[1]==123,'generic fields retained')
old.farm.cash=90
Check(Migration.Update(old) and old.farm.cash==90,'repeated migration preserves cash')
Check(not Migration.Update({dataVersion=99}),'future player version rejected')
Check(not Migration.Update({dataVersion=0/0}),'NaN player version rejected')
Check(not Migration.Update({dataVersion=1,farm={}}),'corrupt farm is rejected instead of reset')
local cargo={itemId='basket',speciesId='rabbit',qualityId='golden',weightKg=6,saleValue=500,configVersion=1}
table.insert(old.farm.basket,cargo)
local orderCargo=table.clone(cargo); orderCargo.itemId='processing'
table.insert(old.farm.kitchen,{cargo=orderCargo,state='Processing',remainingSeconds=1.1,speedSnapshot=1.35,durationSnapshot=6/1.35})
local restored=serde.decode('json',serde.encode('json',old.farm))
Check(Save.Validate(restored) and restored.basket[1].saleValue==500,'cargo snapshot JSON round trip')
Check(restored.ownedWeapons['1'] and restored.weaponLevels['1']==1,'string map keys retained')
Check(restored.kitchen[1].remainingSeconds==1.1 and restored.kitchen[1].cargo.itemId=='processing','offline remaining time and identity retained')
print('FarmMigrationRegression passed:',checks,'checks; actual migration source, generic data and cargo JSON round trip')
'@ | lune run -
    if ($LASTEXITCODE -ne 0) { throw 'FarmMigrationRegression failed' }
} finally {
    Pop-Location
}
