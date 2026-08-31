#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$project_dir/scripts/codex-usage-widget.swift"
launch_agents="$HOME/Library/LaunchAgents"
plist="$launch_agents/com.chitongx.codex-usage-touchbar.plist"
label="com.chitongx.codex-usage-touchbar"

test -f "$script"
mkdir -p "$launch_agents" "$HOME/Library/Logs"

cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/swift</string>
        <string>$script</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$project_dir</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/codex-usage-touchbar.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/codex-usage-touchbar.log</string>
</dict>
</plist>
EOF

uid=$(id -u)
launchctl bootout "gui/$uid/$label" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$uid" "$plist"
launchctl kickstart -k "gui/$uid/$label"

echo "Codex Touch Bar 独立助手已启动并设置为登录后自动运行。"
echo "仅当前台应用 bundle id 为 com.openai.codex 时显示，切换应用后自动收回。"
echo "LaunchAgent：$plist"
