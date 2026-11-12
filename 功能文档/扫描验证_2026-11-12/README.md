# 2026-11-12 扫描证据

审查 HEAD：`a26e482f6cbf2f8f2d3bb0048be619f5876a7444`；基线：`549cab706c799bb1953d305bfcaaff33841e99fc`。

完整临时快照已移除。`sources/` 保留报告引用的三个原始 Git 文件，`source-sha256.json` 为内容哈希；`changes.patch` 为 Scripts/Tools 净差异。

重新验证时，在新的临时目录通过 `git archive <固定 SHA>` 解包，保留 `.luaurc`、Scripts、Tools、JsonData、Assets 等原始目录。所有命令从快照根执行：

```powershell
lune run Tools/Tests/CameraSpawnRegression.luau
lune run Tools/Tests/ConfigOptimizationRegression.luau
lune run Tools/Tests/FarmBusinessRegression.luau
lune run Tools/Tests/FarmContractRegression.luau
lune run Tools/Tests/FarmHatchRegression.luau
lune run Tools/Tests/FarmProgressRegression.luau
lune run Tools/Tests/WeaponToolRegression.luau
pwsh -NoProfile -File Tools/check-strict.ps1 -All
```

将本目录 `diagnostic.luau` 复制到 HEAD 快照根，再运行 `lune run diagnostic.luau`，可复现首阶物种请求错误及声音复用音量问题。前者提取原函数，后者加载整个声音模块；外部对象为受控替身，不能代表引擎集成验证。

`_scan_Run*.luau` 为 PowerShell 测试中 here-string 的原样提取内容，复制到 HEAD 快照根后用 Lune 运行；EggBillboard 入口本次超时，应设置进程超时再重试。其他四个内嵌入口结果见 `embedded-test-results.json`。

`direct-test-results.json` 区分直接测试通过和 Studio 环境缺失。初次批量执行中断，没有完整批次结果文件，不以批次状态替代这些独立结果。相机 PowerShell 包装器结果与相机 Luau 重复。

`strict-*-unique.txt` 按虚拟模块、位置、消息去重。`strict-new-unique.txt` 只是文本集合差异，不能直接作为新增缺陷数；原始日志保留重复信息及门禁输出。
