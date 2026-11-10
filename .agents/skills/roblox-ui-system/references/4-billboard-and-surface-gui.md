# 3D 空间 UI (BillboardGui 与 SurfaceGui) 规范

本规范为 Roblox 3D 空间中的头顶浮动标牌（BillboardGui）与场景表面投射界面（SurfaceGui）提供设计、自适应与性能保障标准。

---

## 一、物理实例与属性预置准则

所有 3D 空间 UI 必须在 Studio **Edit 模式** 下预置于 `ReplicatedStorage.UI`（Folder）中，以 `XxxGui` 命名。

### 1. BillboardGui 核心属性
- **`AlwaysOnTop = true`**：
  - 确保角色轻微穿模、障碍物边缘遮挡或极端俯仰视角下，核心状态（血条、倒计时、交互提示）始终清晰可见，不被几何体切碎。
- **`LightInfluence = 0`**：
  - 完全不受 3D 场景暗光、阴影或动态光照污染，保持图标与字形的清晰对比度与自发光识别度。
- **`MaxDistance` 合理裁剪**：
  - 必须根据游戏视野显式配置 `MaxDistance`（如场景标牌 `70 ~ 120` studs），超出视距自动停止渲染，避免视锥内无效绘制开销。
- **`Size` 尺度规范**：
  - 世界标牌物理尺寸推荐使用 studs 尺度（如 `{8, 0}, {4.25, 0}` 或 `{7, 0}, {2.95, 0}`），内部子节点全比例（Scale 1.0）排布，完全交由原生视口投影；
  - 屏幕贴合型标牌可使用像素 Offset（如 `{0, 160}, {0, 60}`）。

### 2. 实战资产参数参考 (来自实际工程落地)
- **场景库存/垃圾堆指示牌 (`ThrowStockpileGui`)**：
  - `Size = {8, 0}, {4.25, 0}`，`MaxDistance = 70` studs，`StudsOffset = (0, 11.8, 0)`。
- **永久升级属性标牌 (`UpgradeSpeedSignGui`, `UpgradeCarrySignGui`)**：
  - `Size = {7, 0}, {2.95, 0}`，`MaxDistance = 55` studs，`StudsOffset = (0, 0, 0)`。
- **场景指引箭头标牌 (`UpgradeGuideGui`)**：
  - `Size = {4, 0}, {1.34, 0}`，`MaxDistance = 180` studs，超远视距引导。

### 3. 内部 Frame 锚点贴底契约
- 根容器命名为 `XxxFrame`（如 `SignFrame`、`StockpileFrame`）。
- **锚点与位置**：
  - `AnchorPoint = Vector2.new(0.5, 1)`。
  - `Position = UDim2.new(0.5, 0, 1, 0)`。
  - 说明：贴在 Billboard 画布的底部正中，保证当标牌高度或缩放变化时，标牌始终牢牢锚定在 3D 附着点（Adornee）上方，不会上下漂移悬空。
- **根缩放**：
  - 根 `XxxFrame` 下必须挂载直接子节点 `UIScale`。

---

## 二、客户端私有隔离原则 (Local-Only)

在多人联机游戏中，3D 标牌的挂载位置是决定网络带宽与多端稳定性的生命线：

```text
┌─────────────────────────────────────────────────────────────┐
│ ❌ 严重反模式：挂载在 Workspace 物理部件下                  │
│    服务端克隆 -> Workspace.Part.BillboardGui               │
│    后果：全服广播网络同步、所有客户端渲染同一副本、无法私有化 │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│ ✅ 权威规范：客户端本地私有挂载 (Local-Only)                 │
│    客户端从 ReplicatedStorage.UI 模板克隆至:                 │
│    Players.LocalPlayer.PlayerGui                            │
│    并将 billboardGui.Adornee 指向目标 3D Part               │
│    优势：零网络同步带宽、私有化显示、销毁无多端残留         │
└─────────────────────────────────────────────────────────────┘
```

- **必须采用 Local-Only 的场景**：
  - 自身头顶指示箭头、自身血条/耐力条；
  - 玩家当前瞄准的准星、交互距离内的 ProximityPrompt / E 键提示；
  - 客户端预测的伤害飘字与倒计时。
- **全服可见的世界看板**：
  - 仅用于固定建筑或场景公共大屏，通过客户端统一渲染更新。

---

## 三、3D 文本与描边自适应

### 1. 原生自适应规则
- 与屏幕 UI 不同，3D BillboardGui 会随着相机拉远而物理缩小，因此：
  - **BillboardGui 内的所有文本必须开启 `TextScaled = true`**；
  - 文本挂载的 `UIStroke` **严禁使用 `FixedSize`，必须强制设置为 `StrokeSizingMode = ScaledSize`**，`Thickness` 设为 `0.05`；
  - 容器边框 `UIStroke` 强制使用 `StrokeSizingMode = ScaledSize`，`Thickness` 设为 `0.025`（2.5% 短边比例），**严禁误填整数像素**。

### 2. 杜绝 RenderStepped 距离轮询反模式
- 严禁在客户端写 `RunService.RenderStepped` 计算 `(camera.CFrame.Position - part.Position).Magnitude` 去动态调整 `Thickness` 或 `Size`。
- 必须依赖 Roblox C++ 原生引擎的 `ScaledSize` 驱动，达成零脚本开销与无抖动镜头缩放。

---

## 四、UIAdapter 自适应接入与生命周期

若项目集成了视口适配器（如 `UIAdapter`），需按场景调用对应接口：

### 1. 随屏幕分辨率等比缩放
- 针对希望在不同分辨率屏幕下保持物理视觉占比一致的 BillboardGui：
  ```luau
  UIAdapter.AddAdaptiveBillboardGui(billboardGui)
  ```
- 适配器在视口分辨率变化时自动按等比重算 Offset。

### 2. 内部 Frame 随 3D 投影实时自适应
- 当需要根据 3D 投影到视口后的真实像素大小（`billboardGui.AbsoluteSize`）实时调整内部元素的精细缩放时：
  ```luau
  UIAdapter.AddAdaptiveFrameOfBillboardGui(frame, billboardGui, frameUIScale)
  ```

### 3. 注销与对象池回收闭环
- **生命周期铁律**：当 3D 标牌所属的实体死亡、被销毁或归还对象池时，必须显式调用注销，否则适配器中残留的引用将导致严重内存泄漏：
  ```luau
  UIAdapter.RemoveAdaptiveBillboardGui(billboardGui)
  UIAdapter.RemoveAdaptiveFrameOfBillboardGui(frame)
  billboardGui:Destroy()
  ```

---

## 五、SurfaceGui 场景投影规范

1. **模板与挂载**：
   - 模板预置于 `ReplicatedStorage.UI`，命名如 `XxxSurfaceGui`。
   - `Face` 明确指定投射面（如 `Enum.NormalId.Front`）。
   - `LightInfluence = 0` 保证室内外看板发光均一。
2. **像素密度与物理尺度 (PixelsPerStud)**：
   - 保持合理的 `PixelsPerStud`（推荐 `20 ~ 50`），避免过大导致模糊或过小浪费 GPU 纹理显存。
   - 内部排版统一使用 Scale 铺满或以 1920×1080 等比缩放，避免场景拉伸形变。
