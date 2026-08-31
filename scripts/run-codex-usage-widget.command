#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec swift "$project_dir/scripts/codex-usage-widget.swift"
