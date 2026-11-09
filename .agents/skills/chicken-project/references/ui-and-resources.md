# UI、本地化与资源生命周期

通用可视化可维护性、3D 浮动标牌自适应、资源预热与生命周期约定。

## UI 模板与适配

- **共用排版与缩放**：以 PC 模板作为唯一排版基准；手机、平板与 PC 共用根 UIScale 和系统区域容器规则。禁止另设 Touch/Desktop 几何变体、触屏最小像素补偿、窄屏重排或移动端专用换位。输入差异仅改变交互与提示，同一操作槽位保持相同位置和尺寸。
- **唯一来源**：所有项目 UI（屏幕 UI、BillboardGui、SurfaceGui、弹窗、遮罩与列表项）必须在 Studio **Edit 模式**下创建为 `ReplicatedStorage.UI`（Folder）中的持久化模板实例。结构、静态样式及设计布局以这些实例为唯一来源，不能另在业务代码中保存一套 UI 定义。
- **禁止运行时代码拼装 UI**：游戏业务脚本不得通过 `Instance.new` 或代码构建器在运行期创建、补建或拼装 UI（包括 Frame、文字、按钮、UIScale、UIStroke 与布局组件）。模板缺失时应在 Studio Edit 修复实例，严禁用代码做运行期兜底。
- **代码职责**：运行时仅从模板克隆完整 UI 实例、绑定数据与交互、控制显隐及动画，并负责销毁清理。动态列表克隆对应的预置项模板。
- **布局职责**：固定尺寸、位置、颜色、字体在模板属性或 Attributes 中维护；代码读取模板数据，按视口或安全区计算适配，不硬编码第二套设计布局。
- **根缩放与设计分辨率**：以 1920×1080 设计基准，面板、文本、描边使用统一的视口适配负责人，不对同一树叠加第二套视口缩放。
- **文字与描边**：屏幕单行文字关闭 `TextScaled` 与 `TextWrapped`，通过设计字号结合根 `UIScale` 缩放。多行文本保持换行。文字描边强制使用 `StrokeSizingMode = ScaledSize`。

## 3D 浮动标牌（BillboardGui）与文本描边自适应规范

本项目的**所有 `BillboardGui`（包括动物头顶血条/状态、产出倒计时、交互浮标、自身标记等）必须优先遵循本节规范**。

### 1. 结构与 Studio 物理实例预置准则
- **预置位置**：模板在 Studio Edit 模式下预置于 `ReplicatedStorage.UI`，命名如 `xxxGui`。
- **核心属性**：
  - `AlwaysOnTop = true`：确保轻微遮挡或极端视角下不丢失标牌。
  - `LightInfluence = 0`：完全不受 3D 场景低照度环境光影响，保持发光与清晰识别度。
- **内部容器结构**：
  - 根节点命名为 `xxxFrame`，尺寸使用 Offset 像素。
  - 锚点与位置：`AnchorPoint = (0.5, 1)`，`Position = UDim2.new(0.5, 0, 1, 0)`（贴在 BillboardGui 画布底部）。
  - 根节点下挂载直接子节点 `UIScale`。
- **客户端私有隔离（Local-Only）**：
  - 仅当前玩家自身可见的浮标，在客户端运行时从模板克隆至 `Players.LocalPlayer.PlayerGui`，将 `Adornee` 指向 3D Part。
  - 严禁挂载在 Workspace 物理部件下网络广播给所有客户端，从根本上杜绝多端串扰和网络同步开销。
- **本地化与防污染**：
  - 动态变更的数字、倒计时以及纯图标（如 `▼`、`●` 等字符）必须显式设置 `AutoLocalize = false`，严禁让引擎翻译器识别或抓取脏词条。

### 2. 文本与描边自适应（硬性必须遵守）
- **痛点规避**：当相机与 3D 实体距离变远时，文字在视口中自动缩小；若文本下的 `UIStroke` 保持传统的固定像素模式（`FixedSize`），描边厚度不随字号改变，会导致文字核心笔画被描边完全侵蚀遮挡，远距离只能看到一团色块。
- **原生自适应规则**：
  - 标牌内所有文本组件必须设置 `TextScaled = true`。
  - 文本挂载的 `UIStroke` **严禁使用默认的 `FixedSize`，必须设置 `StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize`**。
  - 容器/线框（Frame）若在 BillboardGui 中使用 `UIStroke`，也应统一开启 `StrokeSizingMode = ScaledSize`（`ApplyStrokeMode = Border`），且 **`Thickness` 必须使用相对于容器短边的小比例（如 `0.02 ~ 0.03`，推荐 `0.025` 即 2.5%），严禁误留像素数值**。
  - 推荐属性配置：
    | 属性名 (Property) | 文本描边 (Contextual) | 容器边框 (Border) | 说明 |
    | :--- | :--- | :--- | :--- |
    | **`StrokeSizingMode`** | `ScaledSize` | `ScaledSize` | 描边厚度按比例缩放，杜绝远距遮挡或边框过粗 |
    | **`Thickness`** | `0.04` – `0.08`（推荐 `0.05`） | `0.02` – `0.03`（推荐 `0.025`） | 文本按字号 5%、容器按短边 2.5% |
    | **`ApplyStrokeMode`** | `Contextual` | `Border` | 文本仅作用于字形；容器作用于边框 |
    | **`Transparency`** | `0` – `0.2` | `0` – `0.2` | 保持清晰轮廓与对比度 |
- **严禁帧轮询反模式**：
  - 严禁在 `RenderStepped` 或事件循环中手动计算相机与实体的 3D 距离去动态修改 `Thickness`。
  - 必须依赖 Roblox C++ 原生 `ScaledSize` 驱动，零客户端脚本帧开销，彻底杜绝镜头移动时的文字抖动。

## 文案与本地化

- 静态文案直接预置，AutoLocalize=true；动态文案通过配置/词表维护。
- 纯数字、时间、玩家名及装饰性图标 AutoLocalize=false，不作为词条。文字图标不和需翻译的句子混在一个词条中。

## 预加载与生命周期清理

- 外部模型、图片、音效、动画 ID 集中在配置中管理。
- 高频动作缓存可复用的 AnimationTrack；状态切换优先 Play/Stop，不反复 LoadAnimation/Destroy。
- 事件连接、任务（task.delay/spawn）、Tween、临时克隆与对象池必须有明确所有者及释放点，防止反复初始化导致内存泄漏与事件重复触发。
