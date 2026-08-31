# 🐱 Codex 宠物用量 & MacBook Touch Bar 用量项目

> Codex Desktop Pet Usage Display Experiment and Rollback Backup
> 
> Codex 桌面宠物改动前后的版本管理与恢复方案

[![GitHub stars](https://img.shields.io/github/stars/chitongx/codex-pet-usage-rollback?style=flat-square)](https://github.com/chitongx/codex-pet-usage-rollback/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/chitongx/codex-pet-usage-rollback?style=flat-square)](https://github.com/chitongx/codex-pet-usage-rollback/network)
[![GitHub issues](https://img.shields.io/github/issues/chitongx/codex-pet-usage-rollback?style=flat-square)](https://github.com/chitongx/codex-pet-usage-rollback/issues)
[![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](LICENSE)
[![Shell Script](https://img.shields.io/badge/Shell-100%25-blue?style=flat-square)](https://www.gnu.org/software/bash/)

## 📖 项目概述

这是一个关于 **Codex AI 助手**桌面宠物使用情况管理的备份项目。该项目为 Codex 应用的系统集成、使用统计显示和版本回滚提供完整的解决方案。

### 🎯 核心功能

- 🐱 **Codex 宠物功能** - Codex AI 助手的桌面宠物实现与管理
- 📊 **使用统计显示** - 实时展示 Codex 的使用频率和数据统计
- 🔄 **版本管理与回滚** - 完整的 app.asar 备份、校验和恢复机制
- ✅ **数据完整性验证** - SHA256 校验和确保备份文件的完整性
- 🛠️ **一键恢复脚本** - 快速恢复原始版本，保留修改记录

## 🚀 快速开始

### 前置要求

- macOS 系统（Codex 应用）
- Bash 3.2 或更高版本
- 标准 Unix 工具集（sha256sum、cp、mv 等）

### 安装

```bash
git clone https://github.com/chitongx/codex-pet-usage-rollback.git
cd codex-pet-usage-rollback
chmod +x scripts/*.sh
```

### 📁 项目文件结构

```
.
├── README.md                              # 项目文档
├── scripts/
│   └── restore-codex-original.sh         # 版本恢复脚本
├── backups/
│   └── original-2026-08-31/
│       ├── app.asar                       # 原始应用包（Git 忽略）
│       ├── app.asar.sha256               # 校验文件
│       └── app-version.txt               # 版本信息
└── .gitignore                             # Git 忽略配置
```

## 🔧 使用方法

### 恢复原始版本

关闭 Codex 应用后，执行恢复脚本：

```bash
./scripts/restore-codex-original.sh
```

**脚本工作流程：**
1. ✓ 验证备份文件的 SHA256 校验和
2. ✓ 备份当前版本为 `.before-restore` 文件
3. ✓ 恢复原始 `app.asar`
4. ✓ 输出操作日志和时间戳

### 备份说明

- **原始应用路径**：`/Applications/ChatGPT.app`
- **备份位置**：`backups/original-2026-08-31/app.asar`
- **版本信息**：见 `backups/original-2026-08-31/app-version.txt`
- **校验文件**：`backups/original-2026-08-31/app.asar.sha256`

> ⚠️ 注意：`app.asar` 已在 `.gitignore` 中，不会被推送到 Git 仓库，需本机保留备份文件用于恢复。

## 💡 应用场景

- 📱 **Codex 桌面应用**集成与管理
- 🤖 **AI 助手**的使用统计和性能监控
- 💾 **系统数据**备份、校验与恢复
- 🔬 **功能实验**前后版本对比
- 🛡️ **应用安全**性和完整性验证

## 📊 Codex 集成信息

- **应用名称**：Codex / ChatGPT Desktop
- **语言**：Shell Script
- **集成功能**：使用统计、桌面宠物、Touch Bar 支持
- **备份方案**：完整的 asar 包备份和恢复机制

## 🤝 贡献指南

欢迎提交以下内容：
- 🐛 Bug 报告和问题反馈
- 📝 文档改进和本地化
- 🚀 新的恢复策略和脚本优化
- 💬 讨论和建议

## 📄 许可证

该项目采用 **MIT 许可证**。详见 [LICENSE](LICENSE) 文件。

## 👨‍💻 作者

[@chitongx](https://github.com/chitongx)

---

## 🔗 相关链接

- [Codex 官方网站](https://codex.com)
- [GitHub 仓库](https://github.com/chitongx/codex-pet-usage-rollback)
- [问题反馈](https://github.com/chitongx/codex-pet-usage-rollback/issues)

---

**标签**：#codex #ai-assistant #desktop-pet #usage-tracking #backup-restore #shell-script #macos #version-management

**最后更新**：2026-08-31
