#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_asar="/Applications/ChatGPT.app/Contents/Resources/app.asar"
rem_asset="/Applications/ChatGPT.app/Contents/Resources/codex-rem.png"
backup_dir="$project_dir/backups/original-2026-08-31"
backup_asar="$backup_dir/app.asar"
checksum_file="$backup_dir/app.asar.sha256"

if [ ! -f "$backup_asar" ] || [ ! -f "$checksum_file" ]; then
  echo "找不到 Codex 原始备份：$backup_dir" >&2
  exit 1
fi

if ! (cd "$backup_dir" && shasum -a 256 -c "$(basename -- "$checksum_file")"); then
  echo "备份校验失败，已停止恢复。" >&2
  exit 1
fi

if [ ! -w "$app_asar" ]; then
  echo "没有写入 Codex 应用包的权限：$app_asar" >&2
  exit 1
fi

stamp=$(date +%Y%m%d-%H%M%S)
cp "$app_asar" "$app_asar.before-restore-$stamp"
cp "$backup_asar" "$app_asar"
if [ -f "$rem_asset" ]; then
  rm -f "$rem_asset"
fi

echo "已恢复 Codex 原始 app.asar。"
echo "恢复前版本备份：$app_asar.before-restore-$stamp"
