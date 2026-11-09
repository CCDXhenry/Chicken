# 接口与坐标

## 数据契约

`Area = { Name: string, Rect: Rect, Valid: boolean }`。查询结果为屏幕像素矩形的快照；不可将其直接当作设计画布坐标。

`Bind({ Root, GetScale?, FindControls?, ReadSnapshot?, Observe? })` 返回控制器：

- `GetReservedRects()`：全部已声明禁放区，含无效区域。
- `GetRegion(name)`：按名称查询禁放区或可用区，不存在时 nil。
- `IntersectsReserved(screenRect)`：与任一有效禁放区相交。
- `Changed:Connect(callback)`：矩形、有效性、根坐标或缩放变化后通知；返回 Disconnect 句柄。
- `Refresh()`、`SetDebugVisible(enabled)`、`Destroy()`：显式刷新、调试开关和幂等清理。

`ReadSnapshot` 支持无玩家的几何测试或项目自定义环境；配套 Observe 接收刷新调度函数，返回取消订阅函数。默认服务观察只在未传 ReadSnapshot 时建立。GetScale 返回一个布局单位对应多少屏幕像素；默认读取根 AbsoluteSize.X / Size.X.Offset，非 Offset 根必须显式提供。

## 坐标

GuiService:GetInsetArea 的矩形以 CoreUISafeInsets 为基准。先读 None，令 shift = -None.Min；所有引擎 inset 矩形和 GuiObject.AbsolutePosition 加 shift 后才进入统一屏幕坐标。完整视口使用 None 的矩形大小，不假定 Camera.ViewportSize 包含硬件边界。

根屏幕原点为 Root.AbsolutePosition + shift。局部矩形 = (屏幕矩形 - 根屏幕原点) / scale。预置区域组原点必须为根局部零点，不能再叠加 UIScale。

TopbarSafeInsets 是顶栏中空闲的矩形。设备可用区与它之间的左右差集声明为顶部禁放区；不能把 TopbarInset.Max.Y 当成整条禁放高度。

## 区域语义

- DeviceTop/Bottom/Left/RightFrame：设备边界。
- TopLeftCoreFrame、TopRightCoreFrame：顶部空闲矩形左右的系统占用范围。
- MovementInputFrame、JumpButtonFrame：当前可见原生手势区和按钮；不存在时 Valid=false。动态摇杆使用整个手势响应容器。
- DeviceContentFrame：硬件安全矩形，仍可能包含系统控件。
- TopCenterFrame：顶栏空闲矩形。
- BodyFrame：顶栏下方主体，仍需避开触控区。
- LeftInfoFrame：设备左边、顶栏下方至移动区上沿的候选信息区。
- BottomCenterFrame：移动区右边至跳跃区左边的中央候选区。
- RightActionsFrame：移动区右侧、顶栏下方、跳跃区上方的操作容器；没有原生控件时自然扩展到设备边界。两端使用同一规则。

多个可用区可以重叠。项目需检查完整内容与禁放区的相交，并处理自身控件之间的冲突。默认原生控件查找范围为 PlayerGui.TouchGui.TouchControlFrame；自定义查找器应配合 Observe 监听自身结构、几何和祖先显隐。实际支持的移动容器为 DynamicThumbstickFrame、ThumbstickFrame、DPadFrame。

系统菜单、购买框、展开聊天等临时覆盖层由项目按自身交互策略处理，不声明为常驻矩形。

## 工具与验证

BuildRegionFrames 返回 Build(root)，由 Edit 一次性执行环境调用，不能安装为运行时依赖。构建前调用方确认 Edit 模式与目标模板；技能资产不硬编码场景身份。模板缺失应在 Edit 修复，不在运行时补建。

官方依据：[GuiService](https://create.roblox.com/docs/reference/engine/classes/GuiService)、[ScreenInsets](https://create.roblox.com/docs/reference/engine/enums/ScreenInsets)。引擎 API 变化时重新核对官方文档与当前环境。

## 共用缩放约束

PC 排版为唯一设计基准，统一根 UIScale 负责整棵 UI 的等比缩放。区域边界的变化只改变共用容器的锚定空间，不切换子树设计、不单独放大触屏按钮、不在手机启用紧凑或纵向卡片。鼠标和触屏操作在同一槽位切换交互表现，几何一致。
