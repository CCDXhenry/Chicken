-- WeaponShop 独立窗口控制器：绑定对应购买行为与生命周期
--!strict
local Common = require(script.Parent.Common)
local Storage = game:GetService("ReplicatedStorage")
local Config = require(Storage.Scripts.Shared.FarmEconomyConfig)
local Info = require(script.Parent.Parent.ClientGameInfo)
local Controller = {}
function Controller.Bind(ctx: Common.Context): ()
	local list = ctx.panel:WaitForChild("ItemsScrollingFrame")
	local nextTier = 2
	local function Render(): ()
		local info = Info.GetFarmInfo()
		local levels = info.weaponLevels or { ["1"] = 1 }
		nextTier = #Config.Weapons + 1
		for tier = 2, #Config.Weapons do if (levels[tostring(tier)] or 0) == 0 then nextTier = tier; break end end
		Common.Wallet(ctx)
		for tier, weapon in Config.Weapons do
			local card = list:WaitForChild("Item" .. tier .. "Frame")
			local owned = (levels[tostring(tier)] or 0) > 0
			Common.Label(card, "NameText", "Tier " .. tier .. " weapon")
			Common.Label(card, "DetailText", weapon.damage .. " damage  /  " .. weapon.maximumTargets .. " targets")
			Common.State(Common.Button(card, "ActionButton"), if owned then "Owned" elseif tier ~= nextTier then "Unlock previous first" elseif ctx.pending then "Working…" else Common.Price(weapon.price), not ctx.pending and tier == nextTier and info.cash >= weapon.price)
		end
	end
	for tier = 1, #Config.Weapons do
		local button = Common.Button(list:WaitForChild("Item" .. tier .. "Frame"), "ActionButton")
		local function OnPurchase(): () if button.Active and tier == nextTier then Common.Submit(ctx, { action = "buyZap", expectedStep = nextTier - 1 }, Render) end end
		ctx.window.scope:Connect(button.Activated:Connect(OnPurchase))
	end
	Common.Observe(ctx, Render)
end
return Controller
