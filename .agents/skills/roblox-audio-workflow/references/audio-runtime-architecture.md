# 音频运行时架构、对象池与业务接入规范 (Audio Runtime Architecture)

本参考文档规定在 Roblox 项目中进行音频运行时管理、架构分层防污染、双重对象池回收机制及双端业务调用的工程实现标准。

---

## 1. 架构分层红线 (Architecture Boundary)

> [!CAUTION]
> **绝对红线：严禁修改 `Core/` 框架代码！**
> `Scripts/ReplicatedStorage/Core/` 通常为团队共享的基础设施或第三方底层库。直接修改 Core 会导致分支合并冲突、框架升级失败以及跨项目污染。

### 规范分层方案
- **底层基础设施 (`Core/`)**：只读，提供基础能力，不包含具体项目的资产引用。
- **项目专属工具 (`Scripts/ReplicatedStorage/Scripts/Shared/FarmSoundTool.luau`)**：
  - 承载项目业务声音逻辑；
  - 直接读取 `ReplicatedStorage.Sounds` 模板；
  - 提供业务友好的高层封装接口。
- **业务调用层 (`Scripts/Client/` 与 `Scripts/ServerStorage/`)**：
  - 统一 `require` 项目专用声音工具，禁止跨层直取底层。

---

## 2. 脚本规范与 `--!strict` 契约

所有新增与维护的音频 Luau 脚本必须遵守：
1. **第 1 行必须为中文业务注释**：描述该模块的具体职责；
2. **第 2 行必须为 `--!strict` 严格模式声明**；
3. **杜绝类型推导隐患**：
   - 避免比较非空 Instance 与 `nil`（例如 `cloned == nil` 会引发 `TypeError: Types Sound and nil cannot be compared with ==`，需写为 `if not cloned then`）；
   - 从 `GetAttribute` 获取的值为 `unknown`，必须先用 `typeof(v) == "number"` 收窄或类型断言，禁止直接与数字相加减。

---

## 3. 双重对象池设计与实现 (Double Object Pooling)

游戏运行过程中，若频繁电击、开火或掉落物品，直接 `Instance.new("Sound")` 或无节制 `:Clone()` 会触发高频内存分配与 GC 尖刺。必须采用双重对象池：

### 3.1 载体 Attachment 缓存池
局部 3D 空间音效需要挂载在 `Attachment` 上。我们在 `workspace` 创建一个不可见、无碰撞的锚定零件 `FarmLocalSoundEffects`，其内部维护 Attachment 缓存池：
```luau
local localSoundAttachmentsPool: { Attachment } = {}
local localSoundsPart: Part? = nil

local function GetLocalSoundsPart(): Part
	if localSoundsPart and localSoundsPart.Parent then
		return localSoundsPart
	end
	local part = Instance.new("Part")
	part.Name = "FarmLocalSoundEffects"
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Anchored = true
	part.Position = Vector3.zero
	part.Parent = workspace
	localSoundsPart = part
	return part
end

local function GetLocalSoundAttachment(): Attachment
	local attachment = table.remove(localSoundAttachmentsPool)
	if attachment then
		attachment.Parent = GetLocalSoundsPart()
		return attachment
	end
	local newAttachment = Instance.new("Attachment")
	newAttachment.Name = "LocalSoundAttachment"
	newAttachment.Parent = GetLocalSoundsPart()
	return newAttachment
end

local function RestoreAttachment(attachment: Attachment)
	attachment.Parent = nil
	table.insert(localSoundAttachmentsPool, attachment)
end
```

### 3.2 Sound 实例克隆与自动归还池
按模板索引对象池字典：`soundsPools: { [Sound]: { Sound } }`。
- 获取时优先从池中出栈，池空时才 `:Clone()`；
- 每次取出恢复模板音量、播放速度、TimePosition，并在 Play 前设置本次的循环和声音组；倍率不得残留到下一次播放。
- 绑定 `Ended` 与 `Stopped` 事件：播放结束或主动停止时，自动清空 `Parent` 并归还对象池；
- 模板被销毁时：自动清理池中全部克隆实例，防止悬挂引用。

```luau
local soundsPools: { [Sound]: { Sound } } = {}

local function RestoreSound(sound: Sound, template: Sound)
	local parent = sound.Parent
	if parent and parent:IsA("Attachment") then
		RestoreAttachment(parent)
	end
	sound.Parent = nil
	local pool = soundsPools[template]
	if pool then
		table.insert(pool, sound)
	else
		sound:Destroy()
	end
end

local function GetSoundFromPool(soundTemplate: Sound): Sound?
	local pool = soundsPools[soundTemplate]
	if pool == nil then
		local newPool: { Sound } = {}
		soundsPools[soundTemplate] = newPool
		soundTemplate.Destroying:Connect(function()
			local activePool = soundsPools[soundTemplate]
			if activePool then
				for _, sound in activePool do
					sound:Destroy()
				end
			end
			soundsPools[soundTemplate] = nil
		end)
		pool = newPool
	end

	local recycled = table.remove(pool)
	if recycled then
		recycled.Volume = soundTemplate.Volume
		recycled.PlaybackSpeed = soundTemplate.PlaybackSpeed
		recycled.TimePosition = 0
		return recycled
	end

	local cloned: Sound? = soundTemplate:Clone()
	if not cloned then
		return nil
	end

	cloned.Ended:Connect(function()
		RestoreSound(cloned, soundTemplate)
	end)
	cloned.Stopped:Connect(function()
		RestoreSound(cloned, soundTemplate)
	end)

	return cloned
end
```

---

## 4. 统一调用接口与业务接入范例

### 4.1 统一播放方法设计
```luau
function FarmSoundTool.Play(soundName: string, soundPosition: Vector3?, volumeMultiplier: number?): Sound?
	local template = FarmSoundTool.GetSoundTemplate(soundName)
	if not template then
		return nil
	end

	local sound: Sound? = nil
	if soundPosition then
		sound = FarmSoundTool.PlayLocal(template, soundPosition, false)
	else
		sound = FarmSoundTool.PlayGlobal(template, false)
	end

	if sound then
		sound.Volume = template.Volume * (if volumeMultiplier ~= nil then volumeMultiplier else 1)
	end

	return sound
end
```

### 4.2 典型业务场景接入点

以下片段只演示播放接口，不是完整的业务触发实现：开火须先通过装备、冷却、存活和输入校验；成功音须依赖对应成功事件或状态变化。不要仅凭文案关键词、pending 标志或金币减少推断成功。预测、权威通知和动画各层之间为同一结果指定一个声音入口，具体核对项见 SKILL.md 的校准 reference。

声音先配置再 Play。需要音量倍率时应在底层开始播放之前应用；若现有接口先 Play 再设置音量，应记录该限制并在确有可听问题时做兼容修正，不借文档维护扩大代码修改。

#### 1. UI 弹窗生命周期与按钮点击
```luau
local FarmSoundTool = require(Shared.FarmSoundTool)

function WindowBase.OnInit(self: WindowBase): ()
	FarmSoundTool.Play("UIOpen")
end

function WindowBase.OnClose(self: WindowBase): ()
	FarmSoundTool.Play("UIClose")
end

local function OnButtonClick()
	FarmSoundTool.Play("UIClick")
end
```

#### 2. 玩家电击开火与装备阶位联动
```luau
local tier = ClientGameInfo.GetFarmInfo().zap or 1
-- 根据阶位动态组装 Zap_T1 ~ Zap_T5 音效名
FarmSoundTool.Play("Zap_T" .. tostring(math.clamp(tier, 1, 5)))
```

#### 3. 游戏内货币结算与升级成功
```luau
-- 获得金币
FarmSoundTool.Play("Coin")

-- 科技/武器/等级升级成功
FarmSoundTool.Play("Upgrade")
```

#### 4. 服务端 3D 空间事件触发
```luau
-- 动物下蛋在原点
FarmSoundTool.Play("EggSpawn", originPart.Position)

-- 蛋落地磕击
FarmSoundTool.Play("EggLand", egg.landingPosition)

-- 雏鸟破壳
FarmSoundTool.Play("EggHatch", egg.nestPosition)

-- 窗口送餐与打包完成
FarmSoundTool.Play("Delivery", windowPart.Position)
FarmSoundTool.Play("PackageDone", stationPart.Position)
```
