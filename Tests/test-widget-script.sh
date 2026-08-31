#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$project_dir/scripts/codex-usage-widget.swift"

test -f "$script"
grep -q "https://help.openai.com/en/articles/20001478" "$script"
grep -q "5 小时剩余" "$script"
grep -q "1 周剩余" "$script"
grep -q "applicationSupport" "$script"
grep -q "account/rateLimits/read" "$script"
grep -q '"read-only"' "$script"
grep -q '"app-server"' "$script"
if grep -q 'input.fileHandleForWriting.closeFile' "$script"; then
    echo "widget RPC must keep stdin open until the response arrives" >&2
    exit 1
fi

echo "widget script contract: PASS"
