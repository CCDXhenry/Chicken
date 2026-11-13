-- 扫描诊断：受控加载原生产模块，验证空间校验与异步文字拟合交错。
local fs = require('@lune/fs')
local luau = require('@lune/luau')
local r = require('@lune/roblox')

local source = fs.readFile('Tools/Tests/SpeciesSwitchRegression.luau')
source = source:sub(1, assert(source:find('local rabbitPlayer, rabbitSession', 1, true)) - 1)
source = source:gsub('local modules:', 'local diagRoot = { Position = { X = 0, Y = 0, Z = 0 } }\nlocal modules:', 1)
source = source:gsub('GetPlayerRoot = function%(%): any%s+return nil', 'GetPlayerRoot = function(): any return diagRoot', 1)
source = source:gsub('game = gameMock,', 'game = gameMock, Vector3 = require("@lune/roblox").Vector3,', 1)
source ..= [[
local player, session = NewSession('chicken', false)
local tool = { Enabled = true, IsA = function(_, class) return class == 'Tool' end,
    GetAttribute = function(_, key) return if key == 'WeaponTier' or key == 'WeaponLevel' then 1 else nil end }
player.Character = { FindFirstChildOfClass = function() return { Health = 100 } end,
    FindFirstChild = function(_, name) return if name == 'FarmWeapon' then tool else nil end }
session.animals.remote = { id = 'remote', health = 100, pos = {X=1000,Y=0,Z=0},
    model = {SetAttribute=function() end}, speciesId='chicken', qualityId='normal' }
local request = Request.Parse({action='zap', aim={x=1,y=0,z=0}, targetIds={'remote'}})
assert(request)
manager:OnCommand(player, request)
assert(session.animals.remote.health == 98)
print('SERVER DIAGNOSTIC: tier1 range=' .. Config.Weapons[1].range .. ', target distance=1000, health 100 -> ' .. session.animals.remote.health)
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
assert(stale==36)
local cached=fitting.FitTextLabel(label)
assert(cached==36)
print('TEXT DIAGNOSTIC: long text correct=8, old measurement overwrites=36, subsequent cache hit=36, measured width=180 > available40')
