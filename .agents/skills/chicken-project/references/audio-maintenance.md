# Chicken 音效维护与校准

本文件维护项目参数；通用方法按音频 skill 执行。先检查实际源码、工具参数和清单，后续玩法调整不受本次参数永久限制。

## 当前战斗与收集约定

- 攻击冷却来自 `FarmEconomyConfig.ZapCooldownSeconds`（本次校准时为 0.35 秒），电弧表现约 0.12 秒。保留客户端即时预测；不能为修音效擅自改成全部等待服务端。
- 开火通过既有工具栏装备、冷却、存活与输入条件后播放，合法空枪保留声音。命中音在预测特效中选择受击或变熟，文字反馈不补播变熟音。
- 熟食落地音由服务端实际生成地面熟食触发；不新增落地动画或预测阶段的落地音。
- 拾取收到成功事件后随落袋播放，缺少模型／锚点时成功反馈兜底一次；预留模型、发送请求、空收集、满筐均不播放成功音。
- 密集落袋合并窗口为 0.08 秒，由客户端 VFX 生命周期维护，只合并声音，保留全部物品动画及数量、重量通知。
- 收集容量警告依赖 `kind == "capacity"`；其他业务现存的金币不足反馈不在本轮改造范围。

| 音效 | 有效时长（秒） |
| --- | --- |
| Zap_T1 / T2 / T3 / T4 / T5 | 0.16 / 0.19 / 0.22 / 0.26 / 0.30 |
| AnimalHit / FoodDrop | 0.15 |
| AnimalCooked / Warning | 0.30 |
| Pickup | 0.18 |

这些是本轮已采用的参数，不是孵化、升级、交货、UI 或 BGM 的修改授权。

## 原素材、清单与工具

- 成品在 `Assets/Sounds/<Name>.mp3`，原输入在 `Assets/Sounds/Originals/`，不得用成品覆盖原输入。
- `combat_processing.json` 记录源哈希、裁切区间、包络、安全增益、有效／编码时长与成品哈希；`audio_manifest.json` 维护当前云端映射、哈希与 history，旧 ID 可用于回退。
- 当前 Place 为 `134743372234687`，Universe 为 `10775499195`，Group 为 `33977495`；这些是核对线索，执行前仍须读取当前连接归属。
- 上传读取既有 `SIXCUBE_ROBLOX_OPENCLOUD_KEY` 或 `ROBLOX_API_KEY`，不显示密钥。

示例仅处理两项；按用户实际授权替换名称：

```powershell
python Tools/Audio/trim_combat_sounds.py --names Zap_T1 Pickup
python Tools/Audio/upload_roblox_audio.py --names Zap_T1 Pickup
python Tools/Audio/setup_sounds_in_studio.py --names Zap_T1 Pickup --emit-code
```

`--emit-code` 只生成部署代码，通过当前 Studio MCP 在选定 Edit 会话执行；也可使用工具支持的 `--studio-id` 桥接路径。不要默认选择列表第一项。脚本只改本地，MCP 仅部署实例属性。

## 回归与验收

```powershell
pwsh -File Tools/check-strict.ps1 Scripts/ReplicatedStorage/Scripts/Client/ClientRoastChickenFarmManager.luau Scripts/ReplicatedStorage/Scripts/Client/FarmVisualEffects.luau
lune run Tools/Tests/CombatSoundTriggerRegression.luau
lune run Tools/Tests/AttackVfxRegression.luau
lune run Tools/Tests/FarmToolbarRegression.luau
lune run Tools/Tests/SoundPoolRegression.luau
python -m unittest discover -s Tools/Tests -p test_combat_audio_pipeline.py
```

按变更范围选择相关回归，报告实际结果；文档维护无需重复跑游戏回归。

Script Sync 在团队创建模式下可只同步编辑草稿；使用 `ScriptEditorService:GetEditorSource` 只读比较本地内容，不能把 `Source` 仍旧当成同步失败。未经授权不提交草稿、不发布游戏、不启动 Play；交付分别说明草稿同步、模板更新、云端审核和听感验证状态。纯 skill 修改无需包同步。
