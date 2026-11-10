--!strict
--!native
-- Ported from A* Pathfinding Project Core/RVO/RVOQuadtree.cs.
local RVOAgent = require(script.Parent:FindFirstChild("RVOAgent"))
local AstarMath = require(script.Parent:FindFirstChild("AstarMath"))

type Vector2 = AstarMath.Vector2
type Rect = AstarMath.Rect
type AgentObject = RVOAgent.AgentObject

local RVOQuadtree = {}
RVOQuadtree.__index = RVOQuadtree

local LeafSize: number = 15

export type Node = {
	child00: number,
	linkedList: AgentObject?,
	count: number,
	maxSpeed: number,
}

export type RVOQuadtreeObject = typeof(setmetatable(
	{} :: {
		nodes: { Node },
		filledNodes: number,
		bounds: Rect,
		maxRadius: number,
	},
	RVOQuadtree
))

local function CreateNode(child00: number): Node
	return {
		child00 = child00,
		linkedList = nil,
		count = 0,
		maxSpeed = 0,
	}
end

local function NodeAdd(node: Node, agent: AgentObject)
	agent.next = node.linkedList
	node.linkedList = agent
end

local function NodeDistribute(node: Node, nodes: { Node }, r: Rect)
	local c: Vector2 = AstarMath.RectCenter(r)
	while node.linkedList ~= nil do
		local linked: AgentObject = node.linkedList
		local nx: AgentObject? = linked.next
		local index: number = node.child00 + (if linked.position.x > c.x then 2 else 0) + (if linked.position.y > c.y then 1 else 0)
		NodeAdd(nodes[index + 1], linked)
		node.linkedList = nx
	end
	node.count = 0
end

local function NodeCalculateMaxSpeed(nodes: { Node }, index: number): number
	local node: Node = nodes[index + 1]
	if node.child00 == index then
		local agent: AgentObject? = node.linkedList
		while agent ~= nil do
			node.maxSpeed = math.max(node.maxSpeed, agent.CalculatedSpeed)
			agent = agent.next
		end
	else
		local child00: number = node.child00
		node.maxSpeed = math.max(NodeCalculateMaxSpeed(nodes, child00), NodeCalculateMaxSpeed(nodes, child00 + 1))
		node.maxSpeed = math.max(node.maxSpeed, NodeCalculateMaxSpeed(nodes, child00 + 2))
		node.maxSpeed = math.max(node.maxSpeed, NodeCalculateMaxSpeed(nodes, child00 + 3))
	end
	return node.maxSpeed
end

function RVOQuadtree.new(): RVOQuadtreeObject
	local nodes: { Node } = table.create(16)
	nodes[1] = CreateNode(0)
	return setmetatable({
		nodes = nodes,
		filledNodes = 1,
		bounds = AstarMath.RectMinMax(0, 0, 0, 0),
		maxRadius = 0,
	}, RVOQuadtree) :: RVOQuadtreeObject
end

function RVOQuadtree.Clear(self: RVOQuadtreeObject)
	self.nodes[1] = CreateNode(0)
	self.filledNodes = 1
	self.maxRadius = 0
end

function RVOQuadtree.SetBounds(self: RVOQuadtreeObject, r: Rect)
	self.bounds = r
end

local function GetNodeIndex(self: RVOQuadtreeObject): number
	if self.filledNodes + 4 >= #self.nodes then
		local needed: number = math.max(self.filledNodes + 4, #self.nodes * 2)
		for i: number = #self.nodes + 1, needed do
			self.nodes[i] = CreateNode(0)
		end
	end
	local first: number = self.filledNodes
	for offset: number = 0, 3 do
		local index: number = first + offset
		self.nodes[index + 1] = CreateNode(index)
		self.filledNodes += 1
	end
	return first
end

function RVOQuadtree.Insert(self: RVOQuadtreeObject, agent: AgentObject)
	local i: number = 0
	local r: Rect = {
		xMin = self.bounds.xMin,
		yMin = self.bounds.yMin,
		xMax = self.bounds.xMax,
		yMax = self.bounds.yMax,
	}
	local p: Vector2 = { x = agent.position.x, y = agent.position.y }
	agent.next = nil
	self.maxRadius = math.max(agent.radius, self.maxRadius)
	local depth: number = 0
	while true do
		depth += 1
		local node: Node = self.nodes[i + 1]
		if node.child00 == i then
			if node.count < LeafSize or depth > 10 then
				NodeAdd(node, agent)
				node.count += 1
				break
			else
				node.child00 = GetNodeIndex(self)
				NodeDistribute(node, self.nodes, r)
			end
		end
		node = self.nodes[i + 1]
		if node.child00 ~= i then
			local c: Vector2 = AstarMath.RectCenter(r)
			if p.x > c.x then
				if p.y > c.y then
					i = node.child00 + 3
					r = AstarMath.RectMinMax(c.x, c.y, r.xMax, r.yMax)
				else
					i = node.child00 + 2
					r = AstarMath.RectMinMax(c.x, r.yMin, r.xMax, c.y)
				end
			else
				if p.y > c.y then
					i = node.child00 + 1
					r = AstarMath.RectMinMax(r.xMin, c.y, c.x, r.yMax)
				else
					i = node.child00
					r = AstarMath.RectMinMax(r.xMin, r.yMin, c.x, c.y)
				end
			end
		end
	end
end

function RVOQuadtree.CalculateSpeeds(self: RVOQuadtreeObject)
	NodeCalculateMaxSpeed(self.nodes, 0)
end

local function QueryRec(
	nodes: { Node },
	i: number,
	r: Rect,
	p: Vector2,
	speed: number,
	timeHorizon: number,
	agentRadius: number,
	agent: AgentObject,
	maxRadiusRef: { number }
)
	local node: Node = nodes[i + 1]
	local radius: number = math.min(math.max((node.maxSpeed + speed) * timeHorizon, agentRadius) + agentRadius, maxRadiusRef[1])
	if node.child00 == i then
		local a: AgentObject? = node.linkedList
		while a ~= nil do
			local v: number = agent:InsertAgentNeighbour(a, radius * radius)
			if v < maxRadiusRef[1] * maxRadiusRef[1] then
				maxRadiusRef[1] = math.sqrt(v)
			end
			a = a.next
		end
	else
		local c: Vector2 = AstarMath.RectCenter(r)
		if p.x - radius < c.x then
			if p.y - radius < c.y then
				QueryRec(nodes, node.child00, AstarMath.RectMinMax(r.xMin, r.yMin, c.x, c.y), p, speed, timeHorizon, agentRadius, agent, maxRadiusRef)
				radius = math.min(radius, maxRadiusRef[1])
			end
			if p.y + radius > c.y then
				QueryRec(nodes, node.child00 + 1, AstarMath.RectMinMax(r.xMin, c.y, c.x, r.yMax), p, speed, timeHorizon, agentRadius, agent, maxRadiusRef)
				radius = math.min(radius, maxRadiusRef[1])
			end
		end
		if p.x + radius > c.x then
			if p.y - radius < c.y then
				QueryRec(nodes, node.child00 + 2, AstarMath.RectMinMax(c.x, r.yMin, r.xMax, c.y), p, speed, timeHorizon, agentRadius, agent, maxRadiusRef)
				radius = math.min(radius, maxRadiusRef[1])
			end
			if p.y + radius > c.y then
				QueryRec(nodes, node.child00 + 3, AstarMath.RectMinMax(c.x, c.y, r.xMax, r.yMax), p, speed, timeHorizon, agentRadius, agent, maxRadiusRef)
			end
		end
	end
end

function RVOQuadtree.Query(self: RVOQuadtreeObject, p: Vector2, speed: number, timeHorizon: number, agentRadius: number, agent: AgentObject)
	local maxRadiusRef: { number } = { math.huge }
	QueryRec(self.nodes, 0, self.bounds, p, speed, timeHorizon, agentRadius, agent, maxRadiusRef)
end

return RVOQuadtree
