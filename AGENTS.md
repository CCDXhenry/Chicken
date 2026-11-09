# Chicken 开发入口

处理本项目的代码、配置、UI、资源与 Studio 工作前：
1. 通用 Roblox/Luau 规范读取 [.agents/skills/roblox-game-dev](.agents/skills/roblox-game-dev/SKILL.md) 及当前任务需要的 reference。
2. 涉及屏幕系统占用区、设备安全边界或原生触控布局时，读取项目内 [.agents/skills/roblox-ui-regions](.agents/skills/roblox-ui-regions/SKILL.md)。
3. 当用户明确提出需要创建优质实例（3D 道具/模型、专业 UI 界面、精细 VFX 特效）时，读取 [.agents/skills/quality-instance-workflow](.agents/skills/quality-instance-workflow/SKILL.md)。

脚本只编辑本地文件，沿用已建立的 Script Sync，不通过 MCP 覆写 Studio 源码。
