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

## Codex 聚焦时的 Touch Bar 用量显示

这个版本会把一个最小 Electron Touch Bar 模块安装进 Codex 的 `app.asar`，因此 Codex 聚焦时显示雷姆图标、5 小时剩余和每周剩余；切换到其他应用后，Touch Bar 会由其他前台应用接管。额度读取仍通过本机 Codex CLI 的只读 `app-server` 完成，不读取 Cookies、钥匙串或登录令牌。

安装前先做 dry-run：

```bash
./scripts/install-codex-touchbar.sh --dry-run
```

确认无误并完全退出 Codex 后安装：

```bash
./scripts/install-codex-touchbar.sh --install
```

安装脚本只接受与本项目备份哈希一致的 Codex 版本，避免误改未知更新。Codex 更新后可能覆盖修改，需要重新 dry-run/安装。

额度缓存文件位于：

`~/Library/Application Support/CodexUsageWidget/usage.json`

双击下面的文件即可启动：

`scripts/run-codex-usage-widget.command`

也可以在终端运行：

```bash
./scripts/run-codex-usage-widget.command
```

安装后 Codex 每个新建窗口都会获得 Touch Bar，约每分钟自动刷新。实现使用 Electron 官方 `BrowserWindow.setTouchBar()`；Touch Bar API 本身是实验性 API。

恢复原版：

```bash
./scripts/restore-codex-original.sh
```

恢复脚本会校验原始 `app.asar` 后替换它。独立 Swift 悬浮窗脚本仍保留在项目中，但不再是默认方案。

## GitHub

已创建私有远程仓库：

<https://github.com/chitongx/codex-pet-usage-rollback>

远程仓库保存说明、版本信息、校验文件和恢复脚本；大型 `app.asar` 被 `.gitignore` 排除，仍需保留本机项目目录中的备份文件。
