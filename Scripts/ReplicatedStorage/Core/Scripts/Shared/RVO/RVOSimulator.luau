--!strict
--!native
-- Ported from A* Pathfinding Project Core/RVO/RVOCoreSimulator.cs (single-threaded) + World Vector3 helpers.
local RVOAgent = require(script.Parent:FindFirstChild("RVOAgent"))
local RVOObstacle = require(script.Parent:FindFirstChild("RVOObstacle"))
local RVOQuadtree = require(script.Parent:FindFirstChild("RVOQuadtree"))
local AstarMath = require(script.Parent:FindFirstChild("AstarMath"))

type Vector2 = AstarMath.Vector2
type AgentObject = RVOAgent.AgentObject
type ObstacleVertex = RVOObstacle.ObstacleVertex
type WorkerContext = RVOAgent.WorkerContext
type RVOQuadtreeObject = RVOQuadtree.RVOQuadtreeObject

local RVOSimulator = {}
RVOSimulator.__index = RVOSimulator

-- MovementPlane / RVOLayer (from RVOSimulator.cs)
RVOSimulator.MovementPlaneXZ = 0
RVOSimulator.MovementPlaneXY = 1
RVOSimulator.RVOLayerDefaultAgent = bit32.lshift(1, 0)
RVOSimulator.RVOLayerDefaultObstacle = bit32.lshift(1, 1)
RVOSimulator.RVOLayerAll = 0x7FFFFFFF

RVOSimulator.RvoError = math.huge

export type AgentDefaults = {
	radius: number,
	height: number,
	agentTimeHorizon: number,
	obstacleTimeHorizon: number,
	maxNeighbours: number,
	maxSpeed: number,
	priority: number,
	layer: number,
	collidesWith: number,
}

export type RVOSimulatorObject = typeof(setmetatable(
	{} :: {
		agents: { AgentObject },
		obstacles: { ObstacleVertex },
		Quadtree: RVOQuadtreeObject,
		deltaTime: number,
		DesiredDeltaTime: number,
		symmetryBreakingBias: number,
		movementPlane: number,
		DeltaTime: number,
		doUpdateObstacles: boolean,
		doCleanObstacles: boolean,
		workerContext: WorkerContext,
		defaultAgent: AgentDefaults,
	},
	RVOSimulator
))

function RVOSimulator.new(symmetryBreakingBias: number?, movementPlane: number?, defaults: AgentDefaults?): RVOSimulatorObject
	local defaultAgent: AgentDefaults = defaults
		or {
			radius = 5,
			height = 5,
			agentTimeHorizon = 2,
			obstacleTimeHorizon = 2,
			maxNeighbours = 10,
			maxSpeed = 0,
			priority = 0.5,
			layer = RVOSimulator.RVOLayerDefaultAgent,
			collidesWith = RVOSimulator.RVOLayerAll,
		}
	local self: RVOSimulatorObject = setmetatable({
		agents = {},
		obstacles = {},
		Quadtree = RVOQuadtree.new(),
		deltaTime = 1 / 20,
		DesiredDeltaTime = 0,
		symmetryBreakingBias = symmetryBreakingBias or 0.1,
		movementPlane = movementPlane or RVOSimulator.MovementPlaneXZ,
		DeltaTime = 1 / 20,
		doUpdateObstacles = false,
		doCleanObstacles = false,
		workerContext = RVOAgent.CreateWorkerContext(),
		defaultAgent = defaultAgent,
	}, RVOSimulator) :: RVOSimulatorObject
	return self
end

function RVOSimulator.SetAgentDefaults(
	self: RVOSimulatorObject,
	radius: number,
	height: number,
	agentTimeHorizon: number,
	obstacleTimeHorizon: number,
	maxNeighbours: number,
	maxSpeed: number,
	priority: number?,
	layer: number?,
	collidesWith: number?
)
	self.defaultAgent = {
		radius = radius,
		height = height,
		agentTimeHorizon = agentTimeHorizon,
		obstacleTimeHorizon = obstacleTimeHorizon,
		maxNeighbours = maxNeighbours,
		maxSpeed = maxSpeed,
		priority = priority or 0.5,
		layer = layer or RVOSimulator.RVOLayerDefaultAgent,
		collidesWith = collidesWith or RVOSimulator.RVOLayerAll,
	}
end

function RVOSimulator.GetAgents(self: RVOSimulatorObject): { AgentObject }
	return self.agents
end

function RVOSimulator.GetObstacles(self: RVOSimulatorObject): { ObstacleVertex }
	return self.obstacles
end

function RVOSimulator.ClearAgents(self: RVOSimulatorObject)
	for i: number = 1, #self.agents do
		self.agents[i].simulator = nil
	end
	table.clear(self.agents)
end

local function ApplyDefaults(agent: AgentObject, defaults: AgentDefaults)
	agent.Radius = defaults.radius
	agent.Height = defaults.height
	agent.AgentTimeHorizon = defaults.agentTimeHorizon
	agent.ObstacleTimeHorizon = defaults.obstacleTimeHorizon
	agent.MaxNeighbours = defaults.maxNeighbours
	agent.Priority = defaults.priority
	agent.Layer = defaults.layer
	agent.CollidesWith = defaults.collidesWith
	agent.radius = defaults.radius
	agent.height = defaults.height
end

function RVOSimulator.AddAgent(self: RVOSimulatorObject, position: Vector2, elevationCoordinate: number): AgentObject
	local agent: AgentObject = RVOAgent.new(position, elevationCoordinate)
	ApplyDefaults(agent, self.defaultAgent)
	agent.simulator = self
	table.insert(self.agents, agent)
	return agent
end

function RVOSimulator.RemoveAgent(self: RVOSimulatorObject, agent: AgentObject)
	if agent.simulator ~= self then
		error("The agent is not added to this simulation")
	end
	agent.simulator = nil
	local index: number? = table.find(self.agents, agent)
	if index == nil then
		error("Critical Bug! Agent not found in simulation list")
	end
	table.remove(self.agents, index)
end

function RVOSimulator.AddObstacleVertex(self: RVOSimulatorObject, v: ObstacleVertex): ObstacleVertex
	table.insert(self.obstacles, v)
	self:UpdateObstacles()
	return v
end

function RVOSimulator.AddObstacle(self: RVOSimulatorObject, vertices: { Vector3 }, height: number, layer: number?, cycle: boolean?): ObstacleVertex
	if #vertices < 2 then
		error("Less than 2 vertices in an obstacle")
	end
	local useCycle: boolean = if cycle == nil then true else cycle
	local obstacleLayer: number = layer or RVOSimulator.RVOLayerDefaultObstacle
	local first: ObstacleVertex? = nil
	local prev: ObstacleVertex? = nil
	for _i: number = 1, #vertices do
		local v: ObstacleVertex = RVOObstacle.CreateVertex()
		v.prev = prev
		v.layer = obstacleLayer
		v.height = height
		if first == nil then
			first = v
		elseif prev ~= nil then
			prev.next = v
		end
		prev = v
	end
	assert(first ~= nil and prev ~= nil)
	if useCycle then
		prev.next = first
		first.prev = prev
	end
	self:UpdateObstacle(first, vertices)
	table.insert(self.obstacles, first)
	return first
end

function RVOSimulator.AddObstacleSegment(self: RVOSimulatorObject, a: Vector3, b: Vector3, height: number): ObstacleVertex
	local first: ObstacleVertex = RVOObstacle.CreateVertex()
	local second: ObstacleVertex = RVOObstacle.CreateVertex()
	first.layer = RVOSimulator.RVOLayerDefaultObstacle
	second.layer = RVOSimulator.RVOLayerDefaultObstacle
	first.prev = second
	second.prev = first
	first.next = second
	second.next = first
	first.position = a
	second.position = b
	first.height = height
	second.height = height
	second.ignore = true
	local dir2d: Vector2 = AstarMath.Normalize(AstarMath.New(b.X - a.X, b.Z - a.Z))
	first.dir = dir2d
	second.dir = AstarMath.Negate(dir2d)
	table.insert(self.obstacles, first)
	self:UpdateObstacles()
	return first
end

function RVOSimulator.UpdateObstacle(self: RVOSimulatorObject, obstacle: ObstacleVertex, vertices: { Vector3 })
	if #vertices < 2 then
		error("Less than 2 vertices in an obstacle")
	end
	local count: number = 0
	local vertex: ObstacleVertex? = obstacle
	while vertex ~= nil do
		count += 1
		if count > #vertices then
			error("Obstacle has more vertices than supplied for updating")
		end
		vertex.position = vertices[count]
		vertex = vertex.next
		if vertex == obstacle then
			break
		end
	end
	vertex = obstacle
	while vertex ~= nil do
		local nextVertex: ObstacleVertex? = vertex.next
		if nextVertex == nil then
			vertex.dir = AstarMath.Zero()
		else
			local dir: Vector3 = nextVertex.position - vertex.position
			vertex.dir = AstarMath.Normalize(AstarMath.New(dir.X, dir.Z))
		end
		vertex = vertex.next
		if vertex == obstacle then
			break
		end
	end
	self.doCleanObstacles = true
	self:UpdateObstacles()
end

function RVOSimulator.RemoveObstacle(self: RVOSimulatorObject, v: ObstacleVertex)
	local index: number? = table.find(self.obstacles, v)
	if index ~= nil then
		table.remove(self.obstacles, index)
	end
	self:UpdateObstacles()
end

function RVOSimulator.UpdateObstacles(self: RVOSimulatorObject)
	self.doUpdateObstacles = true
end

local function BuildQuadtree(self: RVOSimulatorObject)
	self.Quadtree:Clear()
	if #self.agents > 0 then
		local firstPosition: Vector2 = self.agents[1].position
		local bounds = AstarMath.RectMinMax(firstPosition.x, firstPosition.y, firstPosition.x, firstPosition.y)
		for i: number = 2, #self.agents do
			local p: Vector2 = self.agents[i].position
			bounds = AstarMath.RectMinMax(math.min(bounds.xMin, p.x), math.min(bounds.yMin, p.y), math.max(bounds.xMax, p.x), math.max(bounds.yMax, p.y))
		end
		self.Quadtree:SetBounds(bounds)
		for i: number = 1, #self.agents do
			self.Quadtree:Insert(self.agents[i])
		end
	end
	self.Quadtree:CalculateSpeeds()
end

local function CleanAndUpdateObstaclesIfNecessary(self: RVOSimulatorObject)
	if self.doCleanObstacles then
		self.doCleanObstacles = false
		self.doUpdateObstacles = true
	end
	if self.doUpdateObstacles then
		self.doUpdateObstacles = false
	end
end

function RVOSimulator.DoStep(self: RVOSimulatorObject, deltaTime: number?)
	local stepDelta: number = deltaTime or self.DesiredDeltaTime
	if stepDelta <= 0 then
		stepDelta = self.deltaTime
	end
	self.deltaTime = math.max(stepDelta, 1 / 2000)
	self.DeltaTime = self.deltaTime
	for i: number = 1, #self.agents do
		self.agents[i]:PreCalculation()
	end
	CleanAndUpdateObstaclesIfNecessary(self)
	-- BufferSwitch before quadtree so neighbour queries use current positions (Roblox single-thread).
	for i: number = 1, #self.agents do
		self.agents[i]:BufferSwitch()
	end
	BuildQuadtree(self)
	for i: number = 1, #self.agents do
		self.agents[i]:CalculateNeighbours()
		self.agents[i]:CalculateVelocity(self.workerContext)
	end
	for i: number = 1, #self.agents do
		self.agents[i]:PostCalculation()
	end
end

function RVOSimulator.SetTimeStep(self: RVOSimulatorObject, timeStep: number)
	self.DesiredDeltaTime = timeStep
	self.deltaTime = math.max(timeStep, 1 / 2000)
	self.DeltaTime = self.deltaTime
end

-- World Vector3 helpers (Agent object API, matching original reference style)

function RVOSimulator.AddAgentFromWorld(self: RVOSimulatorObject, position: Vector3): AgentObject
	return self:AddAgent(AstarMath.FromWorld(position), AstarMath.ElevationFromWorld(position))
end

function RVOSimulator.SetAgentPositionFromWorld(self: RVOSimulatorObject, agent: AgentObject, position: Vector3)
	agent.Position = AstarMath.FromWorld(position)
	agent.ElevationCoordinate = AstarMath.ElevationFromWorld(position)
end

function RVOSimulator.SetAgentVelocityFromWorld(self: RVOSimulatorObject, agent: AgentObject, velocity: Vector3)
	-- Seed observed velocity for next BufferSwitch via Calculated* fields.
	local velocity2d: Vector2 = AstarMath.FromWorld(velocity)
	local speed: number = AstarMath.Abs(velocity2d)
	agent.CalculatedSpeed = speed
	if speed > 0.0001 then
		agent.CalculatedTargetPoint = AstarMath.Add(agent.Position, AstarMath.Multiply(AstarMath.Normalize(velocity2d), 1000))
	else
		agent.CalculatedTargetPoint = { x = agent.Position.x, y = agent.Position.y }
	end
end

function RVOSimulator.SetAgentTargetFromWorld(self: RVOSimulatorObject, agent: AgentObject, targetPoint: Vector3, desiredSpeed: number, maxSpeed: number)
	agent:SetTarget(AstarMath.FromWorld(targetPoint), desiredSpeed, maxSpeed)
end

function RVOSimulator.ForceSetAgentVelocityFromWorld(self: RVOSimulatorObject, agent: AgentObject, velocity: Vector3)
	agent:ForceSetVelocity(AstarMath.FromWorld(velocity))
end

function RVOSimulator.SetAgentCollisionNormalFromWorld(self: RVOSimulatorObject, agent: AgentObject, normal: Vector3)
	agent:SetCollisionNormal(AstarMath.FromWorld(normal))
end

function RVOSimulator.GetAgentVelocityWorld(self: RVOSimulatorObject, agent: AgentObject, y: number?): Vector3
	local delta: Vector2 = AstarMath.Subtract(agent.CalculatedTargetPoint, agent.Position)
	local maxStep: number = agent.CalculatedSpeed * self.DeltaTime
	local clamped: Vector2 = AstarMath.ClampMagnitude(delta, maxStep)
	if self.DeltaTime <= 0 then
		return Vector3.zero
	end
	local velocity2d: Vector2 = AstarMath.Divide(clamped, self.DeltaTime)
	return AstarMath.ToWorld(velocity2d, y or 0)
end

function RVOSimulator.AddObstacleFromWorld(self: RVOSimulatorObject, vertices: { Vector3 }, height: number, layer: number?): ObstacleVertex
	return self:AddObstacle(vertices, height, layer, true)
end

return RVOSimulator
