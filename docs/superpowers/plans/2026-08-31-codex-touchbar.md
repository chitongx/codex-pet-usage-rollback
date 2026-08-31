# Codex Touch Bar 用量显示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将当前独立额度脚本改成原生 macOS Touch Bar companion，在支持 Touch Bar 的 MacBook Pro 上显示雷姆图标、5 小时剩余和 1 周剩余。

**Architecture:** 使用 AppKit 的 `NSTouchBar`/`NSCustomTouchBarItem` 创建独立 accessory app，并复用现有安全的 Codex CLI `app-server` 读取逻辑。Touch Bar 由当前前台应用提供，因此这个版本只在 companion app 获得前台焦点时显示；不修改 Codex.app，不注入 Codex，也不读取 Token/Cookie/钥匙串。没有 Touch Bar 或 companion 不在前台时，程序只保留菜单栏状态和可选的本地数据回退。

**Tech Stack:** Swift script, AppKit, NSTouchBar, NSCustomTouchBarItem, Codex CLI JSON-RPC app-server, shell contract tests。

---

### Task 1: 锁定 Touch Bar 前台应用边界与脚本入口

**Files:**
- Modify: `README.md`
- Modify: `Tests/test-widget-script.sh`

- [x] **Step 1: Write the failing contract checks**

Add checks for `NSTouchBar`, `NSCustomTouchBarItem`, `codex -s read-only -a never app-server`, and the documented foreground-app limitation.

- [x] **Step 2: Run the contract test and confirm it fails**

Run `sh Tests/test-widget-script.sh`. Expected: FAIL because the existing script is still a floating `NSPanel`.

- [x] **Step 3: Update the documentation contract**

Document that the companion does not alter Codex and that native Touch Bar content is supplied by the frontmost app, so a global Codex-frontmost display requires a separate integration.

- [x] **Step 4: Run the contract test again**

Run `sh Tests/test-widget-script.sh`. Expected: PASS after the implementation in Task 2 lands.

- [x] **Step 5: Commit**

```bash
git add README.md Tests/test-widget-script.sh
git commit -m "Document Touch Bar companion boundary"
```

### Task 2: Replace the floating panel with an AppKit Touch Bar

**Files:**
- Modify: `scripts/codex-usage-widget.swift`
- Modify: `scripts/run-codex-usage-widget.command`

- [x] **Step 1: Keep the existing quota reader as the data source**

Retain the CLI app-server command and the local `usage.json` fallback. Do not add direct access to `~/.codex/auth.json`, cookies, keychain, or private HTTP endpoints.

- [x] **Step 2: Implement the native Touch Bar delegate**

Create an `NSTouchBar` with three items: a Rem image item, a compact 5-hour remaining label, and a compact weekly remaining label. Set high visibility priority and refresh item views on the same one-minute timer used by the current script.

- [x] **Step 3: Use an accessory status item host**

Use a hidden/minimal accessory window only to make the companion app a valid frontmost AppKit responder. Do not create an always-on-top floating quota panel. Add a menu-bar item with “刷新额度”, “显示 Touch Bar”, and “退出”.

- [x] **Step 4: Make the Touch Bar graceful on unsupported Macs**

If `NSTouchBar` is unavailable or no Touch Bar is present, show a menu-bar status and a clear message; do not fail the quota reader or alter Codex.

- [x] **Step 5: Keep the launcher simple**

Make the `.command` file compile/run the script and state in its output that the Touch Bar belongs to the companion while it is frontmost.

### Task 3: Verify runtime behavior and safety

**Files:**
- Test: `Tests/test-widget-script.sh`
- Verify: `/Applications/ChatGPT.app/Contents/Resources/app.asar`

- [x] **Step 1: Run static and compile checks**

Run the shell contract test, `swiftc -typecheck -framework AppKit scripts/codex-usage-widget.swift`, `sh -n scripts/run-codex-usage-widget.command`, and `git diff --check`.

- [x] **Step 2: Run the companion and refresh once**

Launch the compiled script, confirm the local `usage.json` timestamp and percentages update, then switch to the companion app to inspect its Touch Bar content.

- [x] **Step 3: Confirm Codex safety**

Verify the original `app.asar` SHA-256 still matches `backups/original-2026-08-31/app.asar.sha256`, confirm Hermes files were not touched, and confirm the working tree is clean.

- [x] **Step 4: Commit the implementation**

```bash
git add README.md Tests/test-widget-script.sh scripts/codex-usage-widget.swift scripts/run-codex-usage-widget.command
git commit -m "Add Codex quota Touch Bar companion"
```
