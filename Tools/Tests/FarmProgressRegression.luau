-- 物种装备与电击离线回归：直接验证正式购买、强化和目标分配规则的边界
--!strict
local Config = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmEconomyConfig")
local Save = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmSaveData")
local Business = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmBusiness")
local Combat = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmCombatRules")
local Request = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmRequest")
local checks = 0
local function Check(value: boolean, message: string): () assert(value, message); checks += 1 end
local farm = Save.CreateDefault()
farm.cash = 299
Check(not Business.TryUnlockSpecies(farm, "rabbit") and farm.cash == 299, "species cannot spend insufficient balance")
Check(not Business.TryUnlockSpecies(farm, "sheep") and farm.cash == 299, "species requires previous unlock")
farm.cash = 500
Check(Business.TryUnlockSpecies(farm, "rabbit") and farm.cash == 200, "rabbit costs exactly 300")
Check(Business.SelectSpecies(farm, "rabbit") and farm.selectedSpeciesId == "rabbit", "select unlocked species")
Check(Business.SelectSpecies(farm, "chicken") and farm.cash == 200, "free return to T1")
Check(not Business.SelectSpecies(farm, "cow") and farm.selectedSpeciesId == "chicken", "locked selection rejected")
farm.weaponLevels["1"] = 3
Check(Business.TryPurchase(farm, "buyZap") and farm.cash == 0 and farm.equippedWeaponTier == 2, "buy next weapon without requiring Lv5")
Check(farm.weaponLevels["1"] == 3 and farm.weaponLevels["2"] == 1, "weapon levels remain independent")
Check(Business.TryEquipWeapon(farm, 1) and Config.GetDamage(1, farm.weaponLevels["1"]) == 4, "equip old enhanced weapon")
Check(not Business.TryEquipWeapon(farm, 5), "unowned equip rejected")
Check(not Business.TryPurchase(farm, "enhanceWeapon") and farm.cash == 0 and farm.weaponLevels["1"] == 3, "enhancement failure has no mutation")
farm = Save.CreateDefault()
farm.cash = 30
Check(Business.TryPurchase(farm, "enhanceWeapon") and farm.cash == 0 and Config.GetDamage(1, farm.weaponLevels["1"]) == 3, "first 30 coins enhance 2 to 3 damage")
farm.cash = 10000000
for _ = 1, 4 do Check(Business.TryPurchase(farm, "buyZap"), "five weapons sequentially purchasable") end
for _ = 1, 4 do Check(Business.TryPurchase(farm, "enhanceWeapon"), "four enhancements per weapon") end
local cash = farm.cash
Check(not Business.TryPurchase(farm, "enhanceWeapon") and not Business.TryPurchase(farm, "buyZap") and farm.cash == cash, "max equipment does not charge")
for _, action in { "buyCollect", "buyBasket", "buyRestaurant" } do
	for _ = 1, 4 do Check(Business.TryPurchase(farm, action), "independent five tier purchase") end
	Check(not Business.TryPurchase(farm, action), "max progress rejected")
end
Check(farm.collectTier == 5 and farm.basketTier == 5 and farm.restaurantLevel == 5 and Save.Validate(farm), "all progress remains serializable")
local function Target(id: string, x: number, z: number, health: number, y: number?): Combat.Candidate
	return { id = id, x = x, y = y or 0, z = z, health = health }
end
local hits = Combat.ResolveShot(2, 3, 0, 0, 0, 0, 1, { Target("a", 0, 4, 6), Target("b", 0, 8, 6) })
Check(#hits == 2 and hits[1].damage == 6 and hits[2].damage == 6, "T2 Lv3 assigns 6+6")
hits = Combat.ResolveShot(2, 3, 0, 0, 0, 0, 1, { Target("a", 0, 4, 20), Target("b", 0, 8, 6) })
Check(#hits == 1 and hits[1].damage == 12, "living first target consumes damage before transfer")
hits = Combat.ResolveShot(2, 5, 0, 0, 0, 0, 1, { Target("a", 0, 4, 2), Target("b", 8, 4, 2), Target("c", 8, 12, 2), Target("d", 0, 12, 2), Target("e", 8, 14, 2) })
Check(#hits == 4 and hits[1].id == "a" and hits[2].id == "b" and hits[3].id == "c" and hits[4].id == "e", "chain chooses nearest each hop with at most three secondary targets")
hits = Combat.ResolveShot(1, 5, 0, 0, 0, 0, 1, { Target("a", 0, 4, 2), Target("b", 0, 5, 2) })
Check(#hits == 1 and hits[1].damage == 2, "single weapon discards remainder")
hits = Combat.ResolveShot(3, 1, 0, 0, 0, 0, 1, { Target("a", 0, 4, 6), Target("b", 0, 5, 6), Target("c", 0, 6, 6), Target("behind", 0, -4, 1), Target("outside", 10, 1, 1) })
Check(#hits == 3 and hits[1].damage == 6 and hits[2].damage == 6 and hits[3].damage == 6, "cone shares budget and excludes outside sector")
hits = Combat.ResolveShot(3, 1, 0, 0, 0, 0, 1, { Target("a", 0, 4, 100), Target("b", 0, 5, 100), Target("c", 0, 6, 100) })
Check(#hits == 3 and hits[1].damage == 6 and hits[2].damage == 6 and hits[3].damage == 6, "cone splits a full-health group instead of dumping the shot into the first target")
hits = Combat.ResolveShot(3, 1, 0, 0, 0, 0, 1, { Target("low", 0, 4, 2), Target("mid", 0, 5, 100), Target("far", 0, 6, 100) })
Check(hits[1].damage == 2 and hits[2].damage == 6 and hits[3].damage == 6, "cone does not move an unused share onto later targets")
local fatTargets: { Combat.Candidate } = {}
for i = 1, 5 do table.insert(fatTargets, Target("fat" .. tostring(i), 0, i + 1, 100)) end
hits = Combat.ResolveShot(3, 1, 0, 0, 0, 0, 1, fatTargets)
Check(#hits == 5 and hits[1].damage == 4 and hits[2].damage == 4 and hits[3].damage == 4 and hits[4].damage == 3 and hits[5].damage == 3, "cone gives leftover damage points to the nearest targets")
local crowd: { Combat.Candidate } = {}
for i = 1, 10 do table.insert(crowd, Target(tostring(i), 0, i + 1, 1)) end
hits = Combat.ResolveShot(3, 1, 0, 0, 0, 0, 1, crowd)
Check(#hits == 5, "cone target count cap")
local trusted = Combat.ApplyOrderedHits(3, 1, { { id = "far", health = 100 }, { id = "near", health = 100 } })
Check(#trusted == 2 and trusted[1].damage == 9 and trusted[2].damage == 9, "ordered cone split ignores positions")
local chained = Combat.ApplyOrderedHits(2, 3, { { id = "a", health = 20 }, { id = "b", health = 6 } })
Check(#chained == 1 and chained[1].damage == 12, "ordered chain stops when the first target consumes the shot")
local single = Combat.ApplyOrderedHits(1, 5, { { id = "a", health = 2 }, { id = "b", health = 2 } })
Check(#single == 1 and single[1].id == "a" and single[1].damage == 2, "ordered single weapon ignores extra targets")
hits = Combat.ResolveShot(1, 1, 0, 0, 0, 0, 1, { Target("above", 0, 1, 2, 100) })
Check(#hits == 0, "vertical distance counts toward range")
Check(Request.Parse({ action = "zap", aim = { x = 0/0, y = 0, z = 1 } }) == nil, "NaN aim rejected")
Check(Request.Parse({ action = "zap", aim = { x = 0, y = 0, z = 0 } }) == nil, "zero aim rejected")
Check(Request.Parse({ action = "zap", aim = { x = 0, y = 0, z = 1 } }) ~= nil, "finite normalized aim accepted")
local acceptedTargets = Request.Parse({ action = "zap", aim = { x = 0, y = 0, z = 1 }, targetIds = { "a", "b" } })
Check(acceptedTargets ~= nil and acceptedTargets.targetIds ~= nil and acceptedTargets.targetIds[1] == "a" and acceptedTargets.targetIds[2] == "b", "zap target ids accepted in order")
local tooManyTargets = {}
for i = 1, 10 do table.insert(tooManyTargets, "id" .. tostring(i)) end
Check(Request.Parse({ action = "zap", aim = { x = 0, y = 0, z = 1 }, targetIds = tooManyTargets }) == nil, "zap rejects more than nine targets")
Check(Request.Parse({ action = "zap", aim = { x = 0, y = 0, z = 1 }, targetIds = { "" } }) == nil, "zap rejects an empty target id")
Check(Request.Parse({ action = "zap", aim = { x = 0, y = 0, z = 1 }, targetIds = "nope" }) == nil, "zap rejects a non-list target payload")
local replayFarm = Save.CreateDefault()
replayFarm.cash = 1000
local step = Business.GetPurchaseStep(replayFarm, "buyZap")
assert(Business.TryPurchase(replayFarm, "buyZap", step))
Check(not Business.TryPurchase(replayFarm, "buyZap", step) and replayFarm.cash == 800 and replayFarm.equippedWeaponTier == 2, "replayed purchase cannot buy or charge the next tier")
local enhancementStep = Business.GetPurchaseStep(replayFarm, "enhanceWeapon")
Business.TryEquipWeapon(replayFarm, 1)
Check(not Business.TryPurchase(replayFarm, "enhanceWeapon", enhancementStep) and replayFarm.weaponLevels["1"] == 1 and replayFarm.weaponLevels["2"] == 1, "stale enhancement cannot charge a different weapon")
print("FarmProgressRegression passed:", checks, "checks; species, independent upgrades and real combat rules")
