---
name: roblox-obs-capture
description: 在 Chicken 项目中通过 OBS 校准并采集 Windows Roblox Studio Play 游戏视口，核验截图边界与录像连续性。实机验证需要 MCP 之外的截图、录屏，或排查 OBS 抓错窗口、裁切偏移、黑屏与冻结时使用；普通 MCP 截图无需调用。
---

# Roblox OBS 准确采集

用于 Chicken 项目在 Windows 上通过 OBS 获取 Studio Play 客户端视口的截图和录像。采集走本地 WebSocket，不依赖 Studio MCP；实例、日志和运行状态检查继续使用已有 Studio 工具。普通 MCP 截图无需改走 OBS。

## 工具与前提

- 复用仓库 `Tools/Studio/obs_media_tool.py`、`obs_controller.py`、`obs_studio_bridge.py` 和 `obs_verify_video.py`，不要临时另写一套截屏或自动绑定脚本。
- 确认当前任务已授权 Play 验证再启动 Play；配置 OBS 或调用本 skill 本身不构成启动游戏的授权。不修改游戏源码来实现捕获。
- OBS 已启动并开启本地 WebSocket 服务，默认 `127.0.0.1:4455`。需要认证时使用环境变量 `OBS_WEBSOCKET_PASSWORD`，不打印、提交密码或为方便连接关闭认证。
- Python 依赖声明在 `Tools/Studio/requirements-obs.txt`；视频文件核验需要 PATH 中的 `ffmpeg`、`ffprobe`。先检查现有环境，缺失时才安装所需依赖。
- 保持唯一目标项目窗口、选中 Play 的“客户端 / Client”文档标签，采用固定窗口与面板布局。窗口不要最小化；被其他窗口遮挡时是否仍更新，应在当前机器验证。

## 校准与采集

以下命令在项目根目录运行。默认场景 `Chicken_Studio_Viewport`，原始窗口来源 `Chicken_Studio_Window`。

```powershell
python Tools/Studio/obs_media_tool.py calibrate
```

工具通过只读 Win32 / UI Automation 识别 `QEngineWidget`，按实际物理像素裁剪客户区、设置 1:1 画布与输出及 60 FPS。不要根据桌面截图的逻辑坐标手填裁剪值，也不要套用历史分辨率。当前编码器要求偶数宽高；遇到奇数尺寸需调整布局再校准，不能裁掉一行或一列凑数。

校准只产生 `pending_review` 状态。打开 `.cache/obs-viewport/acceptance/window-reference.png` 与 `viewport.png`，对照四角、四边和边缘 HUD；完整保留游戏自身菜单、提示和背包，排除 Studio 工具栏、面板及窗口边框。完成视觉复核后才执行 `approve`，无需为已授权的视觉验收另向用户重复请求确认。

```powershell
python Tools/Studio/obs_media_tool.py approve
python Tools/Studio/obs_media_tool.py check
python Tools/Studio/obs_media_tool.py screenshot --save .cache/obs-viewport/example.png
python Tools/Studio/obs_media_tool.py record start --duration 15 --expect-motion
```

仅在测试安排了持续运动时加 `--expect-motion`，静止场景应省略。录像命令在前台持续守卫并自动停止，最长 300 秒；Python 调用方在完成 Play 校准后使用 `RobloxRecordSession` 上下文。不要使用旧版跨进程 `record start/stop` 调用，也不要直接点击 OBS 录制按钮或用热键绕过守卫。

## 失效与验收

- 截图取最终合成场景，必须与录像构图一致，保留原始尺寸。不要用原始窗口源截图代替裁剪后的成果。
- 每次采集检查窗口身份、DPI、客户区、原生视口边界和 OBS 来源、场景、变换及输出设置。窗口重启、位置或尺寸变化、面板影响视口、切换文档/服务器视图、停止 Play 或 OBS 配置变化时，按检查结果重新校准。
- `invalid` 是持久失效状态，恢复旧布局也不能自动放行。遇到黑屏、目标丢失、边界变化或疑似冻结，保留失败原因并停止本轮取证；不能忽略错误、自动重绑其他窗口或自动降级 MCP 后仍声明 OBS 验收通过。
- 文件存在、接口成功和能播放均不足以证明准确。录像结束后运行下面的核验命令，检查实际尺寸、60 FPS、完整解码和首中尾关键帧；有运动要求时还须确认画面更新。核对录像边车 JSON 中渲染/编码丢帧差值，任一大于零不通过连续性验收。

```powershell
python Tools/Studio/obs_verify_video.py "录像返回的绝对路径.mp4"
```

- 文件核验通过后的 `pending_visual_review` 仍须逐一查看首、中、尾关键帧，确认边界、HUD 和预期画面。只有机器检查和视觉核验均通过，才将结果标为验收通过。
- 守卫采用采样而非逐帧监控，实际检查间隔受机器负载影响。不要承诺识别两次检查间变化又恢复的瞬态布局，也不要承诺单张截图与某个渲染帧严格同步；单帧闪烁和短暂特效应提前连续录制再抽帧。

## 交付与维护

- 校准、备份及采集产物默认位于 `.cache/obs-viewport/`，属于本机状态，不提交 Git；报告保留有效时段和采集时校准信息，不把句柄、尺寸或本次成功结果当作下次仍有效的依据。
- 交付专用场景名称、有效截图和录像路径、实际验证结果及限制；结束时停止自己启动的录制。若结束了自己启动的 Play，说明下一次 Play 需要重新校准，不要将失效状态伪装为“就绪”。
- 修改采集工具后执行 `python -m unittest discover -s Tools/Studio -p test_obs_integration.py -v`。默认回归不启动 Play；实机用例需先完成 Play 校准与复核，再显式设置 `OBS_LIVE_TESTS=1`。区分离线回归、实际录像检查和未执行场景。
- 仅维护 skill、文档或本地 Python 采集工具时，无需 Script Sync / Package 同步；不据此提交、推送或发布项目。
