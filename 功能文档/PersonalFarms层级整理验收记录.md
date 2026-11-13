# PersonalFarms 层级整理验收记录

日期：2026-11-13。Place：开发者鸡（134743372234687）。本轮原位整理模板及八户静态农场，未提交、推送、发布 Place 或 Package。

## 实施结果

- `PersonalFarmTemplate` 与 Plot01–Plot08 均保留根 Folder、地块编号及归属属性，按 Environment、Production、Restaurant、ToolShop、Anchors 分区。
- 地面、道路、围栏、绿化与风车归入 Environment；孵化地面及鸡窝归入 Production；餐厅按 Structure、Kitchen、Packing、Service、Queue、Decorations、Anchors 归组。出生点及门牌归入根 Anchors，商店入口归入 ToolShop.Anchors。
- 鸡窝与餐厅各自保留 UpgradeZone 叶节点，通过不同完整路径区分；业务节点名称保留，重复装饰按模板局部 X、Z、Y、尺寸与朝向稳定编号，九套采用同一匹配映射。
- 新增共享 FarmScenePaths，提供 Find、Require、Part、EnsureRuntime。客户端允许逐级查询返回 nil，保留已有后代监听和流送恢复机制；业务不再依赖旧根级节点或递归同名搜索。
- 蛋、动物、熟食在 Runtime 下分容器；员工、顾客及包装展示在 Runtime.Restaurant 下。角色携带物继续跟随角色，释放地块时删除整个 Runtime。
- OrganizePersonalFarms 在全部九套预检成功后原位移动和命名，执行失败回滚；已整理场景重复执行为零改动。独立备份见下文。村落构筑器从已整理模板克隆，餐厅构筑器直接维护新分组。
- Edit 工具只读加载 Script Sync 草稿中的无副作用路径契约；不覆写 Studio Source、不提交草稿。业务模块仍按项目原有入口加载。

## 保留与静态验证

迁移前后核对 4,653 个原有实例；几何、尺寸、颜色、材质、透明度、碰撞与查询、主要对象引用、已有 Attributes 和 Tags 保持不变。新增 189 个分组 Folder，每户新增 21 个；每户仍为 460 个 BasePart、55 个碰撞部件。场景外观与位置保持，未合并或删除装饰。

八户共 3,680 个 BasePart、440 个碰撞部件。公共 FarmVillage 仍为 33 个部件、22 个碰撞部件；FarmPlots 和公共场景的结构与位置未修改。

- 农场 Edit 审计通过：八户位置和朝向正确、无重叠、入口通畅、空户无 Runtime、StreamingEnabled 保留。
- 餐厅 Edit 审计通过：九套原交货区几何、文字及样式、成品台相对方位、包装展示位置和搬运路线均通过。
- 迁移工具重复执行返回 `changes=0`。
- 17 个本轮生产、Studio 工具及 Studio 回归文件通过严格类型分析，0 Error。
- 8 个新增/修改生产模块通过 ScriptEditorService:GetEditorSource 核对：标准化换行后的字节数及两个独立滚动指纹完全一致。未将草稿 Source 字段为空误判为同步缺失。

## 离线回归

| 检查 | 结果 |
|---|---:|
| FarmHierarchyRegression：真实备份迁移、失败预检不修改、几何保留、九套命名一致、资产包一致及两个构筑器 | 4,437 项通过 |
| FarmVillageRegression：认领、满位、归属、整体 Runtime 清理及复用 | 40 项通过 |
| FarmRestaurantRegression：正式调度器、搬运、竞争、购买时机及姿态 | 222 项通过 |
| CameraSpawnRegression | 59 项通过 |
| FarmSignAudienceRegression | 20 项通过 |
| SpeciesSwitchRegression | 18 项通过 |
| AttackVfxRegression | 1,100 项通过 |
| CombatSoundTriggerRegression | 26 项通过 |
| FarmZapRegression | 22 项协议/预测/空间检查及服务端命中、飘字代次、拒绝回执检查通过 |

另执行 FarmToolbarRegression，业务装备检查后在已有 UI 包断言 `preview hierarchy persisted` 失败。本轮没有修改 FarmUITemplates.rbxm；该项保留为独立 UI 资产问题，不能声称全部仓库测试通过。

## 重新双人实测

最初会话因测试账号存档版本不受支持而退出；重新启动后 Player1、Player2 正常加载并认领 Plot01、Plot02。本轮未改存档迁移逻辑，也未用测试档替换真实 profile.farm。

正式状态核验使用 eval_server_runtime / eval_client_runtime，直接共享游戏 VM 的 require 缓存。插件上下文 execute_luau 只用于 Edit 与实例只读查询，不据其独立 require 缓存判断正式管理器状态。

- PersonalFarmRegression 的 10 组检查通过：独立生产与 28 上限、两种旋转的游荡范围、跨户电击与拾取拒绝、两户分别完成电击→拾取→交货→打包→取货→前台售卖、物种确认、孵化、连锁、冻结及释放清理。
- 该夹具使用独立经营档和远端临时地图；期间暂移出正式会话的投影循环，避免工具互抢，结束恢复会话及角色。更新夹具以显式装备工具、提交当前协议要求的目标 ID，并在满产测试后腾出名额验证确认期间下蛋。
- FarmVillageRuntimeRegression 的 13 项检查通过：正式八户、唯一归属、对向地块、邻居拒绝、外人蛋 ID 拒绝、释放保留建筑、空置标牌、邻居保留、原位重认领及重复加载。
- 真实重生成功：Player1 回到自家 Plot01，角色根到出生点上方 3 studs 目标的距离约 0.55 studs。
- 两端客户端入口移除/返回及门牌恢复夹具均通过；移除商店入口后入口数由 4 降为 3，归位恢复 4，门牌销毁并只恢复一份。测试结束重新派发入口到达，恢复正式管理器的 Prompt 连接。
- 实际玩家断开后，Player4 认领释放的 Plot02，静态农场总数仍为 8。随后断开 Player4，确认建筑引用仍在、OwnerUserId 清空、Runtime 删除。
- 新结构下两户员工、顾客及包装投影均位于 Runtime.Restaurant。所查正式服务端及客户端日志未见新增玩法异常，仍有既有插件图标资源类型错误。
- Play 已停止，回到 Edit。客户端后代移除/返回不等同于强制引擎 stream-out；本轮没有进行八人满场性能或真机触屏验收。

## 资产与恢复

- `Assets/Studio/PersonalFarms.before-hierarchy.rbxm`：迁移前单户模板及八户 PersonalFarms 的完整备份，分别恢复到 ServerStorage.Models 与 Workspace。
- `Assets/Studio/FarmVillage.rbxm`：更新后的 PersonalFarms、原 FarmPlots、原 FarmVillage。
- `Assets/Studio/PersonalFarmTemplates.rbxm`：仅替换农场模板，保留包内其余七个根资产；包括当前 Studio 中不存在但包内已有的 FarmBasketTemplate。
- `Assets/Studio/Verification/FarmHierarchy/PersonalFarmTemplate.rbxm`：本次模板单独导出。
- `Assets/Studio/Verification/FarmHierarchy/results.json`：本次机器可读验证摘要。

恢复旧备份时应同时恢复匹配旧路径的业务源码；新源码要求新层级。无需发布或升级 Core 共享包，本次未执行 Package 发布。场景人数上限仍为原值 60，本轮未调整发布配置。
