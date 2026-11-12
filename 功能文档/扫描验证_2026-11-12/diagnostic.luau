local fs = require('@lune/fs')
local luau = require('@lune/luau')
local Config = require('./Scripts/ReplicatedStorage/Scripts/Shared/FarmEconomyConfig')
local source = fs.readFile('Scripts/ServerStorage/Scripts/ServerPersonalFarmManager.luau')
local fn = assert(source:match('(local function RequestSpecies.-)\nlocal function ConfirmSpecies'))
local request = luau.load(fn..'\nreturn RequestSpecies', {environment={Config=Config}})()
local ok, err = pcall(request, {farm={selectedSpeciesId='rabbit'}}, 'chicken', 0)
print('RequestSpecies rabbit->chicken',ok,err)
assert(not ok and tostring(err):find('key'), 'expected nil predecessor failure')
local function Signal()
 local callbacks={}
 return {Connect=function(_,f) table.insert(callbacks,f) end,Fire=function() for _,f in callbacks do f() end end}
end
local template={Volume=0.5,Destroying=Signal()}
function template:Clone()
 local sound={Volume=self.Volume,Ended=Signal(),Stopped=Signal()}
 function sound:Play() end
 function sound:Stop() self.Stopped.Fire() end
 return sound
end
function template:IsA(c) return c=='Sound' end
local folder={Parent=true,FindFirstChild=function(_,n) return template end,IsA=function() return true end}
local rs={FindFirstChild=function() return folder end}
local ss={FindFirstChild=function() return nil end,IsA=function() return false end}
local tool=luau.load(fs.readFile('Scripts/ReplicatedStorage/Scripts/Shared/FarmSoundTool.luau'),{environment={game={GetService=function(_,n) return if n=='ReplicatedStorage' then rs else ss end}}})()
local first=tool.Play('Coin',nil,0.2)
assert(first.Volume==0.1)
first:Stop()
local nextSound=tool.Play('Coin')
print('Sound reuse',first==nextSound,'template volume',template.Volume,'ordinary play volume',nextSound.Volume)
assert(first==nextSound and nextSound.Volume==0.1,'expected inherited multiplier')
print('Both source diagnostics reproduced')
