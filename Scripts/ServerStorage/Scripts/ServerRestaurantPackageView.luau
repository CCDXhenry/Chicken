-- 包装成品表现：按实际库存显示有限代表盒，玩家携带通过焊接跟随角色
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Config = require(ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared"):WaitForChild("FarmRestaurantConfig"))
local View = {}

function View.Sync(parent: Instance, count: number, origin: CFrame, ownerId: number, mount: BasePart?): ()
	local existing = parent:FindFirstChild("Packages")
	local folder: Folder
	if existing and existing:IsA("Folder") then folder = existing else
		folder = Instance.new("Folder")
		folder.Name, folder.Parent = "Packages", parent
	end
	if folder:GetAttribute("Count") == count then return end
	folder:SetAttribute("Count", count)
	folder:SetAttribute("OwnerUserId", ownerId)
	folder:ClearAllChildren()
	local template = ServerStorage:WaitForChild("Models"):WaitForChild("FarmPackageTemplate") :: Model
	for index = 1, math.min(count, Config.VisualPackageLimit) do
		local model = template:Clone()
		model.Name = "Package" .. index
		local slot = index - 1
		model:PivotTo(origin * CFrame.new((slot % 2 - 0.5) * 0.85, math.floor(slot / 4) * 0.5, (math.floor(slot / 2) % 2 - 0.5) * 0.65))
		model:SetAttribute("OwnerUserId", ownerId)
		if mount and model.PrimaryPart then
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then part.Anchored = false; part.Massless = true end
			end
			local weld = Instance.new("WeldConstraint")
			weld.Name, weld.Part0, weld.Part1 = "CarrierWeld", mount, model.PrimaryPart
			weld.Parent = model.PrimaryPart
		end
		model.Parent = folder
	end
end

return View
