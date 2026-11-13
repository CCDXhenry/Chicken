-- 电击预测账本：按攻击编号撤销错误飘字，忽略重复、过期与已清理的回执
--!strict
export type Target = { id: string?, x: number, y: number, z: number, damage: number, isCooked: boolean, remainingHealth: number? }
export type Cancellations = { [string]: () -> () }
type Pending = { targets: { Target }, cancellations: Cancellations }
local Prediction = {}
Prediction.__index = Prediction
export type Tracker = typeof(setmetatable({} :: { nextId: number, pending: { [number]: Pending } }, Prediction))

function Prediction.new(): Tracker
	return setmetatable({ nextId = 0, pending = {} }, Prediction)
end

function Prediction.Begin(self: Tracker, targets: { Target }, cancellations: Cancellations): number
	self.nextId += 1
	self.pending[self.nextId] = { targets = targets, cancellations = cancellations }
	return self.nextId
end

function Prediction.Expire(self: Tracker, shotId: number): ()
	local pending = self.pending[shotId]
	if not pending then return end
	self.pending[shotId] = nil
	for _, cancel in pending.cancellations do cancel() end
end

function Prediction.Resolve(self: Tracker, shotId: number, accepted: boolean, targets: { Target }): { Target }
	local pending = self.pending[shotId]
	if not pending then return {} end
	self.pending[shotId] = nil
	local actual: { [string]: Target } = {}
	if accepted then
		for _, target in targets do
			if target.id then actual[target.id] = target end
		end
	end
	for _, predicted in pending.targets do
		local id = predicted.id
		local result = if id then actual[id] else nil
		if result and result.damage == predicted.damage and result.isCooked == predicted.isCooked then
			actual[id :: string] = nil
		else
			local cancel = if id then pending.cancellations[id] else nil
			if cancel then cancel() end
		end
	end
	local corrections: { Target } = {}
	for _, target in targets do
		if target.id and actual[target.id] then
			table.insert(corrections, target)
			actual[target.id] = nil
		end
	end
	return corrections
end

function Prediction.Clear(self: Tracker): ()
	for shotId in self.pending do self:Expire(shotId) end
end
return Prediction
