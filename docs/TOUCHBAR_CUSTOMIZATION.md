# Touch Bar 自定义说明

这个项目的 Touch Bar 由 `scripts/codex-usage-widget.swift` 独立助手提供。它不会修改 Codex.app；你可以在这个脚本中增加项目自己的 Touch Bar 项目。

## 目前的项目结构

`CodexTouchBarController` 负责创建和更新三个项目：

- `remIdentifier`：左侧角色图标。
- `fiveHourIdentifier`：5 小时窗口；Pro 账户没有该窗口时显示“Pro 无5小时限制”。
- `weeklyIdentifier`：每周剩余百分比和重置倒计时。

`CodexTouchBarAppController` 负责监听 Codex 是否为前台应用、每 60 秒读取一次额度，以及在切换应用时显示或收回 Touch Bar。

## 增加模型名或其他设置

推荐的改法是增加一个新的 `NSCustomTouchBarItem`，然后把它加入默认项目列表。例如，在 `CodexTouchBarController` 中：

```swift
static let modelIdentifier = NSTouchBarItem.Identifier("codexUsage.model")
private let modelItem = NSCustomTouchBarItem(identifier: Self.modelIdentifier)

// init() 中
modelItem.view = NSTextField(labelWithString: "模型：gpt-5-codex")
touchBar.defaultItemIdentifiers = [
    Self.remIdentifier,
    Self.modelIdentifier,
    Self.fiveHourIdentifier,
    Self.weeklyIdentifier
]
touchBar.customizationAllowedItemIdentifiers = [
    Self.remIdentifier,
    Self.modelIdentifier,
    Self.fiveHourIdentifier,
    Self.weeklyIdentifier
]

// touchBar(_:makeItemForIdentifier:) 中
case Self.modelIdentifier: modelItem
```

如果模型名来自额度响应或本地状态，给 `update(snapshot:)` 增加一个字符串参数，再更新 `modelItem.view` 即可。类似方法也可以加入：

- 当前 Codex 会话名称或工作目录。
- 最近一次刷新时间。
- “刷新”按钮或打开官方页面按钮。
- 当前活动模型、推理强度或其他本地配置。

新项目必须同时加入 `defaultItemIdentifiers`、`customizationAllowedItemIdentifiers`，并在 `makeItemForIdentifier` 的 `switch` 中返回对应 item，否则 Touch Bar 不会显示它。

## 额度数据来源

额度通过本机 Codex CLI 的只读 `app-server` 请求 `account/rateLimits/read` 获取。5 小时窗口是可选的，因为 Pro 账户可能只返回每周窗口；不要在解析时强制要求 `primary` 存在，否则会把整个响应误判为失败。

## 注意事项

Touch Bar 的系统级展示使用 macOS 私有 API `presentSystemModalTouchBar` 和 `DFRFoundation`。这是为了让项目在 Codex 聚焦时压过输入框建议栏，但 macOS 更新后可能需要重新适配。修改后运行：

```bash
Tests/test-widget-script.sh
swiftc -parse scripts/codex-usage-widget.swift
```

然后重启独立助手：

```bash
./scripts/install-codex-touchbar-helper.sh
```
