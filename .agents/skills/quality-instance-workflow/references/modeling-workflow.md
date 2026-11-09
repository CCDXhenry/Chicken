# 优质 3D 建模与场景资产流程 (3D Modeling & Building Workflow)

本流程整合 Roqer 的 Blender Headless 生产闭环与 Roblox 场景装配规范，用于生产结构规范、细节丰富且完全契合 Roblox 物理引擎的高品质 3D 模型资产。

---

## 一、资产构建路径分级决策

在接到优质模型创建任务时，遵循如下优先级策略：

1. **复杂曲面、有机造型、细节道具、载具**：首选 **Blender 无头 Python 脚本生成**（结合 Open Cloud 自动上传为 MeshPart / Model）；
2. **纯几何体、地面块、建筑骨架、碰撞箱、触发体**：采用 **原生 Part + 规范 CSG** 组合构建；
3. **环境公共资产（如树木、岩石）**：若无原创要求，检索 Creator Store（Toolbox），但必须经过安全检查（去脚本、核对所有权）方可引入。

---

## 二、Blender 自动化建模管线（推荐路线）

### 1. 脚本编写准则 (`bpy`)
- **使用 Roqer 辅助规范**：
  - 避免手算复杂的四元数旋转矩阵，使用两点定长定位（Start-End CFrame）；
  - 默认采用 Flat-shaded（平滑低面数风格），指定明确的顶点颜色（Vertex Colors）或统一材质库；
  - 单次脚本执行保护时间为 200 秒，代码尽量控制在 60,000 字符以内。
- **分阶段增量构建（Staged Iteration）**：
  - 先构建主骨架/轮廓（Frame / Hull）并保存 Scene；
  - 检查通过后，再在保存的 Scene 基础上追加次级结构（Body / Accessories）；
  - 最后进行细节与倒角（Details / Chamfers）修饰。

### 2. 自动化拓扑与几何自检（严格质量门禁）
导出 `.glb` / `.fbx` 后，必须在无头环境中重新导入该模型，执行独立测量与断言：
- **三角面数预算**：
  - 小型道具（武器、金币、药水瓶）：100 ～ 1,000 三角面；
  - 中型场景道具（箱子、路灯、载具）：1,000 ～ 3,000 三角面；
  - 大型建筑外壳：控制在场景总预算内，避免无效细分。
- **孤立散件检测**：断言是否存在与其他几何体无任何相交或连接的游离碎面。
- **穿模异常检测**：排查独立部件间未预期的交叉穿插（Penetration）。
- **镜像对称检测**：成对部件（如 `Wheel_L` 与 `Wheel_R`）必须检查左右对称轴。
- **坐标合法性**：全面过滤含 `NaN` 或无限大顶点坐标的坏网格。

### 3. 多重视角与渲染审核
- 自动渲染 4 视角合成渲染图（顶视 Top、侧视 Side、以及两个对角透视视角）；
- 在视口或 3D 预览中核验：
  - 物体正向是否沿 Roblox 的 $-Z$ 轴（前向）；
  - 物体底面是否对齐 $Y=0$ 地面基准面。

---

## 三、Open Cloud 上云与 Studio 装配规范

### 1. 资产上传与 Moderate 审核
- 使用 Roblox Open Cloud Assets API（Write 权限），将导出的 3D 文件发布至用户账号/群组；
- 获取云端资产后，将其作为 Model 载入 Studio；
- 若出现 Moderation 延迟，保留 `operation_id` 轮询其完成状态，不重复上传。

### 2. 角色尺寸比例参照体系 (Player Scale)
- **Roblox 标准角色身高**：~5 studs；
- **标准门洞**：宽 4 studs × 高 7 studs；
- **天花板净高**：10 ～ 14 studs；
- **吧台/工作台高度**：3.5 ～ 4 studs；
- **手持道具/投掷物**：通常为 1.5 ～ 2.5 studs。

### 3. 物理属性与焊接契约 (Physics Contract)
- **RootPart 设置**：
  - 将模型的 `PrimaryPart` 设置为根部件 `RootPart`（通常为尺寸 `0.2, 0.2, 0.2` 的透明辅助 Part）；
  - `RootPart` 放置于模型视觉包围盒的底部中心。
- **挂接物（手持、背负、拾取道具）**：
  - 所有子部件必须强制设置为：`CanCollide = false`、`Massless = true`、`CanTouch = false`、`CanQuery = false`；
  - 使用 `WeldConstraint` 将各子部件焊接到 `RootPart` 上；
  - 严禁使挂接物因某一个未解冻部件（`Anchored=true`）导致玩家角色被原地定住。
- **场景静态道具**：
  - 明确标注 `Anchored = true`，合理设置 `CollisionFidelity`（复杂道具设为 `Box` 或 `Hull` 降低物理计算负担）。

---

## 四、交付验证证据

1. **结构读取（Readback）**：使用 inspect 工具读取 Studio 内载入实例的层级树、`Size` 与 `PrimaryPart`；
2. **视口渲染截图**：对准物体特写捕获 Studio 渲染截图，确认材质反射与光影正常；
3. **物理实测**：若为动态/交互道具，在 Play 模式下测试角色拾取、手持与移动，确保角色无浮空、无滑步、相机无剧烈晃动。
