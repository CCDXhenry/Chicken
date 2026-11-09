# UI 编辑规范

在 Roblox Studio 中创建或修改界面时遵循本规范。

## 编辑前提

- 在 Edit 模式修改。Play 模式中的改动停测后会丢失。
- 界面模板放在 `ReplicatedStorage.UI`。

## 设计分辨率与根节点

设计分辨率是 `1920 × 1080`。需要随屏幕缩放的根 `Frame` 添加直接子节点 `UIScale`，`Scale` 为 `1`。根节点 `Size` 使用 Offset。

根节点 `BackgroundTransparency = 1`。底板、按钮和装饰用子级 `ImageLabel` / `ImageButton` 表现。

**全屏界面**（主界面、全屏窗口、全局提示）

- `Size = {0, 1920}, {0, 1080}`， `AnchorPoint = (0.5, 0.5)`， `Position = {0.5, 0}, {0.5, 0}`。

**居中弹窗**

- 按内容使用 Offset 尺寸，如 `{0, 1280}, {0, 800}`。
- `AnchorPoint = (0.5, 0.5)`，`Position = {0.5, 0}, {0.5, 0}`。
- 直接子节点 `UIScale` 的 `Scale` 为 `1`。

铺满父级的遮罩使用 `Size = {1, 0}, {1, 0}`，不加 `UIScale`。

## 子节点布局

- 面板、按钮、图标、文字按 `1920 × 1080` 设计稿用 Offset 摆放。
- 铺满父级的背景 `ImageLabel` 使用 `Size = {1, 0}, {1, 0}`。
- 随父级变宽、高度固定的条，使用 Scale X + Offset Y，例如 `{1, -40}, {0, 50}`。
- 血条、进度遮罩用 Scale 宽度表达比例，高度铺满父级，例如 `{0.7, 0}, {1, 0}`。
- 成组排列使用 `UIListLayout`，`SortOrder = LayoutOrder`，间距写在 `Padding` 的 Offset 上。
- `ScrollingFrame` 的 `AutomaticCanvasSize` 与滚动方向一致，对应轴的 `CanvasSize` 为 `0`。滚动条厚度使用 `10` 或 `12`。
- 列表中放一份列表项模板，`Visible = true`，用 `LayoutOrder` 排顺序。
- 引导手指等跟随目标的小组件使用自身 Offset 尺寸，放在 `ReplicatedStorage.UI`，根节点带 `UIScale`。

## 命名

- 使用有语义的英文 `UpperCamelCase`。
- 后缀对应控件类型：`Frame`、`Text`、`Image`、`Button`。`ScrollingFrame` 保留该后缀。
- 按钮使用 `ImageButton`。按钮文字是其子级 `TextLabel`。
- 弹窗模板以 `Frame` 结尾，如 `SettingsFrame`。
- 缩放节点命名为 `UIScale`，描边节点命名为 `UIStroke`，都作为目标控件的直接子节点。

## 按钮

- 需要悬停放大与按下缩小的按钮设置 Attribute `HasInteractionEffect = true`，并添加直接子节点 `UIScale`。滑动条、列表项、页签不加这个属性。
- 需要点击音效的按钮设置 Attribute `HasClickSound = true`。按住不放的操作按钮不加。

## 文本与图片

- 需要随控件缩放的文字设置 `TextScaled = true`。长文案额外加 `UITextSizeConstraint`，并设置 `MaxTextSize`。
- 描边使用直接子节点 `UIStroke`，`ApplyStrokeMode = Contextual`。新增 `UIStroke` 描边厚度默认值为 `字体大小/12.5`。
- 固定文案：`AutoLocalize = true`，`Text` 为纯英文。
- 会变化的文案、数字、玩家名：`AutoLocalize = false`。
- 图标 `ScaleType = Fit`。九宫格背景 `ScaleType = Slice`，并设置 `SliceCenter`。普通拉伸背景 `ScaleType = Stretch`。

## 头顶 BillboardGui

- 模板放在 `ReplicatedStorage.UI`，命名如 `xxxGui`。
- `AlwaysOnTop = true`，`LightInfluence = 0`。
- 内部根节点命名为 `xxxFrame`，尺寸使用 Offset，并带直接子节点 `UIScale`， `AnchorPoint = (0.5, 1)`，`Position = {0.5, 0}, {1, 0}`，贴在 Billboard 底部。
