-- 农场层级 Edit 迁移：全量预检后原位归组，九套共享模板编号，失败回滚并支持重复执行
--!strict
assert(not game:GetService("RunService"):IsRunning(), "Edit only")
-- Script Sync 在 Edit 使用草稿；只读加载无副作用的路径契约，不提交草稿或覆写 Source。
local pathModule = game:GetService("ReplicatedStorage").Scripts.Shared.FarmScenePaths
local loadPaths, loadError = loadstring(game:GetService("ScriptEditorService"):GetEditorSource(pathModule), "FarmScenePaths")
assert(loadPaths, loadError)
local Paths = loadPaths()
local History = game:GetService("ChangeHistoryService")
local template = game.ServerStorage.Models.PersonalFarmTemplate
local roots: { Instance } = {template}
for index = 1, 8 do table.insert(roots, workspace.PersonalFarms:WaitForChild(string.format("Plot%02d", index))) end
local groups = {
 "Environment", "Environment/Ground", "Environment/Paths", "Environment/Boundary",
 "Environment/Boundary/Posts", "Environment/Boundary/Rails", "Environment/Landscaping",
 "Environment/Landscaping/Trees", "Environment/Landscaping/Flowers", "Environment/Landscaping/HayBales",
 "Production", "Production/HatchField", "Production/HatchField/Tiles", "Production/HatchField/Corners",
 "Production/Nest", "Production/Nest/Structure", "Production/Nest/Decorations", "Production/Nest/Anchors",
 "Production/Anchors", "Restaurant", "Restaurant/Structure", "Restaurant/Kitchen", "Restaurant/Packing",
 "Restaurant/Service", "Restaurant/Queue", "Restaurant/Decorations", "Restaurant/Anchors",
 "ToolShop", "ToolShop/Anchors", "Anchors",
}
local restaurantGroups: { [string]: string } = {}
local function Assign(group: string, names: { string }): ()
 for _, name in names do restaurantGroups[name] = "Restaurant/" .. group end
end
Assign("Anchors", Paths.RestaurantAnchors)
Assign("Structure", {"KitchenDoorLintel", "SideWall", "InteriorFloor", "FrontColumn", "FarmCanopyTrim", "KitchenSideBack", "KitchenSideFront", "FarmCanopyPost", "GoldRoofTrim", "CanopyFoot", "FarmCanopyBeam", "KitchenDoorTrim"})
Assign("Kitchen", {"KitchenFloor", "StockShelf", "StockShelfTop", "StaffAisle", "DepositBorder", "KitchenAccessPath"})
Assign("Packing", {"PackageShelf", "PackageShelfTop"})
Assign("Service", {"CounterSection", "CounterSectionTop", "ServiceCounter1", "ServiceCounter2", "CounterTop1", "CounterTop2", "Register1", "Register2", "RegisterPlaque", "RegisterStaffPlaque", "Lane1Lamp", "Lane2Lamp"})
Assign("Queue", {"CustomerPlaza", "QueueRail", "QueuePost", "QueueLane", "PlazaCurb"})
Assign("Decorations", {"Eye", "Beak", "EggMascot", "Marquee"})
local function Relative(node: Instance, root: Instance): string
 local names = {}
 local current: Instance? = node
 while current and current ~= root do table.insert(names, 1, current.Name); current = current.Parent end
 assert(current == root)
 return table.concat(names, "/")
end
local function Space(root: Instance): CFrame
 if root == template then return CFrame.identity end
 return (workspace.FarmPlots:FindFirstChild(root.Name) :: BasePart).CFrame
end
local function Identity(node: Instance, root: Instance): string
 return Relative(node, root) .. "|" .. node.ClassName
end
local function Destination(node: Instance): string?
 local parent = node.Parent
 assert(parent)
 local path = Relative(parent, template)
 local n = node.Name
 if parent == template then
  local destinations = {Ground="Environment", Paths="Environment", Boundary="Environment", Landscaping="Environment", Windmill="Environment", HatchField="Production", Nest="Production", ToolStand="ToolShop", FarmSpawn="Anchors", OwnerSign="Anchors", FieldSign="Production/Anchors", Shop="ToolShop/Anchors", Sell="Restaurant/Anchors"}
  return destinations[n]
 elseif path == "Boundary" then return "Environment/Boundary/" .. (if n == "FencePost" then "Posts" else "Rails")
 elseif path == "HatchField" then return "Production/HatchField/" .. (if n == "FieldTile" then "Tiles" else "Corners")
 elseif path == "Landscaping/Flowers" and (n == "HayBale" or n == "HayTwine") then return "Environment/Landscaping/HayBales"
 elseif path == "Nest" then
  if n == "Chute" or n == "ProductionSign" or n == "UpgradeZone" then return "Production/Nest/Anchors" end
  return "Production/Nest/" .. (if n == "Straw" or n == "NestEmblem" or n == "EmblemSpot" or n == "EggLaunchBand" then "Decorations" else "Structure")
 elseif path == "Restaurant" then
  if n == "Display" or n == "FloorDetails" then return "Restaurant/Decorations" end
  if n == "Boundary" then return "Restaurant/Structure" end
  assert(restaurantGroups[n], "Unclassified restaurant object: " .. n)
  return restaurantGroups[n]
 end
 return nil
end
-- Existing groups are moved, never replaced. All targets are matched before any write.
local already = template:GetAttribute("FarmHierarchyVersion") == 2
if already then
 for _, root in roots do
  assert(root:GetAttribute("FarmHierarchyVersion") == 2, "Mixed hierarchy versions")
  for key in Paths.StaticPaths do
   if key ~= "Runtime" and key ~= "Eggs" and key ~= "LiveAnimals" and key ~= "CookedFood" and key ~= "RestaurantRuntime" then Paths.Require(root, key) end
  end
  assert(not Paths.Find(root, "Runtime"), "Occupied farm cannot be reorganized")
 end
 return {roots=#roots, originalInstancesPerRoot=0, newFolders=0, version=2, alreadyOrganized=true, changes=0}
end
local descriptors = {}
local duplicateGroups: { [string]: { BasePart } } = {}
for _, node in template:GetDescendants() do
 local destination = Destination(node)
 table.insert(descriptors, {key=Identity(node, template), destination=destination, name=node.Name, node=node})
 if node:IsA("BasePart") then
  local key = (destination or Relative(node.Parent :: Instance, template)) .. "/" .. node.Name
  duplicateGroups[key] = duplicateGroups[key] or {}
  table.insert(duplicateGroups[key], node)
 end
end
local names: { [Instance]: string } = {}
for _, parts in duplicateGroups do
 if #parts > 1 then
  table.sort(parts, function(a, b)
   local acf, bcf = a.CFrame, b.CFrame
   local av = {acf.X, acf.Z, acf.Y, a.Size.X, a.Size.Y, a.Size.Z, select(4, acf:GetComponents())}
   local bv = {bcf.X, bcf.Z, bcf.Y, b.Size.X, b.Size.Y, b.Size.Z, select(4, bcf:GetComponents())}
   for i=1,#av do if math.abs(av[i]-bv[i]) > 0.000001 then return av[i]<bv[i] end end
   return false
  end)
  for index, part in parts do names[part] = part.Name .. string.format("%02d", index) end
 end
end
type Action = {node: Instance, parent: Instance?, name: string, destination: string?, newName: string}
local plans: { {root: Instance, actions: { Action }} } = {}
for _, root in roots do
 assert(root:IsA("Folder") and root:GetAttribute("OwnerUserId") == nil and not root:FindFirstChild("Runtime"), "Only vacant static farms can be reorganized")
 assert(root:GetAttribute("FarmHierarchyVersion") == nil, "Unexpected hierarchy version")
 local nodes: { [string]: { Instance } } = {}
 for _, node in root:GetDescendants() do
  local key = Identity(node, root)
  nodes[key] = nodes[key] or {}
  table.insert(nodes[key], node)
 end
 local actions: { Action } = {}
 for _, descriptor in descriptors do
  local matches = nodes[descriptor.key]
  assert(matches and #matches > 0, "Template mismatch in " .. root.Name .. ": " .. descriptor.key)
  local selected = 1
  if descriptor.node:IsA("BasePart") then
   local expected = Space(template):ToObjectSpace(descriptor.node.CFrame)
   selected = 0
   for i, candidate in matches do
    if candidate:IsA("BasePart") then
     local actual = Space(root):ToObjectSpace(candidate.CFrame)
     if (actual.Position-expected.Position).Magnitude < 0.001 and (candidate.Size-descriptor.node.Size).Magnitude < 0.001 and actual.LookVector:Dot(expected.LookVector) > 0.99999 and actual.UpVector:Dot(expected.UpVector) > 0.99999 then selected=i; break end
    end
   end
   assert(selected > 0, "Geometry mismatch in " .. root.Name .. ": " .. descriptor.key)
  end
  local node = table.remove(matches, selected)
  assert(node, "Preflight match was consumed")
  table.insert(actions, {node=node, parent=node.Parent, name=node.Name, destination=descriptor.destination, newName=names[descriptor.node] or descriptor.name})
 end
 for key, remaining in nodes do assert(#remaining == 0, "Extra instance in " .. root.Name .. ": " .. key) end
 local plan: {root: Instance, actions: { Action }} = {root=root, actions=actions}
 table.insert(plans, plan)
end
History:SetWaypoint("Before PersonalFarms hierarchy")
local created: { Instance } = {}
local function Group(root: Instance, path: string): Instance
 local current = root
 for name in string.gmatch(path, "[^/]+") do
  local child = current:FindFirstChild(name)
  if not child then
   local folder = Instance.new("Folder"); folder.Name = name; folder.Parent = current
   table.insert(created, folder)
   child = folder
  end
  assert(child)
  current = child
 end
 return current
end
local ok, failure = xpcall(function()
 for _, plan in plans do
  -- First move existing containers in template traversal order; then fill their new subgroups.
  for _, action in plan.actions do
   if action.destination then action.node.Parent = Group(plan.root, action.destination) end
   action.node.Name = action.newName
  end
  for _, path in groups do Group(plan.root, path) end
  plan.root:SetAttribute("FarmHierarchyVersion", 2)
  task.wait()
 end
end, debug.traceback)
if not ok then
 for _, plan in plans do
  for _, action in plan.actions do action.node.Name = action.name; action.node.Parent = action.parent end
  plan.root:SetAttribute("FarmHierarchyVersion", nil)
 end
 for i=#created,1,-1 do created[i]:Destroy() end
 error(failure)
end
History:SetWaypoint("After PersonalFarms hierarchy")
return {roots=#roots, originalInstancesPerRoot=#descriptors, newFolders=#created, version=2, alreadyOrganized=false, changes=#descriptors * #roots}
