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
			local seconds = species.weightKg * quality.weightMultiplier / (restaurant.speed * restaurant.workers)
			Check(math.abs(order.durationSnapshot - seconds) < 0.00001 and order.remainingSeconds == order.durationSnapshot and order.speedSnapshot == restaurant.speed * restaurant.workers, "weight / combined packer kg/s for every species, quality and restaurant")
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
local completed = Business.TickKitchen(restored, 11.5)
Check(completed == 1 and restored.cash == 0 and #restored.packed == 1 and #restored.kitchen == 0, "packing completes without money")
Check(Business.TickKitchen(restored, 100) == 0 and #restored.packed == 1, "packing cannot duplicate packages")
Check(Business.TakePackages(restored, "player") == 1 and #restored.playerCarry == 1 and #restored.packed == 0, "player takes entire ready batch")
Check(Business.TakePackages(restored, "1") == 0 and Business.TakePackages(restored, "2") == 0, "competing workers cannot claim same cargo")
Check(Business.PlacePackages(restored, "player") == 1 and restored.cash == 0, "counter drop does not settle")
Check(Business.PlacePackages(restored, "player") == 0, "duplicate drop no-op")
local soldCargo = Business.SellCounterOne(restored)
Check(soldCargo ~= nil and soldCargo.itemId == cargo.itemId and restored.cash == 2500, "customer purchase atomically removes stock and credits money")
Check(Business.SellCounterOne(restored) == nil and restored.cash == 2500, "repeat sale cannot settle twice")
farm.restaurantLevel = 5
Business.TickKitchen(farm, 0.1)
Check(farm.kitchen[1].speedSnapshot == 1 and math.abs(farm.kitchen[1].remainingSeconds - 11.4) < 0.00001, "upgrade leaves accepted speed unchanged")
Check(Business.TryCollect(farm, Business.CreateCargo("after-upgrade", "chicken", "normal")) and Business.DepositOne(farm), "new cargo after upgrade")
Business.TickKitchen(farm, 0)
Check(farm.kitchen[2].state == "Waiting", "single packer cannot start second order")
Business.TickKitchen(farm, 12)
Check(farm.kitchen[1].speedSnapshot == 3.8 and farm.kitchen[1].durationSnapshot == 1 / 3.8, "next order uses total upgraded throughput")
local bulk = Save.CreateDefault()
bulk.basketTier, bulk.restaurantLevel = 5, 4
for i = 1, 30 do
	Check(Business.TryCollect(bulk, Business.CreateCargo(tostring(i), "chicken", "normal")), "bulk cargo accepted")
	Business.DepositOne(bulk)
end
Check(#bulk.kitchen == 30, "no old 24 item kitchen limit")
Business.TickKitchen(bulk, 0)
Check(bulk.kitchen[1].state == "Processing" and bulk.kitchen[2].state == "Waiting", "one packer occupies FIFO item")
Check(bulk.kitchen[1].durationSnapshot == 1 / 3.2, "Lv4 folds former parallel capacity into one packer")
for _ = 1, 30 do Business.TickKitchen(bulk, 1 / 3.2) end
Check(#bulk.packed == 30 and bulk.cash == 0, "all completed food stays unsold")
Check(Business.TakePackages(bulk, "1") == 30 and Business.TakePackages(bulk, "player") == 0, "worker can claim unbounded batch atomically")
Check(Business.GetWeight(bulk) == 0, "packages do not occupy basket weight")
local snapshot = Save.Copy(bulk)
Check(Save.Validate(snapshot) and #snapshot.workerCarry["1"] == 30, "worker cargo persists")
Business.RestoreCarriedPackages(snapshot)
Check(#snapshot.packed == 30 and #snapshot.workerCarry["1"] == 0, "restore returns cargo to pickup area")
Business.RestoreCarriedPackages(snapshot)
Check(#snapshot.packed == 30, "restore is idempotent")
Check(Business.TakePackages(snapshot, "player") == 30 and Business.ReturnPackages(snapshot, "player") == 30, "death returns full player batch")
Business.TakePackages(snapshot, "2")
Business.PlacePackages(snapshot, "2")
local waiting, processing, expected = Business.GetKitchenCounts(snapshot)
Check(waiting == 0 and processing == 0 and expected == 300, "expected value includes all unsold stages")
for i = 1, 30 do
	local item = Business.SellCounterOne(snapshot)
	Check(item ~= nil and item.itemId == tostring(i), "counter buys FIFO by deposit order")
end
Check(snapshot.cash == 300 and Business.SellCounterOne(snapshot) == nil, "exactly once income across full batch")
local malformed = Save.Copy(bulk)
table.insert(malformed.counter, table.clone(malformed.workerCarry["1"][1]))
Check(not Save.Validate(malformed), "duplicate identity across queues rejected")
malformed = Save.Copy(bulk)
malformed.workerCarry["2"] = nil
Check(not Save.Validate(malformed), "missing carrier queue rejected")
Check(#bulk.workerCarry["1"] == 30 and #snapshot.workerCarry["1"] == 0, "snapshots own nested package arrays")
local staged = Save.CreateDefault()
local serde = require("@lune/serde")
for index, queue in { staged.packed, staged.playerCarry, staged.workerCarry["1"], staged.workerCarry["2"], staged.counter } do
	table.insert(queue, Business.CreateCargo("stage-" .. index, "rabbit", "golden"))
end
local roundTrip = serde.decode("json", serde.encode("json", Save.Copy(staged)))
Check(Save.Validate(roundTrip), "all package stages survive JSON save round trip")
Business.RestoreCarriedPackages(roundTrip)
Check(#roundTrip.packed == 4 and #roundTrip.counter == 1 and #staged.playerCarry == 1, "load restores all carriers but preserves counter and source snapshot")
Check(not Business.TryCollect(staged, table.clone(staged.counter[1])), "ground pickup cannot duplicate a counter item")
local pickupCommand = Request.Parse({ action = "takePackages", count = 99999, ownerId = 123 })
Check(pickupCommand ~= nil and pickupCommand.action == "takePackages" and ((pickupCommand :: unknown) :: { [string]: unknown }).count == nil, "pickup request accepts action and strips client cargo claims")
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
