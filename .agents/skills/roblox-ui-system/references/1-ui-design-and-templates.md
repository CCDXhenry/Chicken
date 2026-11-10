# UI 视觉设计、Studio 模板规范与 1920 基准画布

本规范为所有 Roblox 游戏的 UI 视觉设计、Studio 场景预制体制作及尺寸层级标准提供权威契约。

---

## 一、核心工程铁律：模板唯一来源原则

1. **唯一来源 (Single Source of Truth)**：
   - 游戏中所有 UI 预制体必须在 Studio **Edit 模式** 下创建，并持久化保存在 `ReplicatedStorage.UI`（Folder）中。
   - 包含的模板类型矩阵：
     - **全屏主画布**：`GameFrame`、`XxxHudFrame`（1920×1080，挂载根 `UIScale`）；
     - **端独立操作变体**：`XxxControlLayouts`（Folder，内含 `Desktop` 键鼠操作卡与 `Touch` 触控虚拟按键）；
     - **卡片/战况变体**：`XxxStatusLayouts`（Folder，内含 `Main` 本队、`Other` 他队、`Lobby` 大厅等几何与字号预置项）；
     - **动效与反馈组件**：`XxxRewardFrame`（`CanvasGroup` 整体渐隐渐变飘字）、`XxxFlightImage`（`ImageLabel` 曲线飞行动效）；
     - **交互遮罩**：`ModalButton`（全屏 1×1 交互拦截层）；
     - **3D 空间标牌**：`XxxSignGui`（`BillboardGui`、`SurfaceGui`）。
   - 界面结构、静态样式（颜色、圆角、背景贴图、边框描边）以及设计稿初始尺寸以这些模板实例为唯一标准，禁止在业务脚本中硬编码第二套 UI 定义。
2. **严禁运行时通过代码拼装 UI**：
   - 游戏脚本不得通过 `Instance.new` 或代码构建器在运行时创建、补建或逐个拼装 UI，包括 Frame、文字组件、按钮、UIScale、UIStroke 以及布局/约束组件。
   - 模板缺失或损坏时，应在 Edit 模式下修复模板实例，严禁在代码中添加动态生成的兜底拼装逻辑。
3. **代码职责边界**：
   - 运行时代码仅负责从 `ReplicatedStorage.UI` 克隆模板完整实例、挂载至目标容器、绑定数据与事件、驱动状态动画以及执行清理销毁。

---

## 二、1920 × 1080 设计基准与画布层级

所有普通屏幕 UI 均在固定 `1920 × 1080` 横屏画布内设计，完整画布只做居中等比缩放。

公共 `ScreenLayoutGuideFrame` 在设计时对齐根画布 `(0,0)`，半透明红色矩形表示多端采样禁放区并集（已含 24 设计像素间距，不含左下摇杆）。普通内容避开红区，背景/装饰可进入；正式业务模板移除临时参考副本。

### 1. 全屏主界面（Main HUD / 全屏窗口）
- **尺寸与位置**：
  - `Size = UDim2.fromOffset(1920, 1080)`（或 `{0, 1920}, {0, 1080}`）。
  - `AnchorPoint = Vector2.new(0.5, 0.5)`。
  - `Position = UDim2.fromScale(0.5, 0.5)`（居中）。
  - `BackgroundTransparency = 1`（根节点透明，底板装饰交由子级表现）。
- **根缩放**：
  - 必须直接挂载子节点 `UIScale`，初始 `Scale = 1`。
  - 运行时交由屏幕适配器（如 `UIAdapter` 或系统视口缩放管理），仅设置 `min(屏幕宽/1920, 屏幕高/1080)`，不得改变根逻辑尺寸。使用项目 UIAdapter 时选 `Center`，不选会扩展画布的 `FullScreen`。
  - **严禁在同一节点树上叠加第二套视口缩放**。

### 2. 居中弹窗（Dialog / Modal Window）
- 完整窗口模板使用 `1920×1080` 居中根画布；局部弹窗面板作为子节点，按设计稿使用 Offset 尺寸，如 `800×520`。
- 根画布只注册一次视口缩放；局部面板的 `UIScale` 仅负责弹出动画，不再注册视口适配。
- UI 框架应将窗口层级分配到完整画布，模态遮罩在实际屏幕层铺满视口。

### 3. 全屏半透阻断遮罩（Modal Backdrop）
- `Size = UDim2.fromScale(1, 1)`。
- `Position = UDim2.fromScale(0, 0)`。
- **不挂载 UIScale**（始终严格铺满整个真实视口，不受设计基准缩放限制）。

---

## 三、子节点布局与排版规则

1. **绝对尺寸与相对比例分工**：
   - 铺满父级的底板/渐变背景：使用 Scale，`Size = UDim2.fromScale(1, 1)`。
   - 随父级宽度自适应、高度固定的栏目条：使用 Scale X + Offset Y，例如 `UDim2.new(1, -32, 0, 60)`。
   - 血条、进度条遮罩：宽度使用 Scale 表达比例（`0.0 ~ 1.0`），高度铺满父级（Scale 1.0），例如 `UDim2.new(progress, 0, 1, 0)`。
   - 图标、固定按钮、字号边框：按 1920×1080 设计稿 Offset 摆放。
2. **列表与多项排列**：
   - 成组元素必须使用 `UIListLayout` 或 `UIGridLayout`。
   - `SortOrder` 必须设置为 `Enum.SortOrder.LayoutOrder`，间距（Gap）设置在 `Padding` 的 Offset 上。
   - 列表模板内放置一份默认列表项模板（`Visible = true`），运行时克隆此项并根据业务数据赋值。
3. **滚动容器 (ScrollingFrame)**：
   - `AutomaticCanvasSize` 必须与滚动方向一致（如竖向滚动设为 `Y`，横向设为 `X`）。
   - 对应滚动轴的 `CanvasSize` 设为 `0`（完全由内容自动撑开）。
   - 滚动条厚度（`ScrollBarThickness`）统一设为 `8`、`10` 或 `12` px，保持细腻精致。
4. **标准字号层级对标**：
   - 所有文本控件必须严格对标 [标准 UI 文本字号层级模板](3-text-and-stroke-fitting.md#三标准-ui-文本字号层级规范模板-standard-typography-hierarchy)（T1: 72pt、T2: 56pt、T3: 44/36pt、T4: 32pt、T5: 28pt、T6: 26/24/22pt、T7: 20/9pt）；
   - 文本框尺寸必须预留二分拟合算法扣除的 `8 px` 留白高度，确保常用业务样本达到 90% 以上字号达成率。

---

## 四、控件命名与属性契约

### 1. 命名规范 (UpperCamelCase)
所有控件必须使用语义明确的驼峰命名，且**后缀严格对应控件类型**：
- 容器/面板：`Frame`，例如 `SettingsFrame`、`ItemCardFrame`、`HealthBarFrame`。
- 文本标签：`Text`，例如 `TitleText`、`PriceText`、`CountText`。
- 图片/图标：`Image`，例如 `IconImage`、`BannerImage`、`AvatarImage`。
- 交互按钮：`Button`，例如 `CloseButton`、`ConfirmButton`、`BuyButton`。
- 滚动区域：`ScrollingFrame`，例如 `InventoryScrollingFrame`。
- 辅助组件：`UIScale`、`UIStroke`、`UICorner`、`UIPadding`，均保留其类名。

### 2. 声明式 Attribute 契约驱动全景表
固定几何使用模板 Position/Size；状态与动画参数使用 Attributes。下表按键依附和 MinimumTouchSize 仅供独立端操作 UI 使用，不应用到普通 HUD：

| Attribute 字段名 | 类型 | 适用对象 | 契约与作用说明 |
| :--- | :--- | :--- | :--- |
| **`JumpAnchor`** | string | 触控操作按钮 | 相对原生跳跃键的锚点（如 `"0, 0.5"` 为左侧垂直居中，`"0.5, 0"` 为正上方） |
| **`JumpGapDirection`**| string | 触控操作按钮 | 相对原生跳跃键的外推间距方向（如 `"-1, 0"` 为向左外推，`"0, -1"` 为向上外推） |
| **`JumpRelativeSize`**| number | 触控操作按钮 | 相对原生跳跃键物理尺寸的比例（如 `0.75` 或 `1.0`） |
| **`MinimumTouchSize`** | number | 移动端交互按钮 | 保证移动端实际触控区域不低于指定像素（默认 `44` 或 `52` px） |
| **`DesignTextSize`** | number | 动态单行文本 | 声明设计上限字号（如 `28`、`36`、`44`、`72`），运行时由 `FitTextLabel` 在设计框内只缩不放 |
| **`HasInteractionEffect`**| bool | 交互按钮 | 声明需要通用移入放大/按下缩小微动效（必须挂载直接子级 `UIScale`） |
| **`PressedScale`** | number | 按钮 / 动作卡 | 按下时目标缩放比例（如 `0.94` 或 `0.80`） |
| **`HoldSec` / `FadeSec`**| number | 飘字/通知容器 | 动效悬停展示时间（如 `1.0`s）与渐隐销毁耗时（如 `0.2`s） |
| **`PulseScale` / `ComboPulseScale`**| number | 收益飘字 | 普通入场轻微脉冲放大（如 `1.08`）与连击入场大幅脉冲放大（如 `1.16`） |
| **`FlightSec` / `BounceScale`**| number | 飞行动效 Label | 飞行动画时间（如 `0.45`s）与到达目标时的弹跳放大倍率（如 `1.12`） |
| **`AccentColor`** | Color3 | 控制卡/操作钮 | 组件语义强调色（如拾取青绿 `#66EBAC`、投掷暖橙 `#FF9634`） |
| **`ReadyBackground` / `HeldBackground`** | Color3 | 操作卡底板 | 操作就绪底色与按住充能中底板颜色 |
| **`HeldStrokeTransparency`** | number | 边框 UIStroke | 状态透明度梯度（就绪 `0.25`，按住 `0`，禁用 `0.65`） |

---

## 五、三大视觉风格体系 (Theme Routing)

在开始任何 UI 制作前，必须先确定设计语言与主题风格：

1. **SIM 主题（卡通圆角卡片风）**：
   - 特征：纯白/浅色底板、大圆角（`UICorner` 12~16 px）、柔和弥散阴影、高饱和度鲜艳描边。
   - 适用：模拟器、放置点击、养成宠物、休闲聚会类玩法。
2. **MODERN STUDS / 工业风主题（经典积木凸点与工业铭牌风 - 推荐）**：
   - 特征：
     - **深色石墨底板**：深石墨 `#252B2C`、炭黑 `#111617`、工业深蓝 `#182536`、深面板 `#263D4E`；
     - **金属包边与双层边框**：金属灰 `#596361` 外框，内部嵌套 `IndustrialBorderFrame` / `IndustrialBoardFrame` 双层冲压铭牌；
     - **高对比文字**：暖白正文 `#F3EBDD` / `#F5F7FA`，搭配 100% `ScaledSize` 黑色描边；
     - **鲜明阵营与操作语义色**：青蓝 `#2DA9FF`、薄荷绿 `#66EBAC`、工业锈橙 `#FF9634`、磁紫 `#A470EB`、翠绿 `#48CF86`、金币金 `#FFD700`；
     - **微圆角**：`UICorner` 6~12 px，状态进度药丸统一 `UDim.new(1, 0)`。
   - 适用：竞技对战、末日生存、工厂工坊、经典 Roblox 风格。
3. **CLASSIC STUDS 主题（经典复古叠层风）**：
   - 特征：纯方角斜角浮雕、像素感厚底板、多层高对比矩形堆叠。
   - 适用：怀旧、复古老派 Roblox 界面还原。

---

## 六、14 类语义布局模板矩阵 (Semantic Layout Matrix)

界面设计严禁随意凭空拼凑，必须对标以下标准语义布局：

| 布局模版分类 | 模版标识 | 典型应用场景 | 关键设计契约 |
|---|---|---|---|
| **常驻玩法 HUD** | `hud-zone-system` | 血条、资源、快捷状态 | 避让屏幕边缘安全区与顶栏，常驻展示不遮挡中央视线 |
| **持久侧边栏** | `vertical-navigation-sidebar` | 左侧/右侧功能导航入口 | 竖向弹性列表，带小红点与选中高亮动效 |
| **商业化与商城** | `shop-grid` | 道具商城、通行证、限时礼包 | 卡片网格、角标、划线原价与购买弹窗联动 |
| **背包与存储** | `grid-inventory` | 装备、宠物、物品背包 | 网格多页滚动、品质色边框、长按浮动详情框 |
| **全屏登录/选关** | `fullscreen-landing` | 标题画面、选图、角色选择 | 全屏半透底板、居中品牌 Logo、主操作突出按钮 |
| **选择与对比** | `select-screen` | 阵营选择、职业挑选、属性对比 | 左右分栏对比、3D 视口角色实时展示卡 |
| **二次确认弹窗** | `centered-dialog` | 购买确认、重生提示、系统警示 | 居中悬浮、阻断式半透遮罩、主次按钮分明 |
| **任务与成就中心** | `progression-hub` | 每日任务、战令里程碑 | 线性进度条、阶梯节点奖励、一键领取状态反馈 |
| **排行榜单** | `stat-leaderboard` | 积分榜、段位榜、连胜排行 | 滚动列表、前三名皇冠/奖牌排版、自己名次固定置底 |
| **瞬态通知与 Toast** | `notification-alert` | 升级提醒、错误告警、通告 | 顶部/中上方弹出、自动渐隐销毁、不抢夺操作焦点 |
| **大转盘抽奖** | `wheel-spin` | 八分区概率转盘、每日轮盘 | 径向扇形布局、中间指针、匀减速物理回弹算法 |
| **卷轴开箱** | `vertical-reel-roll` | 盲盒、扭蛋、开蛋机滚动卷轴 | 竖向连续跑马灯、减速锁格动效、稀有度光效爆发 |
| **放置连点器** | `incremental-clicker` | 大点击主按钮、每秒产出数值 | 超大响应区、点击浮动缩放动效（Punch Scale） |
| **管理后台控制台** | `admin-control-panel` | 调试菜单、GM 指令面板、监控 | 紧凑信息流、可折叠分组、日志控制台面板 |
