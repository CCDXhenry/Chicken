-- 八人农场村落配置：集中维护地块数量、排列、公共道路和牧场活动边界
--!strict
local Config = {
	Capacity = 8,
	RowZ = { -192, -64, 64, 192 },
	ColumnX = 80,
	RoadWidth = 24,
	RoadLength = 520,
	PastureMinimumX = -23,
	PastureMaximumX = 23,
	PastureMinimumZ = -23,
	PastureMaximumZ = 18,
}
function Config.IsPlotId(id: string): boolean
	local index = tonumber(id:match("^Plot(%d%d)$"))
	return index ~= nil and index >= 1 and index <= Config.Capacity
end
return Config
