-- Studio Edit 武器预览迁移：删除旧展示模型，仅保留指向正式武器模板的阶位契约
local UI = game:GetService("ReplicatedStorage").UI
local count = 0
local function Configure(viewport, tier)
	viewport:SetAttribute("PreviewWeaponTier", tier)
	viewport:SetAttribute("PreviewFieldOfView", 35)
	viewport:SetAttribute("ViewDirection", Vector3.new(-1, 0.7, -1.5))
	viewport.Ambient = Color3.fromRGB(200, 200, 200)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-1, -1, -1)
	viewport:FindFirstChildOfClass("WorldModel"):ClearAllChildren()
	count += 1
end
for _, name in { "FarmWeaponShopFrame", "FarmEquipmentFrame" } do
	for tier = 1, 5 do Configure(UI[name].PanelFrame.ItemsScrollingFrame["Item" .. tier .. "Frame"].Preview, tier) end
end
for tier = 1, 5 do Configure(UI.FarmWeaponEnhanceFrame.PanelFrame["WeaponPreview" .. tier], tier) end
Configure(UI.FarmToolShopFrame.PanelFrame.WeaponShopCardFrame.Preview, 0)
Configure(UI.FarmToolShopFrame.PanelFrame.WeaponEnhanceCardFrame.Preview, 0)
return "Unified " .. count .. " weapon preview contracts"
