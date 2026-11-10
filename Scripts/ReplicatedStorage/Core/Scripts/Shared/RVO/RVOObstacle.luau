--!strict
--!native
-- Ported from A* Pathfinding Project Core/RVO/RVOCoreObstacle.cs.
local AstarMath = require(script.Parent:FindFirstChild("AstarMath"))

type Vector2 = AstarMath.Vector2

local RVOLayerDefaultObstacle: number = bit32.lshift(1, 1)

local RVOObstacle = {}

export type ObstacleVertex = {
	ignore: boolean,
	position: Vector3,
	dir: Vector2,
	height: number,
	layer: number,
	next: any,
	prev: any,
}

function RVOObstacle.CreateVertex(): ObstacleVertex
	return {
		ignore = false,
		position = Vector3.zero,
		dir = AstarMath.Zero(),
		height = 0,
		layer = RVOLayerDefaultObstacle,
		next = nil,
		prev = nil,
	}
end

return RVOObstacle
