-- 拾取工具与鸡筐预制几何：只在 Edit 归档时生成模板，运行时不得调用
--!strict

export type ModelsFolder = Folder

local function Color(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

type PartSpec = {
	name: string,
	size: Vector3,
	offset: Vector3,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?,
}

local function MakeModel(name: string, specs: { PartSpec }): Model
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "RootPart"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.CFrame = CFrame.new()
	root.Transparency = 1
	root.Anchored = false
	root.Massless = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Parent = model
	model.PrimaryPart = root
	for _, spec in specs do
		local part = Instance.new("Part")
		part.Name = spec.name
		part.Size = spec.size
		part.CFrame = CFrame.new(spec.offset)
		part.Color = spec.color
		part.Material = spec.material
		part.Shape = spec.shape or Enum.PartType.Block
		part.Anchored = false
		part.Massless = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Name = spec.name .. "Weld"
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = root
	end
	return model
end

local function Part(name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?): PartSpec
	return { name = name, size = size, offset = offset, color = color, material = material, shape = shape }
end

local function CollectorSpecs(tier: number): { PartSpec }
	if tier == 1 then
		return {
			Part("Palm", Vector3.new(0.62, 0.22, 0.78), Vector3.new(0, 0.36, 0), Color(176, 104, 56), Enum.Material.Fabric),
			Part("Cuff", Vector3.new(0.5, 0.16, 0.34), Vector3.new(0, 0.18, 0.04), Color(120, 72, 40), Enum.Material.Fabric),
			Part("FingerBand", Vector3.new(0.58, 0.08, 0.22), Vector3.new(0, 0.48, -0.24), Color(212, 164, 96), Enum.Material.Fabric),
		}
	elseif tier == 2 then
		return {
			Part("Grip", Vector3.new(0.22, 0.86, 0.22), Vector3.new(0, 0.46, 0), Color(146, 96, 48), Enum.Material.Wood, Enum.PartType.Cylinder),
			Part("Blade", Vector3.new(1.28, 0.1, 0.5), Vector3.new(0, 0.96, 0.18), Color(196, 202, 208), Enum.Material.Metal),
			Part("Brace", Vector3.new(0.16, 0.28, 0.16), Vector3.new(0, 0.78, 0.04), Color(120, 124, 130), Enum.Material.Metal),
		}
	elseif tier == 3 then
		return {
			Part("Canister", Vector3.new(0.52, 0.96, 0.52), Vector3.new(0, 0.56, 0), Color(48, 140, 150), Enum.Material.Metal, Enum.PartType.Cylinder),
			Part("Hose", Vector3.new(0.14, 0.14, 0.74), Vector3.new(0.3, 0.42, 0.16), Color(40, 44, 48), Enum.Material.SmoothPlastic),
			Part("Nozzle", Vector3.new(0.32, 0.2, 0.36), Vector3.new(0.46, 0.42, 0.5), Color(180, 190, 198), Enum.Material.Metal),
		}
	elseif tier == 4 then
		return {
			Part("Tank", Vector3.new(0.64, 1.16, 0.64), Vector3.new(0, 0.66, 0), Color(70, 78, 88), Enum.Material.Metal, Enum.PartType.Cylinder),
			Part("Intake", Vector3.new(1.08, 0.28, 0.74), Vector3.new(0, 1.18, 0.26), Color(230, 120, 40), Enum.Material.Metal),
			Part("Grip", Vector3.new(0.2, 0.62, 0.2), Vector3.new(0.42, 0.4, -0.08), Color(146, 96, 48), Enum.Material.Wood, Enum.PartType.Cylinder),
			Part("Vent", Vector3.new(0.32, 0.1, 0.32), Vector3.new(0, 0.98, -0.22), Color(255, 170, 60), Enum.Material.Neon),
		}
	end
	return {
		Part("Core", Vector3.new(0.42, 0.42, 0.42), Vector3.new(0, 0.58, 0), Color(80, 220, 255), Enum.Material.Neon, Enum.PartType.Ball),
		Part("RingA", Vector3.new(0.88, 0.08, 0.88), Vector3.new(0, 0.58, 0), Color(40, 48, 70), Enum.Material.Metal, Enum.PartType.Cylinder),
		Part("RingB", Vector3.new(1.18, 0.06, 1.18), Vector3.new(0, 0.78, 0), Color(54, 64, 92), Enum.Material.Metal, Enum.PartType.Cylinder),
		Part("Emitter", Vector3.new(0.22, 0.22, 0.42), Vector3.new(0, 0.58, 0.48), Color(180, 255, 255), Enum.Material.Neon),
	}
end

local BasketAccents = {
	{ name = "WovenBand", body = Color(181, 116, 54), accent = Color(237, 181, 104), bodyMaterial = Enum.Material.Wood, accentMaterial = Enum.Material.Fabric },
	{ name = "WoodRim", body = Color(122, 78, 40), accent = Color(92, 58, 28), bodyMaterial = Enum.Material.Wood, accentMaterial = Enum.Material.Wood },
	{ name = "IronRim", body = Color(128, 132, 138), accent = Color(78, 82, 88), bodyMaterial = Enum.Material.Metal, accentMaterial = Enum.Material.Metal },
	{ name = "AlloyBrace", body = Color(96, 112, 130), accent = Color(168, 178, 190), bodyMaterial = Enum.Material.Metal, accentMaterial = Enum.Material.Metal },
	{ name = "PneumaticCap", body = Color(48, 52, 64), accent = Color(80, 220, 255), bodyMaterial = Enum.Material.Metal, accentMaterial = Enum.Material.Neon },
}

local function BasketSpecs(tier: number): { PartSpec }
	local accent = BasketAccents[tier]
	local scale = 1 + (tier - 1) * 0.12
	local width, height, depth = 1.9 * scale, 0.9 * scale, 1.2 * scale
	local specs = {
		Part("Basket", Vector3.new(width, height, depth), Vector3.new(0, height / 2, 0), accent.body, accent.bodyMaterial),
		Part(accent.name, Vector3.new(width + 0.08 * scale, 0.12 * scale, depth + 0.08 * scale), Vector3.new(0, height * 0.72, 0), accent.accent, accent.accentMaterial),
	}
	local roast = Color(239, 149, 59)
	local cargoY = height + 0.16 * scale
	local cargoSize = Vector3.new(0.42 * scale, 0.34 * scale, 0.42 * scale)
	local spots = {
		Vector3.new(-0.32 * scale, cargoY, -0.22 * scale),
		Vector3.new(0.32 * scale, cargoY, -0.22 * scale),
		Vector3.new(-0.32 * scale, cargoY, 0.22 * scale),
		Vector3.new(0.32 * scale, cargoY, 0.22 * scale),
	}
	for index, spot in spots do
		table.insert(specs, Part("Cargo" .. index, cargoSize, spot, roast, Enum.Material.SmoothPlastic, Enum.PartType.Ball))
	end
	return specs
end

local function ReplaceChild(parent: Instance, name: string, replacement: Instance): ()
	local existing = parent:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	replacement.Name = name
	replacement.Parent = parent
end

local function Install(modelsFolder: ModelsFolder): string
	local collectors = modelsFolder:FindFirstChild("Collectors")
	if not (collectors and collectors:IsA("Folder")) then
		if collectors then
			collectors:Destroy()
		end
		local folder = Instance.new("Folder")
		folder.Name = "Collectors"
		folder.Parent = modelsFolder
		collectors = folder
	end
	local baskets = modelsFolder:FindFirstChild("Baskets")
	if not (baskets and baskets:IsA("Folder")) then
		if baskets then
			baskets:Destroy()
		end
		local folder = Instance.new("Folder")
		folder.Name = "Baskets"
		folder.Parent = modelsFolder
		baskets = folder
	end
	local names = {}
	for tier = 1, 5 do
		local collectorName = "Collector_T" .. tier
		local basketName = "Basket_T" .. tier
		ReplaceChild(collectors :: Folder, collectorName, MakeModel(collectorName, CollectorSpecs(tier)))
		ReplaceChild(baskets :: Folder, basketName, MakeModel(basketName, BasketSpecs(tier)))
		table.insert(names, collectorName)
		table.insert(names, basketName)
	end
	return table.concat(names, ",")
end

return Install
