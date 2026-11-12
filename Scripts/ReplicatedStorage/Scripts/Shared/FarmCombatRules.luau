-- 电击纯规则：客户端按射界选目标；单体只打一只，连锁溢出后跳邻近，扇形平分一发总伤害
--!strict
local Config = if script then require(script.Parent:WaitForChild("FarmEconomyConfig")) else require("./FarmEconomyConfig")
export type Candidate = { id: string, x: number, y: number, z: number, health: number }
export type OrderedTarget = { id: string, health: number }
export type Hit = { id: string, damage: number }
local Rules = {}
local function Distance(a: Candidate, x: number, y: number, z: number): number
	return math.sqrt((a.x - x)^2 + (a.y - y)^2 + (a.z - z)^2)
end

-- 按调用方已经排好的顺序结算。不读取坐标，服务端因此不会用距离或射界改写客户端目标。
function Rules.ApplyOrderedHits(tier: number, level: number, ordered: { OrderedTarget }): { Hit }
	local weapon = Config.Weapons[tier]
	local budget = Config.GetDamage(tier, level)
	local hits: { Hit } = {}
	local seen: { [string]: boolean } = {}
	local accepted: { OrderedTarget } = {}
	for _, target in ordered do
		if target.health > 0 and not seen[target.id] then
			seen[target.id] = true
			table.insert(accepted, target)
			if #accepted >= weapon.maximumTargets then
				break
			end
		end
	end
	if #accepted == 0 or budget <= 0 then
		return hits
	end
	if weapon.mode == "cone" then
		local count = #accepted
		local base = math.floor(budget / count)
		local remainder = budget % count
		for index, target in accepted do
			local share = base + (if index <= remainder then 1 else 0)
			local damage = math.min(target.health, share)
			if damage > 0 then
				table.insert(hits, { id = target.id, damage = damage })
			end
		end
		return hits
	end
	for _, target in accepted do
		if budget <= 0 then
			break
		end
		local damage = math.min(target.health, budget)
		table.insert(hits, { id = target.id, damage = damage })
		budget -= damage
		if weapon.mode == "single" then
			break
		end
	end
	return hits
end

function Rules.ResolveShot(tier: number, level: number, x: number, y: number, z: number, directionX: number?, directionZ: number?, candidates: { Candidate }): { Hit }
	local weapon = Config.Weapons[tier]
	local isOmni = weapon.angleDegrees == 360
	local normX, normZ = 0, 1
	if not isOmni then
		if directionX == nil or directionZ == nil then
			return {}
		end
		local length = math.sqrt(directionX^2 + directionZ^2)
		if length ~= length or length <= 0 or length == math.huge then
			return {}
		end
		normX, normZ = directionX / length, directionZ / length
	end
	local initial: { Candidate } = {}
	for _, target in candidates do
		local dx, dz = target.x - x, target.z - z
		local horizontal = math.sqrt(dx^2 + dz^2)
		local dot = if horizontal > 0 then (dx * normX + dz * normZ) / horizontal else 1
		local inAngle = isOmni or dot >= math.cos(math.rad(weapon.angleDegrees / 2))
		if target.health > 0 and Distance(target, x, y, z) <= weapon.range and inAngle then
			table.insert(initial, target)
		end
	end
	table.sort(initial, function(a, b)
		local da, db = Distance(a, x, y, z), Distance(b, x, y, z)
		return if da == db then a.id < b.id else da < db
	end)
	local ordered: { OrderedTarget } = {}
	if weapon.mode == "cone" then
		for index, target in initial do
			if index > weapon.maximumTargets then
				break
			end
			table.insert(ordered, { id = target.id, health = target.health })
		end
		return Rules.ApplyOrderedHits(tier, level, ordered)
	end
	local current: Candidate? = initial[1]
	local visited: { [string]: boolean } = {}
	while current ~= nil and #ordered < weapon.maximumTargets do
		local active = current
		visited[active.id] = true
		table.insert(ordered, { id = active.id, health = active.health })
		if weapon.mode == "single" then
			break
		end
		local closest: Candidate? = nil
		local closestDistance = math.huge
		for _, candidate in candidates do
			local distance = Distance(candidate, active.x, active.y, active.z)
			if not visited[candidate.id] and candidate.health > 0 and distance <= weapon.chainRange and (distance < closestDistance or (distance == closestDistance and closest and candidate.id < closest.id)) then
				closest, closestDistance = candidate, distance
			end
		end
		current = closest
	end
	return Rules.ApplyOrderedHits(tier, level, ordered)
end
return Rules
