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

最终方案使用独立 Swift 后台助手，不修改 Codex.app，也不启动桌面透明窗口。助手监听前台应用：只有 `com.openai.codex` 聚焦时，才用系统级 Touch Bar 显示雷姆图标、5 小时剩余和每周剩余；切换到其他应用后自动收回，让其他应用恢复自己的 Touch Bar。

两个额度框都使用剩余百分比作为填充宽度：例如剩余 30%，彩色填充只占框宽度的 30%，文字保持居中。周额度还会显示窗口重置前的剩余天数（不足一天时显示小时数）。

安装并设置登录后自动运行：

```bash
./scripts/install-codex-touchbar-helper.sh
```

它通过 macOS 的 `presentSystemModalTouchBar` 和 `DFRFoundation` 实现系统级展示。这是目前能压过输入框“打字建议栏”的方式，但属于 macOS 私有 API，系统升级后可能需要适配。额度仍通过本机 Codex CLI 的只读 `app-server` 获取，不读取 Cookies、钥匙串或登录令牌。

额度缓存文件位于：

`~/Library/Application Support/CodexUsageWidget/usage.json`

日志位于：

`~/Library/Logs/codex-usage-touchbar.log`

如需停用自动助手：

```bash
launchctl bootout "gui/$(id -u)/com.chitongx.codex-usage-touchbar"
rm "$HOME/Library/LaunchAgents/com.chitongx.codex-usage-touchbar.plist"
```

## 自定义动漫角色

默认显示内置雷姆，也可以用透明 PNG 替换角色，不需要修改 Codex.app：

```bash
./scripts/set-character.sh "/绝对路径/你的角色.png"
```

图片会复制到 `~/.config/codex-touchbar/character.png`，仅保存在本机；重启助手或切换回 Codex 后生效。恢复内置雷姆：

```bash
./scripts/set-character.sh --reset
```

完整图片要求和重新安装步骤见 [`docs/CUSTOM_CHARACTER.md`](docs/CUSTOM_CHARACTER.md)。

如果想把模型名、会话名、刷新时间或其他设置放到 Touch Bar，上层扩展点和示例见 [`docs/TOUCHBAR_CUSTOMIZATION.md`](docs/TOUCHBAR_CUSTOMIZATION.md)。Pro 账户若没有 5 小时窗口，程序会保留该位置并明确显示“Pro 无5小时限制”，不会因此导致周额度读取失败。

旧版 Electron 注入脚本 `scripts/install-codex-touchbar.sh` 仅作为历史实验保留，不应再运行；如之前安装过它，先运行 `scripts/restore-codex-original.sh` 恢复 Codex 原始包。

## GitHub

已创建私有远程仓库：

<https://github.com/chitongx/codex-pet-usage-rollback>

远程仓库保存说明、版本信息、校验文件和恢复脚本；大型 `app.asar` 被 `.gitignore` 排除，仍需保留本机项目目录中的备份文件。
