---
name: roblox-game-dev
description: Roblox 游戏开发项目规范，编辑游戏脚本、使用 Roblox MCP 时使用此技能。
---

# Roblox Game Dev Skill

以本 Skill 作为 Roblox 项目开发的**首选**规范。遇到规则冲突时：

1. **与仓库既有实现冲突**：以本项目既有代码与目录习惯为准，记录偏差，不强行统一风格。
2. **无既有先例时**：遵循本 Skill 与 `references/` 中的规则。
3. **Skill 未覆盖时**：遵循 Roblox / Luau 官方 API 与通用最佳实践。

## 使用流程

- 读取 [项目目录层级约定.md](references/项目目录层级约定.md)。
- 编辑游戏脚本时，读取 [编码规范.md](references/编码规范.md)。
- 涉及存档时，读取 [存档规范.md](references/存档规范.md)。
- 涉及游戏内文本显示，多语言本地化时，读取 [多语言本地化规范.md](references/多语言本地化规范.md)。
- 涉及资源管理时，读取 [资源管理规范.md](references/资源管理规范.md)。
- 涉及 AB 测试时，读取 [AB 测试规范.md](references/AB 测试规范.md)。
- 使用 MCP 在 Roblox Studio 内编辑 UI 时，读取 [UI 编辑规范.md](references/UI 编辑规范.md)。
- 使用 MCP 在 Roblox Studio 内创建模型时，读取 [模型创建规范.md](references/模型创建规范.md)。

## 自动测试规则
除非用户主动要求，否则无需启动 Play 模式测试。

## 文件引用规则

只从本 `SKILL.md` 直接引用一层 `references/` 文件。不要让 reference 文件继续指向更深层 reference，避免加载链过长。
