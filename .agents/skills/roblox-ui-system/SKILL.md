---
name: roblox-ui-system
description: 通用 Roblox UI 与 GUI 系统开发规范与架构指南。涵盖 1920×1080 基准画布、Studio 模板唯一来源、固定画布与多端采样合并的静态禁放参考 Frame、二分单行文本拟合与 7 级标准字号模板、UIStroke ScaledSize 杜绝文字吞噬、3D BillboardGui 本地隔离与零帧轮询、端独立操作变体、UIManager 窗口生命周期管理及模态交互。
---

# Roblox UI & GUI 通用系统规范 (Roblox UI System)

本 Skill 整合了 Roblox 商业级游戏开发中所有经过实战检验的 UI 视觉设计、Studio 模板持久化工程、客户端 GUI 框架架构、固定 1920×1080 画布与离线采样合并的公共禁放参考模板、二分文本拟合、7 级标准字号层级模板及端独立操作 UI。它独立于任何单一游戏的业务逻辑，适用于所有通用 Roblox 项目。

---

## 核心速查与八大硬性铁律 (Non-Negotiable Rules)

1. **模板唯一来源原则 (Single Source of Truth)**：
   - 所有 UI 预制体（全屏主界面、居中弹窗、列表项、遮罩、BillboardGui、SurfaceGui、动效飘字、双端控制变体及状态卡变体）必须在 Studio **Edit 模式** 下创建并保存在 `ReplicatedStorage.UI`（Folder）中；
   - **绝对禁止运行时通过 `Instance.new` 手拼或补建 UI 结构与样式**。游戏代码只负责克隆模板、绑定数据与事件、驱动补间动画与生命周期清理。
2. **1920 × 1080 基准与单一缩放负责人**：
   - 屏幕设计基准统一为 `1920 × 1080`；
   - 全屏根节点设置 `Size = {0, 1920}, {0, 1080}`，居中锚定 `AnchorPoint = Vector2.new(0.5, 0.5)`，直接子节点挂载 `UIScale`（初始 Scale=1）；
   - 根尺寸始终不变，缩放 `min(屏幕宽/1920, 屏幕高/1080)`，居中显示；项目 UIAdapter 使用只缩放的 `Center` 模式，普通画布不使用会扩展尺寸的 `FullScreen` 模式；
   - 局部面板和弹窗在完整画布中设计；同一树只注册一次视口缩放。背景与模态遮罩独立铺满实际视口。
3. **公共静态禁放参考模板**：
   - Studio Edit 预置 `ReplicatedStorage.UI.ScreenLayoutGuideFrame`，固定 `1920×1080`；内部 `ReservedAreasFrame` 用半透明红色矩形表示各端占用区投影后的并集；
   - 设计时复制到业务根画布下并对齐 `(0,0)`，完成核对后移除临时副本。正式业务模板不携带参考层；参考层不作为业务父容器；
   - 左上系统区与原生跳跃键在开发阶段采样后取并集；不预留底部横条、设备侧边或右上系统区，默认增加 `24` 设计像素间距；不收集左下摇杆区域；
   - 不使用运行时区域控制器、系统控件追踪、水平夹取或设备重排。固定参考只覆盖已测设备和状态，新增设备通过离线补采样更新。
4. **普通 UI 一套排版，独立端 UI 独立模板**：
   - 普通屏幕 UI 全端共用固定画布、位置、尺寸和字号，仅根节点整体缩放；不因输入设备变化调整普通 HUD 几何；
   - 明确独立的桌面/触控操作 UI 可维护 `Desktop`、`Touch` 变体。原生跳跃键依附和最小物理触控尺寸仅适用于这些独立端 UI，不作为普通 HUD 默认接入要求；
   - 左下摇杆未纳入公共禁放图；纯展示层不阻断输入，实际触控手势仍需验证。
5. **屏幕单行文本禁用 TextScaled，严格对标 7 级标准字号模板**：
   - 屏幕单行动态文本强制设置 `TextScaled = false`、`TextWrapped = false`；
   - 必须对标标准文本字号模板（T1: `72`、T2: `56`、T3: `44/36`、T4: `32`、T5: `28`、T6: `26/24/22`、T7: `20/9`），在模板内设置 Attribute `DesignTextSize = <基准字号>` 作为设计上限；
   - 文本框尺寸必须预留二分拟合扣除的 `8 px` 留白高度，确保常用数值样本达到 90% 以上拟合达成率；
   - 运行时调用二分查找算法（`TextFitting.FitTextLabel` / `UIManager.FitTextLabel`）在设计框内**只缩不放**，确保短文本清晰锐利、长文本优雅不溢出。
6. **UIStroke 100% 强制使用 ScaledSize**：
   - 文本与 3D 标牌上的 `UIStroke` **严禁使用默认的 `FixedSize`，必须设置 `StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize`**；
   - 文本描边厚度推荐 `Thickness = 0.05`（字号 5%）；容器边框推荐 `0.012 ~ 0.025`（短边 1.2%～2.5%，**严禁误填整数像素**）；杜绝距离拉远或分辨率变化时粗描边吞噬字形。
7. **3D Billboard 客户端私有隔离与零帧轮询**：
   - 玩家专属的 3D 浮动标牌（自身标记、血条、专属交互浮标、准星）必须在客户端从模板克隆至 `LocalPlayer.PlayerGui`，设置 `Adornee`，**严禁挂在 Workspace 物理部件下网络广播**；
   - 结构统一为根 Frame 贴底锚定（`AnchorPoint = Vector2.new(0.5, 1)`, `Position = UDim2.new(0.5, 0, 1, 0)`），设置 `AlwaysOnTop = true`, `LightInfluence = 0`；
   - 依赖引擎原生 `ScaledSize` 驱动，**严禁在 `RenderStepped` 中手动轮询距离修改 Thickness**。
8. **声明式 Attribute 契约驱动 (Declarative Attribute Contracts)**：
   - 固定布局直接维护在模板 Position/Size 中，不增加区域绑定 Attributes；状态、颜色与动画参数仍由模板 Attributes 声明，运行时代码读取。独立端操作 UI 可维护自身依附参数。

---

## 按专题深入参考 (References)

| 专题领域 | 参考文档 | 核心内容提要 |
|---|---|---|
| **1. UI 设计与 Studio 模板** | [设计与模板规范](references/1-ui-design-and-templates.md) | 1920×1080 画布、三大视觉主题（SIM/STUDS）、14 类语义布局模板矩阵、控件 UpperCamelCase 命名与属性契约全景表 |
| **2. GUI 架构与生命周期** | [GUI 架构与生命周期](references/2-gui-architecture-and-lifecycle.md) | UIManager 窗口单例分层、WindowConfigs 配置驱动、CreateFrame 常驻生成、WindowBase 弹性动效、GuiWrapperBase、全局模态遮罩与按钮交互系统 |
| **3. 文本拟合与描边** | [文本与描边自适应规范](references/3-text-and-stroke-fitting.md) | 7 级标准字号层级模板（T1: 72pt ~ T7: 9pt）、二分查找字号算法原理、DesignBox 坐标换算、RichText 剥离、弱引用零 GC 缓存、ShadowText 阴影同步与 UIStroke 权威配比表 |
| **4. 3D 空间 UI** | [3D 空间 UI 规范](references/4-billboard-and-surface-gui.md) | BillboardGui 核心属性（AlwaysOnTop/LightInfluence）、贴底锚点、Local-Only 隔离、UIAdapter 投影接入与注销闭环、SurfaceGui 像素密度规范 |
| **5. 固定画布与公共禁放参考** | [多端适配与安全区规范](references/5-safe-regions-and-multidevice.md) | 开发期设备采样、画布坐标投影、矩形并集合并、静态参考模板、根等比缩放与验收边界 |
| **6. 本地化与资源管线** | [本地化与资源管线规范](references/6-localization-and-assets.md) | 多语言防污染分流（纯英文静态 vs 动态带参 vs 纯数字/符号）、图标流、Preload 下载与 Warmup 渲染预热、清理清单 |

---

## 通用生产级源码资产 (Assets)

可直接复制到任何新 Roblox 项目中开箱即用的通用模块：

- [`assets/BuildScreenLayoutGuide.luau`](assets/BuildScreenLayoutGuide.luau)：仅 Studio Edit 使用的幂等静态参考模板构建器，接收离线合并矩形，不在客户端运行。
- [`assets/ReadScreenLayoutSample.luau`](assets/ReadScreenLayoutSample.luau)：在 Studio 客户端插件上下文采集安全边缘、系统顶栏与跳跃键几何，输出 JSON；按项目实际根路径配置后使用。
- [`scripts/build_screen_layout_guide.py`](scripts/build_screen_layout_guide.py)：开发期投影与矩形并集工具，输出可核验的 JSON 和 SVG，不进入游戏运行时。
- [`assets/TextFitting.luau`](assets/TextFitting.luau)：独立的二分查找单行文本字号拟合模块（包含 `FitTextLabel`、`FitTextWithShadow`、`FitMarkedText`、`FitMarkedRoot`）。
- [`assets/UIManagerTemplate.luau`](assets/UIManagerTemplate.luau)：基于配置驱动的通用客户端单例 UI 管理器骨架，内含窗口管理、层级自动计算、模态遮罩及按钮动效。
- [`assets/WindowBaseTemplate.luau`](assets/WindowBaseTemplate.luau)：通用弹窗基类骨架，内含 Back Easing 弹性打开动效与生命周期钩子。
- [`assets/GuiWrapperBaseTemplate.luau`](assets/GuiWrapperBaseTemplate.luau)：通用常驻 HUD 界面包装基类骨架。

---

## 标准开发工作流 (Standard Workflows)

### 1. 固定画布与公共参考工作流
1. 普通屏幕 UI 根画布固定 `1920×1080`、居中，根 UIScale 仅做整体等比缩放。
2. 有公共参考模板时，直接在设计中叠加使用；仅在首次建立或新增设备时，执行开发期采样、投影、并集合并和覆盖核验。
3. 用离线合并结果在 Studio Edit 构建/更新唯一 `ScreenLayoutGuideFrame`，所有普通界面据此手工排版。
4. 正式模板移除临时参考副本，客户端仅克隆业务模板、绑定数据/事件、执行动画及根缩放；无区域控制器。

### 2. 创建新弹窗工作流
1. **Studio Edit 预制**：在 `ReplicatedStorage.UI` 下创建固定 `1920×1080` 居中画布，局部弹窗面板放在画布内；画布挂载视口 UIScale，弹窗面板可挂载独立动画 UIScale；需要动效的按钮设置 `HasInteractionEffect = true` 并挂子节点 `UIScale`；单行动态文字设置 `DesignTextSize`；
2. **编写派生窗口类**：继承自 `WindowBase`，在 `OnInit` 中初始化控件与数据绑定，在 `OnClose` 中清理资源；
3. **注册窗口配置**：在客户端初始化脚本中向 `UIManager.RegisterWindow("XxxWindow", { frameName = "XxxFrame", isModal = true, newWindow = ... })` 注册；
4. **业务调用**：通过 `UIManager.OpenWindow("XxxWindow", ...)` 或 `window:Close()` 打开与关闭。

### 3. 动态数据看板与文本刷新工作流
1. 数据到达时，拼接文案（例如 `string.format("LEVEL %d", level)`）；
2. 赋值 `label.Text = newText`；
3. 调用 `UIManager.FitTextLabel(label)` 或 `UIManager.FitTextWithShadow(label, shadowLabel)`；
4. 算法自动在毫秒级内完成二分查找计算，确保文字在设计框内只缩不放且与阴影层严密对齐。
