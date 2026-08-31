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

## 独立用量 Touch Bar companion

脚本不修改 Codex，也不读取 Cookies、钥匙串或登录令牌。它会通过本机 Codex CLI 的只读 `app-server` 请求自动读取两个额度窗口；如果当前 CLI 不可用，则回退到本地保存的数据。数据文件位于：

`~/Library/Application Support/CodexUsageWidget/usage.json`

双击下面的文件即可启动：

`scripts/run-codex-usage-widget.command`

也可以在终端运行：

```bash
./scripts/run-codex-usage-widget.command
```

启动后脚本会在 Touch Bar 中显示雷姆图标、`5小时 xx%` 和 `每周 xx%`，并大约每分钟自动刷新。菜单栏图标中可以手动刷新或激活 Touch Bar。自动方式使用 `codex -s read-only -a never app-server`，不接触私有 HTTP 额度接口，也不改变 Codex 的安装包、登录状态或运行参数。

这是独立 companion：它不会嵌入 Codex 宠物，也不会影响 Codex 正常使用。Apple 的 AppKit 规定 Touch Bar 显示当前前台应用提供的内容，因此切回 Codex 后，Touch Bar 会恢复 Codex 自己的控件；脚本不会抢夺 Codex 焦点。若要在 Codex 前台时持续显示，需要后续做 Codex 集成或使用 BetterTouchTool/MTMR 等全局 Touch Bar 工具。

## GitHub

已创建私有远程仓库：

<https://github.com/chitongx/codex-pet-usage-rollback>

远程仓库保存说明、版本信息、校验文件和恢复脚本；大型 `app.asar` 被 `.gitignore` 排除，仍需保留本机项目目录中的备份文件。
