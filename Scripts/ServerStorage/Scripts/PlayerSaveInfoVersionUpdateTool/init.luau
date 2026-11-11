-- 玩家存档版本更新入口：沿用现有版本迁移链
--!strict
local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerSaveInfoVersionUpdateTool = {}

local scripts = replicatedStorage:WaitForChild("Scripts")
local sharedScripts = scripts:WaitForChild("Shared")
local GameConfig = require(sharedScripts:FindFirstChild("GameConfig"))
local FarmSaveData = require(sharedScripts:WaitForChild("FarmSaveData"))
local PlayerSaveInfoVersionUpdate1 = require(script:WaitForChild("PlayerSaveInfoVersionUpdate1"))

local PlayerSaveInfoVersionUpdateFunctionList: { [number]: (playerSaveInfo: any) -> () } = {
	[1] = PlayerSaveInfoVersionUpdate1,
}

function PlayerSaveInfoVersionUpdateTool.Update(playerSaveInfo: any): (boolean, string?)
	if type(playerSaveInfo) ~= "table" or type(playerSaveInfo.dataVersion) ~= "number" then
		return false, "Invalid player save version"
	end
	local version = playerSaveInfo.dataVersion
	if version ~= version or version < 0 or version % 1 ~= 0 or version > GameConfig.PlayerSaveInfoDataVersion then
		return false, "Unsupported player save version"
	end
	for dataVersion: number = playerSaveInfo.dataVersion + 1, GameConfig.PlayerSaveInfoDataVersion do
		local success: boolean, errMsg: string? = pcall(function()
			PlayerSaveInfoVersionUpdateFunctionList[dataVersion](playerSaveInfo)
		end)
		if not success then
			warn("[PlayerSaveInfoVersionUpdateTool] Update", dataVersion, "failed:", errMsg)
			return false, tostring(errMsg)
		end
	end
	return FarmSaveData.Validate(playerSaveInfo.farm)
end

return PlayerSaveInfoVersionUpdateTool
