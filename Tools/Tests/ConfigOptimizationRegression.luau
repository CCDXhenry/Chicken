-- 验证配置表结构优化、表id全部为int、多语言 _t 列、GameConfig 集中化与初始值调试支持
--!strict

local function Check(condition: boolean, message: string): ()
	if not condition then
		error("Check failed: " .. message)
	end
end

print("--> [1/4] 验证 FarmEconomyConfig 消费配表新字段与整数主键...")
local Economy = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmEconomyConfig")

-- 验证物种
Check(#Economy.Species == 5, "五阶物种均存在")
for idx, sp in Economy.Species do
	Check(type(sp.id) == "number" and sp.id == idx, "物种表 id 必须为 int 且等于下标: " .. tostring(sp.id))
	Check(type(sp.key) == "string" and #sp.key > 0, "物种拥有字符串 key: " .. sp.key)
	Check(type(sp.tier) == "number" and sp.tier >= 1 and sp.tier <= 5, "物种阶位有效")
	Check(type(sp.name_t) == "string" and #sp.name_t > 0, "物种拥有 name_t 翻译列: " .. sp.key)
	Check(type(sp.foodName_t) == "string" and #sp.foodName_t > 0, "物种拥有 foodName_t 翻译列: " .. sp.key)
	Check(type(sp.name) == "string" and sp.name == sp.name_t, "向下兼容 species.name 正常映射")
	Check(type(sp.foodName) == "string" and sp.foodName == sp.foodName_t, "向下兼容 species.foodName 正常映射")
	Check(sp.description_t ~= nil and #sp.description_t > 0, "物种拥有 description_t: " .. sp.key)
end

-- 验证通过 int id 与 string key 均可查找物种
local spById = Economy.GetSpecies(1)
local spByKey = Economy.GetSpecies("chicken")
Check(spById ~= nil and spByKey ~= nil and spById == spByKey, "GetSpecies 支持 int id (1) 与 string key ('chicken') 查找")

-- 验证品质
Check(#Economy.Qualities == 4, "四阶品质均存在")
for idx, q in Economy.Qualities do
	Check(type(q.id) == "number" and q.id == idx, "品质表 id 必须为 int 且等于下标: " .. tostring(q.id))
	Check(type(q.key) == "string", "品质拥有字符串 key: " .. q.key)
	Check(q.tier ~= nil and q.tier >= 1 and q.tier <= 4, "品质包含 tier")
	Check(q.name_t ~= nil and #q.name_t > 0, "品质包含 name_t")
	Check(q.colorHex ~= nil and #q.colorHex == 6, "品质包含 6 位十六进制 colorHex")
end

local qById = Economy.GetQuality(2)
local qByKey = Economy.GetQuality("golden")
Check(qById ~= nil and qByKey ~= nil and qById == qByKey, "GetQuality 支持 int id (2) 与 string key ('golden') 查找")

-- 验证武器
Check(#Economy.Weapons == 5, "五阶武器均存在")
for idx, wp in Economy.Weapons do
	Check(type(wp.id) == "number" and wp.id == idx, "武器表 id 必须为 int: " .. tostring(wp.id))
	Check(wp.tier ~= nil and wp.tier == idx, "武器包含 tier")
	Check(wp.name_t ~= nil and #wp.name_t > 0, "武器包含 name_t 翻译列")
	Check(wp.description_t ~= nil and #wp.description_t > 0, "武器包含 description_t")
end

-- 验证拾取工具
Check(#Economy.Collectors == 5, "五阶拾取工具均存在")
for idx, cl in Economy.Collectors do
	Check(type(cl.id) == "number" and cl.id == idx, "工具表 id 必须为 int: " .. tostring(cl.id))
	Check(cl.tier ~= nil and cl.tier == idx, "工具包含 tier")
	Check(cl.name_t ~= nil and #cl.name_t > 0, "工具包含 name_t 翻译列")
	Check(cl.description_t ~= nil and #cl.description_t > 0, "工具包含 description_t")
end

-- 验证鸡筐
Check(#Economy.Baskets == 5, "五阶鸡筐均存在")
for idx, bk in Economy.Baskets do
	Check(type(bk.id) == "number" and bk.id == idx, "鸡筐表 id 必须为 int: " .. tostring(bk.id))
	Check(bk.tier ~= nil and bk.tier == idx, "鸡筐包含 tier")
	Check(bk.name_t ~= nil and #bk.name_t > 0, "鸡筐包含 name_t 翻译列")
	Check(bk.description_t ~= nil and #bk.description_t > 0, "鸡筐包含 description_t")
end

-- 验证餐厅
Check(#Economy.Restaurants == 5, "五阶餐厅均存在")
for idx, rt in Economy.Restaurants do
	Check(type(rt.id) == "number" and rt.id == idx, "餐厅表 id 必须为 int: " .. tostring(rt.id))
	Check(rt.level ~= nil and rt.level == idx, "餐厅包含 level")
	Check(rt.name_t ~= nil and #rt.name_t > 0, "餐厅包含 name_t 翻译列")
	Check(rt.description_t ~= nil and #rt.description_t > 0, "餐厅包含 description_t")
end

print("--> [2/4] 验证 GameConfig 全局配置与非配表沉淀...")
local GameConfig = require("../../Scripts/ReplicatedStorage/Scripts/Shared/GameConfig")

-- 验证外观覆色沉淀
Check(type(GameConfig.SpeciesAppearance) == "table", "GameConfig 包含 SpeciesAppearance")
Check(GameConfig.SpeciesAppearance.chicken ~= nil and GameConfig.SpeciesAppearance.chicken.Body == "FFE78A", "小黄鸡外观色值正确")
Check(GameConfig.SpeciesAppearance.dragon ~= nil and GameConfig.SpeciesAppearance.dragon.Head == "CF4A2F", "火龙外观色值正确")

-- 验证玩法规则
Check(GameConfig.FarmRules.PopulationCapacity == 28, "牧场蛋和活体上限为 28")
Check(GameConfig.FarmRules.GroundRoastLifetimeSeconds == 75, "熟食生命周期为 75 秒")
Check(GameConfig.VillageRules.Capacity == 8, "村落地块容量为 8")

-- 验证配表子模块与字典索引 (支持 int id 与 string key 双重索引)
Check(GameConfig.SpeciesMap[1] ~= nil and GameConfig.SpeciesMap["chicken"] ~= nil, "SpeciesMap 正确包含 int (1) 与 key ('chicken')")
Check(GameConfig.SpeciesTierMap[5] ~= nil and GameConfig.SpeciesTierMap[5].key == "dragon", "SpeciesTierMap[5] 映射为 dragon")
Check(GameConfig.QualityMap[2] ~= nil and GameConfig.QualityMap["golden"] ~= nil, "QualityMap 正确包含 int (2) 与 key ('golden')")

print("--> [3/4] 验证初始值配置与调试功能...")
Check(type(GameConfig.InitialValues) == "table", "GameConfig 包含 InitialValues")
Check(type(GameConfig.Debug) == "table", "GameConfig 包含 Debug 配置")

-- 验证默认生成存档
local defaultSave = GameConfig.CreateDefaultPlayerSaveInfo()
Check(defaultSave.farm.cash == 0, "默认初始金币为 0")
Check(defaultSave.farm.unlockedSpecies.chicken == true, "默认解锁 chicken")
Check(defaultSave.farm.equippedWeaponTier == 1, "默认装备 T1 武器")

-- 模拟策划调试修改初始值
GameConfig.InitialValues.Cash = 88888
GameConfig.InitialValues.EquippedWeaponTier = 3
GameConfig.InitialValues.UnlockedSpecies.rabbit = true
local debugSave = GameConfig.CreateDefaultPlayerSaveInfo()
Check(debugSave.farm.cash == 88888, "修改 InitialValues.Cash 后新存档金币生效为 88888")
Check(debugSave.farm.equippedWeaponTier == 3, "修改 InitialValues.EquippedWeaponTier 生效")
Check(debugSave.farm.unlockedSpecies.rabbit == true, "修改 InitialValues.UnlockedSpecies 生效")

-- 恢复默认值以防后续测试污染
GameConfig.InitialValues.Cash = 0
GameConfig.InitialValues.EquippedWeaponTier = 1
GameConfig.InitialValues.UnlockedSpecies.rabbit = nil

print("--> [4/4] 验证 FarmSaveData 独立调用与契约验证...")
local FarmSaveData = require("../../Scripts/ReplicatedStorage/Scripts/Shared/FarmSaveData")
local customDefault = FarmSaveData.CreateDefault({ Cash = 666 })
Check(customDefault.cash == 666, "FarmSaveData.CreateDefault 传参生效")
local ok, err = FarmSaveData.Validate(customDefault)
Check(ok, "自定义初始值存档通过 Schema 验证: " .. tostring(err))

print("=== ALL 4 CHECKS PASSED: ConfigOptimizationRegression passed successfully with INT IDs! ===")
