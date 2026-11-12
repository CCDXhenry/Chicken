-- 把拾取工具与鸡筐预制写入 Assets/Studio/CollectorBasketTemplates.rbxm
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local env = {
	Instance = roblox.Instance,
	Color3 = roblox.Color3,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Enum = roblox.Enum,
	table = table,
	string = string,
	math = math,
	tostring = tostring,
	assert = assert,
	error = error,
	type = type,
	ipairs = ipairs,
	pairs = pairs,
	print = print,
}
local install = luau.load(fs.readFile("Tools/Studio/CollectorBasketGeometry.luau"), { environment = env })()
local models = roblox.Instance.new("Folder")
models.Name = "Models"
local summary = install(models)
local serialized = roblox.serializeModel({ models })
fs.writeFile("Assets/Studio/CollectorBasketTemplates.rbxm", serialized)
print(summary)
print("Wrote Assets/Studio/CollectorBasketTemplates.rbxm")
