---
name: quality-instance-workflow
description: >-
  当用户明确提出需要创建优质实例、高品质资产（包括高品质 3D 模型与道具、专业级 UI 界面、精细特效 VFX 与动画）或要求按照工业级标准打造高质量 Roblox 游戏表现时使用本 Skill。
  整合 Roqer 的高品质 3D 建模自检闭环（Blender Headless + 4 视角自检 + Open Cloud 上云）、
  专业 UI 设计规范（SIM/STUDS 主题 + 14 类语义布局模板 + 参考图还原 + 安全区自适应）、
  以及专业特效流程（Mesh VFX + 本地纹理极速预览 + 多层发射 + 对象池预热）。
---

# 优质实例创建流程 (Quality Instance Workflow)

本 Skill 是面向 Roblox 游戏开发的高品质资产与实例创建标准流程。
当且仅当**用户明确提出需要创建优质实例、高质量资产或精细化表现**时触发本流程。

---

## 一、核心原则与工程红线

1. **拒绝粗糙占位**：严禁直接用单 Part 灰模、未调参的默认粒子或简陋无布局的 UI 作为最终交付。
2. **实例唯一来源原则**：
   - 持久化 UI 模板和 3D 模型必须在 **Studio Edit 模式** 下创建并归档至规范目录（如 `ReplicatedStorage.UI`、`ReplicatedStorage.Models`）。
   - 运行时代码仅负责克隆模板、数据绑定、生命周期驱动与状态同步，禁止在运行期通过代码裸写 `Instance.new` 拼装复杂界面或模型。
3. **尊重现有同步链路**：沿用已建立的本地文件与 Script Sync 同步，不在 MCP 中随意覆写业务脚本源码，不在 Edit 模式下非法 `require` 业务代码。
4. **闭环交付与实机验收**：所有优质实例创建完成后，必须通过只读属性核验、视口截图或 Play 模式对象池采样验收。

---

## 二、任务路由与流程索引

根据用户提出的优质实例具体类别，**按需加载** 对应的详细流程规范：

```mermaid
flowchart TD
    Request["用户提出优质实例创建需求"] --> Route{"判断实例类别"}
    Route -- "3D 道具 / 场景部件 / 载具 / 建筑" --> Modeling["[3D 建模与场景资产流程](references/modeling-workflow.md)"]
    Route -- "HUD / 弹窗 / 商城 / 背包 / 界面" --> UI["[优质 UI 界面设计流程](references/ui-design-workflow.md)"]
    Route -- "爆炸 / 刀光 / 命中 / 施法 / 光效" --> VFX["[高品质特效与动画流程](references/vfx-animation-workflow.md)"]
```

- **3D 道具、模型、场景组件与刚性预制体**：
  👉 读取并严格执行 [3D 建模与场景资产流程](references/modeling-workflow.md)。
- **界面、HUD、弹窗、面板、图标与自适应 UI**：
  👉 读取并严格执行 [优质 UI 界面设计流程](references/ui-design-workflow.md)。
- **粒子特效、Mesh VFX、Flipbook 序列帧、受击震颤与对象池**：
  👉 读取并严格执行 [高品质特效与动画流程](references/vfx-animation-workflow.md)。

---

## 三、标准交付检查清单 (Delivery Checklist)

每个优质实例交付前必须逐一核对以下检查点：

- [ ] **视觉与比例达标**：符合真实角色比例（Player ~5 studs），材质与配色和谐，无拉伸畸变；
- [ ] **物理与装配规范**：挂接物 `CanCollide=false`、`Massless=true`；根节点为 `PrimaryPart`，Weld 约束完整；
- [ ] **UI 适配完整**：包含 `UIScale`，支持 1920×1080 基准，严格避让 `DeviceSafeInsets`；
- [ ] **特效零泄漏与对象池**：频繁特效已接入 Warmup 预热池，无运行期持续累积的内存或实例泄漏；
- [ ] **资产合法性确认**：外部贴图与网格已通过 Open Cloud 正式上云获取 `rbxassetid://`，无临时死链。
