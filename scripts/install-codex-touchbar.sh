#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_root=/Applications/ChatGPT.app
resources="$app_root/Contents/Resources"
archive="$resources/app.asar"
expected_hash_file="$project_dir/backups/original-2026-08-31/app.asar.sha256"
main_path=.vite/build/main-BIHCWhv-.js

usage() {
    echo "用法：$0 --dry-run | --install" >&2
    exit 2
}

[ "$#" -eq 1 ] || usage
mode=$1
[ "$mode" = "--dry-run" ] || [ "$mode" = "--install" ] || usage

test -f "$archive"
test -f "$expected_hash_file"
test -f "$project_dir/Sources/CodexTouchBar/codex-touchbar.js"
test -f "$project_dir/Sources/CodexUsageWidget/Resources/rem.png"

current_hash=$(shasum -a 256 "$archive" | awk '{print $1}')
expected_hash=$(awk '{print $1}' "$expected_hash_file")
[ "$current_hash" = "$expected_hash" ] || {
    echo "当前 Codex 版本不是备份的原始版本，已停止，避免覆盖未知更新。" >&2
    exit 1
}

patch_dir=$(mktemp -d "${TMPDIR:-/tmp}/codex-touchbar.XXXXXX")
cleanup() {
    rm -rf "$patch_dir"
}
trap cleanup EXIT INT TERM

npx --yes @electron/asar extract "$archive" "$patch_dir/app"
test -f "$patch_dir/app/$main_path"
cp "$project_dir/Sources/CodexTouchBar/codex-touchbar.js" "$patch_dir/app/.vite/build/codex-touchbar.js"

node - "$patch_dir/app/$main_path" <<'NODE'
const fs = require("node:fs");
const file = process.argv[2];
const marker = 'require("./codex-touchbar.js");';
const source = fs.readFileSync(file, "utf8");
if (!source.includes(marker)) fs.writeFileSync(file, `${marker}\n${source}`);
NODE

npx --yes @electron/asar pack "$patch_dir/app" "$patch_dir/patched.asar" --unpack-dir node_modules
test -s "$patch_dir/patched.asar"

if [ "$mode" = "--dry-run" ]; then
    echo "dry-run: Codex Touch Bar patch assembled successfully"
    exit 0
fi

if pgrep -x "Codex" >/dev/null 2>&1 || pgrep -x "ChatGPT" >/dev/null 2>&1; then
    echo "请先完全退出 Codex/ChatGPT，再重新运行：$0 --install" >&2
    exit 1
fi

cp "$archive" "$archive.before-codex-touchbar"
cp "$patch_dir/patched.asar" "$archive"
cp "$project_dir/Sources/CodexUsageWidget/Resources/rem.png" "$resources/codex-rem.png"
if [ -d "$patch_dir/patched.asar.unpacked" ]; then
    mkdir -p "$resources/app.asar.unpacked"
    cp -R "$patch_dir/patched.asar.unpacked"/. "$resources/app.asar.unpacked/"
fi

echo "Codex Touch Bar 已安装。原始 app.asar 备份：$archive.before-codex-touchbar"
echo "如需恢复，请关闭 Codex 后运行：$project_dir/scripts/restore-codex-original.sh"
