#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script="$project_dir/scripts/codex-usage-widget.swift"
installer="$project_dir/scripts/install-codex-touchbar.sh"
helper_installer="$project_dir/scripts/install-codex-touchbar-helper.sh"
character_script="$project_dir/scripts/set-character.sh"
character_docs="$project_dir/docs/CUSTOM_CHARACTER.md"
customization_docs="$project_dir/docs/TOUCHBAR_CUSTOMIZATION.md"
touchbar_js="$project_dir/Sources/CodexTouchBar/codex-touchbar.js"
restore="$project_dir/scripts/restore-codex-original.sh"

test -f "$script"
test -f "$installer"
test -f "$helper_installer"
test -f "$character_script"
test -f "$character_docs"
test -f "$customization_docs"
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
grep -q "NSWorkspace.didActivateApplicationNotification" "$script"
grep -q "presentSystemModalTouchBar" "$script"
grep -q "dismissSystemModalTouchBar" "$script"
grep -q "DFRElementSetControlStripPresenceForIdentifier" "$script"
grep -q "DFRSystemModalShowsCloseBoxWhenFrontMost" "$script"
grep -q "com.openai.codex" "$script"
grep -q "resetsAt" "$script"
grep -q "remainingUntilReset" "$script"
grep -q "remainingPercent" "$script"
grep -q "monospacedDigitSystemFont" "$script"
grep -q "ofSize: 14" "$script"
grep -q "QuotaPillView(width: 210)" "$script"
grep -q "CAGradientLayer" "$script"
grep -q "shadowOpacity" "$script"
grep -q "masksToBounds" "$script"
grep -q "NSAnimationContext" "$script"
grep -q "CABasicAnimation" "$script"
grep -q "repeatCount" "$script"
grep -q "NSImageView" "$script"
grep -q "customCharacterURL" "$script"
grep -q ".config/codex-touchbar" "$script"
grep -q "character.png" "$script"
grep -q "character.png" "$character_script"
grep -q ".config/codex-touchbar" "$character_docs"
grep -q "let fiveHour: UsageWindow?" "$script"
grep -q "Pro 无5小时限制" "$script"
grep -q "模型" "$customization_docs"
grep -q "defaultItemIdentifiers" "$customization_docs"
if grep -q "RemPetView" "$script"; then
    echo "dynamic Rem pet should be disabled for the previous layout" >&2
    exit 1
fi
if grep -q "principalItemIdentifier" "$script"; then
    echo "Touch Bar layout must keep both quota items visible" >&2
    exit 1
fi
grep -q "launchctl" "$helper_installer"
grep -q "LimitLoadToSessionType" "$helper_installer"
grep -q "RunAtLoad" "$helper_installer"
if grep -q "app.asar" "$helper_installer"; then
    echo "helper installer must not modify Codex.app" >&2
    exit 1
fi
if grep -q "NSApp.activate(ignoringOtherApps: true)" "$script"; then
    echo "helper must not steal focus from Codex" >&2
    exit 1
fi
grep -q -- "--dry-run" "$installer"
grep -q "codex-rem.png" "$restore"

echo "widget script contract: PASS"
