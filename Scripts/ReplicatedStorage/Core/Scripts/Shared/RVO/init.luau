--!strict
--!native
-- Ported from A* Pathfinding Project Core/RVO (Sampled RVO).
local RVOAgent = require(script:FindFirstChild("RVOAgent"))
local RVOObstacle = require(script:FindFirstChild("RVOObstacle"))
local RVOSimulator = require(script:FindFirstChild("RVOSimulator"))
local RVOQuadtree = require(script:FindFirstChild("RVOQuadtree"))
local AstarMath = require(script:FindFirstChild("AstarMath"))

local RVO = {}

RVO.RVOAgent = RVOAgent
RVO.RVOObstacle = RVOObstacle
RVO.RVOSimulator = RVOSimulator
RVO.RVOQuadtree = RVOQuadtree
RVO.AstarMath = AstarMath
RVO.RvoError = RVOSimulator.RvoError
RVO.MovementPlaneXZ = RVOSimulator.MovementPlaneXZ
RVO.MovementPlaneXY = RVOSimulator.MovementPlaneXY
RVO.RVOLayerDefaultAgent = RVOSimulator.RVOLayerDefaultAgent
RVO.RVOLayerDefaultObstacle = RVOSimulator.RVOLayerDefaultObstacle
RVO.RVOLayerAll = RVOSimulator.RVOLayerAll

export type RVOSimulator = RVOSimulator.RVOSimulatorObject
export type AgentObject = RVOAgent.AgentObject
export type ObstacleVertex = RVOObstacle.ObstacleVertex
export type Vector2 = AstarMath.Vector2
export type AgentDefaults = RVOSimulator.AgentDefaults

return RVO
