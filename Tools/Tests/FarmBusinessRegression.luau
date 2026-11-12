-- 个人经营离线回归：用原模块源码验证重量、FIFO、并行打包、快照恢复和请求净化
--!strict
local Config = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmEconomyConfig")
local Save = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmSaveData")
local Request = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmRequest")
local Format = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmNumberFormat")
local Business = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmBusiness")
local checks = 0
local function Check(condition: boolean, message: string): ()
	assert(condition, message)
	checks += 1
end
-- 各物种与品质仅通过实际重量影响耗时；速度为每名服务员 kg/s。
for _, species in Config.Species do
	for _, quality in Config.Qualities do
		for level, restaurant in Config.Restaurants do
			local sample = Save.CreateDefault()
			sample.basketTier, sample.restaurantLevel = 5, level
			local item = Business.CreateCargo("sample", species.key, quality.key)
			Check(Business.TryCollect(sample, item) and Business.DepositOne(sample), "sample enters kitchen")
			Business.TickKitchen(sample, 0)
			local order = sample.kitchen[1]
			local seconds = species.weightKg * quality.weightMultiplier / restaurant.speed
			Check(math.abs(order.durationSnapshot - seconds) < 0.00001 and order.remainingSeconds == order.durationSnapshot and order.speedSnapshot == restaurant.speed, "weight / single worker kg/s for every species, quality and restaurant")
		end
	end
end
local farm = Save.CreateDefault()
local other = Save.CreateDefault()
local cargo = Business.CreateCargo("giant-rabbit", "rabbit", "giant")
Check(cargo.weightKg == 12 and cargo.saleValue == 2500, "giant rabbit cargo")
Check(Business.TryCollect(farm, cargo), "exact capacity accepted")
local accepted, reason = Business.TryCollect(farm, Business.CreateCargo("chicken", "chicken", "normal"))
Check(not accepted and reason == "remainingCapacity", "remaining capacity rejection")
accepted, reason = Business.TryCollect(other, Business.CreateCargo("cow", "cow", "normal"))
Check(not accepted and reason == "itemTooHeavy", "empty basket rejection")
Check(Business.GetWeight(other) == 0 and other.cash == 0, "other player remains isolated")
Check(Business.DepositOne(farm) and #farm.basket == 0 and farm.kitchen[1].cargo.itemId == cargo.itemId, "same identity enters waiting")
Business.TickKitchen(farm, 0)
Check(farm.kitchen[1].state == "Processing" and farm.kitchen[1].remainingSeconds == 12, "12 kg giant rabbit takes 12 seconds at 1 kg/s")
Business.TickKitchen(farm, 0.5)
local saved = Save.Copy(farm)
local restored = Save.Copy(saved)
Check(Save.Validate(restored), "restored snapshot remains valid")
Check(restored.kitchen[1].remainingSeconds == saved.kitchen[1].remainingSeconds, "offline pause has no wall clock subtraction")
Check(restored.kitchen[1].remainingSeconds == 11.5 and restored.kitchen[1].durationSnapshot == 12 and restored.kitchen[1].speedSnapshot == 1, "partial progress and kg/s snapshot survive restore")
local restoredSold, restoredIncome = Business.TickKitchen(restored, 11.5)
Check(restoredSold == 1 and restoredIncome == 2500 and #restored.kitchen == 0, "restored order completes using saved remaining time")
restoredSold, restoredIncome = Business.TickKitchen(restored, 100)
Check(restoredSold == 0 and restoredIncome == 0 and restored.cash == 2500, "restored order cannot settle twice")
farm.restaurantLevel = 5
Business.TickKitchen(farm, 0.1)
Check(farm.kitchen[1].speedSnapshot == 1 and math.abs(farm.kitchen[1].remainingSeconds - 11.4) < 0.00001, "upgrade leaves accepted speed unchanged")
Check(Business.TryCollect(farm, Business.CreateCargo("after-upgrade", "chicken", "normal")) and Business.DepositOne(farm), "new cargo after upgrade")
Business.TickKitchen(farm, 0)
Check(farm.kitchen[2].speedSnapshot == 1.9 and farm.kitchen[2].durationSnapshot == 1 / 1.9, "idle worker accepts with upgraded kg/s")
local sold, income = Business.TickKitchen(farm, 12)
Check(sold == 2 and income == 2510 and farm.cash == 2510 and #farm.kitchen == 0, "settlement atomically removes orders and adds cash")
sold, income = Business.TickKitchen(farm, 100)
Check(sold == 0 and income == 0 and farm.cash == 2510, "repeated tick cannot settle twice")
local bulk = Save.CreateDefault()
bulk.basketTier = 5
for i = 1, 30 do
	Check(Business.TryCollect(bulk, Business.CreateCargo(tostring(i), "chicken", "normal")), "bulk cargo accepted")
	Business.DepositOne(bulk)
end
Check(#bulk.kitchen == 30, "no old 24 item kitchen limit")
bulk.restaurantLevel = 4
Business.TickKitchen(bulk, 0)
Check(bulk.kitchen[1].state == "Processing" and bulk.kitchen[2].state == "Processing" and bulk.kitchen[3].state == "Waiting", "two workers occupy FIFO items")
Check(bulk.kitchen[1].durationSnapshot == 1 / 1.6 and bulk.kitchen[2].durationSnapshot == 1 / 1.6, "parallel workers each use single worker speed")
Business.TickKitchen(bulk, 1 / 1.6)
Check(bulk.cash == 20 and #bulk.kitchen == 28 and bulk.kitchen[1].cargo.itemId == "3", "parallel settlement preserves FIFO")
local command = Request.Parse({ action = "zap", cash = 1000000 })
assert(command)
Check(((command :: unknown) :: { [string]: unknown }).cash == nil, "client cash stripped")
Check(Request.Parse({ action = "equipWeapon", tier = 0/0 }) == nil, "NaN request rejected")
Check(Request.Parse({ action = "confirm", confirmationId = string.rep("x", 129) }) == nil, "oversized confirmation rejected")
Check(Request.Parse({ action = "selectSpecies", speciesId = "unknown" }) == nil, "unknown species rejected")
Check(Request.Parse("zap") == nil, "new command parser ignores legacy strings")
Check(Format.Number(9999) == "9999" and Format.Number(10000) == "10K", "currency threshold")
Check(Format.Number(999950) == "1M" and Format.Number(999950000) == "1B", "rounding promotes unit")
Check(Format.Weight(999) == "999 kg" and Format.Weight(1000) == "1 t", "weight unit threshold")
print("FarmBusinessRegression passed:", checks, "checks; isolated profiles and snapshot restore")
