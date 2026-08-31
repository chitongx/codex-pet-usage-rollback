#!/bin/sh
set -eu

config_dir="$HOME/.config/codex-touchbar"
character_path="$config_dir/character.png"
label="com.chitongx.codex-usage-touchbar"

if [ "${1-}" = "--reset" ]; then
    if [ -e "$character_path" ]; then
        rm -f "$character_path"
        echo "已恢复内置雷姆角色。"
    else
        echo "当前没有自定义角色，仍使用内置雷姆。"
    fi
else
    if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
        echo "用法：$0 /绝对路径/角色.png" >&2
        echo "或：  $0 --reset" >&2
        exit 2
    fi
    mkdir -p "$config_dir"
    cp "$1" "$character_path"
    echo "已设置自定义角色：$character_path"
fi

uid=$(id -u)
launchctl kickstart -k "gui/$uid/$label" >/dev/null 2>&1 || true
echo "Touch Bar 助手已请求刷新；下次 Codex 聚焦时会读取新角色。"
