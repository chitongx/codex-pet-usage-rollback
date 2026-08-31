# Codex 宠物用量菜单回退项目

这个独立项目用于保存 Codex 自带桌面宠物改动前后的版本信息，并提供可验证的恢复脚本。

## 当前备份

- 原始应用：`/Applications/ChatGPT.app`
- 原始包：`backups/original-2026-08-31/app.asar`
- 备份版本：见 `backups/original-2026-08-31/app-version.txt`
- 校验文件：`backups/original-2026-08-31/app.asar.sha256`

`app.asar` 已被 `.gitignore` 排除，不会进入 Git；它保留在本机项目目录中，用于恢复当前 Codex 安装包。

## 恢复原始版本

关闭 Codex 后执行：

```bash
./scripts/restore-codex-original.sh
```

脚本会先验证备份校验和，再替换 Codex 的 `app.asar`，并保留当前包为带时间戳的 `.before-restore` 文件。

## 独立用量悬浮窗口

窗口脚本不修改 Codex，也不读取 Cookies、钥匙串或登录令牌。它只保存你从官方 Usage 页面确认后输入的两个“剩余百分比”，文件位于：

`~/Library/Application Support/CodexUsageWidget/usage.json`

双击下面的文件即可启动：

`scripts/run-codex-usage-widget.command`

也可以在终端运行：

```bash
./scripts/run-codex-usage-widget.command
```

窗口会保持在最前面并可拖动。点击“打开官方用量页”，按官方页面确认 5 小时和 1 周剩余额度后填入并保存。由于 OpenAI 没有提供可供此类独立小工具稳定调用的公开桌面额度 API，这个版本采用手动确认方式，不会因私有接口或登录状态变化而影响 Codex。

## GitHub

已创建私有远程仓库：

<https://github.com/chitongx/codex-pet-usage-rollback>

远程仓库保存说明、版本信息、校验文件和恢复脚本；大型 `app.asar` 被 `.gitignore` 排除，仍需保留本机项目目录中的备份文件。
