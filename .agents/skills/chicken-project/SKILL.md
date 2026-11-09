---
name: chicken-project
description: Chicken Roblox 项目开发规范。处理本仓库代码、配置、UI、模型、资源、网络同步、Excel 配表、Studio 与 Git 工作时使用，提供项目身份、架构及从成熟工程提取并适配的通用工程约定。
---

# Chicken Project

## 项目身份与规则分工

- 本地根目录：`C:/Users/herong/Desktop/work/Chicken`。
- 业务范围：烤鸡农场（Chicken Farm / 包含动物养殖、孵化、电击收获、食材入库、烹饪与餐厅经营等玩法）。
- 通用 Roblox/Luau 规范读取相邻 [roblox-game-dev](../roblox-game-dev/SKILL.md) 及任务相关 reference。该目录为公共 SVN External，项目规则维护在本 skill，不擅自修改公共规范。
- 本 skill 提取自成熟 Roblox 项目的可复用工程约定，并按 Chicken 当前工程适配；既有实现与参考做法不同时，先核对实际调用链，不为统一风格盲目扩大改动。

## 按任务读取

- 屏幕系统占用区、安全区与触控布局：读取项目内 [roblox-ui-regions](../roblox-ui-regions/SKILL.md)，通用区域机制由该 skill 维护，Chicken 业务布局仍由项目维护。
- 入口、消息、数据层、配置、存档或模块职责：[架构与配置](references/architecture-and-config.md)。
- 源码探索、严格类型检查、Studio 模式、包边界或 Git 操作：[开发与交付](references/development-workflow.md)。
- UI、文字本地化、BillboardGui 自适应、资源预载或动画生命周期：[UI 与资源](references/ui-and-resources.md)。所有 BillboardGui 必须优先遵循该规范（UIStroke ScaledSize 与 UIAdapter 适配）。
- 道具、装备、预制体、RootPart、VfxInstance、刚性约束或骨骼：[模型结构](references/model-structure.md)。
- 命中与碰撞、客户端预测、高延迟或高频状态同步：[网络同步](references/network-sync.md)。
- Excel 配表、转换命令或 JSON 映射：[配表维护](references/xlsx-json-maintenance.md)。
- 用户明确提出优质实例需求（高品质 3D 模型/道具、专业 UI、精细特效 VFX）：[优质实例创建流程](../quality-instance-workflow/SKILL.md)。

只读取当前任务需要的 reference。各 reference 自包含，不继续链接其他 reference。

## 始终适用的工作方式

- 只编辑本地源码，使用已建立的 Script Sync；不通过 MCP 覆写 Studio 源码或提交草稿，不引入 Rojo。
- 持久化 UI/模型编辑在 Edit 模式进行；源码同步可只读核对，业务执行验证在 Play 中进行。未明确要求时不主动启动 Play。
- **UI 实例唯一来源**：所有项目 UI 必须在 Studio Edit 中预置于 `ReplicatedStorage.UI`（Folder），以该处实例作为结构、静态样式与设计布局的唯一来源；运行时代码只克隆模板、绑定数据与交互、执行适配和动画，禁止用代码创建 UI 或维护第二套硬编码 UI 定义。具体边界见 [UI 与资源](references/ui-and-resources.md)。
- 保留现有真实存档、配置和分析封装机制，不因本地开发自动切换内存模式或禁用服务。
- Git 与 SVN 并存，不删除 SVN 元数据。提交、推送、创建 PR 或发布资产按用户明确授权的动作与范围执行；普通实现授权不自动包含这些动作。
- 交付区分静态检查、源码同步与运行验证，并说明是否需要包同步及其实际状态。仅改文档/skill 时可简写无需包同步。
- **脚本首行中文注释**：所有新增与维护的业务脚本，第一行必须包含脚本作用的中文注释（如 `-- 服务端烤鸡农场主逻辑：负责...`）；紧随其后（第 2 行）保留 `--!strict` 严格模式声明。
- **BillboardGui 规范优先**：所有 3D 浮动标牌（BillboardGui）及 TextScaled 文字必须优先遵循 [ui-and-resources.md](references/ui-and-resources.md) 中的自适应规范（开启 TextScaled，挂载的 UIStroke 强制设置 `StrokeSizingMode = ScaledSize`，杜绝固定像素吞字与 RenderStepped 距离轮询）。
