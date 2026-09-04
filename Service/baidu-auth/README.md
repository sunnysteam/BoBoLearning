# 百度网盘授权目录

此目录只存放运行时生成的百度 OAuth 令牌。`token.json` 已被忽略，禁止提交到 Git、镜像或日志。

在 Service 目录运行 `cargo run -- --authorize-baidu`，按中文提示完成设备码授权后会自动生成令牌文件。
