-- 玩家存档第一版迁移：为旧资料补充独立经营档并保留通用资料和已有经营字段
--!strict
local replicatedStorage = game:GetService("ReplicatedStorage")
local FarmSaveData = require(replicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared"):WaitForChild("FarmSaveData"))

local function PlayerSaveInfoVersionUpdate1(playerSaveInfo: { dataVersion: number, farm: FarmSaveData.FarmSave? }): ()
	if playerSaveInfo.farm == nil then
		playerSaveInfo.farm = FarmSaveData.CreateDefault()
	end
	playerSaveInfo.dataVersion = 1
end

return PlayerSaveInfoVersionUpdate1
