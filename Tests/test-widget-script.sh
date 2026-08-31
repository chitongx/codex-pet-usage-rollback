#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$project_dir/scripts/codex-usage-widget.swift"
installer="$project_dir/scripts/install-codex-touchbar.sh"
touchbar_js="$project_dir/Sources/CodexTouchBar/codex-touchbar.js"
restore="$project_dir/scripts/restore-codex-original.sh"

test -f "$script"
test -f "$installer"
test -f "$touchbar_js"
test -f "$restore"
grep -q "applicationSupport" "$script"
grep -q "account/rateLimits/read" "$script"
grep -q '"read-only"' "$script"
grep -q '"app-server"' "$script"
if grep -q 'input.fileHandleForWriting.closeFile' "$script"; then
    echo "widget RPC must keep stdin open until the response arrives" >&2
    exit 1
fi
grep -q "NSTouchBar" "$script"
grep -q "NSCustomTouchBarItem" "$script"
grep -q "TouchBarHostWindow" "$script"
grep -q "makeKeyAndOrderFront" "$script"
grep -q "前台应用" "$project_dir/README.md"
grep -q "browser-window-created" "$touchbar_js"
grep -q "setTouchBar" "$touchbar_js"
grep -q '"account/rateLimits/read"' "$touchbar_js"
grep -q -- "--dry-run" "$installer"
grep -q "codex-rem.png" "$restore"

echo "widget script contract: PASS"
