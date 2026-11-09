# Excel 配表与 JSON 维护

通用表格文件命名、转换映射与 BAT 编码约定。

## 路径与规范

- 相对当前项目根目录使用 `ExcelData`、`JsonData`、`Tools/excel2json`。
- `JsonData` 是导出结果目录，不将 JSON 自动硬编码写入 Studio 运行时，沿用现有导入流程。

## 新增或修改配表

- 新表使用中文业务名 `.xlsx`，对应 JSON 使用英文 PascalCase Data 名。
- 每个输入表对应唯一输出映射；改名同步检查转换命令和消费代码，避免不同表覆盖同一输出。
- 遵循当前工具的三行表头、单元格 JSON 识别和 @ 排除前缀；默认新表使用数组导出，已有表的数组/字典形态按消费代码保持兼容。
- 在 BAT 中添加逐表命令，例如：

```bat
excel2json --excel ../../ExcelData/<中文业务名>.xlsx --json ../../JsonData/<EnglishName>Data.json --header 3 --cell_json --exclude_prefix @ --array
```

- 保持现有工具目录切换流程；Windows BAT 涉及中文时使用 GBK/CP936 且无 BOM，避免 UTF-8 BOM 破坏首行命令。路径含空格时正确加引号。
- 运行转换前核对输入存在、输出路径和命令参数；核对输出可解析、字段类型与调用方一致，不手改生成数据来替代源表修复。

## 交付

列出修改的 xlsx、字段/行变化、BAT 命令变化、xlsx→JSON 映射与实际转换结果。说明是否执行 Studio 导入；未执行就明确标记。
