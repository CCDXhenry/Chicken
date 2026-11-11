# 八人地块离线回归：执行正式认领与回收工具，不连接 Roblox 或真实存档。
$ErrorActionPreference = 'Stop'
Push-Location (Resolve-Path "$PSScriptRoot/../..")
try {
@'
local fs = require('@lune/fs')
local luau = require('@lune/luau')
local roblox = require('@lune/roblox')
local Instance = roblox.Instance
local config = luau.load(fs.readFile('Scripts/ReplicatedStorage/Scripts/Shared/FarmVillageConfig.luau'))()
local node = {}
function node:WaitForChild(name) return (name=='Scripts' or name=='Shared') and self or name end
local modules = {FarmVillageConfig=config,GameTexts={Farm={VillageVacant={source='%s · Vacant farm'},VillageOwner={source="%s · %s's farm"}}}}
local env={game={GetService=function() return node end},require=function(name) return assert(modules[name],name) end}
local tool=luau.load(fs.readFile('Scripts/ServerStorage/Scripts/ServerFarmVillageTool.luau'),{environment=env})()
local function Make(class,name,parent)
 local object=Instance.new(class); object.Name=name; object.Parent=parent; return object
end
local plots,farms=Make('Folder','Plots'),Make('Folder','Farms')
local reservations,owners={},{}
local checks=0
local function Check(value,message) assert(value,message); checks+=1 end
for i=1,8 do
 local id=string.format('Plot%02d',i)
 local plot=Make('Part',id,plots)
 local map=Make('Folder',id,farms); map:SetAttribute('FarmId',id)
 Make('Part','FarmSpawn',map); Make('Part','Sell',map)
 local sign=Make('Part','OwnerSign',map); sign:SetAttribute('FarmSign','FarmOwnerSignGui'); sign:SetAttribute('FarmSignAudience','Public')
 Make('Part','Chute',Make('Folder','Nest',map))
 local restaurant=Make('Folder','Restaurant',map); Make('Part','QueueHead',restaurant); Make('Part','QueueStart',restaurant)
 owners[i]={UserId=i,DisplayName='Owner'..i}
end
tool.Validate(plots,farms); Check(true,'eight valid prebuilt plots')
Check(not config.IsPlotId('Plot00') and not config.IsPlotId('Plot09') and not config.IsPlotId('Plot1'),'only padded eight plot IDs')
for i=1,8 do
 local plot,map=tool.FindAvailable(plots,farms,reservations)
 Check(plot.Name==string.format('Plot%02d',i),'lowest free ID')
 Check(tool.Claim(map,plot,owners[i],reservations),'claim unique plot')
 Check(map:GetAttribute('OwnerUserId')==i and map:GetAttribute('Occupied') and map.Sell:GetAttribute('OwnerUserId')==i,'ownership projected')
end
local plot,map=tool.FindAvailable(plots,farms,reservations)
Check(plot==nil and map==nil,'full village waits')
local first=farms.Plot01
Check(not tool.Claim(first,plots.Plot01,owners[1],reservations),'duplicate load cannot claim twice')
Check(not tool.Release(first,plots.Plot01,owners[2],reservations),'foreign release refused')
Make('Part','Egg',Make('Folder','Eggs',first))
Make('Folder','LiveAnimals',first); Make('Folder','CookedFood',first); Make('Model','Worker',Make('Folder','Workers',first.Restaurant))
first.Sell:SetAttribute('FarmSign','RestaurantSignGui')
Check(tool.Release(first,plots.Plot01,owners[1],reservations),'owner release')
Check(first.Parent==farms and first.FarmSpawn.Parent==first,'static building retained')
Check(not first:FindFirstChild('Eggs') and not first:FindFirstChild('LiveAnimals') and not first:FindFirstChild('CookedFood') and not first.Restaurant:FindFirstChild('Workers'),'runtime objects cleared')
Check(first:GetAttribute('OwnerUserId')==nil and first.Sell:GetAttribute('OwnerUserId')==nil and first.Sell:GetAttribute('FarmSign')==nil,'private state cleared')
Check(first.OwnerSign:GetAttribute('FarmSign')=='FarmOwnerSignGui' and first.OwnerSign:GetAttribute('FarmText')=='Plot01 · Vacant farm','public vacancy sign restored')
Check(farms.Plot02:GetAttribute('OwnerUserId')==2,'neighbor unaffected')
local nextOwner={UserId=9,DisplayName='Next'}
plot,map=tool.FindAvailable(plots,farms,reservations)
Check(map==first and tool.Claim(map,plot,nextOwner,reservations),'released plot reused')
Check(not tool.Release(first,plots.Plot01,owners[1],reservations) and first:GetAttribute('OwnerUserId')==9,'old owner cannot release new session')
tool.Release(first,plots.Plot01,nextOwner,reservations)
Check(not tool.Claim(first,plots.Plot01,owners[2],reservations),'one player cannot own a second plot')
local bad=Make('Folder','Unexpected',farms)
Check(not pcall(tool.Validate,plots,farms),'unexpected ninth static farm rejected')
bad:Destroy()
print('FarmVillageRegression passed:',checks,'checks; prebuilt ownership, full capacity, cleanup and reuse')
'@ | lune run -
    if ($LASTEXITCODE -ne 0) { throw 'FarmVillageRegression failed' }
} finally { Pop-Location }
