-- 餐厅 Edit 静态审计：对照原资产核验交货区恢复、玩家右侧成品台和绕台搬运路线
--!strict
local loadPaths, loadError = loadstring(game:GetService("ScriptEditorService"):GetEditorSource(game.ReplicatedStorage.Scripts.Shared.FarmScenePaths), "FarmScenePaths")
assert(loadPaths, loadError)
local Paths = loadPaths()
assert(not game:GetService("RunService"):IsRunning(), "Edit audit only")
local models = game.ServerStorage.Models
local original = models:WaitForChild("FarmRestaurantOriginalLayout")
local maps: { Instance } = { models.PersonalFarmTemplate }
for _, map in workspace.PersonalFarms:GetChildren() do table.insert(maps, map) end
local function Part(parent: Instance, name: string): BasePart
	local part: Instance? = nil
 if parent == original then part = parent:FindFirstChild(name)
 elseif parent.Name == "Anchors" then
  local group = if name == "StockShelf" or name == "StockShelfTop" then "Kitchen" elseif name == "PackageShelfTop" then "Packing" else "Anchors"
  part = (parent.Parent :: Instance):WaitForChild(group):FindFirstChild(name)
 else part = Paths.Find(parent, name) end
	assert(part and part:IsA("BasePart"), "Missing " .. name)
	return part
end
local function SamePose(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 0.001 and a.UpVector:Dot(b.UpVector) > 0.9999 and a.LookVector:Dot(b.LookVector) > 0.9999
end
local checked = 0
for _, map in maps do
	local restaurant = Paths.Require(map, "RestaurantAnchors")
	assert(restaurant)
	local transform = Part(restaurant, "KitchenEntranceSign").CFrame * Part(original, "KitchenEntranceSign").CFrame:Inverse()
	-- 原始区域（包括重复名称的四条边框）逐件比对几何、颜色及指引文字。
	for _, source in original:GetChildren() do
		if source:IsA("BasePart") and source.Name ~= "PrepTable" and source.Name ~= "PrepTop" then
			local parent = map:WaitForChild("Restaurant")
			local match: BasePart? = nil
			for _, candidate in parent:GetDescendants() do
				if candidate:IsA("BasePart") and (candidate.Name == source.Name or source.Name == "DepositBorder" and candidate.Name:match("^DepositBorder%d+$") ~= nil) and SamePose(candidate.CFrame, transform * source.CFrame) and (candidate.Size - source.Size).Magnitude < 0.001 then match = candidate; break end
			end
			assert(match, "Original layout changed: " .. map.Name .. "/" .. source.Name)
			assert(match.Color == source.Color and match.Material == source.Material and match.Transparency == source.Transparency, "Original style changed")
			for _, text in source:GetDescendants() do
				if text:IsA("TextLabel") then
					local label = match:FindFirstChild(text.Name, true)
					assert(label and label:IsA("TextLabel") and label.Text == text.Text, "Original direction sign changed")
				end
			end
		end
	end
	for _, part in (restaurant.Parent :: Instance):GetDescendants() do
		assert(not (part:IsA("BasePart") and (part.Name:match("^DisplayFood%d+$") or part.Name == "PrepTable" or part.Name == "PrepTop" or part.Name == "Oven" or part.Name == "OvenDoor" or part.Name == "OvenWindow")), "Unused part remains: " .. part.Name)
	end
	local management = Part(restaurant, "UpgradeZone")
	assert(SamePose(management.CFrame, transform * CFrame.new(-0.6, 0.13, 23.3) * CFrame.Angles(0, math.pi, 0)), "Restaurant management must match the selected Plot01 layout")
	local borderCount = 0
	for _, child in (restaurant.Parent :: Instance):GetDescendants() do if child.Name:match("^DepositBorder%d+$") then borderCount += 1 end end
	assert(borderCount == 4)
	local sell, input = Part(map, "Sell"), Part(restaurant, "FoodDepositTarget")
	local stock, top = Part(restaurant, "StockShelf"), Part(restaurant, "StockShelfTop")
	local output, display = Part(restaurant, "PackageShelfTop"), Part(restaurant, "PackedDisplay")
	local pickup, approach = Part(restaurant, "PackagePickupSpot"), Part(restaurant, "PackageApproachSpot")
	local pickupZone, packer = Part(restaurant, "PackagePickupZone"), Part(restaurant, "PackerSpot")
	assert(pickupZone:GetAttribute("FarmUIEntry") == "PackagePickup", "Package pickup must expose explicit input interaction")
	local toward = stock.Position - sell.Position
	local forward = Vector3.new(toward.X, 0, toward.Z).Unit
	assert((output.Position - stock.Position):Dot(forward:Cross(Vector3.yAxis)) > 0, "Output table must be on player's right")
	assert((packer.Position - stock.Position):Dot(forward) > 0 and packer.CFrame.LookVector:Dot(-forward) > 0.99, "Packer must stand behind original food shelf and face food")
	local inputLocal = top.CFrame:PointToObjectSpace(input.Position)
	assert(math.abs(inputLocal.X) < top.Size.X / 2 and math.abs(inputLocal.Z) < top.Size.Z / 2 and inputLocal.Y > 0, "Food must land on original shelf")
	local localDisplay = output.CFrame:PointToObjectSpace(display.Position)
	assert(math.abs(localDisplay.Y - 0.1 - output.Size.Y / 2) < 0.001, "Package base not on output tabletop")
	assert(math.abs(localDisplay.X) + 0.835 <= output.Size.X / 2 and math.abs(localDisplay.Z) + 0.635 <= output.Size.Z / 2, "Package stack outside output table")
	local offset = sell.CFrame:PointToObjectSpace(pickupZone.Position)
	assert(math.abs(offset.X) > (sell.Size.X + pickupZone.Size.X) / 2 or math.abs(offset.Z) > (sell.Size.Z + pickupZone.Size.Z) / 2, "Food and package zones overlap")
	local routes = {
		{ Part(restaurant, "WorkerSpot1").Position, approach.Position },
		{ Part(restaurant, "WorkerSpot2").Position, approach.Position },
		{ approach.Position, pickup.Position },
		{ approach.Position, Part(restaurant, "CounterDropSpot").Position },
		{ Part(restaurant, "CounterDropSpot").Position, Part(restaurant, "WorkerSpot2").Position },
	}
	for _, route in routes do
		for _, part in map:GetDescendants() do
			if part:IsA("BasePart") and (part.CanCollide or part.Name == "PackageShelf" or part.Name == "PackageShelfTop") then
				for step = 0, 30 do
					local point = part.CFrame:PointToObjectSpace(route[1]:Lerp(route[2], step / 30) + Vector3.new(0, 1.5, 0))
					assert(not (math.abs(point.X) < part.Size.X / 2 + 0.6 and math.abs(point.Z) < part.Size.Z / 2 + 0.6 and math.abs(point.Y) < part.Size.Y / 2), "Transport route blocked by " .. part:GetFullName())
				end
			end
		end
	end
	checked += 1
end
return { layouts = checked, originalDeliveryRestored = true, outputOnPlayerRight = true, packagesOnOutputTable = true, transportRoutesClear = true }
