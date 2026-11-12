# OBS 游戏视口准确采集

这套工具仅采集当前 Chicken 项目的 Studio Play 客户端视口。截图和录像使用同一个 `Chicken_Studio_Viewport` 场景，原始窗口来源为 `Chicken_Studio_Window`。采集不依赖 Studio MCP；Play 的启动、停止及测试操作可由已有工具完成。

## 每次测试的步骤

在项目根目录使用现有 Python 环境，首次安装依赖：

```powershell
python -m pip install -r Tools/Studio/requirements-obs.txt
```

启动 OBS 的本地 WebSocket 服务，端口为 4455。如果服务已启用密码认证，通过环境变量 `OBS_WEBSOCKET_PASSWORD` 提供密码。工具支持认证，不修改 OBS 的认证设置，也不将密码写入文件。录像核验另需 PATH 中已有的 `ffmpeg` 和 `ffprobe`。

1. 进入目标项目的 Play 模式，显示“客户端 / Client”标签，固定窗口和面板布局；保持窗口可见、不要最小化。
2. 运行校准命令。工具通过只读 Win32 与 UI Automation 找到 `QEngineWidget` 原生窗口，按物理像素设置裁剪和输出，处理 Windows DPI 缩放；不会自动改抓另一个 Studio 窗口。

```powershell
python Tools/Studio/obs_media_tool.py calibrate
```

3. 对照 `.cache/obs-viewport/acceptance/window-reference.png` 和 `viewport.png` 检查四边、四角及边缘 HUD，确认只有游戏视口，之后记录边界复核结果：

```powershell
python Tools/Studio/obs_media_tool.py approve
python Tools/Studio/obs_media_tool.py check
```

`approve` 是对人工或视觉检查结果的显式确认，不代表图像算法能自动证明边界正确。校准后尚未批准时，截图和录像均被拒绝。

4. 截图或录制。以下录像命令在前台持续守卫，到达指定时长自动停止；需要动画验证时使用 `--expect-motion`。

```powershell
python Tools/Studio/obs_media_tool.py screenshot --save .cache/obs-viewport/example.png
python Tools/Studio/obs_media_tool.py record start --duration 15 --expect-motion
python Tools/Studio/obs_verify_video.py "录像返回的绝对路径.mp4"
```

默认最长录制 300 秒。不要将录像开始命令强行结束；Python 调用方使用 `RobloxRecordSession` 上下文，并在 Play 校准之后进入上下文。控制器不会接管已经进行中的录像。旧版一次性 `record start` 后立即退出、再由独立进程 `record stop/pause` 的方式已移除，避免录像脱离守卫。可通过 Ctrl+C 结束当前 CLI 录制，`finally` 会停止并保存录像。

## 有效性与失效规则

- 校准记录保存在 `.cache/obs-viewport/calibration.json`，属于本机临时状态，不提交 Git。校准前的 OBS 视频、场景和来源信息备份也保存在此目录。
- 核对窗口句柄、进程、标题、DPI、客户区和原生视口矩形；检查输出场景、来源设置、裁剪、缩放、可见性、滤镜、源尺寸、画布尺寸及 60 FPS。
- 窗口重启、移动、改变尺寸、显示缩放变化、切换文档/服务器标签、面板影响视口、停止 Play 或改变 OBS 场景后，需要重新校准。检测失败会把校准持久标为 `invalid`，恢复原布局也不能自动重新通过。
- 当前编码器要求偶数宽高。奇数尺寸直接拒绝；请调整固定布局，不能自动裁掉一行或一列。
- 截图前后均校验布局，拒绝原始窗口源和缩放截图。黑屏或近乎纯色的图像按无效处理，因此全屏纯色加载过渡应等待结束后再采集。
- 录像期间有非守护线程持续核验，异常时停止本次录像并保留无效报告。采样采用“检查完成后等待 0.5 秒”，实际间隔受系统和 UI Automation 延迟影响；这不是逐帧监控，无法保证识别两次检查间发生又恢复的瞬态布局变化。
- `--expect-motion` 仅在已安排持续运动时使用：连续六次采样完全相同视为疑似冻结；静止场景不会因此被判为故障。守卫只判断是否持续捕获，不能判断游戏逻辑或相机控制本身是否正确。
- 录像边车报告保留采集时校准快照和 OBS 渲染/编码丢帧差值。任一类丢帧大于零即不通过连续性验收。工具连接或录像结束失败同样不能算通过。
- `obs_verify_video.py` 检查实际文件尺寸和帧率、完整解码，并导出首、中、尾关键帧；机器检查后为 `pending_visual_review`。视觉检查四边和连续性后才能作为验收成果。
- 默认 OBS 失败直接传播错误。`RobloxMediaBridge` 只有显式指定 `prefer_obs=False` 或自定义相机时使用原生 MCP，不能将降级截图冒充 OBS 视口成果。

## 本机验证结果（2026-11-12）

OBS 33.0.1 / WebSocket 5.7.6，Windows 显示缩放 175%。通过边界复核的客户区尺寸为 3840×2036，视口在客户区中的矩形为 `(6, 325, 2032, 1244)`，输出 2032×1244、60 FPS。

完成 10.75 秒录像，645 帧完整解码成功；渲染和编码丢帧均为 0，12 次守卫采样均有画面更新，首中尾关键帧已视觉复核。曾切换 OBS 到前台覆盖 Studio，预览仍能更新。初次验收录像因 4 帧渲染丢帧被正确拒绝，没有用文件存在替代验收。

随后窗口客户区变化触发 `client_size` 失效，截图请求被拒绝且没有生成目标文件。结束时恢复 Edit；原 Play 校准不能直接用于下一次运行。新的窗口布局必须重新校准。

本机证据保存在 `.cache/obs-viewport/acceptance/`，包括 `verified-viewport.png`、`verified-recording.mp4`、录像关键帧和验收报告。截图请求不保证与游戏某一渲染帧严格同步；单帧闪烁和短暂特效应提前录制后抽帧检查。

## 回归检查

```powershell
python -m unittest discover -s Tools/Studio -p test_obs_integration.py -v
```

默认执行失效拒绝、无降级、黑屏、输出前布局变化、录像所有权和异常传播回归。实机测试会启动录像，须在当前 Play 已校准并复核后显式设置 `OBS_LIVE_TESTS=1`。

本次仅修改本地 Python 工具与文档，没有修改游戏业务脚本或 Studio 持久实例，无需 Script Sync 或 Package 同步。
