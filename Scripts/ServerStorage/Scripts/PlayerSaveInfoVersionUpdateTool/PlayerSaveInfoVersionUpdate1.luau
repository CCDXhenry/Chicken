-- 玩家存档版本迁移：保留现有版本转换契约
--!strict
local function PlayerSaveInfoVersionUpdate1(playerSaveInfo: any): ()
	playerSaveInfo.dataVersion = 1
end

return PlayerSaveInfoVersionUpdate1
