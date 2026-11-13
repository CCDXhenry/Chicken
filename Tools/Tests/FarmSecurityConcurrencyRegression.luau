-- 安全与并发回归：执行真实服务端请求及文字拟合，验证远距拒绝与旧测量失效。
local fs = require('@lune/fs')
local luau = require('@lune/luau')
local r = require('@lune/roblox')

local source = fs.readFile('Tools/Tests/SpeciesSwitchRegression.luau')
source = source:sub(1, assert(source:find('local rabbitPlayer, rabbitSession', 1, true)) - 1)
source = source:gsub('local modules:', 'local diagRoot = { Position = { X = 0, Y = 0, Z = 0 } }\nlocal modules:', 1)
source = source:gsub('GetPlayerRoot = function%(%): any%s+return nil', 'GetPlayerRoot = function(): any return diagRoot', 1)
source = source:gsub('game = gameMock,', 'game = gameMock, Vector3 = require("@lune/roblox").Vector3,', 1)
source ..= [[
modules.ServerFarmSceneTool.SetHealthTone = function() end
local player, session = NewSession('chicken', false)
local tool = { Enabled = true, IsA = function(_, class) return class == 'Tool' end,
    GetAttribute = function(_, key) return if key == 'WeaponTier' or key == 'WeaponLevel' then 1 else nil end }
player.Character = { FindFirstChildOfClass = function() return { Health = 100 } end,
    FindFirstChild = function(_, name) return if name == 'FarmWeapon' then tool else nil end }
session.animals.remote = { id = 'remote', health = 100, maxHealth = 100, pos = {X=1000,Y=0,Z=0},
    model = {PrimaryPart={Position={X=1000,Y=0,Z=0}},SetAttribute=function() end}, speciesId='chicken', qualityId='normal' }
local request = Request.Parse({action='zap', aim={x=1,y=0,z=0}, targetIds={'remote'}})
assert(request)
manager:OnCommand(player, request)
assert(session.animals.remote.health == 100)
session.cooldowns.zap = 0
session.animals.remote.model.PrimaryPart.Position = {X=13,Y=0,Z=0}
manager:OnCommand(player, request)
assert(session.animals.remote.health == 98, 'valid boundary target must still take damage')
session.cooldowns.zap = 0
session.animals.remote.model.PrimaryPart.Position = {X=-5,Y=0,Z=0}
manager:OnCommand(player, request)
assert(session.animals.remote.health == 96, 'angular drift is accepted by the server')
print('Server request regression passed: remote rejected; distance margin and angular drift accepted')
]]
local imports = {}
for path in source:gmatch('require%("([^"]+)"%)') do
    imports[path] = require(path)
end
luau.load(source, { environment = { require = function(path) return assert(imports[path], path) end } })()

local service = {}
local slow = false
function service:GetTextBoundsAsync(params)
    if params.Text == 'A' and not slow then
        slow = true
        coroutine.yield('old measurement pending')
    end
    return r.Vector2.new(#params.Text * params.Size / 2, params.Size)
end
local fitting = luau.load(fs.readFile('Scripts/ReplicatedStorage/Scripts/Client/UIManager/TextFitting.luau'), { environment = {
    game={GetService=function() return service end},
    Instance={new=function() return {Destroy=function() end} end},
    Enum=r.Enum, Vector2=r.Vector2, math=math, string=string, setmetatable=setmetatable, assert=assert,
} })()
local label = { Text='A', TextSize=36, RichText=false, Font=r.Enum.Font.Unknown,
    FontFace=r.Font.new('rbxasset://fonts/families/FredokaOne.json',r.Enum.FontWeight.Regular,r.Enum.FontStyle.Italic),
    Size=r.UDim2.fromOffset(48,48), AbsoluteSize=r.Vector2.new(48,48),
    AutomaticSize=r.Enum.AutomaticSize.None,
    FindFirstChildOfClass=function() return nil end,
    GetAttribute=function() return 36 end }
local old = coroutine.create(function() fitting.FitTextLabel(label) end)
assert(coroutine.resume(old))
assert(coroutine.status(old)=='suspended')
label.Text='AAAAAAAAAA'
local correct=fitting.FitTextLabel(label)
assert(correct==8)
assert(coroutine.resume(old))
local stale=label.TextSize
assert(stale==8)
local cached=fitting.FitTextLabel(label)
assert(cached==8)
print('Text race regression passed: old measurement discarded; current and cached size=8')

local rules = require('../../Scripts/ReplicatedStorage/Scripts/Shared/FarmCombatRules')
local function target(id, x, z)
    return {id=id,x=x,y=0,z=z,health=100}
end
local function valid(tier, targets)
    return rules.ValidateOrderedTargets(tier,0,0,0,1,0,targets)
end
assert(valid(2,{target('first',14,0),target('next',24,0)}), 'chain can extend beyond player range')
assert(not valid(2,{target('first',14,0),target('next',29,0)}), 'chain overlong jump rejected')
assert(not valid(2,{target('first',19,0),target('next',20,0)}), 'chain first target must be in range')
assert(valid(3,{target('further',20,0),target('nearer',5,0)}), 'client order is legal without distance sorting')
assert(valid(3,{target('front',5,0),target('side',0,5)}), 'server tolerates cone angular drift')
assert(not valid(3,{target('same',5,0),target('same',5,0)}), 'duplicate target rejected by pure validator')
assert(not valid(1,{target('a',5,0),target('b',6,0)}), 'target cap enforced')
assert(rules.ValidateOrderedTargets(1,0,0,0,nil,nil,{target('a',5,0)}), 'server spatial guard does not require direction')
assert(not require('../../Scripts/ReplicatedStorage/Scripts/Shared/FarmRequest').Parse({action='zap',aim={x=0/0,y=0,z=0}}), 'nonfinite direction rejected at protocol boundary')
print('Spatial rules regression passed: boundary, chain, cone, ordering, duplicates, cap and direction')
