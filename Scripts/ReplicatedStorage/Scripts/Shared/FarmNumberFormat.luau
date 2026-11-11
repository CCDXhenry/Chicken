-- 农场数字展示：按一万起缩写与千公斤转吨规则格式化，计算继续使用原值
--!strict
local Format = {}
local Units = { "", "K", "M", "B", "T" }
local function OneDecimal(value: number): string
	local rounded = math.floor(value * 10 + 0.5) / 10
	return if rounded % 1 == 0 then string.format("%.0f", rounded) else string.format("%.1f", rounded)
end
function Format.Number(value: number): string
	assert(value == value and math.abs(value) < math.huge, "Expected finite number")
	local sign = if value < 0 then "-" else ""
	local magnitude = math.abs(value)
	if magnitude < 10000 then return sign .. string.format("%.0f", magnitude) end
	local unit = 2
	local scaled = magnitude / 1000
	while scaled >= 1000 and unit < #Units do scaled /= 1000; unit += 1 end
	if math.floor(scaled * 10 + 0.5) / 10 >= 1000 and unit < #Units then scaled /= 1000; unit += 1 end
	return sign .. OneDecimal(scaled) .. Units[unit]
end
function Format.Weight(value: number): string
	assert(value >= 0 and value < math.huge, "Expected nonnegative finite weight")
	if value < 1000 then return OneDecimal(value) .. " kg" end
	return OneDecimal(value / 1000) .. " t"
end
return Format
