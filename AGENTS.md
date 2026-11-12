# Chicken 开发入口

处理本项目的代码、配置、UI、资源与 Studio 工作前：
1. 项目级核心规范与工程约定读取 [chicken-project](.agents/skills/chicken-project/SKILL.md)。
2. 通用 Roblox/Luau 规范读取 [.agents/skills/roblox-game-dev](.agents/skills/roblox-game-dev/SKILL.md) 及当前任务需要的 reference。
3. 涉及 UI 设计、Studio 模板制作、GUI 框架开发、屏幕安全区/触控禁放区、文本二分拟合或 3D 标牌自适应时，读取通用的 [.agents/skills/roblox-ui-system](.agents/skills/roblox-ui-system/SKILL.md)。
4. 当用户明确提出需要创建优质实例（3D 道具/模型、专业 UI 界面、精细 VFX 特效）时，读取 [.agents/skills/quality-instance-workflow](.agents/skills/quality-instance-workflow/SKILL.md)。
5. 涉及游戏音效与背景音乐生成、物理声学合成、Roblox Open Cloud 批量自动上云、Studio 实例挂载（ReplicatedStorage.Sounds）或运行时对象池架构时，读取 [.agents/skills/roblox-audio-workflow](.agents/skills/roblox-audio-workflow/SKILL.md)。
6. 实机验证需要 MCP 之外的截图、录屏或 OBS 捕获准确性检查时，读取 [.agents/skills/roblox-obs-capture](.agents/skills/roblox-obs-capture/SKILL.md)。

项目规则维护在 `chicken-project`；不要将 Chicken 专属约定写入公共 `roblox-game-dev`。
脚本只编辑本地文件，沿用已建立的 Script Sync，不通过 MCP 覆写 Studio 源码。
