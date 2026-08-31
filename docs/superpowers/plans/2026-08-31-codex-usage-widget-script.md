# Codex Usage Widget Script

**Goal:** Provide a standalone macOS Swift script with a transparent Rem background that displays manually confirmed 5-hour and weekly remaining percentages.

**Safety boundary:** The script never edits `/Applications/ChatGPT.app`, reads cookies/keychain/tokens, calls private Codex endpoints, or inspects Hermes. It opens the official OpenAI usage guidance page for the user to confirm values, then stores only the two percentages locally in Application Support.

**Files:**
- Create `scripts/codex-usage-widget.swift`: standalone AppKit panel, local JSON persistence, official-page button.
- Create `scripts/run-codex-usage-widget.command`: double-click launcher.
- Use `Sources/CodexUsageWidget/Resources/rem.png`: generated transparent character asset.
- Modify `README.md`: safe usage and run instructions.

**Verification:** `swiftc -parse-as-library -typecheck scripts/codex-usage-widget.swift`, shell syntax check, and a clean git diff inspection. A separate runtime GUI launch is not performed automatically because it would open a persistent window on the user's desktop.
