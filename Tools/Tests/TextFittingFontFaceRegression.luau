-- 字体测量回归：保证参考工具栏斜体 FontFace 使用正确测量接口并释放测量参数
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local face = roblox.Font.new("rbxasset://fonts/families/FredokaOne.json", roblox.Enum.FontWeight.Regular, roblox.Enum.FontStyle.Italic)
local legacyCalls, faceCalls, released = 0, 0, 0
local service = {}
function service:GetTextSize(text, size, font)
	assert(font ~= roblox.Enum.Font.Unknown, "Unknown cannot use legacy API")
	legacyCalls += 1
	return roblox.Vector2.new(#text * size / 2, size)
end
function service:GetTextBoundsAsync(params)
	assert(params.Font == face, "must preserve actual italic face")
	faceCalls += 1
	return roblox.Vector2.new(#params.Text * params.Size / 2, params.Size)
end
local fitting = luau.load(fs.readFile("Scripts/ReplicatedStorage/Scripts/Client/UIManager/TextFitting.luau"), { environment = {
	game = { GetService = function() return service end },
	Instance = { new = function(class)
		assert(class == "GetTextBoundsParams")
		return { Destroy = function() released += 1 end }
	end },
	Enum = roblox.Enum, Vector2 = roblox.Vector2, math = math, string = string,
	setmetatable = setmetatable, assert = assert,
} })()
local available = roblox.Vector2.new(40, 24)
local italic = fitting.CalculateFittedFontSize("Lv.5", available, roblox.Enum.Font.Unknown, 36, 1, face)
assert(italic == 20 and faceCalls > 0 and legacyCalls == 0 and released == 1)
local normal = fitting.CalculateFittedFontSize("Lv.5", available, roblox.Enum.Font.FredokaOne, 36, 1)
assert(normal == 20 and legacyCalls > 0 and released == 1)
print("TextFittingFontFaceRegression passed: italic preserved, correct API, fitted bounds, cleanup, legacy compatibility")
