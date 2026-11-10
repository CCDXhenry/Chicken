# 客户端 GUI 框架架构与生命周期规范

本规范定义 Roblox 客户端 UI 的程序架构、分层设计、窗口生命周期、模态遮罩与全局微动效系统。

---

## 一、架构分层与职责契约

Roblox 客户端 UI 框架分为三层：

```text
┌────────────────────────────────────────────────────────┐
│                      表现与业务层                       │
│  (Window 派生类、HUD 包装类、数据监听与呈现逻辑)       │
└───────────────────────────┬────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│                      框架抽象层                        │
│   WindowBase (弹窗基类)   │  GuiWrapperBase (HUD 包装基类) │
│              UIActions (解耦抽象动作集合)               │
└───────────────────────────┬────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│                      核心管理单例                       │
│     UIManager (模板克隆、ZIndex 排布、遮罩、动效、文本拟合)    │
└────────────────────────────────────────────────────────┘
```

1. **UIManager (单例)**：
   - 掌握 UI 模板来源（`ReplicatedStorage.UI`）与屏幕根挂载点（`StarterGui.GameScreenGui`）。
   - 维护所有弹窗配置（`WindowConfigs`）与当前活动窗口实例。
   - 统一计算动态窗口层级（`ZIndex`），维护全局唯一模态半透遮罩（`ModalButton`）。
   - 全局监听按钮的创建与销毁，自动绑定悬停/点击微动效与音效。
   - 统一暴露纯函数文本自适应拟合接口。
2. **WindowBase (弹窗基类)**：
   - 封装弹窗的打开动画（弹性缩放 `Scale` 动效）、自适应适配与销毁生命周期。
   - 提供标准的 `OnInit()`、`OnClose()`、`Close()` 钩子，禁止外部直接 `Destroy()` 窗口节点破坏状态。
3. **GuiWrapperBase (常驻 HUD 包装基类)**：
   - 适用于玩法主 HUD、快捷操作条、信息看板等非模态、常驻型界面。
   - 通过 `UIManager.CreateFrame(frameName, frameParent, zIndex)` 克隆生成实例并交由 Wrapper 管理；
   - 自动绑定 `Destroying` 事件，在节点被销毁时统一释放数据监听、子 Presentation、Tween 补间与引用。

---

## 二、UIManager 核心服务接口

### 1. 常驻界面快速生成 (`CreateFrame`)
针对无需注册为弹窗（如主游戏 HUD `ThrowHudFrame` 或局部面板），通过 `CreateFrame` 从 `ReplicatedStorage.UI` 快速克隆挂载：
```luau
function UIManager.CreateFrame(frameName: string, frameParent: GuiBase2d?, ZIndex: number?): Frame
```

### 2. 静态文本拟合初始化 (`FitMarkedRoot` / `FitMarkedText`)
模板中的静态单行文字在生成后可能不再被赋值，通过遍历容器对带 `DesignTextSize` 属性的 TextLabel 补齐一次设计框二分拟合：
```luau
function UIManager.FitMarkedRoot(root: Instance): ()
```

### 3. 配置注册契约
所有弹窗必须通过 `WindowConfig` 显式注册，禁止在业务脚本中硬编码克隆逻辑：

```luau
type WindowConfig = {
    frameName: string,                                                         -- 预制体名称 (位于 ReplicatedStorage.UI)
    isModal: boolean,                                                          -- 是否为阻断式模态窗口
    modalTransparency: number?,                                                -- 模态遮罩透明度 (默认 0.5)
    openAnimation: string?,                                                    -- 打开动画 ("Scale" 或 "None")
    newWindow: (frame: Frame, windowId: string, uiActions: UIActions, ...any) -> WindowBase, -- 工厂函数
}
```

### 2. 打开窗口生命周期 (`OpenWindow`)
当调用 `UIManager.OpenWindow(windowId, ...)` 时，执行严格的生命周期链路：
1. **防重入检查**：若该 `windowId` 已处于打开状态，直接返回或提示，严禁重复生成实例。
2. **模板克隆**：从 `ReplicatedStorage.UI` 克隆对应的 `Frame` 预制体，挂载至 `GameScreenGui`。
3. **实例化对象**：调用注册的 `newWindow` 工厂函数创建 `WindowBase` 派生实例。
4. **动态层级计算 (Dynamic ZIndex)**：
   ```luau
   -- 按当前活动窗口计数自动递增 ZIndex，确保后打开的窗口覆盖在前一个窗口上方
   local windowCount = #activeWindows
   frame.ZIndex = 100 + windowCount * 2
   ```
5. **初始化钩子**：调用 `window:OnInit()`，触发子类自定义数据加载与开启动画。
6. **遮罩层级自适应**：调用 `CheckModalButtonVisible()`，将全局遮罩移至当前顶层模态窗口的下一层（`topModalWindow.ZIndex - 1`）。
7. **客户端事件广播**：触发 `ClientMsg.FireOpenWindow(windowId)`，通知外部系统（如隐藏部分主 HUD）。

### 3. 关闭窗口生命周期 (`CloseWindow`)
当调用 `UIManager.CloseWindow(windowId)` 时：
1. 从活动窗口字典中注销该窗口。
2. 调用 `window:OnClose()`，执行销毁前清理并销毁 `frame`。
3. 重新计算模态遮罩显示与透明度；若已无模态窗口，则隐藏 `ModalButton`。
4. 触发 `ClientMsg.FireCloseWindow(windowId)`，恢复主界面关联状态。

---

## 三、模态交互遮罩 (Modal Backdrop) 规范

1. **单一全局实例**：
   - 客户端全局只维护一个 `ModalButton`（`ImageButton`，尺寸 `100% × 100%`）。
   - 避免每个弹窗各自创建全屏遮罩导致的性能浪费与多次叠黑。
2. **层级与透明度动态换算**：
   - 遍历所有活动窗口，找出处于可见状态的模态窗口中 `ZIndex` 最高者。
   - `ModalButton.ZIndex = topModalWindow.ZIndex - 1`。
   - `ModalButton.BackgroundTransparency` 计算所有叠加模态窗口的透明度乘积。
3. **输入拦截**：
   - `ModalButton.AutoButtonColor = false`。
   - 点击遮罩可触发最顶层窗口的通用取消/关闭，或纯粹拦截鼠标向底层 3D 世界及主 HUD 的误触穿透。

---

## 四、声明式按钮交互动效系统 (Micro-Interactions)

为了让游戏全界面的按钮具备细腻的触感，框架采用声明式 Attribute 驱动，杜绝在每个界面脚本中重复写 MouseEnter/MouseButton1Down：

### 1. 动效参数规范
- **默认参数**：
  - 移入放大比例：`1.10`（+10%）。
  - 按下缩小比例：`0.80`（-20%）。
  - 缓动时间：`0.10s`，Quad 缓动。
- **结构契约**：
  - 目标按钮（`GuiButton`）上设置 Attribute `HasInteractionEffect = true`。
  - 目标按钮**必须挂载直接子节点 `UIScale`**。

### 2. 动效状态机与设备环境处理
- **桌面键鼠环境**：
  - `MouseEnter`：Tween 放大至 1.1x。
  - `MouseLeave`：Tween 恢复至 1.0x。
  - `Activated`：Tween 缩小至 0.8x，完成后自动弹回 1.0x。
- **触控移动端环境**：
  - 忽略 `MouseEnter` / `MouseLeave`（触屏无 Hover 概念，防止手指滑动时残留放大状态）。
  - 点击按下时执行缩放回弹动画，确保触控点按反馈明确。
- **自动注册闭环**：
  - `UIManager` 监听 `gameScreenGui` 与 `workspace` 的 `DescendantAdded`。
  - 任何新克隆生成的按钮，只要带 `HasInteractionEffect` 标记且包含 `UIScale`，自动纳入交互体系，销毁时自动通过弱引用/Destroying 解除监听。

---

## 五、WindowBase 与弹窗开启动画

### 1. Scale 弹性弹窗动画
打开弹窗时，利用 `Enum.EasingStyle.Back` 与 `Enum.EasingDirection.Out`（耗时 `0.25s`）实现灵动的微弹动效：
1. 初始将窗口直接子节点 `UIScale.Scale` 设为 `0`。
2. 启动 Tween，将 `UIScale.Scale` 从 `0` 缓动过渡至设计初始缩放（如 `1.0`）。
3. 动画完成，窗口进入稳定响应状态。

---

## 六、代码实现反模式警示

> [!CAUTION]
> 1. **严禁在 Update 循环或帧轮询中调用 OpenWindow/CloseWindow**。
> 2. **严禁在代码中直接 `Instance.new("Frame")` 拼装窗口内容**。
> 3. **严禁直接在业务层修改全局 `ModalButton` 的父级或属性**。
> 4. **严禁在窗口关闭时不清理事件监听**，必须遵循 `WindowBase.OnClose()` 与 `GuiWrapperBase.OnDestroy()` 契约。
