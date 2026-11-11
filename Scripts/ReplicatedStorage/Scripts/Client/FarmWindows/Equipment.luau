-- 已拥有装备独立窗口：展示各阶武器的等级并切换当前武器
--!strict
local Storage = game:GetService("ReplicatedStorage")
local Config = require(Storage.Scripts.Shared.FarmEconomyConfig)
local Info = require(script.Parent.Parent.ClientGameInfo)
local Common = require(script.Parent.Common)
local Equipment = {}
function Equipment.Bind(ctx: Common.Context): ()
	local list = ctx.panel:WaitForChild("ItemsScrollingFrame")
	local function Render(): ()
		local info = Info.GetFarmInfo()
		local levels = info.weaponLevels or { ["1"] = 1 }
		Common.Wallet(ctx)
		for tier = 1, #Config.Weapons do
			local level = levels[tostring(tier)] or 0
			local card = list:WaitForChild("Item" .. tier .. "Frame")
			Common.Label(card, "NameText", "Tier " .. tier .. " weapon")
			Common.Label(card, "DetailText", if level > 0 then "Lv." .. level .. "  /  " .. Config.GetDamage(tier, level) .. " damage" else "Available at the tool shed")
			Common.State(Common.Button(card, "ActionButton"), if ctx.pending then "Working…" elseif level == 0 then "Not owned" elseif tier == info.zap then "Equipped" else "Equip", not ctx.pending and level > 0 and tier ~= info.zap)
		end
	end
	for tier = 1, #Config.Weapons do
		local button = Common.Button(list:WaitForChild("Item" .. tier .. "Frame"), "ActionButton")
		local function OnEquip(): () if button.Active then Common.Submit(ctx, { action = "equipWeapon", tier = tier }, Render) end end
		ctx.window.scope:Connect(button.Activated:Connect(OnEquip))
	end
	Common.Observe(ctx, Render)
end
return Equipment
