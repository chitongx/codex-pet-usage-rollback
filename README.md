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

## GitHub

私有远程仓库：

<https://github.com/chitongx/codex-pet-usage-rollback>

远程仓库保存说明、版本信息、校验文件和恢复脚本；大型 `app.asar` 被 `.gitignore` 排除，仍需保留本机项目目录中的备份文件。
