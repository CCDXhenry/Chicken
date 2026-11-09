# AB 测试规范

- AB 开关放入 `GameConfig.PlayerConfigInfo`，仅作为运行期数据，经 `ServerGameInfo.InitPlayerInfo` 下发到客户端；不得写入玩家存档。
- 服务端通过 `ConfigService` 安全读取：新玩家用 `GetConfigForPlayerAsync(player)` 分组，老玩家用 `GetConfigAsync()` 读取默认值；失败或缺失时回退为 `false` 并记录告警。
- 客户端只读取 `localPlayerInfo.playerConfigInfo`，不得自行调用远程配置；AB 关闭时隐藏功能或入口。
