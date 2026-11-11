-- 玩家存档会话纯规则：以租约、存储修订号和操作标识拒绝旧会话、乱序写入与重复重试
--!strict
export type Metadata = { [string]: unknown }
type Lease = { owner: string?, expiresAt: number, revision: number, operationId: string? }
local Rules = {}
local function Read(metadata: Metadata): Lease?
	local owner, expires, revision, operation = metadata.ChickenSessionId, metadata.ChickenSessionExpires, metadata.ChickenSaveRevision, metadata.ChickenSaveOperation
	if revision == nil then revision = 0 end
	if type(revision) ~= "number" or revision ~= revision or revision < 0 or revision % 1 ~= 0 or revision >= 9007199254740991 then return nil end
	if owner ~= nil and (type(owner) ~= "string" or #owner == 0) then return nil end
	if owner ~= nil and (type(expires) ~= "number" or expires ~= expires or math.abs(expires) == math.huge) then return nil end
	if owner == nil and expires ~= nil then return nil end
	if operation ~= nil and type(operation) ~= "string" then return nil end
	local lease: Lease = { owner = owner :: string?, expiresAt = if type(expires) == "number" then expires else 0, revision = revision, operationId = operation :: string? }
	return lease
end
function Rules.Acquire(metadata: Metadata, token: string, now: number, duration: number): (Metadata?, string?)
	local lease = Read(metadata)
	if not lease then return nil, "invalidMetadata" end
	if lease.owner and lease.owner ~= token and lease.expiresAt > now then return nil, "sessionBusy" end
	local result = table.clone(metadata)
	result.ChickenSessionId, result.ChickenSessionExpires = token, now + duration
	result.ChickenSaveRevision, result.ChickenSaveOperation = lease.revision, nil
	return result, nil
end
function Rules.Write(metadata: Metadata, token: string, now: number, duration: number, expectedRevision: number, operationId: string): (Metadata?, boolean, string?)
	local lease = Read(metadata)
	if not lease then return nil, false, "invalidMetadata" end
	if lease.owner ~= token or lease.expiresAt <= now then return nil, false, "leaseLost" end
	local replay = lease.revision == expectedRevision + 1 and lease.operationId == operationId
	if not replay and lease.revision ~= expectedRevision then return nil, false, "staleRevision" end
	local result = table.clone(metadata)
	result.ChickenSessionExpires = now + duration
	result.ChickenSaveRevision = if replay then lease.revision else lease.revision + 1
	result.ChickenSaveOperation = operationId
	return result, replay, nil
end
function Rules.Release(metadata: Metadata, token: string): Metadata?
	local lease = Read(metadata)
	if not lease or lease.owner ~= token then return nil end
	local result = table.clone(metadata)
	result.ChickenSessionId, result.ChickenSessionExpires, result.ChickenSaveOperation = nil, nil, nil
	return result
end
function Rules.GetRevision(metadata: Metadata): number?
	local lease = Read(metadata)
	return if lease then lease.revision else nil
end
return Rules
