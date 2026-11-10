--!strict
--!native
-- Ported from A* Pathfinding Project Core/RVO/RVOAgent.cs (Pathfinding.RVO.Sampled.Agent).
local RVOObstacle = require(script.Parent:FindFirstChild("RVOObstacle"))
local AstarMath = require(script.Parent:FindFirstChild("AstarMath"))

type Vector2 = AstarMath.Vector2
type ObstacleVertex = RVOObstacle.ObstacleVertex

-- From Pathfinding.RVO (declared in RVOCoreSimulator.cs); inlined to avoid circular require.
local MovementPlaneXY: number = 1
local RVOLayerDefaultAgent: number = bit32.lshift(1, 0)
local RVOLayerAll: number = 0x7FFFFFFF
local DesiredVelocityWeight: number = 0.1
local VectorEpsilon: number = 1e-5
local TraceMaxIterations: number = 50

local Agent = {}
Agent.__index = Agent

export type VO = {
	line1: Vector2,
	line2: Vector2,
	dir1: Vector2,
	dir2: Vector2,
	cutoffLine: Vector2,
	cutoffDir: Vector2,
	circleCenter: Vector2,
	colliding: boolean,
	radius: number,
	weightFactor: number,
	weightBonus: number,
	segmentStart: Vector2,
	segmentEnd: Vector2,
	segment: boolean,
}

export type VOBuffer = {
	buffer: { VO },
	length: number,
}

export type WorkerContext = {
	vos: VOBuffer,
}

-- Avoid circular typeof(setmetatable) self-reference; fields use any for linked agents.
export type AgentObject = {
	radius: number,
	height: number,
	desiredSpeed: number,
	maxSpeed: number,
	agentTimeHorizon: number,
	obstacleTimeHorizon: number,
	locked: boolean,
	layer: number,
	collidesWith: number,
	maxNeighbours: number,
	position: Vector2,
	elevationCoordinate: number,
	currentVelocity: Vector2,
	desiredTargetPointInVelocitySpace: Vector2,
	desiredVelocity: Vector2,
	nextTargetPoint: Vector2,
	nextDesiredSpeed: number,
	nextMaxSpeed: number,
	collisionNormal: Vector2,
	manuallyControlled: boolean,
	Position: Vector2,
	ElevationCoordinate: number,
	CalculatedTargetPoint: Vector2,
	CalculatedSpeed: number,
	Locked: boolean,
	Radius: number,
	Height: number,
	AgentTimeHorizon: number,
	ObstacleTimeHorizon: number,
	MaxNeighbours: number,
	NeighbourCount: number,
	Layer: number,
	CollidesWith: number,
	Priority: number,
	PreCalculationCallback: (() -> ())?,
	next: any,
	calculatedSpeed: number,
	calculatedTargetPoint: Vector2,
	simulator: any,
	neighbours: { any },
	neighbourDists: { number },
	obstaclesBuffered: { ObstacleVertex },
	obstacles: { ObstacleVertex },
	SetTarget: (self: AgentObject, targetPoint: Vector2, desiredSpeed: number, maxSpeed: number) -> (),
	SetCollisionNormal: (self: AgentObject, normal: Vector2) -> (),
	ForceSetVelocity: (self: AgentObject, velocity: Vector2) -> (),
	BufferSwitch: (self: AgentObject) -> (),
	PreCalculation: (self: AgentObject) -> (),
	PostCalculation: (self: AgentObject) -> (),
	CalculateNeighbours: (self: AgentObject) -> (),
	InsertAgentNeighbour: (self: AgentObject, otherAgent: AgentObject, rangeSq: number) -> number,
	CalculateVelocity: (self: AgentObject, context: WorkerContext) -> (),
}

local function Sqr(x: number): number
	return x * x
end

local function SetXY(vector2: Vector2, x: number, y: number)
	vector2.x = x
	vector2.y = y
end

local function SignedDistanceFromLineXY(ax: number, ay: number, dirX: number, dirY: number, px: number, py: number): number
	return (px - ax) * dirY - dirX * (py - ay)
end

local function ClosestPointOnSegmentXY(ax: number, ay: number, bx: number, by: number, px: number, py: number): (number, number)
	local dx: number = bx - ax
	local dy: number = by - ay
	local sqrMagn: number = dx * dx + dy * dy
	if sqrMagn <= 0.000001 then
		return ax, ay
	end
	local factor: number = math.clamp(((px - ax) * dx + (py - ay) * dy) / sqrMagn, 0, 1)
	return ax + dx * factor, ay + dy * factor
end

local function NormalizeXY(x: number, y: number): (number, number)
	local magnitude: number = math.sqrt(x * x + y * y)
	if magnitude < VectorEpsilon then
		return 0, 0
	end
	return x / magnitude, y / magnitude
end

local function NormalizeWithMagnitudeXY(x: number, y: number): (number, number, number)
	local magnitude: number = math.sqrt(x * x + y * y)
	if magnitude > VectorEpsilon then
		return x / magnitude, y / magnitude, magnitude
	end
	return 0, 0, magnitude
end

local function CreateEmptyVO(): VO
	return {
		line1 = { x = 0, y = 0 },
		line2 = { x = 0, y = 0 },
		dir1 = { x = 0, y = 0 },
		dir2 = { x = 0, y = 0 },
		cutoffLine = { x = 0, y = 0 },
		cutoffDir = { x = 0, y = 0 },
		circleCenter = { x = 0, y = 0 },
		colliding = false,
		radius = 0,
		weightFactor = 1,
		weightBonus = 0,
		segmentStart = { x = 0, y = 0 },
		segmentEnd = { x = 0, y = 0 },
		segment = false,
	}
end

function Agent.CreateVOBuffer(initialCapacity: number): VOBuffer
	return {
		buffer = table.create(initialCapacity),
		length = 0,
	}
end

function Agent.ClearVOBuffer(voBuffer: VOBuffer)
	voBuffer.length = 0
end

local function AcquireVO(voBuffer: VOBuffer): VO
	voBuffer.length += 1
	local vo: VO? = voBuffer.buffer[voBuffer.length]
	if vo == nil then
		vo = CreateEmptyVO()
		assert(vo)
		voBuffer.buffer[voBuffer.length] = vo
	end
	assert(vo)
	return vo
end

function Agent.CreateWorkerContext(): WorkerContext
	return {
		vos = Agent.CreateVOBuffer(16),
	}
end

function Agent.SignedDistanceFromLine(a: Vector2, dir: Vector2, p: Vector2): number
	return SignedDistanceFromLineXY(a.x, a.y, dir.x, dir.y, p.x, p.y)
end

local function FillAgentVO(
	vo: VO,
	centerX: number,
	centerY: number,
	offsetX: number,
	offsetY: number,
	radius: number,
	inverseDt: number,
	inverseDeltaTime: number
)
	vo.weightBonus = 0
	SetXY(vo.circleCenter, centerX * inverseDt + offsetX, centerY * inverseDt + offsetY)
	local radiusSq: number = radius * radius
	vo.weightFactor = 4 * math.exp(-Sqr((centerX * centerX + centerY * centerY) / radiusSq)) + 1
	local centerMagnitude: number = math.sqrt(centerX * centerX + centerY * centerY)
	if centerMagnitude < radius then
		vo.colliding = true
		local nx: number, ny: number = NormalizeXY(centerX, centerY)
		local lineScale: number = (centerMagnitude - radius - 0.001) * 0.3 * inverseDeltaTime
		local line1X: number = nx * lineScale
		local line1Y: number = ny * lineScale
		local dirX: number, dirY: number = NormalizeXY(line1Y, -line1X)
		SetXY(vo.dir1, dirX, dirY)
		SetXY(vo.line1, line1X + offsetX, line1Y + offsetY)
		SetXY(vo.cutoffDir, 0, 0)
		SetXY(vo.cutoffLine, 0, 0)
		SetXY(vo.dir2, 0, 0)
		SetXY(vo.line2, 0, 0)
		vo.radius = 0
	else
		vo.colliding = false
		local scaledCenterX: number = centerX * inverseDt
		local scaledCenterY: number = centerY * inverseDt
		local scaledRadius: number = radius * inverseDt
		local globalCenterX: number = scaledCenterX + offsetX
		local globalCenterY: number = scaledCenterY + offsetY
		local scaledCenterAbs: number = math.sqrt(scaledCenterX * scaledCenterX + scaledCenterY * scaledCenterY)
		local cutoffDistance: number = scaledCenterAbs - scaledRadius + 0.001
		local scaledNx: number, scaledNy: number = NormalizeXY(scaledCenterX, scaledCenterY)
		local cutoffLineX: number = scaledNx * cutoffDistance
		local cutoffLineY: number = scaledNy * cutoffDistance
		local cutoffDirX: number, cutoffDirY: number = NormalizeXY(-cutoffLineY, cutoffLineX)
		SetXY(vo.cutoffDir, cutoffDirX, cutoffDirY)
		SetXY(vo.cutoffLine, cutoffLineX + offsetX, cutoffLineY + offsetY)
		local alpha: number = math.atan2(-scaledCenterY, -scaledCenterX)
		local delta: number = math.abs(math.acos(math.clamp(scaledRadius / scaledCenterAbs, -1, 1)))
		vo.radius = scaledRadius
		local line1X: number = math.cos(alpha + delta)
		local line1Y: number = math.sin(alpha + delta)
		SetXY(vo.dir1, line1Y, -line1X)
		local line2X: number = math.cos(alpha - delta)
		local line2Y: number = math.sin(alpha - delta)
		SetXY(vo.dir2, line2Y, -line2X)
		SetXY(vo.line1, line1X * scaledRadius + globalCenterX, line1Y * scaledRadius + globalCenterY)
		SetXY(vo.line2, line2X * scaledRadius + globalCenterX, line2Y * scaledRadius + globalCenterY)
	end
	SetXY(vo.segmentStart, 0, 0)
	SetXY(vo.segmentEnd, 0, 0)
	vo.segment = false
end

local function FillSegmentObstacleVO(
	vo: VO,
	segmentStartX: number,
	segmentStartY: number,
	segmentEndX: number,
	segmentEndY: number,
	offsetX: number,
	offsetY: number,
	radius: number,
	inverseDt: number,
	inverseDeltaTime: number
)
	vo.weightFactor = 1
	vo.weightBonus = math.max(radius, 1) * 40
	local closestX: number, closestY: number = ClosestPointOnSegmentXY(segmentStartX, segmentStartY, segmentEndX, segmentEndY, 0, 0)
	local closestMagnitude: number = math.sqrt(closestX * closestX + closestY * closestY)
	if closestMagnitude <= radius then
		vo.colliding = true
		local nx: number, ny: number = NormalizeXY(closestX, closestY)
		local lineScale: number = (closestMagnitude - radius) * 0.3 * inverseDeltaTime
		local line1X: number = nx * lineScale
		local line1Y: number = ny * lineScale
		local dirX: number, dirY: number = NormalizeXY(line1Y, -line1X)
		SetXY(vo.dir1, dirX, dirY)
		SetXY(vo.line1, line1X + offsetX, line1Y + offsetY)
		SetXY(vo.cutoffDir, 0, 0)
		SetXY(vo.cutoffLine, 0, 0)
		SetXY(vo.dir2, 0, 0)
		SetXY(vo.line2, 0, 0)
		vo.radius = 0
		SetXY(vo.segmentStart, 0, 0)
		SetXY(vo.segmentEnd, 0, 0)
		vo.segment = false
	else
		vo.colliding = false
		local scaledStartX: number = segmentStartX * inverseDt
		local scaledStartY: number = segmentStartY * inverseDt
		local scaledEndX: number = segmentEndX * inverseDt
		local scaledEndY: number = segmentEndY * inverseDt
		local scaledRadius: number = radius * inverseDt
		local cutoffTx: number, cutoffTy: number = NormalizeXY(scaledEndX - scaledStartX, scaledEndY - scaledStartY)
		SetXY(vo.cutoffDir, cutoffTx, cutoffTy)
		SetXY(vo.cutoffLine, scaledStartX + -cutoffTy * scaledRadius + offsetX, scaledStartY + cutoffTx * scaledRadius + offsetY)
		local startSqrMagnitude: number = scaledStartX * scaledStartX + scaledStartY * scaledStartY
		if startSqrMagnitude <= 0.000001 then
			startSqrMagnitude = 0.000001
		end
		local startCross: number = math.sqrt(math.max(0, startSqrMagnitude - scaledRadius * scaledRadius))
		local complex1X: number = scaledStartX * scaledRadius - scaledStartY * startCross
		local complex1Y: number = scaledStartX * startCross + scaledStartY * scaledRadius
		local normal1X: number = -complex1X / startSqrMagnitude
		local normal1Y: number = -complex1Y / startSqrMagnitude
		local endSqrMagnitude: number = scaledEndX * scaledEndX + scaledEndY * scaledEndY
		if endSqrMagnitude <= 0.000001 then
			endSqrMagnitude = 0.000001
		end
		local endCross: number = math.sqrt(math.max(0, endSqrMagnitude - scaledRadius * scaledRadius))
		local complex2X: number = scaledEndX * scaledRadius - scaledEndY * -endCross
		local complex2Y: number = scaledEndX * -endCross + scaledEndY * scaledRadius
		local normal2X: number = -complex2X / endSqrMagnitude
		local normal2Y: number = -complex2Y / endSqrMagnitude
		SetXY(vo.line1, scaledStartX + normal1X * scaledRadius + offsetX, scaledStartY + normal1Y * scaledRadius + offsetY)
		SetXY(vo.line2, scaledEndX + normal2X * scaledRadius + offsetX, scaledEndY + normal2Y * scaledRadius + offsetY)
		SetXY(vo.dir1, normal1Y, -normal1X)
		SetXY(vo.dir2, normal2Y, -normal2X)
		SetXY(vo.segmentStart, scaledStartX, scaledStartY)
		SetXY(vo.segmentEnd, scaledEndX, scaledEndY)
		vo.radius = scaledRadius
		vo.segment = true
	end
end

local function VOGradient(vo: VO, px: number, py: number): (number, number, number)
	if vo.colliding then
		local l1: number = SignedDistanceFromLineXY(vo.line1.x, vo.line1.y, vo.dir1.x, vo.dir1.y, px, py)
		if l1 >= 0 then
			return -vo.dir1.y, vo.dir1.x, l1
		end
		return 0, 0, 0
	end
	local det3: number = SignedDistanceFromLineXY(vo.cutoffLine.x, vo.cutoffLine.y, vo.cutoffDir.x, vo.cutoffDir.y, px, py)
	if det3 <= 0 then
		return 0, 0, 0
	end
	local det1: number = SignedDistanceFromLineXY(vo.line1.x, vo.line1.y, vo.dir1.x, vo.dir1.y, px, py)
	local det2: number = SignedDistanceFromLineXY(vo.line2.x, vo.line2.y, vo.dir2.x, vo.dir2.y, px, py)
	if det1 >= 0 and det2 >= 0 then
		if (px - vo.line1.x) * vo.dir1.x + (py - vo.line1.y) * vo.dir1.y > 0 and (px - vo.line2.x) * vo.dir2.x + (py - vo.line2.y) * vo.dir2.y < 0 then
			if vo.segment then
				if det3 < vo.radius then
					local closestX: number, closestY: number =
						ClosestPointOnSegmentXY(vo.segmentStart.x, vo.segmentStart.y, vo.segmentEnd.x, vo.segmentEnd.y, px, py)
					local nx: number, ny: number, distToCenter: number = NormalizeWithMagnitudeXY(px - closestX, py - closestY)
					return nx, ny, vo.radius - distToCenter
				end
			else
				local nx: number, ny: number, distToCenter: number = NormalizeWithMagnitudeXY(px - vo.circleCenter.x, py - vo.circleCenter.y)
				return nx, ny, vo.radius - distToCenter
			end
		end
		if vo.segment and det3 < det1 and det3 < det2 then
			return -vo.cutoffDir.y, vo.cutoffDir.x, det3
		end
		if det1 < det2 then
			return -vo.dir1.y, vo.dir1.x, det1
		end
		return -vo.dir2.y, vo.dir2.x, det2
	end
	return 0, 0, 0
end

local function VOScaledGradient(vo: VO, px: number, py: number): (number, number, number)
	local gx: number, gy: number, weight: number = VOGradient(vo, px, py)
	if weight > 0 then
		local scale: number = 2 * vo.weightFactor
		gx *= scale
		gy *= scale
		weight = weight * scale + 1 + vo.weightBonus
	end
	return gx, gy, weight
end

function Agent.new(pos: Vector2, elevationCoordinate: number): AgentObject
	local self = setmetatable({
		radius = 5,
		height = 5,
		desiredSpeed = 0,
		maxSpeed = 0,
		agentTimeHorizon = 2,
		obstacleTimeHorizon = 2,
		locked = false,
		layer = RVOLayerDefaultAgent,
		collidesWith = RVOLayerAll,
		maxNeighbours = 10,
		position = { x = pos.x, y = pos.y },
		elevationCoordinate = elevationCoordinate,
		currentVelocity = AstarMath.Zero(),
		desiredTargetPointInVelocitySpace = AstarMath.Zero(),
		desiredVelocity = AstarMath.Zero(),
		nextTargetPoint = { x = pos.x, y = pos.y },
		nextDesiredSpeed = 0,
		nextMaxSpeed = 0,
		collisionNormal = AstarMath.Zero(),
		manuallyControlled = false,
		Position = { x = pos.x, y = pos.y },
		ElevationCoordinate = elevationCoordinate,
		CalculatedTargetPoint = { x = pos.x, y = pos.y },
		CalculatedSpeed = 0,
		Locked = false,
		Radius = 5,
		Height = 5,
		AgentTimeHorizon = 2,
		ObstacleTimeHorizon = 2,
		MaxNeighbours = 10,
		NeighbourCount = 0,
		Layer = RVOLayerDefaultAgent,
		CollidesWith = RVOLayerAll,
		Priority = 0.5,
		PreCalculationCallback = nil,
		next = nil,
		calculatedSpeed = 0,
		calculatedTargetPoint = { x = pos.x, y = pos.y },
		simulator = nil,
		neighbours = {},
		neighbourDists = {},
		obstaclesBuffered = {},
		obstacles = {},
	}, Agent) :: any
	local agent: AgentObject = self :: AgentObject
	agent:SetTarget(pos, 0, 0)
	return agent
end

function Agent.SetTarget(self: AgentObject, targetPoint: Vector2, desiredSpeed: number, maxSpeed: number)
	maxSpeed = math.max(maxSpeed, 0)
	desiredSpeed = math.min(math.max(desiredSpeed, 0), maxSpeed)
	SetXY(self.nextTargetPoint, targetPoint.x, targetPoint.y)
	self.nextDesiredSpeed = desiredSpeed
	self.nextMaxSpeed = maxSpeed
end

function Agent.SetCollisionNormal(self: AgentObject, normal: Vector2)
	SetXY(self.collisionNormal, normal.x, normal.y)
end

function Agent.ForceSetVelocity(self: AgentObject, velocity: Vector2)
	local forcedTarget: Vector2 = AstarMath.Add(self.position, AstarMath.Multiply(velocity, 1000))
	self.nextTargetPoint = forcedTarget
	self.CalculatedTargetPoint = forcedTarget
	local speed: number = AstarMath.Abs(velocity)
	self.nextDesiredSpeed = speed
	self.CalculatedSpeed = speed
	self.manuallyControlled = true
end

function Agent.BufferSwitch(self: AgentObject)
	self.radius = self.Radius
	self.height = self.Height
	self.maxSpeed = self.nextMaxSpeed
	self.desiredSpeed = self.nextDesiredSpeed
	self.agentTimeHorizon = self.AgentTimeHorizon
	self.obstacleTimeHorizon = self.ObstacleTimeHorizon
	self.maxNeighbours = self.MaxNeighbours
	self.locked = self.Locked and not self.manuallyControlled
	SetXY(self.position, self.Position.x, self.Position.y)
	self.elevationCoordinate = self.ElevationCoordinate
	self.collidesWith = self.CollidesWith
	self.layer = self.Layer
	if self.locked then
		SetXY(self.desiredTargetPointInVelocitySpace, self.position.x, self.position.y)
		SetXY(self.desiredVelocity, 0, 0)
		SetXY(self.currentVelocity, 0, 0)
	else
		SetXY(self.desiredTargetPointInVelocitySpace, self.nextTargetPoint.x - self.position.x, self.nextTargetPoint.y - self.position.y)
		local dirX: number, dirY: number = NormalizeXY(self.CalculatedTargetPoint.x - self.position.x, self.CalculatedTargetPoint.y - self.position.y)
		SetXY(self.currentVelocity, dirX * self.CalculatedSpeed, dirY * self.CalculatedSpeed)
		local desiredDirX: number, desiredDirY: number = NormalizeXY(self.desiredTargetPointInVelocitySpace.x, self.desiredTargetPointInVelocitySpace.y)
		SetXY(self.desiredVelocity, desiredDirX * self.desiredSpeed, desiredDirY * self.desiredSpeed)
		local collisionNormalX: number = self.collisionNormal.x
		local collisionNormalY: number = self.collisionNormal.y
		if collisionNormalX * collisionNormalX + collisionNormalY * collisionNormalY > 0 then
			local nx: number, ny: number = NormalizeXY(collisionNormalX, collisionNormalY)
			local dot: number = self.currentVelocity.x * nx + self.currentVelocity.y * ny
			if dot < 0 then
				SetXY(self.currentVelocity, self.currentVelocity.x - nx * dot, self.currentVelocity.y - ny * dot)
			end
			SetXY(self.collisionNormal, 0, 0)
		end
	end
end

function Agent.PreCalculation(self: AgentObject)
	if self.PreCalculationCallback ~= nil then
		self.PreCalculationCallback()
	end
end

function Agent.PostCalculation(self: AgentObject)
	if not self.manuallyControlled then
		SetXY(self.CalculatedTargetPoint, self.calculatedTargetPoint.x, self.calculatedTargetPoint.y)
		self.CalculatedSpeed = self.calculatedSpeed
	end
	local tmp: { ObstacleVertex } = self.obstaclesBuffered
	self.obstaclesBuffered = self.obstacles
	self.obstacles = tmp
	self.manuallyControlled = false
end

function Agent.CalculateNeighbours(self: AgentObject)
	table.clear(self.neighbours)
	table.clear(self.neighbourDists)
	if self.MaxNeighbours > 0 and not self.locked and self.simulator ~= nil then
		self.simulator.Quadtree:Query(self.position, self.maxSpeed, self.agentTimeHorizon, self.radius, self)
	end
	self.NeighbourCount = #self.neighbours
end

function Agent.InsertAgentNeighbour(self: AgentObject, otherAgent: AgentObject, rangeSq: number): number
	if self == otherAgent or bit32.band(otherAgent.layer, self.collidesWith) == 0 then
		return rangeSq
	end
	local dx: number = otherAgent.position.x - self.position.x
	local dy: number = otherAgent.position.y - self.position.y
	local dist: number = dx * dx + dy * dy
	if dist < rangeSq then
		if #self.neighbours < self.maxNeighbours then
			table.insert(self.neighbours, otherAgent)
			table.insert(self.neighbourDists, math.huge)
		end
		local i: number = #self.neighbours
		if dist < self.neighbourDists[i] then
			while i ~= 1 and dist < self.neighbourDists[i - 1] do
				self.neighbours[i] = self.neighbours[i - 1]
				self.neighbourDists[i] = self.neighbourDists[i - 1]
				i -= 1
			end
			self.neighbours[i] = otherAgent
			self.neighbourDists[i] = dist
		end
		if #self.neighbours == self.maxNeighbours then
			rangeSq = self.neighbourDists[#self.neighbourDists]
		end
	end
	return rangeSq
end

local function BiasDesiredVelocity(
	vos: VOBuffer,
	desiredVelocity: Vector2,
	targetPointInVelocitySpace: Vector2,
	maxBiasRadians: number
): (boolean, number, number, number, number)
	local desiredX: number = desiredVelocity.x
	local desiredY: number = desiredVelocity.y
	local desiredVelocityMagn: number = math.sqrt(desiredX * desiredX + desiredY * desiredY)
	local maxValue: number = 0
	for i: number = 1, vos.length do
		local _unusedX: number, _unusedY: number, value: number = VOGradient(vos.buffer[i], desiredX, desiredY)
		maxValue = math.max(maxValue, value)
	end
	local inside: boolean = maxValue > 0
	if desiredVelocityMagn < 0.001 then
		return inside, desiredX, desiredY, targetPointInVelocitySpace.x, targetPointInVelocitySpace.y
	end
	local angle: number = math.min(maxBiasRadians, maxValue / desiredVelocityMagn)
	local targetX: number = targetPointInVelocitySpace.x
	local targetY: number = targetPointInVelocitySpace.y
	return inside, desiredX + desiredY * angle, desiredY + -desiredX * angle, targetX + targetY * angle, targetY + -targetX * angle
end

local function EvaluateGradient(
	vos: VOBuffer,
	px: number,
	py: number,
	desiredX: number,
	desiredY: number,
	desiredSpeed: number,
	maxSpeed: number
): (number, number, number)
	local gradientX: number = 0
	local gradientY: number = 0
	local value: number = 0
	for i: number = 1, vos.length do
		local gx: number, gy: number, w: number = VOScaledGradient(vos.buffer[i], px, py)
		if w > value then
			value = w
			gradientX = gx
			gradientY = gy
		end
	end
	local dirX: number = desiredX - px
	local dirY: number = desiredY - py
	local distToDesiredVelocity: number = math.sqrt(dirX * dirX + dirY * dirY)
	if distToDesiredVelocity > 0.0001 then
		local invDist: number = DesiredVelocityWeight / distToDesiredVelocity
		gradientX += dirX * invDist
		gradientY += dirY * invDist
		value += distToDesiredVelocity * DesiredVelocityWeight
	end
	local sqrSpeed: number = px * px + py * py
	if sqrSpeed > desiredSpeed * desiredSpeed then
		local speed: number = math.sqrt(sqrSpeed)
		local invSpeed: number = 1 / speed
		if speed > maxSpeed then
			local maxSpeedWeight: number = 3
			value += maxSpeedWeight * (speed - maxSpeed)
			gradientX -= px * invSpeed * maxSpeedWeight
			gradientY -= py * invSpeed * maxSpeedWeight
		end
		local scale: number = 2 * DesiredVelocityWeight
		value += scale * (speed - desiredSpeed)
		gradientX -= px * invSpeed * scale
		gradientY -= py * invSpeed * scale
	end
	return gradientX, gradientY, value
end

local function Trace(self: AgentObject, vos: VOBuffer, startX: number, startY: number): (number, number, number)
	local stepSize: number = math.max(self.radius, 0.2 * self.desiredSpeed)
	local bestScore: number = math.huge
	local bestX: number = startX
	local bestY: number = startY
	local currentX: number = startX
	local currentY: number = startY
	local desiredX: number = self.desiredVelocity.x
	local desiredY: number = self.desiredVelocity.y
	local desiredSpeed: number = self.desiredSpeed
	local maxSpeed: number = self.maxSpeed
	for s: number = 0, TraceMaxIterations - 1 do
		local step: number = Sqr(1.0 - (s / TraceMaxIterations)) * stepSize
		local gx: number, gy: number, value: number = EvaluateGradient(vos, currentX, currentY, desiredX, desiredY, desiredSpeed, maxSpeed)
		if value < bestScore then
			bestScore = value
			bestX = currentX
			bestY = currentY
		end
		local nx: number, ny: number = NormalizeXY(gx, gy)
		currentX += nx * step
		currentY += ny * step
	end
	return bestX, bestY, bestScore
end

local function GradientDescent(self: AgentObject, vos: VOBuffer, sample1X: number, sample1Y: number, sample2X: number, sample2Y: number): (number, number)
	local minima1X: number, minima1Y: number, score1: number = Trace(self, vos, sample1X, sample1Y)
	local minima2X: number, minima2Y: number, score2: number = Trace(self, vos, sample2X, sample2Y)
	if score1 < score2 then
		return minima1X, minima1Y
	end
	return minima2X, minima2Y
end

local function GenerateObstacleVOs(self: AgentObject, vos: VOBuffer)
	local simulator = self.simulator
	if simulator == nil then
		return
	end
	local range: number = self.maxSpeed * self.obstacleTimeHorizon
	local obstacles: { ObstacleVertex } = simulator.obstacles
	local positionX: number = self.position.x
	local positionY: number = self.position.y
	for i: number = 1, #obstacles do
		local obstacle: ObstacleVertex = obstacles[i]
		local vertex: ObstacleVertex? = obstacle
		while vertex ~= nil do
			local currentVertex: ObstacleVertex = vertex
			if currentVertex.ignore or bit32.band(currentVertex.layer, self.collidesWith) == 0 then
				vertex = currentVertex.next
				if vertex == obstacle then
					break
				end
				continue
			end
			local nextVertex: ObstacleVertex? = currentVertex.next
			if nextVertex == nil then
				break
			end
			local p1: Vector2
			local elevation1: number
			local p2: Vector2
			local elevation2: number
			p1, elevation1 = AstarMath.To2D(currentVertex.position, simulator.movementPlane)
			p2, elevation2 = AstarMath.To2D(nextVertex.position, simulator.movementPlane)
			local dirX: number, dirY: number = NormalizeXY(p2.x - p1.x, p2.y - p1.y)
			local dist: number = SignedDistanceFromLineXY(p1.x, p1.y, dirX, dirY, positionX, positionY)
			if dist >= -0.01 and dist < range then
				local segmentDx: number = p2.x - p1.x
				local segmentDy: number = p2.y - p1.y
				local segmentSqr: number = segmentDx * segmentDx + segmentDy * segmentDy
				local factorAlongSegment: number = if segmentSqr > 0 then ((positionX - p1.x) * segmentDx + (positionY - p1.y) * segmentDy) / segmentSqr else 0
				local segmentY: number = AstarMath.LerpNumber(elevation1, elevation2, factorAlongSegment)
				local closestX: number = p1.x + (p2.x - p1.x) * factorAlongSegment
				local closestY: number = p1.y + (p2.y - p1.y) * factorAlongSegment
				local toClosestX: number = closestX - positionX
				local toClosestY: number = closestY - positionY
				local sqrDistToSegment: number = toClosestX * toClosestX + toClosestY * toClosestY
				local elevationOverlaps: boolean = simulator.movementPlane == MovementPlaneXY
					or (self.elevationCoordinate <= segmentY + currentVertex.height and self.elevationCoordinate + self.height >= segmentY)
				if sqrDistToSegment < range * range and elevationOverlaps then
					local inverseDeltaTime: number = 1 / math.max(simulator.DeltaTime, 1 / 2000)
					local vo: VO = AcquireVO(vos)
					FillSegmentObstacleVO(
						vo,
						p2.x - positionX,
						p2.y - positionY,
						p1.x - positionX,
						p1.y - positionY,
						0,
						0,
						self.radius * 0.01,
						1 / self.ObstacleTimeHorizon,
						inverseDeltaTime
					)
				end
			end
			vertex = currentVertex.next
			if vertex == obstacle then
				break
			end
		end
	end
end

local function GenerateNeighbourAgentVOs(self: AgentObject, vos: VOBuffer)
	local simulator = self.simulator
	if simulator == nil then
		return
	end
	local inverseAgentTimeHorizon: number = 1 / self.agentTimeHorizon
	local inverseDeltaTime: number = 1 / math.max(simulator.DeltaTime, 1 / 2000)
	local optimalX: number = self.currentVelocity.x
	local optimalY: number = self.currentVelocity.y
	local positionX: number = self.position.x
	local positionY: number = self.position.y
	for o: number = 1, #self.neighbours do
		local other: AgentObject = self.neighbours[o]
		if other == self then
			continue
		end
		local maxY: number = math.min(self.elevationCoordinate + self.height, other.elevationCoordinate + other.height)
		local minY: number = math.max(self.elevationCoordinate, other.elevationCoordinate)
		if maxY - minY < 0 then
			continue
		end
		local totalRadius: number = self.radius + other.radius
		local originX: number = other.position.x - positionX
		local originY: number = other.position.y - positionY
		local avoidanceStrength: number
		if other.locked or other.manuallyControlled then
			avoidanceStrength = 1
		elseif other.Priority > 0.00001 or self.Priority > 0.00001 then
			avoidanceStrength = other.Priority / (self.Priority + other.Priority)
		else
			avoidanceStrength = 0.5
		end
		local lerpT: number = 2 * avoidanceStrength - 1
		local otherOptimalX: number = other.currentVelocity.x + (other.desiredVelocity.x - other.currentVelocity.x) * lerpT
		local otherOptimalY: number = other.currentVelocity.y + (other.desiredVelocity.y - other.currentVelocity.y) * lerpT
		local voCenterX: number = optimalX + (otherOptimalX - optimalX) * avoidanceStrength
		local voCenterY: number = optimalY + (otherOptimalY - optimalY) * avoidanceStrength
		local vo: VO = AcquireVO(vos)
		FillAgentVO(vo, originX, originY, voCenterX, voCenterY, totalRadius, inverseAgentTimeHorizon, inverseDeltaTime)
	end
end

function Agent.CalculateVelocity(self: AgentObject, context: WorkerContext)
	if self.manuallyControlled then
		return
	end
	if self.locked then
		self.calculatedSpeed = 0
		SetXY(self.calculatedTargetPoint, self.position.x, self.position.y)
		return
	end
	local vos: VOBuffer = context.vos
	Agent.ClearVOBuffer(vos)
	GenerateObstacleVOs(self, vos)
	GenerateNeighbourAgentVOs(self, vos)
	local insideAnyVO: boolean
	local desiredX: number
	local desiredY: number
	local targetX: number
	local targetY: number
	insideAnyVO, desiredX, desiredY, targetX, targetY =
		BiasDesiredVelocity(vos, self.desiredVelocity, self.desiredTargetPointInVelocitySpace, self.simulator.symmetryBreakingBias)
	SetXY(self.desiredVelocity, desiredX, desiredY)
	SetXY(self.desiredTargetPointInVelocitySpace, targetX, targetY)
	if not insideAnyVO then
		SetXY(self.calculatedTargetPoint, targetX + self.position.x, targetY + self.position.y)
		self.calculatedSpeed = self.desiredSpeed
		return
	end
	local resultX: number, resultY: number = GradientDescent(self, vos, self.currentVelocity.x, self.currentVelocity.y, desiredX, desiredY)
	SetXY(self.calculatedTargetPoint, self.position.x + resultX, self.position.y + resultY)
	self.calculatedSpeed = math.min(math.sqrt(resultX * resultX + resultY * resultY), self.maxSpeed)
end

return Agent
