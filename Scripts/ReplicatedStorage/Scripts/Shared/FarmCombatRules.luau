-- 电击纯规则：按射界与距离选首目标，逐跳最近邻或扇区共享总伤害，同发不重复命中
--!strict
local Config = if script then require(script.Parent:WaitForChild("FarmEconomyConfig")) else require("./FarmEconomyConfig")
export type Candidate = { id: string, x: number, y: number, z: number, health: number }
export type Hit = { id: string, damage: number }
local Rules = {}
local function Distance(a: Candidate, x: number, y: number, z: number): number
	return math.sqrt((a.x - x)^2 + (a.y - y)^2 + (a.z - z)^2)
end
function Rules.ResolveShot(tier: number, level: number, x: number, y: number, z: number, directionX: number?, directionZ: number?, candidates: { Candidate }): { Hit }
	local weapon = Config.Weapons[tier]
	local budget = Config.GetDamage(tier, level)
	local isOmni = weapon.angleDegrees == 360 or directionX == nil or directionZ == nil
	local normX, normZ = 0, 1
	if not isOmni and directionX ~= nil and directionZ ~= nil then
		local length = math.sqrt(directionX^2 + directionZ^2)
		if length > 0 and length < math.huge then
			normX, normZ = directionX / length, directionZ / length
		else
			isOmni = true
		end
	end
	local initial: { Candidate } = {}
	for _, target in candidates do
		local dx, dz = target.x - x, target.z - z
		local horizontal = math.sqrt(dx^2 + dz^2)
		local dot = if horizontal > 0 then (dx * normX + dz * normZ) / horizontal else 1
		local inAngle = isOmni or dot >= math.cos(math.rad(weapon.angleDegrees / 2))
		if target.health > 0 and Distance(target, x, y, z) <= weapon.range and inAngle then table.insert(initial, target) end
	end
	table.sort(initial, function(a, b)
		local da, db = Distance(a, x, y, z), Distance(b, x, y, z)
		return if da == db then a.id < b.id else da < db
	end)
	local current: Candidate? = initial[1]
	local visited: { [string]: boolean } = {}
	local hits: { Hit } = {}
	while current and budget > 0 and #hits < weapon.maximumTargets do
		visited[current.id] = true
		local damage = math.min(current.health, budget)
		table.insert(hits, { id = current.id, damage = damage })
		budget -= damage
		if weapon.mode == "single" then break end
		if weapon.mode == "chain" then
			local closest: Candidate?
			local closestDistance = math.huge
			for _, candidate in candidates do
				local distance = Distance(candidate, current.x, current.y, current.z)
				if not visited[candidate.id] and candidate.health > 0 and distance <= weapon.chainRange and (distance < closestDistance or (distance == closestDistance and closest and candidate.id < closest.id)) then
					closest, closestDistance = candidate, distance
				end
			end
			current = closest
		else
			current = initial[#hits + 1]
		end
	end
	return hits
end
return Rules
