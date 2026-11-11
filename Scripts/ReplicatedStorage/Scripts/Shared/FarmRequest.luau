-- 新版经营请求契约：限制动作和标识长度，隔离客户端输入与服务端权威货物数值
--!strict
local Config = if script then require(script.Parent:WaitForChild("FarmEconomyConfig")) else require("./FarmEconomyConfig")
export type Request = {
	action: string,
	targetId: string?,
	speciesId: string?,
	tier: number?,
	confirmationId: string?,
	aim: { x: number, y: number, z: number }?,
	expectedStep: number?,
}
local FarmRequest = {}
local SimpleActions = { zap = true, collect = true, buyZap = true, buyCollect = true, buyNest = true, buyRestaurant = true, buyBasket = true, enhanceWeapon = true }
local SpeciesIds = { chicken = true, rabbit = true, sheep = true, cow = true, dragon = true }
local function IsId(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= 128
end
function FarmRequest.Parse(value: unknown): Request?
	if type(value) ~= "table" then return nil end
	local data = value :: { [string]: unknown }
	local action = data.action
	if type(action) ~= "string" then return nil end
	if SimpleActions[action] then
		local request: Request = { action = action }
		if data.expectedStep ~= nil then
			local step = data.expectedStep
			if type(step) ~= "number" or step ~= step or step % 1 ~= 0 or step < 1 or step > Config.GetWeaponProgressStep(#Config.Weapons, Config.MaximumWeaponLevel) then return nil end
			request.expectedStep = step
		end
		if action == "zap" and data.aim ~= nil then
			if type(data.aim) ~= "table" then return nil end
			local aim = data.aim :: { [string]: unknown }
			local x, y, z = aim.x, aim.y, aim.z
			if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return nil end
			local length = math.sqrt(x*x+y*y+z*z)
			if length ~= length or length < 0.5 or length > 2 then return nil end
			request.aim = { x = x / length, y = y / length, z = z / length }
		end
		return request
	end
	if action == "accelerateEgg" or action == "requestInstantHatch" then
		if not IsId(data.targetId) then return nil end
		local request: Request = { action = action, targetId = data.targetId :: string }
		return request
	elseif action == "selectSpecies" then
		if type(data.speciesId) ~= "string" or not SpeciesIds[data.speciesId] then return nil end
		local request: Request = { action = action, speciesId = data.speciesId }
		return request
	elseif action == "equipWeapon" then
		local tier = data.tier
		if type(tier) ~= "number" or tier ~= tier or tier % 1 ~= 0 or tier < 1 or tier > 5 then return nil end
		local request: Request = { action = action, tier = tier }
		return request
	elseif action == "confirm" or action == "cancel" then
		if not IsId(data.confirmationId) then return nil end
		local request: Request = { action = action, confirmationId = data.confirmationId :: string }
		return request
	end
	return nil
end
return FarmRequest
