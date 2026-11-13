-- 独立购买窗口绑定器：展示当前与下一档能力并发送带进度校验的升级请求
--!strict
local Storage = game:GetService("ReplicatedStorage")
local Config = require(Storage.Scripts.Shared.FarmEconomyConfig)
local Texts = require(Storage.Scripts.Shared.GameTexts)
local Format = require(Storage.Scripts.Shared.FarmNumberFormat)
local Info = require(script.Parent.Parent.ClientGameInfo)
local Common = require(script.Parent.Common)
local Purchase = {}
function Purchase.Bind(ctx: Common.Context, action: string): ()
	local details = ctx.panel:WaitForChild("DetailsFrame")
	local button = Common.Button(details, "PurchaseButton")
	local price: number? = nil
	local step = 1
	local function Render(): ()
		local info = Info.GetFarmInfo()
		local current, nextValue, extra, name = "", "", "", ""
		price = nil
		if action == "buyZap" then
			local levels = info.weaponLevels or { ["1"] = 1 }
			local nextTier: number? = nil
			for tier = 2, #Config.Weapons do if (levels[tostring(tier)] or 0) == 0 then nextTier = tier; break end end
			step = (nextTier or (#Config.Weapons + 1)) - 1
			name = if nextTier then "Tier " .. nextTier .. " weapon" else "All weapons owned"
			current = "Equipped damage  " .. tostring(info.damage or 2)
			if nextTier then local w = Config.Weapons[nextTier]; price = w.price; nextValue = "New damage  " .. Config.GetDamage(nextTier, 1); extra = tostring(w.range) .. " range  /  " .. w.maximumTargets .. " targets" end
			for tier = 1, #Config.Weapons do Common.Label(ctx.panel:WaitForChild("Tier" .. tier .. "Frame"), "StateText", "T" .. tier .. if (levels[tostring(tier)] or 0) > 0 then " Owned" else " Locked") end
		elseif action == "enhanceWeapon" then
			for tier = 1, #Config.Weapons do (ctx.panel:WaitForChild("WeaponPreview" .. tier) :: ViewportFrame).Visible = tier == info.zap end
			local level = info.weaponLevel or 1
			step = Config.GetWeaponProgressStep(info.zap, level)
			price = Config.Weapons[info.zap].enhancementPrices[level]
			name = "Tier " .. info.zap .. "  /  Level " .. level
			current = "Current damage  " .. Config.GetDamage(info.zap, level)
			nextValue = if price then "Next damage  " .. Config.GetDamage(info.zap, level + 1) else "Your weapon is fully enhanced"
			extra = "Enhancement stays with this weapon"
		elseif action == "buyCollect" then
			step = info.collect
			local a, b = Config.Collectors[step], Config.Collectors[step + 1]
			name = "Tier " .. step .. " collector"
			current = a.range .. " range  /  " .. a.maximumItems .. " items"
			if b then price = b.price; nextValue = b.range .. " range  /  " .. b.maximumItems .. " items" else nextValue = "Your collector is fully upgraded" end
			extra = "Collect more with every trip"
		elseif action == "buyBasket" then
			step = info.basketTier or 1
			local a, b = Config.Baskets[step], Config.Baskets[step + 1]
			name = "Tier " .. step .. " basket"
			current = "Current capacity  " .. a.capacityKg .. " kg"
			if b then price = b.price; nextValue = "Next capacity  " .. b.capacityKg .. " kg" else nextValue = "Your basket is fully upgraded" end
			extra = "In your basket  " .. tostring(info.basketWeight or 0) .. " kg"
		else
			step = info.restaurantLevel
			local a, b = Config.Restaurants[step], Config.Restaurants[step + 1]
			name = "Restaurant level " .. step
			current = Texts.Farm.FarmUIWorkers.source:format(a.workers, string.format("%g", a.speed * a.workers))
			if b then price = b.price; nextValue = Texts.Farm.FarmUIWorkers.source:format(b.workers, string.format("%g", b.speed * b.workers)) else nextValue = "Your restaurant is fully upgraded" end
			extra = Texts.Farm.RestaurantStock.source:format(info.waiting or 0, info.processing or 0, info.packed or 0, info.carrying or 0, info.counter or 0, Format.Number(info.expectedValue or 0))
		end
		Common.Wallet(ctx)
		Common.Label(details, "ItemNameText", name)
		Common.Label(details, "CurrentText", current)
		Common.Label(details, "NextText", nextValue)
		Common.Label(details, "ExtraText", extra)
		Common.State(button, if ctx.pending then "Working…" elseif price and info.cash < price then "Need " .. Common.Price(price - info.cash) else Common.Price(price), not ctx.pending and price ~= nil and info.cash >= (price or math.huge))
	end
	local function OnPurchase(): () if button.Active then Common.Submit(ctx, { action = action, expectedStep = step }, Render) end end
	ctx.window.scope:Connect(button.Activated:Connect(OnPurchase))
	Common.Observe(ctx, Render)
end
return Purchase
