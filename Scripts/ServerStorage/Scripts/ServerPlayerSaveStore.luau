-- 玩家存档业务封装：沿用真实 PlayerInfo 数据仓库，以条件更新租约串行保存完整玩家快照
--!strict
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local DataStoreTool = require(ServerStorage:WaitForChild("Core"):WaitForChild("Scripts"):WaitForChild("DataStoreTool"))
local Shared = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local FarmSave = require(Shared:WaitForChild("FarmSaveData"))
local Rules = require(script.Parent:WaitForChild("PlayerSaveLeaseRules"))
type Record = { token: string, revision: number, expiresAt: number, lastChangeRevision: number, busy: boolean, closing: boolean }
local Store = {}
Store.__index = Store
export type ServerPlayerSaveStore = typeof(setmetatable({} :: { dataStore: GlobalDataStore, records: { [number]: Record } }, Store))
local LeaseSeconds = 120 -- 自动保存 30 秒；超过 120 秒未成功续租即冻结并退出，避免旧服继续经营

local function GetMetadata(keyInfo: DataStoreKeyInfo?): Rules.Metadata
	return if keyInfo then keyInfo:GetMetadata() else {}
end
local function GetUserIds(keyInfo: DataStoreKeyInfo?, userId: number): { number }
	if keyInfo then return keyInfo:GetUserIds() end
	-- Studio 多人模拟使用负数测试 ID，不把它们登记为真实用户关联。
	return if userId > 0 then { userId } else {}
end
function Store.new(dataStore: GlobalDataStore): ServerPlayerSaveStore
	return setmetatable({ dataStore = dataStore, records = {} }, Store)
end
function Store.IsActive(self: ServerPlayerSaveStore, userId: number): boolean
	local record = self.records[userId]
	return record ~= nil and not record.closing and record.expiresAt > os.time()
end
function Store.IsBusy(self: ServerPlayerSaveStore, userId: number): boolean
	local record = self.records[userId]
	return record ~= nil and record.busy
end
function Store.Acquire(self: ServerPlayerSaveStore, userId: number): (boolean, unknown, string?)
	if self.records[userId] then return false, nil, "alreadyLoading" end
	local record: Record = { token = HttpService:GenerateGUID(false), revision = 0, expiresAt = 0, lastChangeRevision = -1, busy = true, closing = false }
	self.records[userId] = record
	local default = GameConfig.CreateDefaultPlayerSaveInfo()
	local accepted = false
	local reason: string?
	local storedMetadata: Rules.Metadata?
	local function Transform(current: unknown, keyInfo: DataStoreKeyInfo?): (unknown, { number }?, Rules.Metadata?)
		accepted = false
		if record.closing then reason = "closedWhileLoading"; return nil end
		local metadata, errorReason = Rules.Acquire(GetMetadata(keyInfo), record.token, os.time(), LeaseSeconds)
		if not metadata then reason = errorReason; return nil end
		accepted, storedMetadata = true, metadata
		return if current == nil then default else current, GetUserIds(keyInfo, userId), metadata
	end
	local success, value = DataStoreTool.SafeUpdate(self.dataStore, tostring(userId), Transform)
	record.busy = false
	if success and accepted and storedMetadata then
		record.revision = Rules.GetRevision(storedMetadata) or 0
		record.expiresAt = storedMetadata.ChickenSessionExpires :: number
		return true, value, nil
	end
	return false, nil, if success then reason or "acquireRejected" else "storageFailure"
end
function Store.Save(self: ServerPlayerSaveStore, userId: number, snapshot: GameConfig.PlayerSaveInfo, changeRevision: number): (boolean, string?)
	local record = self.records[userId]
	if not record then return false, "leaseLost" end
	while record.busy do task.wait() end
	if record.closing then return false, "leaseLost" end
	if changeRevision < record.lastChangeRevision then return true, "superseded" end
	local valid, invalidReason = FarmSave.Validate(snapshot.farm)
	if not valid then return false, invalidReason end
	record.busy = true
	local expectedRevision, operationId = record.revision, HttpService:GenerateGUID(false)
	local accepted, replayed = false, false
	local reason: string?
	local storedMetadata: Rules.Metadata?
	local function Transform(current: unknown, keyInfo: DataStoreKeyInfo?): (unknown, { number }?, Rules.Metadata?)
		accepted = false
		local metadata, replay, errorReason = Rules.Write(GetMetadata(keyInfo), record.token, os.time(), LeaseSeconds, expectedRevision, operationId)
		if not metadata then reason = errorReason; return nil end
		accepted, replayed, storedMetadata = true, replay, metadata
		return if replayed then current else snapshot, GetUserIds(keyInfo, userId), metadata
	end
	local success = DataStoreTool.SafeUpdate(self.dataStore, tostring(userId), Transform)
	record.busy = false
	if success and accepted and storedMetadata then
		record.revision = Rules.GetRevision(storedMetadata) or record.revision
		record.expiresAt = storedMetadata.ChickenSessionExpires :: number
		record.lastChangeRevision = math.max(record.lastChangeRevision, changeRevision)
		return true, nil
	end
	if reason == "leaseLost" or reason == "staleRevision" or reason == "invalidMetadata" then record.expiresAt = 0 end
	return false, if success then reason or "writeRejected" else "storageFailure"
end
function Store.Release(self: ServerPlayerSaveStore, userId: number): boolean
	local record = self.records[userId]
	if not record then return true end
	record.closing = true
	while record.busy do task.wait() end
	local function Transform(current: unknown, keyInfo: DataStoreKeyInfo?): (unknown, { number }?, Rules.Metadata?)
		local metadata = Rules.Release(GetMetadata(keyInfo), record.token)
		if not metadata then return nil end
		return current, GetUserIds(keyInfo, userId), metadata
	end
	local success = DataStoreTool.SafeUpdate(self.dataStore, tostring(userId), Transform)
	self.records[userId] = nil
	return success
end
return Store
