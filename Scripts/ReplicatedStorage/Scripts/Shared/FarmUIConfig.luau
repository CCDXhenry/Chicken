-- 农场界面路由：定义独立窗口及场景入口，不保存视觉布局
--!strict
local Config = {}
Config.ScanSeconds = 0.15
Config.RequestTimeout = 2
Config.Windows = { "ToolShop", "WeaponShop", "WeaponEnhance", "CollectorShop", "BasketShop", "Species", "Restaurant", "Equipment", "Hatch" }
Config.ToolWindows = { WeaponShop = true, WeaponEnhance = true, CollectorShop = true, BasketShop = true }
Config.EntryWindows = { ToolShop = "ToolShop", Species = "Species", Restaurant = "Restaurant" }
Config.EntryLabels = { ToolShop = "Open tool shop", Species = "Manage species", Restaurant = "Manage restaurant", Hatch = "Inspect egg" }
Config.EntryPrompts = {
	ToolShop = { action = "Open", object = "Tool shop" },
	Species = { action = "Manage", object = "Species" },
	Restaurant = { action = "Manage", object = "Restaurant" },
}
return Config
