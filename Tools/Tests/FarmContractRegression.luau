-- 新版契约离线回归：验证数值边界、品质分布、独立默认档和经营快照，不访问 Roblox 服务
--!strict
local Config = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmEconomyConfig")
local Save = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmSaveData")

local checks = 0
local function Check(condition: boolean, message: string): ()
	assert(condition, message)
	checks += 1
end
local function Reject(value: unknown, message: string): ()
	local valid = Save.Validate(value)
	Check(not valid, message)
end
local function Cargo(id: string): Save.Cargo
	return { itemId = id, speciesId = "rabbit", qualityId = "golden", weightKg = 6, saleValue = 500, configVersion = 1 }
end

Check(#Config.Species == 5 and #Config.Weapons == 5 and #Config.Collectors == 5 and #Config.Baskets == 5 and #Config.Restaurants == 5, "all five tiers exist")
local counts: { [string]: number } = {}
for i = 0, 9999 do
	local quality = Config.RollQuality((i + 0.5) / 10000)
	counts[quality] = (counts[quality] or 0) + 1
end
Check(counts.normal == 9000 and counts.golden == 800 and counts.rainbow == 180 and counts.giant == 20, "stratified probability distribution")
Check(Config.RollQuality(0) == "normal" and Config.RollQuality(1) == "giant", "engine inclusive random endpoints accepted")
local accepted = pcall(function(): () Config.RollQuality(1.01) end)
Check(not accepted, "samples outside engine range rejected")
local rabbit = Config.GetSpecies("rabbit")
local golden = Config.GetQuality("golden")
assert(rabbit and golden)
Check(rabbit.health * golden.healthMultiplier == 12 and rabbit.weightKg * golden.weightMultiplier == 6 and rabbit.saleValue * golden.valueMultiplier == 500, "golden rabbit contract")
Check(rabbit.instantHatchPrice == 25, "all rabbit qualities cost 25")
Check(Config.GetDamage(1, 1) == 2 and Config.GetDamage(1, 2) == 3 and Config.Weapons[1].enhancementPrices[1] == 30, "first enhancement")
Check(Config.GetDamage(2, 3) == 12, "T2 Lv3 damage budget")
for tier, species in Config.Species do
	Check(Config.GetDamage(tier, 1) == species.health, "same tier base weapon one shots normal")
	Check(Config.GetDamage(tier, 3) == species.health * 2, "Lv3 one shots golden")
	Check(Config.GetDamage(tier, 5) == species.health * 3, "Lv5 one shots rainbow")
	Check(Config.Baskets[tier].capacityKg == species.weightKg * 12, "same tier carries twelve normal")
end
Check(Config.Baskets[1].capacityKg == 12 and Config.Baskets[2].capacityKg == 36 and Config.Baskets[1].capacityKg < 27, "basket boundary contract")
local first, second = Save.CreateDefault(), Save.CreateDefault()
first.cash = 40
first.weaponLevels["1"] = 2
table.insert(first.basket, Cargo("basket-1"))
Check(second.cash == 0 and second.weaponLevels["1"] == 1 and #second.basket == 0, "defaults do not share mutable fields")
Check(Save.Validate(first), "default plus valid cargo")
table.insert(first.kitchen, { cargo = Cargo("order-1"), state = "Processing", remainingSeconds = 1.1, speedSnapshot = 1.35, durationSnapshot = 6 / 1.35 })
local snapshot = Save.Copy(first)
first.basket[1].saleValue = 999
first.kitchen[1].remainingSeconds = 0
first.weaponLevels["1"] = 3
Check(snapshot.basket[1].saleValue == 500 and snapshot.kitchen[1].remainingSeconds == 1.1 and snapshot.weaponLevels["1"] == 2, "snapshot owns nested data")
Check(Save.Validate(snapshot), "snapshot round trip remains valid")
local bad = Save.Copy(snapshot)
bad.cash = 0 / 0
Reject(bad, "NaN cash rejected")
bad = Save.Copy(snapshot)
bad.kitchen[1].cargo.itemId = bad.basket[1].itemId
Reject(bad, "duplicate item across basket and processing rejected")
bad = Save.Copy(snapshot)
bad.version = 99
Reject(bad, "future farm version rejected")
bad = Save.Copy(snapshot)
bad.kitchen[1].remainingSeconds = math.huge
Reject(bad, "absolute or infinite timer rejected")
bad = Save.Copy(snapshot)
bad.kitchen[1].state = "Waiting"
Reject(bad, "waiting order cannot carry processing snapshot")
bad = Save.Copy(snapshot)
bad.equippedWeaponTier = 5
Reject(bad, "unowned equipment rejected")
bad = Save.Copy(snapshot)
bad.unlockedSpecies.dragon = true
Reject(bad, "nonsequential unlock rejected")
bad = Save.Copy(snapshot)
bad.basket[1].weightKg = -1
Reject(bad, "negative cargo weight rejected")
print("FarmContractRegression passed:", checks, "checks; 10000 quality samples")
