-- 农场实例路径契约：集中解析静态功能节点与运行期容器，兼容客户端流送缺失
--!strict
local Paths = {}
local StaticPaths: { [string]: { string } } = {
 FarmSpawn = {"Anchors", "FarmSpawn"}, OwnerSign = {"Anchors", "OwnerSign"},
 Shop = {"ToolShop", "Anchors", "Shop"}, FieldSign = {"Production", "Anchors", "FieldSign"},
 Nest = {"Production", "Nest"}, HatchField = {"Production", "HatchField"},
 Chute = {"Production", "Nest", "Anchors", "Chute"},
 ProductionSign = {"Production", "Nest", "Anchors", "ProductionSign"},
 NestUpgradeZone = {"Production", "Nest", "Anchors", "UpgradeZone"},
 Restaurant = {"Restaurant"}, RestaurantAnchors = {"Restaurant", "Anchors"},
 Runtime = {"Runtime"}, Eggs = {"Runtime", "Eggs"},
 LiveAnimals = {"Runtime", "LiveAnimals"}, CookedFood = {"Runtime", "CookedFood"},
 RestaurantRuntime = {"Runtime", "Restaurant"},
}
local RestaurantAnchors = {
 "Sell", "FoodDepositTarget", "PackerSpot", "PackageApproachSpot", "PackagePickupSpot",
 "PackagePickupZone", "CounterDropSpot", "CounterDropZone", "PackedDisplay", "CounterDisplay",
 "WorkerSpot1", "WorkerSpot2", "QueueHead", "QueueStart", "QueueExit", "KitchenApproach",
 "StockSign", "FarmStaffSign", "KitchenEntranceSign", "DeliveryDirection", "QueueSign", "UpgradeZone",
}
for _, name in RestaurantAnchors do
 StaticPaths[if name == "UpgradeZone" then "RestaurantUpgradeZone" else name] = {"Restaurant", "Anchors", name}
end

function Paths.Find(root: Instance, key: string): Instance?
 local segments = StaticPaths[key]
 assert(segments, "Unknown farm scene key: " .. key)
 local current: Instance? = root
 for _, name in segments do
  if not current then return nil end
  current = current:FindFirstChild(name)
 end
 return current
end
function Paths.Require(root: Instance, key: string): Instance
 local node = Paths.Find(root, key)
 assert(node, "Missing farm scene path " .. key .. " under " .. root:GetFullName())
 return node
end
function Paths.Part(root: Instance, key: string): BasePart
 local node = Paths.Require(root, key)
 assert(node:IsA("BasePart"), "Expected farm BasePart: " .. key)
 return node
end
-- 只供服务端经营流程创建动态容器，静态场景绝不由此补造。
function Paths.EnsureRuntime(root: Instance, key: string): Folder
 local segments = StaticPaths[key]
 assert(segments and segments[1] == "Runtime", "Expected runtime path: " .. key)
 local current = root
 for _, name in segments do
  local child = current:FindFirstChild(name)
  if not child then
   local folder = Instance.new("Folder")
   folder.Name, folder.Parent = name, current
   child = folder
  end
  assert(child and child:IsA("Folder"), "Expected runtime Folder: " .. name)
  current = child
 end
 return current :: Folder
end
Paths.StaticPaths = StaticPaths
Paths.RestaurantAnchors = RestaurantAnchors
return Paths
