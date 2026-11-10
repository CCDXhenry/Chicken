# 多语言本地化防污染、图标管线与资源生命周期规范

本规范为多语言翻译集成、图标纹理资产管理与客户端内存生命周期提供工业级开发准则。

---

## 一、多语言本地化防污染规范 (Localization Protocol)

Roblox 自带的云端自动本地化翻译爬虫会在运行时扫描游戏界面中的文本。如果处理不当，会将动态数字、玩家昵称或特殊字符误抓为翻译词条，造成巨额多语言翻译垃圾污染。

### 1. 文案三分类处理准则
| 文本分类 | `AutoLocalize` 属性 | 来源与维护方式 | 规则与禁忌 |
| :--- | :--- | :--- | :--- |
| **纯英文静态文案**<br>(如 "SETTINGS", "PLAY") | **`true`** | 直接在 Studio Edit 模板中填入纯英文 | 引擎自动根据玩家语言翻译。无需在业务代码中启动重新赋值，不重复收录进业务配置表。 |
| **动态参数化文案**<br>(如 "剩余: {1} 秒", "队伍: {1}") | **`false`** | 业务多语言表 (`GameTexts`) 维护 Key，代码调用绑定接口 | 必须显式关闭 `AutoLocalize`。通过 `TranslationTool` 绑定 Key 与参数（如 `{ "10" }`），带参数文案使用唯一 Key。 |
| **纯数字、时间、玩家名、UI 符号**<br>(如 "999", "03:45", "Player1", "▼", "●") | **`false`** | 运行时数据动态赋值 | **强制设置 `AutoLocalize = false`**。<br>⚠️ 严禁让翻译器抓取，严禁将图标字符与需翻译的句子拼接在同一 Label 中。 |

### 2. 业务绑定标准接口
- 文本标签绑定：`TranslationTool.CustomAutoLocalizeTextLabel(label, key, params)`
- 按钮文字绑定：`TranslationTool.CustomAutoLocalizeTextButton(button, key, params)`
- 交互提示绑定：`TranslationTool.CustomAutoLocalizeProximityPrompt(prompt, key, params)`

---

## 二、图标与视觉资产管线 (Asset Pipeline)

1. **严禁写死本地绝对路径**：
   - 所有图片、纹理的 `Image` 属性必须使用合法的 `rbxassetid://<AssetId>` 或精选官方图标。
2. **通用图标获取**：
   - 优先复用项目中已验证的精选图标集或官方矢量符号库。
3. **原创/游戏专属道具图标制作流程**：
   - 3D 道具在 Blender 中设置好正面或 45 度透视；
   - 通过 Blender Headless 渲染透明背景的正方形 PNG（如 512×512）；
   - 使用 Open Cloud API 上传为云端 Decal，获得合法的 `rbxassetid://` 填入模板。
4. **ScaleType 适配契约**：
   - **普通拉伸背景**：`ScaleType = Enum.ScaleType.Stretch`。
   - **九宫格切片底板**：`ScaleType = Enum.ScaleType.Slice`，并精确配置 `SliceCenter`。
   - **道具/技能/货币图标**：`ScaleType = Enum.ScaleType.Fit`，确保图片长宽比不被暴力拉伸变形。

---

## 三、资源预载与 GPU 渲染预热

### 1. 区分资源下载预载与渲染预热
- **资源下载预载 (PreloadAsync)**：
  - 仅代表图片、网格或音效的二进制数据已下载至本地客户端内存，**并不代表 GPU 已完成着色器编译与纹理管线绑定**。
- **渲染预热 (Warmup)**：
  - 对首屏高频展示的复杂 3D 模型、特效粒子或重度 UI 模板，在进入玩法前放置在屏幕外（或短暂开启透明绘制一帧），完成 GPU 着色器预编译，杜绝玩家首次打开界面时的微卡顿（Stutter）。

### 2. 动画轨道 (AnimationTrack) 高频复用
- **反模式**：每次播放按钮动效或角色动作时，现场调用 `Humanoid:LoadAnimation()`，播放完立即 `Destroy()`。这会频繁分配底层 C++ 对象并引起内存碎片化。
- **规范**：
  - 在初始化时预先 `LoadAnimation` 并缓存复用 `AnimationTrack`；
  - 状态切换时仅调用 `track:Play()` 与 `track:Stop()`；
  - 仅在界面彻底销毁或角色重构时，统一注销并销毁 Track。

### 3. 生命周期清理终极清单
在 UI 销毁（`OnClose` / `OnDestroy`）时，必须执行完整的清理闭环：
- [ ] 断开所有非 `gui.AncestryChanged` 的外部全局事件监听（如 `RunService`、网络通信、数据变化信号）；
- [ ] 停止所有正在运行的 `Tween` 补间；
- [ ] 从 `UIAdapter` 或系统区域观察者中注销挂载引用；
- [ ] 归还克隆的列表项至对象池，或直接销毁临时实例；
- [ ] 清理闭包中的强引用 table，防止引起内存泄漏。
