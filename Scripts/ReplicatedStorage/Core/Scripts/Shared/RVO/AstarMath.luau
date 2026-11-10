--!strict
--!native
-- Ported from A* Pathfinding Project Core/AstarMath.cs (Vector2 helpers used by RVO).
local AstarMath = {}

export type Vector2 = { x: number, y: number }
export type Rect = { xMin: number, yMin: number, xMax: number, yMax: number }

local Epsilon: number = 1e-5

function AstarMath.Zero(): Vector2
	return { x = 0, y = 0 }
end

function AstarMath.New(x: number, y: number): Vector2
	return { x = x, y = y }
end

function AstarMath.FromWorld(position: Vector3): Vector2
	return { x = position.X, y = position.Z }
end

function AstarMath.ToWorld(vector2: Vector2, y: number): Vector3
	return Vector3.new(vector2.x, y, vector2.y)
end

function AstarMath.ElevationFromWorld(position: Vector3): number
	return position.Y
end

function AstarMath.Add(leftVector: Vector2, rightVector: Vector2): Vector2
	return { x = leftVector.x + rightVector.x, y = leftVector.y + rightVector.y }
end

function AstarMath.Subtract(leftVector: Vector2, rightVector: Vector2): Vector2
	return { x = leftVector.x - rightVector.x, y = leftVector.y - rightVector.y }
end

function AstarMath.Multiply(vector2: Vector2, scalar: number): Vector2
	return { x = vector2.x * scalar, y = vector2.y * scalar }
end

function AstarMath.Divide(vector2: Vector2, scalar: number): Vector2
	return { x = vector2.x / scalar, y = vector2.y / scalar }
end

function AstarMath.Negate(vector2: Vector2): Vector2
	return { x = -vector2.x, y = -vector2.y }
end

function AstarMath.Dot(leftVector: Vector2, rightVector: Vector2): number
	return leftVector.x * rightVector.x + leftVector.y * rightVector.y
end

function AstarMath.AbsSq(vector2: Vector2): number
	return vector2.x * vector2.x + vector2.y * vector2.y
end

function AstarMath.Abs(vector2: Vector2): number
	return math.sqrt(AstarMath.AbsSq(vector2))
end

function AstarMath.Normalize(vector2: Vector2): Vector2
	local magnitude: number = AstarMath.Abs(vector2)
	if magnitude < Epsilon then
		return AstarMath.Zero()
	end
	return AstarMath.Multiply(vector2, 1 / magnitude)
end

function AstarMath.NormalizeWithMagnitude(vector2: Vector2): (Vector2, number)
	local magnitude: number = AstarMath.Abs(vector2)
	if magnitude > Epsilon then
		return AstarMath.Multiply(vector2, 1 / magnitude), magnitude
	end
	return AstarMath.Zero(), magnitude
end

function AstarMath.Lerp(fromVector: Vector2, toVector: Vector2, t: number): Vector2
	return {
		x = fromVector.x + (toVector.x - fromVector.x) * t,
		y = fromVector.y + (toVector.y - fromVector.y) * t,
	}
end

function AstarMath.LerpNumber(fromValue: number, toValue: number, t: number): number
	return fromValue + (toValue - fromValue) * t
end

function AstarMath.ClampMagnitude(vector2: Vector2, maxLength: number): Vector2
	local sqrMagnitude: number = AstarMath.AbsSq(vector2)
	if sqrMagnitude > maxLength * maxLength and maxLength > 0 then
		local magnitude: number = math.sqrt(sqrMagnitude)
		return AstarMath.Multiply(vector2, maxLength / magnitude)
	end
	return { x = vector2.x, y = vector2.y }
end

function AstarMath.ComplexMultiply(a: Vector2, b: Vector2): Vector2
	return { x = a.x * b.x - a.y * b.y, y = a.x * b.y + a.y * b.x }
end

function AstarMath.ClosestPointOnSegment(lineStart: Vector2, lineEnd: Vector2, point: Vector2): Vector2
	local dir: Vector2 = AstarMath.Subtract(lineEnd, lineStart)
	local sqrMagn: number = AstarMath.AbsSq(dir)
	if sqrMagn <= 0.000001 then
		return { x = lineStart.x, y = lineStart.y }
	end
	local factor: number = math.clamp(AstarMath.Dot(AstarMath.Subtract(point, lineStart), dir) / sqrMagn, 0, 1)
	return AstarMath.Add(lineStart, AstarMath.Multiply(dir, factor))
end

function AstarMath.RectMinMax(xMin: number, yMin: number, xMax: number, yMax: number): Rect
	return { xMin = xMin, yMin = yMin, xMax = xMax, yMax = yMax }
end

function AstarMath.RectCenter(rect: Rect): Vector2
	return { x = (rect.xMin + rect.xMax) * 0.5, y = (rect.yMin + rect.yMax) * 0.5 }
end

function AstarMath.To2D(position: Vector3, movementPlane: number): (Vector2, number)
	if movementPlane == 1 then
		return { x = position.X, y = position.Y }, -position.Z
	end
	return { x = position.X, y = position.Z }, position.Y
end

return AstarMath
